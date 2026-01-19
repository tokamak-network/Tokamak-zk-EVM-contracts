#!/usr/bin/env python3
"""
Generate Groth16Verifier64Leaves.sol and Groth16Verifier64LeavesIC.sol from verification_key.json

Usage: python generate_verifier_64_leaves.py <verification_key.json> <output_dir>
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

def generate_ic_contract(ic_array):
    """Generate the IC contract with getIC function"""
    ic_entries = []
    for i, ic_point in enumerate(ic_array):
        x_part1, x_part2 = split_field_element(ic_point[0])
        y_part1, y_part2 = split_field_element(ic_point[1])
        
        ic_entries.append(f"        if (index == {i}) return ({x_part1}, {x_part2}, {y_part1}, {y_part2});")
    
    ic_contract = f'''// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

// IC Constants contract for 64-leaves verifier - Updated verification key
contract Groth16Verifier64LeavesIC {{
    function getIC(uint256 index) external pure returns (uint256, uint256, uint256, uint256) {{
{chr(10).join(ic_entries)}
        revert("Invalid IC index");
    }}
}}
'''
    
    return ic_contract

def generate_main_contract(vk_data):
    """Generate the main verifier contract"""
    
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
    
    main_contract = f'''// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./Groth16Verifier64LeavesIC.sol";

contract Groth16Verifier64Leaves {{
    // BLS12-381 Scalar field modulus (r)
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    // BLS12-381 Base field modulus (q) - split into two parts for 48-byte representation
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    // Verification Key constants for 64 leaves
    uint256 internal constant alphax_PART1 = {alphax_part1};
    uint256 internal constant alphax_PART2 = {alphax_part2};
    uint256 internal constant alphay_PART1 = {alphay_part1};
    uint256 internal constant alphay_PART2 = {alphay_part2};

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

    uint256 constant deltax1_PART1 = {deltax1_part1};
    uint256 constant deltax1_PART2 = {deltax1_part2};
    uint256 constant deltax2_PART1 = {deltax2_part1};
    uint256 constant deltax2_PART2 = {deltax2_part2};
    uint256 constant deltay1_PART1 = {deltay1_part1};
    uint256 constant deltay1_PART2 = {deltay1_part2};
    uint256 constant deltay2_PART1 = {deltay2_part1};
    uint256 constant deltay2_PART2 = {deltay2_part2};

    // Reference to the IC constants contract
    Groth16Verifier64LeavesIC public icContract;

    // Memory layout for pairing check
    uint16 constant pPairing = 1408;
    uint16 constant pVk = 0; 
    uint16 constant pLastMem = 1664;

    constructor(address _icContract) {{
        icContract = Groth16Verifier64LeavesIC(_icContract);
    }}

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

                // Get IC0 (constant term) from IC contract
                let icContract := sload(icContract.slot)
                let ic0CallData := mload(0x40)
                mstore(ic0CallData, 0x9bac5bf400000000000000000000000000000000000000000000000000000000) // getIC(uint256) selector
                mstore(add(ic0CallData, 4), 0) // index 0
                
                let ic0Success := staticcall(gas(), icContract, ic0CallData, 36, ic0CallData, 128)
                if iszero(ic0Success) {{
                    mstore(0, 0)
                    return(0, 0x20)
                }}

                // Initialize vk_x with IC0
                mstore(_pVk, mload(ic0CallData)) // IC0x_PART1
                mstore(add(_pVk, 32), mload(add(ic0CallData, 32))) // IC0x_PART2
                mstore(add(_pVk, 64), mload(add(ic0CallData, 64))) // IC0y_PART1
                mstore(add(_pVk, 96), mload(add(ic0CallData, 96))) // IC0y_PART2

                // Compute the linear combination using IC contract
                for {{ let i := 1 }} lt(i, {ic_count}) {{ i := add(i, 1) }} {{
                    // Get IC[i] from contract
                    mstore(ic0CallData, 0x9bac5bf400000000000000000000000000000000000000000000000000000000) // getIC(uint256) selector
                    mstore(add(ic0CallData, 4), i)
                    
                    let icSuccess := staticcall(gas(), icContract, ic0CallData, 36, ic0CallData, 128)
                    if iszero(icSuccess) {{
                        mstore(0, 0)
                        return(0, 0x20)
                    }}

                    // Get public signal
                    let signalOffset := mul(sub(i, 1), 32)
                    let signal := calldataload(add(pubSignals, signalOffset))

                    // Multiply and accumulate
                    g1_mulAccC(_pVk, mload(ic0CallData), mload(add(ic0CallData, 32)), mload(add(ic0CallData, 64)), mload(add(ic0CallData, 96)), signal)
                }}

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
            for {{ let i := 0 }} lt(i, {pub_signal_count}) {{ i := add(i, 1) }} {{
                let offset := mul(i, 32)
                checkField(calldataload(add(_pubSignals, offset)))
            }}

            // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
            return(0, 0x20)
        }}
    }}
}}
'''
    
    return main_contract

def main():
    if len(sys.argv) != 3:
        print("Usage: python generate_verifier_64_leaves.py <verification_key.json> <output_dir>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_dir = sys.argv[2]
    
    if not os.path.exists(input_file):
        print(f"Error: Input file {input_file} does not exist")
        sys.exit(1)
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Load verification key
    with open(input_file, 'r') as f:
        vk_data = json.load(f)
    
    ic_array = vk_data['IC']
    
    # Generate contracts
    ic_contract = generate_ic_contract(ic_array)
    main_contract = generate_main_contract(vk_data)
    
    # Write outputs
    ic_file = os.path.join(output_dir, "Groth16Verifier64LeavesIC.sol")
    main_file = os.path.join(output_dir, "Groth16Verifier64Leaves.sol")
    
    with open(ic_file, 'w') as f:
        f.write(ic_contract)
    
    with open(main_file, 'w') as f:
        f.write(main_contract)
    
    print(f"Generated {ic_file}")
    print(f"Generated {main_file}")
    print(f"IC count: {len(ic_array)}")
    print(f"Public signals: {len(ic_array) - 1}")

if __name__ == "__main__":
    main()