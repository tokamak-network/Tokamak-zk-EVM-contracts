# Verifier Generation Scripts

This directory only contains `updateTree` tooling.

## Files

- `generate_update_tree_verifier.py`: Generates `src/Groth16Verifier.sol` from the `updateTree` verification key.
- `generate_update_tree_fixture.py`: Converts `proof.json` and `public.json` into a Solidity fixture library for Foundry tests.

## Usage

Generate the verifier contract:

```bash
python3 groth16/verifier/scripts/generate_update_tree_verifier.py \
  groth16/trusted-setup/crs/verification_key.json \
  groth16/verifier/src/Groth16Verifier.sol
```

Generate the Foundry fixture library:

```bash
python3 groth16/verifier/scripts/generate_update_tree_fixture.py \
  groth16/prover/updateTree/proof.json \
  groth16/prover/updateTree/public.json \
  groth16/verifier/test/UpdateTreeProofFixture.sol
```

Both scripts assume the `updateTree` circuit uses the BLS12-381 verification-key format already used by this repository.
