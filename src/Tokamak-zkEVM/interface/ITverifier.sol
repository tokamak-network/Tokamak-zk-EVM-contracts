// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title The interface of the Verifier contract, responsible for the zero knowledge proof verification.
/// @author TOKAMAK project Ooo
interface ITverifier {
    /// @dev Verifies a zk-SNARK proof.
    /// Note: The function may revert execution instead of returning false in some cases.
    function verify(
        uint256[] calldata _publicInputs,
        uint256[] calldata _proof
    ) external view returns (bool result, uint256 teta1, uint256 teta2, uint256 teta3, uint256 kappa0, uint256 kappa1, uint256 zeta0, uint256 zeta1);

}