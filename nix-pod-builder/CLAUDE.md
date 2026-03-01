# nix-pod-builder/

Nix wrapper that composes user flakes into bootable nspawn NixOS systems.

## What it does

- `nix/compose-pod.nix` -- Nix expression that takes a user flake ref and pod name,
  composes it with platform config to produce a bootable nspawn NixOS system
- `Command.hs` -- Pure Haskell functions to generate the `nix build` command for SSH

## Usage

The compose-pod.nix file is deployed to `/etc/systemdnetes/compose-pod.nix` on worker
nodes. The Haskell `buildPodCommand` generates the SSH command that invokes it.

## Testing

```bash
cabal test systemdnetes-nix-pod-builder-test --test-show-details=streaming
```
