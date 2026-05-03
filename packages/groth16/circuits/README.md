# Tokamak Groth16 `updateTree` Circuit

This directory contains the Circom source used by the `@tokamak-private-dapps/groth16` package. The current circuit is
not the older channel-initialization tree circuit; it is the `updateTree` circuit used by the bridge's
`channelTokenVault` accounting path.

## Current Entrypoint

The generated entrypoint is:

- `src/circuit_updateTree.circom`

That file is rendered from:

- `src/circuit_updateTree.template.circom`

The renderer reads the locally installed `tokamak-l2js` package and injects its exported `MT_DEPTH` into the circuit
entrypoint. The currently generated file records:

- `tokamak-l2js` version: `0.1.4`
- `MT_DEPTH`: `36`
- entrypoint: `updateTree(36)`

This generated file is intentionally committed because the Groth16 CRS, verifier key, and Solidity verifier must all
bind to the exact same circuit.

## What The Circuit Proves

`updateTree(N)` proves one leaf update in a binary Merkle tree of depth `N`. It does not prove a whole-tree rebuild.
The proof is designed for channel-token-vault accounting updates, where the bridge needs to verify that one storage
key's value changed consistently from one root to the next.

The public inputs are:

- `root_before`
- `root_after`
- `storage_key`
- `storage_value_before`
- `storage_value_after`

The private witness contains:

- `leaf_index`
- `proof[N]`, the sibling path from the leaf to the root

The circuit enforces three facts:

1. `leaf_index` is exactly the lower `N` bits of `storage_key`.
2. `storage_value_before` and `proof` reconstruct `root_before`.
3. `storage_value_after` and the same `proof` reconstruct `root_after`.

It also requires `storage_value_after != storage_value_before`. This prevents a nominal update proof from carrying an
unchanged value.

## Template Layout

`src/templates.circom` contains three templates:

- `deriveLeafIndexFromStorageKey(N)`: decomposes `storage_key` and constrains `leaf_index` to the lower `N` bits
- `verifyMerkleProof(N)`: reconstructs a binary Merkle root from one leaf, an index, and a sibling path
- `updateTree(N)`: combines the index derivation and before/after Merkle proof checks

All Merkle-path hashing uses `Poseidon255(2)` from `poseidon-bls12381-circom`.

## Compile

The package-local development compile command is:

```bash
npm --prefix packages/groth16/circuits run compile:dev
```

The production setup flow normally renders and compiles the circuit through:

```bash
node packages/groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs
```

Use the setup flow when `tokamak-l2js` changes `MT_DEPTH` or when the CRS/verifier artifacts need to be regenerated.
The rendered circuit, CRS metadata, verifier key, Solidity verifier, and bridge `TokamakEnvironment` constants must
move together.
