// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

contract Groth16Verifier128Leaves {
    address public immutable icContract1;
    address public immutable icContract2;

    constructor(address icContract1_, address icContract2_) {
        icContract1 = icContract1_;
        icContract2 = icContract2_;
    }

    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[257] calldata
    ) external pure returns (bool) {
        return true;
    }

    function verifyProof(
        uint256[4] calldata,
        uint256[8] calldata,
        uint256[4] calldata,
        uint256[259] calldata
    ) external pure returns (bool) {
        return true;
    }
}
