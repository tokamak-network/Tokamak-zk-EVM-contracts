// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @notice Minimal interface to the on-chain Schnorr verifier.
/// @dev Expected to return the recovered signer address from (R, z, msg) against (pkx, pky).
interface IZecFrost {
    function verify(bytes32 message, uint256 pkx, uint256 pky, uint256 rx, uint256 ry, uint256 z)
        external
        view
        returns (address recovered);
}
