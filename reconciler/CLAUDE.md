# reconciler/

Reconciliation loop that drives the pod lifecycle.

## What it does

Periodically:
1. Lists all nodes and pods
2. Calls the scheduler for Pending pods and assigns them to nodes
3. For each pod with a node, checks container state and reconciles
4. Executes corrective actions (start/stop/rebuild)

## Key functions

- `reconcileOnce` -- one full reconciliation pass, returns actions taken
- `executeAction` -- execute a single ReconcileAction
- `reconcileLoop` -- run reconcileOnce in a loop with threadDelay

## Testing

```bash
cabal test systemdnetes-reconciler-test --test-show-details=streaming
```

Tests use `runAppPure` from the core library for full pure effect stack testing.
