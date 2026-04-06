# Groth16 MPC Setup

This directory contains the Dusk-backed Groth16 setup flow for the `updateTree` circuit.

## Overview

The setup script extracts phase 1 powers for the required `updateTree` size from the published Dusk BLS12-381 response artifact and completes the circuit-specific Groth16 setup locally.

The script performs these steps:

1. Resolve the latest `tokamak-l2js` version and render `groth16/circuits/src/circuit_updateTree.circom`.
2. Compile the circuit and compute the minimum required Powers of Tau power.
3. Download the published Dusk response artifact for contribution `0015`.
4. Verify the downloaded response file hash against the published report value.
5. Extract only the required phase 1 point sections into a local `snarkjs`-compatible ptau container.
6. Prepare phase 2 values and generate the final `zkey` and verification key.

## Usage

```bash
/opt/homebrew/opt/node@20/bin/node groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs
```

## Outputs

The script writes the final setup artifacts to `groth16/mpc-setup/updateTree/`:

- `circuit_final.zkey`
- `verification_key.json`
- `phase1_final_XX.ptau`
- `metadata.json`

Temporary downloads and full-size intermediate ptau files are stored under `groth16/mpc-setup/.tmp/` and are ignored by git.

## Provenance Note

The final phase 1 points come from the published Dusk response artifact. The intermediate `snarkjs` ptau transcript is reconstructed locally for tooling compatibility and should not be treated as a faithful serialized transcript of the original Dusk ceremony.

## Current Status

The Dusk-backed setup flow in this directory is experimental. The response download and hash verification are implemented, but the BLS12-381 point conversion path still needs additional work before the full setup reliably produces final artifacts in this repository.
