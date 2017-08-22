{ pkgs, ... }:
let
  iohk-nixops = pkgs.fetchFromGitHub {
    owner = "input-output-hk";
    repo = "iohk-nixops";
    rev = "88c2b0b05c993287988255d0f32c6e13aad74f1c";
    sha256 = "03vyxxb608nds10c0vhjr1a42dqvsm8mip12dcfin0jgnwxl5ssc";
  };
  mkNode = index: {
    type = "core";
    region = "";
    static-routes = []; # list of lists of name pairs
    host = "node${toString index}.cardano";
  };
  topology = {
    nodes = {
      node1 = mkNode 1;
      node2 = mkNode 2;
      node3 = mkNode 3;
      node4 = mkNode 4;
      node5 = mkNode 5;
    };
  };
  topologyFile = pkgs.writeText "topology.json" (builtins.toJSON topology);
  genesis = (import ../default.nix { inherit pkgs; }).make-genesis;
  mkMachine = index: { config, pkgs, ... }: {
    imports = [ ../nixos/cardano-node.nix ];
    services.dnsmasq.enable = true;
    services.cardano-node = {
      enable = true;
      nodeIndex = index;
      executable = "${(import ../. {}).testjob}/bin/cardano-node-simple";
      autoStart = true;
      #initialPeers = [];
      initialKademliaPeers = [];
      genesisN = 6;
      enableP2P = true;
      type = "core";
      nodeName = "node${toString index}";
      productionMode = true;
      systemStart = 1501545900; # 2017-08-01 00:05:00
      topologyFile = "${topologyFile}";
    };
    networking.firewall.enable = false;
    networking.extraHosts = ''
      192.168.1.1 node1.cardano
      192.168.1.2 node2.cardano
      192.168.1.3 node3.cardano
      192.168.1.4 node4.cardano
      192.168.1.5 node5.cardano
    '';
    virtualisation.qemu.options = [ "-rtc base='2017-08-01'" ];
    boot.kernelParams = [ "quiet" ];
    systemd.services.cardano-node.preStart = ''
      cp -v ${genesis}/keys-testnet/rich/testnet${toString index}.key /var/lib/cardano-node/key${toString index}.sk
      ls -ltrh /var/lib/cardano-node/
    '';
  };
in {
  name = "simple-node";
  nodes = {
    node1 = mkMachine 1;
    node2 = mkMachine 2;
    node3 = mkMachine 3;
    node4 = mkMachine 4;
    node5 = mkMachine 5;
  };
  testScript = ''
    startAll
    $node1->waitForUnit("cardano-node.service");
    # TODO, implement sd_notify?
    $node1->waitForOpenPort(3000);
    $node2->waitForOpenPort(3000);
    $node3->waitForOpenPort(3000);
    $node4->waitForOpenPort(3000);
    $node5->waitForOpenPort(3000);
    #$node1->sleep(60);
    #print $node1->execute("netstat -anp ; ps aux | grep cardano ");
    $node1->sleep(600);
    print $node1->execute("journalctl -u cardano-node | grep 'Created a new block' ");
  '';
}
