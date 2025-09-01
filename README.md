# Tokamak zkEVM Contracts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.23-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-✓-green.svg)](https://getfoundry.sh/)

Our rollup enables on-demand state channels that hold private L2s. State channels are in charge of aggregating proofs and managing state root.

This repository implements the core smart contracts for the Tokamak zkEVM rollup solution, providing Layer 2 privacy with Ethereum-equivalent functionality through zero-knowledge proofs.

## Architecture

![Alt text](./images/workflow.png)

## Overview

This repository contains the smart contracts and documentation for a ZK-Rollup bridge that enables secure off-chain computation with on-chain settlement. The system uses **Quaternary Merkle Trees** with  **Random Linear Combination (RLC)** encoding to ensure tamper-evident balance tracking and employs zero-knowledge proofs for comprehensive computation verification.

### **Latest Innovation: Architectural Optimization with Embedded Merkle Operations**

The project has undergone a major architectural redesign with the introduction of **RollupBridgeV2**, achieving significant gas optimization while maintaining full functional equivalence:

#### **RollupBridgeV2:
- **Embedded Merkle Operations**: All Merkle tree operations embedded directly in the bridge contract
- **No External Calls**: Eliminated 5-6 external contract calls that were consuming substantial gas
- **Optimized Tree Initialization**: Streamlined initialization sequence with batched operations
- **Proven Equivalence**: Produces identical Merkle roots as V1 with comprehensive test coverage

#### **Quaternary Merkle Trees**
Both versions leverage **MerkleTreeManager4** with **4-input hashing** instead of traditional binary trees:

- **Reduced Gas Costs**: Fewer hash operations for tree construction and verification
- **Enhanced Security**: More complex tree structure increases security margin  
- **Better Scalability**: Supports larger trees with fewer levels

## ✨ Key Features

- **🔐 Cryptographic Security**: RLC encoding creates tamper-evident balance commitments
- **⚡ Gas Efficiency**: Quaternary tree structure with batch processing and incremental updates
- **👥 Multi-Party**: Supports 3-50 participants with threshold signature consensus
- **🛡️ Comprehensive Verification**: 4-layer verification including ZK-SNARK validation
- **💰 Balance Conservation**: Mathematical guarantees preventing fund creation/destruction
- **🔄 State Rollback**: Root history tracking for state recovery and verification
- **🔧 Upgradeable Architecture**: UUPS proxy pattern for seamless contract upgrades

## Core Components

#### **Bridge Layer**
- **`RollupBridge.sol`**: **Latest V2** with embedded Merkle operations for 39% gas reduction
- **`IRollupBridge.sol`**: Interface definitions and data structures

#### **Verification Layer**
- **`Verifier.sol`**: ZK-SNARK proof verification contract
- **`IVerifier.sol`**: Verifier interface

#### **Utility Layer**
- **`RLP.sol`**: Recursive Length Prefix encoding utilities

### Workflow Phases

1. **🔓 Channel Opening**: Authorization and participant registration with preprocessing
2. **💰 Deposit Period**: Secure fund collection with balance tracking
3. **🌱 State Initialization**: On-chain RLC computation and initial root storage
4. **⚡ Off-Chain Computation**: High-throughput L2 processing with consensus
5. **🚪 Closure Initiation**: Threshold-signed submission of computation results
6. **✅ Verification**: 4-layer validation including ZK proof verification
7. **💸 Settlement**: Cryptographically verified fund distribution
8. **🧹 Cleanup**: Challenge period and storage optimization

## 🔐 Security Model

### Cryptographic Guarantees
- **Balance Integrity**: RLC chaining prevents undetected manipulation
- **State Consistency**: Quaternary Merkle roots link all state transitions
- **Consensus Security**: 2/3+ threshold signatures required
- **ZK Privacy**: Computation verification without revealing details
- **Tree Security**: 4-input hashing provides stronger collision resistance

### Economic Security
- **Deposit Protection**: Funds locked until valid closure proof
- **Conservation Laws**: Mathematical balance sum verification
- **Challenge Period**: 14-day finality window for dispute resolution
- **Root History**: Rollback capability for state recovery

## 🚀 Getting Started

### Prerequisites

#### 1. Foundry Toolkit
Foundry is a blazing fast, portable and modular toolkit for Ethereum development.

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash

# Follow the instructions to add Foundry to your PATH, then run:
foundryup

# Verify installation
forge --version
cast --version
anvil --version
```

#### 2. Node.js and npm
Required for additional tooling and dependencies.

```bash
# Using nvm (recommended)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 16
nvm use 16

# Or using your system's package manager
# macOS with Homebrew
brew install node@16

# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version  # Should show v16.x.x
npm --version
```

### Installation

```bash
# Clone the repository
git clone https://github.com/tokamak-network/Tokamak-zkEVM-contracts.git
cd Tokamak-zkEVM-contracts

# Install dependencies
forge install

# Build the project
forge build

# Run tests
forge test
```

## 🧪 Testing

The project includes comprehensive test coverage for all components:

```bash
# Run all tests
forge test

# Run specific test contracts
forge test --match-contract RollupBridgeTest
forge test --match-contract WithdrawalsTest
forge test --match-contract BasicUpgradeableTest
forge test --match-contract ArchitecturalOptimizationTest


# Run with gas reporting
forge test --gas-report

# Run with verbose output
forge test -vvv

# Run specific test functions
forge test --match-test testConstructor
```

### Test Coverage

- **RollupBridge.t.sol**: 34 tests covering V1 bridge operations
- **BasicUpgradeableTest.t.sol**: 16 tests covering V1 upgradeability and lifecycle
- **ArchitecturalOptimizationTest.t.sol**: 6 tests comparing V1 vs V2 performance and equivalence
- **Verifier.t.sol**: 5 tests covering ZK proof verification
- **Total**: 61 tests ensuring comprehensive coverage with proven functional equivalence

## Project Structure

```
src/
├── merkleTree/           # Merkle tree implementations
│   ├── MerkleTreeManagerV1.sol           # UUPS upgradeable quaternary tree for V1
│   ├── MerkleTreeManager4.sol            # Non-upgradeable quaternary tree for V1
│   └── MerkleTreeManager2.sol            # Binary tree (Legacy)
├── interface/            # Contract interfaces
│   ├── IMerkleTreeManager.sol
│   ├── IRollupBridge.sol
│   └── IVerifier.sol
├── verifier/             # ZK proof verification
│   └── Verifier.sol
├── library/              # Utility libraries
│   └── RLP.sol
├── RollupBridgeV2.sol    # V2 with embedded Merkle operations (Recommended)
├── RollupBridgeV1.sol    # V1 using external MerkleTreeManager4
└── script/               # Deployment scripts
    ├── DeployV2.s.sol    # V2 deployment script
    ├── deploy-v2.sh      # V2 deployment script
    └── env-v2.template   # V2 environment template

test/
├── RollupBridge.t.sol               # V1 Bridge tests
├── BasicUpgradeableTest.t.sol       # V1 Upgradeability tests
├── ArchitecturalOptimizationTest.t.sol # V1 vs V2 comparison tests
├── Verifier.t.sol                   # ZK verifier tests
└── mocks/                           # Test utilities
```

## Test contract addresses 

- Bridge proxy: 0x9C688e3262421F8383A5c9C96aBa3e66F207e611
- Merkle Tree Manager Proxy: 0x83F163507A788df0EfBfbb08Bc1A185685163d6b


## 📊 Performance & Gas Optimization

### V2 Architectural Optimization Results

| Metric | V1 (External Calls) | V2 (Embedded) | Improvement |
|--------|---------------------|---------------|-------------|
| **Gas per Channel Init (3 users)** | 773,440 gas | 471,595 gas | **39% reduction** |
| **Gas Saved** | - | 301,845 gas | **301K saved** |
| **External Contract Calls** | 5-6 calls | 0 calls | **100% eliminated** |
| **Scalability (40 users)** | 6.9M gas | 3.1M gas | **54% reduction** |

### Quaternary Tree Benefits

| Metric | Binary Tree | Quaternary Tree | Improvement |
|--------|-------------|-----------------|-------------|
| Hash Operations | 2 inputs/hash | 4 inputs/hash | **2x fewer** |
| Tree Depth | 32 levels | 16 levels | **50% reduction** |
| Gas per Insert | ~15k gas | ~12k gas | **20% savings** |
| Proof Size | Larger | Smaller | **25% reduction** |

### Scaling Analysis

The architectural optimization provides increasing benefits with more users:
- **3 users**: 39% reduction (301K gas saved)
- **5 users**: 44% reduction (490K gas saved)  
- **40 users**: 54% reduction (3.8M gas saved)

## 🔄 Version Comparison: V1 vs V2

### Architecture Differences

| Feature | V1 (Legacy) | V2 (Optimized) |
|---------|-------------|----------------|
| **Merkle Operations** | External MerkleTreeManager4 contract | Embedded in bridge contract |
| **External Calls** | 5-6 calls per initialization | 0 calls |
| **Gas Consumption** | ~773K gas (3 users) | ~472K gas (3 users) |
| **Contract Dependencies** | Requires MerkleTreeManager4 deployment | Self-contained |
| **Functional Equivalence** | ✅ Reference implementation | ✅ Produces identical Merkle roots |

### When to Use V1 vs V2

#### Choose V1 (Legacy) if you need:
- Separate Merkle tree contract for other use cases
- Gradual migration from existing V1 deployments
- External access to Merkle tree operations

#### Choose V2 (Recommended) if you need:
- **39% gas reduction** for channel operations
- Simplified deployment (single contract)
- Optimized performance for high-throughput applications
- Latest architectural improvements

### Migration Path

Existing V1 users can migrate to V2 by:
1. Deploying new V2 contracts using `./script/deploy-v2.sh`
2. Migrating channels during their natural lifecycle
3. Both versions maintain full functional equivalence with identical security properties


## 🔒 Security Considerations

### Audit Status

- **Internal Review**: 🆕 Coming Soon
- **External Audit**: 🆕 Coming Soon
- **Bug Bounty**: 🆕 Coming Soon

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass: `forge test`
6. Commit your changes: `git commit -m 'Add amazing feature'`
7. Push to the branch: `git push origin feature/amazing-feature`
8. Open a Pull Request

### Code Style

- Follow Solidity style guide
- Use comprehensive NatSpec documentation
- Include tests for all new functionality
- Ensure gas optimization where possible

## 📚 Documentation

- **Technical Docs**: [docs/](./docs/) directory

## 📦 Deployment

### UUPS Upgradeable Deployment

The contracts are deployed using the **UUPS (Universal Upgradeable Proxy Standard)** pattern for seamless upgrades while preserving state.

#### Deployment Scripts

```bash
# Deploy V2 contracts (Recommended - 39% gas reduction)
./script/deploy-v2.sh sepolia

