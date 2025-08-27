// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8;

import {Poseidon4Field} from "./Poseidon4Field.sol";
import {Poseidon4Lib} from "./Poseidon4Lib.sol";

/**
 * Poseidon4 Contract - 4-input Poseidon hash function
 */
contract Poseidon4 {
    using Poseidon4Field for *;

    /**
     * Main poseidon4 function matching the npm library implementation
     */
    function poseidon4(Poseidon4Field.Type x, Poseidon4Field.Type y, Poseidon4Field.Type z, Poseidon4Field.Type w)
        public
        pure
        returns (Poseidon4Field.Type)
    {
        Poseidon4Field.Type[4] memory inputs;
        inputs[0] = x;
        inputs[1] = y;
        inputs[2] = z;
        inputs[3] = w;
        return Poseidon4Lib.poseidon4Direct(inputs);
    }

    /**
     * Convenience function for uint256 inputs
     */
    function poseidon4Uint256(uint256 x, uint256 y, uint256 z, uint256 w) public pure returns (uint256) {
        Poseidon4Field.Type result = poseidon4(
            Poseidon4Field.toField(x), Poseidon4Field.toField(y), Poseidon4Field.toField(z), Poseidon4Field.toField(w)
        );
        return Poseidon4Field.toUint256(result);
    }

    /**
     * Direct access to permutation for testing
     * Takes 5 elements and returns 5 elements
     */
    function permutation(Poseidon4Field.Type[5] memory inputs) public pure returns (Poseidon4Field.Type[5] memory) {
        Poseidon4Lib.Constants memory constants = Poseidon4Lib.load();
        return Poseidon4Lib.poseidonPermutation(
            inputs,
            8, // rFull
            56, // rPartial
            constants.round_constants,
            constants.mds_matrix
        );
    }

    /**
     * Test vectors for verification
     */
    function testVector1() public pure returns (uint256) {
        return poseidon4Uint256(1, 2, 3, 4);
    }

    function testVector2() public pure returns (uint256) {
        return poseidon4Uint256(0, 0, 0, 0);
    }

    function testVector3() public pure returns (uint256) {
        return poseidon4Uint256(123, 456, 789, 101112);
    }
}
