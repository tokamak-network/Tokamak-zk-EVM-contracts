// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Interface for Groth16 proof verifier with 32 leaves
/// @notice Interface for the generated Groth16 verifier contract supporting 32 leaves
interface IGroth16Verifier32Leaves {
    /// @notice Verifies a Groth16 proof
    /// @param _pA The A component of the proof
    /// @param _pB The B component of the proof
    /// @param _pC The C component of the proof
    /// @param _pubSignals The public signals (merkle keys and storage values for 32 leaves)
    /// @return True if the proof is valid
    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[65] calldata _pubSignals
    ) external view returns (bool);
}
