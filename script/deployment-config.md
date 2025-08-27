# Deployment Configuration Guide

## Required Environment Variables

Create a `.env` file in the project root with the following variables:

```bash
# Private key of the deployer account (without 0x prefix)
PRIVATE_KEY=your_private_key_here

# RPC URL for the target network
RPC_URL=https://your-rpc-endpoint.com

# Address of the ZK Verifier contract
ZK_VERIFIER_ADDRESS=0x...

# Address of the deployer account (optional, will be derived from private key)
DEPLOYER_ADDRESS=0x...

# Optional: Chain ID for verification
CHAIN_ID=1
```

## Deployment Steps

### 1. Prepare Environment
```bash
# Copy environment template
cp .env.example .env

# Edit .env with your values
nano .env
```

### 2. Deploy Contracts
```bash
# Deploy to local network (for testing)
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# Deploy to mainnet
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify --slow
```

### 3. Verify Deployment
The script will automatically verify:
- All contracts are deployed successfully
- Poseidon4 is set in MerkleTreeManager4
- RollupBridge is set in MerkleTreeManager4
- MerkleTreeManager4 is set in RollupBridge

### 4. Post-Deployment Setup
After deployment, you may need to:
1. Authorize channel creators: `RollupBridge.authorizeCreator(address)`
2. Verify contracts on block explorer
3. Test bridge functionality

## Contract Dependencies

The deployment order is:
1. **Poseidon4** - No dependencies
2. **MerkleTreeManager4** - Depends on Poseidon4
3. **RollupBridge** - Depends on MerkleTreeManager4 and ZK Verifier

## Gas Estimation

Estimated gas costs:
- Poseidon4: ~500,000 gas
- MerkleTreeManager4: ~800,000 gas  
- RollupBridge: ~600,000 gas
- Configuration calls: ~100,000 gas

**Total: ~2,000,000 gas**
