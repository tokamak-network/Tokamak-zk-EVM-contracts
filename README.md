# Tokamak zkEVM Contracts

Our rollup enables on-demand state channels that hold private L2s. State channels are in charge of aggregating proofs and managing state root.

This repository implements the core smart contracts for the Tokamak zkEVM rollup solution, providing Layer 2 privacy with Ethereum-equivalent functionality through zero-knowledge proofs.

## Architecture

![Alt text](./images/workflow.png)

## Overview

This repository contains the smart contracts and documentation for a ZK-Rollup bridge that enables secure off-chain computation with on-chain settlement. The system uses Random Linear Combination (RLC) encoding with Poseidon2 hashing to ensure tamper-evident balance tracking and employs zero-knowledge proofs for comprehensive computation verification.

## Key Features

- **🔐 Cryptographic Security**: RLC encoding creates tamper-evident balance commitments
- **⚡ Gas Efficiency**: Batch processing and incremental Merkle tree updates
- **🌳 ZK-Friendly**: Poseidon2 hash function optimized for zero-knowledge circuits
- **👥 Multi-Party**: Supports 3-50 participants with threshold signature consensus
- **🛡️ Comprehensive Verification**: 4-layer verification including ZK-SNARK validation
- **💰 Balance Conservation**: Mathematical guarantees preventing fund creation/destruction

## Architecture

### Core Components

- **`ZKRollupBridge.sol`**: Main bridge contract managing channels and verification
- **`MerkleTreeManager.sol`**: Incremental Merkle tree with RLC leaf encoding
- **`IZKRollupBridge.sol`**: Interface definitions and data structures

### Workflow Phases

1. **Channel Opening**: Authorization and participant registration with preprocessing
2. **Deposit Period**: Secure fund collection with balance tracking
3. **State Initialization**: On-chain RLC computation and initial root storage
4. **Off-Chain Computation**: High-throughput L2 processing with consensus
5. **Closure Initiation**: Threshold-signed submission of computation results
6. **Verification**: 4-layer validation including ZK proof verification
7. **Settlement**: Cryptographically verified fund distribution
8. **Cleanup**: Challenge period and storage optimization

## Security Model

### Cryptographic Guarantees
- **Balance Integrity**: RLC chaining prevents undetected manipulation
- **State Consistency**: Merkle roots link all state transitions
- **Consensus Security**: 2/3+ threshold signatures required
- **ZK Privacy**: Computation verification without revealing details

### Economic Security
- **Deposit Protection**: Funds locked until valid closure proof
- **Conservation Laws**: Mathematical balance sum verification
- **Challenge Period**: 7-day finality window for dispute resolution


## Requirements

- Solidity ^0.8.23
- OpenZeppelin Contracts
- Poseidon2 hash function library
- ZK-SNARK verifier contract


## Getting Started

### Required Software

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

#### 3. Solidity Compiler
The project uses Solidity 0.8.23. Foundry will handle the compiler installation automatically, but you can also install it manually:

```bash
# Via npm (optional)
npm install -g solc@0.8.23

# Verify the compiler version in foundry.toml
```


### Installation
```bash
git clone https://github.com/tokamak-network/Tokamak-zkEVM-contracts.git
cd Tokamak-zkEVM-contracts
forge install
forge test
```