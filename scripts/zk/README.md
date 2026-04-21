# ZK Reflection Helpers

This directory contains internal helpers that keep the repository aligned with the installed
Tokamak zk-EVM CLI runtime, the published Tokamak subcircuit library package, and the latest
published `tokamak-l2js` package.

## Internal reflection entrypoint

- [reflect-submodule-updates.mjs](./reflect-submodule-updates.mjs)

This helper is not intended to be the primary user-facing command anymore. It is called
indirectly by [deploy-bridge.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/deploy-bridge.sh)
before bridge deployment, and it can also be reused by other admin automation.

The reflection step performs the following tasks:

1. Runs the installed `@tokamak-zk-evm/cli` runtime refresh with `tokamak-cli --install`.
2. Copies the installed `sigma_verify.json` into `tokamak-zkp/TokamakVerifierKey/`.
3. Refreshes the hardcoded verifier parameters inside `tokamak-zkp/TokamakVerifier.sol` from the
   published `@tokamak-zk-evm/subcircuit-library` `setupParams.json`.
4. Regenerates Groth16 `updateTree` trusted setup and Solidity verifier artifacts.
5. Resolves the latest published `tokamak-l2js` package and records its `MT_DEPTH`.
6. Writes a reflection manifest that deployment tooling can consume when it needs updated
   bridge-facing constants.

The current reflection manifest is written to:

- `scripts/zk/artifacts/reflection.latest.json`

## DApp registration

Bridge-side DApp metadata registration is now handled by a separate admin script:

- [admin-add-dapp.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/admin-add-dapp.mjs)

That script runs `tokamak-cli --synthesize --tokamak-ch-tx` and `tokamak-cli --preprocess`
for a selected example group such as `privateStateMint`, `privateStateTransfer`, or
`privateStateRedeem`, derives the function metadata from `instance.json` and
`instance_description.json`, and registers the resulting DApp metadata on an already
deployed bridge.

## Current assumptions

The DApp-registration flow currently infers the token-vault storage address from each Tokamak example snapshot:

- if the example touches only one storage address, that storage is treated as the token-vault tree
- if the example touches multiple storage addresses, the single storage address that is not the entry contract is treated as the token-vault tree

That rule matches the current private-state example families, but it is still a bridge-registration assumption rather than an explicit compiler output. If future DApps expose richer storage-role metadata, this inference should be replaced with direct metadata export.
