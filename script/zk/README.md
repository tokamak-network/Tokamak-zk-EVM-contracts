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
6. Builds a DApp-level bridge manifest:
   - one registered DApp per example group
   - one registered function entry per extracted Tokamak function
   - one `storageWrites` list per function, derived from `instance_description.json`, where each entry records:
     - the target storage address
     - the Merkle-tree index written within that storage tree
   - under the current synthesizer format, each storage write contributes four `aPubUser` words:
     - tree-index lower 16 bytes
     - tree-index upper 16 bytes
     - storage-write lower 16 bytes
     - storage-write upper 16 bytes
   - the bridge therefore derives the updated root-vector offset as `4 * storageWrites.length`
   - one channel-ready `aPubBlockHash` per processed example
7. Optionally uploads the derived DApp metadata to the deployed bridge and can create one channel per processed example.

## Helper tool

- [rkyv-to-json](./rkyv-to-json/Cargo.toml)

This small Rust utility converts `sigma_verify.rkyv` into the JSON shape expected by [generate-tokamak-verifier-key.js](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/script/generate-tokamak-verifier-key.js).

## Example usage

```bash
node script/zk/prepare-zk-artifacts.mjs \
  --install-arg "$ALCHEMY_API_KEY" \
  --dapp-manager 0xYourDAppManager \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

To create example channels after DApp registration:

```bash
node script/zk/prepare-zk-artifacts.mjs \
  --install-arg "$ALCHEMY_API_KEY" \
  --dapp-manager 0xYourDAppManager \
  --bridge-core 0xYourBridgeCore \
  --leader 0xYourChannelLeader \
  --asset 0xYourL1Token \
  --create-channels \
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

## Current assumptions

The script currently infers the token-vault storage address from each Tokamak example snapshot:

- if the example touches only one storage address, that storage is treated as the token-vault tree
- if the example touches multiple storage addresses, the single storage address that is not the entry contract is treated as the token-vault tree

That rule matches the current private-state example families, but it is still a bridge-registration assumption rather than an explicit compiler output. If future DApps expose richer storage-role metadata, this inference should be replaced with direct metadata export.
