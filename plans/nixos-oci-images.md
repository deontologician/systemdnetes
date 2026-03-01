# Convert flake outputs to NixOS system OCI images

## Context

The current flake builds orchestrator and worker OCI images using `dockerTools.buildImage` with hand-picked packages (openssh, coreutils, bash, etc.) and custom entrypoint scripts. These are minimal containers with no systemd, no NixOS module system, and no ability to run systemd-nspawn.

The goal is to replace these with proper NixOS system images — evaluated from the existing `nixosModules.orchestrator` and `nixosModules.worker` — packaged as OCI images. This gives us systemd as init, all module-configured services (WireGuard, dnsmasq, sshd), and systemd-nspawn support on workers.

## Approach

Use `nixpkgs.lib.nixosSystem` to evaluate NixOS configurations with the docker-container profile, producing system tarballs that get packaged as OCI images. Add a `unshare --pid --fork --mount-proc` entrypoint wrapper for Fly.io compatibility (Fly runs its own init as PID 1).

## Files to modify

- **`flake.nix`** — Replace `dockerTools.buildImage` definitions with NixOS system evaluations + OCI packaging
- **`deploy/CLAUDE.md`** — Update build/deploy commands
- **`deploy/remote-build.sh`** — May need adjustment if output paths change

## Implementation

### 1. Define NixOS system configurations in `flake.nix`

For each of orchestrator and worker, evaluate a NixOS system:

```nix
workerSystem = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    # Container mode: boot.isContainer = true, builds system.build.tarball
    "${nixpkgs}/nixos/modules/virtualisation/docker-image.nix"

    # Our worker module
    self.nixosModules.worker

    # Concrete configuration
    ({ pkgs, lib, ... }: {
      services.systemdnetes.worker = {
        enable = true;
        # Runtime-injected values handled by entrypoint (see step 3)
        ssh.authorizedKeys = []; # Written at runtime from env
        orchestratorAddress = "placeholder";
        # WireGuard config...
      };

      # Avoid /init conflict with Fly.io's init
      system.activationScripts.installInitScript = lib.mkForce "";
    })
  ];
};
```

Same pattern for orchestrator with `self.nixosModules.orchestrator`.

### 2. Build OCI images from system tarballs

Extract the NixOS system tarball into a derivation, then wrap with `dockerTools.buildImage`:

```nix
workerRootfs = pkgs.runCommand "worker-rootfs" {} ''
  mkdir $out
  cd $out
  tar xf ${workerSystem.config.system.build.tarball}/tarball/nixos-system-*.tar.xz
'';

worker = pkgs.dockerTools.buildImage {
  name = "systemdnetes-worker";
  tag = "latest";
  copyToRoot = workerRootfs;
  config = {
    Entrypoint = [ "${entrypointScript}" ];
  };
};
```

### 3. Entrypoint wrapper for Fly.io

Write a shell script that:
1. Injects runtime secrets from env vars into files (SSH keys, WireGuard keys)
2. Uses `unshare --pid --fork --mount-proc` to give systemd its own PID namespace
3. Execs the NixOS init (`${toplevel}/init` or `/run/current-system/init`)

```nix
entrypoint = pkgs.writeShellScript "start-nixos" ''
  set -euo pipefail

  # Write runtime secrets from Fly.io env vars
  mkdir -p /run/secrets
  if [ -n "''${SSH_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$SSH_PRIVATE_KEY" > /run/secrets/ssh-key
    chmod 600 /run/secrets/ssh-key
  fi
  # ... similar for WireGuard keys, authorized_keys, etc.

  # Start NixOS systemd in its own PID namespace
  exec ${pkgs.util-linux}/bin/unshare \
    --pid --fork --mount-proc \
    ${workerSystem.config.system.build.toplevel}/init
'';
```

### 4. Handle runtime configuration

The NixOS modules currently expect values at evaluation time. For the OCI image:

- **Hardcode** stable values: listen ports, CIDR ranges, DNS zone, package refs
- **Inject at runtime** via entrypoint: SSH keys, WireGuard private keys, authorized_keys
- **Module adjustments needed**: Point `sshKeyFile` / `wireguard.privateKeyFile` to `/run/secrets/...` paths (which the entrypoint populates from env vars before systemd starts)
- **Worker list / WireGuard peers**: Static per build for now (rebuild to add workers). Dynamic peer management can come later.

### 5. Update deploy docs

Update `deploy/CLAUDE.md` commands — the build outputs and deploy flow remain the same shape (`nix build .#container` / `nix build .#worker` → `skopeo copy` → `fly deploy`), just the images are now full NixOS systems.

### 6. Remove dead code

Delete from `flake.nix`: the `passwdFile`, `staticFiles`, `healthScript` derivations and the old `dockerTools.buildImage` blocks. These are all superseded by the NixOS modules.

## Open questions to validate during implementation

1. **Image size**: A NixOS system closure will be significantly larger than the current minimal images. We should check the size and consider using `profiles/minimal.nix` in the NixOS eval to keep it manageable.
2. **`unshare` + systemd**: Need to verify systemd boots cleanly inside a PID namespace on Fly.io's Firecracker VMs. May need `--mount` flag too.
3. **Capabilities**: Workers need `CAP_NET_ADMIN` for WireGuard and potentially additional privileges for systemd-nspawn. Need to verify Fly.io grants these (or if `fly machine run` flags are needed).
4. **Static files**: The orchestrator currently bundles `./static/*`. The NixOS module's systemd service needs the static files available to the binary — ensure the package includes them.

## Verification

1. `nix build .#container` and `nix build .#worker` succeed
2. Load image locally: `docker load < result` (or `skopeo copy`)
3. Run locally with Docker to verify systemd boots: `docker run --privileged systemdnetes-worker`
4. Check that systemd services are active: `systemctl status` shows sshd, dnsmasq, WireGuard
5. Deploy to Fly.io and verify health checks work: `curl https://systemdnetes.fly.dev/healthz`
