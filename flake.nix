{
  description = "systemdnetes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
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
        # Minimal passwd/group with root home set to /root (not /var/empty)
        passwdFile = pkgs.runCommand "passwd" { } ''
          mkdir -p $out/etc
          echo 'root:x:0:0:root:/root:/bin/bash' > $out/etc/passwd
          echo 'root:x:0:' > $out/etc/group
          echo 'sshd:x:22:22:sshd privsep:/var/empty:/bin/false' >> $out/etc/passwd
          echo 'nobody:x:65534:65534:nobody:/nonexistent:/bin/false' >> $out/etc/passwd
          echo 'sshd:x:22:' >> $out/etc/group
          echo 'nogroup:x:65534:' >> $out/etc/group
        '';
      in
      {
        packages = {
          default = systemdnetes;

          # Orchestrator: API server + SSH client for health checks
          container = pkgs.dockerTools.buildImage {
            name = "systemdnetes";
            tag = "latest";
            copyToRoot = pkgs.buildEnv {
              name = "orchestrator-root";
              paths = [
                pkgs.openssh    # ssh client for health checks
                pkgs.coreutils  # mkdir, chmod
                pkgs.bash
                staticFiles
                passwdFile
              ];
              pathsToLink = [ "/bin" "/etc" "/static" ];
            };
            config = {
              Env = [ "PATH=/bin" ];
              Entrypoint = [
                "${pkgs.bash}/bin/bash" "-c" ''
                  set -euo pipefail
                  mkdir -p /root/.ssh && chmod 700 /root/.ssh
                  if [ -n "''${SSH_PRIVATE_KEY:-}" ]; then
                    printf '%s\n' "$SSH_PRIVATE_KEY" > /root/.ssh/id_ed25519
                    chmod 600 /root/.ssh/id_ed25519
                  fi
                  exec ${pkgs.lib.getBin systemdnetes}/bin/systemdnetes
                ''
              ];
              WorkingDir = "/";
              ExposedPorts = { "8080/tcp" = { }; };
            };
          };

          # Worker: sshd + health script (no systemdnetes binary)
          worker =
            let
              healthScript = pkgs.writeShellScriptBin "systemdnetes-health" ''
                set -euo pipefail
                UPTIME=$(cat /proc/uptime | ${pkgs.coreutils}/bin/cut -d' ' -f1)
                LOAD=$(cat /proc/loadavg | ${pkgs.coreutils}/bin/cut -d' ' -f1-3)
                MEM_TOTAL=$(${pkgs.gawk}/bin/awk '/MemTotal/ {print $2}' /proc/meminfo)
                MEM_AVAIL=$(${pkgs.gawk}/bin/awk '/MemAvailable/ {print $2}' /proc/meminfo)
                printf '{"uptime":"%s","load":"%s","memTotalKb":"%s","memAvailKb":"%s"}\n' \
                  "$UPTIME" "$LOAD" "$MEM_TOTAL" "$MEM_AVAIL"
              '';
            in
            pkgs.dockerTools.buildImage {
              name = "systemdnetes-worker";
              tag = "latest";
              copyToRoot = pkgs.buildEnv {
                name = "worker-root";
                paths = [
                  pkgs.openssh
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.bash
                  healthScript
                  passwdFile
                ];
                pathsToLink = [ "/bin" "/etc" ];
              };
              config = {
                Env = [ "PATH=/bin" ];
                Entrypoint = [
                  "${pkgs.bash}/bin/bash" "-c" ''
                    set -euo pipefail
                    mkdir -p /var/empty
                    mkdir -p /root/.ssh && chmod 700 /root/.ssh
                    if [ -n "''${SSH_AUTHORIZED_KEYS:-}" ]; then
                      printf '%s\n' "$SSH_AUTHORIZED_KEYS" > /root/.ssh/authorized_keys
                      chmod 600 /root/.ssh/authorized_keys
                    fi
                    # Generate host keys if missing
                    mkdir -p /etc/ssh
                    for t in rsa ed25519; do
                      [ -f "/etc/ssh/ssh_host_''${t}_key" ] || \
                        ${pkgs.openssh}/bin/ssh-keygen -t "$t" -f "/etc/ssh/ssh_host_''${t}_key" -N ""
                    done
                    exec ${pkgs.openssh}/bin/sshd -D -e
                  ''
                ];
                ExposedPorts = { "22/tcp" = { }; };
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
          ];
        };
      });
}
