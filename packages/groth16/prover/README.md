# Tokamak Groth16 Prover

This directory only supports the `updateTree` circuit.

## Layout

- `updateTree/generateProof.mjs`: Generates a witness, proof, and public signals for the `updateTree` circuit.
- `updateTree/input_example.json`: Deterministic example input rendered from `tokamak-l2js`.

## Hashing Rule

All leaf and Merkle-path hashing in the prover uses `tokamak-l2js.poseidonChainCompress`.

This choice is deliberate. The circuit hashes field elements directly with pairwise Poseidon calls, so the byte-oriented `poseidon(Uint8Array)` wrapper would introduce extra byte chunking and padding semantics that do not match the circuit.

## Usage

```bash
node packages/groth16/prover/updateTree/generateProof.mjs
```

To use a custom input file:

```bash
node packages/groth16/prover/updateTree/generateProof.mjs --input /path/to/input.json
```

The script requires an installed Groth16 runtime and always writes to the fixed workspace paths under `~/tokamak-private-channels/groth16/proof`. Output path flags are intentionally unsupported; use `tokamak-groth16 --extract-proof <OUTPUT_ZIP_PATH>` to export proof artifacts to a user-selected file path.

## Input Shape

The circuit input JSON must contain:

- `root_before`
- `root_after`
- `leaf_index`
- `storage_key`
- `storage_value_before`
- `storage_value_after`
- `proof`

When no `--input` is provided, the bundled script regenerates the fixed workspace `proof/input.json` from `tokamak-l2js` and the installed CRS metadata before producing `proof/proof.json` and `proof/public.json`.
