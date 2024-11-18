// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {TestPlonkVerifier} from "../src/Linea-zkEVM/test/TestPlonkVerifier.sol";

contract testLineaVerifier is Test {
    TestPlonkVerifier lineaverifier;

    function setUp() public virtual {
        lineaverifier = new TestPlonkVerifier();
    }

    function testLineaVerifierFunction() public {
        lineaverifier.test_verifier();
    }
}
