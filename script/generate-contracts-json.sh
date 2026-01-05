#!/bin/bash

# Generate contracts JSON from .env addresses
# Usage: ./generate-contracts-json.sh [network]
# Examples: 
#   ./generate-contracts-json.sh sepolia
#   ./generate-contracts-json.sh mainnet
#   ./generate-contracts-json.sh     # defaults to "unknown"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default network
NETWORK=${1:-"unknown"}

print_status "Generating contracts JSON from .env addresses for network: $NETWORK"

# Check if .env file exists
ENV_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    print_error ".env file not found in project root"
    echo "Please create a .env file with contract addresses"
    exit 1
fi

print_success "Found .env file"

# Source the environment variables
source "$ENV_FILE"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq not installed - cannot generate contracts JSON"
    echo "Please install jq: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Create output directory
OUTPUT_DIR="$SCRIPT_DIR/output"
mkdir -p "$OUTPUT_DIR"

# Output file
OUTPUT_FILE="$OUTPUT_DIR/contracts-$NETWORK-$(date +%Y%m%d-%H%M%S).json"

print_status "Generating JSON file: $OUTPUT_FILE"

# Function to add contract entry
add_contract() {
    local contract_name="$1"
    local address="$2"
    local abi_source="$3"
    local first_contract="$4"
    
    if [ -z "$address" ] || [ "$address" = "null" ]; then
        return 0
    fi
    
    # Add comma for all but first contract
    if [ "$first_contract" = "false" ]; then
        printf ',\n' >> "$OUTPUT_FILE"
    fi
    
    # Get ABI from forge artifacts
    local abi_file="$PROJECT_ROOT/out/${abi_source}.sol/${contract_name}.json"
    local abi="[]"
    
    if [ -f "$abi_file" ]; then
        abi=$(jq -c '.abi' "$abi_file" 2>/dev/null || echo "[]")
    else
        print_warning "ABI file not found for $contract_name: $abi_file"
    fi
    
    # Add contract entry (convert to lowercase for consistency)
    printf '    "%s": {\n      "address": "%s",\n      "abi": %s\n    }' \
        "$contract_name" "$(echo "$address" | tr '[:upper:]' '[:lower:]')" "$abi" >> "$OUTPUT_FILE"
    
    echo "false"  # Return false for next iteration
}

# Start building the JSON
printf '{\n  "network": "%s",\n  "generatedDate": "%s",\n  "source": "env_addresses",\n  "contracts": {\n' \
    "$NETWORK" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$OUTPUT_FILE"

first_contract="true"

# Direct deployment contracts (from .env)
if [ -n "$ZK_VERIFIER_ADDRESS" ]; then
    first_contract=$(add_contract "TokamakVerifier" "$ZK_VERIFIER_ADDRESS" "TokamakVerifier" "$first_contract")
fi

if [ -n "$Groth16_Verifier16" ]; then
    first_contract=$(add_contract "Groth16Verifier16Leaves" "$Groth16_Verifier16" "Groth16Verifier16Leaves" "$first_contract")
fi

if [ -n "$Groth16_Verifier32" ]; then
    first_contract=$(add_contract "Groth16Verifier32Leaves" "$Groth16_Verifier32" "Groth16Verifier32Leaves" "$first_contract")
fi

if [ -n "$Groth16_Verifier64" ]; then
    first_contract=$(add_contract "Groth16Verifier64Leaves" "$Groth16_Verifier64" "Groth16Verifier64Leaves" "$first_contract")
fi

if [ -n "$Groth16_Verifier128" ]; then
    first_contract=$(add_contract "Groth16Verifier128Leaves" "$Groth16_Verifier128" "Groth16Verifier128Leaves" "$first_contract")
fi

if [ -n "$ZEC_FROST_ADDRESS" ]; then
    first_contract=$(add_contract "ZecFrost" "$ZEC_FROST_ADDRESS" "ZecFrost" "$first_contract")
fi

# Proxy contracts (use proxy addresses with implementation ABIs)
if [ -n "$ROLLUP_BRIDGE_CORE_PROXY_ADDRESS" ]; then
    first_contract=$(add_contract "BridgeCore" "$ROLLUP_BRIDGE_CORE_PROXY_ADDRESS" "BridgeCore" "$first_contract")
fi

if [ -n "$ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS" ]; then
    first_contract=$(add_contract "BridgeDepositManager" "$ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS" "BridgeDepositManager" "$first_contract")
fi

if [ -n "$ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS" ]; then
    first_contract=$(add_contract "BridgeProofManager" "$ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS" "BridgeProofManager" "$first_contract")
fi

if [ -n "$ROLLUP_BRIDGE_WITHDRAW_MANAGER_PROXY_ADDRESS" ]; then
    first_contract=$(add_contract "BridgeWithdrawManager" "$ROLLUP_BRIDGE_WITHDRAW_MANAGER_PROXY_ADDRESS" "BridgeWithdrawManager" "$first_contract")
fi

if [ -n "$ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS" ]; then
    first_contract=$(add_contract "BridgeAdminManager" "$ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS" "BridgeAdminManager" "$first_contract")
fi

# Close the JSON
printf '\n  }\n}\n' >> "$OUTPUT_FILE"

# Count contracts
contract_count=$(jq '.contracts | length' "$OUTPUT_FILE" 2>/dev/null || echo "unknown")

print_success "Generated contracts JSON with $contract_count contracts"
print_status "File saved to: $OUTPUT_FILE"

# Show summary
echo ""
echo "=== CONTRACT SUMMARY ==="
if command -v jq &> /dev/null && [ -f "$OUTPUT_FILE" ]; then
    jq -r '.contracts | to_entries[] | "\(.key): \(.value.address)"' "$OUTPUT_FILE"
else
    echo "Use 'jq' to view the generated JSON file"
fi
echo "========================="

print_success "JSON generation complete!"