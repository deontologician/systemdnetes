# app/ -- Executable

Thin wrapper that wires up the Warp server and runs the effect stack.

- Port 8080 (matches Fly Machines `internal_port`)
- All application logic lives in the library; this just calls `runApp`
- Keep this as minimal as possible
