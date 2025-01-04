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
    uint256 internal constant PROOF_OPENING_EVAL_V_X0_SLOT = 0x200 + 0x1c0;
    uint256 internal constant PROOF_OPENING_EVAL_V_X1_SLOT = 0x200 + 0x1e0;
    uint256 internal constant PROOF_OPENING_EVAL_V_Y0_SLOT = 0x200 + 0x200;
    uint256 internal constant PROOF_OPENING_EVAL_V_Y1_SLOT = 0x200 + 0x220;
    uint256 internal constant PROOF_OPENING_EVAL_W_X_SLOT = 0x200 + 0x240;
    uint256 internal constant PROOF_OPENING_EVAL_W_Y_SLOT = 0x200 + 0x260;
    // selector polynomials
    uint256 internal constant PROOF_OPENING_EVAL_A_X_SLOT = 0x200 + 0x280;
    uint256 internal constant PROOF_OPENING_EVAL_A_Y_SLOT = 0x200 + 0x2a0;
    uint256 internal constant PROOF_OPENING_EVAL_B_X_SLOT = 0x200 + 0x2c0;
    uint256 internal constant PROOF_OPENING_EVAL_B_Y_SLOT = 0x200 + 0x2e0;
    uint256 internal constant PROOF_OPENING_EVAL_C_X_SLOT = 0x200 + 0x300;
    uint256 internal constant PROOF_OPENING_EVAL_C_Y_SLOT = 0x200 + 0x320;
    // recursion polynomial
    uint256 internal constant PROOF_RECURSION_POLY_X_SLOT = 0x200 + 0x340;
    uint256 internal constant PROOF_RECURSION_POLY_Y_SLOT = 0x200 + 0x360;
    // quotient polynomial
    uint256 internal constant PROOF_CONSTRAINT_POLY_X_SLOT = 0x200 + 0x380;
    uint256 internal constant PROOF_CONSTRAINT_POLY_Y_SLOT = 0x200 + 0x3a0;
    // points evaluations
    uint256 internal constant PROOF_R1YZ_SLOT = 0x200 + 0x3c0;
    uint256 internal constant PROOF_R2YZ_SLOT = 0x200 + 0x3e0;
    uint256 internal constant PROOF_BYZ_SLOT = 0x200 + 0x400;
    // last transcript components
    uint256 internal constant PROOF_PI0_X_SLOT = 0x200 + 0x420;
    uint256 internal constant PROOF_PI0_Y_SLOT = 0x200 + 0x440;
    uint256 internal constant PROOF_PI1_X_SLOT = 0x200 + 0x460;
    uint256 internal constant PROOF_PI1_Y_SLOT = 0x200 + 0x480;
    uint256 internal constant PROOF_PI2_X_SLOT = 0x200 + 0x4a0;
    uint256 internal constant PROOF_PI2_Y_SLOT = 0x200 + 0x4c0;
    uint256 internal constant PROOF_PI3_X_SLOT = 0x200 + 0x4e0;
    uint256 internal constant PROOF_PI3_Y_SLOT = 0x200 + 0x500;

    /*//////////////////////////////////////////////////////////////
                 transcript slot (used for challenge computation)
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant TRANSCRIPT_BEGIN_SLOT = 0x200 + 0x520;
    uint256 internal constant TRANSCRIPT_DST_BYTE_SLOT = 0x200 + 0x540;
    uint256 internal constant TRANSCRIPT_STATE_0_SLOT = 0x200 + 0x560;
    uint256 internal constant TRANSCRIPT_STATE_1_SLOT = 0x200 + 0x580;
    uint256 internal constant TRANSCRIPT_CHALLENGE_SLOT = 0x200 + 0x5a0;

    /*//////////////////////////////////////////////////////////////
                             Challenges
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant CHALLENGE_TETA_0_SLOT = 0x200 + 0x5c0;
    uint256 internal constant CHALLENGE_TETA_1_SLOT = 0x200 + 0x5e0;
    uint256 internal constant CHALLENGE_TETA_2_SLOT = 0x200 + 0x600;
    uint256 internal constant CHALLENGE_KAPPA_0_SLOT = 0x200 + 0x620;
    uint256 internal constant CHALLENGE_KAPPA_1_SLOT = 0x200 + 0x640;
    uint256 internal constant CHALLENGE_ZETA_0_SLOT = 0x200 + 0x660;
    uint256 internal constant CHALLENGE_ZETA_1_SLOT = 0x200 + 0x680;

    /*//////////////////////////////////////////////////////////////
                             Partial verifier state
    //////////////////////////////////////////////////////////////*/

    // OPEN_1
    

    // OPEN_2
    

    // OPEN_3
    



    /*//////////////////////////////////////////////////////////////
                             Pairing data
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                             Constants
    //////////////////////////////////////////////////////////////*/

    //uint256 internal constant COMMON_REFERENCE_STRING = 
    //uint256 internal constant PUBLIC_PARAMETER = 
    //uint256 internal constant SUBCIRCUIT_LABRARY = 

    // Scalar field size
    uint256 internal constant Q_MOD = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint256 internal constant R_MOD = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @dev flip of 0xe000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant FR_MASK = 0x1fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function verify(
        uint256[] calldata, // _publicInputs
        uint256[] calldata // _proof
    ) public view virtual returns (bool result, uint256 teta1, uint256 teta2, uint256 teta3) {
        
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
                // 1. Load public inputs
                let offset := calldataload(0x04)
                let publicInputLengthInWords := calldataload(add(offset, 0x04)) // we add 0x04 to skip the function selector
                let isValid := eq(publicInputLengthInWords, 12) // (We expect 12 public inputs) 

                // Load each public input into its respective slot
                mstore(PUBLIC_INPUT_PREPROCESSED_COM_S0_X_SLOT, and(calldataload(add(offset, 0x24)), FR_MASK))
                mstore(PUBLIC_INPUT_PREPROCESSED_COM_S0_Y_SLOT, and(calldataload(add(offset, 0x44)), FR_MASK))
                mstore(PUBLIC_INPUT_PREPROCESSED_COM_S1_X_SLOT, and(calldataload(add(offset, 0x64)), FR_MASK))
                mstore(PUBLIC_INPUT_PREPROCESSED_COM_S1_Y_SLOT, and(calldataload(add(offset, 0x84)), FR_MASK))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S2_X_SLOT, and(calldataload(add(offset, 0xa4)), FR_MASK))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S2_Y_SLOT, and(calldataload(add(offset, 0xc4)), FR_MASK))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S2_Z_SLOT, and(calldataload(add(offset, 0xe4)), FR_MASK))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S3_X_SLOT, and(calldataload(add(offset, 0x104)), FR_MASK))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S3_Y_SLOT, and(calldataload(add(offset, 0x124)), FR_MASK))
                mstore(PUBLIC_INPUT_PERMUTATION_POLY_S3_Z_SLOT, and(calldataload(add(offset, 0x144)), FR_MASK))
                mstore(PUBLIC_INPUT_A_IN_SLOT, and(calldataload(add(offset, 0x164)), FR_MASK))
                mstore(PUBLIC_INPUT_A_OUT_SLOT, and(calldataload(add(offset, 0x184)), FR_MASK))

                // 2. Load the proof 
                offset := calldataload(0x24)
                let proofLengthInWords := calldataload(add(offset, 0x04))
                isValid := and(eq(proofLengthInWords, 29), isValid)

                // PROOF_OPENING_EVAL_U
                {
                    let x := mod(calldataload(add(offset, 0x24)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x44)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid) // we verify the point belongs to the BN128 curve
                    mstore(PROOF_OPENING_EVAL_U_X_SLOT, x)
                    mstore(PROOF_OPENING_EVAL_U_Y_SLOT, y)
                }
                // PROOF_OPENING_EVAL_V
                {
                    // Load x0, x1, y0, y1 from calldata
                    let x0 := mod(calldataload(add(offset, 0x64)), Q_MOD)
                    let x1 := mod(calldataload(add(offset, 0x84)), Q_MOD)
                    let y0 := mod(calldataload(add(offset, 0xa4)), Q_MOD)
                    let y1 := mod(calldataload(add(offset, 0xc4)), Q_MOD)

                    // Store the coordinates
                    mstore(PROOF_OPENING_EVAL_V_X0_SLOT, x0)
                    mstore(PROOF_OPENING_EVAL_V_X1_SLOT, x1)
                    mstore(PROOF_OPENING_EVAL_V_Y0_SLOT, y0)
                    mstore(PROOF_OPENING_EVAL_V_Y1_SLOT, y1)
                }
                // PROOF_OPENING_EVAL_W
                {
                    let x := mod(calldataload(add(offset, 0xe4)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x104)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_OPENING_EVAL_W_X_SLOT, x)
                    mstore(PROOF_OPENING_EVAL_W_Y_SLOT, y)
                }

                // PROOF_OPENING_EVAL_A
                {
                    let x := mod(calldataload(add(offset, 0x124)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x144)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_OPENING_EVAL_W_X_SLOT, x)
                    mstore(PROOF_OPENING_EVAL_W_Y_SLOT, y)
                }

                // PROOF_OPENING_EVAL_B
                {
                    let x := mod(calldataload(add(offset, 0x164)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x184)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_OPENING_EVAL_W_X_SLOT, x)
                    mstore(PROOF_OPENING_EVAL_W_Y_SLOT, y)
                }

                // PROOF_OPENING_EVAL_C
                {
                    let x := mod(calldataload(add(offset, 0x1a4)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x1c4)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_OPENING_EVAL_W_X_SLOT, x)
                    mstore(PROOF_OPENING_EVAL_W_Y_SLOT, y)
                }

                // PROOF_RECURSION_POLY
                {
                    let x := mod(calldataload(add(offset, 0x1e4)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x204)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_RECURSION_POLY_X_SLOT, x)
                    mstore(PROOF_RECURSION_POLY_Y_SLOT, y)
                }

                // PROOF_CONSTRAINT_POLY
                {
                    let x := mod(calldataload(add(offset, 0x224)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x244)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_CONSTRAINT_POLY_X_SLOT, x)
                    mstore(PROOF_CONSTRAINT_POLY_X_SLOT, y)
                }

                mstore(PROOF_R1YZ_SLOT, mod(calldataload(add(offset, 0x264)), R_MOD))
                mstore(PROOF_R2YZ_SLOT, mod(calldataload(add(offset, 0x284)), R_MOD))
                mstore(PROOF_BYZ_SLOT, mod(calldataload(add(offset, 0x2a4)), R_MOD))

                // PROOF_PI0
                {
                    let x := mod(calldataload(add(offset, 0x2c4)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x2e4)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_PI0_X_SLOT, x)
                    mstore(PROOF_PI0_Y_SLOT, y)
                }

                // PROOF_PI1
                {
                    let x := mod(calldataload(add(offset, 0x304)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x324)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_PI1_X_SLOT, x)
                    mstore(PROOF_PI1_Y_SLOT, y)
                }

                // PROOF_PI2
                {
                    let x := mod(calldataload(add(offset, 0x344)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x364)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_PI2_X_SLOT, x)
                    mstore(PROOF_PI2_Y_SLOT, y)
                }

                // PROOF_PI3
                {
                    let x := mod(calldataload(add(offset, 0x384)), Q_MOD)
                    let y := mod(calldataload(add(offset, 0x3a4)), Q_MOD)
                    let xx := mulmod(x, x, Q_MOD)
                    isValid := and(eq(mulmod(y, y, Q_MOD), addmod(mulmod(x, xx, Q_MOD), 3, Q_MOD)), isValid)
                    mstore(PROOF_PI3_X_SLOT, x)
                    mstore(PROOF_PI3_Y_SLOT, y)
                }

                // Revert if a proof/public input is not valid
                if iszero(isValid) {
                    revertWithMessage(27, "loadProof: Proof is invalid")
                }

            }

            /*//////////////////////////////////////////////////////////////
                                    2. Transcript initialization
            //////////////////////////////////////////////////////////////*/

            /// @notice Recomputes all challenges
            /// @dev The process is the following:
            /// Commit:   [U], [V], [W], [A], [B], [C]
            /// Get:      teta1, teta2 & teta3
            function initializeTranscript() {
                updateTranscript(mload(PROOF_OPENING_EVAL_U_X_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_U_Y_SLOT))

                mstore(CHALLENGE_TETA_0_SLOT, getTranscriptChallenge(0))

                updateTranscript(mload(PROOF_OPENING_EVAL_V_X0_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_V_X1_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_V_Y0_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_V_Y1_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_W_X_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_W_Y_SLOT))

                mstore(CHALLENGE_TETA_1_SLOT, getTranscriptChallenge(1))

                updateTranscript(mload(PROOF_OPENING_EVAL_A_X_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_A_Y_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_B_X_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_B_Y_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_C_X_SLOT))
                updateTranscript(mload(PROOF_OPENING_EVAL_C_Y_SLOT))

                mstore(CHALLENGE_TETA_2_SLOT, getTranscriptChallenge(2))

            }

            /*//////////////////////////////////////////////////////////////
                            4. Computing the recursion polynomial R
            //////////////////////////////////////////////////////////////*/

            function computeRecursionPolynomial() {
                
            }

            /*//////////////////////////////////////////////////////////////
                            5. copy constraint pairing
            //////////////////////////////////////////////////////////////*/


            /*//////////////////////////////////////////////////////////////
                            6. Arithmetic constraint pairing
            //////////////////////////////////////////////////////////////*/


            


            /*//////////////////////////////////////////////////////////////
                                    Verification
            //////////////////////////////////////////////////////////////*/

            // Step 1: Load the proof and check the correctness of its parts
            loadProof()

            // Step 2: Recompute all the challenges with the transcript
            initializeTranscript()

            teta1 := mload(CHALLENGE_TETA_0_SLOT)
            teta2 := mload(CHALLENGE_TETA_1_SLOT)
            teta3 := mload(CHALLENGE_TETA_2_SLOT)
            result := 1
            mstore(0, true)
        }

    }
}