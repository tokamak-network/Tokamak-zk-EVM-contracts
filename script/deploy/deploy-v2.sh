#!/bin/bash

# RollupBridgeV2 Deployment Script
# Usage: ./deploy-v2.sh <network>
# Example: ./deploy-v2.sh sepolia

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if network argument is provided
if [ $# -eq 0 ]; then
    print_error "Please provide a network name"
    echo "Usage: $0 <network>"
    echo "Examples:"
    echo "  $0 sepolia"
    echo "  $0 mainnet"
    echo "  $0 arbitrum"
    exit 1
fi

NETWORK=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

print_status "Starting RollupBridgeV2 deployment on $NETWORK"

# Check if .env file exists
ENV_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    print_error ".env file not found in project root"
    echo "Please create a .env file using the template:"
    echo "cp script/env-v2.template .env"
    echo "Then edit .env with your configuration"
    exit 1
fi

print_success "Found .env file"

# Source the environment variables
source "$ENV_FILE"

# Validate required environment variables
required_vars=("PRIVATE_KEY" "ZK_VERIFIER_ADDRESS" "DEPLOYER_ADDRESS" "RPC_URL" "CHAIN_ID")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    print_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

print_success "All required environment variables are set"

# Set default values for optional variables  
export VERIFY_CONTRACTS=${VERIFY_CONTRACTS:-true}
export ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY:-""}

# Build the forge command
FORGE_CMD="forge script script/deploy/DeployV2.s.sol:DeployV2Script"
FORGE_CMD="$FORGE_CMD --rpc-url $RPC_URL"
FORGE_CMD="$FORGE_CMD --broadcast"
FORGE_CMD="$FORGE_CMD --slow" # Add delay between transactions
FORGE_CMD="$FORGE_CMD --ffi" # Enable FFI for contract verification

# Add verification if enabled and API key is provided
if [ "$VERIFY_CONTRACTS" = "true" ] && [ -n "$ETHERSCAN_API_KEY" ]; then
    print_status "Contract verification enabled"
    FORGE_CMD="$FORGE_CMD --verify --etherscan-api-key $ETHERSCAN_API_KEY"
else
    print_warning "Contract verification disabled or API key not provided"
fi

print_status "Deployment configuration:"
echo "  Network: $NETWORK"
echo "  RPC URL: $RPC_URL"
echo "  Chain ID: $CHAIN_ID"
echo "  Deployer: $DEPLOYER_ADDRESS"
echo "  ZK Verifier: $ZK_VERIFIER_ADDRESS"
echo "  Contract: RollupBridgeV2 (with embedded Merkle operations)"
echo "  Verify Contracts: $VERIFY_CONTRACTS"

# Confirm deployment
echo ""
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled"
    exit 0
fi

# Create broadcast directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/broadcast"

print_status "Starting deployment..."
print_status "Command: $FORGE_CMD"

# Run the deployment
cd "$PROJECT_ROOT"
if eval $FORGE_CMD; then
    print_success "Deployment completed successfully!"
    
    # Extract deployment addresses from broadcast files
    BROADCAST_DIR="$PROJECT_ROOT/broadcast/DeployV2.s.sol/$CHAIN_ID"
    LATEST_RUN="$BROADCAST_DIR/run-latest.json"
    
    if [ -f "$LATEST_RUN" ]; then
        print_status "Extracting deployment addresses..."
        
        # Parse JSON to extract addresses (requires jq)
        if command -v jq &> /dev/null; then
            echo ""
            echo "=== DEPLOYMENT SUMMARY ==="
            
            # Extract transaction receipts and find contract deployments
            echo "Deployed contracts:"
            
            # Try to extract addresses from the broadcast file
            jq -r '.transactions[] | select(.transactionType == "CREATE" or .transactionType == "CREATE2") | "  \(.contractName // "Contract"): \(.contractAddress)"' "$LATEST_RUN" 2>/dev/null || {
                print_warning "Could not parse deployment addresses automatically"
                echo "Please check the broadcast file: $LATEST_RUN"
            }
            
            echo "=========================="
        else
            print_warning "jq not installed - cannot parse deployment addresses automatically"
            print_status "Check broadcast file for addresses: $LATEST_RUN"
        fi
        
        # Save deployment info
        DEPLOYMENT_INFO="$PROJECT_ROOT/deployments-$NETWORK-$(date +%Y%m%d-%H%M%S).json"
        cp "$LATEST_RUN" "$DEPLOYMENT_INFO"
        print_success "Deployment info saved to: $DEPLOYMENT_INFO"
        
    else
        print_warning "Broadcast file not found, deployment may have failed"
    fi
    
    echo ""
    print_success "Next steps:"
    echo "1. Verify the deployed addresses"
    echo "2. Test the contracts functionality"
    echo "3. Authorize channel creators if needed"
    echo "4. Consider setting up timelock or multisig for upgrades"
    echo "5. Save the proxy addresses for future interactions"
    
else
    print_error "Deployment failed!"
    echo "Check the error messages above for details"
    exit 1
fi