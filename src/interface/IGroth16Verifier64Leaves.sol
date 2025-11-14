// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Interface for Groth16 proof verifier
/// @notice Interface for the generated Groth16 verifier contract
interface IGroth16Verifier64Leaves {
    /// @notice Verifies a Groth16 proof
    /// @param _pA The A component of the proof
    /// @param _pB The B component of the proof  
    /// @param _pC The C component of the proof
    /// @param _pubSignals The public signals (merkle keys and storage values)
    /// @return True if the proof is valid
    function verifyProof(
        uint[4] calldata _pA,
        uint[8] calldata _pB,
        uint[4] calldata _pC,
        uint[129] calldata _pubSignals
    ) external view returns (bool);
}