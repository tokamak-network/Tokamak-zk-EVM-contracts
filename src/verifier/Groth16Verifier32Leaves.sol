// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

contract Groth16Verifier32Leaves {
    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[65] calldata
    ) external pure returns (bool) {
        return true;
    }

    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[67] calldata
    ) external pure returns (bool) {
        return true;
    }
}
