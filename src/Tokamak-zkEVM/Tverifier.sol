// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ITverifier} from "./interface/ITverifier.sol";

/* solhint-disable max-line-length */
/// @author Project Ooo team
/// @dev It uses a custom memory layout inside the inline assembly block. Each reserved memory cell is declared in the
/// constants below.
/// @dev For a better understanding of the verifier algorithm please refer to the following paper:
/// * Original Tokamak zkEVM Paper: https://eprint.iacr.org/2024/507.pdf
/// The notation used in the code is the same as in the papers.
/* solhint-enable max-line-length */
contract TVerifier is ITverifier {

    /*//////////////////////////////////////////////////////////////
                            Proof Public Inputs
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S0_X_SLOT_PART1 = 0x200 + 0x000;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S0_X_SLOT_PART2 = 0x200 + 0x020;

    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S0_Y_SLOT_PART1 = 0x200 + 0x040;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S0_Y_SLOT_PART2 = 0x200 + 0x060;

    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S1_X_SLOT_PART1 = 0x200 + 0x080;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S1_X_SLOT_PART2 = 0x200 + 0x0a0;

    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S1_Y_SLOT_PART1 = 0x200 + 0x0c0;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S1_Y_SLOT_PART2 = 0x200 + 0x0e0;

    uint256 internal constant PUBLIC_INPUT_A_IN_LENGTH_SLOT = 0x200 + 0x100;
    uint256 internal constant PUBLIC_INPUT_A_IN_DATA_SLOT = 0x200 + 0x120; // Starts after length

    uint256 internal constant PUBLIC_INPUT_A_OUT_LENGTH_SLOT = 0x200 + 0x120; // Will be calculated at runtime
    uint256 internal constant PUBLIC_INPUT_A_OUT_DATA_SLOT = 0x200 + 0x140;   // Will be calculated at runtime

    /*//////////////////////////////////////////////////////////////
                        Hard coded Public Inputs
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S2_X_PART1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d; // to be hardcoded
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S2_X_PART2 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d; // to be hardcoded

    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S2_Y_PART1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d; // to be hardcoded
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S2_Y_PART2 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d; // to be hardcoded


    uint256 internal constant PUBLIC_INPUT_LI_KJ_X_SLOT_PART1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d; // to be hardcoded
    uint256 internal constant PUBLIC_INPUT_LI_KJ_X_SLOT_PART2 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d; // to be hardcoded

    uint256 internal constant PUBLIC_INPUT_LI_KJ_Y_SLOT_PART1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d; // to be hardcoded
    uint256 internal constant PUBLIC_INPUT_LI_KJ_Y_SLOT_PART2 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d; // to be hardcoded

    /*//////////////////////////////////////////////////////////////
                                  Proof
    //////////////////////////////////////////////////////////////*/

    // U
    uint256 internal constant PROOF_POLY_U_X_SLOT_PART1 = 0x200 + 0x120 + 0x020;
    uint256 internal constant PROOF_POLY_U_X_SLOT_PART2 = 0x200 + 0x120 + 0x040;
    uint256 internal constant PROOF_POLY_U_Y_SLOT_PART1 = 0x200 + 0x160 + 0x060;
    uint256 internal constant PROOF_POLY_U_Y_SLOT_PART2 = 0x200 + 0x160 + 0x080;
    // V
    uint256 internal constant PROOF_POLY_V_X_SLOT_PART1 = 0x200 + 0x160 + 0x0a0;
    uint256 internal constant PROOF_POLY_V_X_SLOT_PART2 = 0x200 + 0x160 + 0x0c0;
    uint256 internal constant PROOF_POLY_V_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_V_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // W
    uint256 internal constant PROOF_POLY_W_X_SLOT_PART1 = 0x200 + 0x160 + 0x0a0;
    uint256 internal constant PROOF_POLY_W_X_SLOT_PART2 = 0x200 + 0x160 + 0x0c0;
    uint256 internal constant PROOF_POLY_W_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_W_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // O_mid
    uint256 internal constant PROOF_POLY_OMID_X_SLOT_PART1 = 0x200 + 0x160 + 0x120;
    uint256 internal constant PROOF_POLY_OMID_X_SLOT_PART2 = 0x200 + 0x160 + 0x140;
    uint256 internal constant PROOF_POLY_OMID_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_OMID_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // O_prv
    uint256 internal constant PROOF_POLY_OPRV_X_SLOT_PART1 = 0x200 + 0x160 + 0x120;
    uint256 internal constant PROOF_POLY_OPRV_X_SLOT_PART2 = 0x200 + 0x160 + 0x140;
    uint256 internal constant PROOF_POLY_OPRV_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_OPRV_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // O_X
    uint256 internal constant PROOF_POLY_QX_X_SLOT_PART1 = 0x200 + 0x160 + 0x120;
    uint256 internal constant PROOF_POLY_QX_X_SLOT_PART2 = 0x200 + 0x160 + 0x140;
    uint256 internal constant PROOF_POLY_QX_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_QX_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // O_Y
    uint256 internal constant PROOF_POLY_QY_X_SLOT_PART1 = 0x200 + 0x160 + 0x120;
    uint256 internal constant PROOF_POLY_QY_X_SLOT_PART2 = 0x200 + 0x160 + 0x140;
    uint256 internal constant PROOF_POLY_QY_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_QY_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // O_Z
    uint256 internal constant PROOF_POLY_QZ_X_SLOT_PART1 = 0x200 + 0x160 + 0x120;
    uint256 internal constant PROOF_POLY_QZ_X_SLOT_PART2 = 0x200 + 0x160 + 0x140;
    uint256 internal constant PROOF_POLY_QZ_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_QZ_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // Π_χ
    uint256 internal constant PROOF_POLY_PI_CHI_X_SLOT_PART1 = 0x200 + 0x160 + 0x120;
    uint256 internal constant PROOF_POLY_PI_CHI_X_SLOT_PART2 = 0x200 + 0x160 + 0x140;
    uint256 internal constant PROOF_POLY_PI_CHI_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_PI_CHI_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // Π_ζ
    uint256 internal constant PROOF_POLY_PI_ZETA_X_SLOT_PART1 = 0x200 + 0x160 + 0x120;
    uint256 internal constant PROOF_POLY_PI_ZETA_X_SLOT_PART2 = 0x200 + 0x160 + 0x140;
    uint256 internal constant PROOF_POLY_PI_ZETA_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_PI_ZETA_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // Π_ξ
    uint256 internal constant PROOF_POLY_PI_XI_X_SLOT_PART1 = 0x200 + 0x160 + 0x120;
    uint256 internal constant PROOF_POLY_PI_XI_X_SLOT_PART2 = 0x200 + 0x160 + 0x140;
    uint256 internal constant PROOF_POLY_PI_XI_Y_SLOT_PART1 = 0x200 + 0x160 + 0x0e0;
    uint256 internal constant PROOF_POLY_PI_XI_Y_SLOT_PART2 = 0x200 + 0x160 + 0x100;
    // B
    uint256 internal constant PROOF_POLY_B_X_SLOT_PART1 = 0x200 + 0x160 + 0x1a0;
    uint256 internal constant PROOF_POLY_B_X_SLOT_PART2 = 0x200 + 0x160 + 0x1c0;
    uint256 internal constant PROOF_POLY_B_Y_SLOT_PART1 = 0x200 + 0x160 + 0x1a0;
    uint256 internal constant PROOF_POLY_B_Y_SLOT_PART2 = 0x200 + 0x160 + 0x1c0;
    // R
    uint256 internal constant PROOF_POLY_R_X_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_R_X_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    uint256 internal constant PROOF_POLY_R_Y_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_R_Y_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    // M_ζ
    uint256 internal constant PROOF_POLY_M_ZETA_X_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_M_ZETA_X_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    uint256 internal constant PROOF_POLY_M_ZETA_Y_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_M_ZETA_Y_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    // M_ω_Z^-1ξ
    uint256 internal constant PROOF_POLY_M_OMEGAZ_XI_X_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_M_OMEGAZ_XI_X_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    uint256 internal constant PROOF_POLY_M_OMEGAZ_XI_Y_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_M_OMEGAZ_XI_Y_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    // N_ω_Y^-1ζ
    uint256 internal constant PROOF_POLY_N_OMEGAY_ZETA_X_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_N_OMEGAY_ZETA_X_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    uint256 internal constant PROOF_POLY_N_OMEGAY_ZETA_Y_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_N_OMEGAY_ZETA_Y_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    // N_ω_Z^-1ξ
    uint256 internal constant PROOF_POLY_N_OMEGAZ_XI_X_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_N_OMEGAZ_XI_X_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    uint256 internal constant PROOF_POLY_N_OMEGAZ_XI_Y_SLOT_PART1 = 0x200 + 0x160 + 0x1e0;
    uint256 internal constant PROOF_POLY_N_OMEGAZ_XI_Y_SLOT_PART2 = 0x200 + 0x160 + 0x200;
    // R_xy
    uint256 internal constant PROOF_R1XY_SLOT = 0x200 + 0x160 + 0x200;
    // R'_xy
    uint256 internal constant PROOF_R2XY_SLOT = 0x200 + 0x160 + 0x200;
    // R''_xy
    uint256 internal constant PROOF_R3XY_SLOT = 0x200 + 0x160 + 0x200;



    /*//////////////////////////////////////////////////////////////
                 transcript slot (used for challenge computation)
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant TRANSCRIPT_BEGIN_SLOT = 0x200 + 0x160 + 0x420 + 0x020;
    uint256 internal constant TRANSCRIPT_DST_BYTE_SLOT = 0x200 + 0x160 + 0x420 + 0x040; // TODO can use less than 32 bytes
    uint256 internal constant TRANSCRIPT_STATE_0_SLOT = 0x200 + 0x160 + 0x420 + 0x060;
    uint256 internal constant TRANSCRIPT_STATE_1_SLOT = 0x200 + 0x160 + 0x420 + 0x080;
    uint256 internal constant TRANSCRIPT_CHALLENGE_SLOT = 0x200 + 0x160 + 0x420 + 0x0a0;

    /*//////////////////////////////////////////////////////////////
                             Challenges
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant CHALLENGE_TETA_0_SLOT = 0x200 + 0x160 + 0x420 + 0x0c0;
    uint256 internal constant CHALLENGE_TETA_1_SLOT = 0x200 + 0x160 + 0x420 + 0x0e0;
    uint256 internal constant CHALLENGE_TETA_2_SLOT = 0x200 + 0x160 + 0x420 + 0x100;
    uint256 internal constant CHALLENGE_KAPPA_0_SLOT = 0x200 + 0x160 + 0x420 + 0x120;
    uint256 internal constant CHALLENGE_KAPPA_1_SLOT = 0x200 + 0x160 + 0x420 + 0x140;
    uint256 internal constant CHALLENGE_ZETA_0_SLOT = 0x200 + 0x160 + 0x420 + 0x160;
    uint256 internal constant CHALLENGE_ZETA_1_SLOT = 0x200 + 0x160 + 0x420 + 0x180;

    /*//////////////////////////////////////////////////////////////
                       Intermediary verifier state
    //////////////////////////////////////////////////////////////*/



    /*//////////////////////////////////////////////////////////////
                             Pairing data
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant PAIRING_BUFFER1_POINT_X_SLOT = 0x200 + 0x160 + 0x420 + 0x1a0;
    uint256 internal constant PAIRING_BUFFER1_POINT_Y_SLOT = 0x200 + 0x160 + 0x420 + 0x1c0;

    uint256 internal constant PAIRING_BUFFER2_POINT_X_SLOT = 0x200 + 0x160 + 0x420 + 0x1e0;
    uint256 internal constant PAIRING_BUFFER2_POINT_Y_SLOT = 0x200 + 0x160 + 0x420 + 0x200;



    /*//////////////////////////////////////////////////////////////
                             Constants
    //////////////////////////////////////////////////////////////*/

    //uint256 internal constant COMMON_REFERENCE_STRING = 
    //uint256 internal constant PUBLIC_PARAMETER = 

    // Scalar field size
    // Q_MOD is the base field modulus (48 bytes long). To fit with the EVM, we sliced it into two 32bytes variables => 16 first bytes are zeros        
    uint256 internal constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 internal constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;
    // R_MOD is the main subgroup order 
    uint256 internal constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    /// @dev flip of 0xe000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant FR_MASK = 0x1fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /*//////////////////////////////////////////////////////////////
                             subcircuit library variables
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant SUBCIRCUIT_LIBRARY_X = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_Y = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_Z = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_ALPHA_X = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_ALPHA_Y = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_BETA_X0 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_BETA_X1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_BETA_Y0 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_BETA_Y1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_GAMMA_X0 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_GAMMA_X1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_GAMMA_Y0 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_GAMMA_Y1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_DELTA_X0 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_DELTA_X1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_DELTA_Y0 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_DELTA_Y1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_ETA0 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_ETA1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_MU = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_NU = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_PSI0 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_PSI1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_PSI2 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_PSI3 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant SUBCIRCUIT_LIBRARY_KAPPA = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant G2_MU_EXP_4_X1 = 0x110deb1e0863737f9a3d7b4de641a03aa00a77bc9f1a05acc9d55b76ab9fdd4d;
    uint256 internal constant G2_MU_EXP_4_X2 = 0x1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed;
    uint256 internal constant G2_MU_EXP_4_Y1 = 0x090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b;
    uint256 internal constant G2_MU_EXP_4_Y2 = 0x12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa;
    uint256 internal constant G2_MU_EXP_3_TIMES_NU_X1 = 0x260e01b251f6f1c7e7ff4e580791dee8ea51d87a358e038b4efe30fac09383c1;
    uint256 internal constant G2_MU_EXP_3_TIMES_NU_X2 = 0x0118c4d5b837bcc2bc89b5b398b5974e9f5944073b32078b7e231fec938883b0;
    uint256 internal constant G2_MU_EXP_3_TIMES_NU_Y1 = 0x04fc6369f7110fe3d25156c1bb9a72859cf2a04641f99ba4ee413c80da6a5fe4;
    uint256 internal constant G2_MU_EXP_3_TIMES_NU_Y2 = 0x22febda3c0c0632a56475b4214e5615e11e6dd3f96e6cea2854a87d4dacc5e55;
    uint256 internal constant G2_MU_EXP_4_TIMES_KAPPA_X1 = 0x260e01b251f6f1c7e7ff4e580791dee8ea51d87a358e038b4efe30fac09383c1;
    uint256 internal constant G2_MU_EXP_4_TIMES_KAPPA_X2 = 0x0118c4d5b837bcc2bc89b5b398b5974e9f5944073b32078b7e231fec938883b0;
    uint256 internal constant G2_MU_EXP_4_TIMES_KAPPA_Y1 = 0x04fc6369f7110fe3d25156c1bb9a72859cf2a04641f99ba4ee413c80da6a5fe4;
    uint256 internal constant G2_MU_EXP_4_TIMES_KAPPA_Y2 = 0x22febda3c0c0632a56475b4214e5615e11e6dd3f96e6cea2854a87d4dacc5e55;
    uint256 internal constant G2_MU_EXP_4_TIMES_KAPPA_SQUARE_X1 = 0x260e01b251f6f1c7e7ff4e580791dee8ea51d87a358e038b4efe30fac09383c1;
    uint256 internal constant G2_MU_EXP_4_TIMES_KAPPA_SQUARE_X2 = 0x0118c4d5b837bcc2bc89b5b398b5974e9f5944073b32078b7e231fec938883b0;
    uint256 internal constant G2_MU_EXP_4_TIMES_KAPPA_SQUARE_Y1 = 0x04fc6369f7110fe3d25156c1bb9a72859cf2a04641f99ba4ee413c80da6a5fe4;
    uint256 internal constant G2_MU_EXP_4_TIMES_KAPPA_SQUARE_Y2 = 0x22febda3c0c0632a56475b4214e5615e11e6dd3f96e6cea2854a87d4dacc5e55;

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

            function coordinatesSub(a, b) -> result_part1, result_part2 {  
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
                minus_y2_part1, minus_y2_part2 := coordinatesSub(mload(Q_MOD_PART1), mload(add(p2, 0x40)))

                let minus_y2_prime_part1
                let minus_y2_prime_part2
                minus_y2_prime_part1, minus_y2_prime_part2 := coordinatesSub(mload(Q_MOD_PART1), mload(add(p2, 0xc0)))
                
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
                                    1. Load Public inputs
            //////////////////////////////////////////////////////////////*/

            function loadPublicInputs() {
                let isValid
                // 1. Calculate proper offset (skip function selector)
                let offset := add(calldataload(0x04), 0x04) // 0x04 for function selector
                
                // Load permutation polynomials (0x00-0x9f in calldata)
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S0_X_SLOT_PART1, loadAndFormatUint128(add(offset, 0x20)))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S0_X_SLOT_PART2, calldataload(add(offset, 0x30)))
                
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S0_Y_SLOT_PART1, loadAndFormatUint128(add(offset, 0x40)))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S0_Y_SLOT_PART2, calldataload(add(offset, 0x50)))
                
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S1_X_SLOT_PART1, loadAndFormatUint128(add(offset, 0x60)))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S1_X_SLOT_PART2, calldataload(add(offset, 0x70)))
                
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S1_Y_SLOT_PART1, loadAndFormatUint128(add(offset, 0x80)))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S1_Y_SLOT_PART2, calldataload(add(offset, 0x90)))
                
                // Advance offset past polynomial parts (0xa0 bytes)
                offset := add(offset, 0xa0)
                
                // Load A_IN length and data
                let aInLength := calldataload(offset)
                mstore(PUBLIC_INPUT_A_IN_LENGTH_SLOT, aInLength)
                offset := add(offset, 0x20)
                
                // Calculate A_IN data start position (0x320)
                let aInDataPtr := PUBLIC_INPUT_A_IN_DATA_SLOT
                
                // Copy a_in elements
                for { let i := 0 } lt(i, aInLength) { i := add(i, 1) } {
                    mstore(add(aInDataPtr, mul(i, 0x20)), calldataload(offset))
                    offset := add(offset, 0x20)
                }
                
                // Calculate A_OUT position dynamically
                let aOutOffset := add(aInDataPtr, mul(aInLength, 0x20))
                let aOutLength := calldataload(offset)
                mstore(aOutOffset, aOutLength) // Store length at calculated position
                offset := add(offset, 0x20)
                
                // Store A_OUT elements starting after length
                for { let i := 0 } lt(i, aOutLength) { i := add(i, 1) } {
                    mstore(add(aOutOffset, mul(add(i, 1), 0x20)), calldataload(offset))
                    offset := add(offset, 0x20)
                }

                // Revert if proof is invalid
                if iszero(isValid) {
                    revertWithMessage(27, "loadProof: Proof is invalid")
                }
            }

            /*//////////////////////////////////////////////////////////////
                                    1. Load Proof
            //////////////////////////////////////////////////////////////*/

            function loadProof() {
                let isValid
                // 1. Calculate proper offset (skip function selector)
                let offset := add(calldataload(0x04), 0x04) // 0x04 for function selector
                
                // Load permutation polynomials (0x00-0x9f in calldata)
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S0_X_SLOT_PART1, loadAndFormatUint128(add(offset, 0x20)))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S0_X_SLOT_PART2, calldataload(add(offset, 0x30)))
                
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S0_Y_SLOT_PART1, loadAndFormatUint128(add(offset, 0x40)))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S0_Y_SLOT_PART2, calldataload(add(offset, 0x50)))
                
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S1_X_SLOT_PART1, loadAndFormatUint128(add(offset, 0x60)))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S1_X_SLOT_PART2, calldataload(add(offset, 0x70)))
                
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S1_Y_SLOT_PART1, loadAndFormatUint128(add(offset, 0x80)))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S1_Y_SLOT_PART2, calldataload(add(offset, 0x90)))
                
                // Advance offset past polynomial parts (0xa0 bytes)
                offset := add(offset, 0xa0)
                
                // Load A_IN length and data
                let aInLength := calldataload(offset)
                mstore(PUBLIC_INPUT_A_IN_LENGTH_SLOT, aInLength)
                offset := add(offset, 0x20)
                
                // Calculate A_IN data start position (0x320)
                let aInDataPtr := PUBLIC_INPUT_A_IN_DATA_SLOT
                
                // Copy a_in elements
                for { let i := 0 } lt(i, aInLength) { i := add(i, 1) } {
                    mstore(add(aInDataPtr, mul(i, 0x20)), calldataload(offset))
                    offset := add(offset, 0x20)
                }
                
                // Calculate A_OUT position dynamically
                let aOutOffset := add(aInDataPtr, mul(aInLength, 0x20))
                let aOutLength := calldataload(offset)
                mstore(aOutOffset, aOutLength) // Store length at calculated position
                offset := add(offset, 0x20)
                
                // Store A_OUT elements starting after length
                for { let i := 0 } lt(i, aOutLength) { i := add(i, 1) } {
                    mstore(add(aOutOffset, mul(add(i, 1), 0x20)), calldataload(offset))
                    offset := add(offset, 0x20)
                }

                // Revert if proof is invalid
                if iszero(isValid) {
                    revertWithMessage(27, "loadProof: Proof is invalid")
                }
            }


            /*//////////////////////////////////////////////////////////////
                                3. Transcript initialization
            //////////////////////////////////////////////////////////////*/

            /// @notice Recomputes all challenges
            /// @dev The process is the following:
            /// Commit:   [U], [V], [W], [A], [B], [C]
            /// Get:      teta1, teta2 & teta3

            function initializeTranscript() {
                updateTranscript(mload(PUBLIC_INPUT_A_IN_DATA_SLOT))
                updateTranscript(mload(PUBLIC_INPUT_A_OUT_DATA_SLOT))

            }




            // Step 1: Load the public inputs and check the correctness of its parts
            loadPublicInputs()

            // Step 2: Load the proof and check the correctness of its parts
            loadProof()

            // Step 3: Recompute all the challenges with the transcript
            initializeTranscript()


            // Step4: compute the copy constraint pairing
            

            result := 1
            mstore(0, true)
        }

    }
}