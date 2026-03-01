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

## Git workflow

Split work into small, self-contained commits. Each commit must build successfully on its own (`cabal build all` must pass). When a commit adds source files, the cabal file update goes in the same commit so the build never breaks.

Typical split for a new effect:

1. Library changes (effect algebra, interpreter, cabal `exposed-modules`, re-export)
2. Tests (spec module, cabal `other-modules`, test runner registration)
3. Wiring (App.hs stack update, any executable changes)

Write descriptive commit messages: summary line says *what*, body says *why* and lists key details.

## Deployment

Fly Machines via Nix-built OCI image. See `deploy/CLAUDE.md`.

## Task tracking

Keep `TODO.md` up to date with any plans you are working on. When entering plan mode, link to the plan file from `TODO.md` under a `## Current Plan` section and keep the status in sync as work progresses. Mark items complete in `TODO.md` as they are finished, and remove the current plan link once the plan is fully implemented.

## CLAUDE doc structure
Add a CLAUDE.md in each directory explaining at a high level what the files contain to help with navigation. Additionally, if there are operational instructions necessary in that directory (like a tool or cli invocations needed) explain them there with examples.
