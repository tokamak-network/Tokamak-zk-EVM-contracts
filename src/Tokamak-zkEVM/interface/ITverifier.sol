// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title The interface of the Verifier contract, responsible for the zero knowledge proof verification.
/// @author TOKAMAK project Ooo
interface ITverifier {
    /// @dev Verifies a zk-SNARK proof.
    /// @return A boolean value indicating whether the zk-SNARK proof is valid.
    /// Note: The function may revert execution instead of returning false in some cases.
    function verify(
        uint256[] calldata _publicInputs,
        uint256[] calldata _proof,
        uint256[] calldata _recursiveAggregationInput
    ) external view returns (bool);

}