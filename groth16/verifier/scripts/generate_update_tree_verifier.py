#!/usr/bin/env python3
"""
Generate a single Solidity verifier for the updateTree verification key.

Usage:
    python3 generate_update_tree_verifier.py <verification_key.json> <output.sol>
"""

import json
import sys
from pathlib import Path


def split_field_element(value):
    val = int(value)
    hex_val = hex(val)[2:].zfill(96)
    high_part = hex_val[:32]
    low_part = hex_val[32:]
    part1 = "0x" + "0" * 32 + high_part
    part2 = "0x" + low_part
    return part1, part2


def generate_ic_constants(ic_array):
    lines = []
    for index, point in enumerate(ic_array):
        x_part1, x_part2 = split_field_element(point[0])
        y_part1, y_part2 = split_field_element(point[1])
        lines.extend(
            [
                f"    uint256 constant IC{index}x_PART1 = {x_part1};",
                f"    uint256 constant IC{index}x_PART2 = {x_part2};",
                f"    uint256 constant IC{index}y_PART1 = {y_part1};",
                f"    uint256 constant IC{index}y_PART2 = {y_part2};",
                "",
            ]
        )
    return "\n".join(lines).rstrip()


def generate_ic_calls(ic_count):
    lines = []
    for index in range(1, ic_count):
        offset = (index - 1) * 32
        lines.extend(
            [
                f"                g1_mulAccC(_pVk, IC{index}x_PART1, IC{index}x_PART2, IC{index}y_PART1, IC{index}y_PART2, calldataload(add(pubSignals, {offset})))",
                "",
            ]
        )
    return "\n".join(lines).rstrip()


def generate_checkfield_calls(pub_signal_count):
    lines = []
    for index in range(pub_signal_count):
        offset = index * 32
        lines.extend(
            [
                f"            checkField(calldataload(add(_pubSignals, {offset})))",
                "",
            ]
        )
    return "\n".join(lines).rstrip()


