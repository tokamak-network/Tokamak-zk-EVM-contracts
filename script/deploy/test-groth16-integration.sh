#!/bin/bash

# Script to test Groth16 integration
# Usage: ./test-groth16-integration.sh [--verify]

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
required_vars=("PRIVATE_KEY" "RPC_URL")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: Environment variable $var is not set${NC}"
        exit 1
    fi
done

echo -e "${YELLOW}=== Test Groth16 Integration Script ===${NC}"
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

# Run the script
echo -e "${YELLOW}Starting TestGroth16Integration script...${NC}"
forge script script/deploy/TestGroth16Integration.s.sol:TestGroth16IntegrationScript \
    --rpc-url $RPC_URL \
    --broadcast \
    --gas-limit 3000000 \
    $VERIFY_FLAG

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ TestGroth16Integration script completed successfully!${NC}"
else
    echo -e "${RED}❌ TestGroth16Integration script failed${NC}"
    exit 1
fi