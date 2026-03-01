# scheduler/

Pure scheduling algorithm. No Polysemy, no IO.

## What it does

Assigns Pending pods to Worker nodes using a best-fit strategy without
over-committing CPU or memory.

## Key functions

- `buildNodeResources` -- build a resource ledger from current node/pod state
- `scheduleOne` -- schedule a single pod, returning updated ledger + decision
- `schedule` -- schedule all Pending pods, threading the ledger through

## Testing

```bash
cabal test systemdnetes-scheduler-test --test-show-details=streaming
```
