# systemdnetes PoC Checklist

These are high level tasks that need to be implemented.

## Core Nix Library

- [x] Define the pod module interface (`pod.name`, `pod.resources`, `pod.replicas`, etc.) — `nix/modules/pod.nix`, exported as `nixosModules.pod`
- [x] Write the wrapper module that injects platform config (WireGuard, store mounts) around a user-provided NixOS module — `nix-pod-builder/nix/compose-pod.nix`
- [x] Generate nspawn machine configs from pod definitions (nspawn settings, bind mounts for `/nix/store`, cgroup resource limits) — `Domain.Nspawn` renders `.nspawn` files and machine setup scripts
- [ ] Build tooling: evaluate a pod's Nix expression to extract the `pod` attrset without building the full closure
- [x] Build tooling: `nix build` the NixOS system closure for a pod, producing a switchable system profile — `RebuildContainer` runs `nix build <flakeRef>` on the worker via SSH

## Orchestrator

- [x] Basic server exposing an API (submit pod definitions, list pods, delete pods, get status)
  - [x] REST routes: GET/POST/DELETE `/api/v1/pods`, GET `/api/v1/nodes`, GET `/healthz`
  - [x] JSON request/response via aeson
  - [x] SSE log streaming endpoint
  - [x] Cluster state aggregation endpoint (`GET /api/v1/cluster`)
  - [x] Container state in node/pod responses (`GET /api/v1/nodes/:name`, `GET /api/v1/pods/:name`)
  - [x] Container listing route (`GET /api/v1/nodes/:name/containers`)
  - [ ] Request validation (reject malformed flake refs, empty names, non-positive replicas)
  - [ ] Error responses with structured JSON instead of plain text
- [x] In-memory desired state store (map of pod name -> pod definition + scheduling metadata)
  - [x] Store effect with pure (Map) and IO (TVar) interpreters
  - [ ] Pod status lifecycle driven by reconciliation (Pending -> Scheduled -> Running / Failed)
- [x] Systemd effect for machinectl operations
  - [x] Effect GADT: ListContainers, GetContainer, StartContainer, StopContainer, RebuildContainer
  - [x] Pure interpreter (nested Map) for testing
  - [x] Real IO interpreter: SSH + machinectl commands via `Ssh`, `NodeStore`, `Log` Member dependencies
  - [ ] Connection pooling / multiplexed SSH sessions
- [x] NodeStore effect: register, list, get, remove nodes
  - [x] Pure interpreter (Map via State) for testing
  - [x] IO interpreter (TVar) for production
- [x] Ssh effect: run commands on remote nodes
  - [x] Pure interpreter (canned responses from Map) for testing
  - [x] IO interpreter (shells out to `ssh` with timeout)
  - [x] SshConfig: configurable key file (`SYSTEMDNETES_SSH_KEY_FILE`) and username (default `systemdnetes`)
- [x] Log effect: structured logging with levels (Debug/Info/Warn/Error)
  - [x] Pure interpreter (collects into list via State)
  - [x] IO interpreter (prints to stdout)
- [x] FileServer effect: serve static files
  - [x] Pure interpreter (Map-based lookup)
  - [x] IO interpreter (reads from filesystem)
- [x] DnsRegistry effect: manage per-pod DNS hosts files
  - [x] Pure interpreter (Map via State)
  - [x] IO interpreter (writes hosts files for dnsmasq inotify)
- [x] IpAllocator effect: allocate/release IPs from CIDR block
  - [x] Pure interpreter (sequential scan through CIDR)
  - [x] IO interpreter (TVar + STM, idempotent allocation)
- [x] WireGuardControl effect: keypair generation and peer management
  - [x] Pure interpreter (fake keys, in-memory peer lists)
  - [x] IO interpreter (shells out to `wg genkey`/`wg pubkey`, pushes peers via SSH)
- [x] Reconcile domain logic (`Domain/Reconcile.hs`)
  - [x] `reconcilePod` maps (desired state, actual state) to actions (Schedule/Start/Rebuild/Stop/NoAction)
  - [x] Property-tested with pure interpreters
- [x] Cluster state aggregation (`Domain/Cluster.hs`)
  - [x] `buildClusterState` groups pods under nodes, sums resource usage
  - [x] D3.js dashboard (polls `/api/v1/cluster`, renders node cards with CPU/memory bars)
- [x] Domain types and pure logic
  - [x] Resource parsing (`parseCpu`, `parseMemory` with millicores/mebibytes)
  - [x] Network/CIDR arithmetic (`IPv4`, `CidrBlock`, `parseCidr`, `cidrContains`, etc.)
  - [x] WireGuard types and peer config rendering
  - [x] DNS hosts entry rendering
  - [x] Pod, Node, PodSpec, PodState types with full JSON serialization
  - [x] Nspawn domain module: `parseMachinectlList`, `parseMachinectlState`, `renderNspawnFile`, `renderMachineSetup`
