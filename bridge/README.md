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

The documents do not specify enough Tokamak-zkp or onchain hashing detail to implement every production path safely. The following areas are therefore still mocked on purpose:

- Tokamak proof verification
- Poseidon leaf hashing, represented here by a mock hash helper
- final proposal-pool and token-economics behavior

Groth proof verification is no longer mocked. The bridge now expects raw Groth16 proof coordinates and forwards them into the generated `updateTree` verifier under `groth16/verifier/`.

The verifier-facing public signal `leaf_index` is not accepted from user calldata. The vault reads the registered leaf index from bridge storage and injects it into the Groth16 public-input vector.
