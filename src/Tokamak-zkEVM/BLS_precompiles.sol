// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract BLS_precompiles {
    function g1Add(
        bytes calldata x1, bytes calldata y1, // First point (x1, y1)
        bytes calldata x2, bytes calldata y2  // Second point (x2, y2)
    ) external view returns (bytes memory x, bytes memory y) {
        // Ensure input lengths are correct (48 bytes each)
        require(x1.length == 48 && y1.length == 48, "Invalid input length for point 1");
        require(x2.length == 48 && y2.length == 48, "Invalid input length for point 2");

        // Allocate memory for the result (96 bytes)
        bytes memory result = new bytes(96);

        assembly {
            // Load input data into memory
            let inputPtr := mload(0x40) // Free memory pointer
            calldatacopy(inputPtr, x1.offset, 48) // Copy x1
            calldatacopy(add(inputPtr, 48), y1.offset, 48) // Copy y1
            calldatacopy(add(inputPtr, 96), x2.offset, 48) // Copy x2
            calldatacopy(add(inputPtr, 144), y2.offset, 48) // Copy y2

            // Call the precompile at address 0x0d
            let success := staticcall(
                gas(),              // Forward all gas
                0x0b,              // Precompile address
                inputPtr,          // Input pointer
                192,               // Input size (48 * 4)
                add(result, 32),   // Output pointer (skip 32 bytes for length)
                96                 // Output size (48 * 2)
            )

            // Check if the precompile call succeeded
            if iszero(success) {
                revert(0, 0)
            }
        }

        // Split the result into x and y coordinates
        x = new bytes(48);
        y = new bytes(48);
        assembly {
            mstore(add(x, 32), mload(add(result, 32)))  // Copy x
            mstore(add(y, 32), mload(add(result, 64)))  // Copy y
        }
    }
}