- [x] Full effect stack composition (`App.hs`)
  - [x] `AppEffects` type alias wiring all 9 effects
  - [x] `runApp` IO interpreter stack for production
  - [x] `runAppPure` pure interpreter stack for testing
- [x] Resource ledger: track CPU/memory commitments per node — `scheduler/` package, `buildNodeResources` builds ledger from current node/pod state
- [x] Scheduler: given a pod's resource requests and the ledger, pick a node — `scheduler/` package, best-fit algorithm in `Systemdnetes.Scheduler.Algo`
- [x] Reconciliation loop:
  - [x] Poll each node over SSH — enumerate running nspawn containers via `machinectl list` or `systemctl`
  - [x] Compare actual state against desired state (using existing `reconcilePod`)
  - [x] Create missing pods: push closure to node's nix store, start nspawn container, trigger `nixos-rebuild switch` inside it
  - [ ] Destroy pods that shouldn't exist
  - [ ] Detect pods that exist but aren't healthy (systemd unit failed, etc.)
- [ ] Timeout-based health: if a pod doesn't converge within N seconds, mark node unhealthy for that pod and reschedule elsewhere
- [x] Nix pod builder: compose user flakes into bootable nspawn NixOS systems — `nix-pod-builder/` package

## Deployment Tooling

- [x] Deploy effect subsystem (`Cmd` + `HttpReq` effects with pure and IO interpreters)
- [x] Bootstrap workflow: provision new Fly.io machines
- [x] Redeploy workflow: update existing machines
- [x] NixOS system build integration (`nix build` flake outputs)
- [x] Remote build script for cross-compilation
- [x] Fly.io and Skopeo helper modules

## Testing

- [x] Property-based test suite (Hedgehog + Tasty)
  - [x] 25 spec modules covering all effects, domain logic, API, and deploy subsystem
  - [x] Pure interpreters used for all effect tests (no IO in test suite)
  - [x] JSON round-trip properties for all domain types

## Node Setup

- [x] Base NixOS configuration for worker nodes (`nix/modules/worker.nix`)
  - [x] Enable nspawn (`systemd.targets.machines`, `/var/lib/machines`)
  - [x] SSH access for orchestrator (dedicated `systemdnetes` user, authorized keys)
  - [x] Passwordless sudo for `machinectl` and `systemctl`
- [x] NixOS module for orchestrator (`nix/modules/orchestrator.nix`)
  - [x] Systemd service for the Haskell binary
  - [x] Firewall rules (API port TCP, WireGuard UDP)
- [ ] Handle reboot recovery: orchestrator detects containers are gone after reboot and re-pushes

## Networking (WireGuard)

- [x] Orchestrator WireGuard interface with static worker peers (`nix/modules/orchestrator.nix`)
- [x] Worker WireGuard interface peered with orchestrator (`nix/modules/worker.nix`)
- [x] Pod CIDR configuration on both sides
- [x] DNS for pod zone: dnsmasq authoritative on orchestrator, workers forward pod zone queries
- [x] IpAllocator effect: allocate/release IPs from CIDR block (pure + IO interpreters)
- [x] WireGuardControl effect: keypair generation and peer management (pure + IO interpreters)
- [x] Wire IP allocation into pod lifecycle (effect exists, not yet called during pod creation)
- [x] Wire key management into pod lifecycle (effect exists, not yet called during pod creation)
- [ ] Pod-side WireGuard config: injected into the pod's NixOS config via the wrapper module
- [ ] Peer update loop: as pods come and go, update WireGuard peer configs on affected nodes


## UI improvements
- [x] Add node ips
- [x] Add pod ips (wireguard ips)
- [x] Show a nice animation when the pod is transitioning states
- [x] Show the orchestrator as a separate kind of node from workers
- [x] Allow a user of the UI to pick from a select list of flakes

## Deferred / Out of Scope for PoC

- [ ] Orchestrator state persistence (etcd, SQLite, etc.)
- [ ] Multi-orchestrator HA / leader election
- [ ] Dynamic node registration (fixed node set for now)
- [ ] Service discovery / internal DNS
- [ ] Load balancing across pod replicas
- [ ] Secrets/config injection system
- [ ] Nix store isolation between pods (shared read-write for now)
- [ ] Nix evaluation sandboxing on the orchestrator
- [ ] Binary cache integration for faster closure distribution
- [ ] In-place update vs. replace-and-recreate policy per pod
- [ ] Inner systemd monitoring (health checks inside the pod)
