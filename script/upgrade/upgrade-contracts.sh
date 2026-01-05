#!/bin/bash

# Bridge Contracts Upgrade Script
# Usage: ./upgrade-contracts.sh <network>
# Example: ./upgrade-contracts.sh sepolia

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

# Function to generate comprehensive contracts JSON for upgrades
generate_upgrade_contracts_json() {
    local broadcast_file="$1"
    local output_file="$2"
    local network="$3"
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq not installed - cannot generate contracts JSON"
        return 1
    fi
    
    # Contract names and their corresponding source files for upgrade
    local contracts=(
        "BridgeCore:src/BridgeCore.sol"
        "BridgeDepositManager:src/BridgeDepositManager.sol"
        "BridgeProofManager:src/BridgeProofManager.sol"
        "BridgeWithdrawManager:src/BridgeWithdrawManager.sol"
        "BridgeAdminManager:src/BridgeAdminManager.sol"
    )
    
    # Start building the JSON
    cat > "$output_file" << EOF
{
  "network": "$network",
  "upgradeDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "proxyAddresses": {
    "BridgeCore": "$ROLLUP_BRIDGE_CORE_PROXY_ADDRESS",
    "BridgeDepositManager": "$ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS",
    "BridgeProofManager": "$ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS",
    "BridgeWithdrawManager": "$ROLLUP_BRIDGE_WITHDRAW_MANAGER_PROXY_ADDRESS",
    "BridgeAdminManager": "$ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS"
  },
  "newImplementations": {
EOF

    local first_contract=true
    
    # Extract new implementation addresses from broadcast file and match with ABIs
    for contract_info in "${contracts[@]}"; do
        local contract_name="${contract_info%%:*}"
        local source_file="${contract_info##*:}"
        
        # Get contract address from broadcast file
        local address=$(jq -r --arg name "$contract_name" '
            .transactions[] | 
            select(.transactionType == "CREATE" or .transactionType == "CREATE2") |
            select(.contractName == $name) |
            .contractAddress' "$broadcast_file" 2>/dev/null | head -1)
        
        if [ "$address" != "null" ] && [ -n "$address" ]; then
            # Add comma for all but first contract
            if [ "$first_contract" = false ]; then
                echo "    ," >> "$output_file"
            fi
            first_contract=false
            
            # Get ABI from forge artifacts
            local abi_file="$PROJECT_ROOT/out/${contract_name}.sol/${contract_name}.json"
            local abi="[]"
            
            if [ -f "$abi_file" ]; then
                abi=$(jq -c '.abi' "$abi_file" 2>/dev/null || echo "[]")
            fi
            
            # Add contract entry
            printf '    "%s": {\n      "address": "%s",\n      "abi": %s\n    }' \
                "$contract_name" "$address" "$abi" >> "$output_file"
        fi
    done
    
    # Close the JSON
    printf '\n  }\n}\n' >> "$output_file"

    print_success "Generated upgrade contracts JSON with $(jq '.newImplementations | length' "$output_file" 2>/dev/null || echo "unknown") implementations"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <network>"
    echo ""
    echo "This script upgrades ALL 5 bridge contracts simultaneously:"
    echo "  - BridgeCore (main bridge logic)"
    echo "  - BridgeDepositManager (handles deposits)"
    echo "  - BridgeProofManager (handles proofs and state)"
    echo "  - BridgeWithdrawManager (handles withdrawals)"
    echo "  - BridgeAdminManager (handles administration)"
    echo ""
    echo "Options:"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 sepolia"
    echo "  $0 mainnet"
    echo "  $0 arbitrum"
    echo ""
    echo "Required environment variables:"
    echo "  PRIVATE_KEY                                     - Private key for deployment"
    echo "  ROLLUP_BRIDGE_CORE_PROXY_ADDRESS               - Address of BridgeCore proxy"
    echo "  ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS     - Address of DepositManager proxy"
    echo "  ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS       - Address of ProofManager proxy"
    echo "  ROLLUP_BRIDGE_WITHDRAW_MANAGER_PROXY_ADDRESS    - Address of WithdrawManager proxy"
    echo "  ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS       - Address of AdminManager proxy"
    echo "  DEPLOYER_ADDRESS                               - Address of contract owner"
    echo "  RPC_URL                                        - RPC endpoint"
    echo "  CHAIN_ID                                       - Chain ID"
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

# Parse options (only --help is supported)
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_error "This script only accepts a network name. Use --help for usage."
            show_usage
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

print_status "Starting Bridge Contracts upgrade on $NETWORK"

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
required_vars=(
    "PRIVATE_KEY" 
    "DEPLOYER_ADDRESS" 
    "RPC_URL" 
    "CHAIN_ID"
    "ROLLUP_BRIDGE_CORE_PROXY_ADDRESS"
    "ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS"
    "ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS"
    "ROLLUP_BRIDGE_WITHDRAW_MANAGER_PROXY_ADDRESS"
    "ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS"
)

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
FORGE_CMD="forge script script/upgrade/UpgradeContracts.s.sol:UpgradeContractsScript"
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
echo ""
echo "  Bridge Contract Proxies:"
echo "    BridgeCore: $ROLLUP_BRIDGE_CORE_PROXY_ADDRESS"
echo "    DepositManager: $ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS"
echo "    ProofManager: $ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS"
echo "    WithdrawManager: $ROLLUP_BRIDGE_WITHDRAW_MANAGER_PROXY_ADDRESS"
echo "    AdminManager: $ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS"
echo ""
echo "  Verify Contracts: $VERIFY_CONTRACTS"

# Confirmation with extra warning for mainnet
echo ""
if [[ "$NETWORK" =~ ^(mainnet|ethereum|eth)$ ]]; then
    print_warning "⚠️  MAINNET BRIDGE UPGRADE DETECTED ⚠️"
    print_warning "This will upgrade ALL 5 bridge contracts on MAINNET!"
    print_warning "Make sure you have tested on testnet first!"
    print_warning "This affects BridgeCore, DepositManager, ProofManager, WithdrawManager, and AdminManager"
    echo ""
    read -p "Are you absolutely sure you want to upgrade ALL bridge contracts on MAINNET? Type 'YES' to continue: " -r
    if [[ $REPLY != "YES" ]]; then
        print_warning "Upgrade cancelled"
        exit 0
    fi
else
    print_warning "This will upgrade ALL 5 bridge contracts simultaneously"
    read -p "Do you want to proceed with the bridge contracts upgrade? (y/N): " -n 1 -r
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
            echo "New bridge implementation contracts:"
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
        
        # Generate single comprehensive JSON with all contract info
        print_status "Generating comprehensive upgrade JSON with addresses and ABIs..."
        
        # Create output directory
        OUTPUT_DIR="$PROJECT_ROOT/script/output"
        mkdir -p "$OUTPUT_DIR"
        
        CONTRACTS_JSON="$OUTPUT_DIR/upgrade-contracts-$NETWORK-$(date +%Y%m%d-%H%M%S).json"
        
        # Create the upgrade contracts JSON
        generate_upgrade_contracts_json "$LATEST_RUN" "$CONTRACTS_JSON" "$NETWORK"
        
        if [ -f "$CONTRACTS_JSON" ]; then
            print_success "All upgrade contract information saved to: $CONTRACTS_JSON"
        fi
        
    else
        print_warning "Broadcast file not found, upgrade may have failed"
    fi
    
    echo ""
    print_success "Next steps:"
    echo "1. Test ALL bridge contract functionality thoroughly"
    echo "   - Test deposits, proofs, withdrawals, and admin functions"
    echo "   - Verify cross-contract interactions work correctly"
    echo "2. Verify that all state is preserved correctly across all contracts"
    echo "3. Monitor ALL 5 contracts for any issues"
    echo "4. Update any off-chain systems with new implementation addresses"
    echo "5. Announce the upgrade to users if appropriate"
    
    print_warning "Important reminders:"
    echo "- ALL 5 proxy addresses remain the same for user interactions"
    echo "- ALL 5 implementation addresses have changed simultaneously"
    echo "- All existing state should be preserved across all contracts"
    echo "- Contract interdependencies should remain intact"
    
else
    print_error "Upgrade failed!"
    echo "Check the error messages above for details"
    exit 1
fi