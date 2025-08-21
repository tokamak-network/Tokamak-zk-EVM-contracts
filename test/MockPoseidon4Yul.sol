// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPoseidon4Yul} from "../src/interface/IPoseidon4Yul.sol";

contract MockPoseidon4Yul is IPoseidon4Yul {
    // Mock implementation for testing that mimics Poseidon4Yul's fallback behavior
    // In production, this would be the actual Poseidon4Yul contract
    
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
