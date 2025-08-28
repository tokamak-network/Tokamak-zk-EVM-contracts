# UUPS Upgradeable Contract Deployment Guide

This directory contains deployment and upgrade scripts for the UUPS (Universal Upgradeable Proxy Standard) versions of the Tokamak zkRollup contracts.

## 📁 Files Overview

### Deployment Scripts
- **`DeployUpgradeable.s.sol`** - Foundry script for deploying UUPS upgradeable contracts
- **`deploy-upgradeable.sh`** - Shell script wrapper for easy deployment
- **`env-upgradeable.template`** - Environment configuration template

### Upgrade Scripts  
- **`UpgradeContracts.s.sol`** - Foundry script for upgrading existing contracts
- **`upgrade-contracts.sh`** - Shell script wrapper for easy upgrades

## 🚀 Quick Start

### 1. Setup Environment

```bash
# Copy the environment template
cp script/env-upgradeable.template .env

# Edit .env with your configuration
nano .env
```

### 2. Deploy Contracts

```bash
# Deploy to testnet (e.g., Sepolia)
./script/deploy-upgradeable.sh sepolia

# Deploy to mainnet
./script/deploy-upgradeable.sh mainnet
```

### 3. Upgrade Contracts (Later)

```bash
# Upgrade both contracts
./script/upgrade-contracts.sh sepolia --both

# Upgrade only MerkleTreeManager4
./script/upgrade-contracts.sh sepolia --merkle-tree

# Upgrade only RollupBridge  
./script/upgrade-contracts.sh sepolia --rollup-bridge
```

## 🔧 Detailed Configuration

### Required Environment Variables

```bash
# Deployment account
PRIVATE_KEY=your_private_key_here
DEPLOYER_ADDRESS=0x1234567890123456789012345678901234567890

# Contract dependencies
ZK_VERIFIER_ADDRESS=0x1234567890123456789012345678901234567890

# Network configuration
RPC_URL=https://your-rpc-endpoint-here
CHAIN_ID=11155111

# Optional configuration
TREE_DEPTH=3                    # Merkle tree depth (default: 3)
VERIFY_CONTRACTS=true            # Verify on block explorer
ETHERSCAN_API_KEY=your_api_key   # Required for verification
```

### Additional Variables for Upgrades

```bash
# Existing proxy addresses (required for upgrades)
MERKLE_TREE_PROXY_ADDRESS=0x1234567890123456789012345678901234567890
ROLLUP_BRIDGE_PROXY_ADDRESS=0x1234567890123456789012345678901234567890

# Upgrade flags
UPGRADE_MERKLE_TREE=true         # Upgrade MerkleTreeManager4
UPGRADE_ROLLUP_BRIDGE=true       # Upgrade RollupBridge
```

## 📋 Step-by-Step Deployment

### Initial Deployment Process

1. **Deploy Implementations**: Both contract implementations are deployed
2. **Deploy Proxies**: ERC1967 proxies are deployed pointing to implementations
3. **Initialize Contracts**: Proxies are initialized with constructor data
4. **Configure Bridge**: MerkleTreeManager4 is configured with bridge address
5. **Verification**: All deployments are verified for correctness
6. **Block Explorer Verification**: Contracts are verified on block explorer (optional)

### What Gets Deployed

| Contract Type | Description | Usage |
|---------------|-------------|-------|
| `MerkleTreeManager4Upgradeable` (Implementation) | Contract logic | For upgrades only |
| `MerkleTreeManager4` (Proxy) | User-facing contract | Main interactions |
| `RollupBridgeUpgradeable` (Implementation) | Contract logic | For upgrades only |  
| `RollupBridge` (Proxy) | User-facing contract | Main interactions |

**⚠️ Important**: Always interact with the **proxy addresses**, not the implementation addresses!

## 🔄 Upgrade Process

### How Upgrades Work

