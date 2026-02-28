# Deployment -- Fly Machines

OCI container image built by Nix (no Docker required).

## Build

```bash
nix build .#container
```

This produces `result` -- a `.tar.gz` OCI image containing just the binary.

## Deploy

```bash
fly auth docker
# Option A: skopeo
skopeo copy docker-archive:result docker://registry.fly.io/systemdnetes:latest
fly deploy --image registry.fly.io/systemdnetes:latest

# Option B: local image
fly deploy --local-only --image systemdnetes:latest
```

## Configuration

`fly.toml` in the repo root:
- App name: `systemdnetes`
- Internal port: 8080
- Auto-stop/start enabled (cost savings)
- Health check: `GET /`
