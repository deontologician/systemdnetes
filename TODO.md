# systemdnetes PoC Checklist

These are high level tasks that need to be implemented.

## Core Nix Library

- [ ] Define the pod module interface (`pod.name`, `pod.resources`, `pod.replicas`, etc.)
- [ ] Write the wrapper module that injects platform config (WireGuard, store mounts) around a user-provided NixOS module
- [ ] Generate nspawn machine configs from pod definitions (nspawn settings, bind mounts for `/nix/store`, cgroup resource limits)
- [ ] Build tooling: evaluate a pod's Nix expression to extract the `pod` attrset without building the full closure
- [ ] Build tooling: `nix build` the NixOS system closure for a pod, producing a switchable system profile

## Orchestrator

- [x] Basic server exposing an API (submit pod definitions, list pods, delete pods, get status)
  - [x] REST routes: GET/POST/DELETE `/api/v1/pods`, GET `/api/v1/nodes`, GET `/healthz`
  - [x] JSON request/response via aeson
  - [ ] Request validation (reject malformed flake refs, empty names, non-positive replicas)
  - [ ] Error responses with structured JSON instead of plain text
- [x] In-memory desired state store (map of pod name -> pod definition + scheduling metadata)
  - [x] Store effect with pure (Map) and IO (TVar) interpreters
  - [ ] Pod status updates (transition Pending -> Scheduled -> Running / Failed)
- [x] Systemd effect for machinectl operations
  - [x] Effect GADT: ListContainers, GetContainer, StartContainer, StopContainer
  - [x] Pure interpreter (nested Map) for testing
  - [ ] Real IO interpreter: SSH + machinectl commands
  - [ ] Connection pooling / multiplexed SSH sessions
- [ ] Resource ledger: track CPU/memory commitments per node (not just actual usage)
- [ ] Scheduler: given a pod's resource requests and the ledger, pick a node
- [ ] Reconciliation loop:
  - [ ] Poll each node over SSH -- enumerate running nspawn containers via `machinectl list` or `systemctl`
  - [ ] Compare actual state against desired state
  - [ ] Create missing pods: push closure to node's nix store, start nspawn container, trigger `nixos-rebuild switch` inside it
  - [ ] Destroy pods that shouldn't exist
  - [ ] Detect pods that exist but aren't healthy (systemd unit failed, etc.)
- [ ] Timeout-based health: if a pod doesn't converge within N seconds, mark node unhealthy for that pod and reschedule elsewhere

## Node Setup

- [ ] Base NixOS configuration for nodes: enable nspawn, configure shared `/nix/store` bind mount, SSH access for orchestrator
- [ ] Capsule support: configure nspawn containers as capsules for ephemeral cleanup semantics
- [ ] Handle reboot recovery: orchestrator detects all capsules are gone after reboot and re-pushes

## Networking (WireGuard)

- [ ] IP allocation: orchestrator assigns a unique WireGuard IP per pod from a managed CIDR block
- [ ] Key management: generate WireGuard keypairs per pod, distribute public keys to peers
- [ ] Host-side WireGuard config: each node maintains a WireGuard interface with peers for all pods on that node
- [ ] Pod-side WireGuard config: injected into the pod's NixOS config via the wrapper module
- [ ] Peer update loop: as pods come and go, update WireGuard peer configs on affected nodes

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
