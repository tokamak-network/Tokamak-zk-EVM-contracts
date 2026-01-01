#!/bin/bash

# Script to upgrade BridgeCore contract
# Usage: ./upgrade-bridge-core.sh [--verify]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please create a .env file with the required environment variables"
    exit 1
fi

# Source environment variables
source .env

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
    
    # Check if --verify flag is passed and perform contract verification
    if [ "$SHOULD_VERIFY" = true ]; then
        echo -e "${YELLOW}Starting contract verification...${NC}"
        
        # Extract implementation address from script output
        IMPL_ADDRESS=$(echo "$SCRIPT_OUTPUT" | grep "VERIFY_IMPL_ADDRESS:" | awk '{print $2}')
        
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