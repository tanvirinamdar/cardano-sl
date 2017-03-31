module Explorer.Api.Http where

import Prelude
import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Error.Class (throwError)
import Data.Argonaut.Core (Json)
import Data.Either (Either(..), either)
import Data.Generic (class Generic, gShow)
import Data.HTTP.Method (Method(..))
import Data.Lens ((^.))
import Data.Maybe (Maybe(..))
import Explorer.Api.Helper (decodeResult)
import Explorer.Api.Types (EndpointError(..), Endpoint)
import Explorer.Types.State (CBlockEntries, CTxEntries, CTxBriefs)
import Network.HTTP.Affjax (AJAX, AffjaxRequest, affjax, defaultRequest)
import Network.HTTP.Affjax.Request (class Requestable)
import Network.HTTP.StatusCode (StatusCode(..))
import Pos.Core.Types (EpochIndex)
import Pos.Explorer.Web.ClientTypes (CAddress(..), CAddressSummary, CBlockSummary, CHash(..), CTxId, CTxSummary)
import Pos.Explorer.Web.Lenses.ClientTypes (_CHash, _CTxId)

endpointPrefix :: String
-- endpointPrefix = "http://localhost:8100/api/"
endpointPrefix = "/api/"

-- result helper

decodeResponse :: forall a eff. Generic a => {response :: Json | eff} -> Either Error a
decodeResponse = decodeResult <<< _.response

request :: forall a r eff. (Generic a, Requestable r) => AffjaxRequest r ->
    Endpoint -> Aff (ajax :: AJAX | eff) a
request req endpoint = do
    result <- affjax $ req { url = endpointPrefix <> endpoint }
    when (isHttpError result.status) $
        throwError <<< error <<< show $ HTTPStatusError result
    either throwError pure $ decodeResponse result
    where
      isHttpError (StatusCode c) = c >= 400

get :: forall eff a. Generic a => Endpoint -> Aff (ajax :: AJAX | eff) a
get e = request defaultRequest e

post :: forall eff a. Generic a => Endpoint -> Aff (ajax :: AJAX | eff) a
post = request $ defaultRequest { method = Left POST }

-- api

-- blocks
fetchLatestBlocks :: forall eff. Aff (ajax::AJAX | eff) CBlockEntries
fetchLatestBlocks = get "blocks/last"

fetchBlockSummary :: forall eff. CHash -> Aff (ajax::AJAX | eff) CBlockSummary
fetchBlockSummary (CHash hash) = get $ "blocks/summary/" <> hash

fetchBlockTxs :: forall eff. CHash -> Aff (ajax::AJAX | eff) CTxBriefs
fetchBlockTxs (CHash hash) = get $ "blocks/txs/" <> hash

-- txs
fetchLatestTxs :: forall eff. Aff (ajax::AJAX | eff) CTxEntries
fetchLatestTxs = get "txs/last"

fetchTxSummary :: forall eff. CTxId -> Aff (ajax::AJAX | eff) CTxSummary
fetchTxSummary id = get $ "txs/summary/" <> id ^. (_CTxId <<< _CHash)

-- addresses
fetchAddressSummary :: forall eff. CAddress -> Aff (ajax::AJAX | eff) CAddressSummary
fetchAddressSummary (CAddress address) = get $ "addresses/summary/" <> address

-- search by epoch / slot
searchEpoch :: forall eff. EpochIndex -> Maybe Int -> Aff (ajax::AJAX | eff) CBlockEntries
searchEpoch epoch mSlot = get $ "search/epoch/" <> gShow epoch <> slotQuery mSlot
    where
        slotQuery Nothing = ""
        slotQuery (Just s) = "?slot=" <> show s
