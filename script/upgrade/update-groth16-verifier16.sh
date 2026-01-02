#!/bin/bash

# Script to update Groth16Verifier16 contract
# Usage: ./update-groth16-verifier16.sh [--verify]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
required_vars=("PRIVATE_KEY" "RPC_URL")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: Environment variable $var is not set${NC}"
        exit 1
    fi
done

echo -e "${YELLOW}=== Update Groth16Verifier16 Script ===${NC}"
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
echo -e "${YELLOW}Starting UpdateGroth16Verifier16 script...${NC}"
forge script script/upgrade/UpdateGroth16Verifier16.s.sol:UpdateGroth16Verifier16Script \
    --rpc-url $RPC_URL \
    --broadcast \
    --gas-limit 3000000 \
    $VERIFY_FLAG

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ UpdateGroth16Verifier16 script completed successfully!${NC}"
else
    echo -e "${RED}❌ UpdateGroth16Verifier16 script failed${NC}"
    exit 1
fi