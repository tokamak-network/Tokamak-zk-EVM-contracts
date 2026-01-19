# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the BLS12-Poseidon-Merkle-tree-Groth16 package, a production-ready Groth16 zero-knowledge SNARK implementation for Tokamak's storage proof verification system. The project implements a quaternary Merkle tree using Poseidon4 hashing over the BLS12-381 curve to prove storage state consistency across channel participants.

## Development Commands

### Circuit Development

```bash
# Navigate to circuits directory
cd circuits

# Compile circuit (N5 configuration for 1024 leaves)
npm run compile

# Run circuit tests
npm test

# Test specific circuit functionality
node test/circuit_test.js
```

### Proof Generation

```bash
# Navigate to specific leaf configuration directory
cd prover/64_leaves_groth  # or 16_leaves_groth, 32_leaves_groth, 128_leaves_groth

# Generate proof using existing script
node generateProof.js

# Generate witness manually with snarkjs
snarkjs wtns calculate ../../circuits/build/circuit_N6_js/circuit_N6.wasm input.json witness.wtns

# Generate proof manually with snarkjs
snarkjs groth16 prove ../../trusted-setup/64_leaves_vk/circuit_final.zkey witness.wtns proof.json public.json

# Verify proof
snarkjs groth16 verify ../../trusted-setup/64_leaves_vk/verification_key.json public.json proof.json
```

### Verifier Contract Development

```bash
# Navigate to verifier directory
cd verifier

# Build contracts
forge build

# Run all verifier tests
forge test

# Run specific test suite
forge test --match-path test/64_leaves/Groth16Verifier64LeavesTest.t.sol

# Run with verbose output
forge test -vv

# Deploy verifier contract (example)
forge create src/Groth16Verifier64Leaves.sol:Groth16Verifier64Leaves --constructor-args <IC_CONTRACT_ADDRESS>
```

## Architecture Overview

The project consists of four main components that work together to provide complete zkSNARK functionality:

### 1. Circuits (`circuits/`)
- **Parameterized Circom circuits** with configurable tree depth N (supports 4^N leaves)
- **Current configurations**: N4 (256 leaves), N5 (1024 leaves), N6 (4096 leaves), N7 (16384 leaves), N8 (65536 leaves)
- **Main template**: `TokamakStorageMerkleProof(N)` - computes Merkle root from split L2 public key coordinates
- **Core dependency**: `poseidon-bls12381-circom` for BLS12-381 optimized Poseidon hashing
- **Input format**: Split L2 public keys (x,y coordinates), storage slots, and values (4^N elements each)

### 2. Prover Scripts (`prover/`)
- **Organized by leaf count**: Separate directories for 16, 32, 64, 128 leaf configurations
- **Automated proof generation**: `generateProof.js` scripts that handle witness calculation and proof generation
- **Input examples**: `input_example.json` files showing proper data format for each configuration
- **snarkjs integration**: Uses snarkjs for witness calculation and Groth16 proof generation

### 3. Trusted Setup (`trusted-setup/`)
- **Powers of Tau ceremonies**: Pre-computed `pow_of_tau/` files for different constraint sizes (pow15-pow20)
- **Circuit-specific keys**: Separate verification keys and proving keys for each leaf configuration
- **Key files**: `circuit_final.zkey` (proving key) and `verification_key.json` for each configuration

### 4. Verifier Contracts (`verifier/`)
- **Solidity verifiers**: BLS12-381 compatible Groth16 verifiers for each leaf configuration
- **Foundry test suite**: Comprehensive tests for each verifier contract
- **Split verification key storage**: Constants split into PART1/PART2 for BLS12-381 48-byte field elements
- **IC (Input Commitment) contracts**: Separate contracts storing large IC arrays for gas optimization

## Circuit Configuration Guide

The circuits are parameterized by depth N, which determines capacity:

- **N=4**: 256 leaves (4^4) - Current production configuration
- **N=5**: 1024 leaves (4^5) - Default compile target
- **N=6**: 4096 leaves (4^6) - Large channels
- **N=7**: 16384 leaves (4^7) - Extra large channels  
- **N=8**: 65536 leaves (4^8) - Maximum supported

To change configuration:
1. Modify compile script in `circuits/package.json` to target desired `circuit_N*.circom`
2. Ensure corresponding trusted setup files exist in `trusted-setup/`
3. Use matching prover scripts in appropriate `*_leaves_groth/` directory

## Key Implementation Details

### Circuit Input Format
Each circuit expects exactly 4^N elements for each input array:
- `L2PublicKeys_x[4^N]`: X coordinates of L2 public keys  
- `L2PublicKeys_y[4^N]`: Y coordinates of L2 public keys
- `storage_slots[4^N]`: Storage slot identifiers for each leaf
- `storage_values[4^N]`: Storage values for each leaf

### Cryptographic Parameters
- **Curve**: BLS12-381 (254-bit scalar field)
- **Hash function**: Poseidon with 4 inputs, 128-bit security
- **Merkle tree**: Quaternary (4-way branching)
- **Privacy**: Merkle keys computed internally from public key coordinates and slots

### Performance Characteristics
- **Constraint count**: ~550K for N=4, scales as ~4^N × 288 constraints
- **Proving time**: ~25s for N=4 configuration with 256 leaves
- **Memory usage**: ~2.5GB for N=4, scales with constraint count
- **Verification**: Constant ~83K gas regardless of leaf count

## File Organization

```
circuits/src/          # Circom circuit files (circuit_N4.circom to circuit_N8.circom)
prover/*/              # Proof generation scripts organized by leaf count
trusted-setup/*/       # Verification keys and proving keys by configuration
verifier/src/          # Solidity verifier contracts 
verifier/test/*/       # Foundry test suites organized by leaf count
```

## Testing Strategy

1. **Circuit tests**: Verify constraint satisfaction and output correctness
2. **Proof generation tests**: Ensure proofs can be generated for valid inputs
3. **Solidity verifier tests**: Test on-chain proof verification with real proof data
4. **Cross-validation**: Verify that circuit outputs match verifier expectations

## Common Development Workflows

### Adding New Circuit Configuration
1. Create new `circuit_N*.circom` file with desired N parameter
2. Add corresponding compile script to `circuits/package.json`
3. Generate trusted setup for new configuration
4. Create Solidity verifier contract
5. Add test suite for new verifier

### Updating Proof Generation
1. Modify input format in prover scripts
2. Update witness calculation paths
3. Ensure trusted setup files match circuit changes
4. Update verifier contract constants if needed

### Debugging Circuit Issues
1. Use `console.log` in circuit tests for signal inspection
2. Check constraint satisfaction with circom compiler warnings
3. Validate witness generation with known good inputs
4. Cross-reference with working configurations