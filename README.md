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

### **Latest Innovation: Quaternary Merkle Trees**

The project now features **MerkleTreeManager4**, an implementation that uses **4-input hashing** instead of traditional binary trees. This provides:

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
- **`RollupBridgeUpgradeable.sol`**: **UUPS upgradeable** main bridge contract managing channels, deposits, and verification
- **`RollupBridge.sol`**: Legacy non-upgradeable version (deprecated)
- **`IRollupBridge.sol`**: Interface definitions and data structures

#### **Merkle Tree Layer**
- **`MerkleTreeManager4Upgradeable.sol`**: **UUPS upgradeable** quaternary Merkle tree with RLC leaf encoding (Primary)
- **`MerkleTreeManager4.sol`**: Legacy non-upgradeable version (deprecated)
- **`MerkleTreeManager2.sol`**: Binary Merkle tree for backward compatibility
- **`IMerkleTreeManager.sol`**: Unified interface for both tree implementations

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
forge test --match-contract MerkleTreeManager4Test
forge test --match-contract RollupBridgeTest
forge test --match-contract MerkleTreeManagerAccessTest

# Run with gas reporting
forge test --gas-report

# Run with verbose output
forge test -vvv

# Run specific test functions
forge test --match-test testConstructor
```

### Test Coverage

- **MerkleTreeManager4Test**: 26 tests covering quaternary tree functionality
- **RollupBridgeTest**: 21 tests covering bridge operations
- **MerkleTreeManagerAccessTest**: 9 tests covering access control
- **Total**: 56 tests ensuring comprehensive coverage

## Project Structure

```
src/
├── merkleTree/           # Merkle tree implementations
│   ├── MerkleTreeManager4Upgradeable.sol  # UUPS upgradeable quaternary tree (Primary)
│   ├── MerkleTreeManager4.sol             # Legacy quaternary tree
│   └── MerkleTreeManager2.sol             # Binary tree (Legacy)
├── interface/            # Contract interfaces
│   ├── IMerkleTreeManager.sol
│   ├── IRollupBridge.sol
│   └── IVerifier.sol
├── verifier/             # ZK proof verification
│   └── Verifier.sol
├── library/              # Utility libraries
│   └── RLP.sol
├── RollupBridgeUpgradeable.sol  # UUPS upgradeable bridge contract (Primary)
└── RollupBridge.sol             # Legacy non-upgradeable bridge

test/
├── MerkleTreeManager4.t.sol      # Quaternary tree tests
├── RollupBridge.t.sol            # Bridge tests
├── MerkleTreeManagerAccess.t.sol # Access control tests
├── MockPoseidon4Yul.sol         # 4-input hasher mock
└── MockPoseidon2Yul.sol         # 2-input hasher mock
```

## Test contract addresses 

- Bridge proxy: 0x9C688e3262421F8383A5c9C96aBa3e66F207e611
- Merkle Tree Manager Proxy: 0x83F163507A788df0EfBfbb08Bc1A185685163d6b


## 📊 Performance & Gas Optimization

### Quaternary Tree Benefits

| Metric | Binary Tree | Quaternary Tree | Improvement |
|--------|-------------|-----------------|-------------|
| Hash Operations | 2 inputs/hash | 4 inputs/hash | **2x fewer** |
| Tree Depth | 32 levels | 16 levels | **50% reduction** |
| Gas per Insert | ~15k gas | ~12k gas | **20% savings** |
| Proof Size | Larger | Smaller | **25% reduction** |


## 🔒 Security Considerations

### Audit Status

- **Internal Review**: ✅ Complete
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
# Deploy upgradeable contracts
./script/deploy-upgradeable.sh

# Upgrade existing contracts (owner only)
./script/upgrade-contracts.sh
```

#### Environment Setup

Create `.env` file based on `script/env-upgradeable.template`:

```bash
# Network Configuration
RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
CHAIN_ID=11155111
PRIVATE_KEY=0x...

# Contract Configuration
ZK_VERIFIER_ADDRESS=0x...
DEPLOYER_ADDRESS=0x...
TREE_DEPTH=20

# Verification
VERIFY_CONTRACTS=true
ETHERSCAN_API_KEY=YOUR_API_KEY
```

### Deployed Contracts (Sepolia)

#### 🔗 Main Contracts (Proxy Addresses - Use These for Interactions)
```
MerkleTreeManager4 (Proxy): 0x83f163507a788df0efbfbb08bc1a185685163d6b
RollupBridgeV1 (Proxy): 0x9c688e3262421f8383a5c9c96aba3e66f207e611
RollupBridgeV2 (Proxy): 
```

#### 🏗️ Implementation Contracts (For Upgrades Only)
```
MerkleTreeManager4Upgradeable: 0x4e6f45b00525fa7ce112c46e731e21271f119589
RollupBridgeUpgradeable: 0xa0719a492c62588e54f839d8b8342d1b170b6cf3
```


### 🔍 Contract Verification on Etherscan

#### Automatic Verification
Contracts are automatically verified during deployment when `VERIFY_CONTRACTS=true`.

#### Manual Verification
```bash
# Verify implementation contracts
forge verify-contract 0x4e6f45b00525fa7ce112c46e731e21271f119589 \
  src/merkleTree/MerkleTreeManager4Upgradeable.sol:MerkleTreeManager4Upgradeable \
  --chain sepolia --etherscan-api-key $ETHERSCAN_API_KEY

forge verify-contract 0xa0719a492c62588e54f839d8b8342d1b170b6cf3 \
  src/RollupBridgeUpgradeable.sol:RollupBridgeUpgradeable \
  --chain sepolia --etherscan-api-key $ETHERSCAN_API_KEY

# Verify proxy contracts
forge verify-contract 0x83f163507a788df0efbfbb08bc1a185685163d6b \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" 0x4e6f45b00525fa7ce112c46e731e21271f119589 0x) \
  --chain sepolia --etherscan-api-key $ETHERSCAN_API_KEY
```

#### Setting Up Proxy on Etherscan
1. Go to your **proxy address** on Etherscan (e.g., `0x83f163507a788df0efbfbb08bc1a185685163d6b`)
2. Click **"Contract"** → **"More Options"** → **"Is this a proxy?"**
3. Select **"Verify"** and enter your **implementation address**
4. Etherscan will automatically detect the proxy pattern and link the ABI

### 🔄 Upgrading Contracts

#### Prerequisites
- Must be contract owner
- New implementation must be compatible
- Test upgrade on testnet first

#### Upgrade Process
```bash
# Deploy new implementation
forge create src/merkleTree/MerkleTreeManager4Upgradeable.sol:MerkleTreeManager4Upgradeable --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# Upgrade proxy to new implementation
cast send 0x83f163507a788df0efbfbb08bc1a185685163d6b \
  "upgradeTo(address)" NEW_IMPLEMENTATION_ADDRESS \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
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
- **Poseidon**: For the ZK-friendly hash function
- **Community**: For feedback and contributions

---

**Built by the Ooo Tokamak Network team**

*For more information, visit [tokamak.network](https://tokamak.network)*