{ config, lib, ... }:

let
  cfg = config.pod;
in
{
  options.pod = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Name of the pod. Used as the machine name in systemd-nspawn.";
    };

    resources = {
      cpu = lib.mkOption {
        type = lib.types.str;
        default = "100m";
        description = "CPU request in millicores (e.g. '100m', '1000m').";
      };

      memory = lib.mkOption {
        type = lib.types.str;
        default = "256Mi";
        description = "Memory request in mebibytes (e.g. '256Mi', '1Gi').";
      };
    };

    replicas = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Number of desired replicas for this pod.";
    };
  };

  config = {
    # Mark this system as a container so NixOS omits hardware-specific
    # configuration (bootloader, kernel modules, filesystems).
    boot.isContainer = true;

    # Default the hostname to the pod name.
    networking.hostName = lib.mkDefault cfg.name;
  };
}
