# systemdnetes

Systemd-style container orchestration built with Haskell + Polysemy effects.

## Development

Always work inside the Nix dev shell:

```bash
nix develop
```

### Commands

```bash
cabal build all                                # Build everything
cabal test all --test-show-details=streaming   # Run property tests
cabal run systemdnetes                         # Start server on :8080
ormolu --mode check $(find src app test -name '*.hs')  # Format check
ormolu --mode inplace $(find src app test -name '*.hs') # Auto-format
hlint src app test                             # Lint
nix build .#container                          # Build OCI image
```

## Architecture

### Effect discipline

- **Never use raw IO.** All side effects go through Polysemy effect algebras.
- Effect stacks are composed in `Systemdnetes.App`.
- Pure interpreters exist for every effect (used in tests).
- IO interpreters are used only at the application boundary.

### Type-first development

1. Define types (data types, effect GADTs)
2. Write properties (Hedgehog, using pure interpreters)
3. Run tests (they should fail)
4. Implement (interpreters, domain logic)

### Module structure

- **One effect per module** in `Systemdnetes.Effects.<Name>`
- Interpreters in `Systemdnetes.Effects.<Name>.Interpreter`
- Pure domain logic in `Systemdnetes.Domain.<Name>`
- Tests co-located at `test/Systemdnetes/Effects/<Name>Spec.hs`

### Adding a new effect

1. Create `src/Systemdnetes/Effects/Foo.hs` -- GADT + `makeSem`
2. Create `src/Systemdnetes/Effects/Foo/Interpreter.hs` -- pure + IO interpreters
3. Create `test/Systemdnetes/Effects/FooSpec.hs` -- property tests using pure interpreter
4. Add modules to `systemdnetes.cabal` (`exposed-modules` and `other-modules`)
5. Re-export from `src/Systemdnetes.hs`
6. Wire into `AppEffects` in `src/Systemdnetes/App.hs`
7. Register tests in `test/Main.hs`

## Deployment

Fly Machines via Nix-built OCI image. See `deploy/CLAUDE.md`.
