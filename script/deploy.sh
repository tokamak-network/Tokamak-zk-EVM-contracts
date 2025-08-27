#!/bin/bash

# Deployment script for Tokamak zkEVM contracts
# Make sure you have a .env file with the required variables

set -e

echo "🚀 Starting Tokamak zkEVM deployment..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create a .env file with the required variables:"
    echo "  - PRIVATE_KEY"
    echo "  - RPC_URL" 
    echo "  - ZK_VERIFIER_ADDRESS"
    echo "  - DEPLOYER_ADDRESS (optional)"
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY not set in .env"
    exit 1
fi

if [ -z "$RPC_URL" ]; then
    echo "❌ Error: RPC_URL not set in .env"
    exit 1
fi

if [ -z "$ZK_VERIFIER_ADDRESS" ]; then
    echo "❌ Error: ZK_VERIFIER_ADDRESS not set in .env"
    exit 1
fi

echo "✅ Environment variables loaded"
echo "📡 RPC URL: $RPC_URL"
echo "🔑 ZK Verifier: $ZK_VERIFIER_ADDRESS"

# Check verification settings
if [ "$VERIFY_CONTRACTS" = "true" ]; then
    if [ -n "$ETHERSCAN_API_KEY" ]; then
        echo "🔍 Contract verification: ENABLED"
        echo "🔑 Etherscan API Key: ${ETHERSCAN_API_KEY:0:8}..."
    else
        echo "⚠️  Contract verification: DISABLED (no API key)"
        echo "   Set ETHERSCAN_API_KEY to enable verification"
    fi
else
    echo "🔍 Contract verification: DISABLED"
fi

# Build the project
echo "🔨 Building contracts..."
forge build

# Deploy contracts
echo "🚀 Deploying contracts..."

# Build command with conditional verification
if [ "$VERIFY_CONTRACTS" = "true" ] && [ -n "$ETHERSCAN_API_KEY" ]; then
    echo "🔍 Deploying with contract verification..."
    forge script script/Deploy.s.sol \
        --rpc-url "$RPC_URL" \
        --broadcast \
        --verify
else
    echo "📝 Deploying without contract verification..."
    forge script script/Deploy.s.sol \
        --rpc-url "$RPC_URL" \
        --broadcast
fi

echo "✅ Deployment completed!"
echo "📋 Check the broadcast/ directory for deployment details"
