// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

contract Groth16Verifier64Leaves {
    address public immutable icContract;

    constructor(address icContract_) {
        icContract = icContract_;
    }

    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[129] calldata
    ) external pure returns (bool) {
        return true;
    }

    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[131] calldata
    ) external pure returns (bool) {
        return true;
    }
}
