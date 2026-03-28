// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITokamakVerifier {
    function verify(
        uint128[] calldata _proof_part1,
        uint256[] calldata _proof_part2,
        uint128[] calldata _preprocessed_part1,
        uint256[] calldata _preprocessed_part2,
        uint256[] calldata a_pub_user,
        uint256[] calldata a_pub_block
    ) external view returns (bool);
}
