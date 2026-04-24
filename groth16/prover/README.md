# Tokamak Groth16 Prover

This directory only supports the `updateTree` circuit.

## Layout

- `../../scripts/groth16/prover/updateTree/generateProof.mjs`: Generates a witness, proof, and public signals for the `updateTree` circuit.
- `updateTree/input_example.json`: Deterministic example input rendered from `tokamak-l2js`.
- `updateTree/proof.json`: Example proof output.
- `updateTree/public.json`: Example public-signal output.

## Hashing Rule

All leaf and Merkle-path hashing in the prover uses `tokamak-l2js.poseidonChainCompress`.

This choice is deliberate. The circuit hashes field elements directly with pairwise Poseidon calls, so the byte-oriented `poseidon(Uint8Array)` wrapper would introduce extra byte chunking and padding semantics that do not match the circuit.

## Usage

```bash
node scripts/groth16/prover/updateTree/generateProof.mjs
```

To use a custom input file:

```bash
node scripts/groth16/prover/updateTree/generateProof.mjs --input /path/to/input.json
```

To use a prebuilt proving key and skip circuit compilation:

```bash
node scripts/groth16/prover/updateTree/generateProof.mjs \
  --input /path/to/input.json \
  --skip-compile \
  --wasm /path/to/circuit_updateTree.wasm \
  --zkey /path/to/circuit_final.zkey \
  --proof-output /path/to/proof.json \
  --public-output /path/to/public.json
```

## Input Shape

The circuit input JSON must contain:

- `root_before`
- `root_after`
- `leaf_index`
- `storage_key_before`
- `storage_value_before`
- `storage_key_after`
- `storage_value_after`
- `proof`

The bundled script regenerates `input_example.json` from `tokamak-l2js` and the trusted-setup metadata before producing `proof.json` and `public.json`.
When `--skip-compile` is used, the script does not rebuild the circuit and instead uses the prebuilt proving inputs supplied on the command line. If no verification key path is supplied, the script exports one from the provided zkey before running the local proof check.
