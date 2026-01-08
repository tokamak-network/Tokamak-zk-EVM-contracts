# Tokamak Private Channels Contracts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.29-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-✓-green.svg)](https://getfoundry.sh/)

Our Channel Bridge enables on-demand state channels that hold private L2s. State channels are in charge of aggregating proofs and managing state root.

This repository implements the core smart contracts for the Tokamak zkEVM Bridge solution, providing Layer 2 privacy with Ethereum-equivalent functionality through zero-knowledge proofs.

### Modular Architecture Design

#### **RollupBridge Components**:
- **Modular Design**: Separated concerns across specialized manager contracts
- **Upgradeable Contracts**: UUPS proxy pattern for all core components
- **Gas Optimization**: Streamlined operations with efficient state management
- **Scalable Verification**: Dynamic tree size selection based on channel requirements

#### **Dynamic Merkle Tree Sizing**
The system automatically selects optimal Merkle tree sizes based on channel requirements:

- **Adaptive Sizing**: Tree sizes of 16, 32, 64, or 128 leaves based on participant × token count
- **Groth16 Verification**: Specialized verifiers for each tree size
- **Efficient Proofs**: Optimized proof verification for different channel scales

## Key Features

- **Cryptographic Security**: Groth16 zero-knowledge proofs ensure computation integrity
- **Gas Efficiency**: Dynamic tree sizing with optimized state management
- **Multi-Party**: Supports 1-128 participants with configurable token sets
- **Comprehensive Verification**: Multi-layer verification including ZK-SNARK validation
- **Balance Conservation**: Mathematical guarantees preventing fund creation/destruction
- **State Management**: Secure state transitions with proper authorization
- **🔧pgradeable Architecture**: UUPS proxy pattern for seamless contract upgrades
- **Granular Withdrawals**: Per-token withdrawal system allowing multiple withdrawals
- **Secure Channel Management**: Channel leader controls with proper authorization

## Core Components

#### **Modular Bridge Architecture**
- **`BridgeCore.sol`**: Core state management and channel operations
- **`BridgeDepositManager.sol`**: Deposit handling and token management
- **`BridgeProofManager.sol`**: ZK proof submission and verification
- **`BridgeWithdrawManager.sol`**: Per-token withdrawal processing and finalization
- **`BridgeAdminManager.sol`**: Administrative functions and contract management
- **`IBridgeCore.sol`**: Core interface definitions and data structures

#### **Verification Layer**
- **`TokamakVerifier.sol`**: Main ZK-SNARK proof verification contract
- **`Groth16Verifier*.sol`**: Specialized Groth16 verifiers for different tree sizes (16, 32, 64, 128 leaves)
- **`ZecFrost.sol`**: FROST signature verification library

#### **Utility Layer**
- **`RLP.sol`**: Recursive Length Prefix encoding utilities

### Workflow Phases

1. **Channel Opening**: Authorization and participant registration with leader assignment
2. **Public Key Setup**: Channel leader sets cryptographic public key for signatures
3. **Deposit Period**: Secure fund collection with per-token balance tracking
4. **State Initialization**: Groth16 proof submission establishing initial state root
6. **Proof Submission**: ZK proof verification of computation results and final balances
7. **Signature Verification**: FROST signature validation for result authenticity
8. **Channel Closure**: State transition to Closed with verified final balances
9. **Settlement**: Cryptographically verified per-token fund distribution
10. **Cleanup**: Storage optimization and resource reclamation

## Security Model

### Cryptographic Guarantees
- **Balance Integrity**: Merkle tree proofs ensure tamper-evident balance tracking
- **State Consistency**: Groth16 proofs link all state transitions cryptographically
- **Consensus Security**: FROST multi-signature consensus mechanisms
- **ZK Privacy**: Computation verification without revealing details

### Economic Security
- **Deposit Protection**: Funds locked until valid closure proof
- **Conservation Laws**: Mathematical balance sum verification
- **Root History**: Rollback capability for state recovery
- **Channel Isolation**: Per-channel state prevents cross-contamination

## Getting Started

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
nvm install 18
nvm use 18

