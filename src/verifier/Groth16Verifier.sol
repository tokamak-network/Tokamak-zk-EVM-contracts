// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

contract Groth16Verifier {
    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[] calldata
    ) external pure returns (bool) {
        return true;
    }
}
