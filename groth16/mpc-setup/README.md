# Groth16 MPC Setup

This directory contains the Dusk-backed Groth16 setup flow for the `updateTree` circuit.

## Overview

The setup script extracts phase 1 powers for the required `updateTree` size from the published Dusk BLS12-381 response artifact and completes the circuit-specific Groth16 setup locally.

The script performs these steps:

1. Resolve the latest `tokamak-l2js` version and render `groth16/circuits/src/circuit_updateTree.circom`.
2. Compile the circuit and compute the minimum required Powers of Tau power.
3. Download the published Dusk response artifact for contribution `0015`.
4. Verify the downloaded response file hash against the published report value.
5. Convert only the required phase 1 point sections into a local `snarkjs`-compatible ptau container with the Rust helper in this directory.
6. Prepare phase 2 values and generate the final `zkey` and verification key.

## Usage

```bash
node groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs
```

To verify that the committed `phase1_final_XX.ptau` is reproducibly derived from the published Dusk response artifact, run:

```bash
node groth16/mpc-setup/verify_update_tree_phase1_provenance.mjs
```

## Outputs

The script writes the final setup artifacts to `groth16/mpc-setup/crs/`:

- `circuit_final.zkey`
- `verification_key.json`
- `phase1_final_XX.ptau`
- `metadata.json`
- `zkey_provenance.json`

Temporary downloads and full-size intermediate ptau files are stored under `groth16/mpc-setup/.tmp/` and are ignored by git.

## Publishing

Publish the Dusk-backed `updateTree` setup archive to Google Drive with:

```bash
node groth16/mpc-setup/publish_update_tree_setup.mjs
```

The publisher reads these environment variables:

- `GROTH16_MPC_DRIVE_FOLDER_ID`: Google Drive folder id for Groth16 MPC archives.
- `GOOGLE_DRIVE_OAUTH_CLIENT_JSON_PATH`: OAuth client JSON path shared by repository Drive upload scripts.
- `GOOGLE_DRIVE_OAUTH_TOKEN_PATH`: OAuth token cache path shared by repository Drive upload scripts.

The uploaded archive name follows `tokamak-private-dapps-groth16-v{packageVersion}-{YYYYMMDDTHHMMSSZ}.zip`.
The archive contains `circuit_final.zkey`, `verification_key.json`, `metadata.json`, and `zkey_provenance.json`.
The generated `phase1_final_XX.ptau` is not included; its source and SHA-256 hash are recorded in `zkey_provenance.json`.

## Provenance Note

The final phase 1 points come from the published Dusk response artifact. The intermediate `snarkjs` ptau transcript is reconstructed locally for tooling compatibility and should not be treated as a faithful serialized transcript of the original Dusk ceremony.

## Current Status

The Dusk-backed setup flow in this directory completes successfully for the current `updateTree` circuit and produces committed setup artifacts under `groth16/mpc-setup/crs/`.
