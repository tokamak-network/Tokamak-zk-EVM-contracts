// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPoseidon4Yul} from "../src/interface/IPoseidon4Yul.sol";

/**
 * @title MockPoseidon4Yul
 * @author Tokamak Ooo project
 * @notice Mock implementation of Poseidon4Yul for testing purposes
 * @dev This contract provides a mock implementation that mimics the behavior
 *      of the actual Poseidon4Yul contract. It implements the fallback function
 *      to handle 4-input hashing requests and returns a deterministic hash
 *      based on the inputs.
 *      
 *      The mock uses a simple keccak256-based hash function for testing,
 *      ensuring that tests can run without the actual Yul-optimized Poseidon
 *      implementation while maintaining the same interface and behavior.
 */
contract MockPoseidon4Yul is IPoseidon4Yul {
    
    /**
     * @notice Mock fallback function that mimics Poseidon4Yul's 4-input hashing
     * @dev This function processes 4 input values from calldata and returns a
     *      deterministic hash result. It extracts 4 uint256 values from the
     *      calldata (32 bytes each) and computes a hash using keccak256.
     *      
     *      The result is modulo'd by the BLS12-381 field size to ensure it
     *      fits within the expected range for Poseidon hashes.
     */
    fallback() external {
        uint256 a;
        uint256 b;
        uint256 c;
        uint256 d;
        
        assembly {
            a := calldataload(0)
            b := calldataload(32)
            c := calldataload(64)
            d := calldataload(96)
        }
        
        // Simple mock hash function for testing
        uint256 result = uint256(keccak256(abi.encodePacked(a, b, c, d))) % 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
        
        // Store result in memory for return
        assembly {
            mstore(0, result)
            return(0, 32)
        }
    }
}
