# Verifier Generation Scripts

Scripts to generate Solidity Groth16 verifier contracts from verification keys.

## Prerequisites

- Python 3.6 or higher
- Standard library modules: `json`, `sys`, `os`

## Usage

```bash
# Generate 16 leaves verifier (single contract)
python3 generate_verifier_16_leaves.py ../trusted-setup/16_leaves_vk/verification_key.json output.sol

# Generate 32 leaves verifier (single contract)  
python3 generate_verifier_32_leaves.py ../trusted-setup/32_leaves_vk/verification_key.json output.sol

# Generate 64 leaves verifier (main + IC contract)
python3 generate_verifier_64_leaves.py ../trusted-setup/64_leaves_vk/verification_key.json output_dir/

# Generate 128 leaves verifier (main + IC1 + IC2 contracts)
python3 generate_verifier_128_leaves.py ../trusted-setup/128_leaves_vk/verification_key.json output_dir/
```

## Notes

- 16/32 leaves: Single contract with inline IC arrays
- 64/128 leaves: Split into multiple contracts for size optimization
- All scripts use proper BLS12-381 field element formatting
- Generated contracts are ready for deployment