# Deploy Scripts

This folder contains all deployment scripts for the Tokamak zk-EVM bridge system.

## Available Deployment Scripts

### Solidity Scripts (.sol)

1. **DeployV2.s.sol** - Main deployment script for V2 contracts
2. **DeployTokamakVerifier.s.sol** - Deploys TokamakVerifier contract
3. **RegisterFunction.s.sol** - Registers functions in deployed contracts
4. **SetChannelPublicKey.s.sol** - Sets channel public keys
5. **TestGroth16Integration.s.sol** - Tests Groth16 integration

### Shell Scripts (.sh)

1. **deploy-v2.sh** - Executes main V2 deployment
2. **deploy-tokamak-verifier.sh** - Executes TokamakVerifier deployment
3. **register-function.sh** - Executes function registration
4. **set-channel-public-key.sh** - Executes channel public key setup
5. **test-groth16-integration.sh** - Executes Groth16 integration tests

## Configuration Files

- **env-v2.template** - Template for environment variables needed for V2 deployment

## Usage

### Prerequisites

1. Copy the environment template and configure it:
   ```bash
   cp env-v2.template .env
   # Edit .env with your specific values
   ```

2. Make sure you have all required environment variables set:
   ```bash
   PRIVATE_KEY=your_private_key_here
   RPC_URL=your_rpc_url_here
   ETHERSCAN_API_KEY=your_etherscan_api_key_here  # Optional, for verification
   
   # Add other deployment-specific variables as needed
   ```

### Running Deployments

```bash
# Navigate to the deploy directory
cd script/deploy

# Run main V2 deployment
./deploy-v2.sh --verify

# Deploy TokamakVerifier
./deploy-tokamak-verifier.sh --verify

# Register functions
./register-function.sh

# Set channel public key
./set-channel-public-key.sh

# Test Groth16 integration
./test-groth16-integration.sh
```

## Important Notes

1. **Environment Setup**: Always ensure your `.env` file is properly configured before running any deployment scripts.

2. **Network Configuration**: Make sure `RPC_URL` points to the correct network (testnet for testing, mainnet for production).

3. **Verification**: Use the `--verify` flag to automatically verify contracts on Etherscan.

4. **Gas Costs**: Deployment can be expensive on mainnet. Test thoroughly on testnet first.

5. **Security**: Never commit your `.env` file with real private keys to version control.

## Script Features

All shell scripts include:
- Environment validation
- Color-coded output for better readability
- Error handling with proper exit codes
- Optional contract verification
- Gas limit configuration
- Success/failure reporting