#!/usr/bin/env python3
"""
Generate Groth16Verifier16Leaves.sol from verification_key.json

Usage: python generate_verifier_16_leaves.py <verification_key.json> <output.sol>
"""

import json
import sys
import os

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

def generate_ic_constants(ic_array):
    """Generate IC constant declarations"""
    constants = []
    for i, ic_point in enumerate(ic_array):
        x_part1, x_part2 = split_field_element(ic_point[0])
        y_part1, y_part2 = split_field_element(ic_point[1])
        
        constants.extend([
            f"    uint256 constant IC{i}x_PART1 = {x_part1};",
            f"    uint256 constant IC{i}x_PART2 = {x_part2};", 
            f"    uint256 constant IC{i}y_PART1 = {y_part1};",
            f"    uint256 constant IC{i}y_PART2 = {y_part2};",
            ""
        ])
    
    return "\n".join(constants)

def generate_ic_calls(ic_count):
    """Generate g1_mulAccC calls for IC points"""
    calls = []
    for i in range(1, ic_count):  # Start from 1, skip IC0
        offset = i * 32
        calls.append(f"                g1_mulAccC(_pVk, IC{i}x_PART1, IC{i}x_PART2, IC{i}y_PART1, IC{i}y_PART2, calldataload(add(pubSignals, {offset})))")
        calls.append("")
    
    return "\n".join(calls)

def generate_checkfield_calls(pub_signal_count):
    """Generate checkField calls for public signals"""
    calls = []
    for i in range(pub_signal_count):
        offset = i * 32
        calls.append(f"            checkField(calldataload(add(_pubSignals, {offset})))")
        calls.append("")
    
    return "\n".join(calls)

