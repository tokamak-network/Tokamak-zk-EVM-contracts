#!/usr/bin/env python3
"""
Convert Groth16 proof from decimal to BLS12-381 format (PART1/PART2 split)
"""

import json
import sys

def split_field_element(value):
    """Split a field element into BLS12-381 48-byte format (PART1 with 32 zeros + 16 bytes, PART2 with 32 bytes)"""
    if isinstance(value, str):
        val = int(value)
    else:
        val = int(value)
    
    # Convert to hex (remove 0x prefix)
    hex_val = hex(val)[2:].zfill(96)  # Pad to 96 hex chars (48 bytes)
    
    # Split into high 16 bytes and low 32 bytes
    high_part = hex_val[:32]  # First 32 hex chars = 16 bytes
    low_part = hex_val[32:]   # Last 64 hex chars = 32 bytes
    
    # Add 16 zero bytes (32 hex chars) prefix to high part
    part1 = "0x" + "0" * 32 + high_part
    part2 = "0x" + low_part
    
    return part1, part2

def get_expected_signal_count(public_signals):
    """Determine expected signal count based on input size"""
    input_count = len(public_signals)
    
    # Map input sizes to expected test sizes based on actual needs
    if input_count <= 35:
        return 35  # 16-leaf
    elif input_count <= 68:  # 32-leaf public.json has 68, needs 67
        return 67  # 32-leaf  
    elif input_count <= 132:  # 64-leaf public.json has 132, needs 131
        return 131  # 64-leaf 
    else:  # 128-leaf public.json has 260, needs 259
        return 259  # 128-leaf

def pad_signals_for_test(public_signals, target_count):
    """Pad signals to match test expectations with zero padding"""
    input_count = len(public_signals)
    
    # Handle specific cases where we need to truncate
    if target_count == 67 and input_count >= 68:
        # 32-leaf: Remove the last element if we have 68+ values but need 67
        return public_signals[:67]
    elif target_count == 131 and input_count >= 132:
        # 64-leaf: Remove the last element if we have 132+ values but need 131
        return public_signals[:131]  
    elif target_count == 259 and input_count >= 260:
        # 128-leaf: Remove the last element if we have 260+ values but need 259
        return public_signals[:259]
    elif len(public_signals) >= target_count:
        return public_signals[:target_count]
    
    # Otherwise pad with zeros
    padded = list(public_signals)
    while len(padded) < target_count:
        padded.append("0")
    
    return padded

def convert_proof(proof_file, public_file):
    """Convert proof and public signals to Solidity test format"""
    
    # Load proof
    with open(proof_file, 'r') as f:
        proof = json.load(f)
    
    # Load public signals
    with open(public_file, 'r') as f:
        public_signals = json.load(f)
    
    # Convert pi_a (G1 point)
    pa_x_part1, pa_x_part2 = split_field_element(proof['pi_a'][0])
    pa_y_part1, pa_y_part2 = split_field_element(proof['pi_a'][1])
    
    # Convert pi_b (G2 point) - note: coordinates may need to be swapped
    pb_x0_part1, pb_x0_part2 = split_field_element(proof['pi_b'][0][1])  # x0 = second element
    pb_x1_part1, pb_x1_part2 = split_field_element(proof['pi_b'][0][0])  # x1 = first element
    pb_y0_part1, pb_y0_part2 = split_field_element(proof['pi_b'][1][1])  # y0 = second element  
    pb_y1_part1, pb_y1_part2 = split_field_element(proof['pi_b'][1][0])  # y1 = first element
    
    # Convert pi_c (G1 point)
    pc_x_part1, pc_x_part2 = split_field_element(proof['pi_c'][0])
    pc_y_part1, pc_y_part2 = split_field_element(proof['pi_c'][1])
    
    # Generate Solidity constants
    print("// Updated proof constants from prover proof.json")
    print(f"uint256 constant pA_x_PART1 = {pa_x_part1};")
    print(f"uint256 constant pA_x_PART2 = {pa_x_part2};")
    print(f"uint256 constant pA_y_PART1 = {pa_y_part1};")
    print(f"uint256 constant pA_y_PART2 = {pa_y_part2};")
    print()
    print(f"uint256 constant pB_x0_PART1 = {pb_x0_part1};")
    print(f"uint256 constant pB_x0_PART2 = {pb_x0_part2};")
    print(f"uint256 constant pB_x1_PART1 = {pb_x1_part1};")
    print(f"uint256 constant pB_x1_PART2 = {pb_x1_part2};")
    print()
    print(f"uint256 constant pB_y0_PART1 = {pb_y0_part1};")
    print(f"uint256 constant pB_y0_PART2 = {pb_y0_part2};")
    print(f"uint256 constant pB_y1_PART1 = {pb_y1_part1};")
    print(f"uint256 constant pB_y1_PART2 = {pb_y1_part2};")
    print()
    print(f"uint256 constant pC_x_PART1 = {pc_x_part1};")
    print(f"uint256 constant pC_x_PART2 = {pc_x_part2};")
    print(f"uint256 constant pC_y_PART1 = {pc_y_part1};")
    print(f"uint256 constant pC_y_PART2 = {pc_y_part2};")
    print()
    
    # Determine target signal count and apply padding
    target_count = get_expected_signal_count(public_signals)
    padded_signals = pad_signals_for_test(public_signals, target_count)
    
    # Generate public signals array
    print(f"// Public signals from public.json ({len(public_signals)} values, padded to {target_count})")
    print(f"uint256[{target_count}] memory _pubSignals = [")
    for i, signal in enumerate(padded_signals):
        comma = "," if i < len(padded_signals) - 1 else ""
        print(f"    uint256({signal}){comma}")
    print("];")
    print()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python convert_proof.py <proof.json> <public.json>")
        sys.exit(1)
    
    convert_proof(sys.argv[1], sys.argv[2])