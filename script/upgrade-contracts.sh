#!/bin/bash

# UUPS Contract Upgrade Script
# Usage: ./upgrade-contracts.sh <network> [options]
# Example: ./upgrade-contracts.sh sepolia --merkle-tree --rollup-bridge

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

# Function to show usage
show_usage() {
    echo "Usage: $0 <network> [options]"
    echo ""
    echo "Options:"
    echo "  --merkle-tree      Upgrade MerkleTreeManager4 contract"
    echo "  --rollup-bridge    Upgrade RollupBridge contract"
    echo "  --both             Upgrade both contracts (default if no specific option given)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 sepolia --both"
    echo "  $0 mainnet --merkle-tree"
    echo "  $0 arbitrum --rollup-bridge"
    echo ""
    echo "Required environment variables:"
    echo "  PRIVATE_KEY                   - Private key for deployment"
    echo "  ROLLUP_BRIDGE_PROXY_ADDRESS  - Address of RollupBridge proxy"
    echo "  DEPLOYER_ADDRESS             - Address of contract owner"
    echo "  RPC_URL                      - RPC endpoint"
    echo "  CHAIN_ID                     - Chain ID"
    echo ""
    echo "Optional environment variables:"
    echo "  VERIFY_CONTRACTS             - Verify contracts (default: true)"
    echo "  ETHERSCAN_API_KEY           - Etherscan API key for verification"
}

# Check if network argument is provided
if [ $# -eq 0 ]; then
    print_error "Please provide a network name"
    show_usage
    exit 1
fi

# Check for help flag
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

NETWORK=$1
shift

# Parse options
UPGRADE_MERKLE_TREE=false
UPGRADE_ROLLUP_BRIDGE=false
DEFAULT_BOTH=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --merkle-tree)
            UPGRADE_MERKLE_TREE=true
            DEFAULT_BOTH=false
            shift
            ;;
        --rollup-bridge)
            UPGRADE_ROLLUP_BRIDGE=true
            DEFAULT_BOTH=false
            shift
            ;;
        --both)
            UPGRADE_MERKLE_TREE=true
            UPGRADE_ROLLUP_BRIDGE=true
            DEFAULT_BOTH=false
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# If no specific upgrade options were given, upgrade both
if [ "$DEFAULT_BOTH" = true ]; then
    UPGRADE_MERKLE_TREE=true
    UPGRADE_ROLLUP_BRIDGE=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_status "Starting UUPS contract upgrade on $NETWORK"

# Check if .env file exists
ENV_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    print_error ".env file not found in project root"
    echo "Please create a .env file with the required environment variables"
    show_usage
    exit 1
fi

print_success "Found .env file"

# Source the environment variables
source "$ENV_FILE"

# Validate required environment variables
required_vars=("PRIVATE_KEY" "DEPLOYER_ADDRESS" "RPC_URL" "CHAIN_ID")


if [ "$UPGRADE_ROLLUP_BRIDGE" = true ]; then
    required_vars+=("ROLLUP_BRIDGE_PROXY_ADDRESS")
fi

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

# Set upgrade flags
export UPGRADE_MERKLE_TREE=$UPGRADE_MERKLE_TREE
export UPGRADE_ROLLUP_BRIDGE=$UPGRADE_ROLLUP_BRIDGE

# Build the forge command
FORGE_CMD="forge script script/UpgradeContracts.s.sol:UpgradeContractsScript"
FORGE_CMD="$FORGE_CMD --rpc-url $RPC_URL"
FORGE_CMD="$FORGE_CMD --broadcast"
FORGE_CMD="$FORGE_CMD --slow" # Add delay between transactions

# Add verification if enabled and API key is provided
if [ "$VERIFY_CONTRACTS" = "true" ] && [ -n "$ETHERSCAN_API_KEY" ]; then
    print_status "Contract verification enabled"
    FORGE_CMD="$FORGE_CMD --verify --etherscan-api-key $ETHERSCAN_API_KEY"
