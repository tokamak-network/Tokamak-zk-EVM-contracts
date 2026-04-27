# Groth16 MPC Setup

This directory contains the Dusk-backed Groth16 setup flow for the `updateTree` circuit.

## Overview

The setup script extracts phase 1 powers for the required `updateTree` size from the published Dusk BLS12-381 response artifact and completes the circuit-specific Groth16 setup locally.

The script performs these steps:

1. Read the locally installed `tokamak-l2js` package and render `packages/groth16/circuits/src/circuit_updateTree.circom`.
2. Compile the circuit and compute the minimum required Powers of Tau power.
3. Download the published Dusk response artifact for contribution `0015`.
4. Verify the downloaded response file hash against the published report value.
5. Convert only the required phase 1 point sections into a local `snarkjs`-compatible ptau container with the Rust helper in this directory.
6. Prepare phase 2 values and generate the final `zkey` and verification key.

## Usage

```bash
node packages/groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs
```

## Outputs

The script writes the final setup artifacts to `packages/groth16/mpc-setup/crs/`:

- `circuit_final.zkey`
- `verification_key.json`
- `phase1_final_XX.ptau`
- `metadata.json`
- `zkey_provenance.json`

Temporary downloads and full-size intermediate ptau files are stored under `packages/groth16/mpc-setup/.tmp/` and are ignored by git.

## Publishing

Publish the Dusk-backed `updateTree` setup archive to Google Drive with:

```bash
node packages/groth16/mpc-setup/publish_update_tree_setup.mjs
```

Run the upload preflight before generating a new setup:

```bash
node packages/groth16/mpc-setup/publish_update_tree_setup.mjs --preflight
```

The publisher reads these environment variables:

- `GROTH16_MPC_DRIVE_FOLDER_ID`: Google Drive folder id for Groth16 MPC archives.
- `GOOGLE_DRIVE_OAUTH_CLIENT_JSON_PATH`: OAuth client JSON path shared by repository Drive upload scripts.
- `GOOGLE_DRIVE_OAUTH_TOKEN_PATH`: Optional OAuth token cache path shared by repository Drive upload scripts. If omitted, the OAuth browser flow runs without persisting a token file.

The uploaded archive name follows `tokamak-private-dapps-groth16-v{packageVersion}-{YYYYMMDDTHHMMSSZ}.zip`.
The archive contains `circuit_final.zkey`, `verification_key.json`, `metadata.json`, and `zkey_provenance.json`.
The generated `phase1_final_XX.ptau` is not included; its source and SHA-256 hash are recorded in `zkey_provenance.json`.

## Provenance Note

The final phase 1 points come from the published Dusk response artifact. The intermediate `snarkjs` ptau transcript is reconstructed locally for tooling compatibility and should not be treated as a faithful serialized transcript of the original Dusk ceremony.

## Phase 1 Derivation and Manual Verification

The Dusk response artifact is not used as a `ptau` file directly. The setup flow derives a local, `snarkjs`-compatible phase 1 file in two steps:

1. `generate_update_tree_setup_from_dusk.mjs` downloads the pinned Dusk response artifact recorded in `duskSource`, verifies its BLAKE2b-512 hash, and invokes the Rust helper:

```bash
cargo run \
  --manifest-path packages/groth16/mpc-setup/Cargo.toml \
  --release \
  -- \
  response-to-ptau \
  --response <dusk-response-file> \
  --power <powers-of-tau-power> \
  --output <raw-ptau>
```

2. The Rust helper reads the compressed Dusk G1/G2 point sections, keeps only the points required by `updateTree`, writes a `snarkjs`-compatible raw `ptau` container, and then the setup flow prepares it for phase 2:

```bash
node packages/groth16/circuits/node_modules/.bin/snarkjs \
  powersoftau prepare phase2 \
  <raw-ptau> \
  <prepared-ptau>
```

The committed `packages/groth16/mpc-setup/crs/metadata.json` records:

- `phase1Source.responseUrl`
- `phase1Source.reportUrl`
- `phase1Source.verifiedBlake2b512`
- `powersOfTauPower`

To manually verify that the committed `phase1_final_XX.ptau` was correctly derived:

1. Download the Dusk response artifact from `phase1Source.responseUrl`.
2. Hash the downloaded file with BLAKE2b-512 and compare it with `phase1Source.verifiedBlake2b512`.
3. Fetch `phase1Source.reportUrl` and confirm that the same response hash appears in the published Dusk report.
4. Run the `response-to-ptau` command above with `--power` set to `metadata.powersOfTauPower`.
5. Run `snarkjs powersoftau prepare phase2` on the reconstructed raw `ptau`.
6. Compare the prepared file's byte size and BLAKE2b-512 hash with the committed `packages/groth16/mpc-setup/crs/phase1_final_XX.ptau`.

For a local hash check:

```bash
node -e 'const crypto=require("node:crypto"),fs=require("node:fs"); const h=crypto.createHash("blake2b512"); h.update(fs.readFileSync(process.argv[1])); console.log(h.digest("hex"));' <file>
```

This verifies the pinned Dusk response file and reproducibility of the local truncated `ptau` reconstruction. It does not independently re-verify the full Dusk ceremony transcript; the published Dusk report and pinned response hash remain the external trust anchor.

## Current Status

The Dusk-backed setup flow in this directory completes successfully for the current `updateTree` circuit and produces committed setup artifacts under `packages/groth16/mpc-setup/crs/`.
