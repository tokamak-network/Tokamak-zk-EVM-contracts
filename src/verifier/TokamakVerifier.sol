    // SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ITokamakVerifier} from "../interface/ITokamakVerifier.sol";

/* solhint-disable max-line-length */
/// @author Project Ooo team
/// @dev It uses a custom memory layout inside the inline assembly block. Each reserved memory cell is declared in the
/// constants below.
/// @dev For a better understanding of the verifier algorithm please refer to the following papers:
/// *
/// * Original Tokamak zkSNARK Paper: https://eprint.iacr.org/2024/507.pdf
/// The notation used in the code is the same as in the papers.
/* solhint-enable max-line-length */
contract TokamakVerifier is ITokamakVerifier {
    /*//////////////////////////////////////////////////////////////
                                    Proof
    //////////////////////////////////////////////////////////////*/

    /// The encoding order of the `proof` (part1) is
    /// ```
    /// |                  672 bytes                 |
    /// | Polynomial commitments (16th first bytes)  |
    /// ```

    /// The encoding order of the `proof` (part2) is
    /// ```
    /// |               1344 bytes                |   32 bytes  |   32 bytes   |   32 bytes  |   32 bytes  |
    /// | Polynomial commitments (last 32 bytes)  |   R_{x,y}   |   R'_{x,y}   |   R''_{x,y} |   V_{x,y}   |
    /// ```

    // [s^{(0)}(x,y)]_1
    uint256 internal constant PUBLIC_INPUTS_S_0_X_SLOT_PART1 = 0x8000 + 0x200 + 0x040;
    uint256 internal constant PUBLIC_INPUTS_S_0_X_SLOT_PART2 = 0x8000 + 0x200 + 0x060;
    uint256 internal constant PUBLIC_INPUTS_S_0_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x080;
    uint256 internal constant PUBLIC_INPUTS_S_0_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x0a0;

    // [s^{(1)}(x,y)]_1
    uint256 internal constant PUBLIC_INPUTS_S_1_X_SLOT_PART1 = 0x8000 + 0x200 + 0x0c0;
    uint256 internal constant PUBLIC_INPUTS_S_1_X_SLOT_PART2 = 0x8000 + 0x200 + 0x0e0;
    uint256 internal constant PUBLIC_INPUTS_S_1_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x100;
    uint256 internal constant PUBLIC_INPUTS_S_1_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120;

    // U
    uint256 internal constant PROOF_POLY_U_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x020;
    uint256 internal constant PROOF_POLY_U_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x040;
    uint256 internal constant PROOF_POLY_U_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x060;
    uint256 internal constant PROOF_POLY_U_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x080;
    // V
    uint256 internal constant PROOF_POLY_V_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x0a0;
    uint256 internal constant PROOF_POLY_V_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x0c0;
    uint256 internal constant PROOF_POLY_V_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x0e0;
    uint256 internal constant PROOF_POLY_V_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x100;
    // W
    uint256 internal constant PROOF_POLY_W_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x120;
    uint256 internal constant PROOF_POLY_W_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x140;
    uint256 internal constant PROOF_POLY_W_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x160;
    uint256 internal constant PROOF_POLY_W_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x180;
    // O_mid
    uint256 internal constant PROOF_POLY_OMID_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x1a0;
    uint256 internal constant PROOF_POLY_OMID_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x1c0;
    uint256 internal constant PROOF_POLY_OMID_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x1e0;
    uint256 internal constant PROOF_POLY_OMID_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x200;
    // O_prv
    uint256 internal constant PROOF_POLY_OPRV_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x220;
    uint256 internal constant PROOF_POLY_OPRV_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x240;
    uint256 internal constant PROOF_POLY_OPRV_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x260;
    uint256 internal constant PROOF_POLY_OPRV_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x280;
    // Q_{AX}
    uint256 internal constant PROOF_POLY_QAX_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x2a0;
    uint256 internal constant PROOF_POLY_QAX_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x2c0;
    uint256 internal constant PROOF_POLY_QAX_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x2e0;
    uint256 internal constant PROOF_POLY_QAX_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x300;
    // Q_{AY}
    uint256 internal constant PROOF_POLY_QAY_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x320;
    uint256 internal constant PROOF_POLY_QAY_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x340;
    uint256 internal constant PROOF_POLY_QAY_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x360;
    uint256 internal constant PROOF_POLY_QAY_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x380;
    // Q_{CX}
    uint256 internal constant PROOF_POLY_QCX_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x3a0;
    uint256 internal constant PROOF_POLY_QCX_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x3c0;
    uint256 internal constant PROOF_POLY_QCX_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x3e0;
    uint256 internal constant PROOF_POLY_QCX_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x400;
    // Q_{CY}
    uint256 internal constant PROOF_POLY_QCY_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x420;
    uint256 internal constant PROOF_POLY_QCY_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x440;
    uint256 internal constant PROOF_POLY_QCY_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x460;
    uint256 internal constant PROOF_POLY_QCY_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x480;
    // Π_{χ}
    uint256 internal constant PROOF_POLY_PI_CHI_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x4a0;
    uint256 internal constant PROOF_POLY_PI_CHI_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x4c0;
    uint256 internal constant PROOF_POLY_PI_CHI_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x4e0;
    uint256 internal constant PROOF_POLY_PI_CHI_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x500;
    // Π{ζ}
    uint256 internal constant PROOF_POLY_PI_ZETA_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x520;
    uint256 internal constant PROOF_POLY_PI_ZETA_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x540;
    uint256 internal constant PROOF_POLY_PI_ZETA_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x560;
    uint256 internal constant PROOF_POLY_PI_ZETA_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x580;
    // B
    uint256 internal constant PROOF_POLY_B_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x5a0;
    uint256 internal constant PROOF_POLY_B_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x5c0;
    uint256 internal constant PROOF_POLY_B_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x5e0;
    uint256 internal constant PROOF_POLY_B_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x600;
    // R
    uint256 internal constant PROOF_POLY_R_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x620;
    uint256 internal constant PROOF_POLY_R_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x640;
    uint256 internal constant PROOF_POLY_R_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x660;
    uint256 internal constant PROOF_POLY_R_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x680;
    // M_ζ
    uint256 internal constant PROOF_POLY_M_ZETA_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x6a0;
    uint256 internal constant PROOF_POLY_M_ZETA_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x6c0;
    uint256 internal constant PROOF_POLY_M_ZETA_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x6e0;
    uint256 internal constant PROOF_POLY_M_ZETA_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x700;
    // M_χ
    uint256 internal constant PROOF_POLY_M_CHI_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x720;
    uint256 internal constant PROOF_POLY_M_CHI_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x740;
    uint256 internal constant PROOF_POLY_M_CHI_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x760;
    uint256 internal constant PROOF_POLY_M_CHI_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x780;
    // N_ζ
    uint256 internal constant PROOF_POLY_N_ZETA_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x7a0;
    uint256 internal constant PROOF_POLY_N_ZETA_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x7c0;
    uint256 internal constant PROOF_POLY_N_ZETA_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x7e0;
    uint256 internal constant PROOF_POLY_N_ZETA_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x800;
    // N_χ
    uint256 internal constant PROOF_POLY_N_CHI_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x820;
    uint256 internal constant PROOF_POLY_N_CHI_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x840;
    uint256 internal constant PROOF_POLY_N_CHI_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x860;
    uint256 internal constant PROOF_POLY_N_CHI_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x880;
    // O_pub
    uint256 internal constant PROOF_POLY_OPUB_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x8a0;
    uint256 internal constant PROOF_POLY_OPUB_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x8c0;
    uint256 internal constant PROOF_POLY_OPUB_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x8e0;
    uint256 internal constant PROOF_POLY_OPUB_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x900;
    // A
    uint256 internal constant PROOF_POLY_A_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x920;
    uint256 internal constant PROOF_POLY_A_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x940;
    uint256 internal constant PROOF_POLY_A_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x960;
    uint256 internal constant PROOF_POLY_A_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x980;
    // R_xy
    uint256 internal constant PROOF_R1XY_SLOT = 0x8000 + 0x200 + 0x120 + 0x9a0;
    // R'_xy
    uint256 internal constant PROOF_R2XY_SLOT = 0x8000 + 0x200 + 0x120 + 0x9c0;
    // R''_xy
    uint256 internal constant PROOF_R3XY_SLOT = 0x8000 + 0x200 + 0x120 + 0x9e0;
    // V_xy
    uint256 internal constant PROOF_VXY_SLOT = 0x8000 + 0x200 + 0x120 + 0xa00;

    /*//////////////////////////////////////////////////////////////
                transcript slot (used for challenge computation)
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant TRANSCRIPT_BEGIN_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x00;
    uint256 internal constant TRANSCRIPT_DST_BYTE_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x03;
    uint256 internal constant TRANSCRIPT_STATE_0_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x04;
    uint256 internal constant TRANSCRIPT_STATE_1_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x24;
    uint256 internal constant TRANSCRIPT_CHALLENGE_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x44;

    /*//////////////////////////////////////////////////////////////
                                Challenges
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant CHALLENGE_THETA_0_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x000;
    uint256 internal constant CHALLENGE_THETA_1_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x020;
    uint256 internal constant CHALLENGE_THETA_2_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x040;
    uint256 internal constant CHALLENGE_KAPPA_0_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x060;
    uint256 internal constant CHALLENGE_KAPPA_1_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x080;
    uint256 internal constant CHALLENGE_KAPPA_2_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x0a0;
    uint256 internal constant CHALLENGE_ZETA_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x0c0;
    uint256 internal constant CHALLENGE_XI_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x0e0;
    uint256 internal constant CHALLENGE_CHI_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100;

    /*//////////////////////////////////////////////////////////////
                        Intermediary verifier state
    //////////////////////////////////////////////////////////////*/

    // [F]_1
    uint256 internal constant INTERMERDIARY_POLY_F_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x020;
    uint256 internal constant INTERMERDIARY_POLY_F_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x040;
    uint256 internal constant INTERMERDIARY_POLY_F_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x060;
    uint256 internal constant INTERMERDIARY_POLY_F_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x080;

    // [G]_1
    uint256 internal constant INTERMERDIARY_POLY_G_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x0a0;
    uint256 internal constant INTERMERDIARY_POLY_G_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x0c0;
    uint256 internal constant INTERMERDIARY_POLY_G_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x0e0;
    uint256 internal constant INTERMERDIARY_POLY_G_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x100;

    // t_n(χ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_N_CHI_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x120;
    // t_smax(ζ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x140;
    // t_ml(χ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_MI_CHI_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x160;
    // K_0(χ)
    uint256 internal constant INTERMEDIARY_SCALAR_KO_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x180;
    // A_pub
    uint256 internal constant INTERMEDIARY_SCALAR_APUB_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0;

    /*//////////////////////////////////////////////////////////////
                      Aggregated commitment
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant AGG_LHS_A_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x020;
    uint256 internal constant AGG_LHS_A_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x040;
    uint256 internal constant AGG_LHS_A_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x060;
    uint256 internal constant AGG_LHS_A_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x080;

    uint256 internal constant AGG_LHS_B_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x0a0;
    uint256 internal constant AGG_LHS_B_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x0c0;
    uint256 internal constant AGG_LHS_B_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x0e0;
    uint256 internal constant AGG_LHS_B_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x100;

    uint256 internal constant AGG_LHS_C_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x120;
    uint256 internal constant AGG_LHS_C_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x140;
    uint256 internal constant AGG_LHS_C_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x160;
    uint256 internal constant AGG_LHS_C_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x180;

    uint256 internal constant PAIRING_AGG_LHS_X_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x1a0;
    uint256 internal constant PAIRING_AGG_LHS_X_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x1c0;
    uint256 internal constant PAIRING_AGG_LHS_Y_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x1e0;
    uint256 internal constant PAIRING_AGG_LHS_Y_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x200;

    uint256 internal constant PAIRING_AGG_AUX_X_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x220;
    uint256 internal constant PAIRING_AGG_AUX_X_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x240;
    uint256 internal constant PAIRING_AGG_AUX_Y_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x260;
    uint256 internal constant PAIRING_AGG_AUX_Y_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x280;

    uint256 internal constant PAIRING_AGG_LHS_AUX_X_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x2a0;
    uint256 internal constant PAIRING_AGG_LHS_AUX_X_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x2c0;
    uint256 internal constant PAIRING_AGG_LHS_AUX_Y_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x2e0;
    uint256 internal constant PAIRING_AGG_LHS_AUX_Y_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x300;

    uint256 internal constant PAIRING_AGG_RHS_1_X_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x320;
    uint256 internal constant PAIRING_AGG_RHS_1_X_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x340;
    uint256 internal constant PAIRING_AGG_RHS_1_Y_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x360;
    uint256 internal constant PAIRING_AGG_RHS_1_Y_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x380;

    uint256 internal constant PAIRING_AGG_RHS_2_X_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x3a0;
    uint256 internal constant PAIRING_AGG_RHS_2_X_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x3c0;
    uint256 internal constant PAIRING_AGG_RHS_2_Y_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x3e0;
    uint256 internal constant PAIRING_AGG_RHS_2_Y_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x400;

    /*//////////////////////////////////////////////////////////////
                                Pairing data
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant BUFFER_AGGREGATED_POLY_X_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x420;
    uint256 internal constant BUFFER_AGGREGATED_POLY_X_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x440;
    uint256 internal constant BUFFER_AGGREGATED_POLY_Y_SLOT_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x460;
    uint256 internal constant BUFFER_AGGREGATED_POLY_Y_SLOT_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480;

    /*//////////////////////////////////////////////////////////////
                            Verification keys
    //////////////////////////////////////////////////////////////*/

    // [K^_1(X)L^-1(X)]_1
    uint256 internal constant VK_POLY_KXLX_X_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x020;
    uint256 internal constant VK_POLY_KXLX_X_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x040;
    uint256 internal constant VK_POLY_KXLX_Y_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x060;
    uint256 internal constant VK_POLY_KXLX_Y_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x080;

    // [x]_1
    uint256 internal constant VK_POLY_X_X_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x0a0;
    uint256 internal constant VK_POLY_X_X_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x0c0;
    uint256 internal constant VK_POLY_X_Y_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x0e0;
    uint256 internal constant VK_POLY_X_Y_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x100;

    // [y]_1
    uint256 internal constant VK_POLY_Y_X_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x120;
    uint256 internal constant VK_POLY_Y_X_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x140;
    uint256 internal constant VK_POLY_Y_Y_PART1 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x160;
    uint256 internal constant VK_POLY_Y_Y_PART2 = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x180;

    // [1]_1
    uint256 internal constant VK_IDENTITY_X_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x1a0;
    uint256 internal constant VK_IDENTITY_X_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x1c0;
    uint256 internal constant VK_IDENTITY_Y_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x1e0;
    uint256 internal constant VK_IDENTITY_Y_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x200;

    /*//////////////////////////////////////////////////////////////
                                trusted-setup param
    //////////////////////////////////////////////////////////////*/

    // smax
    uint256 internal constant PARAM_SMAX = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x200 + 0x020;

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

    // n
    uint256 internal constant CONSTANT_N = 2048;
    // ω_512
    uint256 internal constant OMEGA_512 = 0x1bb466679a5d88b1ecfbede342dee7f415c1ad4c687f28a233811ea1fe0c65f4;
    // m_i
    uint256 internal constant CONSTANT_MI = 2048;

    // ω_{m_i}^{-1}
    uint256 internal constant OMEGA_MI_1 = 0x394fda0d65ba213edeae67bc36f376e13cc5bb329aa58ff53dc9e5600f6fb2ac;

    // ω_smax_64^{-1}
    uint256 internal constant OMEGA_SMAX_64_MINUS_1 = 0x199cdaee7b3c79d6566009b5882952d6a41e85011d426b52b891fa3f982b68c5;
    // ω_smax_128^{-1}
    uint256 internal constant OMEGA_SMAX_128_MINUS_1 =
        0x1996fa8d52f970ba51420be43501370b166fb582ac74db12571ba2fccf28601b;
    // ω_smax_256^{-1}
    uint256 internal constant OMEGA_SMAX_256_MINUS_1 =
        0x6d64ed25272e58ee91b000235a5bfd4fc03cae032393991be9561c176a2f777a;
    // ω_smax_512^{-1}
    uint256 internal constant OMEGA_SMAX_512_MINUS_1 =
        0x1907a56e80f82b2df675522e37ad4eca1c510ebfb4543a3efb350dbef02a116e;
    // ω_smax_1024^{-1}
    uint256 internal constant OMEGA_SMAX_1024_MINUS_1 =
        0x2bcd9508a3dad316105f067219141f4450a32c41aa67e0beb0ad80034eb71aa6;
    // ω_smax_2048^{-1}
    uint256 internal constant OMEGA_SMAX_2048_MINUS_1 =
        0x394fda0d65ba213edeae67bc36f376e13cc5bb329aa58ff53dc9e5600f6fb2ac;

    /*//////////////////////////////////////////////////////////////
                            G2 elements
        //////////////////////////////////////////////////////////////*/

    // G2 Points for zkEVM Verifier (BLS12-381) - Standard Naming Convention
    // Each point uses 8 uint256 slots (256 bytes total)
    // Format: X0_PART1, X0_PART2, X1_PART1, X1_PART2, Y0_PART1, Y0_PART2, Y1_PART1, Y1_PART2

    //H: G2serde(Affine { x: 0x1116094a7c01d4fd8abcfea69c658c92c037765bee00556b8d4063c33540b316ac68a2d913d3adc3b43c7d7cc7505cfc17206c8ae661f247979b3f1daa7fb6d5f7ce9c17b5ed1d7e8b421a2508b3f09a603e6a5fab3fcde7364fd178d656ac36, y: 0x15bf297a4b9842fb1a3a6f2dbf6b94de06997b11b2f72436c22efbb48d2f74b0de7239ea182a2ee50c23ae3d0be6fdee09459611409874fe4b04b1a7e42cb84eb4ae01728dc55dbd1343fda8d0fe94a299fc757acc1d2602a49a005b4ff90190 })
    // [1]_2 (Identity/Generator point H)
    uint256 internal constant IDENTITY2_X0_PART1 = 0x000000000000000000000000000000001116094a7c01d4fd8abcfea69c658c92;
    uint256 internal constant IDENTITY2_X0_PART2 = 0xc037765bee00556b8d4063c33540b316ac68a2d913d3adc3b43c7d7cc7505cfc;
    uint256 internal constant IDENTITY2_X1_PART1 = 0x0000000000000000000000000000000017206c8ae661f247979b3f1daa7fb6d5;
    uint256 internal constant IDENTITY2_X1_PART2 = 0xf7ce9c17b5ed1d7e8b421a2508b3f09a603e6a5fab3fcde7364fd178d656ac36;
    uint256 internal constant IDENTITY2_Y0_PART1 = 0x0000000000000000000000000000000015bf297a4b9842fb1a3a6f2dbf6b94de;
    uint256 internal constant IDENTITY2_Y0_PART2 = 0x06997b11b2f72436c22efbb48d2f74b0de7239ea182a2ee50c23ae3d0be6fdee;
    uint256 internal constant IDENTITY2_Y1_PART1 = 0x0000000000000000000000000000000009459611409874fe4b04b1a7e42cb84e;
    uint256 internal constant IDENTITY2_Y1_PART2 = 0xb4ae01728dc55dbd1343fda8d0fe94a299fc757acc1d2602a49a005b4ff90190;

    //alpha: G2serde(Affine { x: 0x05fc26da747c6cfef0305b496594b460e39e12dca4aebacb2d4bb6d2c4b02b2c50fe7ffe6f33940434a15a9425aa82ed0494bd39f21522f3fe14c8f9283e3fa1e05e39e804bb1881ef4529958798c9b68126138e3594797bc2f7042824b7d97e, y: 0x11161b94b2a44106ed5b9226279a2469c0eccdfedd34359d8577b9d980b238e80b97ad277d2c3010e94054edfa20e2e00e0075cf9d5766c2f27a41f2ebaf2aa2029de98dae9e4ab91c03b2c36a905d1e31072a0999bcde2a3c7722870cf0a2ec })
    // [α]_2
    uint256 internal constant ALPHA_X0_PART1 = 0x0000000000000000000000000000000005fc26da747c6cfef0305b496594b460;
    uint256 internal constant ALPHA_X0_PART2 = 0xe39e12dca4aebacb2d4bb6d2c4b02b2c50fe7ffe6f33940434a15a9425aa82ed;
    uint256 internal constant ALPHA_X1_PART1 = 0x000000000000000000000000000000000494bd39f21522f3fe14c8f9283e3fa1;
    uint256 internal constant ALPHA_X1_PART2 = 0xe05e39e804bb1881ef4529958798c9b68126138e3594797bc2f7042824b7d97e;
    uint256 internal constant ALPHA_Y0_PART1 = 0x0000000000000000000000000000000011161b94b2a44106ed5b9226279a2469;
    uint256 internal constant ALPHA_Y0_PART2 = 0xc0eccdfedd34359d8577b9d980b238e80b97ad277d2c3010e94054edfa20e2e0;
    uint256 internal constant ALPHA_Y1_PART1 = 0x000000000000000000000000000000000e0075cf9d5766c2f27a41f2ebaf2aa2;
    uint256 internal constant ALPHA_Y1_PART2 = 0x029de98dae9e4ab91c03b2c36a905d1e31072a0999bcde2a3c7722870cf0a2ec;

    //alpha2: G2serde(Affine { x: 0x133162dff634e8ff94132dd738659db83d0618c48e8c6c8d5b0805ad237364eeaf06286440b00c8e68faeec4ed9c154b1065e41eba7012b1b416f58dd3bbdda89bf3a06944476337565ab07746065e3807f5a04f933453e48f3edb96b86f5e52, y: 0x19f032956715814f77a9bd9e06ccb681bf2af52adbbed8df7b01b04966db248c80b76328459349995d0780cfe4ac11ba0b13ca416c480313f7dfba208414d08412adecdc9f8b84e0ec2dcb4e532e2d6d1f6e6d2308bc7b4e38072e51d40c3d04 })
    // [α^2]_2
    uint256 internal constant ALPHA_POWER2_X0_PART1 = 0x00000000000000000000000000000000133162dff634e8ff94132dd738659db8;
    uint256 internal constant ALPHA_POWER2_X0_PART2 = 0x3d0618c48e8c6c8d5b0805ad237364eeaf06286440b00c8e68faeec4ed9c154b;
    uint256 internal constant ALPHA_POWER2_X1_PART1 = 0x000000000000000000000000000000001065e41eba7012b1b416f58dd3bbdda8;
    uint256 internal constant ALPHA_POWER2_X1_PART2 = 0x9bf3a06944476337565ab07746065e3807f5a04f933453e48f3edb96b86f5e52;
    uint256 internal constant ALPHA_POWER2_Y0_PART1 = 0x0000000000000000000000000000000019f032956715814f77a9bd9e06ccb681;
    uint256 internal constant ALPHA_POWER2_Y0_PART2 = 0xbf2af52adbbed8df7b01b04966db248c80b76328459349995d0780cfe4ac11ba;
    uint256 internal constant ALPHA_POWER2_Y1_PART1 = 0x000000000000000000000000000000000b13ca416c480313f7dfba208414d084;
    uint256 internal constant ALPHA_POWER2_Y1_PART2 = 0x12adecdc9f8b84e0ec2dcb4e532e2d6d1f6e6d2308bc7b4e38072e51d40c3d04;

    //alpha3: G2serde(Affine { x: 0x03f4debb62e445a8d577dfcb3b9e9e6fbfeff7390c23dae3c84bbe70394c5d8c8bfcd81f39ab65db1647ac9e7905a830048e5721d748709bdb68b01af622428ada2799bdb21845dad8e0e80ec4c02c89eb0a65f5f7f2b64a9d2f104ff9912c1a, y: 0x0c99a7e666f2e9bd896335d5ea1cd0d696fcc1fcc2658dc666f97f238a6ad6cb07997380d33e28beffb74262751b651011892c5548e7c5b9ed9d6e75d2507ff3285d8c4d9ac82b91766ae09f185bd4824f95abef13b87d3d96ed05635d7936b6 })
    // [α^3]_2
    uint256 internal constant ALPHA_POWER3_X0_PART1 = 0x0000000000000000000000000000000003f4debb62e445a8d577dfcb3b9e9e6f;
    uint256 internal constant ALPHA_POWER3_X0_PART2 = 0xbfeff7390c23dae3c84bbe70394c5d8c8bfcd81f39ab65db1647ac9e7905a830;
    uint256 internal constant ALPHA_POWER3_X1_PART1 = 0x00000000000000000000000000000000048e5721d748709bdb68b01af622428a;
    uint256 internal constant ALPHA_POWER3_X1_PART2 = 0xda2799bdb21845dad8e0e80ec4c02c89eb0a65f5f7f2b64a9d2f104ff9912c1a;
    uint256 internal constant ALPHA_POWER3_Y0_PART1 = 0x000000000000000000000000000000000c99a7e666f2e9bd896335d5ea1cd0d6;
    uint256 internal constant ALPHA_POWER3_Y0_PART2 = 0x96fcc1fcc2658dc666f97f238a6ad6cb07997380d33e28beffb74262751b6510;
    uint256 internal constant ALPHA_POWER3_Y1_PART1 = 0x0000000000000000000000000000000011892c5548e7c5b9ed9d6e75d2507ff3;
    uint256 internal constant ALPHA_POWER3_Y1_PART2 = 0x285d8c4d9ac82b91766ae09f185bd4824f95abef13b87d3d96ed05635d7936b6;

    //alpha4: G2serde(Affine { x: 0x119487452ff2249b913d3615596b23ed798963dce3e84bb1cda6d8275420d78d6b8c689444b44d6abf94336be9344f050fd4fedaf2dea68d920f1de7dd6136c094d9e733600996a597cd54aa910474408470624188e655f7f7fd28e490d561d8, y: 0x036d8893301ebf86f558727a258d0c01e274a405033f63d35a80b7547f9f893ff9502295e54dae44f0f40052d89c93f615774c7ad74887b825aa76fbc677f95caaf2fc055bc4cf92385d115876a2032e71455bcbc47323cfa19b1b0f44a681dc })
    // [α^4]_2
    uint256 internal constant ALPHA_POWER4_X0_PART1 = 0x00000000000000000000000000000000119487452ff2249b913d3615596b23ed;
    uint256 internal constant ALPHA_POWER4_X0_PART2 = 0x798963dce3e84bb1cda6d8275420d78d6b8c689444b44d6abf94336be9344f05;
    uint256 internal constant ALPHA_POWER4_X1_PART1 = 0x000000000000000000000000000000000fd4fedaf2dea68d920f1de7dd6136c0;
    uint256 internal constant ALPHA_POWER4_X1_PART2 = 0x94d9e733600996a597cd54aa910474408470624188e655f7f7fd28e490d561d8;
    uint256 internal constant ALPHA_POWER4_Y0_PART1 = 0x00000000000000000000000000000000036d8893301ebf86f558727a258d0c01;
    uint256 internal constant ALPHA_POWER4_Y0_PART2 = 0xe274a405033f63d35a80b7547f9f893ff9502295e54dae44f0f40052d89c93f6;
    uint256 internal constant ALPHA_POWER4_Y1_PART1 = 0x0000000000000000000000000000000015774c7ad74887b825aa76fbc677f95c;
    uint256 internal constant ALPHA_POWER4_Y1_PART2 = 0xaaf2fc055bc4cf92385d115876a2032e71455bcbc47323cfa19b1b0f44a681dc;

    //-gamma: G2serde(Affine { x: 0x0c5f05ae1cd7c8c9d23904a90041ba698baf0a264bfd553d2c4f9b51ac51795839aef12df95d82ca94bb88b705ac9c6518356bdcacde783dd402ae3b1b7004e365385d828b938721c6e17ecff44403ceeed486592da4e2acb6ad1a99d1ac7a10, y: 0x02c8345a6ed2c39c85d0060afda056f4afd58411c2f9bd04796de3d47fcf2437001ebafd8c378514f7bfc58d597bbdaa17227dbdfedcb0e7bab68b1a59ae7265b4e308f8c0343efe071a972e1c7eb3a6ee204a485782bcbc19d04ef85afc35ba })
    // -[γ]_2 (negated for pairing)
    uint256 internal constant GAMMA_X0_PART1 = 0x000000000000000000000000000000000c5f05ae1cd7c8c9d23904a90041ba69;
    uint256 internal constant GAMMA_X0_PART2 = 0x8baf0a264bfd553d2c4f9b51ac51795839aef12df95d82ca94bb88b705ac9c65;
    uint256 internal constant GAMMA_X1_PART1 = 0x0000000000000000000000000000000018356bdcacde783dd402ae3b1b7004e3;
    uint256 internal constant GAMMA_X1_PART2 = 0x65385d828b938721c6e17ecff44403ceeed486592da4e2acb6ad1a99d1ac7a10;
    uint256 internal constant GAMMA_Y0_PART1 = 0x0000000000000000000000000000000002c8345a6ed2c39c85d0060afda056f4;
    uint256 internal constant GAMMA_Y0_PART2 = 0xafd58411c2f9bd04796de3d47fcf2437001ebafd8c378514f7bfc58d597bbdaa;
    uint256 internal constant GAMMA_Y1_PART1 = 0x0000000000000000000000000000000017227dbdfedcb0e7bab68b1a59ae7265;
    uint256 internal constant GAMMA_Y1_PART2 = 0xb4e308f8c0343efe071a972e1c7eb3a6ee204a485782bcbc19d04ef85afc35ba;

    //-eta: G2serde(Affine { x: 0x0dee20e8a1a4601b8b8498881220ca31036ee005b261f0cda1a47cd364094ac493a9446f69c00c18b85920798b7189790d952a8d8d2e7ab7774f04402897938d621ea0baf138e19617c320a2ec5de9d7694efef008994bc7a1b9f96939e38141, y: 0x008fe985823f536253d44624957d6cb56688c976fb9500a5de0f60e5b0ea13ded0f9b52bea37878fab734649ddc9416014584ce9324f72a304457fcd578a051a906515cd3d07ad3c146e9c4fceb44599219770bd16033d3e328cdfe9ba0040f4 })
    // -[η]_2 (negated for pairing)
    uint256 internal constant ETA_X0_PART1 = 0x000000000000000000000000000000000dee20e8a1a4601b8b8498881220ca31;
    uint256 internal constant ETA_X0_PART2 = 0x036ee005b261f0cda1a47cd364094ac493a9446f69c00c18b85920798b718979;
    uint256 internal constant ETA_X1_PART1 = 0x000000000000000000000000000000000d952a8d8d2e7ab7774f04402897938d;
    uint256 internal constant ETA_X1_PART2 = 0x621ea0baf138e19617c320a2ec5de9d7694efef008994bc7a1b9f96939e38141;
    uint256 internal constant ETA_Y0_PART1 = 0x00000000000000000000000000000000008fe985823f536253d44624957d6cb5;
    uint256 internal constant ETA_Y0_PART2 = 0x6688c976fb9500a5de0f60e5b0ea13ded0f9b52bea37878fab734649ddc94160;
    uint256 internal constant ETA_Y1_PART1 = 0x0000000000000000000000000000000014584ce9324f72a304457fcd578a051a;
    uint256 internal constant ETA_Y1_PART2 = 0x906515cd3d07ad3c146e9c4fceb44599219770bd16033d3e328cdfe9ba0040f4;

    //-delta: G2serde(Affine { x: 0x0d82e8b936233a9bfaf7587777b2ae7e2daa56831d2105076d0140015a9a299a42656cfa6149dc45246c121a37f05ffe04718ed40c6f593d1bdd16b161bd662fe33f1d39c3eab8548a90e0b8d15b2f68fcc73b63694e46f773c101ce369e57f6, y: 0x0ced763d46e2c7a1b36e7906825b663f16b6ee1eb58e77f918d2476a2afe5481b95c9fbfe525a77ece5004631ae82f9304a088624a997f337758547f065202f0900c0af7e6dedb86f4e4ce228d6e36e855f7a22a6a026478290b35b12161d339 })
    // -[δ]_2 (negated for pairing)
    uint256 internal constant DELTA_X0_PART1 = 0x000000000000000000000000000000000d82e8b936233a9bfaf7587777b2ae7e;
    uint256 internal constant DELTA_X0_PART2 = 0x2daa56831d2105076d0140015a9a299a42656cfa6149dc45246c121a37f05ffe;
    uint256 internal constant DELTA_X1_PART1 = 0x0000000000000000000000000000000004718ed40c6f593d1bdd16b161bd662f;
    uint256 internal constant DELTA_X1_PART2 = 0xe33f1d39c3eab8548a90e0b8d15b2f68fcc73b63694e46f773c101ce369e57f6;
    uint256 internal constant DELTA_Y0_PART1 = 0x000000000000000000000000000000000ced763d46e2c7a1b36e7906825b663f;
    uint256 internal constant DELTA_Y0_PART2 = 0x16b6ee1eb58e77f918d2476a2afe5481b95c9fbfe525a77ece5004631ae82f93;
    uint256 internal constant DELTA_Y1_PART1 = 0x0000000000000000000000000000000004a088624a997f337758547f065202f0;
    uint256 internal constant DELTA_Y1_PART2 = 0x900c0af7e6dedb86f4e4ce228d6e36e855f7a22a6a026478290b35b12161d339;

    //-x: G2serde(Affine { x: 0x05fc26da747c6cfef0305b496594b460e39e12dca4aebacb2d4bb6d2c4b02b2c50fe7ffe6f33940434a15a9425aa82ed0494bd39f21522f3fe14c8f9283e3fa1e05e39e804bb1881ef4529958798c9b68126138e3594797bc2f7042824b7d97e, y: 0x08eaf65586dba5935dc015901bb1886da38a7d861650dd21e1b918c775febd3c131452d73427cfeed0beab1205dec7cb0c009c1a9c287fd758a165c3579c823561d961f744e6c8064b2d1fdd8c209905eda4d5f5179721d57d87dd78f30f07bf })
    // -[x]_2 (negated for pairing)
    uint256 internal constant X_X0_PART1 = 0x0000000000000000000000000000000005fc26da747c6cfef0305b496594b460;
    uint256 internal constant X_X0_PART2 = 0xe39e12dca4aebacb2d4bb6d2c4b02b2c50fe7ffe6f33940434a15a9425aa82ed;
    uint256 internal constant X_X1_PART1 = 0x000000000000000000000000000000000494bd39f21522f3fe14c8f9283e3fa1;
    uint256 internal constant X_X1_PART2 = 0xe05e39e804bb1881ef4529958798c9b68126138e3594797bc2f7042824b7d97e;
    uint256 internal constant X_Y0_PART1 = 0x0000000000000000000000000000000008eaf65586dba5935dc015901bb1886d;
    uint256 internal constant X_Y0_PART2 = 0xa38a7d861650dd21e1b918c775febd3c131452d73427cfeed0beab1205dec7cb;
    uint256 internal constant X_Y1_PART1 = 0x000000000000000000000000000000000c009c1a9c287fd758a165c3579c8235;
    uint256 internal constant X_Y1_PART2 = 0x61d961f744e6c8064b2d1fdd8c209905eda4d5f5179721d57d87dd78f30f07bf;

    //-y: G2serde(Affine { x: 0x0de2cd58780b23995a0e7795b1bde089da3ce45ff2cbce991549908da59ec96266cc2f9654c1b266a658997482afb0e10366edab3105b9b73a7730d96163c2c9e90109fc5ab19667422a2b9487c0be72dd9dd43d36956c324fcdcf53675a9f80, y: 0x141fa81ff24c54735cc358459366792096241a20e596a6e4ed95f8b8b149c7d20aeff35306317d6f8d18caf9953eebba14379f9fd21f1e8b838e6d58334313082e99282b71132b41f1e4c97dcccd725b09968dda8f9e56c24bddd4412e61299e })
    // -[y]_2 (negated for pairing)
    uint256 internal constant Y_X0_PART1 = 0x000000000000000000000000000000000de2cd58780b23995a0e7795b1bde089;
    uint256 internal constant Y_X0_PART2 = 0xda3ce45ff2cbce991549908da59ec96266cc2f9654c1b266a658997482afb0e1;
    uint256 internal constant Y_X1_PART1 = 0x000000000000000000000000000000000366edab3105b9b73a7730d96163c2c9;
    uint256 internal constant Y_X1_PART2 = 0xe90109fc5ab19667422a2b9487c0be72dd9dd43d36956c324fcdcf53675a9f80;
    uint256 internal constant Y_Y0_PART1 = 0x00000000000000000000000000000000141fa81ff24c54735cc3584593667920;
    uint256 internal constant Y_Y0_PART2 = 0x96241a20e596a6e4ed95f8b8b149c7d20aeff35306317d6f8d18caf9953eebba;
    uint256 internal constant Y_Y1_PART1 = 0x0000000000000000000000000000000014379f9fd21f1e8b838e6d5833431308;
    uint256 internal constant Y_Y1_PART2 = 0x2e99282b71132b41f1e4c97dcccd725b09968dda8f9e56c24bddd4412e61299e;

    /// @notice Load verification keys to memory in runtime.
    /// @dev The constants are loaded into memory in a specific layout declared in the constants starting from
    /// `VK_` prefix.
    /// NOTE: Function may corrupt the memory state if some memory was used before this function was called.
    function _loadVerificationKey() internal pure virtual {
        assembly {
            /*
            "lagrange_KL": {
                "x": "0x04f1e1a2ec023aef31bde5b77da1e69ddf5f0bc762904ccee1e8b0131e517246ccf938b28f294dcaca7dbd0c36ff3607",
                "y": "0x13440b9abcae5c5c5749fbc390065d1edea2da1ca7a4f63960dc958c9f32d289c3df14028dc7262642cc1466d6745bef"
            }
            */
            // preproccessed KL commitment vk
            mstore(VK_POLY_KXLX_X_PART1, 0x0000000000000000000000000000000004f1e1a2ec023aef31bde5b77da1e69d)
            mstore(VK_POLY_KXLX_X_PART2, 0xdf5f0bc762904ccee1e8b0131e517246ccf938b28f294dcaca7dbd0c36ff3607)
            mstore(VK_POLY_KXLX_Y_PART1, 0x0000000000000000000000000000000013440b9abcae5c5c5749fbc390065d1e)
            mstore(VK_POLY_KXLX_Y_PART2, 0xdea2da1ca7a4f63960dc958c9f32d289c3df14028dc7262642cc1466d6745bef)

            /*
            "G": {
                "x": "0x0b001b4cc05fa01578be7d4e821d6ff58f2a05c584fba3cb31a37942dece65eadec9a878add2282f7c2513abb8d4ab05",
                "y": "0x15e237775397ed22eef43dd36cdca277c9cf6fa7e4ffff0a5bb4b20a82392caacf0f63fb6cdb02bccf2f5af14970d6b9"
            },
            */
            // [1]_1 (Generator/Identity point)
            mstore(VK_IDENTITY_X_PART1, 0x000000000000000000000000000000000b001b4cc05fa01578be7d4e821d6ff5)
            mstore(VK_IDENTITY_X_PART2, 0x8f2a05c584fba3cb31a37942dece65eadec9a878add2282f7c2513abb8d4ab05)
            mstore(VK_IDENTITY_Y_PART1, 0x0000000000000000000000000000000015e237775397ed22eef43dd36cdca277)
            mstore(VK_IDENTITY_Y_PART2, 0xc9cf6fa7e4ffff0a5bb4b20a82392caacf0f63fb6cdb02bccf2f5af14970d6b9)

            /*
            "x": {
                "x": "0x0d45aca9cf6986877b859616c9613dfe38633f32c81a5a5e426f37beb4f1f9a8db94bcb17673c014031ed6f80406ae12",
                "y": "0x014de0221674a94bd5e60383f1f262d100c79178775b99480ec1a267fb28c905389357c2c111b94becf8676365f64133"
            },
            */
            // [x]_1 (Polynomial evaluation point)
            mstore(VK_POLY_X_X_PART1, 0x000000000000000000000000000000000d45aca9cf6986877b859616c9613dfe)
            mstore(VK_POLY_X_X_PART2, 0x38633f32c81a5a5e426f37beb4f1f9a8db94bcb17673c014031ed6f80406ae12)
            mstore(VK_POLY_X_Y_PART1, 0x00000000000000000000000000000000014de0221674a94bd5e60383f1f262d1)
            mstore(VK_POLY_X_Y_PART2, 0x00c79178775b99480ec1a267fb28c905389357c2c111b94becf8676365f64133)

            /*
            "y": {
                "x": "0x09cf106b4240325df41d6a76331883cbe61a678d7d877bf670446001be74d27580424e05a37af26bb85f99b380758888",
                "y": "0x0889c802a90694c68dfbcf207205778a7493cda2cbb6f9fb0b5ad39dbeef2fac91d847cc01d6040164ef30d840395af0"
            }
            */
            // [y]_1 (Polynomial evaluation point)
            mstore(VK_POLY_Y_X_PART1, 0x0000000000000000000000000000000009cf106b4240325df41d6a76331883cb)
            mstore(VK_POLY_Y_X_PART2, 0xe61a678d7d877bf670446001be74d27580424e05a37af26bb85f99b380758888)
            mstore(VK_POLY_Y_Y_PART1, 0x000000000000000000000000000000000889c802a90694c68dfbcf207205778a)
            mstore(VK_POLY_Y_Y_PART2, 0x7493cda2cbb6f9fb0b5ad39dbeef2fac91d847cc01d6040164ef30d840395af0)
        }
    }

    function verify(
        uint128[] calldata, //_proof part1 (16 bytes)
        uint256[] calldata, // _proof part2 (32 bytes)
        uint128[] calldata, // _preprocessedPart1 (16 bytes)
        uint256[] calldata, // _preprocessedPart2 (32 bytes)
        uint256[] calldata, // publicInputs (used for computing A_pub)
        uint256 // smax
    ) public view virtual returns (bool final_result) {
        // No memory was accessed yet, so keys can be loaded into the right place and not corrupt any other memory.
        _loadVerificationKey();

        // Beginning of the big inline assembly block that makes all the verification work.
        // Note: We use the custom memory layout, so the return value should be returned from the assembly, not
        // Solidity code.
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
                    revertWithMessage(30, "g1pointMulIntoDest: G1MSM failed")
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
                    revertWithMessage(30, "g1pointAddIntoDest: G1ADD failed")
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

                if iszero(success) { revertWithMessage(22, "g1pointMulAndAddIntoDest") }
            }

            /// @dev Performs a point subtraction operation and updates the first point with the result.
            function g1pointSubAssign(p1, p2) {
                // We'll use the fact that for BLS12-381 with 48-byte coordinates,
                // the precompile expects the full 384-bit representation

                // Copy p1 to memory
                mstore(0x00, mload(p1))
                mstore(0x20, mload(add(p1, 0x20)))
                mstore(0x40, mload(add(p1, 0x40)))
                mstore(0x60, mload(add(p1, 0x60)))

                // Copy p2's x-coordinate
                mstore(0x80, mload(p2))
                mstore(0xa0, mload(add(p2, 0x20)))

                // For the y-coordinate, we need to negate it
                // In BLS12-381, -y = q - y where q is the field modulus
                let y_low := mload(add(p2, 0x60))
                let y_high := mload(add(p2, 0x40))

                // Perform q - y
                let neg_y_low, neg_y_high

                // Since we're working with 384-bit numbers split into two 256-bit parts,
                // and the high 128 bits of the high part are always zero for valid field elements
                let borrow := 0

                // Subtract low part
                switch lt(Q_MOD_PART2, y_low)
                case 1 {
                    // Need to borrow from high part
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0)) // Add 2^256
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }
                default { neg_y_low := sub(Q_MOD_PART2, y_low) }

                // Subtract high part with borrow
                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)

                mstore(0xc0, neg_y_high)
                mstore(0xe0, neg_y_low)

                // Perform the addition
                if iszero(staticcall(gas(), 0x0b, 0x00, 0x100, p1, 0x80)) {
                    revertWithMessage(28, "pointSubAssign: G1ADD failed")
                }
            }

            /// @dev Performs a point subtraction operation and updates dest with the result.
            function g1pointSubIntoDest(p1, p2, dest) {
                // We'll use the fact that for BLS12-381 with 48-byte coordinates,
                // the precompile expects the full 384-bit representation

                // Copy p1 to memory
                mstore(0x00, mload(p1))
                mstore(0x20, mload(add(p1, 0x20)))
                mstore(0x40, mload(add(p1, 0x40)))
                mstore(0x60, mload(add(p1, 0x60)))

                // Copy p2's x-coordinate
                mstore(0x80, mload(p2))
                mstore(0xa0, mload(add(p2, 0x20)))

                // For the y-coordinate, we need to negate it
                // In BLS12-381, -y = q - y where q is the field modulus
                let y_low := mload(add(p2, 0x60))
                let y_high := mload(add(p2, 0x40))

                // Perform q - y
                let neg_y_low, neg_y_high

                // Since we're working with 384-bit numbers split into two 256-bit parts,
                // and the high 128 bits of the high part are always zero for valid field elements
                let borrow := 0

                // Subtract low part
                switch lt(Q_MOD_PART2, y_low)
                case 1 {
                    // Need to borrow from high part
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0)) // Add 2^256
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }
                default { neg_y_low := sub(Q_MOD_PART2, y_low) }

                // Subtract high part with borrow
                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)

                mstore(0xc0, neg_y_high)
                mstore(0xe0, neg_y_low)

                // Perform the addition
                if iszero(staticcall(gas(), 0x0b, 0x00, 0x100, dest, 0x80)) {
                    revertWithMessage(28, "pointSubAssign: G1ADD failed")
                }
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
                let offset := calldataload(0x04)
                let offset2 := calldataload(0x24)
                let offset3 := calldataload(0x44)
                let offset4 := calldataload(0x64)
                let part1LengthInWords := calldataload(add(offset, 0x04))
                let part2LengthInWords := calldataload(add(offset2, 0x04))
                let isValid := and(eq(part1LengthInWords, 38), eq(part2LengthInWords, 42))

                // revert if the length of the proof is not valid
                if iszero(isValid) { revertWithMessage(27, "loadProof: Proof is invalid") }

                // S PERMUTATION POLYNOMIALS
                {
                    let x0 := calldataload(add(offset3, 0x024))
                    let y0 := calldataload(add(offset3, 0x044))
                    let x1 := calldataload(add(offset3, 0x064))
                    let y1 := calldataload(add(offset3, 0x084))
                    mstore(PUBLIC_INPUTS_S_0_X_SLOT_PART1, x0)
                    mstore(PUBLIC_INPUTS_S_0_Y_SLOT_PART1, y0)
                    mstore(PUBLIC_INPUTS_S_1_X_SLOT_PART1, x1)
                    mstore(PUBLIC_INPUTS_S_1_Y_SLOT_PART1, y1)
                    x0 := calldataload(add(offset4, 0x024))
                    y0 := calldataload(add(offset4, 0x044))
                    x1 := calldataload(add(offset4, 0x064))
                    y1 := calldataload(add(offset4, 0x084))
                    mstore(PUBLIC_INPUTS_S_0_X_SLOT_PART2, x0)
                    mstore(PUBLIC_INPUTS_S_0_Y_SLOT_PART2, y0)
                    mstore(PUBLIC_INPUTS_S_1_X_SLOT_PART2, x1)
                    mstore(PUBLIC_INPUTS_S_1_Y_SLOT_PART2, y1)
                }
                // PROOF U, V & W
                {
                    let x0 := calldataload(add(offset, 0x024))
                    let y0 := calldataload(add(offset, 0x044))
                    let x1 := calldataload(add(offset, 0x064))
                    let y1 := calldataload(add(offset, 0x084))
                    let x2 := calldataload(add(offset, 0x0a4))
                    let y2 := calldataload(add(offset, 0x0c4))
                    mstore(PROOF_POLY_U_X_SLOT_PART1, x0)
                    mstore(PROOF_POLY_U_Y_SLOT_PART1, y0)
                    mstore(PROOF_POLY_V_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_V_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_W_X_SLOT_PART1, x2)
                    mstore(PROOF_POLY_W_Y_SLOT_PART1, y2)
                    x0 := calldataload(add(offset2, 0x024))
                    y0 := calldataload(add(offset2, 0x044))
                    x1 := calldataload(add(offset2, 0x064))
                    y1 := calldataload(add(offset2, 0x084))
                    x2 := calldataload(add(offset2, 0x0a4))
                    y2 := calldataload(add(offset2, 0x0c4))
                    mstore(PROOF_POLY_U_X_SLOT_PART2, x0)
                    mstore(PROOF_POLY_U_Y_SLOT_PART2, y0)
                    mstore(PROOF_POLY_V_X_SLOT_PART2, x1)
                    mstore(PROOF_POLY_V_Y_SLOT_PART2, y1)
                    mstore(PROOF_POLY_W_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_W_Y_SLOT_PART2, y2)
                }
                // PROOF O_MID & O_PRV
                {
                    let x0 := calldataload(add(offset, 0x0e4))
                    let y0 := calldataload(add(offset, 0x104))
                    let x1 := calldataload(add(offset, 0x124))
                    let y1 := calldataload(add(offset, 0x144))
                    mstore(PROOF_POLY_OMID_X_SLOT_PART1, x0)
                    mstore(PROOF_POLY_OMID_Y_SLOT_PART1, y0)
                    mstore(PROOF_POLY_OPRV_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_OPRV_Y_SLOT_PART1, y1)
                    x0 := calldataload(add(offset2, 0x0e4))
                    y0 := calldataload(add(offset2, 0x104))
                    x1 := calldataload(add(offset2, 0x124))
                    y1 := calldataload(add(offset2, 0x144))
                    mstore(PROOF_POLY_OMID_X_SLOT_PART2, x0)
                    mstore(PROOF_POLY_OMID_Y_SLOT_PART2, y0)
                    mstore(PROOF_POLY_OPRV_X_SLOT_PART2, x1)
                    mstore(PROOF_POLY_OPRV_Y_SLOT_PART2, y1)
                }
                // PROOF Q_AX, Q_AY, Q_CX & Q_CY
                {
                    let x0 := calldataload(add(offset, 0x164))
                    let y0 := calldataload(add(offset, 0x184))
                    let x1 := calldataload(add(offset, 0x1a4))
                    let y1 := calldataload(add(offset, 0x1c4))
                    let x2 := calldataload(add(offset, 0x1e4))
                    let y2 := calldataload(add(offset, 0x204))
                    let x3 := calldataload(add(offset, 0x224))
                    let y3 := calldataload(add(offset, 0x244))
                    mstore(PROOF_POLY_QAX_X_SLOT_PART1, x0)
                    mstore(PROOF_POLY_QAX_Y_SLOT_PART1, y0)
                    mstore(PROOF_POLY_QAY_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_QAY_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_QCX_X_SLOT_PART1, x2)
                    mstore(PROOF_POLY_QCX_Y_SLOT_PART1, y2)
                    mstore(PROOF_POLY_QCY_X_SLOT_PART1, x3)
                    mstore(PROOF_POLY_QCY_Y_SLOT_PART1, y3)
                    x0 := calldataload(add(offset2, 0x164))
                    y0 := calldataload(add(offset2, 0x184))
                    x1 := calldataload(add(offset2, 0x1a4))
                    y1 := calldataload(add(offset2, 0x1c4))
                    x2 := calldataload(add(offset2, 0x1e4))
                    y2 := calldataload(add(offset2, 0x204))
                    x3 := calldataload(add(offset2, 0x224))
                    y3 := calldataload(add(offset2, 0x244))
                    mstore(PROOF_POLY_QAX_X_SLOT_PART2, x0)
                    mstore(PROOF_POLY_QAX_Y_SLOT_PART2, y0)
                    mstore(PROOF_POLY_QAY_X_SLOT_PART2, x1)
                    mstore(PROOF_POLY_QAY_Y_SLOT_PART2, y1)
                    mstore(PROOF_POLY_QCX_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_QCX_Y_SLOT_PART2, y2)
                    mstore(PROOF_POLY_QCY_X_SLOT_PART2, x3)
                    mstore(PROOF_POLY_QCY_Y_SLOT_PART2, y3)
                }
                // PROOF Π_{χ}, Π_{ζ}
                {
                    let x0 := calldataload(add(offset, 0x264))
                    let y0 := calldataload(add(offset, 0x284))
                    let x1 := calldataload(add(offset, 0x2a4))
                    let y1 := calldataload(add(offset, 0x2c4))
                    mstore(PROOF_POLY_PI_CHI_X_SLOT_PART1, x0)
                    mstore(PROOF_POLY_PI_CHI_Y_SLOT_PART1, y0)
                    mstore(PROOF_POLY_PI_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_ZETA_Y_SLOT_PART1, y1)
                    x0 := calldataload(add(offset2, 0x264))
                    y0 := calldataload(add(offset2, 0x284))
                    x1 := calldataload(add(offset2, 0x2a4))
                    y1 := calldataload(add(offset2, 0x2c4))
                    mstore(PROOF_POLY_PI_CHI_X_SLOT_PART2, x0)
                    mstore(PROOF_POLY_PI_CHI_Y_SLOT_PART2, y0)
                    mstore(PROOF_POLY_PI_ZETA_X_SLOT_PART2, x1)
                    mstore(PROOF_POLY_PI_ZETA_Y_SLOT_PART2, y1)
                }
                // PROOF B & R
                {
                    let x0 := calldataload(add(offset, 0x2e4))
                    let y0 := calldataload(add(offset, 0x304))
                    let x1 := calldataload(add(offset, 0x324))
                    let y1 := calldataload(add(offset, 0x344))
                    mstore(PROOF_POLY_B_X_SLOT_PART1, x0)
                    mstore(PROOF_POLY_B_Y_SLOT_PART1, y0)
                    mstore(PROOF_POLY_R_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_R_Y_SLOT_PART1, y1)
                    x0 := calldataload(add(offset2, 0x2e4))
                    y0 := calldataload(add(offset2, 0x304))
                    x1 := calldataload(add(offset2, 0x324))
                    y1 := calldataload(add(offset2, 0x344))
                    mstore(PROOF_POLY_B_X_SLOT_PART2, x0)
                    mstore(PROOF_POLY_B_Y_SLOT_PART2, y0)
                    mstore(PROOF_POLY_R_X_SLOT_PART2, x1)
                    mstore(PROOF_POLY_R_Y_SLOT_PART2, y1)
                }
                // PROOF M_ζ, M_χ, N_ζ & N_χ
                {
                    let x0 := calldataload(add(offset, 0x364))
                    let y0 := calldataload(add(offset, 0x384))
                    let x1 := calldataload(add(offset, 0x3a4))
                    let y1 := calldataload(add(offset, 0x3c4))
                    let x2 := calldataload(add(offset, 0x3e4))
                    let y2 := calldataload(add(offset, 0x404))
                    let x3 := calldataload(add(offset, 0x424))
                    let y3 := calldataload(add(offset, 0x444))
                    mstore(PROOF_POLY_M_ZETA_X_SLOT_PART1, x0)
                    mstore(PROOF_POLY_M_ZETA_Y_SLOT_PART1, y0)
                    mstore(PROOF_POLY_M_CHI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_M_CHI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_N_ZETA_X_SLOT_PART1, x2)
                    mstore(PROOF_POLY_N_ZETA_Y_SLOT_PART1, y2)
                    mstore(PROOF_POLY_N_CHI_X_SLOT_PART1, x3)
                    mstore(PROOF_POLY_N_CHI_Y_SLOT_PART1, y3)
                    x0 := calldataload(add(offset2, 0x364))
                    y0 := calldataload(add(offset2, 0x384))
                    x1 := calldataload(add(offset2, 0x3a4))
                    y1 := calldataload(add(offset2, 0x3c4))
                    x2 := calldataload(add(offset2, 0x3e4))
                    y2 := calldataload(add(offset2, 0x404))
                    x3 := calldataload(add(offset2, 0x424))
                    y3 := calldataload(add(offset2, 0x444))
                    mstore(PROOF_POLY_M_ZETA_X_SLOT_PART2, x0)
                    mstore(PROOF_POLY_M_ZETA_Y_SLOT_PART2, y0)
                    mstore(PROOF_POLY_M_CHI_X_SLOT_PART2, x1)
                    mstore(PROOF_POLY_M_CHI_Y_SLOT_PART2, y1)
                    mstore(PROOF_POLY_N_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_N_ZETA_Y_SLOT_PART2, y2)
                    mstore(PROOF_POLY_N_CHI_X_SLOT_PART2, x3)
                    mstore(PROOF_POLY_N_CHI_Y_SLOT_PART2, y3)
                }
                // PROOF O_PUB & A
                {
                    let x0 := calldataload(add(offset, 0x464))
                    let y0 := calldataload(add(offset, 0x484))
                    let x1 := calldataload(add(offset, 0x4a4))
                    let y1 := calldataload(add(offset, 0x4c4))
                    mstore(PROOF_POLY_OPUB_X_SLOT_PART1, x0)
                    mstore(PROOF_POLY_OPUB_Y_SLOT_PART1, y0)
                    mstore(PROOF_POLY_A_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_A_Y_SLOT_PART1, y1)
                    x0 := calldataload(add(offset2, 0x464))
                    y0 := calldataload(add(offset2, 0x484))
                    x1 := calldataload(add(offset2, 0x4a4))
                    y1 := calldataload(add(offset2, 0x4c4))
                    mstore(PROOF_POLY_OPUB_X_SLOT_PART2, x0)
                    mstore(PROOF_POLY_OPUB_Y_SLOT_PART2, y0)
                    mstore(PROOF_POLY_A_X_SLOT_PART2, x1)
                    mstore(PROOF_POLY_A_Y_SLOT_PART2, y1)
                }

                mstore(PROOF_R1XY_SLOT, mod(calldataload(add(offset2, 0x4e4)), R_MOD))
                mstore(PROOF_R2XY_SLOT, mod(calldataload(add(offset2, 0x504)), R_MOD))
                mstore(PROOF_R3XY_SLOT, mod(calldataload(add(offset2, 0x524)), R_MOD))
                mstore(PROOF_VXY_SLOT, mod(calldataload(add(offset2, 0x544)), R_MOD))

                // load smax
                let smax := calldataload(0xa4)
                let isValidSmax
                {
                    isValidSmax :=
                        or(
                            or(or(eq(smax, 64), eq(smax, 128)), or(eq(smax, 256), eq(smax, 512))),
                            or(eq(smax, 1024), eq(smax, 2048))
                        )
                    mstore(PARAM_SMAX, smax)
                }

                // Revert if smax is not valid
                if iszero(isValidSmax) { revertWithMessage(27, "loadProof: smax is invalid") }
            }

            /*//////////////////////////////////////////////////////////////
                                    2. Transcript initialization
                //////////////////////////////////////////////////////////////*/

            /// @notice Recomputes all challenges
            /// @dev The process is the following:
            /// Commit:   [U], [V], [W], [Q_AX], [Q_AY], [B]
            /// Get:      θ_0, θ_1, θ_2
            /// Commit:   [R]
            /// Get:      κ0
            /// Commit:   [Q_CX], [Q_CY]
            /// Get:      χ, ζ
            /// Commit    V_xy, R1, R2, R3
            /// Get:      κ1, κ2

            function initializeTranscript() {
                // Round 1
                updateTranscript(mload(PROOF_POLY_U_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_U_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_U_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_U_Y_SLOT_PART2))

                updateTranscript(mload(PROOF_POLY_V_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_V_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_V_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_V_Y_SLOT_PART2))

                updateTranscript(mload(PROOF_POLY_W_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_W_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_W_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_W_Y_SLOT_PART2))

                updateTranscript(mload(PROOF_POLY_QAX_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QAX_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QAX_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QAX_Y_SLOT_PART2))

                updateTranscript(mload(PROOF_POLY_QAY_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QAY_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QAY_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QAY_Y_SLOT_PART2))

                updateTranscript(mload(PROOF_POLY_B_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_B_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_B_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_B_Y_SLOT_PART2))

                // compute thetas
                mstore(CHALLENGE_THETA_0_SLOT, getTranscriptChallenge(0))
                mstore(CHALLENGE_THETA_1_SLOT, getTranscriptChallenge(1))
                mstore(CHALLENGE_THETA_2_SLOT, getTranscriptChallenge(2))

                // Round 2
                updateTranscript(mload(PROOF_POLY_R_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_R_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_R_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_R_Y_SLOT_PART2))

                // compute κ0
                mstore(CHALLENGE_KAPPA_0_SLOT, getTranscriptChallenge(3))

                // Round 3
                updateTranscript(mload(PROOF_POLY_QCX_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QCX_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QCX_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QCX_Y_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QCY_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QCY_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QCY_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QCY_Y_SLOT_PART2))

                // compute χ
                mstore(CHALLENGE_CHI_SLOT, getTranscriptChallenge(4))
                // compute ζ
                mstore(CHALLENGE_ZETA_SLOT, getTranscriptChallenge(5))

                // Round 4
                updateTranscript(mload(PROOF_VXY_SLOT))
                updateTranscript(mload(PROOF_R1XY_SLOT))
                updateTranscript(mload(PROOF_R2XY_SLOT))
                updateTranscript(mload(PROOF_R3XY_SLOT))

                // compute κ1
                mstore(CHALLENGE_KAPPA_1_SLOT, getTranscriptChallenge(6))
                // compute κ2
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
            /// t_{smax}(ζ) := ζ^{smax}-1
            ///
            /// t_{m_I}(χ) := χ^{m_I}-1

            function prepareQueries() {
                // calculate [F]_1
                {
                    let theta0 := mload(CHALLENGE_THETA_0_SLOT)
                    let theta1 := mload(CHALLENGE_THETA_1_SLOT)
                    let theta2 := mload(CHALLENGE_THETA_2_SLOT)

                    mstore(INTERMERDIARY_POLY_F_X_SLOT_PART1, mload(PROOF_POLY_B_X_SLOT_PART1))
                    mstore(INTERMERDIARY_POLY_F_X_SLOT_PART2, mload(PROOF_POLY_B_X_SLOT_PART2))
                    mstore(INTERMERDIARY_POLY_F_Y_SLOT_PART1, mload(PROOF_POLY_B_Y_SLOT_PART1))
                    mstore(INTERMERDIARY_POLY_F_Y_SLOT_PART2, mload(PROOF_POLY_B_Y_SLOT_PART2))

                    g1pointMulAndAddIntoDest(PUBLIC_INPUTS_S_0_X_SLOT_PART1, theta0, INTERMERDIARY_POLY_F_X_SLOT_PART1)
                    g1pointMulAndAddIntoDest(PUBLIC_INPUTS_S_1_X_SLOT_PART1, theta1, INTERMERDIARY_POLY_F_X_SLOT_PART1)
                    g1pointMulAndAddIntoDest(VK_IDENTITY_X_PART1, theta2, INTERMERDIARY_POLY_F_X_SLOT_PART1)
                }
                // calculate [G]_1
                {
                    let theta0 := mload(CHALLENGE_THETA_0_SLOT)
                    let theta1 := mload(CHALLENGE_THETA_1_SLOT)
                    let theta2 := mload(CHALLENGE_THETA_2_SLOT)

                    mstore(INTERMERDIARY_POLY_G_X_SLOT_PART1, mload(PROOF_POLY_B_X_SLOT_PART1))
                    mstore(INTERMERDIARY_POLY_G_X_SLOT_PART2, mload(PROOF_POLY_B_X_SLOT_PART2))
                    mstore(INTERMERDIARY_POLY_G_Y_SLOT_PART1, mload(PROOF_POLY_B_Y_SLOT_PART1))
                    mstore(INTERMERDIARY_POLY_G_Y_SLOT_PART2, mload(PROOF_POLY_B_Y_SLOT_PART2))

                    g1pointMulAndAddIntoDest(VK_POLY_X_X_PART1, theta0, INTERMERDIARY_POLY_G_X_SLOT_PART1)
                    g1pointMulAndAddIntoDest(VK_POLY_Y_X_PART1, theta1, INTERMERDIARY_POLY_G_X_SLOT_PART1)
                    g1pointMulAndAddIntoDest(VK_IDENTITY_X_PART1, theta2, INTERMERDIARY_POLY_G_X_SLOT_PART1)
                }
                // calculate t_n(χ)
                {
                    let chi := mload(CHALLENGE_CHI_SLOT)
                    let t := sub(modexp(chi, CONSTANT_N), 1)
                    mstore(INTERMERDIARY_SCALAR_T_N_CHI_SLOT, t)
                }

                // calculate t_smax(ζ)
                {
                    let zeta := mload(CHALLENGE_ZETA_SLOT)
                    let t := sub(modexp(zeta, mload(PARAM_SMAX)), 1)
                    mstore(INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT, t)
                }

                // calculate t_mI(χ)
                {
                    let chi := mload(CHALLENGE_CHI_SLOT)
                    let t := sub(modexp(chi, CONSTANT_MI), 1)
                    mstore(INTERMERDIARY_SCALAR_T_MI_CHI_SLOT, t)
                }
            }

            // lagrange_K0_eval computation
            function computeLagrangeK0Eval() {
                let chi := mload(CHALLENGE_CHI_SLOT)
                let m_i := CONSTANT_MI // 256

                // For k0_evals = [1, 0, 0, ..., 0], the polynomial evaluation becomes:
                // lagrange_K0_eval = L_0(chi) where L_0 is the 0th Lagrange basis polynomial
                // L_0(chi) = ∏_{k=1}^{m_i-1} (chi - ω^k) / (1 - ω^k)
                // This is mathematically equivalent to: (chi^m_i - 1) / (m_i * (chi - 1))

                // Safety check: χ cannot be 1
                if eq(chi, 1) { revert(0, 0) }

                // Compute χ^m_i mod R_MOD
                let chi_mi := modexp(chi, m_i)

                // Compute numerator (χ^m_i - 1) mod R_MOD
                let numerator := addmod(chi_mi, sub(R_MOD, 1), R_MOD)

                // Compute denominator m_i*(χ-1) mod R_MOD
                let chi_1 := addmod(chi, sub(R_MOD, 1), R_MOD)
                let denominator := mulmod(m_i, chi_1, R_MOD)

                // Check denominator is not zero
                if iszero(denominator) { revert(0, 0) }

                // Compute modular inverse using Fermat's little theorem
                let inv_denominator := modexp(denominator, sub(R_MOD, 2))

                // Final result: numerator * inv_denominator mod R_MOD
                let r := mulmod(numerator, inv_denominator, R_MOD)

                mstore(INTERMEDIARY_SCALAR_KO_SLOT, r)
            }

            // A_pub = A(chi)
            // A(chi) = sum_0^{l-1}(a_j * M_j(chi))
            function computeAPUB() {
                let chi := mload(CHALLENGE_CHI_SLOT)
                let offset := calldataload(0x84)

                let n := 512
                let omega := OMEGA_512
                let numPublicInputs := 512

                // Compute chi^512 - 1
                let chi_n := modexp(chi, n)
                let chi_n_1 := addmod(chi_n, sub(R_MOD, 1), R_MOD)

                // Check if chi is a 512th root of unity
                if iszero(chi_n_1) {
                    // Special case: find and return the corresponding value
                    let omega_power := 1
                    for { let i := 0 } lt(i, numPublicInputs) { i := add(i, 1) } {
                        if eq(chi, omega_power) {
                            let val := calldataload(add(add(offset, 0x24), mul(i, 0x20)))
                            mstore(INTERMEDIARY_SCALAR_APUB_SLOT, val)
                            leave
                        }
                        omega_power := mulmod(omega_power, omega, R_MOD)
                    }
                }

                // Normal case: compute weighted sum
                let weightedSum := 0
                let inv_n := modexp(n, sub(R_MOD, 2))

                // First pass: count non-zero values and store their indices
                let nonZeroCount := 0
                let tempOffset := 0x2000 // Temporary storage location

                for { let i := 0 } lt(i, numPublicInputs) { i := add(i, 1) } {
                    let val := calldataload(add(add(offset, 0x24), mul(i, 0x20)))
                    if val {
                        // Store index and value
                        mstore(add(tempOffset, mul(nonZeroCount, 0x40)), i)
                        mstore(add(tempOffset, add(mul(nonZeroCount, 0x40), 0x20)), val)
                        nonZeroCount := add(nonZeroCount, 1)
                    }
                }

                // Second pass: process only non-zero values
                for { let j := 0 } lt(j, nonZeroCount) { j := add(j, 1) } {
                    let i := mload(add(tempOffset, mul(j, 0x40)))
                    let val := mload(add(tempOffset, add(mul(j, 0x40), 0x20)))

                    // Compute omega^i using efficient method based on i
                    let omega_i := 1

                    // For small i, use repeated multiplication
                    if lt(i, 16) {
                        for { let k := 0 } lt(k, i) { k := add(k, 1) } { omega_i := mulmod(omega_i, omega, R_MOD) }
                    }
                    // For larger i, use modexp
                    if iszero(lt(i, 16)) { omega_i := modexp(omega, i) }

                    // Compute contribution
                    let denominator := addmod(chi, sub(R_MOD, omega_i), R_MOD)

                    if iszero(denominator) {
                        mstore(INTERMEDIARY_SCALAR_APUB_SLOT, val)
                        leave
                    }

                    // Compute full denominator: (chi - ω^j) * n
                    let denominator_full := mulmod(denominator, n, R_MOD)
                    let inv_denominator_full := modexp(denominator_full, sub(R_MOD, 2))

                    // Compute numerator: a_j * ω^j * (chi^n - 1)
                    let numerator := mulmod(val, omega_i, R_MOD)
                    numerator := mulmod(numerator, chi_n_1, R_MOD)

                    let contribution := mulmod(numerator, inv_denominator_full, R_MOD)
                    weightedSum := addmod(weightedSum, contribution, R_MOD)
                }

                // Result is the weighted sum (no additional factors needed)
                let result := weightedSum

                mstore(INTERMEDIARY_SCALAR_APUB_SLOT, result)
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
            /// [LHS_A]_1 := V_{x,y}[U]_1 - [W]_1 + κ1([V]_1 - V_{x,y}[G]_1) - t_n(χ)[Q_{A,X}]_1 - t_{s_{max}}(ζ)[Q_{A,Y}]_1
            ///
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
            ///  [AUX]_1 := κ2 * χ * [Π_{χ}]_1 + κ2 * ζ *[Π_ζ]_1 +
            ///             κ2^2 * ω_{m_i}^{-1} * χ *[M_{χ}]_1 + κ2^2 * ζ * [M_{ζ}]_1 + κ2^3 * ω_{m_i}^{-1} * χ * [N_{χ}]_1 + κ_2^3 ω_smax^{-1} * ζ * [N_{ζ}]
            ///

            /// @dev calculate [LHS_A]_1 = V_{x,y}[U]_1 - [W]_1 + κ1[V]_1 - t_n(χ)[Q_{A,X}]_1 - t_{s_{max}}(ζ)[Q_{A,Y}]_1
            function prepareLHSA() {
                g1pointMulIntoDest(PROOF_POLY_U_X_SLOT_PART1, mload(PROOF_VXY_SLOT), AGG_LHS_A_X_SLOT_PART1)
                g1pointSubAssign(AGG_LHS_A_X_SLOT_PART1, PROOF_POLY_W_X_SLOT_PART1)

                //κ1[V]_1
                g1pointMulIntoDest(
                    PROOF_POLY_V_X_SLOT_PART1, mload(CHALLENGE_KAPPA_1_SLOT), BUFFER_AGGREGATED_POLY_X_SLOT_PART1
                )

                // (V_{x,y}[U]_1 - [W]_1) + κ1[V]_1
                g1pointAddIntoDest(AGG_LHS_A_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1, AGG_LHS_A_X_SLOT_PART1)

                // t_n(χ)[Q_{A,X}]_1
                g1pointMulIntoDest(
                    PROOF_POLY_QAX_X_SLOT_PART1,
                    mload(INTERMERDIARY_SCALAR_T_N_CHI_SLOT),
                    BUFFER_AGGREGATED_POLY_X_SLOT_PART1
                )

                // (V_{x,y}[U]_1 - [W]_1) + (κ1 * ([V]_1 - V_{x,y}[1]_1)) - t_n(χ)[Q_{A,X}]_1
                g1pointSubAssign(AGG_LHS_A_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                // t_{s_{max}}(ζ)[Q_{A,Y}]_1
                g1pointMulIntoDest(
                    PROOF_POLY_QAY_X_SLOT_PART1,
                    mload(INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT),
                    BUFFER_AGGREGATED_POLY_X_SLOT_PART1
                )
                // V_{x,y}[U]_1 - [W]_1 + κ1 * ([V]_1 - V_{x,y}[1]_1) - t_n(χ)[Q_{A,X}]_1 - t_{s_{max}}(ζ)[Q_{A,Y}]_1
                g1pointSubAssign(AGG_LHS_A_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
            }

            /// @dev [LHS_B]_1 := (1+κ2κ1^4)[A]_1
            function prepareLHSB() {
                let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                let kappa1 := mload(CHALLENGE_KAPPA_1_SLOT)
                let A_pub := mload(INTERMEDIARY_SCALAR_APUB_SLOT)

                // 1+κ2κ1^4
                let coeff1 := addmod(1, mulmod(kappa2, modexp(kappa1, 4), R_MOD), R_MOD)

                // (1+κ2κ1^4)[A]_1
                g1pointMulIntoDest(PROOF_POLY_A_X_SLOT_PART1, coeff1, AGG_LHS_B_X_SLOT_PART1)
            }

            ///  @dev [LHS_C]_1 := κ1^2(R_{x,y} - 1) * [K_{-1}(X)L_{-1}(X)]_1 + a[G]_1
            ///                    - b[F]_1 - κ1^2 * t_{m_i}(χ) * [Q_{C,X}]_1 - κ1^2 * t_{s_{max}}(ζ) * [Q_{C,Y}]_1) + c[R]_1 + d[1]_1
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
                let A_pub := mload(INTERMEDIARY_SCALAR_APUB_SLOT)
                let t_ml := mload(INTERMERDIARY_SCALAR_T_MI_CHI_SLOT)
                let t_smax := mload(INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT)

                // a := κ1^2 * κ0 * R_{x,y} * ((χ-1) + κ0 * K_0(χ))
                let a :=
                    mulmod(
                        mulmod(mulmod(mulmod(kappa1, kappa1, R_MOD), kappa0, R_MOD), r1, R_MOD),
                        addmod(chi_minus_1, mulmod(kappa0, k0, R_MOD), R_MOD),
                        R_MOD
                    )
                // b := κ1^2 * κ0 * ((χ-1) R’_{x,y} + κ0K_0(χ)R’’_{x,y})
                let b :=
                    mulmod(
                        mulmod(kappa1_pow2, kappa0, R_MOD),
                        addmod(mulmod(chi_minus_1, r2, R_MOD), mulmod(mulmod(kappa0, k0, R_MOD), r3, R_MOD), R_MOD),
                        R_MOD
                    )
                // c := κ1^3 + κ2 + κ2^2
                let c := addmod(kappa1_pow3, addmod(kappa2, kappa2_pow2, R_MOD), R_MOD)
                //    d := -κ1^3R_{x,y} - κ2R’_{x,y} - κ2^2R’’_{x,y} - κ1V_{x,y} - κ1^4A_{pub}
                // => d := - (κ1^3R_{x,y} + κ2R’_{x,y} + κ2^2R’’_{x,y} + κ1V_{x,y} + κ1^4A_{pub})
                let d :=
                    sub(
                        R_MOD,
                        addmod(
                            addmod(
                                addmod(mulmod(kappa1_pow3, r1, R_MOD), mulmod(kappa2, r2, R_MOD), R_MOD),
                                mulmod(kappa2_pow2, r3, R_MOD),
                                R_MOD
                            ),
                            addmod(
                                mulmod(kappa1, V_xy, R_MOD), mulmod(mulmod(kappa1, kappa1_pow3, R_MOD), A_pub, R_MOD), R_MOD
                            ),
                            R_MOD
                        )
                    )
                // κ1^2(R_x,y - 1)
                let kappa1_r_minus_1 := mulmod(mulmod(kappa1, kappa1, R_MOD), sub(r1, 1), R_MOD)
                // κ1^2 * t_{m_l}(χ)
                let kappa1_tml := mulmod(kappa1_pow2, t_ml, R_MOD)
                // κ1^2 * t_{s_{max}}(ζ)
                let kappa1_tsmax := mulmod(kappa1_pow2, t_smax, R_MOD)

                g1pointMulIntoDest(VK_POLY_KXLX_X_PART1, kappa1_r_minus_1, AGG_LHS_C_X_SLOT_PART1)
                g1pointMulAndAddIntoDest(INTERMERDIARY_POLY_G_X_SLOT_PART1, a, AGG_LHS_C_X_SLOT_PART1)

                g1pointMulIntoDest(INTERMERDIARY_POLY_F_X_SLOT_PART1, b, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                g1pointSubAssign(AGG_LHS_C_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                g1pointMulIntoDest(PROOF_POLY_QCX_X_SLOT_PART1, kappa1_tml, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                g1pointSubAssign(AGG_LHS_C_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                g1pointMulIntoDest(PROOF_POLY_QCY_X_SLOT_PART1, kappa1_tsmax, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)
                g1pointSubAssign(AGG_LHS_C_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                g1pointMulAndAddIntoDest(PROOF_POLY_R_X_SLOT_PART1, c, AGG_LHS_C_X_SLOT_PART1)
                g1pointMulAndAddIntoDest(VK_IDENTITY_X_PART1, d, AGG_LHS_C_X_SLOT_PART1)
            }

            /// @dev [RHS_1]_1 := κ2[Π_{χ}]_1 + κ2^2[M_{χ}]_1 + κ2^3[N_{χ}]_1
            function prepareRHS1() {
                let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                let kappa2_pow2 := mulmod(kappa2, kappa2, R_MOD)
                let kappa2_pow3 := mulmod(kappa2_pow2, kappa2, R_MOD)

                g1pointMulIntoDest(PROOF_POLY_PI_CHI_X_SLOT_PART1, kappa2, PAIRING_AGG_RHS_1_X_SLOT_PART1)
                g1pointMulAndAddIntoDest(PROOF_POLY_M_CHI_X_SLOT_PART1, kappa2_pow2, PAIRING_AGG_RHS_1_X_SLOT_PART1)
                g1pointMulAndAddIntoDest(PROOF_POLY_N_CHI_X_SLOT_PART1, kappa2_pow3, PAIRING_AGG_RHS_1_X_SLOT_PART1)
            }

            /// @dev [RHS_2]_1 := κ2[Π_{ζ}]_1 + κ2^2[M_{ζ}]_1 + κ2^3[N_{ζ}]_1
            function prepareRHS2() {
                let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                let kappa2_pow2 := mulmod(kappa2, kappa2, R_MOD)
                let kappa2_pow3 := mulmod(kappa2_pow2, kappa2, R_MOD)

                g1pointMulIntoDest(PROOF_POLY_PI_ZETA_X_SLOT_PART1, kappa2, PAIRING_AGG_RHS_2_X_SLOT_PART1)
                g1pointMulAndAddIntoDest(PROOF_POLY_M_ZETA_X_SLOT_PART1, kappa2_pow2, PAIRING_AGG_RHS_2_X_SLOT_PART1)
                g1pointMulAndAddIntoDest(PROOF_POLY_N_ZETA_X_SLOT_PART1, kappa2_pow3, PAIRING_AGG_RHS_2_X_SLOT_PART1)
            }

            // @dev Function to get the correct omega_smax^{-1} value based on smax parameter
            function getOmegaSmaxInverse(smax) -> omega_smax_inv {
                switch smax
                case 64 { omega_smax_inv := OMEGA_SMAX_64_MINUS_1 }
                case 128 { omega_smax_inv := OMEGA_SMAX_128_MINUS_1 }
                case 256 { omega_smax_inv := OMEGA_SMAX_256_MINUS_1 }
                case 512 { omega_smax_inv := OMEGA_SMAX_512_MINUS_1 }
                case 1024 { omega_smax_inv := OMEGA_SMAX_1024_MINUS_1 }
                case 2048 { omega_smax_inv := OMEGA_SMAX_2048_MINUS_1 }
                default {
                    // This should never happen if loadProof validation is correct
                    revertWithMessage(25, "Invalid smax for omega")
                }
            }

            /// @dev [LHS]_1 := [LHS_B]_1 + κ2([LHS_A]_1 + [LHS_C]_1)
            /// @dev [AUX]_1 := κ2 * χ * [Π_{χ}]_1 + κ2 * ζ *[Π_ζ]_1 +
            ///                 κ2^2 * ω_{m_l}^{-1} * χ *[M_{χ}]_1 + κ2^2 * ζ * [M_ζ]_1 + κ2^3 * ω_{m_l}^{-1} * χ * [N_{χ}]_1 + κ_2^3 * ω_smax^{-1} * ζ * [N_{ζ}]
            function prepareAggregatedCommitment() {
                // calculate [LHS]_1 = [LHS_B]_1 + κ2([LHS_A]_1 + [LHS_C]_1)
                {
                    let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)

                    // First add [LHS_A]_1 + [LHS_C]_1
                    g1pointAddIntoDest(
                        AGG_LHS_A_X_SLOT_PART1, AGG_LHS_C_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1
                    )

                    // Multiply by κ2: κ2([LHS_A]_1 + [LHS_C]_1)
                    g1pointMulIntoDest(BUFFER_AGGREGATED_POLY_X_SLOT_PART1, kappa2, BUFFER_AGGREGATED_POLY_X_SLOT_PART1)

                    // Add [LHS_B]_1: [LHS_B]_1 + κ2([LHS_A]_1 + [LHS_C]_1)
                    g1pointAddIntoDest(
                        AGG_LHS_B_X_SLOT_PART1, BUFFER_AGGREGATED_POLY_X_SLOT_PART1, PAIRING_AGG_LHS_X_SLOT_PART1
                    )
                }

                // calculate [AUX]_1
                {
                    let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                    let chi := mload(CHALLENGE_CHI_SLOT)
                    let zeta := mload(CHALLENGE_ZETA_SLOT)
                    let omega_ml := OMEGA_MI_1
                    let omega_smax := getOmegaSmaxInverse(mload(PARAM_SMAX))

                    let kappa2_chi := mulmod(kappa2, chi, R_MOD)
                    let kappa2_zeta := mulmod(kappa2, zeta, R_MOD)
                    let kappa2_pow2_omega_ml_chi :=
                        mulmod(mulmod(mulmod(kappa2, kappa2, R_MOD), omega_ml, R_MOD), chi, R_MOD)
                    let kappa2_pow2_zeta := mulmod(mulmod(kappa2, kappa2, R_MOD), zeta, R_MOD)
                    let kappa2_pow3_omega_ml_chi :=
                        mulmod(mulmod(mulmod(mulmod(kappa2, kappa2, R_MOD), kappa2, R_MOD), omega_ml, R_MOD), chi, R_MOD)
                    let kappa2_pow3_omega_smax_zeta :=
                        mulmod(mulmod(mulmod(mulmod(kappa2, kappa2, R_MOD), kappa2, R_MOD), omega_smax, R_MOD), zeta, R_MOD)
                    // [AUX]_1 accumulation
                    // κ2 * χ * [Π_{χ}]_1
                    g1pointMulIntoDest(PROOF_POLY_PI_CHI_X_SLOT_PART1, kappa2_chi, PAIRING_AGG_AUX_X_SLOT_PART1)
                    // += κ2 * ζ *[Π_ζ]_1
                    g1pointMulAndAddIntoDest(PROOF_POLY_PI_ZETA_X_SLOT_PART1, kappa2_zeta, PAIRING_AGG_AUX_X_SLOT_PART1)
                    // += κ2^2 * ω_{m_l}^{-1} * χ *[M_{χ}]_1
                    g1pointMulAndAddIntoDest(
                        PROOF_POLY_M_CHI_X_SLOT_PART1, kappa2_pow2_omega_ml_chi, PAIRING_AGG_AUX_X_SLOT_PART1
                    )
                    // += κ2^2 * ζ * [M_ζ]_1
                    g1pointMulAndAddIntoDest(
                        PROOF_POLY_M_ZETA_X_SLOT_PART1, kappa2_pow2_zeta, PAIRING_AGG_AUX_X_SLOT_PART1
                    )
                    // κ2^3 * ω_{m_l}^{-1} * χ * [N_{χ}]_1
                    g1pointMulAndAddIntoDest(
                        PROOF_POLY_N_CHI_X_SLOT_PART1, kappa2_pow3_omega_ml_chi, PAIRING_AGG_AUX_X_SLOT_PART1
                    )
                    // κ2^3 * ω_smax^{-1} * ζ * [N_{ζ}]
                    g1pointMulAndAddIntoDest(
                        PROOF_POLY_N_ZETA_X_SLOT_PART1, kappa2_pow3_omega_smax_zeta, PAIRING_AGG_AUX_X_SLOT_PART1
                    )
                }

                // calculate [LHS]_1 + [AUX]_1
                {
                    g1pointAddIntoDest(
                        PAIRING_AGG_LHS_X_SLOT_PART1, PAIRING_AGG_AUX_X_SLOT_PART1, PAIRING_AGG_LHS_AUX_X_SLOT_PART1
                    )
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
            // e(P1, P2) = e(G1, G2)
            // e(P1, P2)*e(G1, -G2) = 1

            function finalPairing() {
                // load [LHS]_1 + [AUX]_1
                mstore(0x000, mload(PAIRING_AGG_LHS_AUX_X_SLOT_PART1))
                mstore(0x020, mload(PAIRING_AGG_LHS_AUX_X_SLOT_PART2))
                mstore(0x040, mload(PAIRING_AGG_LHS_AUX_Y_SLOT_PART1))
                mstore(0x060, mload(PAIRING_AGG_LHS_AUX_Y_SLOT_PART2))

                // load [1]_2
                mstore(0x080, IDENTITY2_X1_PART1)
                mstore(0x0a0, IDENTITY2_X1_PART2)
                mstore(0x0c0, IDENTITY2_X0_PART1)
                mstore(0x0e0, IDENTITY2_X0_PART2)
                mstore(0x100, IDENTITY2_Y1_PART1)
                mstore(0x120, IDENTITY2_Y1_PART2)
                mstore(0x140, IDENTITY2_Y0_PART1)
                mstore(0x160, IDENTITY2_Y0_PART2)

                // load [B]_1
                mstore(0x180, mload(PROOF_POLY_B_X_SLOT_PART1))
                mstore(0x1a0, mload(PROOF_POLY_B_X_SLOT_PART2))
                mstore(0x1c0, mload(PROOF_POLY_B_Y_SLOT_PART1))
                mstore(0x1e0, mload(PROOF_POLY_B_Y_SLOT_PART2))

                // load [α^4]_2
                mstore(0x200, ALPHA_POWER4_X1_PART1)
                mstore(0x220, ALPHA_POWER4_X1_PART2)
                mstore(0x240, ALPHA_POWER4_X0_PART1)
                mstore(0x260, ALPHA_POWER4_X0_PART2)
                mstore(0x280, ALPHA_POWER4_Y1_PART1)
                mstore(0x2a0, ALPHA_POWER4_Y1_PART2)
                mstore(0x2c0, ALPHA_POWER4_Y0_PART1)
                mstore(0x2e0, ALPHA_POWER4_Y0_PART2)

                // load [U]_1
                mstore(0x300, mload(PROOF_POLY_U_X_SLOT_PART1))
                mstore(0x320, mload(PROOF_POLY_U_X_SLOT_PART2))
                mstore(0x340, mload(PROOF_POLY_U_Y_SLOT_PART1))
                mstore(0x360, mload(PROOF_POLY_U_Y_SLOT_PART2))

                // load [α]_2
                mstore(0x380, ALPHA_X1_PART1)
                mstore(0x3a0, ALPHA_X1_PART2)
                mstore(0x3c0, ALPHA_X0_PART1)
                mstore(0x3e0, ALPHA_X0_PART2)
                mstore(0x400, ALPHA_Y1_PART1)
                mstore(0x420, ALPHA_Y1_PART2)
                mstore(0x440, ALPHA_Y0_PART1)
                mstore(0x460, ALPHA_Y0_PART2)

                // load [V]_1
                mstore(0x480, mload(PROOF_POLY_V_X_SLOT_PART1))
                mstore(0x4a0, mload(PROOF_POLY_V_X_SLOT_PART2))
                mstore(0x4c0, mload(PROOF_POLY_V_Y_SLOT_PART1))
                mstore(0x4e0, mload(PROOF_POLY_V_Y_SLOT_PART2))

                // load [α^2]_2
                mstore(0x500, ALPHA_POWER2_X1_PART1)
                mstore(0x520, ALPHA_POWER2_X1_PART2)
                mstore(0x540, ALPHA_POWER2_X0_PART1)
                mstore(0x560, ALPHA_POWER2_X0_PART2)
                mstore(0x580, ALPHA_POWER2_Y1_PART1)
                mstore(0x5a0, ALPHA_POWER2_Y1_PART2)
                mstore(0x5c0, ALPHA_POWER2_Y0_PART1)
                mstore(0x5e0, ALPHA_POWER2_Y0_PART2)

                // load [W]_1
                mstore(0x600, mload(PROOF_POLY_W_X_SLOT_PART1))
                mstore(0x620, mload(PROOF_POLY_W_X_SLOT_PART2))
                mstore(0x640, mload(PROOF_POLY_W_Y_SLOT_PART1))
                mstore(0x660, mload(PROOF_POLY_W_Y_SLOT_PART2))

                // load [α^3]_2
                mstore(0x680, ALPHA_POWER3_X1_PART1)
                mstore(0x6a0, ALPHA_POWER3_X1_PART2)
                mstore(0x6c0, ALPHA_POWER3_X0_PART1)
                mstore(0x6e0, ALPHA_POWER3_X0_PART2)
                mstore(0x700, ALPHA_POWER3_Y1_PART1)
                mstore(0x720, ALPHA_POWER3_Y1_PART2)
                mstore(0x740, ALPHA_POWER3_Y0_PART1)
                mstore(0x760, ALPHA_POWER3_Y0_PART2)

                // load [O_pub]_1
                mstore(0x780, mload(PROOF_POLY_OPUB_X_SLOT_PART1))
                mstore(0x7a0, mload(PROOF_POLY_OPUB_X_SLOT_PART2))
                mstore(0x7c0, mload(PROOF_POLY_OPUB_Y_SLOT_PART1))
                mstore(0x7e0, mload(PROOF_POLY_OPUB_Y_SLOT_PART2))

                // load -[γ]_2
                mstore(0x800, GAMMA_X1_PART1)
                mstore(0x820, GAMMA_X1_PART2)
                mstore(0x840, GAMMA_X0_PART1)
                mstore(0x860, GAMMA_X0_PART2)
                mstore(0x880, GAMMA_Y1_PART1)
                mstore(0x8a0, GAMMA_Y1_PART2)
                mstore(0x8c0, GAMMA_Y0_PART1)
                mstore(0x8e0, GAMMA_Y0_PART2)

                // load [O_mid]_1
                mstore(0x900, mload(PROOF_POLY_OMID_X_SLOT_PART1))
                mstore(0x920, mload(PROOF_POLY_OMID_X_SLOT_PART2))
                mstore(0x940, mload(PROOF_POLY_OMID_Y_SLOT_PART1))
                mstore(0x960, mload(PROOF_POLY_OMID_Y_SLOT_PART2))

                // load -[η]_2
                mstore(0x980, ETA_X1_PART1)
                mstore(0x9a0, ETA_X1_PART2)
                mstore(0x9c0, ETA_X0_PART1)
                mstore(0x9e0, ETA_X0_PART2)
                mstore(0xa00, ETA_Y1_PART1)
                mstore(0xa20, ETA_Y1_PART2)
                mstore(0xa40, ETA_Y0_PART1)
                mstore(0xa60, ETA_Y0_PART2)

                // load [O_prv]_1
                mstore(0xa80, mload(PROOF_POLY_OPRV_X_SLOT_PART1))
                mstore(0xaa0, mload(PROOF_POLY_OPRV_X_SLOT_PART2))
                mstore(0xac0, mload(PROOF_POLY_OPRV_Y_SLOT_PART1))
                mstore(0xae0, mload(PROOF_POLY_OPRV_Y_SLOT_PART2))

                // load -[δ]_2
                mstore(0xb00, DELTA_X1_PART1)
                mstore(0xb20, DELTA_X1_PART2)
                mstore(0xb40, DELTA_X0_PART1)
                mstore(0xb60, DELTA_X0_PART2)
                mstore(0xb80, DELTA_Y1_PART1)
                mstore(0xba0, DELTA_Y1_PART2)
                mstore(0xbc0, DELTA_Y0_PART1)
                mstore(0xbe0, DELTA_Y0_PART2)

                // load [RHS_1]_1 := κ2[Π_{χ}]_1 + κ2^2[M_{χ}]_1 + κ2^3[N_{χ}]_1
                mstore(0xc00, mload(PAIRING_AGG_RHS_1_X_SLOT_PART1))
                mstore(0xc20, mload(PAIRING_AGG_RHS_1_X_SLOT_PART2))
                mstore(0xc40, mload(PAIRING_AGG_RHS_1_Y_SLOT_PART1))
                mstore(0xc60, mload(PAIRING_AGG_RHS_1_Y_SLOT_PART2))

                // load -[x]_2
                mstore(0xc80, X_X1_PART1)
                mstore(0xca0, X_X1_PART2)
                mstore(0xcc0, X_X0_PART1)
                mstore(0xce0, X_X0_PART2)
                mstore(0xd00, X_Y1_PART1)
                mstore(0xd20, X_Y1_PART2)
                mstore(0xd40, X_Y0_PART1)
                mstore(0xd60, X_Y0_PART2)

                // load [RHS_2]_2 := κ2[Π_{ζ}]_1 + κ2^2[M_{ζ}]_1 + κ2^3[N_{ζ}]_1
                mstore(0xd80, mload(PAIRING_AGG_RHS_2_X_SLOT_PART1))
                mstore(0xda0, mload(PAIRING_AGG_RHS_2_X_SLOT_PART2))
                mstore(0xdc0, mload(PAIRING_AGG_RHS_2_Y_SLOT_PART1))
                mstore(0xde0, mload(PAIRING_AGG_RHS_2_Y_SLOT_PART2))

                // load -[y]_2
                mstore(0xe00, Y_X1_PART1)
                mstore(0xe20, Y_X1_PART2)
                mstore(0xe40, Y_X0_PART1)
                mstore(0xe60, Y_X0_PART2)
                mstore(0xe80, Y_Y1_PART1)
                mstore(0xea0, Y_Y1_PART2)
                mstore(0xec0, Y_Y0_PART1)
                mstore(0xee0, Y_Y0_PART2)

                // precompile call
                let success := staticcall(gas(), 0x0f, 0, 0xf00, 0x00, 0x20)
                if iszero(success) { revertWithMessage(32, "finalPairing: precompile failure") }
                if iszero(mload(0)) { revertWithMessage(29, "finalPairing: pairing failure") }
            }

            // Step1: Load the PI/proof
            loadProof()

            // Step2: Recompute all the challenges with the transcript
            initializeTranscript()

            // Step3: computation of [F]_1, [G]_1, t_n(χ), t_smax(ζ) and t_ml(χ), K0(χ) and A_pub
            prepareQueries()
            computeLagrangeK0Eval()
            computeAPUB()

            // Step4: computation of the final polynomial commitments - COMMENTED OUT FOR DEBUGGING
            prepareLHSA()
            prepareLHSB()
            prepareLHSC()
            prepareRHS1()
            prepareRHS2()
            prepareAggregatedCommitment()

            // Step5: final pairing - COMMENTED OUT FOR DEBUGGING
            finalPairing()
            final_result := true

            // DEBUG: Return A_pub instead of final result
            mstore(0x00, final_result)
            return(0x00, 0x20)
        }
    }
}
