// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8;

import {Field} from "./Field.sol";
import {Poseidon2Lib} from "./Poseidon2Lib.sol";

contract Poseidon2 {
    using Field for *;

    /**
     * Main poseidon2 function matching TypeScript implementation
     * Takes 2 inputs and returns first element of permutation
     */
    function poseidon2(Field.Type x, Field.Type y) public pure returns (Field.Type) {
        Field.Type[2] memory inputs;
        inputs[0] = x;
        inputs[1] = y;
        return Poseidon2Lib.poseidon2Direct(inputs);
    }

    /**
     * Convenience function for uint256 inputs
     */
    function poseidon2Uint256(uint256 x, uint256 y) public pure returns (uint256) {
        Field.Type result = poseidon2(Field.toField(x), Field.toField(y));
        return Field.toUint256(result);
    }

    /**
     * Alternative hash functions using sponge construction
     */
    function hash_1(Field.Type x) public pure returns (Field.Type) {
        return Poseidon2Lib.hash_1(x);
    }

    function hash_2(Field.Type x, Field.Type y) public pure returns (Field.Type) {
        return Poseidon2Lib.hash_2(x, y);
    }

    function hash(Field.Type[] memory input) public pure returns (Field.Type) {
        return Poseidon2Lib.hash(input, input.length, false);
    }

    function hash(Field.Type[] memory input, uint256 std_input_length, bool is_variable_length)
        public
        pure
        returns (Field.Type)
    {
        return Poseidon2Lib.hash(input, std_input_length, is_variable_length);
    }

    /**
     * Direct access to permutation for testing
     * Takes 3 elements and returns 3 elements
     */
    function permutation(Field.Type[3] memory inputs) public pure returns (Field.Type[3] memory) {
        Poseidon2Lib.Constants memory constants = Poseidon2Lib.load();
        return Poseidon2Lib.poseidonPermutation(
            inputs,
            8,  // rFull
            56, // rPartial
            constants.round_constants,
            constants.mds_matrix
        );
    }

    /**
     * Helper function to convert uint256 arrays to Field.Type arrays
     */
    function convertToFieldArray(uint256[] memory input) public pure returns (Field.Type[] memory) {
        Field.Type[] memory fieldArray = new Field.Type[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            fieldArray[i] = Field.toField(input[i]);
        }
        return fieldArray;
    }

    /**
     * Convenient function for testing with uint256 inputs
     */
    function hashUint256(uint256[] memory input) public pure returns (uint256) {
        Field.Type[] memory fieldInput = convertToFieldArray(input);
        Field.Type result = hash(fieldInput);
        return Field.toUint256(result);
    }

    /**
     * Test vectors for verification (you can add expected outputs from TypeScript)
     */
    function testVector1() public pure returns (uint256) {
        // poseidon2(1, 2) - add expected result from TypeScript
        return poseidon2Uint256(1, 2);
    }

    function testVector2() public pure returns (uint256) {
        // poseidon2(0, 0) - add expected result from TypeScript
        return poseidon2Uint256(0, 0);
    }
}