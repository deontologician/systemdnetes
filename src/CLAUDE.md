# src/ -- Library Source

## Module structure

- `Systemdnetes.hs` -- Re-export module. Every public effect and interpreter gets re-exported here.
- `Systemdnetes.App` -- Effect stack composition. `AppEffects` type alias and `runApp` function.
- `Systemdnetes.Effects.<Name>` -- Effect algebra (GADT + `makeSem` + convenience wrappers).
- `Systemdnetes.Effects.<Name>.Interpreter` -- Pure and IO interpreters.
- `Systemdnetes.Domain.<Name>` -- Pure domain logic. No Polysemy, no effects.

## Effect constraints

Use `Member` constraints, not concrete effect stacks:

```haskell
-- Good: polymorphic in the stack
doSomething :: (Member Log r) => Text -> Sem r ()

-- Bad: tied to a specific stack
doSomething :: Text -> Sem AppEffects ()
```

This keeps functions testable with pure interpreters.
