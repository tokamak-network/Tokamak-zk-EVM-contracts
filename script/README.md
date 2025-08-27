# Deployment Guide for Tokamak zkEVM Contracts

This directory contains deployment scripts for the Tokamak zkEVM system.

## 📁 Files

- **`Deploy.s.sol`** - Main Foundry deployment script
- **`deploy.sh`** - Shell script wrapper for easy deployment
- **`deployment-config.md`** - Configuration guide
- **`README.md`** - This file

## 🚀 Quick Start

### 1. Prepare Environment

Create a `.env` file in the project root:

```bash
# Required variables
PRIVATE_KEY=your_private_key_here
RPC_URL=https://your-rpc-endpoint.com
ZK_VERIFIER_ADDRESS=0x...

# Optional variables
DEPLOYER_ADDRESS=0x...
CHAIN_ID=1
```

### 2. Deploy Contracts

#### Option A: Using the shell script (Recommended)
```bash
./script/deploy.sh
```

#### Option B: Using Foundry directly
```bash
# Build first
forge build

# Deploy
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## 🔧 Deployment Process

The script automatically:

1. **Deploys Poseidon4** - Cryptographic hashing contract
2. **Deploys MerkleTreeManager4** - Merkle tree management with Poseidon4 integration
3. **Deploys RollupBridge** - Main bridge contract connecting to ZK verifier
4. **Configures contracts** - Sets up proper contract relationships
5. **Verifies deployment** - Ensures all contracts are properly configured

## 📊 Contract Dependencies

```
Poseidon4 (no deps)
    ↓
MerkleTreeManager4 (depends on Poseidon4)
    ↓
RollupBridge (depends on MerkleTreeManager4 + ZK Verifier)
```

## 💰 Gas Estimation

| Contract | Estimated Gas |
|----------|---------------|
| Poseidon4 | ~500,000 |
| MerkleTreeManager4 | ~800,000 |
| RollupBridge | ~600,000 |
| Configuration | ~100,000 |
| **Total** | **~2,000,000** |

## 🧪 Testing Deployment

### Local Testing
```bash
# Start local node
anvil

# Deploy to local network
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Testnet Deployment
```bash
# Deploy to Sepolia
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify

# Deploy to Goerli
forge script script/Deploy.s.sol --rpc-url $GOERLI_RPC --broadcast --verify
```

### Mainnet Deployment
```bash
# Deploy to mainnet (use --slow flag for better gas estimation)
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC --broadcast --verify --slow
```

## 🔍 Verification

The deployment script automatically verifies:
- ✅ All contracts deployed successfully
- ✅ Poseidon4 set in MerkleTreeManager4
- ✅ RollupBridge set in MerkleTreeManager4
- ✅ MerkleTreeManager4 set in RollupBridge

## 📋 Post-Deployment Steps

1. **Save deployed addresses** from the deployment output
2. **Verify contracts** on block explorer
3. **Authorize channel creators**:
   ```solidity
   RollupBridge.authorizeCreator(address)
   ```
4. **Test bridge functionality** with small amounts first

## 🚨 Important Notes

- **Private Key Security**: Never commit your `.env` file to version control
- **Gas Limits**: Ensure your network has sufficient gas limits
- **Verification**: Use `--verify` flag for automatic contract verification
- **Testing**: Always test on testnet before mainnet deployment

## 🆘 Troubleshooting

### Common Issues

1. **Insufficient Gas**
   - Increase gas limit in foundry.toml
   - Use `--slow` flag for better gas estimation

2. **Contract Verification Fails**
   - Check that all dependencies are verified
   - Ensure correct compiler version

3. **Deployment Reverts**
   - Check environment variables
   - Verify ZK verifier address is correct
   - Ensure sufficient balance for deployment

### Getting Help

- Check the Foundry documentation
- Review contract logs for specific error messages
- Ensure all environment variables are set correctly

## 📚 Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
