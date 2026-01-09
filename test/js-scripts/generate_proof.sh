#!/bin/bash

# Script to generate Groth16 proofs for testing
# Usage: ./generate_proof.sh [mpt_key1] [balance1] [mpt_key2] [balance2] [mpt_key3] [balance3]

# Default test values if no arguments provided
if [ $# -eq 0 ]; then
    echo "Using default test values..."
    MPT_KEY1="1461501637330902918203684832716283019655932542976"  # uint160 of address(0xd69B7AaaE8C1c9F0546AfA4Fd8eD39741cE3f59F)
    BALANCE1="1000000000000000000"  # 1 ETH
    MPT_KEY2="1240746827509629851092253602051341618533"  # uint160 of address(0xb18E7CdB6Aa28Cc645227041329896446A1478bd)
    BALANCE2="2000000000000000000"  # 2 ETH
    MPT_KEY3="1033628234203421458715762354672"  # uint160 of address(0x9D70617FF571Ac34516C610a51023EE1F28373e8)
    BALANCE3="3000000000000000000"  # 3 ETH
else
    MPT_KEY1=$1
    BALANCE1=$2
    MPT_KEY2=$3
    BALANCE2=$4
    MPT_KEY3=$5
    BALANCE3=$6
fi

echo "Generating Groth16 proof with:"
echo "Participant 1: MPT Key = $MPT_KEY1, Balance = $BALANCE1"
echo "Participant 2: MPT Key = $MPT_KEY2, Balance = $BALANCE2"  
echo "Participant 3: MPT Key = $MPT_KEY3, Balance = $BALANCE3"

# Change to the project root directory
cd "$(dirname "$0")/../.."

# Run the Node.js script
node test/js-scripts/generateGroth16Proof.js $MPT_KEY1 $BALANCE1 $MPT_KEY2 $BALANCE2 $MPT_KEY3 $BALANCE3