else
    print_warning "Contract verification disabled or API key not provided"
fi

print_status "Upgrade configuration:"
echo "  Network: $NETWORK"
echo "  RPC URL: $RPC_URL"
echo "  Chain ID: $CHAIN_ID"
echo "  Deployer (Owner): $DEPLOYER_ADDRESS"

if [ "$UPGRADE_ROLLUP_BRIDGE" = true ]; then
    echo "  RollupBridge proxy: $ROLLUP_BRIDGE_PROXY_ADDRESS"
fi

echo "  Upgrade MerkleTree: $UPGRADE_MERKLE_TREE"
echo "  Upgrade RollupBridge: $UPGRADE_ROLLUP_BRIDGE"
echo "  Verify Contracts: $VERIFY_CONTRACTS"

# Confirmation with extra warning for mainnet
echo ""
if [[ "$NETWORK" =~ ^(mainnet|ethereum|eth)$ ]]; then
    print_warning "⚠️  MAINNET UPGRADE DETECTED ⚠️"
    print_warning "This will upgrade contracts on MAINNET!"
    print_warning "Make sure you have tested on testnet first!"
    echo ""
    read -p "Are you absolutely sure you want to upgrade on MAINNET? Type 'YES' to continue: " -r
    if [[ $REPLY != "YES" ]]; then
        print_warning "Upgrade cancelled"
        exit 0
    fi
else
    read -p "Do you want to proceed with the upgrade? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Upgrade cancelled"
        exit 0
    fi
fi

# Create broadcast directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/broadcast"

print_status "Starting upgrade..."
print_status "Command: $FORGE_CMD"

# Run the upgrade
cd "$PROJECT_ROOT"
if eval $FORGE_CMD; then
    print_success "Upgrade completed successfully!"
    
    # Extract deployment addresses from broadcast files
    BROADCAST_DIR="$PROJECT_ROOT/broadcast/UpgradeContracts.s.sol/$CHAIN_ID"
    LATEST_RUN="$BROADCAST_DIR/run-latest.json"
    
    if [ -f "$LATEST_RUN" ]; then
        print_status "Extracting upgrade information..."
        
        # Parse JSON to extract addresses (requires jq)
        if command -v jq &> /dev/null; then
            echo ""
            echo "=== UPGRADE SUMMARY ==="
            
            # Try to extract addresses from the broadcast file
            echo "New implementation contracts:"
            jq -r '.transactions[] | select(.transactionType == "CREATE" or .transactionType == "CREATE2") | "  \(.contractName // "Contract"): \(.contractAddress)"' "$LATEST_RUN" 2>/dev/null || {
                print_warning "Could not parse implementation addresses automatically"
                echo "Please check the broadcast file: $LATEST_RUN"
            }
            
            echo "===================="
        else
            print_warning "jq not installed - cannot parse upgrade addresses automatically"
            print_status "Check broadcast file for addresses: $LATEST_RUN"
        fi
        
        # Save upgrade info
        UPGRADE_INFO="$PROJECT_ROOT/upgrades-$NETWORK-$(date +%Y%m%d-%H%M%S).json"
        cp "$LATEST_RUN" "$UPGRADE_INFO"
        print_success "Upgrade info saved to: $UPGRADE_INFO"
        
    else
        print_warning "Broadcast file not found, upgrade may have failed"
    fi
    
    echo ""
    print_success "Next steps:"
    echo "1. Test all contract functionality thoroughly"
    echo "2. Verify that all state is preserved correctly"
    echo "3. Monitor contracts for any issues"
    echo "4. Update any off-chain systems if needed"
    echo "5. Announce the upgrade to users if appropriate"
    
    print_warning "Important reminders:"
    echo "- Proxy addresses remain the same for user interactions"
    echo "- Only implementation addresses have changed"
    echo "- All existing state should be preserved"
    
else
    print_error "Upgrade failed!"
    echo "Check the error messages above for details"
    exit 1
fi