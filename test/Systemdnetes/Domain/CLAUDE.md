# test/Systemdnetes/Domain/

Property tests for pure domain logic. These tests don't use any Polysemy effects --
they exercise pure functions and JSON round-trip properties directly.

- `ClusterSpec.hs` -- Tests for `buildClusterState` (pod accounting, usage sums)
- `ResourceSpec.hs` -- Tests for `parseCpu` / `parseMemory` parsing
- `NodeSpec.hs` -- JSON round-trip properties for Node domain types
- `PodSpec.hs` -- JSON round-trip properties for Pod domain types