1. **Deploy New Implementation**: New contract logic is deployed
2. **Verify Ownership**: Script confirms deployer owns the contracts
3. **Execute Upgrade**: `upgradeTo()` is called on existing proxies
4. **Verify Upgrade**: Script confirms implementations were updated
5. **State Preservation**: All existing state remains intact

### Upgrade Safety

- ✅ State is preserved across upgrades
- ✅ Proxy addresses never change
- ✅ Only owner can perform upgrades
- ✅ Implementation addresses are updated
- ✅ All functionality continues to work

## 🌐 Network Examples

### Ethereum Sepolia Testnet
```bash
CHAIN_ID=11155111
RPC_URL=https://sepolia.infura.io/v3/YOUR_PROJECT_ID
```

### Ethereum Mainnet
```bash
CHAIN_ID=1
RPC_URL=https://mainnet.infura.io/v3/YOUR_PROJECT_ID
```

### Arbitrum One
```bash
CHAIN_ID=42161
RPC_URL=https://arb1.arbitrum.io/rpc
```

### Arbitrum Sepolia
```bash
CHAIN_ID=421614
RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
```

## 🔍 Manual Deployment Commands

If you prefer to run commands manually:

### Deploy
```bash
forge script script/DeployUpgradeable.s.sol:DeployUpgradeableScript \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

### Upgrade
```bash
forge script script/UpgradeContracts.s.sol:UpgradeContractsScript \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

## 📁 Output Files

### Deployment Outputs
- **`broadcast/`** - Foundry broadcast files with transaction details
- **`deployments-{network}-{timestamp}.json`** - Deployment summary
- **Console logs** - Addresses and configuration details

### Important Addresses to Save
After deployment, save these addresses:
- **MerkleTreeManager4 Proxy** - Use for all interactions
- **RollupBridge Proxy** - Use for all interactions  
- Implementation addresses - Keep for upgrade reference

## 🛡️ Security Best Practices

### Pre-Deployment
1. **Test on testnet first** - Always deploy and test on testnet
2. **Verify verifier contract** - Ensure ZK_VERIFIER_ADDRESS is correct
3. **Check deployer balance** - Ensure sufficient funds for deployment
4. **Backup private keys** - Secure your deployment keys

### Post-Deployment
1. **Verify contract code** - Confirm contracts are verified on block explorer  
2. **Test functionality** - Run comprehensive tests on deployed contracts
3. **Secure owner keys** - Transfer ownership to multisig for production
4. **Monitor contracts** - Set up monitoring for contract activity

### Upgrade Safety
1. **Test upgrades on testnet** - Never upgrade mainnet without testing
2. **Backup state** - Consider snapshotting state before upgrades
3. **Gradual rollout** - Consider phased upgrades for complex changes
4. **Emergency procedures** - Have rollback plans ready

## ❗ Common Issues & Solutions

### Deployment Failures
- **"Insufficient funds"** - Add more ETH to deployer account
- **"Invalid verifier address"** - Check ZK_VERIFIER_ADDRESS is deployed
- **"Initialization failed"** - Verify constructor parameters

### Upgrade Failures  
- **"Ownable: caller is not the owner"** - Deployer must own contracts
- **"Same implementation"** - Cannot upgrade to same implementation
- **"Proxy not found"** - Check proxy addresses are correct

### Verification Failures
- **"Contract not verified"** - Check ETHERSCAN_API_KEY is valid
- **"Constructor mismatch"** - Verify constructor arguments are correct

## 📞 Support

For issues or questions:
1. Check the error messages carefully
2. Verify your environment configuration  
3. Test on a testnet first
4. Review the broadcast files for transaction details

## 🔗 References

- [OpenZeppelin UUPS Documentation](https://docs.openzeppelin.com/contracts/4.x/upgradeable)
- [EIP-1967: Standard Proxy Storage Slots](https://eips.ethereum.org/EIPS/eip-1967)
- [Foundry Deployment Documentation](https://book.getfoundry.sh/forge/deploying)
- [UUPS_UPGRADE_IMPLEMENTATION.md](../UUPS_UPGRADE_IMPLEMENTATION.md) - Technical implementation details