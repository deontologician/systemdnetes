{ config, lib, pkgs, ... }:

let
  cfg = config.services.systemdnetes.worker;
in
{
  options.services.systemdnetes.worker = {
    enable = lib.mkEnableOption "systemdnetes worker";

    orchestratorAddress = lib.mkOption {
      type = lib.types.str;
      description = "SSH-reachable address of the orchestrator.";
    };

    orchestratorWireguardAddress = lib.mkOption {
      type = lib.types.str;
      example = "10.100.0.1";
      description = "Orchestrator's WireGuard IP (for DNS forwarding).";
    };

    orchestratorWireguardPublicKey = lib.mkOption {
      type = lib.types.str;
      description = "WireGuard public key of the orchestrator.";
    };

    orchestratorWireguardEndpoint = lib.mkOption {
      type = lib.types.str;
      description = "WireGuard endpoint (host:port) of the orchestrator.";
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
        example = "10.100.1.1/24";
        description = "Worker's WireGuard IP with prefix length.";
      };

      podCidr = lib.mkOption {
        type = lib.types.str;
        default = "10.100.0.0/16";
        description = "Full pod CIDR (routed through the overlay).";
      };
    };

    ssh.authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "SSH public keys the orchestrator uses to reach this worker.";
    };

    dns.zone = lib.mkOption {
      type = lib.types.str;
      default = "pod.systemdnetes";
      description = "DNS zone for pod name resolution.";
    };
  };

  config = lib.mkIf cfg.enable {
    # --- systemd-nspawn / machinectl ---
    systemd.targets.machines.enable = true;

    systemd.tmpfiles.rules = [
      "d /var/lib/machines 0700 root root - -"
    ];

    # --- Dedicated systemdnetes user for orchestrator SSH access ---
    users.users.systemdnetes = {
      isSystemUser = true;
      group = "systemdnetes";
      home = "/var/lib/systemdnetes";
      shell = pkgs.bashInteractive;
      openssh.authorizedKeys.keys = cfg.ssh.authorizedKeys;
    };

    users.groups.systemdnetes = { };

    # --- Passwordless sudo for container management ---
    security.sudo.extraRules = [
      {
        users = [ "systemdnetes" ];
        commands = [
          { command = "${pkgs.systemd}/bin/machinectl *"; options = [ "NOPASSWD" ]; }
          { command = "${pkgs.systemd}/bin/systemctl *"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];

    # --- dnsmasq: local DNS cache, forward pod zone to orchestrator ---
    services.dnsmasq = {
      enable = true;
      settings = {
        listen-address = "127.0.0.1";
        bind-interfaces = true;

        # Forward pod zone queries to orchestrator's WireGuard IP
        server = [ "/${cfg.dns.zone}/${cfg.orchestratorWireguardAddress}" ];

        # No DHCP
        no-dhcp-interface = [ "lo" ];
      };
    };

    # --- WireGuard interface peered with orchestrator ---
    networking.wireguard.interfaces.systemdnetes = {
      ips = [ cfg.wireguard.address ];
      listenPort = cfg.wireguard.listenPort;
      privateKeyFile = toString cfg.wireguard.privateKeyFile;

      peers = [
        {
          publicKey = cfg.orchestratorWireguardPublicKey;
          endpoint = cfg.orchestratorWireguardEndpoint;
          allowedIPs = [ cfg.wireguard.podCidr ];
          persistentKeepalive = 25;
        }
      ];
    };

    # --- Firewall: allow WireGuard port (UDP) ---
    # SSH is already handled by services.openssh
    networking.firewall.allowedUDPPorts = [ cfg.wireguard.listenPort ];

    # --- Ensure SSH is enabled ---
    services.openssh.enable = true;
  };
}
