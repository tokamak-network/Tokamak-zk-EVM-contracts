// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Interface for Groth16 proof verifier with N=10 (1024 leaves)
/// @notice Interface for the generated Groth16 verifier contract with 5 public signals
interface IGroth16Verifier1024Leaves {
    /// @notice Verifies a Groth16 proof
    /// @param _pA The A component of the proof
    /// @param _pB The B component of the proof
    /// @param _pC The C component of the proof
    /// @param _pubSignals The public signals [root_before, root_after, storage_key, storage_value_before, storage_value_after]
    /// @return True if the proof is valid
    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[5] calldata _pubSignals
    ) external view returns (bool);
}
