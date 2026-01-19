// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "../../forge-std/src/Test.sol";
import "../../forge-std/src/console.sol";
import "../../src/Groth16Verifier32Leaves.sol";

contract Groth16Verifier32LeavesTest is Test {
    Groth16Verifier32Leaves public verifier;

    // Updated proof constants from prover/32_leaves_groth/proof.json - split into PART1/PART2
    uint256 constant pA_x_PART1 = 0x000000000000000000000000000000000f336c3b8a47dbd956fbe3d8b325cf2a;
    uint256 constant pA_x_PART2 = 0x53080a61314c571e54a7449d7a009566db3805c1e4bce0b9ffd3c231e0128c8e;
    uint256 constant pA_y_PART1 = 0x000000000000000000000000000000000443790d151bc1e8aab041ad1688f259;
    uint256 constant pA_y_PART2 = 0xc74682f85fa12dba095dce46658ac86c062685d606a1e5257fdf4c89cd690c1c;

    uint256 constant pB_x0_PART1 = 0x0000000000000000000000000000000004458e36b770de559c007be7eed48153;
    uint256 constant pB_x0_PART2 = 0x4b3f8c82cc92c7ee5a5bfa61ab832a73da97ac6285b472b551d3195ab21ab09b;
    uint256 constant pB_x1_PART1 = 0x0000000000000000000000000000000003addf48dc22f350ad77ccb424e00963;
    uint256 constant pB_x1_PART2 = 0xa3bf18000152fc7effd92a518ceec5ef5d95dc8d7c67d1c8043f083639baa008;

    uint256 constant pB_y0_PART1 = 0x0000000000000000000000000000000009fb58cd00c423874c6818b163986e0a;
    uint256 constant pB_y0_PART2 = 0x9eea5ad3e27db0e0134f3d14411c8b8e4572b6bf2cc72ce40be91cb867a62f7f;
    uint256 constant pB_y1_PART1 = 0x00000000000000000000000000000000032b234cfa09d28e7e183ea116bb3eec;
    uint256 constant pB_y1_PART2 = 0xfc412c59fa3697cb5b3ea22a164dfc8e304a3d18296088337d08b3d6892ab081;

    uint256 constant pC_x_PART1 = 0x000000000000000000000000000000000e2d9f54aabfd0ba65e82f6048185281;
    uint256 constant pC_x_PART2 = 0x20b392ed1edf89410e976706694b13e7b8b6407d8589cd795f0d64dd59a9003e;
    uint256 constant pC_y_PART1 = 0x00000000000000000000000000000000068b0f0187a6650f1df271dfa7572bee;
    uint256 constant pC_y_PART2 = 0x9d66571205e1f745cb4cc4de3b8c5fc1d43ededc4c349f587979d1ca57feb021;

    function setUp() public {
        verifier = new Groth16Verifier32Leaves();
    }

    function testValidProof32() public view {
        // Test data from prover/32_leaves_groth/proof.json and prover/32_leaves_groth/public.json
        // This proof is generated for BLS12-381 curve with 32-leaf Merkle tree

        // pi_a - G1 point (x_PART1, x_PART2, y_PART1, y_PART2)
        uint256[4] memory _pA = [pA_x_PART1, pA_x_PART2, pA_y_PART1, pA_y_PART2];

        // pi_b - G2 point (x0_PART1, x0_PART2, x1_PART1, x1_PART2, y0_PART1, y0_PART2, y1_PART1, y1_PART2)
        uint256[8] memory _pB =
            [pB_x0_PART1, pB_x0_PART2, pB_x1_PART1, pB_x1_PART2, pB_y0_PART1, pB_y0_PART2, pB_y1_PART1, pB_y1_PART2];

        // pi_c - G1 point (x_PART1, x_PART2, y_PART1, y_PART2)
        uint256[4] memory _pC = [pC_x_PART1, pC_x_PART2, pC_y_PART1, pC_y_PART2];

        // Public signals from prover/32_leaves_groth/public.json (67 values for 32-leaf Merkle tree proof)
        uint256[67] memory _pubSignals = [
            uint256(37313680328208527071742884240564653402860122418310991085745147043134005207746),
            uint256(12345678901234567890123456789012345678901234567890123456789012345678),
            uint256(930919869281768667460268632116214329467302314052),
            uint256(6218676549690402052910318315276979534381485872621884367715834658603456243904),
            uint256(0),
            uint256(0),
            uint256(5708510646087729135889959965248975632956651064800454628727069218571497917126),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(2000000000000000000000000000),
            uint256(0),
            uint256(0),
            uint256(1000000),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0)
        ];

        // Verify the proof
        bool result = verifier.verifyProof(_pA, _pB, _pC, _pubSignals);
        assertTrue(result, "Valid proof should pass verification");
    }

    function testGasConsumption32() public view {
        // Test data from prover/32_leaves_groth/proof.json and prover/32_leaves_groth/public.json
        // This test measures gas consumption for BLS12-381 Groth16 verification

        // pi_a - G1 point (x_PART1, x_PART2, y_PART1, y_PART2)
        uint256[4] memory _pA = [pA_x_PART1, pA_x_PART2, pA_y_PART1, pA_y_PART2];

        // pi_b - G2 point (x0_PART1, x0_PART2, x1_PART1, x1_PART2, y0_PART1, y0_PART2, y1_PART1, y1_PART2)
        uint256[8] memory _pB =
            [pB_x0_PART1, pB_x0_PART2, pB_x1_PART1, pB_x1_PART2, pB_y0_PART1, pB_y0_PART2, pB_y1_PART1, pB_y1_PART2];

        // pi_c - G1 point (x_PART1, x_PART2, y_PART1, y_PART2)
        uint256[4] memory _pC = [pC_x_PART1, pC_x_PART2, pC_y_PART1, pC_y_PART2];

        // Public signals from prover/32_leaves_groth/public.json (67 values for 32-leaf Merkle tree proof)
        uint256[67] memory _pubSignals = [
            uint256(37313680328208527071742884240564653402860122418310991085745147043134005207746),
            uint256(12345678901234567890123456789012345678901234567890123456789012345678),
            uint256(930919869281768667460268632116214329467302314052),
            uint256(6218676549690402052910318315276979534381485872621884367715834658603456243904),
            uint256(0),
            uint256(0),
            uint256(5708510646087729135889959965248975632956651064800454628727069218571497917126),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(2000000000000000000000000000),
            uint256(0),
            uint256(0),
            uint256(1000000),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0)
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
        console.log("Circuit: 32-leaf Merkle tree");
        console.log("Public signals: 67");
        console.log("Curve: BLS12-381");
        console.log("Protocol: Groth16");

        // Assert the proof is valid
        assertTrue(result, "Valid proof should pass verification");
    }
}
