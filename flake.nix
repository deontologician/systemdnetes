{
  description = "systemdnetes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs = { self, nixpkgs, flake-utils, flake-compat }:
    {
      nixosModules = {
        orchestrator = import ./nix/modules/orchestrator.nix;
        worker = import ./nix/modules/worker.nix;
      };
    }
    //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        haskellPackages = pkgs.haskellPackages.override {
          overrides = hself: hsuper: {
            systemdnetes = hself.callCabal2nix "systemdnetes" ./. { };
          };
        };
        systemdnetes = haskellPackages.systemdnetes;
        staticFiles = pkgs.runCommand "systemdnetes-static" { } ''
          mkdir -p $out/static
          cp ${./static}/* $out/static/
        '';

        # --- NixOS system configurations for OCI images ---

        orchestratorSystem = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/docker-image.nix"
            "${nixpkgs}/nixos/modules/profiles/minimal.nix"
            self.nixosModules.orchestrator
            ({ pkgs, lib, ... }: {
              services.systemdnetes.orchestrator = {
                enable = true;
                package = systemdnetes;
                sshKeyFile = "/run/secrets/ssh-key";
                wireguard = {
                  privateKeyFile = "/run/secrets/wireguard-key";
                  address = "10.100.0.1/24";
                };
                workers = [];
              };

              # Static files for the web server binary
              systemd.services.systemdnetes.serviceConfig.WorkingDirectory =
                "${staticFiles}";

              # Avoid /init conflict with Fly.io's init
              system.activationScripts.installInitScript = lib.mkForce "";

              system.stateVersion = "24.11";
            })
          ];
        };

        workerSystem = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/docker-image.nix"
            "${nixpkgs}/nixos/modules/profiles/minimal.nix"
            self.nixosModules.worker
            ({ pkgs, lib, ... }: {
              services.systemdnetes.worker = {
                enable = true;
                orchestratorAddress = "orchestrator";
                orchestratorWireguardAddress = "10.100.0.1";
                # Placeholder — rebuild with real key when deploying
                orchestratorWireguardPublicKey =
                  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                orchestratorWireguardEndpoint = "orchestrator:51820";
                wireguard = {
                  privateKeyFile = "/run/secrets/wireguard-key";
                  address = "10.100.1.1/24";
                };
                ssh.authorizedKeys = [];
              };

              # Inject SSH authorized keys at runtime before sshd starts.
              # The entrypoint writes env vars to /run/secrets/authorized-keys;
              # this service copies them to the NixOS-managed sshd keys path.
              systemd.services.inject-ssh-keys = {
                description = "Inject SSH authorized keys from runtime secrets";
                wantedBy = [ "sshd.service" ];
                before = [ "sshd.service" ];
                after = [ "local-fs.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                script = ''
                  if [ -f /run/secrets/authorized-keys ]; then
                    mkdir -p /etc/ssh/authorized_keys.d
                    rm -f /etc/ssh/authorized_keys.d/systemdnetes
                    cp /run/secrets/authorized-keys /etc/ssh/authorized_keys.d/systemdnetes
                    chmod 644 /etc/ssh/authorized_keys.d/systemdnetes
                  fi
                '';
              };

              # Avoid /init conflict with Fly.io's init
              system.activationScripts.installInitScript = lib.mkForce "";

              system.stateVersion = "24.11";
            })
          ];
        };

        # --- Entrypoint scripts ---
        # These run before systemd: inject runtime secrets from env vars,
        # then start NixOS init inside a PID namespace (for Fly.io compat).

        orchestratorEntrypoint = pkgs.writeShellScript "start-orchestrator" ''
          set -euo pipefail

          mkdir -p /run/secrets
          if [ -n "''${SSH_PRIVATE_KEY:-}" ]; then
            printf '%s\n' "$SSH_PRIVATE_KEY" > /run/secrets/ssh-key
            chmod 600 /run/secrets/ssh-key
          fi
          if [ -n "''${WG_PRIVATE_KEY:-}" ]; then
            printf '%s\n' "$WG_PRIVATE_KEY" > /run/secrets/wireguard-key
            chmod 600 /run/secrets/wireguard-key
          fi

          exec ${pkgs.util-linux}/bin/unshare \
            --pid --fork --mount-proc \
            ${orchestratorSystem.config.system.build.toplevel}/init
        '';

        workerEntrypoint = pkgs.writeShellScript "start-worker" ''
          set -euo pipefail

          mkdir -p /run/secrets
          if [ -n "''${SSH_AUTHORIZED_KEYS:-}" ]; then
            printf '%s\n' "$SSH_AUTHORIZED_KEYS" > /run/secrets/authorized-keys
            chmod 644 /run/secrets/authorized-keys
          fi
          if [ -n "''${WG_PRIVATE_KEY:-}" ]; then
            printf '%s\n' "$WG_PRIVATE_KEY" > /run/secrets/wireguard-key
            chmod 600 /run/secrets/wireguard-key
          fi

          exec ${pkgs.util-linux}/bin/unshare \
            --pid --fork --mount-proc \
            ${workerSystem.config.system.build.toplevel}/init
        '';

        # --- Build rootfs: NixOS system tarball + entrypoint closure ---

        mkRootfs = { name, systemCfg, entrypoint }:
          let
            tarball = systemCfg.config.system.build.tarball;
            entrypointClosure = pkgs.closureInfo {
              rootPaths = [ entrypoint ];
            };
          in
          pkgs.runCommand "${name}-rootfs" { } ''
            mkdir -p $out
            tar xf ${tarball}/tarball/nixos-system-*.tar.xz -C $out

            # Add entrypoint script and its closure to the rootfs nix store
            while IFS= read -r storePath; do
              if [ ! -e "$out$storePath" ]; then
                cp -a "$storePath" "$out$storePath"
              fi
            done < ${entrypointClosure}/store-paths
          '';

        orchestratorRootfs = mkRootfs {
          name = "orchestrator";
          systemCfg = orchestratorSystem;
          entrypoint = orchestratorEntrypoint;
        };

        workerRootfs = mkRootfs {
          name = "worker";
          systemCfg = workerSystem;
          entrypoint = workerEntrypoint;
        };
      in
      {
        packages = {
          default = systemdnetes;

          # Orchestrator: full NixOS system with systemd, API server,
          # dnsmasq, WireGuard, and SSH client
          container = pkgs.dockerTools.buildLayeredImage {
            name = "systemdnetes";
            tag = "latest";
            contents = [ orchestratorRootfs ];
            config = {
              Entrypoint = [ "${orchestratorEntrypoint}" ];
            };
          };

          # Worker: full NixOS system with systemd, sshd, dnsmasq,
          # WireGuard, and systemd-nspawn support
          worker = pkgs.dockerTools.buildLayeredImage {
            name = "systemdnetes-worker";
            tag = "latest";
            contents = [ workerRootfs ];
            config = {
              Entrypoint = [ "${workerEntrypoint}" ];
            };
          };
        };

        devShells.default = haskellPackages.shellFor {
          packages = p: [ p.systemdnetes ];
          nativeBuildInputs = [
            pkgs.cabal-install
            pkgs.haskellPackages.haskell-language-server
            pkgs.ormolu
            pkgs.hlint
            pkgs.ghcid
            pkgs.skopeo
            pkgs.flyctl
            pkgs.curl
            pkgs.openssh
            pkgs.git
            pkgs.findutils
          ];
        };
      });
}
