# Tests

Property-based tests using Hedgehog + Tasty.

## Pattern

Every effect gets a `<Name>Spec.hs` with property tests using the **pure interpreter**:

```haskell
-- Fully pure, no IO needed
let (results, returnValue) = run . myEffectToList $ program
```

## Adding a test module

1. Create `test/Systemdnetes/Effects/<Name>Spec.hs`
2. Export a `tests :: TestTree`
3. Add to `other-modules` in `systemdnetes.cabal`
4. Import and register in `test/Main.hs`

## Generators

Write Hedgehog generators for domain types. Keep generators close to the types they generate (either in the spec file or a shared `Gen` module if reused).
