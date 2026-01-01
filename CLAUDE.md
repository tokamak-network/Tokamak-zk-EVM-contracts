# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the Tokamak zkEVM contracts repository - a Zero-Knowledge rollup bridge system that enables secure off-chain computation with on-chain settlement. The system uses ZK-SNARKs (specifically Groth16) for computation verification and manages state channels with configurable Merkle tree sizes.

## Development Commands

### Build & Testing
```bash
# Build all contracts
forge build

# Run all tests
forge test

# Run specific test files
forge test --match-contract RollupBridgeTest
forge test --match-contract WithdrawalsTest
forge test --match-contract ModularArchitectureTest

# Run with gas reporting
forge test --gas-report

# Run with verbose output for debugging
forge test -vvv

# Run specific test functions
forge test --match-test testChannelCreationAndDeposits
```

### Deployment & Scripts
```bash
# Deploy V2 contracts (main deployment)
./script/deploy/deploy-v2.sh sepolia

# Deploy TokamakVerifier
./script/deploy/deploy-tokamak-verifier.sh sepolia

# Upgrade contracts
./script/upgrade/upgrade-contracts.sh sepolia

# Register functions
./script/deploy/register-function.sh

# Set channel public key
./script/deploy/set-channel-public-key.sh

# Test Groth16 integration
./script/deploy/test-groth16-integration.sh
```

### Environment Setup
Copy `script/deploy/env-v2.template` to `.env` and configure:
```bash
PRIVATE_KEY=your_private_key
RPC_URL=your_rpc_url
ETHERSCAN_API_KEY=your_api_key
DEPLOYER_ADDRESS=0x...
```

## Architecture Overview

### Modular Bridge Design
The system uses a modular architecture with specialized manager contracts:

- **BridgeCore.sol**: Core state management and channel operations
- **BridgeDepositManager.sol**: Handles deposits and token management 
- **BridgeProofManager.sol**: ZK proof submission and verification
- **BridgeWithdrawManager.sol**: Per-token withdrawal processing
- **BridgeAdminManager.sol**: Administrative functions

### Channel Lifecycle
1. **Initialization**: Channel creation with participants and target contract
2. **Opening**: Public key setup by channel leader
3. **Deposits**: Secure fund collection with per-token tracking
4. **State Initialization**: Groth16 proof establishes initial state root
5. **Off-chain Computation**: L2 processing with consensus mechanisms
6. **Proof Submission**: ZK verification of computation results
7. **Signature Verification**: FROST signature validation
8. **Closure**: State transition with verified final balances
9. **Withdrawal**: Per-token fund distribution

### Verification Layer
- **TokamakVerifier.sol**: Main ZK-SNARK proof verification
- **Groth16Verifier*.sol**: Specialized verifiers for different tree sizes (16, 32, 64, 128 leaves)
- **ZecFrost.sol**: FROST signature verification library

### Dynamic Merkle Tree Sizing
The system automatically selects tree sizes based on channel requirements:
- Tree sizes: 16, 32, 64, or 128 leaves
- Selection based on participant × token count
- Each size has its own optimized Groth16 verifier

## Key File Locations

### Core Contracts
- `src/BridgeCore.sol` - Main bridge logic
- `src/interface/IBridgeCore.sol` - Core interface definitions
- `src/verifier/TokamakVerifier.sol` - ZK proof verification
- `src/library/ZecFrost.sol` - FROST signatures
- `src/library/RLP.sol` - RLP encoding utilities

### Test Structure
- `test/bridge/` - Bridge functionality tests (39 tests total)
- `test/groth16/` - Groth16 verifier tests for each tree size
- `test/verifier/` - ZK verification tests
- `test/frost/` - FROST signature tests
- `test/js-scripts/` - JavaScript utilities for proof generation

### Deployment Scripts
- `script/deploy/DeployV2.s.sol` - Main deployment script
- `script/upgrade/UpgradeContracts.s.sol` - Contract upgrade script
- Shell wrappers in `script/deploy/` and `script/upgrade/`

## Security Features

- **UUPS Upgradeable**: Safe upgrade mechanism with storage protection
- **Balance Conservation**: Mathematical guarantees preventing fund loss/creation
- **Multi-signature Consensus**: FROST threshold signatures
- **Per-token Isolation**: Independent token balance management
- **ZK Privacy**: Computation verification without revealing details
- **Access Control**: Role-based permissions with channel leaders

## Testing Notes

- 52 comprehensive tests covering all functionality
- Gas limit configured to 100M for heavy ZK operations
- FFI enabled for JavaScript proof generation scripts
- Test data includes real Groth16 proofs in `test/groth16/*/proof.json`

## Common Development Patterns

- All contracts use OpenZeppelin Upgradeable pattern
- Contracts follow modular design with clear separation of concerns
- ZK verification is abstracted behind interfaces for different tree sizes
- Error handling uses custom errors for gas efficiency
- Events are emitted for all state changes

## Important Notes

- **No ETH Support**: System focused exclusively on ERC20 tokens
- **Channel Leaders**: Each channel has a designated leader for key operations
- **Tree Size Selection**: Automatic based on participant and token counts
- **Proof Generation**: Uses external JavaScript scripts with FFI
- **Upgrades**: UUPS pattern allows seamless contract upgrades while preserving state