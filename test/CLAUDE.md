# Tests

Property-based tests using Hedgehog + Tasty.

## Effect test pattern

Every effect gets a `<Name>Spec.hs` with property tests using the **pure interpreter**:

```haskell
-- Fully pure, no IO needed
let (results, returnValue) = run . myEffectToList $ program
```

## Domain test pattern

Pure domain modules get property tests that exercise pure functions directly, with no
Polysemy effect machinery. Common patterns:

- **JSON round-trip**: Verify `decode (encode x) == Right x` using Hedgehog's `tripping`
- **Function properties**: Assert invariants on pure domain logic (e.g., `buildClusterState` accounting)

```haskell
-- JSON round-trip with tripping
prop_roundTrip = property $ do
  x <- forAll genMyType
  tripping x encode eitherDecode
```

## Adding a test module

1. Create `test/Systemdnetes/Effects/<Name>Spec.hs` or `test/Systemdnetes/Domain/<Name>Spec.hs`
2. Export a `tests :: TestTree`
3. Add to `other-modules` in `systemdnetes.cabal`
4. Import and register in `test/Main.hs`

## Generators

Write Hedgehog generators for domain types. Keep generators close to the types they generate (either in the spec file or a shared `Gen` module if reused).
