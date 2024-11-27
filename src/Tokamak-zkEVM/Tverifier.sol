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
                                  Public Inputs
    //////////////////////////////////////////////////////////////*/

    // preprocessed commitments
    uint256 internal constant PUBLIC_INPUT_PREPROCESSED_COM_S0_X_SLOT = 0x200 + 0x000;
    uint256 internal constant PUBLIC_INPUT_PREPROCESSED_COM_S0_Y_SLOT = 0x200 + 0x020;
    uint256 internal constant PUBLIC_INPUT_PREPROCESSED_COM_S1_X_SLOT = 0x200 + 0x040;
    uint256 internal constant PUBLIC_INPUT_PREPROCESSED_COM_S1_Y_SLOT = 0x200 + 0x060;

    // permutation polynomials
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S2_X_SLOT = 0x200 + 0x080;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S2_Y_SLOT = 0x200 + 0x0a0;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S2_Z_SLOT = 0x200 + 0x0c0;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S3_X_SLOT = 0x200 + 0x0e0;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S3_Y_SLOT = 0x200 + 0x100;
    uint256 internal constant PUBLIC_INPUT_PERMUTATION_POLY_S3_Z_SLOT = 0x200 + 0x120;
    uint256 internal constant PUBLIC_INPUT_A_IN_SLOT = 0x200 + 0x140;
    uint256 internal constant PUBLIC_INPUT_A_OUT_SLOT = 0x200 + 0x160;

    /*//////////////////////////////////////////////////////////////
                                  Proof
    //////////////////////////////////////////////////////////////*/

    // OPEN_0
    uint256 internal constant PROOF_OPENING_EVAL_U_X_SLOT = 0x200 + 0x180;
    uint256 internal constant PROOF_OPENING_EVAL_U_Y_SLOT = 0x200 + 0x1a0;
    uint256 internal constant PROOF_OPENING_EVAL_V_X_SLOT = 0x200 + 0x1c0;
    uint256 internal constant PROOF_OPENING_EVAL_V_Y_SLOT = 0x200 + 0x1e0;
    uint256 internal constant PROOF_OPENING_EVAL_W_X_SLOT = 0x200 + 0x200;
    uint256 internal constant PROOF_OPENING_EVAL_W_Y_SLOT = 0x200 + 0x220;
    // selector polynomials
    uint256 internal constant PROOF_OPENING_EVAL_A_X_SLOT = 0x200 + 0x240;
    uint256 internal constant PROOF_OPENING_EVAL_A_Y_SLOT = 0x200 + 0x260;
    uint256 internal constant PROOF_OPENING_EVAL_B_X_SLOT = 0x200 + 0x280;
    uint256 internal constant PROOF_OPENING_EVAL_B_Y_SLOT = 0x200 + 0x2a0;
    uint256 internal constant PROOF_OPENING_EVAL_C_X_SLOT = 0x200 + 0x2c0;
    uint256 internal constant PROOF_OPENING_EVAL_C_Y_SLOT = 0x200 + 0x2e0;


    /*//////////////////////////////////////////////////////////////
                             Transcript slot
    //////////////////////////////////////////////////////////////*/
    
    // OPEN_1
    uint256 internal constant TRANSCRIPT_R_POLY_X_SLOT = 0x200 + 0x300;
    uint256 internal constant TRANSCRIPT_R_POLY_Y_SLOT = 0x200 + 0x320;

    // OPEN_2
    uint256 internal constant TRANSCRIPT_Q_POLY_X_SLOT = 0x200 + 0x340;
    uint256 internal constant TRANSCRIPT_Q_POLY_Y_SLOT = 0x200 + 0x360;

    // OPEN_3
    uint256 internal constant TRANSCRIPT_R1YZ_SLOT = 0x200 + 0x380;
    uint256 internal constant TRANSCRIPT_R2YZ_SLOT = 0x200 + 0x3a0;
    uint256 internal constant TRANSCRIPT_BYZ_SLOT = 0x200 + 0x3c0;

    /*//////////////////////////////////////////////////////////////
                             Partial verifier state
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                             Challenges
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant CHALLENGE_TETA_0_SLOT = 0x200 + 0x3e0;
    uint256 internal constant CHALLENGE_TETA_1_SLOT = 0x200 + 0x400;
    uint256 internal constant CHALLENGE_TETA_2_SLOT = 0x200 + 0x420;
    uint256 internal constant CHALLENGE_KAPPA_0_SLOT = 0x200 + 0x440;
    uint256 internal constant CHALLENGE_KAPPA_1_SLOT = 0x200 + 0x460;
    uint256 internal constant CHALLENGE_ZETA_0_SLOT = 0x200 + 0x480;
    uint256 internal constant CHALLENGE_ZETA_1_SLOT = 0x200 + 0x4a0;


    /*//////////////////////////////////////////////////////////////
                             Pairing data
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                             Constants
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant COMMON_REFERENCE_STRING = 
    uint256 internal constant PUBLIC_PARAMETER = 
    uint256 internal constant SUBCIRCUIT_LABRARY = 

    // Scalar field size
    uint256 internal constant Q_MOD = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    /// @dev flip of 0xe000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant FR_MASK = 0x1fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;


    function verify(
        uint256[] calldata, // _publicInputs
        uint256[] calldata, // _proof
    ) public view virtual returns (bool) {

        assembly {
            /*//////////////////////////////////////////////////////////////
                                        1. Load Proof
            //////////////////////////////////////////////////////////////*/
            function loadProof() {
                // 1. Load public input
                let offset := calldataload(0x04)
                let publicInputLengthInWords := calldataload(add(offset, 0x04)) // we add 0x04 to skip the function selector
                let isValid := eq(publicInputLengthInWords, 1) // We expect only one public input
                mstore(PROOF_PUBLIC_INPUT, and(calldataload(add(offset, 0x24)), FR_MASK))

                // 2. Load the proof 
                offset := calldataload(0x24)
                let proofLengthInWords := calldataload(add(offset, 0x04))
                isValid := and(eq(proofLengthInWords, 44), isValid)

                // PROOF_OPENING_EVAL_U
                {
                    let x := mod(calldataload(add(offset, 0x024)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x044)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid) // we verify the point belongs to the BN128 curve
                    mstore(PROOF_OPENING_EVAL_U_X_SLOT, x)
                    mstore(PROOF_OPENING_EVAL_U_Y_SLOT, y)
                }
                // PROOF_OPENING_EVAL_V
                {
                    let x := mod(calldataload(add(offset, 0x064)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x084)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    //isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid) // V belongs to a twisted curve (TODO) 
                    mstore(PROOF_OPENING_EVAL_V_X_SLOT, x)
                    mstore(PROOF_OPENING_EVAL_V_Y_SLOT, y)
                }
                // PROOF_OPENING_EVAL_W
                {
                    let x := mod(calldataload(add(offset, 0x0a4)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x0c4)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_OPENING_EVAL_W_X_SLOT, x)
                    mstore(PROOF_OPENING_EVAL_W_Y_SLOT, y)
                }
                
            }
        }


    }
}