# Tokamak Groth16 zkSNARK Package

This directory is the `@tokamak-private-dapps/groth16` npm package. It contains the Groth16 circuit, Dusk-backed MPC setup tooling, and proof generation helpers used by Tokamak private DApps.

## Architecture

The package currently supports the `updateTree` circuit. The circuit proves one `channelTokenVault` leaf update against
the fixed-depth Tokamak managed-storage tree used by the bridge. The generated entrypoint renders
`updateTree(MT_DEPTH)` from the locally installed `tokamak-l2js` package; the current generated depth is `36`.

The proof binds five public values:

- `root_before`
- `root_after`
- `storage_key`
- `storage_value_before`
- `storage_value_after`

The witness provides the derived leaf index and Merkle sibling path. The circuit constrains the leaf index to the lower
`MT_DEPTH` bits of `storage_key`, verifies the before-root path with `storage_value_before`, verifies the after-root path
with `storage_value_after`, and requires the before and after values to differ. This lets bridge contracts verify
channel-token-vault accounting updates without storing the full tree on-chain.

## CLI

The package exposes a standalone Groth16 runtime CLI:

```bash
tokamak-groth16 --install
tokamak-groth16 --prove packages/groth16/prover/updateTree/input_example.json
tokamak-groth16 --verify
tokamak-groth16 --extract-proof ./update-tree-proof.zip
tokamak-groth16 --doctor
```

The fixed workspace is:

```text
~/tokamak-private-channels/groth16/
```

`--install` downloads the latest public Groth16 MPC CRS archive from the hard-coded Groth16 CRS Drive folder, installs `circuit_final.zkey`, `verification_key.json`, `metadata.json`, and `zkey_provenance.json`, renders the `updateTree` circuit from package-local templates, and compiles the circuit WASM/R1CS into the workspace build directory.

`--install --trusted-setup` does not copy any package-local CRS. It renders and compiles the workspace circuit, runs a local snarkjs powers-of-tau and Groth16 setup, and writes the generated CRS only under the fixed workspace:

```text
~/tokamak-private-channels/groth16/crs/circuit_final.zkey
~/tokamak-private-channels/groth16/crs/verification_key.json
~/tokamak-private-channels/groth16/crs/metadata.json
~/tokamak-private-channels/groth16/crs/zkey_provenance.json
```

`--install --docker` is supported on Linux hosts and Windows hosts with Docker Desktop. It builds the packaged Ubuntu 22 Docker image, mounts the fixed Groth16 workspace into the container, runs the install flow there, and stores Docker bootstrap files under:

```text
~/tokamak-private-channels/groth16/docker/
```

After a Docker install, `--prove` and `--verify` run snarkjs through the saved Docker bootstrap when Docker is available. Linux hosts can fall back to native snarkjs when Docker is not running. Windows hosts require Docker Desktop because native Groth16 runtime execution is not supported there. macOS hosts should use the native install path.

`--prove <INPUT_JSON>` runs the proving flow only: witness generation, proof generation, and public signal generation. It always writes proof artifacts to fixed workspace paths:

```text
~/tokamak-private-channels/groth16/proof/input.json
~/tokamak-private-channels/groth16/proof/proof.json
~/tokamak-private-channels/groth16/proof/public.json
~/tokamak-private-channels/groth16/proof/proof-manifest.json
```

`--verify [<PROOF_ZIP|DIR>]` verifies an existing `proof.json` and `public.json` against the installed workspace verification key. Running `--prove` does not verify the proof.

`--extract-proof <OUTPUT_ZIP_PATH>` is the only Groth16 CLI command that lets the user choose an output file path. It exports the fixed workspace proof artifacts into the requested zip file.

## Generating Proofs with snarkjs

### Prerequisites

1. Install snarkjs globally:
```bash
npm install -g snarkjs
```

2. Run `tokamak-groth16 --install` or `tokamak-groth16 --install --trusted-setup` so the workspace contains:
   - Circuit WASM file: `~/tokamak-private-channels/groth16/build/circuit_updateTree.wasm`
   - Final proving key: `~/tokamak-private-channels/groth16/crs/circuit_final.zkey`
   - Verification key: `~/tokamak-private-channels/groth16/crs/verification_key.json`

### Input Format

Create an input JSON file for one leaf update:

```json
{
  "root_before": "1",
  "root_after": "2",
  "leaf_index": "3",
  "storage_key": "3",
  "storage_value_before": "100",
  "storage_value_after": "200",
  "proof": ["<36 sibling values>"]
}
```

The `proof` array must contain one sibling value per tree level. For the current generated `MT_DEPTH = 36` circuit, it
therefore contains `36` entries. For a runnable local example, use
`packages/groth16/prover/updateTree/input_example.json`; it is generated from the installed `tokamak-l2js` tree helper
and matches the current circuit depth.

### Generate a Proof

1. **Calculate witness**:
```bash
snarkjs wtns calculate ~/tokamak-private-channels/groth16/build/circuit_updateTree.wasm input.json witness.wtns
```
This generates `witness.wtns` - a binary file containing all the intermediate values (witness) computed by the circuit for your specific input.

2. **Generate the proof**:
```bash
snarkjs groth16 prove ~/tokamak-private-channels/groth16/crs/circuit_final.zkey witness.wtns proof.json public.json
```

This creates:
- `proof.json`: The zero-knowledge proof
- `public.json`: Public inputs/outputs

### Verify a Proof

Verify the proof using the verification key:

```bash
snarkjs groth16 verify ~/tokamak-private-channels/groth16/crs/verification_key.json public.json proof.json
```

### Example Workflow

```bash
# 1. Create input file from the bundled deterministic example
cp packages/groth16/prover/updateTree/input_example.json input.json

# 2. Calculate witness
snarkjs wtns calculate ~/tokamak-private-channels/groth16/build/circuit_updateTree.wasm input.json witness.wtns

# 3. Generate proof
snarkjs groth16 prove ~/tokamak-private-channels/groth16/crs/circuit_final.zkey witness.wtns proof.json public.json

# 4. Verify proof
snarkjs groth16 verify ~/tokamak-private-channels/groth16/crs/verification_key.json public.json proof.json
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
