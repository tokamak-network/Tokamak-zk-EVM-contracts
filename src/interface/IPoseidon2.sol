// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8;

import {Field} from "../poseidon/Field.sol";

interface IPoseidon2 {
    /**
     * Main poseidon2 function that takes 2 inputs and returns first element of permutation
     */
    function poseidon2(Field.Type x, Field.Type y) external pure returns (Field.Type);
    
    /**
     * Convenience function for uint256 inputs
     */
    function poseidon2Uint256(uint256 x, uint256 y) external pure returns (uint256);
}
