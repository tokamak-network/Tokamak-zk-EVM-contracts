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

    // Public input
    uint256 internal constant PROOF_PUBLIC_INPUTS_HASH = 0x200 + 0x020;

    /*//////////////////////////////////////////////////////////////
                                  Proof
    //////////////////////////////////////////////////////////////*/

    // U
    uint256 internal constant PROOF_POLY_U_X_SLOT_PART1 = 0x200 + 0x020 + 0x020;
    uint256 internal constant PROOF_POLY_U_X_SLOT_PART2 = 0x200 + 0x020 + 0x040;
    uint256 internal constant PROOF_POLY_U_Y_SLOT_PART1 = 0x200 + 0x020 + 0x060;
    uint256 internal constant PROOF_POLY_U_Y_SLOT_PART2 = 0x200 + 0x020 + 0x080;
    // V
    uint256 internal constant PROOF_POLY_V_X_SLOT_PART1 = 0x200 + 0x020 + 0x0a0;
    uint256 internal constant PROOF_POLY_V_X_SLOT_PART2 = 0x200 + 0x020 + 0x0c0;
    uint256 internal constant PROOF_POLY_V_Y_SLOT_PART1 = 0x200 + 0x020 + 0x0e0;
    uint256 internal constant PROOF_POLY_V_Y_SLOT_PART2 = 0x200 + 0x020 + 0x100;
    // W
    uint256 internal constant PROOF_POLY_W_X_SLOT_PART1 = 0x200 + 0x020 + 0x120;
    uint256 internal constant PROOF_POLY_W_X_SLOT_PART2 = 0x200 + 0x020 + 0x140;
    uint256 internal constant PROOF_POLY_W_Y_SLOT_PART1 = 0x200 + 0x020 + 0x160;
    uint256 internal constant PROOF_POLY_W_Y_SLOT_PART2 = 0x200 + 0x020 + 0x180;
    // O_mid
    uint256 internal constant PROOF_POLY_OMID_X_SLOT_PART1 = 0x200 + 0x020 + 0x1a0;
    uint256 internal constant PROOF_POLY_OMID_X_SLOT_PART2 = 0x200 + 0x020 + 0x1c0;
    uint256 internal constant PROOF_POLY_OMID_Y_SLOT_PART1 = 0x200 + 0x020 + 0x0e0;
    uint256 internal constant PROOF_POLY_OMID_Y_SLOT_PART2 = 0x200 + 0x020 + 0x200;
    // O_prv
    uint256 internal constant PROOF_POLY_OPRV_X_SLOT_PART1 = 0x200 + 0x020 + 0x220;
    uint256 internal constant PROOF_POLY_OPRV_X_SLOT_PART2 = 0x200 + 0x020 + 0x240;
    uint256 internal constant PROOF_POLY_OPRV_Y_SLOT_PART1 = 0x200 + 0x020 + 0x260;
    uint256 internal constant PROOF_POLY_OPRV_Y_SLOT_PART2 = 0x200 + 0x020 + 0x280;
    // O_X
    uint256 internal constant PROOF_POLY_QX_X_SLOT_PART1 = 0x200 + 0x020 + 0x2a0;
    uint256 internal constant PROOF_POLY_QX_X_SLOT_PART2 = 0x200 + 0x020 + 0x2c0;
    uint256 internal constant PROOF_POLY_QX_Y_SLOT_PART1 = 0x200 + 0x020 + 0x2e0;
    uint256 internal constant PROOF_POLY_QX_Y_SLOT_PART2 = 0x200 + 0x020 + 0x300;
    // O_Y
    uint256 internal constant PROOF_POLY_QY_X_SLOT_PART1 = 0x200 + 0x020 + 0x320;
    uint256 internal constant PROOF_POLY_QY_X_SLOT_PART2 = 0x200 + 0x020 + 0x340;
    uint256 internal constant PROOF_POLY_QY_Y_SLOT_PART1 = 0x200 + 0x020 + 0x360;
    uint256 internal constant PROOF_POLY_QY_Y_SLOT_PART2 = 0x200 + 0x020 + 0x380;
    // O_Z
    uint256 internal constant PROOF_POLY_QZ_X_SLOT_PART1 = 0x200 + 0x020 + 0x3a0;
    uint256 internal constant PROOF_POLY_QZ_X_SLOT_PART2 = 0x200 + 0x020 + 0x3c0;
    uint256 internal constant PROOF_POLY_QZ_Y_SLOT_PART1 = 0x200 + 0x020 + 0x3e0;
    uint256 internal constant PROOF_POLY_QZ_Y_SLOT_PART2 = 0x200 + 0x020 + 0x400;
    // Π_χ
    uint256 internal constant PROOF_POLY_PI_CHI_X_SLOT_PART1 = 0x200 + 0x020 + 0x420;
    uint256 internal constant PROOF_POLY_PI_CHI_X_SLOT_PART2 = 0x200 + 0x020 + 0x440;
    uint256 internal constant PROOF_POLY_PI_CHI_Y_SLOT_PART1 = 0x200 + 0x020 + 0x460;
    uint256 internal constant PROOF_POLY_PI_CHI_Y_SLOT_PART2 = 0x200 + 0x020 + 0x480;
    // Π_ζ
    uint256 internal constant PROOF_POLY_PI_ZETA_X_SLOT_PART1 = 0x200 + 0x020 + 0x4a0;
    uint256 internal constant PROOF_POLY_PI_ZETA_X_SLOT_PART2 = 0x200 + 0x020 + 0x4c0;
    uint256 internal constant PROOF_POLY_PI_ZETA_Y_SLOT_PART1 = 0x200 + 0x020 + 0x4e0;
    uint256 internal constant PROOF_POLY_PI_ZETA_Y_SLOT_PART2 = 0x200 + 0x020 + 0x500;
    // Π_ξ
    uint256 internal constant PROOF_POLY_PI_XI_X_SLOT_PART1 = 0x200 + 0x020 + 0x520;
    uint256 internal constant PROOF_POLY_PI_XI_X_SLOT_PART2 = 0x200 + 0x020 + 0x540;
    uint256 internal constant PROOF_POLY_PI_XI_Y_SLOT_PART1 = 0x200 + 0x020 + 0x560;
    uint256 internal constant PROOF_POLY_PI_XI_Y_SLOT_PART2 = 0x200 + 0x020 + 0x580;
    // B
    uint256 internal constant PROOF_POLY_B_X_SLOT_PART1 = 0x200 + 0x020 + 0x5a0;
    uint256 internal constant PROOF_POLY_B_X_SLOT_PART2 = 0x200 + 0x020 + 0x5c0;
    uint256 internal constant PROOF_POLY_B_Y_SLOT_PART1 = 0x200 + 0x020 + 0x5e0;
    uint256 internal constant PROOF_POLY_B_Y_SLOT_PART2 = 0x200 + 0x020 + 0x600;
    // R
    uint256 internal constant PROOF_POLY_R_X_SLOT_PART1 = 0x200 + 0x020 + 0x620;
    uint256 internal constant PROOF_POLY_R_X_SLOT_PART2 = 0x200 + 0x020 + 0x640;
    uint256 internal constant PROOF_POLY_R_Y_SLOT_PART1 = 0x200 + 0x020 + 0x660;
    uint256 internal constant PROOF_POLY_R_Y_SLOT_PART2 = 0x200 + 0x020 + 0x680;
    // M_ζ
    uint256 internal constant PROOF_POLY_M_ZETA_X_SLOT_PART1 = 0x200 + 0x020 + 0x6a0;
    uint256 internal constant PROOF_POLY_M_ZETA_X_SLOT_PART2 = 0x200 + 0x020 + 0x6c0;
    uint256 internal constant PROOF_POLY_M_ZETA_Y_SLOT_PART1 = 0x200 + 0x020 + 0x6e0;
    uint256 internal constant PROOF_POLY_M_ZETA_Y_SLOT_PART2 = 0x200 + 0x020 + 0x700;
    // M_ω_Z^-1ξ
    uint256 internal constant PROOF_POLY_M_OMEGAZ_XI_X_SLOT_PART1 = 0x200 + 0x020 + 0x720;
    uint256 internal constant PROOF_POLY_M_OMEGAZ_XI_X_SLOT_PART2 = 0x200 + 0x020 + 0x740;
    uint256 internal constant PROOF_POLY_M_OMEGAZ_XI_Y_SLOT_PART1 = 0x200 + 0x020 + 0x760;
    uint256 internal constant PROOF_POLY_M_OMEGAZ_XI_Y_SLOT_PART2 = 0x200 + 0x020 + 0x780;
    // N_ω_Y^-1ζ
    uint256 internal constant PROOF_POLY_N_OMEGAY_ZETA_X_SLOT_PART1 = 0x200 + 0x020 + 0x7a0;
    uint256 internal constant PROOF_POLY_N_OMEGAY_ZETA_X_SLOT_PART2 = 0x200 + 0x020 + 0x7c0;
    uint256 internal constant PROOF_POLY_N_OMEGAY_ZETA_Y_SLOT_PART1 = 0x200 + 0x020 + 0x7e0;
    uint256 internal constant PROOF_POLY_N_OMEGAY_ZETA_Y_SLOT_PART2 = 0x200 + 0x020 + 0x800;
    // N_ω_Z^-1ξ
    uint256 internal constant PROOF_POLY_N_OMEGAZ_XI_X_SLOT_PART1 = 0x200 + 0x020 + 0x820;
    uint256 internal constant PROOF_POLY_N_OMEGAZ_XI_X_SLOT_PART2 = 0x200 + 0x020 + 0x840;
    uint256 internal constant PROOF_POLY_N_OMEGAZ_XI_Y_SLOT_PART1 = 0x200 + 0x020 + 0x860;
    uint256 internal constant PROOF_POLY_N_OMEGAZ_XI_Y_SLOT_PART2 = 0x200 + 0x020 + 0x880;
    // R_xy
    uint256 internal constant PROOF_R1XY_SLOT = 0x200 + 0x020 + 0x8a0;
    // R'_xy
    uint256 internal constant PROOF_R2XY_SLOT = 0x200 + 0x020 + 0x8c0;
    // R''_xy
    uint256 internal constant PROOF_R3XY_SLOT = 0x200 + 0x020 + 0x8e0;
    // V_xy
    uint256 internal constant PROOF_VXY = 0x200 + 0x020 + 0x900;



    /*//////////////////////////////////////////////////////////////
            transcript slot (used for challenge computation)
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant TRANSCRIPT_BEGIN_SLOT = 0x200 + 0x020 + 0x900 + 0x020;
    uint256 internal constant TRANSCRIPT_DST_BYTE_SLOT = 0x200 + 0x020 + 0x900 + 0x040; 
    uint256 internal constant TRANSCRIPT_STATE_0_SLOT = 0x200 + 0x020 + 0x900 + 0x060;
    uint256 internal constant TRANSCRIPT_STATE_1_SLOT = 0x200 + 0x020 + 0x900 + 0x080;
    uint256 internal constant TRANSCRIPT_CHALLENGE_SLOT = 0x200 + 0x020 + 0x900 + 0x0a0;

    /*//////////////////////////////////////////////////////////////
                             Challenges
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant CHALLENGE_THETA_0_SLOT = 0x200 + 0x020 + 0x900 + 0x0c0;
    uint256 internal constant CHALLENGE_THETA_1_SLOT = 0x200 + 0x020 + 0x900 + 0x0e0;
    uint256 internal constant CHALLENGE_THETA_2_SLOT = 0x200 + 0x020 + 0x900 + 0x100;
    uint256 internal constant CHALLENGE_KAPPA_0_SLOT = 0x200 + 0x020 + 0x900 + 0x120;
    uint256 internal constant CHALLENGE_KAPPA_1_SLOT = 0x200 + 0x020 + 0x900 + 0x140;
    uint256 internal constant CHALLENGE_KAPPA_2_SLOT = 0x200 + 0x020 + 0x900 + 0x140;
    uint256 internal constant CHALLENGE_ZETA_SLOT = 0x200 + 0x020 + 0x900 + 0x160;
    uint256 internal constant CHALLENGE_XI_SLOT = 0x200 + 0x020 + 0x900 + 0x180;
    uint256 internal constant CHALLENGE_CHI_SLOT = 0x200 + 0x020 + 0x900 + 0x180;

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
                                    1. Load Proof
            //////////////////////////////////////////////////////////////*/

            function loadProof() {
                // 1. Load public input
                let offset := calldataload(0x04)
                let publicInputLengthInWords := calldataload(add(offset, 0x04))
                let isValid := eq(publicInputLengthInWords, 1) // We expect only one public input
                mstore(PROOF_PUBLIC_INPUTS_HASH, and(calldataload(add(offset, 0x24)), FR_MASK))

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
                // PROOF_POLY_QX
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x204))
                    let x2 := calldataload(add(offset, 0x214))
                    let y1 := loadAndFormatUint128(add(offset, 0x234))
                    let y2 := calldataload(add(offset, 0x244))
                    mstore(PROOF_POLY_QX_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_QX_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_QX_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_QX_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_QY
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x264))
                    let x2 := calldataload(add(offset, 0x274))
                    let y1 := loadAndFormatUint128(add(offset, 0x294))
                    let y2 := calldataload(add(offset, 0x2a4))
                    mstore(PROOF_POLY_QY_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_QY_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_QY_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_QY_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_QZ
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x2c4))
                    let x2 := calldataload(add(offset, 0x2d4))
                    let y1 := loadAndFormatUint128(add(offset, 0x2f4))
                    let y2 := calldataload(add(offset, 0x304))
                    mstore(PROOF_POLY_QZ_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_QZ_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_QZ_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_QZ_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_CHI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x324))
                    let x2 := calldataload(add(offset, 0x334))
                    let y1 := loadAndFormatUint128(add(offset, 0x354))
                    let y2 := calldataload(add(offset, 0x364))
                    mstore(PROOF_POLY_PI_CHI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_CHI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_CHI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_CHI_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_ZETA
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x384))
                    let x2 := calldataload(add(offset, 0x394))
                    let y1 := loadAndFormatUint128(add(offset, 0x3b4))
                    let y2 := calldataload(add(offset, 0x3c4))
                    mstore(PROOF_POLY_PI_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_ZETA_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_ZETA_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_PI_XI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x3e4))
                    let x2 := calldataload(add(offset, 0x3f4))
                    let y1 := loadAndFormatUint128(add(offset, 0x414))
                    let y2 := calldataload(add(offset, 0x424))
                    mstore(PROOF_POLY_PI_XI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_PI_XI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_PI_XI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_PI_XI_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_B
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x444))
                    let x2 := calldataload(add(offset, 0x454))
                    let y1 := loadAndFormatUint128(add(offset, 0x474))
                    let y2 := calldataload(add(offset, 0x484))
                    mstore(PROOF_POLY_B_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_B_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_B_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_B_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_R
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x4a4))
                    let x2 := calldataload(add(offset, 0x4b4))
                    let y1 := loadAndFormatUint128(add(offset, 0x4d4))
                    let y2 := calldataload(add(offset, 0x4e4))
                    mstore(PROOF_POLY_R_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_R_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_R_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_R_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_M_ZETA
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x504))
                    let x2 := calldataload(add(offset, 0x514))
                    let y1 := loadAndFormatUint128(add(offset, 0x534))
                    let y2 := calldataload(add(offset, 0x544))
                    mstore(PROOF_POLY_M_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_M_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_M_ZETA_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_M_ZETA_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_M_OMEGAZ_XI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x564))
                    let x2 := calldataload(add(offset, 0x574))
                    let y1 := loadAndFormatUint128(add(offset, 0x594))
                    let y2 := calldataload(add(offset, 0x5a4))
                    mstore(PROOF_POLY_M_OMEGAZ_XI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_M_OMEGAZ_XI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_M_OMEGAZ_XI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_M_OMEGAZ_XI_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_N_OMEGAY_ZETA
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x5c4))
                    let x2 := calldataload(add(offset, 0x5d4))
                    let y1 := loadAndFormatUint128(add(offset, 0x5f4))
                    let y2 := calldataload(add(offset, 0x604))
                    mstore(PROOF_POLY_N_OMEGAY_ZETA_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_N_OMEGAY_ZETA_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_N_OMEGAY_ZETA_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_N_OMEGAY_ZETA_Y_SLOT_PART2, y2)
                }
                // PROOF_POLY_N_OMEGAZ_XI
                {
                    let x1 := loadAndFormatUint128(add(offset, 0x624))
                    let x2 := calldataload(add(offset, 0x634))
                    let y1 := loadAndFormatUint128(add(offset, 0x654))
                    let y2 := calldataload(add(offset, 0x664))
                    mstore(PROOF_POLY_N_OMEGAZ_XI_X_SLOT_PART1, x1)
                    mstore(PROOF_POLY_N_OMEGAZ_XI_X_SLOT_PART2, x2)
                    mstore(PROOF_POLY_N_OMEGAZ_XI_Y_SLOT_PART1, y1)
                    mstore(PROOF_POLY_N_OMEGAZ_XI_Y_SLOT_PART2, y2)
                }

                mstore(PROOF_R1XY_SLOT, mod(calldataload(add(offset, 0x684)), R_MOD))
                mstore(PROOF_R2XY_SLOT, mod(calldataload(add(offset, 0x6a4)), R_MOD))
                mstore(PROOF_R3XY_SLOT, mod(calldataload(add(offset, 0x6c4)), R_MOD))
                mstore(PROOF_VXY, mod(calldataload(add(offset, 0x6e4)), R_MOD))
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
                updateTranscript(mload(PROOF_PUBLIC_INPUTS_HASH))
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
                updateTranscript(mload(PROOF_POLY_QX_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QX_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QX_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QX_Y_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QY_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QY_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QY_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QY_Y_SLOT_PART2))

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

                // Round 4
                updateTranscript(mload(PROOF_POLY_QZ_X_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QZ_X_SLOT_PART2))
                updateTranscript(mload(PROOF_POLY_QZ_Y_SLOT_PART1))
                updateTranscript(mload(PROOF_POLY_QZ_Y_SLOT_PART2))

                mstore(CHALLENGE_XI_SLOT, getTranscriptChallenge(8))              

            }



            // Step 1: Load the PI/proof a
            loadProof()

            // Step 2: Recompute all the challenges with the transcript
            initializeTranscript()


            // Step4: compute the copy constraint pairing
            

            result := 1
            mstore(0, true)
        }

    }
}