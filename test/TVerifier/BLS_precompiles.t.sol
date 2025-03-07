// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/Tokamak-zkEVM/BLS_precompiles.sol";

contract BLS_precompilesTest is Test {
    BLS_precompiles private g1Add;

    function setUp() public {
        g1Add = new BLS_precompiles();
    }

    function test_G1ADD() public view {
        // Example input points (replace with valid BLS12-381 G1 points)
        bytes memory x1 = hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        bytes memory y1 = hex"abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
        bytes memory x2 = hex"abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
        bytes memory y2 = hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        // Call the g1Add function
        (bytes memory x, bytes memory y) = g1Add.g1Add(x1, y1, x2, y2);

        // Log the results
        console.logBytes(x);
        console.logBytes(y);

        // Assert that the output is 48 bytes each
        assertEq(x.length, 48, "Invalid x length");
        assertEq(y.length, 48, "Invalid y length");

        // Add more assertions based on expected results
        // For example, you can compare the output against a known result from a reference implementation.
    }
}