# Deploy V1 contracts (Legacy)
./script/deploy-upgradeable.sh sepolia

# Upgrade existing contracts (owner only)
./script/upgrade-contracts.sh
```

#### Environment Setup

##### For V2 Deployment (Recommended)
Create `.env` file based on `script/env-v2.template`:

```bash
# Network Configuration
RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
CHAIN_ID=11155111
PRIVATE_KEY=0x...

# Contract Configuration
ZK_VERIFIER_ADDRESS=0x...
DEPLOYER_ADDRESS=0x...

# Verification
VERIFY_CONTRACTS=true
ETHERSCAN_API_KEY=YOUR_API_KEY
```

##### For V1 Deployment (Legacy)
Create `.env` file based on `script/env-v1.template` with additional `TREE_DEPTH` parameter.

### Deployed Contracts (Sepolia)

#### 🔗 V1 Contracts (External Merkle Tree Manager)
```
MerkleTreeManager4 (Proxy): 0x83f163507a788df0efbfbb08bc1a185685163d6b
RollupBridgeV1 (Proxy): 0x9c688e3262421f8383a5c9c96aba3e66f207e611
```

#### ⚡ V2 Contracts (Embedded Merkle Operations - Recommended)
```
RollupBridgeV2 impl: 0x0b1C462CF1FF872bfB336ec404764ED8b6515684
RollupBridgeV2 (Proxy): 0x5c6446d4039be4c1a0c2ff1a8d294f813893d1e9
```

https://sepolia.etherscan.io/tx/0xb3f33e3d630795edbdb68aac75fe5b83f98db54a92d4544ec4ac233455af28b7
A5376FAC3B26618337FBA8FF718CE432B7BC3651B6AF9BCB3AF578F4632B35BF

#### 🏗️ Implementation Contracts (For Upgrades Only)
```
MerkleTreeManagerV1: 0x4e6f45b00525fa7ce112c46e731e21271f119589
RollupBridgeV1: 0xa0719a492c62588e54f839d8b8342d1b170b6cf3
```

#### Safety Features
- **Storage Layout Compatibility**: Automated checks prevent storage collisions
- **Initialization Protection**: Prevents re-initialization attacks
- **Owner-Only Upgrades**: Only contract owner can perform upgrades
- **Atomic Deployment**: MEV-protected deployment with immediate initialization

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/tokamak-network/Tokamak-zkEVM-contracts/issues)
- **Discussions**: [GitHub Discussions](https://github.com/tokamak-network/Tokamak-zkEVM-contracts/discussions)
- **Documentation**: [docs/](./docs/) directory

## 🙏 Acknowledgments

- **OpenZeppelin**: For secure contract libraries
- **Foundry**: For the excellent development toolkit
- **Community**: For feedback and contributions

---

**Built by the Ooo Tokamak Network team**

*For more information, visit [tokamak.network](https://tokamak.network)*