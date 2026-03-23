# ZK Artifact Pipeline

This directory contains the integrated Tokamak/Groth artifact pipeline for bridge deployment.

## Main entrypoint

- [prepare-zk-artifacts.mjs](./prepare-zk-artifacts.mjs)

The pipeline performs the following tasks:

1. Updates `submodules/Tokamak-zk-EVM` to the latest `origin/dev`.
2. Runs `./tokamak-cli --install`.
3. Regenerates Tokamak verifier key artifacts from `sigma_verify.rkyv` and refreshes the fixed `smax` constants inside `tokamak-zkp/TokamakVerifier.sol` from `setupParams.json`.
4. Regenerates Groth16 `updateTree` trusted-setup and Solidity verifier artifacts.
5. Runs the private-state example matrix (`privateStateMint`, `privateStateTransfer`, `privateStateRedeem`), skipping examples that fail because qap-compiler capacity is insufficient.
6. Hashes Tokamak `functionInstance` and `functionPreprocess` encodings and optionally registers them on the deployed bridge.

## Helper tool

- [rkyv-to-json](./rkyv-to-json/Cargo.toml)

This small Rust utility converts `sigma_verify.rkyv` into the JSON shape expected by [generate-tokamak-verifier-key.js](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/script/generate-tokamak-verifier-key.js).

## Example usage

```bash
node script/zk/prepare-zk-artifacts.mjs \
  --install-arg "$ALCHEMY_API_KEY" \
  --bridge-admin-manager 0xYourBridgeAdminManager \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

For local validation without mutating the submodule or broadcasting transactions:

```bash
node script/zk/prepare-zk-artifacts.mjs \
  --skip-submodule-update \
  --skip-install \
  --skip-private-state \
  --skip-bridge-upload
```
