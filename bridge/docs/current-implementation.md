# Current Bridge Implementation Notes

This document records implementation details that are useful for operating or reviewing the
current bridge, but that are too concrete or volatile for the abstract bridge specification or the
stable architecture notes.

## ZK Deployment Helpers

Bridge deployment and DApp registration consume the installed Tokamak zk-EVM CLI runtime, the
published Tokamak subcircuit library package, the Groth16 package, and the locally installed
`tokamak-l2js` package.

### Bridge Deployment

Bridge deployment performs its ZK refresh directly inside
[deploy-bridge.sh](../scripts/deploy-bridge.sh) instead of routing through a separate reflection
orchestrator. The deployment helper performs the following tasks before broadcasting:

1. Runs the installed `@tokamak-zk-evm/cli` runtime refresh with `tokamak-cli --install`.
2. Copies the installed `sigma_verify.json` into `bridge/src/generated/`.
3. Refreshes the hardcoded verifier parameters inside `bridge/src/verifiers/TokamakVerifier.sol` from the
   published `@tokamak-zk-evm/subcircuit-library` `setupParams.json`.
4. Regenerates or downloads the selected Groth16 `updateTree` CRS artifacts and regenerates the
   Solidity verifier.
5. Reads the locally installed `tokamak-l2js` package and records its `MT_DEPTH`.
6. Writes a bridge ZK manifest that deployment tooling can consume when it needs updated
   bridge-facing constants.

The current manifest is written into the timestamped bridge deployment directory as
`zk-reflection.latest.json`.

### DApp Registration

Bridge-side DApp metadata registration is handled by:

- [admin-add-dapp.mjs](../scripts/admin-add-dapp.mjs)

That script runs `tokamak-cli --synthesize --tokamak-ch-tx` and `tokamak-cli --preprocess` for a
selected example group such as `privateStateMint`, `privateStateTransfer`, or `privateStateRedeem`.
It derives the function metadata from `instance.json` and `instance_description.json`, then
registers the resulting DApp metadata on an already deployed bridge.

### Current Assumptions

The DApp-registration flow currently infers the token-vault storage address from each Tokamak
example snapshot:

- if the example touches only one storage address, that storage is treated as the token-vault tree
- if the example touches multiple storage addresses, the single storage address that is not the
  entry contract is treated as the token-vault tree

That rule matches the current private-state example families, but it is still a bridge-registration
assumption rather than an explicit compiler output. If future DApps expose richer storage-role
metadata, this inference should be replaced with direct metadata export.
