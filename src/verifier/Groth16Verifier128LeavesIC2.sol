// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

contract Groth16Verifier128LeavesIC2 {
    function point(uint256 idx) external pure returns (uint256 x, uint256 y) {
        return (idx + 2, idx + 3);
    }
}
