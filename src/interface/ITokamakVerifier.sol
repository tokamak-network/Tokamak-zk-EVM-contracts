// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface ITokamakVerifier {
    function verify(
        uint128[] calldata proofPart1,
        uint256[] calldata proofPart2,
        uint128[] calldata preprocessedPart1,
        uint256[] calldata preprocessedPart2,
        uint256[] calldata publicInputs,
        uint256 smax
    ) external view returns (bool);
}
