# Fix Fly Machines Deployment

## Current State (2026-02-28)

Fly app `systemdnetes` exists in `ord` region. Four machines total:

| Machine ID       | Name              | Role         | State   | Image                  | Process Group |
|------------------|-------------------|--------------|---------|------------------------|---------------|
| e823340b761578   | dawn-wave-757     | orchestrator | started | systemdnetes:latest    | app           |
| 8e795eb77314d8   | crimson-bush-1321 | orchestrator | stopped | systemdnetes:latest    | app           |
| 7815107a114128   | worker-1          | worker       | stopped | systemdnetes:worker-v2 | (none)        |
| 287dd17c0525d8   | worker-2          | worker       | stopped | systemdnetes:worker-v2 | (none)        |

SSH keypair at `/tmp/systemdnetes-key`. Private key is already set as `SSH_PRIVATE_KEY` secret on the app. Workers have `SSH_AUTHORIZED_KEYS` env var set with the public key.

## What Went Wrong

Three bugs in the Nix-built container images caused crash loops:

### 1. Missing PATH (fixed in d8cca82)

`dockerTools.buildImage` doesn't set PATH. The bash entrypoint calls `mkdir`, `chmod` etc. by name, but they live in `/bin` (via `buildEnv` + `pathsToLink`). Under `set -euo pipefail`, the first `mkdir: command not found` kills the script immediately.

**Fix**: Added `Env = [ "PATH=/bin" ];` to both container configs.

### 2. No /etc/passwd (fixed in d8cca82)

sshd on the workers refused connections with `No user exists for uid 0`. Nix containers don't have passwd by default. We initially tried `dockerTools.fakeNss` but it sets root's home to `/var/empty` which doesn't exist and causes its own problems.

**Fix**: Custom `passwdFile` derivation that creates `/etc/passwd` and `/etc/group` with root's home set to `/root`.

### 3. SSH known_hosts write failure (fixed in d8cca82)

The orchestrator's SSH client tried to write to `~/.ssh/known_hosts`. With fakeNss, `~` resolved to `/var/empty` which doesn't exist, so SSH failed with `Could not create directory '/var/empty/.ssh'` followed by `Permission denied (publickey)`.

**Fix**: Added `-o UserKnownHostsFile=/dev/null` to `sshToIO` in `Ssh/Interpreter.hs`. Combined with the existing `-o StrictHostKeyChecking=no`, this means SSH won't try to read or write known_hosts at all.

## What's Deployed vs What's Committed

The fixes are committed locally (d8cca82) but **not yet deployed**. The running orchestrator (`e823340b761578`) has the PATH and fakeNss fixes but NOT the UserKnownHostsFile or custom passwd fixes. The workers are on `worker-v2` which has PATH and fakeNss but not custom passwd.

Last health check output before stopping:
- worker-1: `ssh: connect to host ... port 22: Connection timed out` (may have been still starting)
- worker-2: `Could not create directory '/var/empty/.ssh'` + `Permission denied (publickey)` (the fakeNss home dir problem)

## Theories

### Why worker-2 got "Permission denied (publickey)"

Two possible causes layered together:
1. The known_hosts write failure might cause SSH to abort before even attempting auth (fixed by UserKnownHostsFile=/dev/null)
2. sshd on the worker might not be reading authorized_keys correctly because the root home in fakeNss is `/var/empty` and sshd looks for `~/.ssh/authorized_keys` relative to the user's home. The entrypoint writes to `/root/.ssh/authorized_keys` but sshd looks in `/var/empty/.ssh/authorized_keys`. **This is the most likely root cause.** The custom passwd with `root:/root` should fix this.

### Why worker-1 timed out

Likely just slow startup — sshd needs to generate host keys on first boot which takes a moment. The timeout might also indicate the machine was stopped/crash-looping at the time. Less concerning.

### The stopped orchestrator (crimson-bush-1321)

Hit the 10-restart limit during the initial deploy (before PATH fix). `fly deploy` later only updated the running machine. It may need to be manually destroyed and recreated, or `fly machine start` might work now that the image is fixed.

## Next Steps

### 1. Build and push fixed images

```bash
nix build .#container
nix build .#worker --out-link result-worker
nix shell nixpkgs#flyctl -c flyctl auth docker
nix shell nixpkgs#skopeo -c skopeo copy docker-archive:result docker://registry.fly.io/systemdnetes:latest
nix shell nixpkgs#skopeo -c skopeo copy docker-archive:result-worker docker://registry.fly.io/systemdnetes:worker-v3
```

### 2. Deploy orchestrator

```bash
nix shell nixpkgs#flyctl -c flyctl deploy --image registry.fly.io/systemdnetes:latest --app systemdnetes
```

This should update the running machine. The stopped one may or may not get picked up.

### 3. Update and start workers

```bash
nix shell nixpkgs#flyctl -c flyctl machine update 7815107a114128 --image registry.fly.io/systemdnetes:worker-v3 --app systemdnetes -y
nix shell nixpkgs#flyctl -c flyctl machine update 287dd17c0525d8 --image registry.fly.io/systemdnetes:worker-v3 --app systemdnetes -y
nix shell nixpkgs#flyctl -c flyctl machine start 7815107a114128 --app systemdnetes
nix shell nixpkgs#flyctl -c flyctl machine start 287dd17c0525d8 --app systemdnetes
```

### 4. Re-register workers

Node registrations are in-memory (TVar) and lost on orchestrator redeploy:

```bash
curl -X POST "https://systemdnetes.fly.dev/api/v1/nodes" \
  -H 'Content-Type: application/json' \
  -d '{"nodeName":"worker-1","nodeAddress":"fdaa:4b:a616:a7b:2ac:8fe7:548a:2"}'

curl -X POST "https://systemdnetes.fly.dev/api/v1/nodes" \
  -H 'Content-Type: application/json' \
  -d '{"nodeName":"worker-2","nodeAddress":"fdaa:4b:a616:a7b:67a:6a27:d5c9:2"}'
```

### 5. Verify

```bash
curl https://systemdnetes.fly.dev/api/v1/nodes | python3 -m json.tool
```

Should show both workers as `Healthy` with uptime/load/memory JSON.

## If It Still Fails

- **SSH still can't connect**: Try `fly ssh console -a systemdnetes` into the orchestrator and manually run `ssh -v root@<worker-ip>` to get verbose SSH debug output
- **sshd not running on workers**: Check worker logs with `fly logs -a systemdnetes` — look for sshd startup errors
- **authorized_keys path mismatch**: If custom passwd still doesn't fix it, modify the worker entrypoint to also write authorized_keys to `/var/empty/.ssh/` as a fallback, or configure sshd with `AuthorizedKeysFile /root/.ssh/authorized_keys` explicitly
- **Workers keep stopping**: They have no health check and no auto-restart config. May need `--restart always` or equivalent on `fly machine run/update`

## Longer-term Issues

- Node registrations are ephemeral — lost on every orchestrator redeploy. Need persistent storage or auto-discovery via Fly API / DNS.
- Two orchestrator machines exist because `fly deploy` defaults to `min_machines_running = 1` and creates a second for HA. Only one is needed for now — could set `min_machines_running = 0` or destroy the extra.
- Worker machines are standalone (no process group) which means `fly deploy` doesn't manage them. This is intentional per the deploy docs but worth noting.
