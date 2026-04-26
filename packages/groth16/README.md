# Tokamak Groth16 zkSNARK Package

This directory is the `@tokamak-private-dapps/groth16` npm package. It contains the Groth16 circuit, Dusk-backed MPC setup tooling, and proof generation helpers used by Tokamak private DApps.

## Architecture

The circuit implements a quaternary Merkle tree using Poseidon4 hashing over the BLS12-381 curve to prove storage state consistency across channel participants.

## CLI

The package exposes a standalone Groth16 runtime CLI:

```bash
tokamak-groth16 --install
tokamak-groth16 --prove packages/groth16/prover/updateTree/input_example.json
tokamak-groth16 --verify
tokamak-groth16 --extract-proof ./update-tree-proof.zip
tokamak-groth16 --doctor
```

The default workspace is:

```text
~/tokamak-private-channels/groth16/
```

`--install` downloads the latest public Groth16 MPC CRS archive from the hard-coded Groth16 CRS Drive folder, installs `circuit_final.zkey`, `verification_key.json`, `metadata.json`, and `zkey_provenance.json`, renders the `updateTree` circuit from package-local templates, and compiles the circuit WASM into the workspace.

`--prove <INPUT_JSON>` runs the complete proving flow: witness generation, proof generation, and proof verification. It writes the latest outputs under:

```text
~/tokamak-private-channels/groth16/runs/latest/
```

## Generating Proofs with snarkjs

### Prerequisites

1. Install snarkjs globally:
```bash
npm install -g snarkjs
```

2. Ensure you have the required files:
   - Circuit WASM file: `circuits/build/merkle_tree_circuit_js/merkle_tree_circuit.wasm`
   - Final proving key: `trusted-setup/merkle_tree_circuit_final.zkey`
   - Verification key: `trusted-setup/verification_key.json`

### Input Format

Create an input JSON file with your Merkle tree data:

```json
{
  "merkle_keys": ["1", "2", "3", ...],
  "storage_values": ["100", "200", "300", ...]
}
```

**Note**: All arrays must contain exactly 50 elements (padded with zeros if needed).

### Generate a Proof

1. **Calculate witness**:
```bash
snarkjs wtns calculate circuits/build/merkle_tree_circuit_js/merkle_tree_circuit.wasm input.json witness.wtns
```
This generates `witness.wtns` - a binary file containing all the intermediate values (witness) computed by the circuit for your specific input.

2. **Generate the proof**:
```bash
snarkjs groth16 prove trusted-setup/merkle_tree_circuit_final.zkey witness.wtns proof.json public.json
```

This creates:
- `proof.json`: The zero-knowledge proof
- `public.json`: Public inputs/outputs

### Verify a Proof

Verify the proof using the verification key:

```bash
snarkjs groth16 verify trusted-setup/verification_key.json public.json proof.json
```

### Example Workflow

```bash
# 1. Create input file
echo '{
  "merkle_keys": ["1", "1", "1", ..., "1"],
  "storage_values": ["1", "1", "1", ..., "1"],
}' > input.json

# 2. Calculate witness
snarkjs wtns calculate circuits/build/merkle_tree_circuit_js/merkle_tree_circuit.wasm input.json witness.wtns

# 3. Generate proof
snarkjs groth16 prove trusted-setup/merkle_tree_circuit_final.zkey witness.wtns proof.json public.json

# 4. Verify proof
snarkjs groth16 verify trusted-setup/verification_key.json public.json proof.json
```

### Proof Format

The generated proof follows the Groth16 format for BLS12-381:

```json
{
  "pi_a": ["...", "...", "1"],
  "pi_b": [["...", "..."], ["...", "..."], ["1", "0"]],
  "pi_c": ["...", "...", "1"],
  "protocol": "groth16",
  "curve": "bls12381"
}
```

### Integration with Smart Contracts

The verification key and proofs are compatible with Ethereum smart contracts using a generated
Solidity verifier. In this repository, the bridge owns the generated verifier source under
`bridge/src/generated/Groth16Verifier.sol`.
