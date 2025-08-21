// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IPoseidon4Yul
 * @author Tokamak Ooo project
 * @notice Interface for the Poseidon4Yul hasher contract
 * @dev This interface is intentionally minimal as the actual implementation
 *      uses a fallback function with the call pattern. The Poseidon4Yul contract
 *      expects 4 inputs (4 * 32 bytes) and returns a single hash value.
 *
 *      The interface is designed to work with the call pattern where:
 *      - Input data is encoded as 4 uint256 values
 *      - The fallback function processes the calldata
 *      - Returns a 32-byte hash result
 *
 *      This approach allows for efficient interaction with Yul-optimized
 *      hashing implementations while maintaining Solidity compatibility.
 */
interface IPoseidon4Yul {
// This interface is intentionally empty - we'll use call pattern
// The actual implementation will be in Poseidon4Yul contract
}
