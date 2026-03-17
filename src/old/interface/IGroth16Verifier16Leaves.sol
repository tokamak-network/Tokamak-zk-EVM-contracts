// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IGroth16Verifier16Leaves {
    function verifyProof(
        uint256[4] calldata pA,
        uint256[8] calldata pB,
        uint256[4] calldata pC,
        uint256[33] calldata pubSignals
    ) external view returns (bool);
}
