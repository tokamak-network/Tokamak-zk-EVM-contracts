// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPoseidon2Yul} from "../../src/interface/IPoseidon2Yul.sol";

contract MockPoseidon2Yul is IPoseidon2Yul {
    // Mock implementation for testing that mimics Poseidon2Yul's fallback behavior
    // In production, this would be the actual Poseidon2Yul contract

    fallback() external {
        uint256 a;
        uint256 b;

        assembly {
            a := calldataload(0)
            b := calldataload(32)
        }

        // Simple mock hash function for testing
        uint256 result = uint256(keccak256(abi.encodePacked(a, b)))
            % 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

        // Store result in memory for return
        assembly {
            mstore(0, result)
            return(0, 32)
        }
    }
}
