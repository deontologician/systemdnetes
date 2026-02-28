# test/Systemdnetes/

Test modules mirroring the library structure. Subdirectories:

- `Domain/` -- Pure domain logic property tests (no effect machinery needed)
- `Effects/` -- Effect property tests using pure interpreters
- `ApiSpec.hs` -- API routing and handler tests using the full pure interpreter stack
