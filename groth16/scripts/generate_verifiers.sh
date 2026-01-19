#!/bin/bash

# Generate Solidity Verifiers for Tokamak Circuits
# This script generates basic verifiers and provides instructions for BLS12-381 adaptation

set -e

echo "🔧 Generating Solidity verifiers for all circuit configurations..."

# Ensure we're in the right directory
cd "$(dirname "$0")/.."

# Create output directory
mkdir -p verifier/src/generated

# Configuration arrays
CIRCUITS=("16_leaves_vk:N4:16" "32_leaves_vk:N5:32" "64_leaves_vk:N6:64" "128_leaves_vk:N7:128")

echo "📋 Circuit configurations to process:"
for config in "${CIRCUITS[@]}"; do
    IFS=':' read -r vk_dir circuit_name leaves <<< "$config"
    echo "  - ${leaves} leaves (${circuit_name}) -> ${vk_dir}"
done
echo ""

# Check if trusted setup files exist
echo "🔍 Checking trusted setup files..."
all_exist=true
for config in "${CIRCUITS[@]}"; do
    IFS=':' read -r vk_dir circuit_name leaves <<< "$config"
    zkey_file="trusted-setup/${vk_dir}/circuit_final.zkey"
    
    if [ ! -f "$zkey_file" ]; then
        echo "❌ Missing: $zkey_file"
        echo "   Please run trusted setup first (see TRUSTED_SETUP_GUIDE.md)"
        all_exist=false
    else
        echo "✅ Found: $zkey_file"
    fi
done

if [ "$all_exist" = false ]; then
    echo ""
    echo "⚠️  Missing trusted setup files. Please complete the trusted setup ceremony first."
    echo "   See TRUSTED_SETUP_GUIDE.md for instructions."
    exit 1
fi

echo ""
echo "🏭 Generating Solidity verifiers..."

# Generate verifiers for each configuration
for config in "${CIRCUITS[@]}"; do
    IFS=':' read -r vk_dir circuit_name leaves <<< "$config"
    
    echo ""
    echo "📝 Generating verifier for ${leaves} leaves (${circuit_name})..."
    
    # Input and output files
    zkey_file="trusted-setup/${vk_dir}/circuit_final.zkey"
    output_file="verifier/src/generated/Groth16Verifier${leaves}LeavesGenerated.sol"
    
    # Generate the verifier using snarkjs
    echo "   Running: snarkjs zkey export solidityverifier $zkey_file $output_file"
    
    if command -v snarkjs >/dev/null 2>&1; then
        snarkjs zkey export solidityverifier "$zkey_file" "$output_file"
        echo "   ✅ Generated: $output_file"
    else
        echo "   ❌ snarkjs not found. Please install: npm install -g snarkjs"
        exit 1
    fi
    
    # Show file info
    if [ -f "$output_file" ]; then
        lines=$(wc -l < "$output_file")
        size=$(ls -lh "$output_file" | awk '{print $5}')
        echo "   📊 File info: ${lines} lines, ${size}"
    fi
done

echo ""
echo "🎉 Verifier generation complete!"
echo ""
echo "📋 Generated files:"
for config in "${CIRCUITS[@]}"; do
    IFS=':' read -r vk_dir circuit_name leaves <<< "$config"
    echo "  - verifier/src/generated/Groth16Verifier${leaves}LeavesGenerated.sol"
done

echo ""
echo "⚠️  IMPORTANT NEXT STEPS:"
echo ""
echo "1. 🔄 BLS12-381 Adaptation Required:"
echo "   The generated verifiers are for bn128 curve and need adaptation for BLS12-381."
echo "   See VERIFIER_GENERATION_GUIDE.md for detailed instructions."
echo ""
echo "2. 🧪 Key Changes Needed:"
echo "   - Split verification key constants into PART1/PART2 format (48-byte fields)"
echo "   - Replace pairing operations with BLS12-381 compatible operations"
echo "   - Update field modulus constants"
echo ""
echo "3. 🔧 Manual Adaptation Process:"
echo "   - Copy existing adapted verifiers as templates"
echo "   - Extract verification key from generated files"
echo "   - Update constants in BLS12-381 format"
echo "   - Test with real proofs"
echo ""
echo "4. 🧪 Testing:"
echo "   cd verifier && forge build && forge test"
echo ""
echo "For detailed adaptation instructions, see:"
echo "  - VERIFIER_GENERATION_GUIDE.md"
echo "  - Existing verifier files in verifier/src/ (as templates)"
echo ""

# Show example of extracted verification key
echo "📊 Example: Extracting verification key for manual adaptation..."
echo ""
first_config="${CIRCUITS[0]}"
IFS=':' read -r vk_dir circuit_name leaves <<< "$first_config"
vk_json_file="trusted-setup/${vk_dir}/verification_key.json"

if [ -f "$vk_json_file" ]; then
    echo "Verification key structure (${leaves} leaves):"
    echo "File: $vk_json_file"
    echo ""
    echo "Key components to adapt:"
    jq -r '.vk_alpha_1, .vk_beta_2, .vk_gamma_2, .vk_delta_2' "$vk_json_file" 2>/dev/null | head -8 || echo "Install jq to see key structure: brew install jq"
else
    echo "Verification key JSON not found. Extract with:"
    echo "snarkjs zkey export verificationkey trusted-setup/${vk_dir}/circuit_final.zkey $vk_json_file"
fi

echo ""
echo "🎯 Ready for BLS12-381 adaptation!"