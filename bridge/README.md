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
- final proposal-pool and token-economics behavior

Groth proof verification is no longer mocked. The bridge now expects raw Groth16 proof coordinates and forwards them into the generated `updateTree` verifier under `groth16/verifier/`. Under the current circuit model, each token-vault leaf is the raw stored balance value rather than a key-value hash.
