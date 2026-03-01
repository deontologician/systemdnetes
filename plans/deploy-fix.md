# Deploy Status & Next Steps

## What was done

### Code changes (all merged to `main`, commit `f14d00b`)

1. **Switched to `buildLayeredImage`** in `flake.nix` for both `container` and `worker`.
   Each Nix store path gets its own Docker layer, so only changed layers rebuild/push.
   On subsequent deploys, only the top layer (the systemdnetes binary or NixOS config
   change) needs rebuilding — base layers (glibc, openssh, systemd, etc.) are cached.

2. **Streaming stderr in Cmd interpreter** (`src/Systemdnetes/Deploy/Cmd/Interpreter.hs`).
   Replaced `readProcessWithExitCode` with `createProcess` + `std_err = Inherit`.
   Now nix build progress, scp transfers, and fly deploy output stream in real time.

3. **Step logging in redeploy** (`src/Systemdnetes/Deploy/Redeploy.hs`).
   Added `[1/7]` through `[7/7]` prefixes so you can see which phase is running.

4. **Granular remote build logging** (`src/Systemdnetes/Deploy/Nix.hs`).
   Added log messages for "resolving store path" and "copying from remote" phases.

5. **Deleted `deploy/remote-build.sh`** and its section from `deploy/CLAUDE.md`
   (superseded by `systemdnetes-deploy`).

### Deploy progress

- Both images (orchestrator + worker) were built on auralith.vhs.city and
  copied back as `result-container` and `result-worker`.
- **Orchestrator image was successfully pushed** to `registry.fly.io/systemdnetes:latest`
  (confirmed: "Writing manifest to image destination").
- Worker image was **NOT yet pushed**.
- `fly deploy` was **NOT yet run**.
- Worker machines were **NOT yet updated**.
- Nodes were **NOT yet re-registered**.

### What went wrong

- The worktree directory (`/home/josh/Code/systemdnetes/.claude/worktrees/deploy`)
  got removed mid-session, breaking the shell. This happened after skopeo printed
  a `pwd` error, suggesting the worktree cleanup raced with the deploy.
- Earlier: `fly auth docker` token expired during the initial 16-minute build
  (caused by `buildImage`'s single-layer rsync). This is now fixed by `buildLayeredImage`.
- Earlier: 3 stale `nix build` processes on auralith were competing for resources.
  Killed the older two.

## Next steps (from main repo, inside `nix develop`)

### 1. Push worker image
```bash
fly auth docker
skopeo copy docker-archive:result-worker docker://registry.fly.io/systemdnetes:worker
```

### 2. Deploy orchestrator
```bash
fly deploy --image registry.fly.io/systemdnetes:latest
```

### 3. Update worker machines
```bash
# Get worker machine IDs
fly machine list --app systemdnetes --json | jq '.[] | select(.name | startswith("worker-")) | {id: .id, name: .name}'

# Update each worker
fly machine update <worker-1-id> --image registry.fly.io/systemdnetes:worker --app systemdnetes --yes
fly machine update <worker-2-id> --image registry.fly.io/systemdnetes:worker --app systemdnetes --yes
```

### 4. Re-register nodes (in-memory store lost on restart)
```bash
API=https://systemdnetes.fly.dev

# Get worker private IPs from fly machine list, then:
curl -X POST "$API/api/v1/nodes" -H 'Content-Type: application/json' \
  -d '{"nodeName":"worker-1","nodeAddress":"<worker-1-ip>"}'
curl -X POST "$API/api/v1/nodes" -H 'Content-Type: application/json' \
  -d '{"nodeName":"worker-2","nodeAddress":"<worker-2-ip>"}'
```

### 5. Verify
```bash
curl https://systemdnetes.fly.dev/healthz
curl https://systemdnetes.fly.dev/api/v1/nodes
```

### Alternative: just re-run the deploy tool
Since images are cached on auralith, this should be fast now:
```bash
REMOTE_HOST=auralith.vhs.city cabal run systemdnetes-deploy -- redeploy
```
The build step will be near-instant (everything cached), so the `fly auth docker`
token won't expire before the push completes.

### Known issue to fix later
The deploy tool's `authRegistry` step happens before the push, but if the build
takes long enough the token expires. Consider moving `fly auth docker` to right
before each `skopeo copy`, or refreshing the token between build and push steps.
