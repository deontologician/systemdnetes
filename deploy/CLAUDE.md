# Deployment -- Fly Machines (3-Machine Cluster)

3 Fly Machines: 1 orchestrator (API server + SSH client), 2 workers (sshd + health script).

## Architecture

- **Orchestrator**: runs the systemdnetes binary, SSHes to workers for health checks
- **Workers**: plain machines with sshd, accept SSH from orchestrator, run `systemdnetes-health` script

Communication uses Fly private networking (6PN / `fdaa::` addresses).

## Build Images

```bash
# Orchestrator (API server + openssh client)
nix build .#container
# result -> OCI tar.gz

# Worker (sshd + health script)
nix build .#worker
# result -> OCI tar.gz
```

## Deploy Orchestrator

```bash
fly auth docker

# Push orchestrator image
skopeo copy docker-archive:result docker://registry.fly.io/systemdnetes:latest
fly deploy --image registry.fly.io/systemdnetes:latest
```

## Deploy Workers

Workers are standalone machines, not managed by `fly deploy`. Use `fly machine run`:

```bash
# Build and load worker image
nix build .#worker
skopeo copy docker-archive:result docker://registry.fly.io/systemdnetes:worker

# Create worker 1
fly machine run registry.fly.io/systemdnetes:worker \
  --name worker-1 \
  --region ord \
  --app systemdnetes

# Create worker 2
fly machine run registry.fly.io/systemdnetes:worker \
  --name worker-2 \
  --region ord \
  --app systemdnetes
```

## Set Secrets

### Generate SSH keypair (one-time)

```bash
ssh-keygen -t ed25519 -f /tmp/systemdnetes-key -N ""
```

### Set orchestrator secret

```bash
fly secrets set SSH_PRIVATE_KEY="$(cat /tmp/systemdnetes-key)" --app systemdnetes
```

### Set worker secrets

Workers need the public key. Set via `fly machine update`:

```bash
PUB_KEY=$(cat /tmp/systemdnetes-key.pub)

fly machine update <worker-1-id> \
  --env SSH_AUTHORIZED_KEYS="$PUB_KEY" \
  --app systemdnetes

fly machine update <worker-2-id> \
  --env SSH_AUTHORIZED_KEYS="$PUB_KEY" \
  --app systemdnetes
```

## Register Workers

Get worker 6PN addresses from `fly machine list`, then register:

```bash
API=https://systemdnetes.fly.dev

# Register worker nodes
curl -X POST "$API/api/v1/nodes" \
  -H 'Content-Type: application/json' \
  -d '{"nodeName":"worker-1","nodeAddress":"fdaa:x:x::a"}'

curl -X POST "$API/api/v1/nodes" \
  -H 'Content-Type: application/json' \
  -d '{"nodeName":"worker-2","nodeAddress":"fdaa:x:x::b"}'
```

## Verify

```bash
# List nodes with live health status
curl "$API/api/v1/nodes"

# Check single node
curl "$API/api/v1/nodes/worker-1"

# Should show Healthy with uptime/load/memory JSON
```

## Configuration

`fly.toml` in the repo root:
- App name: `systemdnetes`
- Internal port: 8080
- Auto-stop off (orchestrator must stay running for health checks)
- Health check: `GET /healthz`

## Automated Deploy (systemdnetes-deploy)

The `systemdnetes-deploy` executable automates the full deploy pipeline.

### First-time bootstrap

```bash
cabal run systemdnetes-deploy -- bootstrap
```

This will:
1. Check prerequisites (fly, skopeo, nix)
2. Create the Fly app if needed
3. Build orchestrator and worker OCI images
4. Push images to registry.fly.io
5. Generate SSH keypair in `deploy/.ssh/`
6. Set `SSH_PRIVATE_KEY` secret on Fly
7. Deploy orchestrator via `fly deploy`
8. Poll `/healthz` until healthy
9. Create worker machines with SSH public key
10. Register workers as nodes via the API

### Redeploy (update existing)

```bash
cabal run systemdnetes-deploy -- redeploy
```

This will rebuild images, push, `fly deploy`, update worker machines,
and re-register nodes (node store is in-memory, lost on restart).

### Environment variables

- `NUM_WORKERS` -- number of worker machines (default: 2)

### SSH keys

SSH keys are stored in `deploy/.ssh/` (gitignored). Bootstrap creates
them automatically if they don't exist.

## Updating Workers

```bash
nix build .#worker
skopeo copy docker-archive:result docker://registry.fly.io/systemdnetes:worker
fly machine update <worker-id> --image registry.fly.io/systemdnetes:worker
```
