// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Interface for Groth16 verifier (N=10 / 1024 leaves)
interface IGroth16Verifier {
    /// @notice Verifies a Groth16 proof with five public signals.
    /// @param _pA The A component of the proof.
    /// @param _pB The B component of the proof.
    /// @param _pC The C component of the proof.
    /// @param _pubSignals The public signals:
    /// [root_before, root_after, storage_key, storage_value_before, storage_value_after].
    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[5] calldata _pubSignals
    ) external view returns (bool);
}
