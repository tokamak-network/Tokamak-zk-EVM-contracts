// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

contract Groth16Verifier16Leaves {
    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[33] calldata
    ) external pure returns (bool) {
        return true;
    }

    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[35] calldata
    ) external pure returns (bool) {
        return true;
    }
}
