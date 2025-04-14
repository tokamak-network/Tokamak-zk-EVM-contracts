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
        
        serializedProofPart1.push(0x17f1d3a73197d7942695638c4fa9ac0f); // s^{(0)}(x,y)_X
        serializedProofPart1.push(0x08b3f481e3aaa0f1a09e30ed741d8ae4); // s^{(0)}(x,y)_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31003); // s^{(1)}(x,y)_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31004); // s^{(1)}(x,y)_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31005); // s^{(2)}(x,y)_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31006); // s^{(2)}(x,y)_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31007); // U_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31008); // U_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31009); // V_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31010); // V_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31011); // W_X 
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31012); // W_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31013); // O_mid_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31014); // O_mid_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31015); // O_prv_X 
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31016); // O_prv_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31017); // Q_{AX}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31018); // Q_{AX}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31019); // Q_{AY}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31020); // Q_{AY}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31021); // Q_{CX}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31022); // Q_{CX}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31023); // Q_{CY}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31024); // Q_{CY}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31025); // Π_{A,χ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31026); // Π_{A,χ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31027); // Π_{A,ζ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31028); // Π_{A,ζ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31029); // Π_{B,χ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31030); // Π_{B,χ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31031); // Π_{B,ζ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31032); // Π_{B,ζ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31033); // Π_{C,χ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31034); // Π_{C,χ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31035); // Π_{C,ζ}_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31036); // Π_{C,ζ}_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31037); // B_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31038); // B_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31039); // R_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31040); // R_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31041); // M_ζ_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31042); // M_ζ_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31043); // M_χ_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31044); // M_χ_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31045); // N_ζ_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31046); // N_ζ_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31047); // N_χ_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31048); // N_χ_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31049); // O_pub_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31050); // O_pub_Y
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31051); // A_X
        serializedProofPart1.push(0xf1aa493335a9e71297e485b7aef31052); // A_Y

        serializedProofPart2.push(0xc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb); // s^{(0)}(x,y)_X
        serializedProofPart2.push(0xfcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1); // s^{(0)}(x,y)_Y
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
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef31201); // R1XY
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef31202); // R2XY
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef31203); // R3XY
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef31204); // VXY
        serializedProofPart2.push(0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef31205); // A_PUB

    }

    function testVerifier() public view {
        // Call the verify function
        bytes32 result = verifier.verify(serializedProofPart1, serializedProofPart2);
        console.logBytes32(result);
    }
}
