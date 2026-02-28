{ config, lib, pkgs, ... }:

let
  cfg = config.services.systemdnetes.orchestrator;

  workerOpts = {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Hostname of the worker node.";
      };
      address = lib.mkOption {
        type = lib.types.str;
        description = "SSH-reachable address of the worker.";
      };
      wireguardPublicKey = lib.mkOption {
        type = lib.types.str;
        description = "WireGuard public key of the worker.";
      };
      wireguardEndpoint = lib.mkOption {
        type = lib.types.str;
        description = "WireGuard endpoint (host:port) of the worker.";
      };
    };
  };
in
{
  options.services.systemdnetes.orchestrator = {
    enable = lib.mkEnableOption "systemdnetes orchestrator";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The systemdnetes Haskell binary package.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address the API server binds to.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port the API server listens on.";
    };

    wireguard = {
      privateKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the WireGuard private key file.";
      };

      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 51820;
        description = "WireGuard listen port.";
      };

      address = lib.mkOption {
        type = lib.types.str;
        example = "10.100.0.1/24";
        description = "Orchestrator's WireGuard IP with prefix length.";
      };

      podCidr = lib.mkOption {
        type = lib.types.str;
        default = "10.100.0.0/16";
        description = "CIDR range for pod IP allocation.";
      };
    };

    dns = {
      zone = lib.mkOption {
        type = lib.types.str;
        default = "pod.systemdnetes";
        description = "DNS zone for pod name resolution.";
      };

      hostsDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/systemdnetes/dns";
        description = "Directory where the orchestrator writes per-pod hosts files; dnsmasq reads from here.";
      };
    };

    workers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule workerOpts);
      default = [ ];
      description = "Worker nodes managed by this orchestrator.";
    };

    sshKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to SSH private key for reaching worker nodes.";
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Stub systemd service for the Haskell orchestrator binary ---
    systemd.services.systemdnetes = {
      description = "systemdnetes orchestrator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "wireguard-systemdnetes.service" ];
      wants = [ "network-online.target" ];

      environment = {
        SYSTEMDNETES_LISTEN_ADDRESS = cfg.listenAddress;
        SYSTEMDNETES_LISTEN_PORT = toString cfg.listenPort;
        SYSTEMDNETES_POD_CIDR = cfg.wireguard.podCidr;
        SYSTEMDNETES_DNS_HOSTS_DIR = toString cfg.dns.hostsDir;
        SYSTEMDNETES_SSH_KEY_FILE = toString cfg.sshKeyFile;
      };

      serviceConfig = {
        ExecStart = "${lib.getBin cfg.package}/bin/systemdnetes";
        DynamicUser = true;
        StateDirectory = "systemdnetes";
        SupplementaryGroups = [ "systemdnetes" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" ];
        Restart = "on-failure";
      };
    };

    # --- Group for shared access to DNS hostsdir ---
    users.groups.systemdnetes = { };

    # --- tmpfiles: create DNS hostsdir with group-write ---
    systemd.tmpfiles.rules = [
      "d ${toString cfg.dns.hostsDir} 0775 root systemdnetes - -"
    ];

    # --- dnsmasq: authoritative DNS for pod zone ---
    services.dnsmasq = {
      enable = true;
      settings = {
        # Only listen on loopback and the WireGuard interface
        interface = [ "lo" "systemdnetes" ];
        bind-interfaces = true;

        # Authoritative for the pod zone
        auth-zone = "${cfg.dns.zone}";
        hostsdir = toString cfg.dns.hostsDir;

        # No DHCP
        no-dhcp-interface = [ "lo" "systemdnetes" ];

        # Don't read /etc/resolv.conf — we only serve the pod zone
        no-resolv = true;

        # Don't forward unknown queries
        bogus-priv = true;
        domain-needed = true;
      };
    };

    # --- WireGuard interface for cluster overlay ---
    networking.wireguard.interfaces.systemdnetes = {
      ips = [ cfg.wireguard.address ];
      listenPort = cfg.wireguard.listenPort;
      privateKeyFile = toString cfg.wireguard.privateKeyFile;

      # Static peers: one per worker node
      peers = map (w: {
        publicKey = w.wireguardPublicKey;
        endpoint = w.wireguardEndpoint;
        allowedIPs = [ cfg.wireguard.podCidr ];
        persistentKeepalive = 25;
      }) cfg.workers;
    };

    # --- Firewall: allow API port (TCP) and WireGuard port (UDP) ---
    networking.firewall = {
      allowedTCPPorts = [ cfg.listenPort ];
      allowedUDPPorts = [ cfg.wireguard.listenPort ];
    };
  };
}
