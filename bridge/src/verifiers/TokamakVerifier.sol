// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ITokamakVerifier } from "../interfaces/ITokamakVerifier.sol";
import { TokamakVerifierKeyGenerated } from "../generated/TokamakVerifierKey.generated.sol";

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
    string public compatibleBackendVersion;

    constructor(string memory compatibleBackendVersion_) {
        compatibleBackendVersion = compatibleBackendVersion_;
    }

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
    // O_pub,free
    uint256 internal constant PROOF_POLY_OPUB_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x8a0;
    uint256 internal constant PROOF_POLY_OPUB_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x8c0;
    uint256 internal constant PROOF_POLY_OPUB_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x8e0;
    uint256 internal constant PROOF_POLY_OPUB_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x900;
    // A_free
    uint256 internal constant PROOF_POLY_A_FREE_X_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x920;
    uint256 internal constant PROOF_POLY_A_FREE_X_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x940;
    uint256 internal constant PROOF_POLY_A_FREE_Y_SLOT_PART1 = 0x8000 + 0x200 + 0x120 + 0x960;
    uint256 internal constant PROOF_POLY_A_FREE_Y_SLOT_PART2 = 0x8000 + 0x200 + 0x120 + 0x980;
    // R_xy
    uint256 internal constant PROOF_R1XY_SLOT = 0x8000 + 0x200 + 0x120 + 0x9a0;
    // R'_xy
    uint256 internal constant PROOF_R2XY_SLOT = 0x8000 + 0x200 + 0x120 + 0x9c0;
    // R''_xy
    uint256 internal constant PROOF_R3XY_SLOT = 0x8000 + 0x200 + 0x120 + 0x9e0;
    // V_xy
    uint256 internal constant PROOF_VXY_SLOT = 0x8000 + 0x200 + 0x120 + 0xa00;

    // O_pub,fix (decoded from `_preprocessed`; used in final pairing)
    uint256 internal constant PROOF_POLY_OPUB_FIX_X_SLOT_PART1 = 0x9720;
    uint256 internal constant PROOF_POLY_OPUB_FIX_X_SLOT_PART2 = 0x9740;
    uint256 internal constant PROOF_POLY_OPUB_FIX_Y_SLOT_PART1 = 0x9760;
    uint256 internal constant PROOF_POLY_OPUB_FIX_Y_SLOT_PART2 = 0x9780;

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

    uint256 internal constant CHALLENGE_THETA_0_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80
        + 0x000;
    uint256 internal constant CHALLENGE_THETA_1_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80
        + 0x020;
    uint256 internal constant CHALLENGE_THETA_2_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80
        + 0x040;
    uint256 internal constant CHALLENGE_KAPPA_0_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80
        + 0x060;
    uint256 internal constant CHALLENGE_KAPPA_1_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80
        + 0x080;
    uint256 internal constant CHALLENGE_KAPPA_2_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80
        + 0x0a0;
    uint256 internal constant CHALLENGE_ZETA_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x0c0;
    uint256 internal constant CHALLENGE_CHI_SLOT = 0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100;

    /*//////////////////////////////////////////////////////////////
                        Intermediary verifier state
    //////////////////////////////////////////////////////////////*/

    // t_n(χ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_N_CHI_SLOT =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x120;
    // t_smax(ζ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x140;
    // t_ml(χ)
    uint256 internal constant INTERMERDIARY_SCALAR_T_MI_CHI_SLOT =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x160;
    // K_0(χ)
    uint256 internal constant INTERMEDIARY_SCALAR_KO_SLOT =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x180;
    // A_eval = A(chi)
    uint256 internal constant INTERMEDIARY_SCALAR_APUB_SLOT =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0;

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
    uint256 internal constant VK_POLY_X_X_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x0a0;
    uint256 internal constant VK_POLY_X_X_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x0c0;
    uint256 internal constant VK_POLY_X_Y_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x0e0;
    uint256 internal constant VK_POLY_X_Y_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x100;

    // [y]_1
    uint256 internal constant VK_POLY_Y_X_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x120;
    uint256 internal constant VK_POLY_Y_X_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x140;
    uint256 internal constant VK_POLY_Y_Y_PART1 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x160;
    uint256 internal constant VK_POLY_Y_Y_PART2 =
        0x8000 + 0x200 + 0x120 + 0xa20 + 0x80 + 0x100 + 0x1a0 + 0x480 + 0x180;

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
                                Constants
    //////////////////////////////////////////////////////////////*/

    // Scalar field size
    // R_MOD is the main subgroup order
    uint256 internal constant R_MOD =
        0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    /// @dev flip of 0xe000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant FR_MASK =
        0x1fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // n, refreshed from setupParams.json by bridge/scripts/deploy-bridge.mjs
    uint256 internal constant CONSTANT_N = 4096;
    // ω_64
    uint256 internal constant OMEGA_64 =
        0x0e4840ac57f86f5e293b1d67bc8de5d9a12a70a615d0b8e4d2fc5e69ac5db47f;
    // ω_128
    uint256 internal constant OMEGA_128 =
        0x07d0c802a94a946e8cbe2437f0b4b276501dff643be95635b750da4cab28e208;
    // ω_512
    uint256 internal constant OMEGA_512 =
        0x1bb466679a5d88b1ecfbede342dee7f415c1ad4c687f28a233811ea1fe0c65f4;
    // m_i = l_D - l, refreshed from setupParams.json by bridge/scripts/deploy-bridge.mjs
    uint256 internal constant CONSTANT_MI = 4096;
    // l_user, refreshed from setupParams.json by bridge/scripts/deploy-bridge.mjs
    uint256 internal constant EXPECTED_L_USER = 85;
    // l_free, refreshed from setupParams.json by bridge/scripts/deploy-bridge.mjs
    uint256 internal constant EXPECTED_L_FREE = 128;
    // omega_{l_free}, refreshed from setupParams.json by bridge/scripts/deploy-bridge.mjs
    uint256 internal constant OMEGA_L_FREE = 0x07d0c802a94a946e8cbe2437f0b4b276501dff643be95635b750da4cab28e208;
    // s_max, refreshed from setupParams.json by bridge/scripts/deploy-bridge.mjs
    uint256 internal constant EXPECTED_SMAX = 256;

    // omega_{m_i}^{-1}, refreshed from setupParams.json by bridge/scripts/deploy-bridge.mjs
    uint256 internal constant OMEGA_MI_1 = 0x58c3ba636d174692ad5a534045625d9514180e0e8b24f12309f239f760b82267;
    // omega_{s_max}^{-1}, refreshed from setupParams.json by bridge/scripts/deploy-bridge.mjs
    uint256 internal constant OMEGA_SMAX_MINUS_1 =
        0x6d64ed25272e58ee91b000235a5bfd4fc03cae032393991be9561c176a2f777a;

    // computeAPUB scratch buffers, sized to EXPECTED_L_FREE words and placed above verifier reserved slots.
    uint256 internal constant COMPUTE_APUB_NUMERATOR_BUFFER_SLOT = 0x10000;
    uint256 internal constant COMPUTE_APUB_DENOMINATOR_BUFFER_SLOT = 0x11000;
    uint256 internal constant COMPUTE_APUB_PREFIX_BUFFER_SLOT = 0x12000;
    // Step 4 temporary coefficients (C_G, C_F, C_B = C_G + C_F), kept outside reserved verifier slots.
    uint256 internal constant STEP4_COEFF_C_G_SLOT = 0x13000;
    uint256 internal constant STEP4_COEFF_C_F_SLOT = 0x13020;
    uint256 internal constant STEP4_COEFF_C_B_SLOT = 0x13040;

    /*//////////////////////////////////////////////////////////////
                            G2 elements
        //////////////////////////////////////////////////////////////*/

    // G2 Points for zkEVM Verifier (BLS12-381) - Standard Naming Convention
    // Each point uses 8 uint256 slots (256 bytes total)
    // Format: X0_PART1, X0_PART2, X1_PART1, X1_PART2, Y0_PART1, Y0_PART2, Y1_PART1, Y1_PART2

    // [1]_2 (Identity/Generator point H), refreshed from sigma_verify.json.
    uint256 internal constant IDENTITY2_X0_PART1 = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 internal constant IDENTITY2_X0_PART2 = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 internal constant IDENTITY2_X1_PART1 = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 internal constant IDENTITY2_X1_PART2 = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 internal constant IDENTITY2_Y0_PART1 = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 internal constant IDENTITY2_Y0_PART2 = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;
    uint256 internal constant IDENTITY2_Y1_PART1 = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 internal constant IDENTITY2_Y1_PART2 = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;

    // [α]_2, refreshed from sigma_verify.json.
    uint256 internal constant ALPHA_X0_PART1 = 0x00000000000000000000000000000000034289d007faad5feab722a30d9ac950;
    uint256 internal constant ALPHA_X0_PART2 = 0x422a7f9e37a01849d37dcda7bbfa0492949c16bd620bad36ce20e779450d1423;
    uint256 internal constant ALPHA_X1_PART1 = 0x00000000000000000000000000000000093f57f8f806ab233d8434d0267c7754;
    uint256 internal constant ALPHA_X1_PART2 = 0x1be6c915576c1bddfa460bf8b6e8f1f937c81a3871fd50a3aa81726065086aad;
    uint256 internal constant ALPHA_Y0_PART1 = 0x0000000000000000000000000000000004d89fd2c1e7527eb39911672cb4ee30;
    uint256 internal constant ALPHA_Y0_PART2 = 0x5d9a98575dd9351b8be857d2714db52fe352408b1b7eda48051b0aebad8d68c4;
    uint256 internal constant ALPHA_Y1_PART1 = 0x0000000000000000000000000000000002b195572a97a24b3d937fbc5a3f17e3;
    uint256 internal constant ALPHA_Y1_PART2 = 0x2447f72db948e76770d9feb379768e7e1bf4319a5cd42f1fee53c907ad8526e2;

    // [α^2]_2, refreshed from sigma_verify.json.
    uint256 internal constant ALPHA_POWER2_X0_PART1 = 0x000000000000000000000000000000001909c0ad9d7658042a2b60842c0b0516;
    uint256 internal constant ALPHA_POWER2_X0_PART2 = 0x7ea0cec8fd603ec362b53f777309333c04634d699ac1a51fa912413ddf02796b;
    uint256 internal constant ALPHA_POWER2_X1_PART1 = 0x000000000000000000000000000000000df79b8707062baa404dda649be447c5;
    uint256 internal constant ALPHA_POWER2_X1_PART2 = 0x9dedc36b3591f4f5b818b9247eabec29bf526919022f2020c2a06c5d4df0f973;
    uint256 internal constant ALPHA_POWER2_Y0_PART1 = 0x000000000000000000000000000000000c90af2e608571fed42a1d7e617ad227;
    uint256 internal constant ALPHA_POWER2_Y0_PART2 = 0x5ae378ffbab95fd8cb79e79ea24dc0f072f8617e6f63b9965b96992a163d72e7;
    uint256 internal constant ALPHA_POWER2_Y1_PART1 = 0x000000000000000000000000000000000b2475e8e122bdd9d68d5dac9ec71995;
    uint256 internal constant ALPHA_POWER2_Y1_PART2 = 0x095af85f2ef84a34815d97d7da60d463a70ff74595ba174de837b15ead72dd67;

    // [α^3]_2, refreshed from sigma_verify.json.
    uint256 internal constant ALPHA_POWER3_X0_PART1 = 0x000000000000000000000000000000000051b699a4c977eab087d8f3fb100234;
    uint256 internal constant ALPHA_POWER3_X0_PART2 = 0xca8f9ab9ec2d84769fcf8a6a999021579f78e29e81c6911e3ee1bb868de10b19;
    uint256 internal constant ALPHA_POWER3_X1_PART1 = 0x000000000000000000000000000000000b477a017fb4ba1901048bbf67a1c576;
    uint256 internal constant ALPHA_POWER3_X1_PART2 = 0xf3377f378426d68eb5d4c24d4d10438791ecf4d16630921b65005a1c8a80fbe9;
    uint256 internal constant ALPHA_POWER3_Y0_PART1 = 0x000000000000000000000000000000000d5258592704eb980b451fa215ec7714;
    uint256 internal constant ALPHA_POWER3_Y0_PART2 = 0xc8f6aa2be5d773faea761ce2737dc8126b2cadeb52fc3b8ccdb3fce98f4202df;
    uint256 internal constant ALPHA_POWER3_Y1_PART1 = 0x00000000000000000000000000000000141d6e6bcc12277e7c1c33b534ed033c;
    uint256 internal constant ALPHA_POWER3_Y1_PART2 = 0x5488cc691fc99cbaeaac71a434e5c19618a40c4a00a18d903285943f6ba94fe8;

    // [α^4]_2, refreshed from sigma_verify.json.
    uint256 internal constant ALPHA_POWER4_X0_PART1 = 0x000000000000000000000000000000000d4b13721cdcd6aa4f3d1ce5d2141fde;
    uint256 internal constant ALPHA_POWER4_X0_PART2 = 0xe74a7e9f2b9128da8961eb187e129ae57fd1d2c7c66006d38426b72fa18c4137;
    uint256 internal constant ALPHA_POWER4_X1_PART1 = 0x000000000000000000000000000000000010ef98caa3943cd772e523530eca9d;
    uint256 internal constant ALPHA_POWER4_X1_PART2 = 0x3f5d81c4ef75eb3638789e4bb711f204eabb20610f9d3c6bf158a6e92e38cbeb;
    uint256 internal constant ALPHA_POWER4_Y0_PART1 = 0x000000000000000000000000000000000c4aad341b2c63d949a828b5543056d0;
    uint256 internal constant ALPHA_POWER4_Y0_PART2 = 0x0b68f6870ee0b771defc41a8bce8b0ee59e56df547cc26e6ab6523db5315d631;
    uint256 internal constant ALPHA_POWER4_Y1_PART1 = 0x000000000000000000000000000000000707e22518e33b5eb6c6c5aa51b2332c;
    uint256 internal constant ALPHA_POWER4_Y1_PART2 = 0x01597ab09398b775d54c7b75e6af259196eecac5818e09eab53449a53a5477c6;

    // -[γ]_2, refreshed from sigma_verify.json and negated for pairing.
    uint256 internal constant GAMMA_X0_PART1 = 0x0000000000000000000000000000000016548a05366f6cf70a30d3e6e978d5ff;
    uint256 internal constant GAMMA_X0_PART2 = 0x3047b35129b0b85229b3d622702fb1692d3c0e54a95177c6cc12e35571373872;
    uint256 internal constant GAMMA_X1_PART1 = 0x000000000000000000000000000000000bb4c168b4e8f8da421faf1e36156c73;
    uint256 internal constant GAMMA_X1_PART2 = 0xc19ac8e276261148e70861d0d0282eb9fb66175218908db83a4af2a2be9cc0b6;
    uint256 internal constant GAMMA_Y0_PART1 = 0x0000000000000000000000000000000002f0c1a7df29c80644d2c2a859654de6;
    uint256 internal constant GAMMA_Y0_PART2 = 0x6dde3f1c68bba7a990c6f076bf57ef21f3ed4ba60dbec45639dea86cf1a6a162;
    uint256 internal constant GAMMA_Y1_PART1 = 0x00000000000000000000000000000000039b1a432df43e8d3d62dc7ff3d47c12;
    uint256 internal constant GAMMA_Y1_PART2 = 0x393adab8cc238a316ad2ca5cef7890228f61576368266874a078c078790eea3f;

    // -[η]_2, refreshed from sigma_verify.json and negated for pairing.
    uint256 internal constant ETA_X0_PART1 = 0x00000000000000000000000000000000128bdfe90501684add21fd1209ace1f6;
    uint256 internal constant ETA_X0_PART2 = 0xda2e5c323dcb377ce86fa713d6131037ef3283ef622806a34562e56961610097;
    uint256 internal constant ETA_X1_PART1 = 0x00000000000000000000000000000000080a69638b454d302c6708de704fb87f;
    uint256 internal constant ETA_X1_PART2 = 0x048ed07668cffb6e8dd8b4f5417e309f0da044e61f8b115dfecc027382764c3f;
    uint256 internal constant ETA_Y0_PART1 = 0x0000000000000000000000000000000018ab2ffa1a26e0cb70554677660bfa67;
    uint256 internal constant ETA_Y0_PART2 = 0xa15700f3b5c30af63657d18c7c1aa325404fb9309b10a76303f4c945587b07a5;
    uint256 internal constant ETA_Y1_PART1 = 0x0000000000000000000000000000000008239a8597466afb2c9075398b445fce;
    uint256 internal constant ETA_Y1_PART2 = 0x6894c8d905784afb14aa606207a027b0f56d6873f893784f05e6d7e8ebc6f84d;

    // -[δ]_2, refreshed from sigma_verify.json and negated for pairing.
    uint256 internal constant DELTA_X0_PART1 = 0x0000000000000000000000000000000001bb56c4eefb0466294d6400546c1d15;
    uint256 internal constant DELTA_X0_PART2 = 0xd5b938ae8727af67eec56607e8cf955189700620762aff5cf626b66be6fb89a4;
    uint256 internal constant DELTA_X1_PART1 = 0x000000000000000000000000000000000ba1355632bf852089083e4f4c94dd02;
    uint256 internal constant DELTA_X1_PART2 = 0xa6c19ea38f18b3d7cef415754db5fe4b4e9ce4e2cfeb5ea41a3c327278901705;
    uint256 internal constant DELTA_Y0_PART1 = 0x00000000000000000000000000000000069993ce963a2e94b34345d08a3b4c6e;
    uint256 internal constant DELTA_Y0_PART2 = 0xf4e0be9bec21fa8832cc91d2d2de22c8b81870cd34d2397b3e965063df0c0323;
    uint256 internal constant DELTA_Y1_PART1 = 0x000000000000000000000000000000000204edf39bdf1c6592e4d0dc01318ea3;
    uint256 internal constant DELTA_Y1_PART2 = 0x912e9a2f733e8044fa7c8c0f45beb5cd61248abfe65aa22832ae6f91cfca1f7a;

    // -[x]_2, refreshed from sigma_verify.json and negated for pairing.
    uint256 internal constant X_X0_PART1 = 0x000000000000000000000000000000000fd840491fe66a0cc60f45930d88a9b5;
    uint256 internal constant X_X0_PART2 = 0x62136137f78260648ce6a4bf5d31849f18de090e2644780d2bf6b42e20842276;
    uint256 internal constant X_X1_PART1 = 0x000000000000000000000000000000000fabe7238383b48bd61f25125a0d0933;
    uint256 internal constant X_X1_PART2 = 0x06ef5511550312e2c1a9fb985e21ce1bf71b1fb0565c3b54836463eb1f043d48;
    uint256 internal constant X_Y0_PART1 = 0x0000000000000000000000000000000010e716bbdb338901b238d9f87c72f114;
    uint256 internal constant X_Y0_PART2 = 0x08a7fb342bd25a78136d46bd782b23628d8ddb01304d9b7f67a267f3878e2270;
    uint256 internal constant X_Y1_PART1 = 0x0000000000000000000000000000000011660f79174de9952ac8f61b370e68e3;
    uint256 internal constant X_Y1_PART2 = 0x3f38addb65bd1a43d48dc2b8f6e15c452a9ad7e17c83fed266eb7fc8055b2e1e;

    // -[y]_2, refreshed from sigma_verify.json and negated for pairing.
    uint256 internal constant Y_X0_PART1 = 0x00000000000000000000000000000000187b14cdde696e37ffd8a8cc68a4dcab;
    uint256 internal constant Y_X0_PART2 = 0x70e189eb5a7eb041b1b2e6641f6f9b8a7e80e49923394dfbbc330eb14706ca67;
    uint256 internal constant Y_X1_PART1 = 0x000000000000000000000000000000001016e78ff8d77a593a17ecde907696bd;
    uint256 internal constant Y_X1_PART2 = 0x31ee56db72b23a473a96a6f089cc3406a7c816d9407ee3cc4a0883f679d2ba6d;
    uint256 internal constant Y_Y0_PART1 = 0x000000000000000000000000000000000d342cbc123598955079dfac077a8081;
    uint256 internal constant Y_Y0_PART2 = 0x601a544516a6379587b6a5a3785436050feb0d298fff3cee9494a78220575ace;
    uint256 internal constant Y_Y1_PART1 = 0x0000000000000000000000000000000000e1973dc3ce78955685a635ef56fd41;
    uint256 internal constant Y_Y1_PART2 = 0x3db77eba7f62e090996c7244ff93fcc2f65f9b99e066a87a38022a15dec00cae;

    /// @notice Load verification keys to memory in runtime.
    /// @dev The constants are loaded into memory in a specific layout declared in the constants starting from
    /// `VK_` prefix.
    /// NOTE: Function may corrupt the memory state if some memory was used before this function was called.
    function _loadVerificationKey() internal pure virtual {
        uint256 lagrangeKlXPart1 = TokamakVerifierKeyGenerated.LAGRANGE_KL_X_PART1;
        uint256 lagrangeKlXPart2 = TokamakVerifierKeyGenerated.LAGRANGE_KL_X_PART2;
        uint256 lagrangeKlYPart1 = TokamakVerifierKeyGenerated.LAGRANGE_KL_Y_PART1;
        uint256 lagrangeKlYPart2 = TokamakVerifierKeyGenerated.LAGRANGE_KL_Y_PART2;

        uint256 identityXPart1 = TokamakVerifierKeyGenerated.IDENTITY_X_PART1;
        uint256 identityXPart2 = TokamakVerifierKeyGenerated.IDENTITY_X_PART2;
        uint256 identityYPart1 = TokamakVerifierKeyGenerated.IDENTITY_Y_PART1;
        uint256 identityYPart2 = TokamakVerifierKeyGenerated.IDENTITY_Y_PART2;

        uint256 sigmaXXPart1 = TokamakVerifierKeyGenerated.SIGMA_X_X_PART1;
        uint256 sigmaXXPart2 = TokamakVerifierKeyGenerated.SIGMA_X_X_PART2;
        uint256 sigmaXYPart1 = TokamakVerifierKeyGenerated.SIGMA_X_Y_PART1;
        uint256 sigmaXYPart2 = TokamakVerifierKeyGenerated.SIGMA_X_Y_PART2;

        uint256 sigmaYXPart1 = TokamakVerifierKeyGenerated.SIGMA_Y_X_PART1;
        uint256 sigmaYXPart2 = TokamakVerifierKeyGenerated.SIGMA_Y_X_PART2;
        uint256 sigmaYYPart1 = TokamakVerifierKeyGenerated.SIGMA_Y_Y_PART1;
        uint256 sigmaYYPart2 = TokamakVerifierKeyGenerated.SIGMA_Y_Y_PART2;

        assembly {
            /*
            "lagrange_KL": {
                "x": "0x04f1e1a2ec023aef31bde5b77da1e69ddf5f0bc762904ccee1e8b0131e517246ccf938b28f294dcaca7dbd0c36ff3607",
                "y": "0x13440b9abcae5c5c5749fbc390065d1edea2da1ca7a4f63960dc958c9f32d289c3df14028dc7262642cc1466d6745bef"
            }
            */
            // preproccessed KL commitment vk
            mstore(VK_POLY_KXLX_X_PART1, lagrangeKlXPart1)
            mstore(VK_POLY_KXLX_X_PART2, lagrangeKlXPart2)
            mstore(VK_POLY_KXLX_Y_PART1, lagrangeKlYPart1)
            mstore(VK_POLY_KXLX_Y_PART2, lagrangeKlYPart2)

            /*
            "G": {
                "x": "0x0b001b4cc05fa01578be7d4e821d6ff58f2a05c584fba3cb31a37942dece65eadec9a878add2282f7c2513abb8d4ab05",
                "y": "0x15e237775397ed22eef43dd36cdca277c9cf6fa7e4ffff0a5bb4b20a82392caacf0f63fb6cdb02bccf2f5af14970d6b9"
            },
            */
            // [1]_1 (Generator/Identity point)
            mstore(VK_IDENTITY_X_PART1, identityXPart1)
            mstore(VK_IDENTITY_X_PART2, identityXPart2)
            mstore(VK_IDENTITY_Y_PART1, identityYPart1)
            mstore(VK_IDENTITY_Y_PART2, identityYPart2)

            /*
            "x": {
                "x": "0x0d45aca9cf6986877b859616c9613dfe38633f32c81a5a5e426f37beb4f1f9a8db94bcb17673c014031ed6f80406ae12",
                "y": "0x014de0221674a94bd5e60383f1f262d100c79178775b99480ec1a267fb28c905389357c2c111b94becf8676365f64133"
            },
            */
            // [x]_1 (Polynomial evaluation point)
            mstore(VK_POLY_X_X_PART1, sigmaXXPart1)
            mstore(VK_POLY_X_X_PART2, sigmaXXPart2)
            mstore(VK_POLY_X_Y_PART1, sigmaXYPart1)
            mstore(VK_POLY_X_Y_PART2, sigmaXYPart2)

            /*
            "y": {
                "x": "0x09cf106b4240325df41d6a76331883cbe61a678d7d877bf670446001be74d27580424e05a37af26bb85f99b380758888",
                "y": "0x0889c802a90694c68dfbcf207205778a7493cda2cbb6f9fb0b5ad39dbeef2fac91d847cc01d6040164ef30d840395af0"
            }
            */
            // [y]_1 (Polynomial evaluation point)
            mstore(VK_POLY_Y_X_PART1, sigmaYXPart1)
            mstore(VK_POLY_Y_X_PART2, sigmaYXPart2)
            mstore(VK_POLY_Y_Y_PART1, sigmaYYPart1)
            mstore(VK_POLY_Y_Y_PART2, sigmaYYPart2)
        }
    }

    function verify(
        uint128[] calldata, // _proof_part1 (16 bytes)
        uint256[] calldata, // _proof part2 (32 bytes)
        uint128[] calldata, // _preprocessed_part1 (16 bytes)
        uint256[] calldata, // _preprocessed_part2 (32 bytes)
        uint256[] calldata, // a_pub_user
        uint256[] calldata // a_pub_block
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

            /// @dev Writes one `(point, scalar)` term into a packed MSM buffer.
            function msmStoreTerm(buffer, idx, point, scalar) {
                let off := add(buffer, mul(idx, 0xa0))
                mstore(off, mload(point))
                mstore(add(off, 0x20), mload(add(point, 0x20)))
                mstore(add(off, 0x40), mload(add(point, 0x40)))
                mstore(add(off, 0x60), mload(add(point, 0x60)))
                mstore(add(off, 0x80), scalar)
            }

            /// @dev Computes MSM over packed `(point, scalar)` terms already stored in memory.
            function g1msmFromBuffer(buffer, nTerms, dest) {
                if iszero(staticcall(gas(), 0x0c, buffer, mul(nTerms, 0xa0), dest, 0x80)) {
                    revertWithMessage(25, "g1msmFromBuffer failed")
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
                let aPubUserOffset := calldataload(0x84)
                let aPubBlockOffset := calldataload(0xa4)
                let part1LengthInWords := calldataload(add(offset, 0x04))
                let part2LengthInWords := calldataload(add(offset2, 0x04))
                let preprocessedPart1LengthInWords := calldataload(add(offset3, 0x04))
                let preprocessedPart2LengthInWords := calldataload(add(offset4, 0x04))
                let aPubUserLength := calldataload(add(aPubUserOffset, 0x04))
                let aPubBlockLength := calldataload(add(aPubBlockOffset, 0x04))
                let isValid :=
                    and(
                        and(
                            and(eq(part1LengthInWords, 38), eq(part2LengthInWords, 42)),
                            and(
                                eq(preprocessedPart1LengthInWords, 6),
                                eq(preprocessedPart2LengthInWords, 6)
                            )
                        ),
                        and(
                            eq(aPubUserLength, EXPECTED_L_USER),
                            eq(aPubBlockLength, sub(EXPECTED_L_FREE, EXPECTED_L_USER))
                        )
                    )

                // revert if the length of the proof is not valid
                if iszero(isValid) {
                    revertWithMessage(27, "loadProof: Proof is invalid")
                }

                // S PERMUTATION POLYNOMIALS & O_pub,fix
                {
                    let x0 := calldataload(add(offset3, 0x024))
                    let y0 := calldataload(add(offset3, 0x044))
                    let x1 := calldataload(add(offset3, 0x064))
                    let y1 := calldataload(add(offset3, 0x084))
                    let x2 := calldataload(add(offset3, 0x0a4))
                    let y2 := calldataload(add(offset3, 0x0c4))
                    mstore(PUBLIC_INPUTS_S_0_X_SLOT_PART1, x0)
                    mstore(PUBLIC_INPUTS_S_0_Y_SLOT_PART1, y0)
                    mstore(PUBLIC_INPUTS_S_1_X_SLOT_PART1, x1)
                    mstore(PUBLIC_INPUTS_S_1_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_OPUB_FIX_X_SLOT_PART1, x2)
                    mstore(PROOF_POLY_OPUB_FIX_Y_SLOT_PART1, y2)
                    x0 := calldataload(add(offset4, 0x024))
                    y0 := calldataload(add(offset4, 0x044))
                    x1 := calldataload(add(offset4, 0x064))
                    y1 := calldataload(add(offset4, 0x084))
                    x2 := calldataload(add(offset4, 0x0a4))
                    y2 := calldataload(add(offset4, 0x0c4))
                    mstore(PUBLIC_INPUTS_S_0_X_SLOT_PART2, x0)
                    mstore(PUBLIC_INPUTS_S_0_Y_SLOT_PART2, y0)
                    mstore(PUBLIC_INPUTS_S_1_X_SLOT_PART2, x1)
                    mstore(PUBLIC_INPUTS_S_1_Y_SLOT_PART2, y1)
                    mstore(PROOF_POLY_OPUB_FIX_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_OPUB_FIX_Y_SLOT_PART2, y2)
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
                // PROOF O_PUB & A_free
                {
                    let x0 := calldataload(add(offset, 0x464))
                    let y0 := calldataload(add(offset, 0x484))
                    let x1 := calldataload(add(offset, 0x4a4))
                    let y1 := calldataload(add(offset, 0x4c4))
                    mstore(PROOF_POLY_OPUB_X_SLOT_PART1, x0)
                    mstore(PROOF_POLY_OPUB_Y_SLOT_PART1, y0)
                    mstore(PROOF_POLY_A_FREE_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_A_FREE_Y_SLOT_PART1, y1)
                    x0 := calldataload(add(offset2, 0x464))
                    y0 := calldataload(add(offset2, 0x484))
                    x1 := calldataload(add(offset2, 0x4a4))
                    y1 := calldataload(add(offset2, 0x4c4))
                    mstore(PROOF_POLY_OPUB_X_SLOT_PART2, x0)
                    mstore(PROOF_POLY_OPUB_Y_SLOT_PART2, y0)
                    mstore(PROOF_POLY_A_FREE_X_SLOT_PART2, x1)
                    mstore(PROOF_POLY_A_FREE_Y_SLOT_PART2, y1)
                }

                mstore(PROOF_R1XY_SLOT, mod(calldataload(add(offset2, 0x4e4)), R_MOD))
                mstore(PROOF_R2XY_SLOT, mod(calldataload(add(offset2, 0x504)), R_MOD))
                mstore(PROOF_R3XY_SLOT, mod(calldataload(add(offset2, 0x524)), R_MOD))
                mstore(PROOF_VXY_SLOT, mod(calldataload(add(offset2, 0x544)), R_MOD))
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

            /// @dev Prepare scalar queries consumed by the single-shot Step 4 MSM.
            /// We compute:
            /// - t_n(χ) := χ^{n}-1
            /// - t_{smax}(ζ) := ζ^{smax}-1
            /// - t_{m_I}(χ) := χ^{m_I}-1

            function prepareQueries() {
                // calculate t_n(χ)
                {
                    let chi := mload(CHALLENGE_CHI_SLOT)
                    let t := sub(modexp(chi, CONSTANT_N), 1)
                    mstore(INTERMERDIARY_SCALAR_T_N_CHI_SLOT, t)
                }

                // calculate t_smax(ζ)
                {
                    let zeta := mload(CHALLENGE_ZETA_SLOT)
                    let t := sub(modexp(zeta, EXPECTED_SMAX), 1)
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

            // A_eval = A(chi)
            // A(chi) = sum_0^{l-1}(a_j * M_j(chi))
            function computeAPUB() {
                let chi := mload(CHALLENGE_CHI_SLOT)
                let aPubUserOffset := calldataload(0x84)
                let aPubBlockOffset := calldataload(0xa4)

                let l_user := EXPECTED_L_USER
                let l_free := EXPECTED_L_FREE
                let omega := OMEGA_L_FREE

                // Compute chi^64 - 1
                let chi_n := modexp(chi, l_free)
                let chi_n_1 := addmod(chi_n, sub(R_MOD, 1), R_MOD)

                // Check if chi is a 64th root of unity
                if iszero(chi_n_1) {
                    // Special case: find and return the corresponding value
                    let omega_power := 1
                    for { let i := 0 } lt(i, l_free) { i := add(i, 1) } {
                        if eq(chi, omega_power) {
                            let val
                            switch lt(i, l_user)
                            case 1 {
                                val := calldataload(add(add(aPubUserOffset, 0x24), mul(i, 0x20)))
                            }
                            default {
                                val := calldataload(
                                    add(add(aPubBlockOffset, 0x24), mul(sub(i, l_user), 0x20))
                                )
                            }
                            mstore(INTERMEDIARY_SCALAR_APUB_SLOT, val)
                            leave
                        }
                        omega_power := mulmod(omega_power, omega, R_MOD)
                    }
                }

                // Normal case: compute weighted sum
                // We store:
                // - numerator base: a_j * ω^j
                // - denominator_full: (χ - ω^j) * l_free
                // and build prefix products in the same pass to reduce loop overhead.
                let weightedSumRaw := 0
                let nonZeroCount := 0
                let tempOffset := COMPUTE_APUB_NUMERATOR_BUFFER_SLOT
                let denomOffset := COMPUTE_APUB_DENOMINATOR_BUFFER_SLOT
                let prefixOffset := COMPUTE_APUB_PREFIX_BUFFER_SLOT
                let omega_power := 1
                let prefix := 1

                for { let i := 0 } lt(i, l_free) { i := add(i, 1) } {
                    let val
                    switch lt(i, l_user)
                    case 1 { val := calldataload(add(add(aPubUserOffset, 0x24), mul(i, 0x20))) }
                    default {
                        val := calldataload(
                            add(add(aPubBlockOffset, 0x24), mul(sub(i, l_user), 0x20))
                        )
                    }
                    if val {
                        let denominator := addmod(chi, sub(R_MOD, omega_power), R_MOD)

                        // singular point: χ == ω^j
                        if iszero(denominator) {
                            mstore(INTERMEDIARY_SCALAR_APUB_SLOT, val)
                            leave
                        }

                        let denominatorFull := mulmod(denominator, l_free, R_MOD)
                        let numeratorBase := mulmod(val, omega_power, R_MOD)

                        mstore(add(tempOffset, mul(nonZeroCount, 0x20)), numeratorBase)
                        mstore(add(denomOffset, mul(nonZeroCount, 0x20)), denominatorFull)

                        prefix := mulmod(prefix, denominatorFull, R_MOD)
                        mstore(add(prefixOffset, mul(nonZeroCount, 0x20)), prefix)
                        nonZeroCount := add(nonZeroCount, 1)
                    }
                    omega_power := mulmod(omega_power, omega, R_MOD)
                }

                // Invert product once, then recover each inverse right-to-left.
                if nonZeroCount {
                    let running := modexp(prefix, sub(R_MOD, 2))

                    for { let j := nonZeroCount } gt(j, 0) { j := sub(j, 1) } {
                        let idx := sub(j, 1)
                        let prefixPrev := 1
                        if idx {
                            prefixPrev := mload(add(prefixOffset, sub(mul(idx, 0x20), 0x20)))
                        }

                        let invDenominatorFull := mulmod(prefixPrev, running, R_MOD)
                        let denominatorFull := mload(add(denomOffset, mul(idx, 0x20)))
                        running := mulmod(running, denominatorFull, R_MOD)

                        let numeratorBase := mload(add(tempOffset, mul(idx, 0x20)))
                        let contributionRaw := mulmod(numeratorBase, invDenominatorFull, R_MOD)
                        weightedSumRaw := addmod(weightedSumRaw, contributionRaw, R_MOD)
                    }
                }

                // Apply (χ^n - 1) once at the end.
                let result := mulmod(weightedSumRaw, chi_n_1, R_MOD)

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
            /// Implementation note:
            /// - This implementation computes `[LHS]_1 + [AUX]_1` directly in one 22-term MSM using the expanded form.
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
            ///              d := -κ1^3R_{x,y} - κ2R’_{x,y} - κ2^2R’’_{x,y} - κ1V_{x,y} - κ1^4A_{eval}
            ///
            ///  and where
            ///
            ///  [LHS_B]_1 := (1+κ2κ1^4)[A_{free}]_1 - κ2κ1^4A_{eval}[1]_1
            ///
            ///  implementation note for current proof format:
            ///  - `O_{pub,fix}` is loaded from `_preprocessed` and used in final pairing
            ///  - `A_{free}` is loaded from `_proof`
            ///  - `A_{eval}` is provided by `computeAPUB()` into `INTERMEDIARY_SCALAR_APUB_SLOT`
            ///
            ///  and
            ///
            ///  [AUX]_1 := κ2 * χ * [Π_{χ}]_1 + κ2 * ζ *[Π_ζ]_1 +
            ///             κ2^2 * ω_{m_i}^{-1} * χ *[M_{χ}]_1 + κ2^2 * ζ * [M_{ζ}]_1 + κ2^3 * ω_{m_i}^{-1} * χ * [N_{χ}]_1 + κ_2^3 ω_smax^{-1} * ζ * [N_{ζ}]
            ///

            /// @dev Compute [LHS]_1 + [AUX]_1 in one 22-term MSM using the fully expanded form
            ///      from `bridge/docs/verifier-spec.md` summary table.
            function prepareLhsAuxSingleMSM() {
                let msmPtr := 0x9800

                let kappa0 := mload(CHALLENGE_KAPPA_0_SLOT)
                let kappa1 := mload(CHALLENGE_KAPPA_1_SLOT)
                let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                let chi := mload(CHALLENGE_CHI_SLOT)
                let zeta := mload(CHALLENGE_ZETA_SLOT)
                let theta0 := mload(CHALLENGE_THETA_0_SLOT)
                let theta1 := mload(CHALLENGE_THETA_1_SLOT)
                let theta2 := mload(CHALLENGE_THETA_2_SLOT)

                let kappa1_pow2 := mulmod(kappa1, kappa1, R_MOD)
                let kappa1_pow3 := mulmod(kappa1, kappa1_pow2, R_MOD)
                let kappa1_pow4 := mulmod(kappa1, kappa1_pow3, R_MOD)
                let kappa2_pow2 := mulmod(kappa2, kappa2, R_MOD)
                let kappa2_pow3 := mulmod(kappa2_pow2, kappa2, R_MOD)
                let common := mulmod(kappa2, kappa1_pow2, R_MOD)

                // Scratch slots:
                // STEP4_COEFF_C_G_SLOT: C_G, STEP4_COEFF_C_F_SLOT: C_F, STEP4_COEFF_C_B_SLOT: C_B = C_G + C_F.
                {
                    let chi_minus_1 := addmod(chi, sub(R_MOD, 1), R_MOD)
                    let kappa0_chi_minus_1 := mulmod(kappa0, chi_minus_1, R_MOD)
                    let kappa0_pow2_k0 :=
                        mulmod(
                            mulmod(kappa0, kappa0, R_MOD),
                            mload(INTERMEDIARY_SCALAR_KO_SLOT),
                            R_MOD
                        )
                    let kappa0_mix := addmod(kappa0_chi_minus_1, kappa0_pow2_k0, R_MOD)
                    let c_g :=
                        mulmod(mulmod(common, mload(PROOF_R1XY_SLOT), R_MOD), kappa0_mix, R_MOD)
                    let c_f_inner :=
                        addmod(
                            mulmod(kappa0_chi_minus_1, mload(PROOF_R2XY_SLOT), R_MOD),
                            mulmod(kappa0_pow2_k0, mload(PROOF_R3XY_SLOT), R_MOD),
                            R_MOD
                        )
                    let c_f := addmod(0, sub(R_MOD, mulmod(common, c_f_inner, R_MOD)), R_MOD)
                    mstore(STEP4_COEFF_C_G_SLOT, c_g)
                    mstore(STEP4_COEFF_C_F_SLOT, c_f)
                    mstore(STEP4_COEFF_C_B_SLOT, addmod(c_g, c_f, R_MOD))
                }

                // (1 + κ2κ1^4) * [A_free]_1
                msmStoreTerm(
                    msmPtr,
                    0,
                    PROOF_POLY_A_FREE_X_SLOT_PART1,
                    addmod(1, mulmod(kappa2, kappa1_pow4, R_MOD), R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    1,
                    PROOF_POLY_U_X_SLOT_PART1,
                    mulmod(kappa2, mload(PROOF_VXY_SLOT), R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    2,
                    PROOF_POLY_W_X_SLOT_PART1,
                    addmod(0, sub(R_MOD, kappa2), R_MOD)
                )
                msmStoreTerm(msmPtr, 3, PROOF_POLY_V_X_SLOT_PART1, mulmod(kappa2, kappa1, R_MOD))
                msmStoreTerm(
                    msmPtr,
                    4,
                    PROOF_POLY_QAX_X_SLOT_PART1,
                    addmod(
                        0,
                        sub(R_MOD, mulmod(kappa2, mload(INTERMERDIARY_SCALAR_T_N_CHI_SLOT), R_MOD)),
                        R_MOD
                    )
                )
                msmStoreTerm(
                    msmPtr,
                    5,
                    PROOF_POLY_QAY_X_SLOT_PART1,
                    addmod(
                        0,
                        sub(
                            R_MOD,
                            mulmod(kappa2, mload(INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT), R_MOD)
                        ),
                        R_MOD
                    )
                )
                msmStoreTerm(
                    msmPtr,
                    6,
                    VK_POLY_KXLX_X_PART1,
                    mulmod(common, addmod(mload(PROOF_R1XY_SLOT), sub(R_MOD, 1), R_MOD), R_MOD)
                )
                msmStoreTerm(msmPtr, 7, PROOF_POLY_B_X_SLOT_PART1, mload(STEP4_COEFF_C_B_SLOT))
                msmStoreTerm(
                    msmPtr,
                    8,
                    PUBLIC_INPUTS_S_0_X_SLOT_PART1,
                    mulmod(theta0, mload(STEP4_COEFF_C_F_SLOT), R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    9,
                    PUBLIC_INPUTS_S_1_X_SLOT_PART1,
                    mulmod(theta1, mload(STEP4_COEFF_C_F_SLOT), R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    10,
                    VK_POLY_X_X_PART1,
                    mulmod(theta0, mload(STEP4_COEFF_C_G_SLOT), R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    11,
                    VK_POLY_Y_X_PART1,
                    mulmod(theta1, mload(STEP4_COEFF_C_G_SLOT), R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    12,
                    PROOF_POLY_QCX_X_SLOT_PART1,
                    addmod(
                        0,
                        sub(
                            R_MOD,
                            mulmod(common, mload(INTERMERDIARY_SCALAR_T_MI_CHI_SLOT), R_MOD)
                        ),
                        R_MOD
                    )
                )
                msmStoreTerm(
                    msmPtr,
                    13,
                    PROOF_POLY_QCY_X_SLOT_PART1,
                    addmod(
                        0,
                        sub(
                            R_MOD,
                            mulmod(common, mload(INTERMERDIARY_SCALAR_T_SMAX_ZETA_SLOT), R_MOD)
                        ),
                        R_MOD
                    )
                )
                msmStoreTerm(
                    msmPtr,
                    14,
                    PROOF_POLY_R_X_SLOT_PART1,
                    addmod(
                        mulmod(kappa2, kappa1_pow3, R_MOD),
                        addmod(kappa2_pow2, kappa2_pow3, R_MOD),
                        R_MOD
                    )
                )

                {
                    let coeff_identity_base :=
                        addmod(
                            addmod(
                                // κ2κ1^4 * A_eval
                                mulmod(
                                    mulmod(kappa2, kappa1_pow4, R_MOD),
                                    mload(INTERMEDIARY_SCALAR_APUB_SLOT),
                                    R_MOD
                                ),
                                mulmod(mulmod(kappa2, kappa1, R_MOD), mload(PROOF_VXY_SLOT), R_MOD),
                                R_MOD
                            ),
                            addmod(
                                mulmod(
                                    mulmod(kappa2, kappa1_pow3, R_MOD),
                                    mload(PROOF_R1XY_SLOT),
                                    R_MOD
                                ),
                                addmod(
                                    mulmod(kappa2_pow2, mload(PROOF_R2XY_SLOT), R_MOD),
                                    mulmod(kappa2_pow3, mload(PROOF_R3XY_SLOT), R_MOD),
                                    R_MOD
                                ),
                                R_MOD
                            ),
                            R_MOD
                        )
                    let coeff_identity :=
                        addmod(
                            addmod(0, sub(R_MOD, coeff_identity_base), R_MOD),
                            mulmod(theta2, mload(STEP4_COEFF_C_B_SLOT), R_MOD),
                            R_MOD
                        )
                    msmStoreTerm(msmPtr, 15, VK_IDENTITY_X_PART1, coeff_identity)
                }

                msmStoreTerm(msmPtr, 16, PROOF_POLY_PI_CHI_X_SLOT_PART1, mulmod(kappa2, chi, R_MOD))
                msmStoreTerm(
                    msmPtr,
                    17,
                    PROOF_POLY_PI_ZETA_X_SLOT_PART1,
                    mulmod(kappa2, zeta, R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    18,
                    PROOF_POLY_M_CHI_X_SLOT_PART1,
                    mulmod(kappa2_pow2, mulmod(OMEGA_MI_1, chi, R_MOD), R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    19,
                    PROOF_POLY_M_ZETA_X_SLOT_PART1,
                    mulmod(kappa2_pow2, zeta, R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    20,
                    PROOF_POLY_N_CHI_X_SLOT_PART1,
                    mulmod(kappa2_pow3, mulmod(OMEGA_MI_1, chi, R_MOD), R_MOD)
                )
                msmStoreTerm(
                    msmPtr,
                    21,
                    PROOF_POLY_N_ZETA_X_SLOT_PART1,
                    mulmod(kappa2_pow3, mulmod(OMEGA_SMAX_MINUS_1, zeta, R_MOD), R_MOD)
                )

                g1msmFromBuffer(msmPtr, 22, PAIRING_AGG_LHS_AUX_X_SLOT_PART1)
            }

            /// @dev [RHS_1]_1 := κ2[Π_{χ}]_1 + κ2^2[M_{χ}]_1 + κ2^3[N_{χ}]_1
            function prepareRHS1() {
                let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                let kappa2_pow2 := mulmod(kappa2, kappa2, R_MOD)
                let kappa2_pow3 := mulmod(kappa2_pow2, kappa2, R_MOD)
                let msmPtr := 0x9800

                msmStoreTerm(msmPtr, 0, PROOF_POLY_PI_CHI_X_SLOT_PART1, kappa2)
                msmStoreTerm(msmPtr, 1, PROOF_POLY_M_CHI_X_SLOT_PART1, kappa2_pow2)
                msmStoreTerm(msmPtr, 2, PROOF_POLY_N_CHI_X_SLOT_PART1, kappa2_pow3)
                g1msmFromBuffer(msmPtr, 3, PAIRING_AGG_RHS_1_X_SLOT_PART1)
            }

            /// @dev [RHS_2]_1 := κ2[Π_{ζ}]_1 + κ2^2[M_{ζ}]_1 + κ2^3[N_{ζ}]_1
            function prepareRHS2() {
                let kappa2 := mload(CHALLENGE_KAPPA_2_SLOT)
                let kappa2_pow2 := mulmod(kappa2, kappa2, R_MOD)
                let kappa2_pow3 := mulmod(kappa2_pow2, kappa2, R_MOD)
                let msmPtr := 0x9800

                msmStoreTerm(msmPtr, 0, PROOF_POLY_PI_ZETA_X_SLOT_PART1, kappa2)
                msmStoreTerm(msmPtr, 1, PROOF_POLY_M_ZETA_X_SLOT_PART1, kappa2_pow2)
                msmStoreTerm(msmPtr, 2, PROOF_POLY_N_ZETA_X_SLOT_PART1, kappa2_pow3)
                g1msmFromBuffer(msmPtr, 3, PAIRING_AGG_RHS_2_X_SLOT_PART1)
            }

            /*////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                                            5. Pairing
                ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

            /// @notice Checks the final pairing
            /// @dev We should check the equation:
            ///
            ///    /                                                  \           /                                                          \
            ///   | e([LHS]_1 + [AUX]_1, [1]_2)e([B]_1, [α^4]_2)       |         |  e([O_{pub,fix}]_1+[O_{pub,free}]_1, [γ]_2)e([O_mid]_1, [η]_2)e([O_prv]_1, [δ]_2)  |
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

                // load [O_{pub,fix}]_1 + [O_{pub,free}]_1 using G1 add precompile
                mstore(0xf00, mload(PROOF_POLY_OPUB_FIX_X_SLOT_PART1))
                mstore(0xf20, mload(PROOF_POLY_OPUB_FIX_X_SLOT_PART2))
                mstore(0xf40, mload(PROOF_POLY_OPUB_FIX_Y_SLOT_PART1))
                mstore(0xf60, mload(PROOF_POLY_OPUB_FIX_Y_SLOT_PART2))
                mstore(0xf80, mload(PROOF_POLY_OPUB_X_SLOT_PART1))
                mstore(0xfa0, mload(PROOF_POLY_OPUB_X_SLOT_PART2))
                mstore(0xfc0, mload(PROOF_POLY_OPUB_Y_SLOT_PART1))
                mstore(0xfe0, mload(PROOF_POLY_OPUB_Y_SLOT_PART2))
                if iszero(staticcall(gas(), 0x0b, 0xf00, 0x100, 0x780, 0x80)) {
                    revertWithMessage(22, "g1add precompile failed")
                }

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

                // load [RHS_2]_1 := κ2[Π_{ζ}]_1 + κ2^2[M_{ζ}]_1 + κ2^3[N_{ζ}]_1
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
                if iszero(success) {
                    revertWithMessage(32, "finalPairing: precompile failure")
                }
                if iszero(mload(0)) {
                    revertWithMessage(29, "finalPairing: pairing failure")
                }
            }

            // Step1: Load the PI/proof
            loadProof()

            // Step2: Recompute all the challenges with the transcript
            initializeTranscript()

            // Step3: computation of [F]_1, [G]_1, t_n(χ), t_smax(ζ), t_ml(χ), K0(χ), and A_eval
            prepareQueries()
            computeLagrangeK0Eval()
            computeAPUB()

            // Step4: one-shot computation of [LHS]_1 + [AUX]_1, and RHS aggregation for pairing terms
            prepareLhsAuxSingleMSM()
            prepareRHS1()
            prepareRHS2()

            // Step5: final pairing - COMMENTED OUT FOR DEBUGGING
            finalPairing()
            final_result := true

            // DEBUG: Return A_eval instead of final result
            mstore(0x00, final_result)
            return(0x00, 0x20)
        }
    }
}
