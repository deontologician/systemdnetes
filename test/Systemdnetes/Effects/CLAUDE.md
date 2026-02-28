# test/Systemdnetes/Effects/

Property tests for effects using **pure interpreters**. Each spec composes the pure
interpreter for its effect, runs a program, and asserts on the results:

```haskell
let (state, result) = run $ myEffectToPure initialState $ program
```

- `FileServerSpec.hs` -- FileServer effect (static file lookup)
- `LogSpec.hs` -- Log effect (message collection and ordering)
- `NodeStoreSpec.hs` -- NodeStore effect (node CRUD operations)
- `SshSpec.hs` -- Ssh effect (command execution with canned responses)
- `StoreSpec.hs` -- Store effect (pod CRUD operations)
- `SystemdSpec.hs` -- Systemd effect (container lifecycle)