def generate_contract(vk_data):
    """Generate the complete contract from verification key data"""
    
    # Extract verification key components
    alpha = vk_data['vk_alpha_1']
    beta = vk_data['vk_beta_2']
    gamma = vk_data['vk_gamma_2'] 
    delta = vk_data['vk_delta_2']
    ic_array = vk_data['IC']
    
    # Calculate counts
    ic_count = len(ic_array)
    pub_signal_count = ic_count - 1  # IC0 is constant term
    
    # Split field elements
    alphax_part1, alphax_part2 = split_field_element(alpha[0])
    alphay_part1, alphay_part2 = split_field_element(alpha[1])
    
    betax1_part1, betax1_part2 = split_field_element(beta[0][1])  # x0
    betax2_part1, betax2_part2 = split_field_element(beta[0][0])  # x1  
    betay1_part1, betay1_part2 = split_field_element(beta[1][1])  # y0
    betay2_part1, betay2_part2 = split_field_element(beta[1][0])  # y1
    
    gammax1_part1, gammax1_part2 = split_field_element(gamma[0][1])  # x0
    gammax2_part1, gammax2_part2 = split_field_element(gamma[0][0])  # x1
    gammay1_part1, gammay1_part2 = split_field_element(gamma[1][1])  # y0
    gammay2_part1, gammay2_part2 = split_field_element(gamma[1][0])  # y1
    
    deltax1_part1, deltax1_part2 = split_field_element(delta[0][1])  # x0
    deltax2_part1, deltax2_part2 = split_field_element(delta[0][0])  # x1
    deltay1_part1, deltay1_part2 = split_field_element(delta[1][1])  # y0
    deltay2_part1, deltay2_part2 = split_field_element(delta[1][0])  # y1
    
    # Generate IC constants
    ic_constants = generate_ic_constants(ic_array)
    
    # Generate assembly calls
    ic_calls = generate_ic_calls(ic_count)
    checkfield_calls = generate_checkfield_calls(pub_signal_count)
    
    contract_template = f'''// SPDX-License-Identifier: GPL-3.0
/*
    Copyright 2021 0KIMS association.

    This file is generated with [snarkJS](https://github.com/iden3/snarkjs).

    snarkJS is a free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    snarkJS is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
    License for more details.

    You should have received a copy of the GNU General Public License
    along with snarkJS. If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier16Leaves {{
    // BLS12-381 Scalar field modulus (r)
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    // BLS12-381 Base field modulus (q) - split into two parts for 48-byte representation
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    // Verification Key data - split into PART1/PART2 for BLS12-381 format
    uint256 constant alphax_PART1 = {alphax_part1};
    uint256 constant alphax_PART2 = {alphax_part2};
    uint256 constant alphay_PART1 = {alphay_part1};
    uint256 constant alphay_PART2 = {alphay_part2};
    uint256 constant betax1_PART1 = {betax1_part1};
    uint256 constant betax1_PART2 = {betax1_part2};
    uint256 constant betax2_PART1 = {betax2_part1};
    uint256 constant betax2_PART2 = {betax2_part2};
    uint256 constant betay1_PART1 = {betay1_part1};
    uint256 constant betay1_PART2 = {betay1_part2};
    uint256 constant betay2_PART1 = {betay2_part1};
    uint256 constant betay2_PART2 = {betay2_part2};
    uint256 constant gammax1_PART1 = {gammax1_part1};
    uint256 constant gammax1_PART2 = {gammax1_part2};
    uint256 constant gammax2_PART1 = {gammax2_part1};
    uint256 constant gammax2_PART2 = {gammax2_part2};
    uint256 constant gammay1_PART1 = {gammay1_part1};
    uint256 constant gammay1_PART2 = {gammay1_part2};
    uint256 constant gammay2_PART1 = {gammay2_part1};
    uint256 constant gammay2_PART2 = {gammay2_part2};

    uint256 constant deltax2_PART1 = {deltax2_part1};
    uint256 constant deltax2_PART2 = {deltax2_part2};
    uint256 constant deltax1_PART1 = {deltax1_part1};
    uint256 constant deltax1_PART2 = {deltax1_part2};
    uint256 constant deltay2_PART1 = {deltay2_part1};
    uint256 constant deltay2_PART2 = {deltay2_part2};
    uint256 constant deltay1_PART1 = {deltay1_part1};
    uint256 constant deltay1_PART2 = {deltay1_part2};

    // IC Points - split into PART1/PART2 for BLS12-381 format

{ic_constants}

    // Memory data
    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;

    uint16 constant pLastMem = 1664;

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[{pub_signal_count}] calldata _pubSignals
    ) public view returns (bool) {{
        assembly {{
            function checkField(v) {{
                if iszero(lt(v, R_MOD)) {{
                    mstore(0, 0)
                    return(0, 0x20)
                }}
            }}

            // G1 function to multiply a G1 value(x,y) to value in an address
            function g1_mulAccC(pR, x0, x1, y0, y1, s) {{
                let success
                let mIn := mload(0x40)
                mstore(mIn, x0)
                mstore(add(mIn, 32), x1)
                mstore(add(mIn, 64), y0)
                mstore(add(mIn, 96), y1)
                mstore(add(mIn, 128), s)

                success := staticcall(sub(gas(), 2000), 0x0c, mIn, 160, mIn, 128)

                if iszero(success) {{
                    mstore(0, 0)
                    return(0, 0x20)
                }}

                mstore(add(mIn, 128), mload(pR))
                mstore(add(mIn, 160), mload(add(pR, 32)))
                mstore(add(mIn, 192), mload(add(pR, 64)))
                mstore(add(mIn, 224), mload(add(pR, 96)))

                success := staticcall(sub(gas(), 2000), 0x0b, mIn, 256, pR, 128)

                if iszero(success) {{
                    mstore(0, 0)
                    return(0, 0x20)
                }}
            }}

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {{
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                // Initialize vk_x with IC0 (the constant term)
                mstore(_pVk, IC0x_PART1)
                mstore(add(_pVk, 32), IC0x_PART2)
                mstore(add(_pVk, 64), IC0y_PART1)
                mstore(add(_pVk, 96), IC0y_PART2)

                // Compute the linear combination vk_x = IC0 + IC1*pubSignals[0] + IC2*pubSignals[1] + ...

{ic_calls}

                // -A (48-byte BLS12-381 format with proper base field negation)
                mstore(_pPairing, calldataload(pA)) // _pA[0][0] (x_PART1)
                mstore(add(_pPairing, 32), calldataload(add(pA, 32))) // _pA[0][1] (x_PART2)

                // Negate y-coordinate using proper BLS12-381 base field arithmetic: q - y
                let y_high := calldataload(add(pA, 64)) // y_PART1 (high part)
                let y_low := calldataload(add(pA, 96)) // y_PART2 (low part)

                let neg_y_high, neg_y_low
                let borrow := 0

                // Correct BLS12-381 field negation: q - y where q = Q_MOD_PART1 || Q_MOD_PART2
                // Handle the subtraction properly with borrowing
                switch lt(Q_MOD_PART2, y_low)
                case 1 {{
                    // Need to borrow from high part
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0)) // Add 2^256
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }}
                default {{
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    borrow := 0
                }}

                // Subtract high part with borrow
                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)

                mstore(add(_pPairing, 64), neg_y_high) // _pA[1][0] (-y_PART1)
                mstore(add(_pPairing, 96), neg_y_low) // _pA[1][1] (-y_PART2)

                // B (48-byte BLS12-381 format)
                // B G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 128), calldataload(add(pB, 64))) // x1_PART1
                mstore(add(_pPairing, 160), calldataload(add(pB, 96))) // x1_PART2
                mstore(add(_pPairing, 192), calldataload(pB)) // x0_PART1
                mstore(add(_pPairing, 224), calldataload(add(pB, 32))) // x0_PART2
                mstore(add(_pPairing, 256), calldataload(add(pB, 192))) // y1_PART1
                mstore(add(_pPairing, 288), calldataload(add(pB, 224))) // y1_PART2
                mstore(add(_pPairing, 320), calldataload(add(pB, 128))) // y0_PART1
                mstore(add(_pPairing, 352), calldataload(add(pB, 160))) // y0_PART2

                // alpha1 (48-byte format) - PAIR 4 G1
                mstore(add(_pPairing, 384), alphax_PART1)
                mstore(add(_pPairing, 416), alphax_PART2)
                mstore(add(_pPairing, 448), alphay_PART1)
                mstore(add(_pPairing, 480), alphay_PART2)

                // beta2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 512), betax2_PART1) // x1_PART1
                mstore(add(_pPairing, 544), betax2_PART2) // x1_PART2
                mstore(add(_pPairing, 576), betax1_PART1) // x0_PART1
                mstore(add(_pPairing, 608), betax1_PART2) // x0_PART2
                mstore(add(_pPairing, 640), betay2_PART1) // y1_PART1
                mstore(add(_pPairing, 672), betay2_PART2) // y1_PART2
                mstore(add(_pPairing, 704), betay1_PART1) // y0_PART1
                mstore(add(_pPairing, 736), betay1_PART2) // y0_PART2

                // vk_x (48-byte format from G1 point) - PAIR 2 G1
                mstore(add(_pPairing, 768), mload(add(pMem, pVk))) // x_PART1
                mstore(add(_pPairing, 800), mload(add(pMem, add(pVk, 32)))) // x_PART2
                mstore(add(_pPairing, 832), mload(add(pMem, add(pVk, 64)))) // y_PART1
                mstore(add(_pPairing, 864), mload(add(pMem, add(pVk, 96)))) // y_PART2

                // gamma2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 896), gammax2_PART1) // x1_PART1
                mstore(add(_pPairing, 928), gammax2_PART2) // x1_PART2
                mstore(add(_pPairing, 960), gammax1_PART1) // x0_PART1
                mstore(add(_pPairing, 992), gammax1_PART2) // x0_PART2
                mstore(add(_pPairing, 1024), gammay2_PART1) // y1_PART1
                mstore(add(_pPairing, 1056), gammay2_PART2) // y1_PART2
                mstore(add(_pPairing, 1088), gammay1_PART1) // y0_PART1
                mstore(add(_pPairing, 1120), gammay1_PART2) // y0_PART2

                // C (48-byte BLS12-381 format) - PAIR 3 G1
                mstore(add(_pPairing, 1152), calldataload(pC)) // _pC[0][0] (x_PART1)
                mstore(add(_pPairing, 1184), calldataload(add(pC, 32))) // _pC[0][1] (x_PART2)
                mstore(add(_pPairing, 1216), calldataload(add(pC, 64))) // _pC[1][0] (y_PART1)
                mstore(add(_pPairing, 1248), calldataload(add(pC, 96))) // _pC[1][1] (y_PART2)

                // delta2 G2 point order: x1, x0, y1, y0
                mstore(add(_pPairing, 1280), deltax2_PART1) // x1_PART1
                mstore(add(_pPairing, 1312), deltax2_PART2) // x1_PART2
                mstore(add(_pPairing, 1344), deltax1_PART1) // x0_PART1
                mstore(add(_pPairing, 1376), deltax1_PART2) // x0_PART2
                mstore(add(_pPairing, 1408), deltay2_PART1) // y1_PART1
                mstore(add(_pPairing, 1440), deltay2_PART2) // y1_PART2
                mstore(add(_pPairing, 1472), deltay1_PART1) // y0_PART1
                mstore(add(_pPairing, 1504), deltay1_PART2) // y0_PART2

                let success := staticcall(sub(gas(), 2000), 0x0f, _pPairing, 1536, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }}

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            // Validate that all evaluations ∈ F

{checkfield_calls}

            // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
            return(0, 0x20)
        }}
    }}
}}
'''
    
    return contract_template

def main():
    if len(sys.argv) != 3:
        print("Usage: python generate_verifier_16_leaves.py <verification_key.json> <output.sol>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    if not os.path.exists(input_file):
        print(f"Error: Input file {input_file} does not exist")
        sys.exit(1)
    
    # Load verification key
    with open(input_file, 'r') as f:
        vk_data = json.load(f)
    
    # Generate contract
    contract_code = generate_contract(vk_data)
    
    # Write output
    with open(output_file, 'w') as f:
        f.write(contract_code)
    
    print(f"Generated {output_file}")
    print(f"IC count: {len(vk_data['IC'])}")
    print(f"Public signals: {len(vk_data['IC']) - 1}")

if __name__ == "__main__":
    main()