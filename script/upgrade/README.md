# Upgrade Scripts

This folder contains all contract upgrade scripts for the Tokamak zk-EVM bridge system.

## Available Upgrade Scripts

### Solidity Scripts (.sol)

1. **UpgradeBridgeCore.s.sol** - Upgrades the BridgeCore contract implementation
2. **UpgradeBridgeProofManager.s.sol** - Upgrades the BridgeProofManager contract implementation  
3. **UpgradeBridgeAdminManager.s.sol** - Upgrades the BridgeAdminManager contract implementation
4. **UpgradeBridgeDepositManager.s.sol** - Upgrades the BridgeDepositManager contract implementation
5. **UpgradeBridgeWithdrawManager.s.sol** - Upgrades the BridgeWithdrawManager contract implementation
6. **UpgradeTokamakVerifier.s.sol** - Upgrades the TokamakVerifier contract implementation
7. **UpgradeContracts.s.sol** - Upgrades multiple contracts in a single transaction
8. **UpdateGroth16Verifier16.s.sol** - Updates the Groth16Verifier16 contract

### Shell Scripts (.sh)

Each Solidity script has a corresponding shell script for easy execution:

1. **upgrade-bridge-core.sh** - Executes BridgeCore upgrade
2. **upgrade-bridge-proof-manager.sh** - Executes BridgeProofManager upgrade
3. **upgrade-bridge-admin-manager.sh** - Executes BridgeAdminManager upgrade
4. **upgrade-bridge-deposit-manager.sh** - Executes BridgeDepositManager upgrade
5. **upgrade-bridge-withdraw-manager.sh** - Executes BridgeWithdrawManager upgrade
6. **upgrade-tokamak-verifier.sh** - Executes TokamakVerifier upgrade
7. **upgrade-contracts.sh** - Executes multiple contract upgrades
8. **update-groth16-verifier16.sh** - Executes Groth16Verifier16 update

## Usage

### Prerequisites

1. Make sure you have a `.env` file in the project root with the required environment variables:
   ```bash
   PRIVATE_KEY=your_private_key_here
   RPC_URL=your_rpc_url_here
   ETHERSCAN_API_KEY=your_etherscan_api_key_here  # Optional, for verification
   
   # Proxy addresses for individual upgrades
   ROLLUP_BRIDGE_CORE_PROXY_ADDRESS=0x...
   ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS=0x...
   ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS=0x...
   ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS=0x...
   ROLLUP_BRIDGE_WITHDRAW_MANAGER_PROXY_ADDRESS=0x...
   TOKAMAK_VERIFIER_PROXY_ADDRESS=0x...
   
   # Additional variables for specific scripts
   DEPLOYER_ADDRESS=0x...  # Required for BridgeProofManager upgrade
   CHAIN_ID=11155111       # Optional, defaults to Sepolia
   VERIFY_CONTRACTS=false  # Optional, for BridgeProofManager script
   ```

### Running Individual Upgrades

To upgrade a specific contract:

```bash
# Navigate to the upgrade directory
cd script/upgrade

# Run individual upgrade (without verification)
./upgrade-bridge-core.sh

# Run with contract verification
./upgrade-bridge-core.sh sepolia --verify
```

### Running Multiple Upgrades

To upgrade all contracts at once:

```bash
cd script/upgrade
./upgrade-contracts.sh sepolia --verify
```

## Important Notes

1. **Proxy Addresses**: Each upgrade script targets a specific proxy address. Make sure the correct proxy addresses are set in your `.env` file.

2. **Verification**: Use the `--verify` flag to automatically verify contracts on Etherscan. This requires `ETHERSCAN_API_KEY` to be set.

3. **Gas Limits**: All scripts use a default gas limit of 3,000,000. Adjust if needed based on network conditions.

4. **Permissions**: The account associated with `PRIVATE_KEY` must have upgrade permissions (usually the owner) for the contracts being upgraded.

5. **Testing**: Always test upgrades on testnet before deploying to mainnet.

## Script Structure

Each shell script follows this pattern:
- Environment validation
- Color-coded output for better readability
- Error handling with proper exit codes
- Optional contract verification
- Success/failure reporting

## Troubleshooting

1. **Environment Variable Errors**: Make sure all required environment variables are set in your `.env` file.

2. **Permission Errors**: Ensure the deployer account has the necessary permissions to upgrade the contracts.

3. **Gas Estimation Errors**: Try increasing the gas limit or check network conditions.

4. **Verification Failures**: Ensure `ETHERSCAN_API_KEY` is valid and the network supports verification.