// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {VerifierV1} from "../../src/Tokamak-zkEVM/VerifierV1.sol";
import "forge-std/console.sol";

contract testTokamakVerifier is Test {
    VerifierV1 verifier;

    uint128[] public serializedProofPart1;
    uint256[] public serializedProofPart2;

    function setUp() public virtual {
        verifier = new VerifierV1();

        // proof
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // s^{(0)}(x,y)_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // s^{(0)}(x,y)_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // s^{(1)}(x,y)_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // s^{(1)}(x,y)_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // s^{(2)}(x,y)_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // s^{(2)}(x,y)_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // U_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // U_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // V_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // V_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // W_X 
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // W_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // O_mid_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // O_mid_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // O_prv_X 
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // O_prv_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Q_{AX}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Q_{AX}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Q_{AY}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Q_{AY}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Q_{CX}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Q_{CY}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{A,χ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{A,χ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{A,ζ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{A,ζ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{B,χ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{B,χ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{B,ζ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{B,ζ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{C,χ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{C,χ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{C,ζ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // Π_{C,ζ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // B_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // B_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // R_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // R_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // M_ζ_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // M_ζ_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // M_χ_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // M_χ_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // N_ζ_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // N_ζ_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // N_χ_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // N_χ_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // O_pub_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // O_pub_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // A_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef312c2); // A_Y

        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // s^{(0)}(x,y)_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // s^{(0)}(x,y)_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // s^{(1)}(x,y)_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // s^{(1)}(x,y)_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // s^{(2)}(x,y)_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // s^{(2)}(x,y)_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // U_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // U_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // V_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // V_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // W_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // W_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // O_mid_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // O_mid_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // O_prv_X 
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // O_prv_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Q_{AX}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Q_{AX}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Q_{AY}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Q_{AY}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Q_{CX}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Q_{CX}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Q_{CY}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Q_{CY}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{A,χ}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{A,χ}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{A,ζ}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{A,ζ}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{B,χ}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{B,χ}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{B,ζ}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{B,ζ}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{C,χ}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{C,χ}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{C,ζ}_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // Π_{C,ζ}_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // B_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // B_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // R_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // R_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // M_ζ_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // M_ζ_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // M_χ_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // M_χ_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // N_ζ_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // N_ζ_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // N_χ_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // N_χ_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // O_pub_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // O_pub_Y
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // A_X
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // A_Y

        // evaluations
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // R1XY
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // R2XY
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // R3XY
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // VXY
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2); // A_PUB

    }

    function testVerifier() public view {
        // Call the verify function
        bool result = verifier.verify(serializedProofPart1, serializedProofPart2);
        
        assertTrue(result);
    }
}
