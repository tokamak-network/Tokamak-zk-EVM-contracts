#!/bin/bash

# Deploy and verify TokamakVerifier script
# Usage: ./script/deploy-tokamak-verifier.sh [network]
# Example: ./script/deploy-tokamak-verifier.sh sepolia

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default network
NETWORK=${1:-sepolia}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  TokamakVerifier Deployment Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Network: ${YELLOW}$NETWORK${NC}"
echo ""

# Load environment variables
if [ -f .env ]; then
    echo -e "${GREEN}Loading environment variables from .env${NC}"
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Validate required environment variables
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set in .env${NC}"
    exit 1
fi

if [ -z "$RPC_URL" ]; then
    echo -e "${RED}Error: RPC_URL not set in .env${NC}"
    exit 1
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo -e "${YELLOW}Warning: ETHERSCAN_API_KEY not set - verification will be skipped${NC}"
    VERIFY_CONTRACTS=false
else
    VERIFY_CONTRACTS=true
fi

# Set chain-specific RPC URL if needed
case $NETWORK in
    sepolia)
        if [ -z "$SEPOLIA_RPC_URL" ]; then
            DEPLOY_RPC_URL=$RPC_URL
        else
            DEPLOY_RPC_URL=$SEPOLIA_RPC_URL
        fi
        ;;
    mainnet)
        if [ -z "$MAINNET_RPC_URL" ]; then
            DEPLOY_RPC_URL=$RPC_URL
        else
            DEPLOY_RPC_URL=$MAINNET_RPC_URL
        fi
        ;;
    *)
        DEPLOY_RPC_URL=$RPC_URL
        ;;
esac

echo -e "${GREEN}Configuration:${NC}"
echo -e "  RPC URL: ${DEPLOY_RPC_URL}"
echo -e "  Verification: ${VERIFY_CONTRACTS}"
echo -e "  Deployer: ${DEPLOYER_ADDRESS:-Auto-detected from private key}"
echo ""

# Deploy the contract
echo -e "${BLUE}Deploying TokamakVerifier...${NC}"
VERIFY_CONTRACTS=$VERIFY_CONTRACTS forge script script/DeployTokamakVerifier.s.sol \
    --rpc-url $DEPLOY_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvv

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Deployment Successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # Extract the deployed address from the broadcast log
    BROADCAST_DIR="broadcast/DeployTokamakVerifier.s.sol"
    if [ -d "$BROADCAST_DIR" ]; then
        LATEST_RUN=$(ls -t $BROADCAST_DIR | head -n1)
        RUN_LATEST_FILE="$BROADCAST_DIR/$LATEST_RUN/run-latest.json"
        
        if [ -f "$RUN_LATEST_FILE" ]; then
            echo -e "${BLUE}Extracting deployed contract address...${NC}"
            # Extract TokamakVerifier address from the broadcast log
            VERIFIER_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "TokamakVerifier") | .contractAddress' "$RUN_LATEST_FILE" 2>/dev/null || echo "")
            
            if [ ! -z "$VERIFIER_ADDRESS" ] && [ "$VERIFIER_ADDRESS" != "null" ]; then
                echo -e "${GREEN}TokamakVerifier deployed at: ${YELLOW}$VERIFIER_ADDRESS${NC}"
                
                # Save address to a file for easy reference
                echo "TOKAMAK_VERIFIER_ADDRESS=$VERIFIER_ADDRESS" > .tokamak-verifier-address
                echo -e "${GREEN}Address saved to .tokamak-verifier-address${NC}"
                
                # Show usage instructions
                echo ""
                echo -e "${BLUE}Usage Instructions:${NC}"
                echo -e "  Add this to your .env file:"
                echo -e "  ${YELLOW}ZK_VERIFIER_ADDRESS=$VERIFIER_ADDRESS${NC}"
                echo ""
                echo -e "  Or load from file:"
                echo -e "  ${YELLOW}source .tokamak-verifier-address${NC}"
            else
                echo -e "${YELLOW}Could not extract contract address from broadcast log${NC}"
            fi
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Deployment and verification complete!${NC}"
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi