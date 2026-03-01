# compose-pod.nix -- Compose a user flake with platform config for nspawn.
#
# Deployed to /etc/systemdnetes/compose-pod.nix on worker nodes.
#
# Usage:
#   nix build --impure --no-link --print-out-paths \
#     --expr '(import /etc/systemdnetes/compose-pod.nix {
#       userFlakeRef = "github:user/my-pod";
#       podName = "my-pod";
#     }).config.system.build.toplevel'

{ userFlakeRef, podName, podIp ? null }:

let
  userFlake = builtins.getFlake userFlakeRef;
  userModule = userFlake.nixosModules.default or userFlake.nixosModule
    or (throw "Flake ${userFlakeRef} must export nixosModules.default or nixosModule");
  nixpkgs = userFlake.inputs.nixpkgs;
  lib = nixpkgs.lib;
in
  nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      userModule
      ({ lib, ... }: {
        boot.isContainer = true;
        networking.hostName = lib.mkDefault podName;
        networking.nameservers = lib.mkDefault [ "10.100.0.1" ];
        documentation.enable = false;
        nix.enable = false;
      })
    ] ++ lib.optionals (podIp != null) [
      ({ lib, ... }: {
        networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [{
          address = podIp;
          prefixLength = 24;
        }];
      })
    ];
  }
