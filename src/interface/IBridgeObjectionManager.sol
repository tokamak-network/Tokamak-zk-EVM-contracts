// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title IBridgeObjectionManager
 * @notice Interface for managing pending proofs, objections, and state confirmations
 * @dev Part of the Q2 2026 upgrade implementing the objection/slash/reward architecture
 */
interface IBridgeObjectionManager {
    // ========== ENUMS ==========

    enum PendingProofStatus {
        None,           // 0 - Proof doesn't exist
        Pending,        // 1 - Awaiting challenge period
        Challenged,     // 2 - Objection raised
        Confirmed,      // 3 - Challenge period passed, confirmed
        Rejected        // 4 - Objection upheld, proof invalid
    }

    enum ObjectionStatus {
        None,           // 0 - Objection doesn't exist
        Active,         // 1 - Awaiting resolution
        Dismissed,      // 2 - Proof was valid, objector slashed
        Upheld          // 3 - Proof was invalid, submitter slashed
    }

    // ========== STRUCTS ==========

    struct PendingProof {
        bytes32 channelId;            // Channel this proof belongs to
        bytes32 proofHash;            // Hash of proof data for front-running protection
        bytes32 previousStateRoot;    // State root before this proof
        bytes32 newStateRoot;         // State root after this proof
        address submitter;            // Address that submitted the proof
        uint256 submittedAt;          // Submission timestamp
        uint256 challengeDeadline;    // Deadline for raising objections
        PendingProofStatus status;    // Current status
        uint256 proofIndex;           // Index in the channel's proof queue
    }

    struct Objection {
        bytes32 channelId;            // Channel of objection
        uint256 proofIndex;           // Index of challenged proof
        address objector;             // Address that raised objection
        bytes32 reason;               // Reason for objection
        uint256 raisedAt;             // When objection was raised
        uint256 resolutionDeadline;   // Deadline to resolve
        ObjectionStatus status;       // Current status
    }

    struct ProofData {
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
        uint256 smax;
    }

    // ========== EVENTS ==========

    event PendingProofSubmitted(
        bytes32 indexed channelId,
        uint256 indexed proofIndex,
        address indexed submitter,
        bytes32 proofHash,
        uint256 challengeDeadline
    );
    event ObjectionRaised(
        bytes32 indexed channelId,
        uint256 indexed proofIndex,
        address indexed objector,
        bytes32 reason,
        uint256 resolutionDeadline
    );
    event ObjectionResolved(
        bytes32 indexed channelId,
        uint256 indexed proofIndex,
        ObjectionStatus outcome,
        address slashedParty
    );
    event StateConfirmed(
        bytes32 indexed channelId,
        bytes32 newStateRoot,
        uint256 confirmedProofCount
    );
    event ProofRejected(
        bytes32 indexed channelId,
        uint256 indexed proofIndex,
        bytes32 reason
    );

    // ========== PROOF SUBMISSION ==========

    /**
     * @notice Submit a pending proof for a channel (not verified immediately)
     * @dev Any channel participant can submit. Proof is queued for challenge period.
     * @param channelId The channel to submit proof for
     * @param proofData The ZK proof data
     * @param previousStateRoot The state root this proof builds upon
     * @param newStateRoot The new state root after applying this proof
     * @return proofIndex Index of the submitted proof in the queue
     */
    function submitPendingProof(
        bytes32 channelId,
        ProofData calldata proofData,
        bytes32 previousStateRoot,
        bytes32 newStateRoot
    ) external returns (uint256 proofIndex);

    // ========== OBJECTION FUNCTIONS ==========

    /**
     * @notice Raise an objection against a pending proof
     * @dev Requires minimum stake. Transitions channel to Disputing state.
     * @param channelId The channel containing the proof
     * @param proofIndex Index of the proof to challenge
     * @param reason Identifier for objection reason
     */
    function raiseObjection(bytes32 channelId, uint256 proofIndex, bytes32 reason) external;

    /**
     * @notice Resolve an active objection by verifying the proof on-chain
     * @dev Anyone can call. Verifies proof and slashes appropriate party.
     * @param channelId The channel with the objection
     * @param objectionIndex Index of the objection to resolve
     * @param proofData Full proof data for on-chain verification
     */
    function resolveObjection(
        bytes32 channelId,
        uint256 objectionIndex,
        ProofData calldata proofData
    ) external;

    // ========== STATE CONFIRMATION ==========

    /**
     * @notice Confirm accumulated proofs as a new checkpoint state
     * @dev Can only be called after challenge period passes with no active objections
     * @param channelId The channel to confirm state for
     */
    function confirmState(bytes32 channelId) external;

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Get pending proof details
     * @param channelId The channel to query
     * @param proofIndex Index of the proof
     * @return proof The pending proof details
     */
    function getPendingProof(bytes32 channelId, uint256 proofIndex)
        external
        view
        returns (PendingProof memory proof);

    /**
     * @notice Get number of pending proofs for a channel
     * @param channelId The channel to query
     * @return count Number of pending proofs
     */
    function getPendingProofCount(bytes32 channelId) external view returns (uint256 count);

    /**
     * @notice Get objection details
     * @param channelId The channel to query
     * @param objectionIndex Index of the objection
     * @return objection The objection details
     */
    function getObjection(bytes32 channelId, uint256 objectionIndex)
        external
        view
        returns (Objection memory objection);

    /**
     * @notice Get number of objections for a channel
     * @param channelId The channel to query
     * @return count Number of objections
     */
    function getObjectionCount(bytes32 channelId) external view returns (uint256 count);

    /**
     * @notice Check if a channel has any active objections
     * @param channelId The channel to check
     * @return hasActive True if there are unresolved objections
     */
    function hasActiveObjections(bytes32 channelId) external view returns (bool hasActive);

    /**
     * @notice Get the latest confirmable proof index
     * @dev Returns the highest proof index that has passed challenge period
     * @param channelId The channel to query
     * @return index The latest confirmable proof index (-1 if none)
     */
    function getLatestConfirmableProofIndex(bytes32 channelId) external view returns (int256 index);

    /**
     * @notice Check if state can be confirmed for a channel
     * @param channelId The channel to check
     * @return canConfirm True if confirmState can be called
     */
    function canConfirmState(bytes32 channelId) external view returns (bool canConfirm);

    // ========== PARAMETER GETTERS ==========

    /**
     * @notice Get the challenge period duration
     * @return period Challenge period in seconds
     */
    function getChallengePeriod() external view returns (uint256 period);

    /**
     * @notice Get the resolution timeout duration
     * @return timeout Resolution timeout in seconds
     */
    function getResolutionTimeout() external view returns (uint256 timeout);

    /**
     * @notice Get the maximum number of pending proofs allowed
     * @return max Maximum pending proofs
     */
    function getMaxPendingProofs() external view returns (uint256 max);
}
