#!/usr/bin/env python3
"""
Convert an updateTree proof/public pair into a Solidity fixture library.

Usage:
    python3 generate_update_tree_fixture.py <proof.json> <public.json> <output.sol>
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


def solidity_array(values, indent):
    lines = []
    for index, value in enumerate(values):
        suffix = "," if index + 1 < len(values) else ""
        lines.append(f"{indent}{value}{suffix}")
    return "\n".join(lines)


def main():
    if len(sys.argv) != 4:
        print("Usage: python3 generate_update_tree_fixture.py <proof.json> <public.json> <output.sol>")
        sys.exit(1)

    proof = json.loads(Path(sys.argv[1]).read_text())
    public_signals = json.loads(Path(sys.argv[2]).read_text())
    output_path = Path(sys.argv[3])

    if len(public_signals) != 6:
        raise ValueError(f"Expected 6 public signals for updateTree, got {len(public_signals)}.")

    p_a = [
        *split_field_element(proof["pi_a"][0]),
        *split_field_element(proof["pi_a"][1]),
    ]
    p_b = [
        *split_field_element(proof["pi_b"][0][1]),
        *split_field_element(proof["pi_b"][0][0]),
        *split_field_element(proof["pi_b"][1][1]),
        *split_field_element(proof["pi_b"][1][0]),
    ]
    p_c = [
        *split_field_element(proof["pi_c"][0]),
        *split_field_element(proof["pi_c"][1]),
    ]

    source = f"""// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UpdateTreeProofFixture {{
    function pA() internal pure returns (uint256[4] memory values) {{
        values = [
{solidity_array([f'uint256({value})' for value in p_a], '            ')}
        ];
    }}

    function pB() internal pure returns (uint256[8] memory values) {{
        values = [
{solidity_array([f'uint256({value})' for value in p_b], '            ')}
        ];
    }}

    function pC() internal pure returns (uint256[4] memory values) {{
        values = [
{solidity_array([f'uint256({value})' for value in p_c], '            ')}
        ];
    }}

    function pubSignals() internal pure returns (uint256[6] memory values) {{
        values = [
{solidity_array([f'uint256({int(value)})' for value in public_signals], '            ')}
        ];
    }}
}}
"""

    output_path.write_text(source)


if __name__ == "__main__":
    main()