def generate_contract(vk_data):
    alpha = vk_data["vk_alpha_1"]
    beta = vk_data["vk_beta_2"]
    gamma = vk_data["vk_gamma_2"]
    delta = vk_data["vk_delta_2"]
    ic_array = vk_data["IC"]

    if vk_data.get("curve") != "bls12381":
        raise ValueError("Only bls12381 verification keys are supported.")

    ic_count = len(ic_array)
    pub_signal_count = ic_count - 1
    if pub_signal_count != int(vk_data.get("nPublic", pub_signal_count)):
        raise ValueError("Verification key public-input count does not match the IC array.")

    alphax_part1, alphax_part2 = split_field_element(alpha[0])
    alphay_part1, alphay_part2 = split_field_element(alpha[1])

    betax1_part1, betax1_part2 = split_field_element(beta[0][1])
    betax2_part1, betax2_part2 = split_field_element(beta[0][0])
    betay1_part1, betay1_part2 = split_field_element(beta[1][1])
    betay2_part1, betay2_part2 = split_field_element(beta[1][0])

    gammax1_part1, gammax1_part2 = split_field_element(gamma[0][1])
    gammax2_part1, gammax2_part2 = split_field_element(gamma[0][0])
    gammay1_part1, gammay1_part2 = split_field_element(gamma[1][1])
    gammay2_part1, gammay2_part2 = split_field_element(gamma[1][0])

    deltax1_part1, deltax1_part2 = split_field_element(delta[0][1])
    deltax2_part1, deltax2_part2 = split_field_element(delta[0][0])
    deltay1_part1, deltay1_part2 = split_field_element(delta[1][1])
    deltay2_part1, deltay2_part2 = split_field_element(delta[1][0])

    ic_constants = generate_ic_constants(ic_array)
    ic_calls = generate_ic_calls(ic_count)
    checkfield_calls = generate_checkfield_calls(pub_signal_count)

    return f"""// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {{
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

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

{ic_constants}

    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;
    uint16 constant pLastMem = 1664;

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[{pub_signal_count}] calldata _pubSignals
    ) external view returns (bool) {{
        assembly {{
            function checkField(v) {{
                if iszero(lt(v, R_MOD)) {{
                    mstore(0, 0)
                    return(0, 0x20)
                }}
            }}

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

                mstore(_pVk, IC0x_PART1)
                mstore(add(_pVk, 32), IC0x_PART2)
                mstore(add(_pVk, 64), IC0y_PART1)
                mstore(add(_pVk, 96), IC0y_PART2)

{ic_calls}

                mstore(_pPairing, calldataload(pA))
                mstore(add(_pPairing, 32), calldataload(add(pA, 32)))

                let y_high := calldataload(add(pA, 64))
                let y_low := calldataload(add(pA, 96))
                let neg_y_high
                let neg_y_low
                let borrow := 0

                switch lt(Q_MOD_PART2, y_low)
                case 1 {{
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0))
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }}
                default {{
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                }}

                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)
                mstore(add(_pPairing, 64), neg_y_high)
                mstore(add(_pPairing, 96), neg_y_low)

                mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
                mstore(add(_pPairing, 160), calldataload(add(pB, 96)))
                mstore(add(_pPairing, 192), calldataload(pB))
                mstore(add(_pPairing, 224), calldataload(add(pB, 32)))
                mstore(add(_pPairing, 256), calldataload(add(pB, 192)))
                mstore(add(_pPairing, 288), calldataload(add(pB, 224)))
                mstore(add(_pPairing, 320), calldataload(add(pB, 128)))
                mstore(add(_pPairing, 352), calldataload(add(pB, 160)))

                mstore(add(_pPairing, 384), alphax_PART1)
                mstore(add(_pPairing, 416), alphax_PART2)
                mstore(add(_pPairing, 448), alphay_PART1)
                mstore(add(_pPairing, 480), alphay_PART2)

                mstore(add(_pPairing, 512), betax2_PART1)
                mstore(add(_pPairing, 544), betax2_PART2)
                mstore(add(_pPairing, 576), betax1_PART1)
                mstore(add(_pPairing, 608), betax1_PART2)
                mstore(add(_pPairing, 640), betay2_PART1)
                mstore(add(_pPairing, 672), betay2_PART2)
                mstore(add(_pPairing, 704), betay1_PART1)
                mstore(add(_pPairing, 736), betay1_PART2)

                mstore(add(_pPairing, 768), mload(add(pMem, pVk)))
                mstore(add(_pPairing, 800), mload(add(pMem, add(pVk, 32))))
                mstore(add(_pPairing, 832), mload(add(pMem, add(pVk, 64))))
                mstore(add(_pPairing, 864), mload(add(pMem, add(pVk, 96))))

                mstore(add(_pPairing, 896), gammax2_PART1)
                mstore(add(_pPairing, 928), gammax2_PART2)
                mstore(add(_pPairing, 960), gammax1_PART1)
                mstore(add(_pPairing, 992), gammax1_PART2)
                mstore(add(_pPairing, 1024), gammay2_PART1)
                mstore(add(_pPairing, 1056), gammay2_PART2)
                mstore(add(_pPairing, 1088), gammay1_PART1)
                mstore(add(_pPairing, 1120), gammay1_PART2)

                mstore(add(_pPairing, 1152), calldataload(pC))
                mstore(add(_pPairing, 1184), calldataload(add(pC, 32)))
                mstore(add(_pPairing, 1216), calldataload(add(pC, 64)))
                mstore(add(_pPairing, 1248), calldataload(add(pC, 96)))

                mstore(add(_pPairing, 1280), deltax2_PART1)
                mstore(add(_pPairing, 1312), deltax2_PART2)
                mstore(add(_pPairing, 1344), deltax1_PART1)
                mstore(add(_pPairing, 1376), deltax1_PART2)
                mstore(add(_pPairing, 1408), deltay2_PART1)
                mstore(add(_pPairing, 1440), deltay2_PART2)
                mstore(add(_pPairing, 1472), deltay1_PART1)
                mstore(add(_pPairing, 1504), deltay1_PART2)

                let success := staticcall(sub(gas(), 2000), 0x0f, _pPairing, 1536, _pPairing, 0x20)
                isOk := and(success, mload(_pPairing))
            }}

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

{checkfield_calls}

            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)
            mstore(0, isValid)
            return(0, 0x20)
        }}
    }}
}}
"""


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 generate_update_tree_verifier.py <verification_key.json> <output.sol>")
        sys.exit(1)

    verification_key_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    vk_data = json.loads(verification_key_path.read_text())
    contract_source = generate_contract(vk_data)
    output_path.write_text(contract_source)


if __name__ == "__main__":
    main()
