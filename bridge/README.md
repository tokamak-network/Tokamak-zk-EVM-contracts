# Bridge Workspace

This folder contains a standalone bridge-contract implementation derived only from:

- `docs/zk-l2-bridge-design-notes.md`
- `docs/spec.md`

The existing bridge implementation under the repository `src` directory was intentionally not referenced or reused.

## Scope

This workspace focuses on the current design documented in the notes:

- immediate Tokamak-zkp verification
- per-channel L1 token vaults
- bridge-managed DApp metadata
- per-channel channel instances
- globally unique L2 token-vault keys
- per-channel non-collision of derived token-vault leaf indices

## Mocked Areas

The documents do not specify enough circuit-level or hashing-level detail to implement production verifiers safely. The following areas are therefore mocked on purpose:

- Groth proof verification
- Tokamak proof verification
- Poseidon leaf hashing, represented here by a mock hash helper
- exact public-input serialization and circuit-binding formats
- final proposal-pool and token-economics behavior

Any function or path that depends on these unspecified details is explicitly implemented as a mock-oriented interface or helper rather than as a fake production verifier.

