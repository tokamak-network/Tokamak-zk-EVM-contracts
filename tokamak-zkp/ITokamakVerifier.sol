// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title The interface of the Verifier contract, responsible for the zero knowledge proof verification.
/// @author TOKAMAK project Ooo
interface ITokamakVerifier {
    /// @dev Verifies a zk-SNARK proof.
    /// Note: The function may revert execution instead of returning false in some cases.
    function verify(
        uint128[] calldata _proof_part1,
        uint256[] calldata _proof_part2,
        uint128[] calldata _preprocessed_part1,
        uint256[] calldata _preprocessed_part2,
        uint256[] calldata a_pub_user,
        uint256[] calldata a_pub_block
    ) external view returns (bool);
}
