#!/bin/bash

# Script to upgrade BridgeCore contract
# Usage: ./upgrade-bridge-core.sh [--verify]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to update or create contracts JSON
update_contracts_json() {
    local contract_name="$1"
    local contract_address="$2"
    local network="$3"
    local source_file="$4"
    local is_upgrade="${5:-false}"
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}jq not installed - cannot update contracts JSON${NC}"
        return 1
    fi
    
    local contracts_json="$PROJECT_ROOT/contracts-$network.json"
    
    # Get ABI from forge artifacts
    local abi_file="$PROJECT_ROOT/out/${source_file##*/}/${contract_name}.json"
    local abi="[]"
    
    if [ -f "$abi_file" ]; then
        abi=$(jq -c '.abi' "$abi_file" 2>/dev/null || echo "[]")
    fi
    
    # Create or update JSON file
    if [ -f "$contracts_json" ]; then
        # Update existing JSON
        if [ "$is_upgrade" = "true" ]; then
            # For upgrades, update the implementation address but keep proxy info
            jq --arg name "$contract_name" \
               --arg impl_addr "$contract_address" \
               --argjson abi "$abi" \
               --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
               'if .contracts[$name] then 
                  .contracts[$name].implementationAddress = $impl_addr | 
                  .contracts[$name].abi = $abi |
                  .contracts[$name].lastUpgraded = $date
                else 
                  .contracts[$name] = {implementationAddress: $impl_addr, abi: $abi, lastUpgraded: $date}
                end | .lastUpdated = $date' \
               "$contracts_json" > "${contracts_json}.tmp" && mv "${contracts_json}.tmp" "$contracts_json"
        else
            # For regular deployments
            jq --arg name "$contract_name" \
               --arg addr "$contract_address" \
               --argjson abi "$abi" \
               --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
               '.contracts[$name] = {address: $addr, abi: $abi} | .lastUpdated = $date' \
               "$contracts_json" > "${contracts_json}.tmp" && mv "${contracts_json}.tmp" "$contracts_json"
        fi
        echo -e "${GREEN}Updated existing contracts JSON: $contracts_json${NC}"
    else
        # Create new JSON
        if [ "$is_upgrade" = "true" ]; then
            cat > "$contracts_json" << EOF
{
  "network": "$network",
  "deploymentDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "lastUpdated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "contracts": {
    "$contract_name": {
      "implementationAddress": "$contract_address",
      "abi": $abi,
      "lastUpgraded": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    }
  }
}
EOF
        else
            cat > "$contracts_json" << EOF
{
  "network": "$network",
  "deploymentDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "lastUpdated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "contracts": {
    "$contract_name": {
      "address": "$contract_address",
      "abi": $abi
    }
  }
}
EOF
        fi
        echo -e "${GREEN}Created new contracts JSON: $contracts_json${NC}"
    fi
}

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Check if .env file exists
ENV_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env file not found in project root${NC}"
    echo "Please create a .env file with the required environment variables"
    exit 1
fi

# Source environment variables
source "$ENV_FILE"

# Verify required environment variables
required_vars=("PRIVATE_KEY" "ROLLUP_BRIDGE_CORE_PROXY_ADDRESS" "DEPLOYER_ADDRESS" "RPC_URL")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: Environment variable $var is not set${NC}"
        exit 1
    fi
done

# Set default values for verification variables if not set
export VERIFY_CONTRACTS=${VERIFY_CONTRACTS:-false}
export CHAIN_ID=${CHAIN_ID:-11155111}

echo -e "${YELLOW}=== BridgeCore Upgrade Script ===${NC}"
echo "Proxy Address: $ROLLUP_BRIDGE_CORE_PROXY_ADDRESS"
echo "Deployer: $DEPLOYER_ADDRESS"
echo "RPC URL: $RPC_URL"
echo ""

# Check if --verify flag is passed
VERIFY_FLAG=""
SHOULD_VERIFY=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --verify)
            SHOULD_VERIFY=true
            VERIFY_FLAG="--verify"
            ;;
        sepolia|mainnet|arbitrum|optimism)
            # Network names are ignored - we use RPC_URL from .env
            ;;
        *)
            echo -e "${YELLOW}Unknown argument: $arg${NC}"
            ;;
    esac
done

if [ "$SHOULD_VERIFY" = true ]; then
    if [ -z "$ETHERSCAN_API_KEY" ]; then
        echo -e "${RED}Error: ETHERSCAN_API_KEY is required for verification${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Contract verification enabled${NC}"
fi

# Run the upgrade script and capture output
echo -e "${YELLOW}Starting BridgeCore upgrade...${NC}"
SCRIPT_OUTPUT=$(forge script script/upgrade/UpgradeBridgeCore.s.sol:UpgradeBridgeCoreScript \
    --rpc-url $RPC_URL \
    --broadcast \
    --gas-limit 10000000 \
    $VERIFY_FLAG 2>&1)

SCRIPT_EXIT_CODE=$?
echo "$SCRIPT_OUTPUT"

if [ $SCRIPT_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ BridgeCore upgrade completed successfully!${NC}"
    
    # Extract implementation address from script output
    IMPL_ADDRESS=$(echo "$SCRIPT_OUTPUT" | grep "VERIFY_IMPL_ADDRESS:" | awk '{print $2}')
    
    # Update contracts JSON file with new implementation
    if [ -n "$IMPL_ADDRESS" ]; then
        NETWORK=${NETWORK:-"unknown"}
        echo -e "${YELLOW}Updating contracts JSON...${NC}"
        update_contracts_json "BridgeCore" "$IMPL_ADDRESS" "$NETWORK" "src/BridgeCore.sol" "true"
    fi
    
    # Check if --verify flag is passed and perform contract verification
    if [ "$SHOULD_VERIFY" = true ]; then
        echo -e "${YELLOW}Starting contract verification...${NC}"
        
        if [ -n "$IMPL_ADDRESS" ]; then
            echo "Verifying BridgeCore implementation at: $IMPL_ADDRESS"
            
            forge verify-contract $IMPL_ADDRESS \
                src/BridgeCore.sol:BridgeCore \
                --chain-id $CHAIN_ID \
                --etherscan-api-key $ETHERSCAN_API_KEY \
                --watch
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ BridgeCore implementation verified on Etherscan!${NC}"
            else
                echo -e "${RED}❌ Contract verification failed${NC}"
            fi
        else
            echo -e "${RED}❌ Could not extract implementation address from script output${NC}"
        fi
    fi
else
    echo -e "${RED}❌ BridgeCore upgrade failed${NC}"
    exit 1
fi