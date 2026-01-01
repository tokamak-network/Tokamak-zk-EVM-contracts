#!/bin/bash

# Script to upgrade BridgeAdminManager contract
# Usage: ./upgrade-bridge-admin-manager.sh [--verify]

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
required_vars=("PRIVATE_KEY" "ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS" "DEPLOYER_ADDRESS" "RPC_URL")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: Environment variable $var is not set${NC}"
        exit 1
    fi
done

# Set default values for verification variables if not set
export VERIFY_CONTRACTS=${VERIFY_CONTRACTS:-false}
export CHAIN_ID=${CHAIN_ID:-11155111}

echo -e "${YELLOW}=== BridgeAdminManager Upgrade Script ===${NC}"
echo "Proxy Address: $ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS"
echo "Deployer: $DEPLOYER_ADDRESS"
echo "RPC URL: $RPC_URL"
echo ""

# Check if --verify flag is passed
VERIFY_FLAG=""
if [ "$1" = "--verify" ]; then
    if [ -z "$ETHERSCAN_API_KEY" ]; then
        echo -e "${RED}Error: ETHERSCAN_API_KEY is required for verification${NC}"
        exit 1
    fi
    VERIFY_FLAG="--verify"
    echo -e "${YELLOW}Contract verification enabled${NC}"
fi

# Run the upgrade script
echo -e "${YELLOW}Starting BridgeAdminManager upgrade...${NC}"
forge script script/upgrade/UpgradeBridgeAdminManager.s.sol:UpgradeBridgeAdminManagerScript \
    --rpc-url $RPC_URL \
    --broadcast \
    --gas-limit 10000000 \
    $VERIFY_FLAG

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ BridgeAdminManager upgrade completed successfully!${NC}"
    
    # Check if --verify flag is passed and perform contract verification
    if [ "$1" = "--verify" ]; then
        echo -e "${YELLOW}Starting contract verification...${NC}"
        
        # Find the most recent upgrade addresses file
        ADDRESSES_FILE=$(ls -t upgrade_addresses_*.txt 2>/dev/null | head -n1)
        
        if [ -f "$ADDRESSES_FILE" ]; then
            source $ADDRESSES_FILE
            
            if [ -n "$BRIDGE_ADMIN_MANAGER_IMPL" ]; then
                echo "Verifying BridgeAdminManager implementation at: $BRIDGE_ADMIN_MANAGER_IMPL"
                
                forge verify-contract $BRIDGE_ADMIN_MANAGER_IMPL \
                    src/BridgeAdminManager.sol:BridgeAdminManager \
                    --chain-id $CHAIN_ID \
                    --etherscan-api-key $ETHERSCAN_API_KEY \
                    --watch
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ BridgeAdminManager implementation verified on Etherscan!${NC}"
                else
                    echo -e "${RED}❌ Contract verification failed${NC}"
                fi
            else
                echo -e "${RED}❌ Could not find BRIDGE_ADMIN_MANAGER_IMPL address${NC}"
            fi
            
            # Clean up the addresses file
            rm -f $ADDRESSES_FILE
        else
            echo -e "${RED}❌ Could not find upgrade addresses file${NC}"
        fi
    fi
else
    echo -e "${RED}❌ BridgeAdminManager upgrade failed${NC}"
    exit 1
fi