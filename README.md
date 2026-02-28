# systemdnetes

systemdnetes is a workload orchestration system built on NixOS and systemd. The motivating observation is that systemd and NixOS already provide most of the primitives that container orchestrators like Kubernetes implement: process supervision, container isolation (nspawn), cgroup-based resource control, declarative configuration with atomic rollback, and remote host management over SSH. systemdnetes adds a scheduling and reconciliation layer on top.

This is a proof of concept. The orchestrator is written in Haskell using Polysemy effects.

## Core Concepts

### Pod definitions

A pod is defined as a Nix flake with two outputs: `pod` (a plain attribute set of scheduling metadata) and `nixosModule` (the NixOS configuration for the container).

```nix
{
  description = "my-api pod";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systemdnetes.url = "github:yourorg/systemdnetes";
  };

  outputs = { self, nixpkgs, systemdnetes, ... }: {
    pod = {
      name = "my-api";
      resources.cpu = "500m";
      resources.memory = "512Mi";
      replicas = 3;
    };

    nixosModule = { config, lib, pkgs, ... }: {
      services.my-api = {
        enable = true;
        # ...
      };

      services.redis = {
        enable = true;
        bind = "127.0.0.1";
      };

      networking.firewall.allowedTCPPorts = [ 8080 ];
    };
  };
}
```

The separation between `pod` and `nixosModule` is deliberate. `pod` is a plain attrset with no dependencies — the orchestrator can evaluate it instantly without pulling in nixpkgs or doing any builds. This is what the orchestrator reads to make scheduling decisions: resource requests, replica count, name. Validation (required fields present, resource values parse, name unique) happens at this stage cheaply.

`nixosModule` is a standard NixOS module that defines the actual workload. Since the pod is a full NixOS system, multiple services within a pod communicate over localhost and are managed by the container's own systemd instance. This replaces the Kubernetes pattern of multi-container pods with sidecars — you define multiple systemd services in a single NixOS config and get socket activation, user management, tmpfiles, firewall rules, and everything else NixOS provides.

The flake structure means pod authors pin their own dependencies via `flake.lock`. At deploy time, the orchestrator evaluates the flake's `nixosModule`, wraps it with the systemdnetes platform module (WireGuard configuration, store mounts, cgroup limits), and builds the resulting NixOS closure. The pod author's dependency pins are respected because the build happens against their flake.

### Nodes

Nodes are NixOS machines. The orchestrator does not install an agent on them. Instead it communicates with systemd over SSH using `machinectl` and `systemctl` to manage container lifecycle and query status. Resource accounting (CPU, memory) comes from systemd's cgroup tracking.

nspawn containers use systemd's capsule feature, which gives ephemeral semantics — containers clean up fully when stopped, and a node reboot produces a clean slate. The orchestrator is responsible for re-pushing pods after a reboot.

Containers share the host's `/nix/store` read-write. This is an efficiency tradeoff: it avoids duplicating the store across pods, but it means pods can observe which packages are present on the node and it requires write access for builds. A production system would likely want a read-only shared store with a separate build mechanism, possibly using filesystem-level copy-on-write (btrfs reflinks or similar).

### Orchestrator

The orchestrator is a single process with no redundancy requirement for the PoC. It:

- Exposes an API for submitting, listing, and deleting pod definitions (as flake references).
- Evaluates the `pod` output of each flake to extract scheduling metadata. Since `pod` is a plain attrset, this is fast and does not require building anything.
- Maintains an in-memory resource ledger tracking committed (not actual) CPU and memory per node, and uses it for scheduling decisions.
- Runs a reconciliation loop on a polling interval. Each iteration enumerates running containers on each node over SSH, compares against desired state, and creates or destroys containers accordingly.

Deploying a pod means evaluating the flake's `nixosModule`, composing it with the systemdnetes platform module, building the resulting NixOS closure, pushing it to the target node's Nix store, starting an nspawn container, and running `nixos-rebuild switch` inside it. Updates to a running pod are applied in-place via rebuild-switch, which takes advantage of NixOS's atomic service activation. The alternative — tearing down and replacing the container — is also viable and may be preferable for workloads that shouldn't accumulate state in `/var`.

Desired state is held in memory. If the orchestrator restarts, pod definitions must be resubmitted. Persistent state storage is deferred.

### Failure handling

If a pod does not reach its desired state within a configurable timeout, the orchestrator marks that node as unhealthy for that pod and reschedules it elsewhere. The reconciliation loop also detects containers that have disappeared (node reboot, manual intervention, nspawn crash) and recreates them.

There is no intra-pod health checking — the orchestrator monitors the outer nspawn container via systemd, not the services running inside it. Monitoring inner systemd units would require reaching into the container via `machinectl shell` or similar, which is possible but adds complexity.

### Networking

Each pod receives a unique IP via WireGuard. The orchestrator allocates IPs from a configured CIDR block, generates keypairs per pod, and manages peer distribution across nodes. WireGuard peer configuration is updated as pods are created and destroyed.

This replaces the CNI plugin layer in Kubernetes. WireGuard runs in-kernel and has a simple enough configuration model to manage programmatically. Service discovery and load balancing across replicas are not yet implemented — pods can reach each other by IP, but there is no DNS or proxy layer.

## What's Deferred

- Orchestrator state persistence
- Orchestrator HA / leader election
- Dynamic node membership (node set is fixed in config)
- Service discovery / internal DNS
- Load balancing across replicas
- Secrets management
- Nix store isolation between pods
- Nix evaluation sandboxing on the orchestrator