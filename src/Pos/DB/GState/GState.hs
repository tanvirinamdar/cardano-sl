{-# LANGUAGE ScopedTypeVariables #-}

-- | Higher-level functions working with GState DB.

module Pos.DB.GState.GState
       ( prepareGStateDB
       , sanityCheckGStateDB
       , usingGStateSnapshot
       ) where

import           Universum

import           Control.Monad.Catch        (MonadMask)
import qualified Database.RocksDB           as Rocks
import           EtherCompat
import           System.Wlog                (WithLogger)

import           Pos.Context.Context        (GenesisUtxo (..))
import           Pos.Context.Functions      (genesisUtxoM)
import           Pos.Core                   (HeaderHash, Timestamp)
import           Pos.DB.Class               (MonadDB, MonadDBRead, MonadRealDB,
                                             getNodeDBs, usingReadOptions)
import           Pos.DB.GState.Balances     (getRealTotalStake)
import           Pos.DB.GState.BlockExtra   (prepareGStateBlockExtra)
import           Pos.DB.GState.Common       (prepareGStateCommon)
import           Pos.DB.Types               (DB (..), NodeDBs (..), Snapshot (..),
                                             gStateDB, usingSnapshot)
import           Pos.Ssc.GodTossing.DB      (prepareGtDB)
import           Pos.Ssc.GodTossing.Genesis (genesisCertificates)
import           Pos.Txp.DB                 (prepareGStateBalances, prepareGStateUtxo,
                                             sanityCheckBalances, sanityCheckUtxo)
import           Pos.Update.DB              (prepareGStateUS)

-- | Put missing initial data into GState DB.
prepareGStateDB
    :: forall ctx m.
       ( MonadReader ctx m
       , HasLens GenesisUtxo ctx GenesisUtxo
       , MonadDB m
       )
    => Timestamp -> HeaderHash -> m ()
prepareGStateDB systemStart initialTip = do
    prepareGStateCommon initialTip
    genesisUtxo <- genesisUtxoM
    prepareGStateUtxo genesisUtxo
    prepareGtDB genesisCertificates
    prepareGStateBalances genesisUtxo
    prepareGStateUS systemStart
    prepareGStateBlockExtra initialTip

-- | Check that GState DB is consistent.
sanityCheckGStateDB
    :: forall m.
       (MonadDBRead m, MonadMask m, WithLogger m)
    => m ()
sanityCheckGStateDB = do
    sanityCheckBalances
    sanityCheckUtxo =<< getRealTotalStake

usingGStateSnapshot :: (MonadRealDB ctx m, MonadMask m) => m a -> m a
usingGStateSnapshot action = do
    db <- _gStateDB <$> getNodeDBs
    let readOpts = rocksReadOpts db
    usingSnapshot db (\(Snapshot sn) ->
        usingReadOptions readOpts {Rocks.useSnapshot = Just sn} gStateDB action)