# Verify installation
node --version  # Should show v18.x.x
npm --version
```

### Installation

```bash
# Clone the repository
git clone https://github.com/tokamak-network/Tokamak-Zk-EVM-contracts.git
cd Tokamak-Zk-EVM-contracts

# Install dependencies
forge install

# Build the project
forge build

# Run tests
forge test
```

## Testing

The project includes comprehensive test coverage for all components:

```bash
# Run all tests
forge test

# Run specific test contracts
forge test --match-contract RollupBridgeTest
forge test --match-contract WithdrawalsTest
forge test --match-contract ModularArchitectureTest

# Run with gas reporting
forge test --gas-report

# Run with verbose output
forge test -vvv

# Run specific test functions
forge test --match-test testChannelCreationAndDeposits
```

### Test Coverage

- **RollupBridge.t.sol**: 24 tests covering modular bridge operations and state transitions
- **Withdrawals.t.sol**: 10 tests covering per-token withdrawal functionality
- **ModularArchitectureTest.t.sol**: 5 tests covering modular architecture interactions
- **Groth16Verifier*.t.sol**: Tests covering Groth16 verification for different tree sizes (16, 32, 64, 128 leaves)
- **Verifier.t.sol**: 5 tests covering ZK proof verification
- **ZecFrost.t.sol**: 2 tests covering FROST signature verification
- **Total**: 52 comprehensive tests ensuring security and functionality

## Project Structure

```
src/
├── interface/                         # Contract interfaces
│   ├── IBridgeCore.sol                # Core bridge interface
│   ├── IGroth16Verifier*.sol          # Groth16 verifier interfaces
│   ├── ITokamakVerifier.sol           # Tokamak verifier interface
│   └── IZecFrost.sol                  # FROST signature interface
├── verifier/                          # ZK proof verification
│   ├── TokamakVerifier.sol            # Main Tokamak verifier
│   ├── Groth16Verifier*.sol           # Groth16 verifiers for different tree sizes
│   └── Verifier.sol                   # Base verifier contract
├── library/                           # Utility libraries
│   ├── RLP.sol                        # RLP encoding utilities
│   └── ZecFrost.sol                   # FROST signature library
├── BridgeCore.sol                     # Core state management
├── BridgeDepositManager.sol           # Deposit handling
├── BridgeProofManager.sol             # Proof management
├── BridgeWithdrawManager.sol          # Per-token withdrawal management
└── BridgeAdminManager.sol             # Administrative functions

test/
├── bridge/                            # Bridge-specific tests
│   ├── Bridge.t.sol                   # Modular bridge tests 
│   ├── Withdrawals.t.sol              # Withdrawal functionality tests 
│   └── ModularArchitectureTest.t.sol  # Modular architecture tests 
├── groth16/                           # Groth16 verifier tests
│   ├── 16_leaves/                     # 16-leaf tree tests 
│   ├── 32_leaves/                     # 32-leaf tree tests 
│   ├── 64_leaves/                     # 64-leaf tree tests 
│   └── 128_leaves/                    # 128-leaf tree tests 
├── verifier/                          # Verifier tests
│   └── Verifier.t.sol                 # ZK verifier tests 
├── frost/                             # FROST signature tests
│   └── ZecFrost.t.sol                 # FROST tests
├── js-scripts/                        # JavaScript utilities
│   ├── generateGroth16Proof.js        # Groth16 proof generation
│   ├── generateProof.js               # General proof generation
│   └── merkleTree.js                  # Merkle tree utilities
└── scripts/                           # Test scripts
    └── generate_proof.sh              # Proof generation script
```


## Contributing

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

## Documentation

- **Technical Docs**: [docs/](./docs/) directory
- **Test Documentation**: Detailed test coverage and examples

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/tokamak-network/Tokamak-zkEVM-contracts/issues)
- **Discussions**: [GitHub Discussions](https://github.com/tokamak-network/Tokamak-zkEVM-contracts/discussions)
- **Documentation**: [docs/](./docs/) directory

## Acknowledgments

- **OpenZeppelin**: For secure contract libraries
- **Foundry**: For the excellent development toolkit
- **Community**: For feedback and contributions

---

**Built by the Tokamak Network team**

*For more information, visit [tokamak.network](https://tokamak.network)*