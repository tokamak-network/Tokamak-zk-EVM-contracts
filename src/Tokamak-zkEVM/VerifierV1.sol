// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IVerifier} from "./interface/IVerifier.sol";

/* solhint-disable max-line-length */
/// @author Project Ooo team
/// @dev It uses a custom memory layout inside the inline assembly block. Each reserved memory cell is declared in the
/// constants below.
/// @dev For a better understanding of the verifier algorithm please refer to the following paper:
/// * Original Tokamak zkEVM Paper: https://eprint.iacr.org/2024/507.pdf
/// The notation used in the code is the same as in the papers.
/* solhint-enable max-line-length */
contract VerifierV1 is IVerifier {

    /*//////////////////////////////////////////////////////////////
                            Proof Public Inputs
    //////////////////////////////////////////////////////////////*/

    // Public input
    uint256 internal constant PUBLIC_INPUTS_HASH = 0x200 + 0x020;

    // [s^{(0)}(x,y)]_1
    uint256 internal constant PUBLIC_INPUTS_S_0_X_SLOT_PART1 = 0x200 + 0x040;
    uint256 internal constant PUBLIC_INPUTS_S_0_X_SLOT_PART2 = 0x200 + 0x060;
    uint256 internal constant PUBLIC_INPUTS_S_0_Y_SLOT_PART1 = 0x200 + 0x080;
    uint256 internal constant PUBLIC_INPUTS_S_0_Y_SLOT_PART2 = 0x200 + 0x0a0;

    // [s^{(1)}(x,y)]_1
    uint256 internal constant PUBLIC_INPUTS_S_1_X_SLOT_PART1 = 0x200 + 0x0c0;
    uint256 internal constant PUBLIC_INPUTS_S_1_X_SLOT_PART2 = 0x200 + 0x0e0;
    uint256 internal constant PUBLIC_INPUTS_S_1_Y_SLOT_PART1 = 0x200 + 0x100;
    uint256 internal constant PUBLIC_INPUTS_S_1_Y_SLOT_PART2 = 0x200 + 0x120;

    // [s^{(2)}(x,y)]_1
    uint256 internal constant PUBLIC_INPUTS_S_2_X_SLOT_PART1 = 0x200 + 0x140;
    uint256 internal constant PUBLIC_INPUTS_S_2_X_SLOT_PART2 = 0x200 + 0x160;
    uint256 internal constant PUBLIC_INPUTS_S_2_Y_SLOT_PART1 = 0x200 + 0x180;
    uint256 internal constant PUBLIC_INPUTS_S_2_Y_SLOT_PART2 = 0x200 + 0x1a0;

    /*//////////////////////////////////////////////////////////////
                                  Proof
    //////////////////////////////////////////////////////////////*/

    // U
    uint256 internal constant PROOF_POLY_U_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x020;
    uint256 internal constant PROOF_POLY_U_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x040;
    uint256 internal constant PROOF_POLY_U_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x060;
    uint256 internal constant PROOF_POLY_U_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x080;
    // V
    uint256 internal constant PROOF_POLY_V_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x0a0;
    uint256 internal constant PROOF_POLY_V_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x0c0;
    uint256 internal constant PROOF_POLY_V_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x0e0;
    uint256 internal constant PROOF_POLY_V_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x100;
    // W
    uint256 internal constant PROOF_POLY_W_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x120;
    uint256 internal constant PROOF_POLY_W_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x140;
    uint256 internal constant PROOF_POLY_W_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x160;
    uint256 internal constant PROOF_POLY_W_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x180;
    // O_mid
    uint256 internal constant PROOF_POLY_OMID_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x1a0;
    uint256 internal constant PROOF_POLY_OMID_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x1c0;
    uint256 internal constant PROOF_POLY_OMID_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x0e0;
    uint256 internal constant PROOF_POLY_OMID_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x200;
    // O_prv
    uint256 internal constant PROOF_POLY_OPRV_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x220;
    uint256 internal constant PROOF_POLY_OPRV_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x240;
    uint256 internal constant PROOF_POLY_OPRV_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x260;
    uint256 internal constant PROOF_POLY_OPRV_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x280;
    // Q_{AX}
    uint256 internal constant PROOF_POLY_QAX_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x3a0;
    uint256 internal constant PROOF_POLY_QAX_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x3c0;
    uint256 internal constant PROOF_POLY_QAX_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x3e0;
    uint256 internal constant PROOF_POLY_QAX_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x400;
    // Q_{AY}
    uint256 internal constant PROOF_POLY_QAY_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x420;
    uint256 internal constant PROOF_POLY_QAY_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x440;
    uint256 internal constant PROOF_POLY_QAY_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x460;
    uint256 internal constant PROOF_POLY_QAY_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x480;
    // Q_{CX}
    uint256 internal constant PROOF_POLY_QCX_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x2a0;
    uint256 internal constant PROOF_POLY_QCX_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x2c0;
    uint256 internal constant PROOF_POLY_QCX_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x2e0;
    uint256 internal constant PROOF_POLY_QCX_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x300;
    // Q_{CY}
    uint256 internal constant PROOF_POLY_QCY_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x320;
    uint256 internal constant PROOF_POLY_QCY_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x340;
    uint256 internal constant PROOF_POLY_QCY_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x360;
    uint256 internal constant PROOF_POLY_QCY_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x380;
    // Π_{A,χ}
    uint256 internal constant PROOF_POLY_PI_A_CHI_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x4a0;
    uint256 internal constant PROOF_POLY_PI_A_CHI_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x4c0;
    uint256 internal constant PROOF_POLY_PI_A_CHI_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x4e0;
    uint256 internal constant PROOF_POLY_PI_A_CHI_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x500;
    // Π{A,ζ}
    uint256 internal constant PROOF_POLY_PI_A_ZETA_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x520;
    uint256 internal constant PROOF_POLY_PI_A_ZETA_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x4c0;
    uint256 internal constant PROOF_POLY_PI_A_ZETA_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x4e0;
    uint256 internal constant PROOF_POLY_PI_A_ZETA_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x500;
    // Π_{B,χ}
    uint256 internal constant PROOF_POLY_PI_B_CHI_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x4a0;
    uint256 internal constant PROOF_POLY_PI_B_CHI_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x4c0;
    uint256 internal constant PROOF_POLY_PI_B_CHI_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x4e0;
    uint256 internal constant PROOF_POLY_PI_B_CHI_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x500;
    // Π{B,ζ}
    uint256 internal constant PROOF_POLY_PI_B_ZETA_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x520;
    uint256 internal constant PROOF_POLY_PI_B_ZETA_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x4c0;
    uint256 internal constant PROOF_POLY_PI_B_ZETA_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x4e0;
    uint256 internal constant PROOF_POLY_PI_B_ZETA_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x500;
    // Π_{C,χ}  
    uint256 internal constant PROOF_POLY_PI_C_CHI_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x4a0;
    uint256 internal constant PROOF_POLY_PI_C_CHI_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x4c0;
    uint256 internal constant PROOF_POLY_PI_C_CHI_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x4e0;
    uint256 internal constant PROOF_POLY_PI_C_CHI_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x500;
    // Π{C,ζ}
    uint256 internal constant PROOF_POLY_PI_C_ZETA_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x520;
    uint256 internal constant PROOF_POLY_PI_C_ZETA_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x4c0;
    uint256 internal constant PROOF_POLY_PI_C_ZETA_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x4e0;
    uint256 internal constant PROOF_POLY_PI_C_ZETA_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x500;
    // B
    uint256 internal constant PROOF_POLY_B_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x5a0;
    uint256 internal constant PROOF_POLY_B_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x5c0;
    uint256 internal constant PROOF_POLY_B_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x5e0;
    uint256 internal constant PROOF_POLY_B_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x600;
    // R
    uint256 internal constant PROOF_POLY_R_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x620;
    uint256 internal constant PROOF_POLY_R_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x640;
    uint256 internal constant PROOF_POLY_R_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x660;
    uint256 internal constant PROOF_POLY_R_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x680;
    // M_ζ
    uint256 internal constant PROOF_POLY_M_ZETA_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x6a0;
    uint256 internal constant PROOF_POLY_M_ZETA_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x6c0;
    uint256 internal constant PROOF_POLY_M_ZETA_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x6e0;
    uint256 internal constant PROOF_POLY_M_ZETA_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x700;
    // M_χ
    uint256 internal constant PROOF_POLY_M_CHI_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x720;
    uint256 internal constant PROOF_POLY_M_CHI_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x740;
    uint256 internal constant PROOF_POLY_M_CHI_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x760;
    uint256 internal constant PROOF_POLY_M_CHI_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x780;
    // N_ζ
    uint256 internal constant PROOF_POLY_N_ZETA_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x7a0;
    uint256 internal constant PROOF_POLY_N_ZETA_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x7c0;
    uint256 internal constant PROOF_POLY_N_ZETA_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x7e0;
    uint256 internal constant PROOF_POLY_N_ZETA_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x800;
    // N_χ
    uint256 internal constant PROOF_POLY_N_CHI_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x820;
    uint256 internal constant PROOF_POLY_N_CHI_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x840;
    uint256 internal constant PROOF_POLY_N_CHI_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x860;
    uint256 internal constant PROOF_POLY_N_CHI_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x880;
    // O_pub
    uint256 internal constant PROOF_POLY_OPUB_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x8a0;
    uint256 internal constant PROOF_POLY_OPUB_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x8c0;
    uint256 internal constant PROOF_POLY_OPUB_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x8e0;
    uint256 internal constant PROOF_POLY_OPUB_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x900;
    // A
    uint256 internal constant PROOF_POLY_A_X_SLOT_PART1 = 0x200 + 0x1a0 + 0x920;
    uint256 internal constant PROOF_POLY_A_X_SLOT_PART2 = 0x200 + 0x1a0 + 0x940;
    uint256 internal constant PROOF_POLY_A_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0x960;
    uint256 internal constant PROOF_POLY_A_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0x980;
    // R_xy
    uint256 internal constant PROOF_R1XY_SLOT = 0x200 + 0x1a0 + 0x9a0;
    // R'_xy
    uint256 internal constant PROOF_R2XY_SLOT = 0x200 + 0x1a0 + 0x9c0;
    // R''_xy
    uint256 internal constant PROOF_R3XY_SLOT = 0x200 + 0x1a0 + 0x9e0;
    // V_xy
    uint256 internal constant PROOF_VXY_SLOT = 0x200 + 0x1a0 + 0xa00;
    // A_pub
    uint256 internal constant PROOF_A_PUB_SLOT = 0x200 + 0x1a0 + 0xa20;



    /*//////////////////////////////////////////////////////////////
            transcript slot (used for challenge computation)
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant TRANSCRIPT_BEGIN_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x020;
    uint256 internal constant TRANSCRIPT_DST_BYTE_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x040; 
    uint256 internal constant TRANSCRIPT_STATE_0_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x060;
    uint256 internal constant TRANSCRIPT_STATE_1_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x080;
    uint256 internal constant TRANSCRIPT_CHALLENGE_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x0a0;

    /*//////////////////////////////////////////////////////////////
                             Challenges
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant CHALLENGE_THETA_0_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x0c0;
    uint256 internal constant CHALLENGE_THETA_1_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x0e0;
    uint256 internal constant CHALLENGE_THETA_2_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x100;
    uint256 internal constant CHALLENGE_KAPPA_0_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x120;
    uint256 internal constant CHALLENGE_KAPPA_1_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x140;
    uint256 internal constant CHALLENGE_KAPPA_2_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x140;
    uint256 internal constant CHALLENGE_ZETA_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x160;
    uint256 internal constant CHALLENGE_XI_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x180;
    uint256 internal constant CHALLENGE_CHI_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x180;

    /*//////////////////////////////////////////////////////////////
                       Intermediary verifier state
    //////////////////////////////////////////////////////////////*/

    // [F]_1
    uint256 internal constant INTERMERDIARY_POLY_F_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x020;
    uint256 internal constant INTERMERDIARY_POLY_F_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x040;
    uint256 internal constant INTERMERDIARY_POLY_F_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x060;
    uint256 internal constant INTERMERDIARY_POLY_F_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x080;

    // [G]_1
    uint256 internal constant INTERMERDIARY_POLY_G_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x0a0;
    uint256 internal constant INTERMERDIARY_POLY_G_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x0c0;
    uint256 internal constant INTERMERDIARY_POLY_G_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x0e0;
    uint256 internal constant INTERMERDIARY_POLY_G_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x100;

    // [Π_{χ}]_1
    uint256 internal constant INTERMERDIARY_POLY_PI_CHI_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x120;
    uint256 internal constant INTERMERDIARY_POLY_PI_CHI_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x140;
    uint256 internal constant INTERMERDIARY_POLY_PI_CHI_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x160;
    uint256 internal constant INTERMERDIARY_POLY_PI_CHI_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x180;

    // [Π_{ζ}]_1
    uint256 internal constant INTERMERDIARY_POLY_PI_ZETA_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x1a;
    uint256 internal constant INTERMERDIARY_POLY_PI_ZETA_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x1c0;
    uint256 internal constant INTERMERDIARY_POLY_PI_ZETA_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x1e0;
    uint256 internal constant INTERMERDIARY_POLY_PI_ZETA_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x200;

    // t_n(χ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_N_CHI_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x220;
    // t_smax(ζ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x240;
    // t_ml(χ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_MI_CHI_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x260;
    // K_0(χ)
    uint256 internal constant INTERMEDIARY_SCALAR_KO_SLOT = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280;

    /*//////////////////////////////////////////////////////////////
                             Pairing data
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant BUFFER_LHS_A_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x020;
    uint256 internal constant BUFFER_LHS_A_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x040;
    uint256 internal constant BUFFER_LHS_A_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x060;
    uint256 internal constant BUFFER_LHS_A_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x080; 

    uint256 internal constant BUFFER_LHS_B_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x0a0;
    uint256 internal constant BUFFER_LHS_B_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x0c0;
    uint256 internal constant BUFFER_LHS_B_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x0e0;
    uint256 internal constant BUFFER_LHS_B_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x100;

    uint256 internal constant BUFFER_LHS_C_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x120;
    uint256 internal constant BUFFER_LHS_C_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x140;
    uint256 internal constant BUFFER_LHS_C_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x160;
    uint256 internal constant BUFFER_LHS_C_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x180;

    uint256 internal constant PAIRING_BUFFER_LHS_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x1a0;
    uint256 internal constant PAIRING_BUFFER_LHS_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x1c0;
    uint256 internal constant PAIRING_BUFFER_LHS_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x1e0;
    uint256 internal constant PAIRING_BUFFER_LHS_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x200;

    uint256 internal constant PAIRING_BUFFER_AUX_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x220;
    uint256 internal constant PAIRING_BUFFER_AUX_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x240;
    uint256 internal constant PAIRING_BUFFER_AUX_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x260;
    uint256 internal constant PAIRING_BUFFER_AUX_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x280;

    /*//////////////////////////////////////////////////////////////
                             Aggregated commitment
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant BUFFER_AGGREGATED_POLY_X_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x2a0;
    uint256 internal constant BUFFER_AGGREGATED_POLY_X_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x2c0;
    uint256 internal constant BUFFER_AGGREGATED_POLY_Y_SLOT_PART1 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x2e0;
    uint256 internal constant BUFFER_AGGREGATED_POLY_Y_SLOT_PART2 = 0x200 + 0x1a0 + 0xa20 + 0x180 + 0x280 + 0x300;



    /*//////////////////////////////////////////////////////////////
                             Constants
    //////////////////////////////////////////////////////////////*/

    // Scalar field size
    // Q_MOD is the base field modulus (48 bytes long). To fit with the EVM, we sliced it into two 32bytes variables => 16 first bytes are zeros        
    uint256 internal constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 internal constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;
    // R_MOD is the main subgroup order 
    uint256 internal constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    /// @dev flip of 0xe000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant FR_MASK = 0x1fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    
    // [K^_1(X)L^-1(X)]_1
    uint256 internal constant POLY_KXLX_X_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant POLY_KXLX_X_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant POLY_KXLX_Y_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant POLY_KXLX_Y_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    // [y]_1
    uint256 internal constant POLY_Y_X_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant POLY_Y_X_PART2 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant POLY_Y_Y_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant POLY_Y_Y_PART2 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;

    // n 
    uint256 internal constant CONSTANT_N = 10;
    // s_max
    uint256 internal constant CONSTANT_SMAX = 100;
    // m_l
    uint256 internal constant CONSTANT_MI = 50;

    // [1]_1
    uint256 internal constant IDENTITY_X_PART1 = 0x0;
    uint256 internal constant IDENTITY_X_PART2 = 0x0;
    uint256 internal constant IDENTITY_Y_PART1 = 0x0;
    uint256 internal constant IDENTITY_Y_PART2 = 0x0;

    // ω_{m_l}^{-1}
    uint256 internal constant OMEGA_MI_MINUS_1 = 0x0;

    // ω_smax^{-1}
    uint256 internal constant OMEGA_SMAX_MINUS_1 = 0x0;


    /*//////////////////////////////////////////////////////////////
                        G2 elements
    //////////////////////////////////////////////////////////////*/

    // [α]_2
    uint256 internal constant ALPHA_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    // [α^2]_2
    uint256 internal constant ALPHA_POWER2_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER2_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER2_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER2_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER2_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2; 
    uint256 internal constant ALPHA_POWER2_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER2_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER2_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    // [α^3]_2
    uint256 internal constant ALPHA_POWER3_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER3_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER3_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER3_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER3_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER3_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER3_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER3_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    //[α^4]_2
    uint256 internal constant ALPHA_POWER4_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER4_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER4_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER4_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER4_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER4_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER4_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ALPHA_POWER4_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    // [γ]_2
    uint256 internal constant GAMMA_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant GAMMA_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant GAMMA_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant GAMMA_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant GAMMA_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant GAMMA_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant GAMMA_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant GAMMA_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    // [η]_2
    uint256 internal constant ETA_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ETA_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ETA_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ETA_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ETA_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ETA_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ETA_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant ETA_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    // [δ]_2
    uint256 internal constant DELTA_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant DELTA_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant DELTA_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant DELTA_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant DELTA_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant DELTA_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant DELTA_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant DELTA_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    // [x]_2
    uint256 internal constant X_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant X_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant X_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant X_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant X_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant X_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant X_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant X_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;

    //[y]_2
    uint256 internal constant Y_X0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant Y_X0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant Y_X1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant Y_X1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant Y_Y0_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant Y_Y0_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant Y_Y1_PART1 = 0x0000000000000000198e939731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 internal constant Y_Y1_PART2 = 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;


    function verify(
        uint256[] calldata, // _publicInputs
        uint256[] calldata // _proof
    ) public view virtual returns (bool result) {
        
        assembly {

            /*//////////////////////////////////////////////////////////////
                                    Utils
            //////////////////////////////////////////////////////////////*/

            /// @dev Reverts execution with a provided revert reason.
            /// @param len The byte length of the error message string, which is expected to be no more than 32.
            /// @param reason The 1-word revert reason string, encoded in ASCII.
            function revertWithMessage(len, reason) {
                // "Error(string)" signature: bytes32(bytes4(keccak256("Error(string)")))
                mstore(0x00, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                // Data offset
                mstore(0x04, 0x0000000000000000000000000000000000000000000000000000000000000020)
                // Length of revert string
                mstore(0x24, len)
                // Revert reason
                mstore(0x44, reason)
                // Revert
                revert(0x00, 0x64)
            }

            /// @dev Performs modular exponentiation using the formula (value ^ power) mod R_MOD.
            function modexp(value, power) -> res {
                mstore(0x00, 0x20)
                mstore(0x20, 0x20)
                mstore(0x40, 0x20)
                mstore(0x60, value)
                mstore(0x80, power)
                mstore(0xa0, R_MOD)
                if iszero(staticcall(gas(), 5, 0, 0xc0, 0x00, 0x20)) {
                    revertWithMessage(24, "modexp precompile failed")
                }
                res := mload(0x00)
            }

            /// @dev Performs a G1 point multiplication operation and stores the result in a given memory destination.
            function g1pointMulIntoDest(point, s, dest) {
                mstore(0x00, mload(point))
                mstore(0x20, mload(add(point, 0x20)))
                mstore(0x40, mload(add(point, 0x40)))
                mstore(0x60, mload(add(point, 0x60)))
                mstore(0x80, s)  
                // BLS12-381 G1MSM at address 0x0c
                if iszero(staticcall(gas(), 0x0c, 0, 0xa0, dest, 0x80)) {
                    revertWithMessage(30, "g1pointMulIntoDest: ecMul failed")
                }
            }

            /// @dev Performs a G1 point addition operation and stores the result in a given memory destination.
            function g1pointAddIntoDest(p1, p2, dest) {
                mstore(0x00, mload(p1))
                mstore(0x20, mload(add(p1, 0x20)))
                mstore(0x40, mload(add(p1, 0x40)))
                mstore(0x60, mload(add(p1, 0x60)))
                mstore(0x80, mload(p2))
                mstore(0xa0, mload(add(p2, 0x20)))
                mstore(0xc0, mload(add(p2, 0x40)))
                mstore(0xe0, mload(add(p2, 0x60)))
                //  BLS12-381 G1ADDat address 0x0b
                if iszero(staticcall(gas(), 0x0b, 0x00, 0x100, dest, 0x80)) {
                    revertWithMessage(30, "g1pointAddIntoDest: ecAdd failed")
                }
            }

            /// @dev Performs a G1 point multiplication and addition operations and stores the result in a given memory destination.
            function g1pointMulAndAddIntoDest(point, s, dest) {
                mstore(0x00, mload(point))
                mstore(0x20, mload(add(point, 0x20)))
                mstore(0x40, mload(add(point, 0x40)))
                mstore(0x60, mload(add(point, 0x60)))
                mstore(0x80, s) 
                let success := staticcall(gas(), 0x0c, 0, 0xa0, 0, 0x80)

                mstore(0x80, mload(dest))
                mstore(0xa0, mload(add(dest, 0x20)))
                mstore(0xc0, mload(add(dest, 0x40)))
                mstore(0xe0, mload(add(dest, 0x60)))
                success := and(success, staticcall(gas(), 0x0b, 0x00, 0x100, dest, 0x80))

                if iszero(success) {
                    revertWithMessage(22, "g1pointMulAndAddIntoDest")
                }
            }

            /// @dev Performs a G2 point multiplication operation and stores the result in a given memory destination.
            function g2pointMulIntoDest(point, s, dest) {
                mstore(0x00, mload(point))
                mstore(0x20, mload(add(point, 0x20)))
                mstore(0x40, mload(add(point, 0x40)))
                mstore(0x60, mload(add(point, 0x60)))
                mstore(0x80, mload(add(point, 0x80)))
                mstore(0xa0, mload(add(point, 0xa0)))
                mstore(0xc0, mload(add(point, 0xc0)))
                mstore(0xe0, mload(add(point, 0xe0)))
                mstore(0x100, s)  
                // BLS12-381 G2MSM at address 0x0c
                if iszero(staticcall(gas(), 0x0e, 0, 0x120, dest, 0x100)) {
                    revertWithMessage(30, "g2pointMulIntoDest: ecMul failed")
                }
            }

            /// @dev Performs a G2 point addition operation and stores the result in a given memory destination.
            function g2pointAddIntoDest(p1, p2, dest) {
                mstore(0x00, mload(p1))
                mstore(0x20, mload(add(p1, 0x20)))
                mstore(0x40, mload(add(p1, 0x40)))
                mstore(0x60, mload(add(p1, 0x60)))
                mstore(0x80, mload(add(p1, 0x80)))
                mstore(0xa0, mload(add(p1, 0xa0)))
                mstore(0xc0, mload(add(p1, 0xc0)))
                mstore(0xe0, mload(add(p1, 0xe0)))
                mstore(0x100, mload(p2))
                mstore(0x120, mload(add(p2, 0x20)))
                mstore(0x140, mload(add(p2, 0x40)))
                mstore(0x160, mload(add(p2, 0x60)))
                mstore(0x180, mload(add(p2, 0x80)))
                mstore(0x1a0, mload(add(p2, 0xa0)))
                mstore(0x1c0, mload(add(p2, 0xc0)))
                mstore(0x1e0, mload(add(p2, 0xe0)))
                // BLS12-381 G2ADD at address 0x0d
                if iszero(staticcall(gas(), 0x0d, 0x00, 0x200, dest, 0x100)) {
                    revertWithMessage(30, "g2pointAddIntoDest: ecAdd failed")
                }
            }

            function coordinatesNeg(a, b) -> result_part1, result_part2 {  
                // Load the first 32 bytes of each variable
                let a1 := mload(a)
                let b1 := mload(b)

                // Load the second 32 bytes of each variable
                let a2 := mload(add(a, 0x20))
                let b2 := mload(add(b, 0x20))

                // Perform subtraction on the lower 32 bytes
                let diff1 := sub(a1, b1)

                // Check if there was a borrow (if b1 > a1)
                let borrow := lt(a1, b1)

                // Perform subtraction on the upper 32 bytes, accounting for borrow
                let diff2 := sub(sub(a2, b2), borrow)

                // Store the result
                mstore(result_part1, diff1)
                mstore(result_part2, diff2) 
            }

            /// @dev Performs a point subtraction operation and updates the first point with the result.
            function g1pointSubAssign(p1, p2) {
                mstore(0x00, mload(p1))             // x1
                mstore(0x20, mload(add(p1, 0x20)))  // x1
                mstore(0x40, mload(add(p1, 0x40)))  // y1
                mstore(0x60, mload(add(p1, 0x60)))  // y1

                // computes -y2 and -y2' coordinates 
                let minus_y2_part1
                let minus_y2_part2 
                minus_y2_part1, minus_y2_part2 := coordinatesNeg(mload(Q_MOD_PART1), mload(add(p2, 0x40)))

                mstore(0x80, mload(p2))             // x2
                mstore(0xa0, mload(add(p2, 0x20)))  // x2
                mstore(0xc0, minus_y2_part1)        // -y2
                mstore(0xe0, minus_y2_part2)        // -y2

                if iszero(staticcall(gas(), 0x0d, 0x00, 0x100, p1, 0x80)) {
                    revertWithMessage(28, "pointSubAssign: G1ADD failed")
                }
            }

            /// @dev Performs a point subtraction operation and stores the result in a given memory destination.
            function g1pointSubIntoDest(p1, p2, dest) {
                mstore(0x00, mload(p1))             // x1
                mstore(0x20, mload(add(p1, 0x20)))  // x1
                mstore(0x40, mload(add(p1, 0x40)))  // y1
                mstore(0x60, mload(add(p1, 0x60)))  // y1

                // computes -y2 and -y2' coordinates 
                let minus_y2_part1
                let minus_y2_part2 
                minus_y2_part1, minus_y2_part2 := coordinatesNeg(mload(Q_MOD_PART1), mload(add(p2, 0x40)))

                mstore(0x80, mload(p2))             // x2
                mstore(0xa0, mload(add(p2, 0x20)))  // x2
                mstore(0xc0, minus_y2_part1)        // -y2
                mstore(0xe0, minus_y2_part2)        // -y2

                if iszero(staticcall(gas(), 0x0d, 0x00, 0x100, dest, 0x80)) {
                    revertWithMessage(28, "pointSubAssign: G1ADD failed")
                }
            }


            /// @dev Performs a G2 point subtraction operation and stores the result in a given memory destination.
            function g2pointSubIntoDest(p1, p2, dest) {
                // Load the coordinates of the first point (p1)
                mstore(0x000, mload(p1))            // x1
                mstore(0x020, mload(add(p1, 0x20))) // x1
                mstore(0x040, mload(add(p1, 0x40))) // y1
                mstore(0x060, mload(add(p1, 0x60))) // y1
                mstore(0x080, mload(add(p1, 0x80))) // x1'
                mstore(0x0a0, mload(add(p1, 0xa0))) // x1'
                mstore(0x0c0, mload(add(p1, 0xc0))) // y1'
                mstore(0x0e0, mload(add(p1, 0xe0))) // y1'
                    
                // computes -y2 and -y2' coordinates 
                let minus_y2_part1
                let minus_y2_part2 
                minus_y2_part1, minus_y2_part2 := coordinatesNeg(mload(Q_MOD_PART1), mload(add(p2, 0x40)))

                let minus_y2_prime_part1
                let minus_y2_prime_part2
                minus_y2_prime_part1, minus_y2_prime_part2 := coordinatesNeg(mload(Q_MOD_PART1), mload(add(p2, 0xc0)))
                
                    // Load the coordinates of the second point (p2)
                mstore(0x100, mload(p2))            // x2
                mstore(0x120, mload(add(p2, 0x20))) // x2
                mstore(0x140, minus_y2_part1)       // -y2
                mstore(0x160, minus_y2_part2)       // -y2
                mstore(0x180, mload(add(p2, 0x80))) // x2'
                mstore(0x1a0, mload(add(p2, 0xa0))) // x2'
                mstore(0x1c0, minus_y2_prime_part1) // -y2'
                mstore(0x1e0, minus_y2_prime_part2) // -y2'

                // Precompile at address 0x0d performs a G2ADD operation
                if iszero(staticcall(gas(), 0x0d, 0x00, 0x200, dest, 0x100)) {
                    revertWithMessage(30, "pointSubIntoDest: ecAdd failed")
                }
            }

            // Helper function to load a uint128 and left-pad it to bytes32
            function loadAndFormatUint128(calldataOffset) -> formatted {
                let rawValue := calldataload(calldataOffset)
                // Mask to 128 bits (discard upper 16 bytes if they exist)
                formatted := and(rawValue, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            }

            /*//////////////////////////////////////////////////////////////
                                    Transcript helpers
            //////////////////////////////////////////////////////////////*/

            /// @dev Updates the transcript state with a new challenge value.
            function updateTranscript(value) { 
                mstore8(TRANSCRIPT_DST_BYTE_SLOT, 0x00)
                mstore(TRANSCRIPT_CHALLENGE_SLOT, value)
                let newState0 := keccak256(TRANSCRIPT_BEGIN_SLOT, 0x64)
                mstore8(TRANSCRIPT_DST_BYTE_SLOT, 0x01)
                let newState1 := keccak256(TRANSCRIPT_BEGIN_SLOT, 0x64)
                mstore(TRANSCRIPT_STATE_1_SLOT, newState1)
                mstore(TRANSCRIPT_STATE_0_SLOT, newState0)
            }

            /// @dev Retrieves a transcript challenge.
            function getTranscriptChallenge(numberOfChallenge) -> challenge {
                mstore8(TRANSCRIPT_DST_BYTE_SLOT, 0x02)
                mstore(TRANSCRIPT_CHALLENGE_SLOT, shl(224, numberOfChallenge))
                challenge := and(keccak256(TRANSCRIPT_BEGIN_SLOT, 0x48), FR_MASK)
            }


            /*//////////////////////////////////////////////////////////////
                                    1. Load Proof
            //////////////////////////////////////////////////////////////*/

            function loadProof() {
                // 1. Load public input
                let offset := calldataload(0x04)
                let publicInputLengthInWords := calldataload(add(offset, 0x04))
                let isValid := eq(publicInputLengthInWords, 1) // We expect only one public input
                mstore(PUBLIC_INPUTS_HASH, and(calldataload(add(offset, 0x24)), FR_MASK))

                // 2. load proof
                offset := calldataload(0x24)
                // PROOF_POLY_U
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x024))
                    let x2 := calldataload(add(offset, 0x034))
                    let y1 := loadAndFormatUint128(add(offset, 0x054))
                    let y2 := calldataload(add(offset, 0x064))
                    mstore(PROOF_POLY_U_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_U_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_U_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_U_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_V
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x084))
                    let x2 := calldataload(add(offset, 0x094))
                    let y1 := loadAndFormatUint128(add(offset, 0x0b4))
                    let y2 := calldataload(add(offset, 0x0c4))
                    mstore(PROOF_POLY_V_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_V_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_V_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_V_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_W
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x0e4))
                    let x2 := calldataload(add(offset, 0x0f4))
                    let y1 := loadAndFormatUint128(add(offset, 0x114))
                    let y2 := calldataload(add(offset, 0x124))
                    mstore(PROOF_POLY_W_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_W_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_W_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_W_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_OMID
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x144))
                    let x2 := calldataload(add(offset, 0x154))
                    let y1 := loadAndFormatUint128(add(offset, 0x174))
                    let y2 := calldataload(add(offset, 0x184))
                    mstore(PROOF_POLY_OMID_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_OMID_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_OMID_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_OMID_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_OPRV
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x1a4))
                    let x2 := calldataload(add(offset, 0x1b4))
                    let y1 := loadAndFormatUint128(add(offset, 0x1d4))
                    let y2 := calldataload(add(offset, 0x1e4))
                    mstore(PROOF_POLY_OPRV_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_OPRV_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_OPRV_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_OPRV_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_QAX
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x204))
                    let x2 := calldataload(add(offset, 0x214))
                    let y1 := loadAndFormatUint128(add(offset, 0x234))
                    let y2 := calldataload(add(offset, 0x244))
                    mstore(PROOF_POLY_QAX_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_QAX_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_QAX_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_QAX_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_QAY
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x264))
                    let x2 := calldataload(add(offset, 0x274))
                    let y1 := loadAndFormatUint128(add(offset, 0x294))
                    let y2 := calldataload(add(offset, 0x2a4))
                    mstore(PROOF_POLY_QAY_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_QAY_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_QAY_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_QAY_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_QCX
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x2c4))
                    let x2 := calldataload(add(offset, 0x2d4))
                    let y1 := loadAndFormatUint128(add(offset, 0x2f4))
                    let y2 := calldataload(add(offset, 0x304))
                    mstore(PROOF_POLY_QCX_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_QCX_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_QCX_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_QCX_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_QCY
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x324))
                    let x2 := calldataload(add(offset, 0x334))
                    let y1 := loadAndFormatUint128(add(offset, 0x354))
                    let y2 := calldataload(add(offset, 0x364))
                    mstore(PROOF_POLY_QCY_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_QCY_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_QCY_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_QCY_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_A_CHI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x384))
                    let x2 := calldataload(add(offset, 0x394))
                    let y1 := loadAndFormatUint128(add(offset, 0x3b4))
                    let y2 := calldataload(add(offset, 0x3c4))
                    mstore(PROOF_POLY_PI_A_CHI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_A_CHI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_A_CHI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_A_CHI_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_A_ZETA
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x3e4))
                    let x2 := calldataload(add(offset, 0x3f4))
                    let y1 := loadAndFormatUint128(add(offset, 0x414))
                    let y2 := calldataload(add(offset, 0x424))
                    mstore(PROOF_POLY_PI_A_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_A_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_A_ZETA_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_A_ZETA_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_B_CHI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x444))
                    let x2 := calldataload(add(offset, 0x454))
                    let y1 := loadAndFormatUint128(add(offset, 0x474))
                    let y2 := calldataload(add(offset, 0x484))
                    mstore(PROOF_POLY_PI_B_CHI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_B_CHI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_B_CHI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_B_CHI_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_B_ZETA
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x4a4))
                    let x2 := calldataload(add(offset, 0x4b4))
                    let y1 := loadAndFormatUint128(add(offset, 0x4d4))
                    let y2 := calldataload(add(offset, 0x4e4))
                    mstore(PROOF_POLY_PI_B_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_B_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_B_ZETA_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_B_ZETA_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_C_CHI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x504))
                    let x2 := calldataload(add(offset, 0x514))
                    let y1 := loadAndFormatUint128(add(offset, 0x534))
                    let y2 := calldataload(add(offset, 0x544))
                    mstore(PROOF_POLY_PI_C_CHI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_C_CHI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_C_CHI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_C_CHI_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_C_ZETA
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x564))
                    let x2 := calldataload(add(offset, 0x574))
                    let y1 := loadAndFormatUint128(add(offset, 0x594))
                    let y2 := calldataload(add(offset, 0x5a4))
                    mstore(PROOF_POLY_PI_C_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_C_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_C_ZETA_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_C_ZETA_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_B
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x5c4))
                    let x2 := calldataload(add(offset, 0x5d4))
                    let y1 := loadAndFormatUint128(add(offset, 0x5f4))
                    let y2 := calldataload(add(offset, 0x604))
                    mstore(PROOF_POLY_B_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_B_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_B_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_B_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_R
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x624))
                    let x2 := calldataload(add(offset, 0x634))
                    let y1 := loadAndFormatUint128(add(offset, 0x654))
                    let y2 := calldataload(add(offset, 0x664))
                    mstore(PROOF_POLY_R_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_R_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_R_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_R_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_M_ZETA
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x684))
                    let x2 := calldataload(add(offset, 0x694))
                    let y1 := loadAndFormatUint128(add(offset, 0x6b4))
                    let y2 := calldataload(add(offset, 0x6c4))
                    mstore(PROOF_POLY_M_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_M_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_M_ZETA_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_M_ZETA_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_M_CHI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x6e4))
                    let x2 := calldataload(add(offset, 0x6f4))
                    let y1 := loadAndFormatUint128(add(offset, 0x714))
                    let y2 := calldataload(add(offset, 0x724))
                    mstore(PROOF_POLY_M_CHI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_M_CHI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_M_CHI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_M_CHI_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_N_ZETA
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x744))
                    let x2 := calldataload(add(offset, 0x754))
                    let y1 := loadAndFormatUint128(add(offset, 0x774))
                    let y2 := calldataload(add(offset, 0x784))
                    mstore(PROOF_POLY_N_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_N_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_N_ZETA_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_N_ZETA_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_N_CHI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x7a4))
                    let x2 := calldataload(add(offset, 0x7b4))
                    let y1 := loadAndFormatUint128(add(offset, 0x7d4))
                    let y2 := calldataload(add(offset, 0x7e4))
                    mstore(PROOF_POLY_N_CHI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_N_CHI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_N_CHI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_N_CHI_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_OPUB
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x804))
                    let x2 := calldataload(add(offset, 0x814))
                    let y1 := loadAndFormatUint128(add(offset, 0x834))
                    let y2 := calldataload(add(offset, 0x844))
                    mstore(PROOF_POLY_OPUB_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_OPUB_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_OPUB_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_OPUB_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_A
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x864))
                    let x2 := calldataload(add(offset, 0x874))
                    let y1 := loadAndFormatUint128(add(offset, 0x894))
                    let y2 := calldataload(add(offset, 0x8a4))
                    mstore(PROOF_POLY_A_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_A_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_A_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_A_Y_SLOT_PART2, y2)
                }

                mstore(PROOF_R1XY_SLOT, mod(calldataload(add(offset, 0x8c4)), R_MOD))
                mstore(PROOF_R2XY_SLOT, mod(calldataload(add(offset, 0x8e4)), R_MOD))
                mstore(PROOF_R3XY_SLOT, mod(calldataload(add(offset, 0x904)), R_MOD))
                mstore(PROOF_VXY_SLOT, mod(calldataload(add(offset, 0x924)), R_MOD))
                mstore(PROOF_A_PUB_SLOT, mod(calldataload(add(offset, 0x924)), R_MOD))
            }


            /*//////////////////////////////////////////////////////////////
                                2. Transcript initialization
            //////////////////////////////////////////////////////////////*/

            /// @notice Recomputes all challenges
            /// @dev The process is the following:
            /// Commit:   [U], [V], [W], [Q_X], [Q_Y]
            /// Get:      χ, ζ
            /// Commit:   [B]
            /// Get:      θ_0, θ_1, θ_2
            /// Commit    [R]
            /// Get:      κ0, κ1, κ2
            /// Commit    [Q_Z]
            /// Get:      ξ

            function initializeTranscript() {
                // Round 1
                updateTranscript(mload(PUBLIC_INPUTS_HASH))
                updateTranscript(mload(PROOF_POLY_U_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_U_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_U_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_V_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_V_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_V_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_V_Y_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_W_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_W_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_W_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_W_Y_SLOT_PART2))
                
                // compute χ
                mstore(CHALLENGE_CHI_SLOT, getTranscriptChallenge(0))

                // Round 1.5
                updateTranscript(mload(PROOF_POLY_QAX_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QAX_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QAX_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QAX_Y_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QAY_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QAY_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QAY_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QAY_Y_SLOT_PART2))

                // compute ζ
                mstore(CHALLENGE_ZETA_SLOT, getTranscriptChallenge(1))

                // Round 2
                updateTranscript(mload(PROOF_POLY_B_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_B_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_B_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_B_Y_SLOT_PART2))

                mstore(CHALLENGE_THETA_0_SLOT, getTranscriptChallenge(2))
                mstore(CHALLENGE_THETA_1_SLOT, getTranscriptChallenge(3))
                mstore(CHALLENGE_THETA_2_SLOT, getTranscriptChallenge(4))

                // Round 3
                updateTranscript(mload(PROOF_POLY_R_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_R_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_R_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_R_Y_SLOT_PART2))

                mstore(CHALLENGE_KAPPA_0_SLOT, getTranscriptChallenge(5))
                mstore(CHALLENGE_KAPPA_1_SLOT, getTranscriptChallenge(6))
                mstore(CHALLENGE_KAPPA_2_SLOT, getTranscriptChallenge(7))
            
            }

            /*//////////////////////////////////////////////////////////////
                                    3. Prepare Queries
            //////////////////////////////////////////////////////////////*/

            /// @dev Here we compute some queries for the final pairing
            /// We use the formulas:
            /// [F]_1:=[B]_1+θ_0[s^{(0)}(x,y)]_1+θ_1[s^{(1)}(x,y)]_1+θ_2[1]_1
            /// 
            /// [G]_1:= [B]_1+θ_0[s^{(2)}(x,y)]_1+θ_1[y]_1+θ_2[1]_1
            ///
            /// t_n(χ):=χ^{n}-1
            ///
            /// t_{smax}(ζ)=ζ^{smax}-1
            ///
            /// t_{m_I}(χ)=χ^{m_I}-1
            ///
            /// K_0(χ)

            function prepareQueries() {
                // calculate [F]_1
                {
                    let theta0 := mload(CHALLENGE_THETA_0_SLOT)
                    let theta1 := mload(CHALLENGE_THETA_0_SLOT)
                    let theta2 := mload(CHALLENGE_THETA_0_SLOT)


                    mstore(INTERMERDIARY_POLY_F_X_SLOT_PART1, mload(PROOF_POLY_B_X_SLOT_PART1))
                    mstore(INTERMERDIARY_POLY_F_X_SLOT_PART2, mload(PROOF_POLY_B_X_SLOT_PART2))
                    mstore(INTERMERDIARY_POLY_F_X_SLOT_PART1, mload(PROOF_POLY_B_X_SLOT_PART1))
                    mstore(INTERMERDIARY_POLY_F_Y_SLOT_PART2, mload(PROOF_POLY_B_Y_SLOT_PART2))

                    g1pointMulAndAddIntoDest(PUBLIC_INPUTS_S_0_X_SLOT_PART1,theta0,INTERMERDIARY_POLY_F_X_SLOT_PART1)
                    g1pointMulAndAddIntoDest(PUBLIC_INPUTS_S_1_X_SLOT_PART1,theta1,INTERMERDIARY_POLY_F_X_SLOT_PART1)
                    g1pointMulAndAddIntoDest(IDENTITY_X_PART1, theta2, INTERMERDIARY_POLY_F_X_SLOT_PART1)

                }
                
                // calculate [G]_1
                {
                    let theta0 := mload(CHALLENGE_THETA_0_SLOT)
                    let theta1 := mload(CHALLENGE_THETA_0_SLOT)
                    let theta2 := mload(CHALLENGE_THETA_0_SLOT)

                    mstore(INTERMERDIARY_POLY_G_X_SLOT_PART1, mload(PROOF_POLY_B_X_SLOT_PART1))
                    mstore(INTERMERDIARY_POLY_G_X_SLOT_PART2, mload(PROOF_POLY_B_X_SLOT_PART2))
                    mstore(INTERMERDIARY_POLY_G_X_SLOT_PART1, mload(PROOF_POLY_B_X_SLOT_PART1))
                    mstore(INTERMERDIARY_POLY_G_Y_SLOT_PART2, mload(PROOF_POLY_B_Y_SLOT_PART2))

                    g1pointMulAndAddIntoDest(PUBLIC_INPUTS_S_2_X_SLOT_PART1,theta0,INTERMERDIARY_POLY_G_X_SLOT_PART1)
                    g1pointMulAndAddIntoDest(POLY_Y_X_PART1,theta1,INTERMERDIARY_POLY_G_X_SLOT_PART1)
                    g1pointMulAndAddIntoDest(IDENTITY_X_PART1,theta2,INTERMERDIARY_POLY_G_X_SLOT_PART1)
                }

                // calculate t_n(χ)
                {
                    let chi := mload(CHALLENGE_CHI_SLOT)
                    let n := mload(CONSTANT_N)
                    let t := sub(modexp(chi,n),1)
                    mstore(INTERMERDIARY_SCALAR_T_N_CHI_SLOT,t)
                }

                // calculate t_smax(ζ)
                {
                    let zeta := mload(CHALLENGE_ZETA_SLOT)
                    let smax := mload(CONSTANT_SMAX)
                    let t := sub(modexp(zeta,smax),1)
                    mstore(INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT,t)
                }

                // calculate t_mI(χ)
                {
                    let chi := mload(CHALLENGE_CHI_SLOT)
                    let mI := mload(CONSTANT_MI)
                    let t := sub(modexp(chi,mI),1)
                    mstore(INTERMERDIARY_SCALAR_T_MI_CHI_SLOT,t)
                }

                // calculate K_0(χ)
                {
                    let chi := mload(CHALLENGE_CHI_SLOT)
                    let mI := mload(CONSTANT_MI)
                    
                    let chi_mI := modexp(chi, mI)
                    let chi_mI_minus_1 := addmod(chi_mI, sub(R_MOD, 1), R_MOD)

                    // Calculate mI * (chi - 1) mod R_MOD
                    let chi_minus_1 := addmod(chi, sub(R_MOD, 1), R_MOD)
                    let mI_chi_minus_1 := mulmod(mI, chi_minus_1, R_MOD)

                    // Calculate K0 = (chi^ml - 1) / (ml * (chi - 1)) mod R_MOD
                    // Division in modular arithmetic is multiplication by the modular inverse
                    //let ml_chi_minus_1_inv := modinv(ml_chi_minus_1, R_MOD)
                    //let k0 := mulmod(chi_ml_minus_1, ml_chi_minus_1_inv, R_MOD)
                    //mstore(INTERMEDIARY_SCALAR_KO_SLOT, k0)

                }
            }


            /*//////////////////////////////////////////////////////////////
                                    4. Compute LHS and AUX
            //////////////////////////////////////////////////////////////*/

            /// @dev Here we compute [LHS]_1 + [AUX]_1 aggregated commitment for the final pairing
            /// We use the formulas:
            /// [LHS]_1 := [LHS_B]_1 + κ2([LHS_A]_1 + [LHS_C]_1)
            ///
            /// where
            ///
            /// [LHS_A]_1 :=  V_{x,y}[U]_1 - [W]_1 + κ1[V]_1 
            ///               - t_n(χ)[Q_{A,X}]_1 - t_{s_{max}}(ζ)[Q_{A,Y}]_1
            ///
            /// and where
            ///
            /// [LHS_C]_1 := κ1^2(R_{x,y} - 1) * [K_{-1}(X)L_{-1}(X)]_1 + a[G]_1 
            ///              - b[F]_1 - κ1^2 * t_{m_l}(χ) * [Q_{C,X}]_1 - κ1^2 * t_{s_{max}}(ζ) * [Q_{C,Y}]_1) + c[R]_1 + d[1 ]_1
            ///              
            ///         with a := κ1^2κ0R_{x,y}((χ-1)  + κ0K_0(χ))
            ///              b := κ1^2κ0((χ-1) R’_{x,y} + κ0K_0(χ)R’’_{x,y})
            ///              c := κ1^3 + κ2 + κ2^2
            ///              d := -κ1^3R_{x,y} - κ2R’_{x,y} - κ2^2R’’_{x,y} - κ1V_{x,y} - κ1^4A_{pub}    
            ///
            ///  and where
            /// 
            ///  [LHS_B]_1 := (1+κ2κ1^4)[A]_1
            ///
            ///  and 
            ///
            ///  [AUX]_1 := κ2 * χ * [Π_{χ}]_1 + κ2 * ζ *([Π_ζ]_1 + [M_ζ]_1) + 
            ///             κ2^2 * ω_{m_l}^{-1} * χ *[M_{χ}]_1 + κ2^3 * ω_{m_l}^{-1} * χ * [N_{χ}]_1 + κ_2 ω_smax^{-1} * ζ * [N_{ζ}]
            /// 

            /// @dev calculate [LHS_A]_1 = V_{x,y}[U]_1 - [W]_1 + κ1 * ([V]_1 - V_{x,y}[1]_1) - t_n(χ)[Q_{A,X}]_1 - t_{s_{max}}(ζ)[Q_{A,Y}]_1            
            function prepareLHSA() {
                g1pointMulIntoDest(PROOF_POLY_U_X_SLOT_PART1, mload(PROOF_VXY_SLOT), BUFFER_LHS_A_X_SLOT_PART1)
                g1pointSubAssign(BUFFER_LHS_A_X_SLOT_PART1, PROOF_POLY_W_X_SLOT_PART1)
                // V_{x,y} * [1]_1
                g1pointMulIntoDest(IDENTITY_X_PART1, mload(PROOF_VXY_SLOT), BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                // [V]_1 - V_{x,y} * [1]_1
                g1pointSubIntoDest(PROOF_POLY_V_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                // κ1 * ([V]_1 - V_{x,y} * [1]_1)
                g1pointMulIntoDest(BUFFER_AGGREGATED_POLY_X_SLOT_PART1, mload(CHALLENGE_KAPPA_1_SLOT), BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                // (V_{x,y}[U]_1 - [W]_1) + (κ1 * ([V]_1 - V_{x,y}[1]_1))
                g1pointAddIntoDest(BUFFER_LHS_A_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                // t_n(χ)[Q_{A,X}]_1
                g1pointMulIntoDest(PROOF_POLY_QAX_X_SLOT_PART1, mload(INTERMERDIARY_SCALAR_T_N_CHI_SLOT), BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                
                // (V_{x,y}[U]_1 - [W]_1) + (κ1 * ([V]_1 - V_{x,y}[1]_1)) - t_n(χ)[Q_{A,X}]_1
                g1pointSubAssign(BUFFER_LHS_A_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                // t_{s_{max}}(ζ)[Q_{A,Y}]_1
                g1pointMulIntoDest(PROOF_POLY_QAY_X_SLOT_PART1, mload(INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT), BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                // V_{x,y}[U]_1 - [W]_1 + κ1 * ([V]_1 - V_{x,y}[1]_1) - t_n(χ)[Q_{A,X}]_1 - t_{s_{max}}(ζ)[Q_{A,Y}]_1
                g1pointSubAssign(BUFFER_LHS_A_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
            }

            /// @dev [LHS_B]_1 := (1+κ2κ1^4)[A]_1 - κ2κ1^4 * A_{pub}[1]_1
            function prepareLHSB() {
                let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                let kappa1 := mload(CHALLENGE_KAPPA_1_SLOT)
                let A_pub := mload(PROOF_A_PUB_SLOT)

                // κ2κ1^4
                let coeff1 := addmod(1, mulmod(kappa2, modexp(kappa1, 4), R_MOD), R_MOD)

                // (1+κ2κ1^4) * A_{pub}
                let coeff2 := mulmod(mulmod(kappa2, modexp(kappa1, 4), R_MOD), A_pub, R_MOD)

                // (1+κ2κ1^4)[A]_1
                g1pointMulIntoDest(PROOF_POLY_A_X_SLOT_PART1, coeff1, BUFFER_LHS_B_X_SLOT_PART1)

                // κ2κ1^4 * A_{pub}[1]_1
                g1pointMulIntoDest(IDENTITY_X_PART1, coeff2, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                // (1+κ2κ1^4)[A]_1 - κ2κ1^4 * A_{pub}[1]_1
                g1pointSubAssign(BUFFER_LHS_B_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
            }

            ///  @dev [LHS_C]_1 := κ1^2(R_{x,y} - 1) * [K_{-1}(X)L_{-1}(X)]_1 + a[G]_1 
            ///                    - b[F]_1 - κ1^2 * t_{m_l}(χ) * [Q_{C,X}]_1 - κ1^2 * t_{s_{max}}(ζ) * [Q_{C,Y}]_1) + c[R]_1 + d[1]_1
            function prepareLHSC() {
                let kappa0 := mload(CHALLENGE_KAPPA_0_SLOT)
                let kappa1 := mload(CHALLENGE_KAPPA_1_SLOT)
                let kappa1_pow2 := mulmod(kappa1, kappa1, R_MOD)
                let kappa1_pow3 := mulmod(kappa1, kappa1_pow2, R_MOD)
                let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                let kappa2_pow2 := mulmod(kappa2, kappa2, R_MOD)
                let chi := mload(CHALLENGE_CHI_SLOT)
                let chi_minus_1 := addmod(chi, sub(R_MOD, 1), R_MOD)
                let r1 := mload(PROOF_R1XY_SLOT)
                let r2 := mload(PROOF_R2XY_SLOT)
                let r3 := mload(PROOF_R3XY_SLOT)
                let k0 := mload(INTERMEDIARY_SCALAR_KO_SLOT)
                let V_xy := mload(PROOF_VXY_SLOT)
                let A_pub := mload(PROOF_A_PUB_SLOT)
                let t_ml := mload(INTERMERDIARY_SCALAR_T_MI_CHI_SLOT)
                let t_smax := mload(INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT)

                // a := κ1^2 * κ0 * R_{x,y} * ((χ-1) + κ0 * K_0(χ))
                let a := mulmod(mulmod(mulmod(mulmod(kappa1, kappa1, R_MOD), kappa0, R_MOD),r1, R_MOD), addmod(chi_minus_1, mulmod(kappa0, k0, R_MOD), R_MOD), R_MOD)
                // b := κ1^2 * κ0 * ((χ-1) R’_{x,y} + κ0K_0(χ)R’’_{x,y})
                let b := mulmod(mulmod(kappa1_pow2, kappa0, R_MOD), addmod(mulmod(chi_minus_1, r2, R_MOD), mulmod(mulmod(kappa0, k0, R_MOD), r3, R_MOD), R_MOD), R_MOD)
                // c := κ1^3 + κ2 + κ2^2
                let c := addmod(kappa1_pow3, addmod(kappa2, kappa2_pow2, R_MOD), R_MOD)
                //    d := -κ1^3R_{x,y} - κ2R’_{x,y} - κ2^2R’’_{x,y} - κ1V_{x,y} - κ1^4A_{pub} 
                // => d := - (κ1^3R_{x,y} + κ2R’_{x,y} + κ2^2R’’_{x,y} + κ1V_{x,y} + κ1^4A_{pub})
                let d := sub(R_MOD,addmod(addmod(addmod(mulmod(kappa1_pow3, r1, R_MOD),mulmod(kappa2, r2, R_MOD), R_MOD), mulmod(kappa2_pow2, r3, R_MOD), R_MOD), addmod(mulmod(kappa1, V_xy, R_MOD),mulmod(mulmod(kappa1, kappa1_pow3, R_MOD), A_pub, R_MOD),R_MOD),R_MOD))                
                // κ1^2(R_x,y - 1)
                let kappa1_r_minus_1 := mulmod(mulmod(kappa1, kappa1, R_MOD), sub(r1, 1), R_MOD)
                // κ1^2 * t_{m_l}(χ)
                let kappa1_tml := mulmod(kappa1_pow2, t_ml, R_MOD)
                // κ1^2 * t_{s_{max}}(ζ)
                let kappa1_tsmax := mulmod(kappa1_pow2, t_smax, R_MOD)
                
                g1pointMulIntoDest(POLY_KXLX_X_PART1, kappa1_r_minus_1, BUFFER_LHS_C_X_SLOT_PART1)
                g1pointMulAndAddIntoDest(INTERMERDIARY_POLY_G_X_SLOT_PART1, a, BUFFER_LHS_C_X_SLOT_PART1)

                g1pointMulIntoDest(INTERMERDIARY_POLY_F_X_SLOT_PART1, b, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                g1pointSubAssign(BUFFER_LHS_C_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                g1pointMulIntoDest(PROOF_POLY_QCX_X_SLOT_PART1, kappa1_tml, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                g1pointSubAssign(BUFFER_LHS_C_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                g1pointMulIntoDest(PROOF_POLY_QCY_X_SLOT_PART1, kappa1_tsmax, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                g1pointSubAssign(BUFFER_LHS_C_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                g1pointMulAndAddIntoDest(PROOF_POLY_R_X_SLOT_PART1, c, BUFFER_LHS_C_X_SLOT_PART1)
                g1pointMulAndAddIntoDest(IDENTITY_X_PART1, d, BUFFER_LHS_C_X_SLOT_PART1)

            }

            /// @dev [LHS]_1 := [LHS_B]_1 + κ2([LHS_A]_1 + [LHS_C]_1)
            /// @dev [AUX]_1 := κ2 * χ * [Π_{χ}]_1 + κ2 * ζ *([Π_ζ]_1 + [M_ζ]_1) + 
            ///                 κ2^2 * ω_{m_l}^{-1} * χ *[M_{χ}]_1 + κ2^3 * ω_{m_l}^{-1} * χ * [N_{χ}]_1 + κ_2 * ω_smax^{-1} * ζ * [N_{ζ}]
            function prepareAggregatedCommitment() {
                // calculate [LHS]_1
                {
                    let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                    g1pointAddIntoDest(BUFFER_LHS_A_X_SLOT_PART1, BUFFER_LHS_C_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                    g1pointMulIntoDest(BUFFER_AGGREGATED_POLY_X_SLOT_PART1, kappa2, PAIRING_BUFFER_LHS_X_SLOT_PART1)
                    g1pointAddIntoDest(BUFFER_LHS_B_X_SLOT_PART1, PAIRING_BUFFER_LHS_X_SLOT_PART1, PAIRING_BUFFER_LHS_X_SLOT_PART1)
                }

                // calculate [AUX]_1
                {
                    let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                    let chi := mload(CHALLENGE_CHI_SLOT)
                    let zeta := mload(CHALLENGE_ZETA_SLOT)
                    let omega_ml := mload(OMEGA_MI_MINUS_1)
                    let omega_smax := mload(OMEGA_SMAX_MINUS_1)

                    let kappa2_chi := mulmod(kappa2, chi, R_MOD)
                    let kappa2_zeta := mulmod(kappa2, zeta, R_MOD)
                    let kappa2_pow2_omega_ml_chi := mulmod(mulmod(mulmod(kappa2, kappa2, R_MOD), omega_ml, R_MOD), chi, R_MOD)
                    let kappa2_pow3_omega_ml_chi := mulmod(mulmod(mulmod(mulmod(kappa2, kappa2, R_MOD), kappa2, R_MOD), omega_ml, R_MOD), chi, R_MOD)
                    let kappa2_omega_smax_zeta := mulmod(mulmod(mulmod(kappa2, kappa2, R_MOD), omega_smax, R_MOD), zeta, R_MOD)

                    // [Π_{χ}]_1 := [Π_{A,χ}]_1 + [Π_{B,χ}]_1 + [Π_{C,χ}]_1
                    g1pointAddIntoDest(PROOF_POLY_PI_A_CHI_X_SLOT_PART1, PROOF_POLY_PI_B_CHI_X_SLOT_PART1, INTERMERDIARY_POLY_PI_CHI_X_SLOT_PART1)
                    g1pointAddIntoDest(INTERMERDIARY_POLY_PI_CHI_X_SLOT_PART1, PROOF_POLY_PI_C_CHI_X_SLOT_PART1, INTERMERDIARY_POLY_PI_CHI_X_SLOT_PART1)
                    // [Π_{χ}]_1 := [Π_{A,χ}]_1 + [Π_{B,χ}]_1 + [Π_{C,χ}]_1
                    g1pointAddIntoDest(PROOF_POLY_PI_A_ZETA_X_SLOT_PART1, PROOF_POLY_PI_C_ZETA_X_SLOT_PART1, INTERMERDIARY_POLY_PI_ZETA_X_SLOT_PART1)

                    // [AUX]_1 accumulation
                    // κ2 * χ * [Π_{χ}]_1
                    g1pointMulIntoDest(INTERMERDIARY_POLY_PI_CHI_X_SLOT_PART1, kappa2_chi, PAIRING_BUFFER_AUX_X_SLOT_PART1)
                    // [Π_ζ]_1 + [M_ζ]_1
                    g1pointAddIntoDest(INTERMERDIARY_POLY_PI_ZETA_X_SLOT_PART1, PROOF_POLY_M_ZETA_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                    //  += κ2 * ζ *([Π_ζ]_1 + [M_ζ]_1)
                    g1pointMulAndAddIntoDest(BUFFER_AGGREGATED_POLY_X_SLOT_PART1, kappa2_zeta, PAIRING_BUFFER_AUX_X_SLOT_PART1)
                    // += κ2^2 * ω_{m_l}^{-1} * χ *[M_{χ}]_1
                    g1pointMulAndAddIntoDest(PROOF_POLY_M_CHI_X_SLOT_PART1, kappa2_pow2_omega_ml_chi, PAIRING_BUFFER_AUX_X_SLOT_PART1)
                    // += κ2^3 * ω_{m_l}^{-1} * χ * [N_{χ}]_1
                    g1pointMulAndAddIntoDest(PROOF_POLY_N_CHI_X_SLOT_PART1, kappa2_pow3_omega_ml_chi, PAIRING_BUFFER_AUX_X_SLOT_PART1)
                    // += κ2 * ω_smax^{-1} * ζ * [N_{ζ}]
                    g1pointMulAndAddIntoDest(PROOF_POLY_N_ZETA_X_SLOT_PART1, kappa2_omega_smax_zeta, PAIRING_BUFFER_AUX_X_SLOT_PART1)

                }

            }

            /*////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                                        5. Pairing
            ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

            /// @notice Checks the final pairing
            /// @dev We should check the equation:
            ///
            ///    /                                                  \           /                                                          \  
            ///   | e([LHS]_1 + [AUX]_1, [1]_2)e([B]_1, [α^4]_2)       |         |  e([O_pub], [γ]_2])e([O_mid]_1, [η]_2)e([O_prv]_1, [δ]_2)  |
            ///   | e([U]_1, [α]_2)e([V]_1, [α^2]_2)e([W]_1, [α^3]_2)  |    =    |  . e(κ2[Π_{χ}]_1 + κ2^2[M_{χ}]_1 + κ2^3[N_{χ}]_1, [x]_2)   |
            ///    \                                                  /          |  . e(κ2[Π_{ζ}]_1 + κ2^2[M_{ζ}]_1 + κ2^3[N_{ζ}]_1, [y]_2)   |
            ///                                                                   \                                                          / 
            function finalPairing() {
                
            }

            // Step1: Load the PI/proof
            loadProof()

            // Step2: Recompute all the challenges with the transcript
            initializeTranscript()

            // Step3: computation of [F]_1, [G]_1, t_n(χ), t_smax(ζ) and t_ml(χ)
            prepareQueries()


            // Step4: computation of the final polynomial commitments
            prepareLHSA()
            prepareLHSB()
            prepareLHSC()
            prepareAggregatedCommitment()

            // Step5: final pairing
            finalPairing()
            

            result := 1
            mstore(0, true)
        }

    }
}