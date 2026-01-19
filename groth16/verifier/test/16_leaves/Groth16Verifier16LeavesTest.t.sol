// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "../../forge-std/src/Test.sol";
import "../../forge-std/src/console.sol";
import "../../src/Groth16Verifier16Leaves.sol";

contract Groth16Verifier16LeavesTest is Test {
    Groth16Verifier16Leaves public verifier;

    // Updated proof constants from prover/16_leaves_groth/proof.json - split into PART1/PART2
    uint256 constant pA_x_PART1 = 0x00000000000000000000000000000000136569c52d8ae28174779a4137be90a1;
    uint256 constant pA_x_PART2 = 0x779ae14f3a3dedd3762b71595898a38b899c64d7fa4ad8ceedb85821862c423a;
    uint256 constant pA_y_PART1 = 0x00000000000000000000000000000000120fbfa077720f1c5a34b1c62fb44343;
    uint256 constant pA_y_PART2 = 0x4dee5b1180fb47e19a75613c2ac3927fc6e9a0f191bbf91ee454b670cc2731aa;

    uint256 constant pB_x0_PART1 = 0x0000000000000000000000000000000019909e281a9c874573b50d0b028f14e6;
    uint256 constant pB_x0_PART2 = 0x13e5ec6a16bc6815117fe4ae1577a50e3eeb79e9fc45e5c855a47357cc1adf21;
    uint256 constant pB_x1_PART1 = 0x0000000000000000000000000000000010c65fe20741bf7df6af765035202b29;
    uint256 constant pB_x1_PART2 = 0x9337750e7c1261bcd2898006359a8f816e9ebecf0c861896ace44447ebbd420c;

    uint256 constant pB_y0_PART1 = 0x00000000000000000000000000000000151ab2ec8d92fb50dd33a57bd1f78f37;
    uint256 constant pB_y0_PART2 = 0xb82a58d01b6dc19277fb5b7a4745e8ec1968eec86264975d410678e937924a72;
    uint256 constant pB_y1_PART1 = 0x000000000000000000000000000000001121527ee8658367cedfb1480514189c;
    uint256 constant pB_y1_PART2 = 0xb02c24ba02a8d4742c4302807c4ff40eb5df407fb09ab7b03ac4bac2ec835e6b;

    uint256 constant pC_x_PART1 = 0x0000000000000000000000000000000017cec1b0782f4aaf18dd83c70fa65fd3;
    uint256 constant pC_x_PART2 = 0x4b72d6e0f2c9a4c25446edaf5d36dc414c7337c651519932cbab0c04d5d44aa0;
    uint256 constant pC_y_PART1 = 0x000000000000000000000000000000001365f5b649597193fdd485f117303c76;
    uint256 constant pC_y_PART2 = 0xcf3bfe461b099a88026a417abf8dd2459730e8e99041bb17d0ad812809ce5e15;

    function setUp() public {
        verifier = new Groth16Verifier16Leaves();
    }

    function testValidProof16() public view {
        // Test data from prover/16_leaves_groth/proof.json and prover/16_leaves_groth/public.json
        // This proof is generated for BLS12-381 curve with 16-leaf Merkle tree

        // pi_a - G1 point (x_PART1, x_PART2, y_PART1, y_PART2)
        uint256[4] memory _pA = [pA_x_PART1, pA_x_PART2, pA_y_PART1, pA_y_PART2];

        // pi_b - G2 point (x0_PART1, x0_PART2, x1_PART1, x1_PART2, y0_PART1, y0_PART2, y1_PART1, y1_PART2)
        uint256[8] memory _pB =
            [pB_x0_PART1, pB_x0_PART2, pB_x1_PART1, pB_x1_PART2, pB_y0_PART1, pB_y0_PART2, pB_y1_PART1, pB_y1_PART2];

        // pi_c - G1 point (x_PART1, x_PART2, y_PART1, y_PART2)
        uint256[4] memory _pC = [pC_x_PART1, pC_x_PART2, pC_y_PART1, pC_y_PART2];

        // Public signals from prover/16_leaves_groth/public.json (35 values for 16-leaf Merkle tree proof)
        uint256[35] memory _pubSignals = [
            uint256(28610243300859813175896801336277197512176412480259486447172509003484661197946),
            uint256(12345678901234567890123456789012345678901234567890123456789012345678),
            uint256(930919869281768667460268632116214329467302314052),
            uint256(123456789012345678901234567890),
            uint256(987654321098765432109876543210),
            uint256(111111111111111111111111111111),
            uint256(222222222222222222222222222222),
            uint256(333333333333333333333333333333),
            uint256(444444444444444444444444444444),
            uint256(555555555555555555555555555555),
            uint256(666666666666666666666666666666),
            uint256(777777777777777777777777777777),
            uint256(888888888888888888888888888888),
            uint256(999999999999999999999999999999),
            uint256(101010101010101010101010101010),
            uint256(121212121212121212121212121212),
            uint256(131313131313131313131313131313),
            uint256(141414141414141414141414141414),
            uint256(151515151515151515151515151515),
            uint256(1000000000000000000000000000000),
            uint256(2000000000000000000000000000000),
            uint256(3000000000000000000000000000000),
            uint256(4000000000000000000000000000000),
            uint256(5000000000000000000000000000000),
            uint256(6000000000000000000000000000000),
            uint256(7000000000000000000000000000000),
            uint256(8000000000000000000000000000000),
            uint256(9000000000000000000000000000000),
            uint256(1100000000000000000000000000000),
            uint256(1200000000000000000000000000000),
            uint256(1300000000000000000000000000000),
            uint256(1400000000000000000000000000000),
            uint256(1500000000000000000000000000000),
            uint256(1600000000000000000000000000000),
            uint256(1700000000000000000000000000000)
        ];

        // Verify the proof
        bool result = verifier.verifyProof(_pA, _pB, _pC, _pubSignals);
        assertTrue(result, "Valid proof should pass verification");
    }

    function testGasConsumption16() public view {
        // Test data from prover/16_leaves_groth/proof.json and prover/16_leaves_groth/public.json
        // This test measures gas consumption for BLS12-381 Groth16 verification

        // pi_a - G1 point (x_PART1, x_PART2, y_PART1, y_PART2)
        uint256[4] memory _pA = [pA_x_PART1, pA_x_PART2, pA_y_PART1, pA_y_PART2];

        // pi_b - G2 point (x0_PART1, x0_PART2, x1_PART1, x1_PART2, y0_PART1, y0_PART2, y1_PART1, y1_PART2)
        uint256[8] memory _pB =
            [pB_x0_PART1, pB_x0_PART2, pB_x1_PART1, pB_x1_PART2, pB_y0_PART1, pB_y0_PART2, pB_y1_PART1, pB_y1_PART2];

        // pi_c - G1 point (x_PART1, x_PART2, y_PART1, y_PART2)
        uint256[4] memory _pC = [pC_x_PART1, pC_x_PART2, pC_y_PART1, pC_y_PART2];

        // Public signals from prover/16_leaves_groth/public.json (35 values for 16-leaf Merkle tree proof)
        uint256[35] memory _pubSignals = [
            uint256(28610243300859813175896801336277197512176412480259486447172509003484661197946),
            uint256(12345678901234567890123456789012345678901234567890123456789012345678),
            uint256(930919869281768667460268632116214329467302314052),
            uint256(123456789012345678901234567890),
            uint256(987654321098765432109876543210),
            uint256(111111111111111111111111111111),
            uint256(222222222222222222222222222222),
            uint256(333333333333333333333333333333),
            uint256(444444444444444444444444444444),
            uint256(555555555555555555555555555555),
            uint256(666666666666666666666666666666),
            uint256(777777777777777777777777777777),
            uint256(888888888888888888888888888888),
            uint256(999999999999999999999999999999),
            uint256(101010101010101010101010101010),
            uint256(121212121212121212121212121212),
            uint256(131313131313131313131313131313),
            uint256(141414141414141414141414141414),
            uint256(151515151515151515151515151515),
            uint256(1000000000000000000000000000000),
            uint256(2000000000000000000000000000000),
            uint256(3000000000000000000000000000000),
            uint256(4000000000000000000000000000000),
            uint256(5000000000000000000000000000000),
            uint256(6000000000000000000000000000000),
            uint256(7000000000000000000000000000000),
            uint256(8000000000000000000000000000000),
            uint256(9000000000000000000000000000000),
            uint256(1100000000000000000000000000000),
            uint256(1200000000000000000000000000000),
            uint256(1300000000000000000000000000000),
            uint256(1400000000000000000000000000000),
            uint256(1500000000000000000000000000000),
            uint256(1600000000000000000000000000000),
            uint256(1700000000000000000000000000000)
        ];

        // Measure gas consumption
        uint256 gasStart = gasleft();
        bool result = verifier.verifyProof(_pA, _pB, _pC, _pubSignals);
        uint256 gasEnd = gasleft();

        uint256 gasUsed = gasStart - gasEnd;

        // Log the gas consumption
        console.log("=== BLS12-381 Groth16 Verification Gas Report ===");
        console.log("Gas used for proof verification:", gasUsed);
        console.log("Proof verification result:", result ? "PASSED" : "FAILED");
        console.log("Circuit: 16-leaf Merkle tree");
        console.log("Public signals: 33");
        console.log("Curve: BLS12-381");
        console.log("Protocol: Groth16");

        // Assert the proof is valid
        assertTrue(result, "Valid proof should pass verification");
    }
}
