# server/

Thin executable that wires up the Warp server, reconciliation loop, and effect stack.

- Port 8080 (matches Fly Machines `internal_port`)
- All application logic lives in the library packages; this just calls `runApp`
- Forks a background thread for `reconcileLoop`
- Keep this as minimal as possible
