// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8;

import {Poseidon4Field} from "../poseidon/Poseidon4Field.sol";

interface IPoseidon4 {
    /**
     * Main poseidon4 function that takes 4 inputs and returns first element of permutation
     */
    function poseidon4(Poseidon4Field.Type x, Poseidon4Field.Type y, Poseidon4Field.Type z, Poseidon4Field.Type w) external pure returns (Poseidon4Field.Type);
    
    /**
     * Convenience function for uint256 inputs
     */
    function poseidon4Uint256(uint256 x, uint256 y, uint256 z, uint256 w) external pure returns (uint256);
}
