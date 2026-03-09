// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

contract Groth16Verifier64LeavesIC {
    function point(uint256 idx) external pure returns (uint256 x, uint256 y) {
        return (idx, idx + 1);
    }
}
