// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interface/IBridgeCore.sol";
import "./interface/IBridgeObjectionManager.sol";
import "./interface/IBridgeStakingManager.sol";
import {ITokamakVerifier} from "./interface/ITokamakVerifier.sol";

/**
 * @title BridgeObjectionManager
 * @notice Manages pending proofs, objections, and state confirmations
 * @dev Part of the Q2 2026 upgrade implementing the objection/slash/reward architecture
 */
contract BridgeObjectionManager is
    IBridgeObjectionManager,
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ========== CONSTANTS ==========

    uint256 public constant CHALLENGE_PERIOD = 24 hours;      // 24 hour challenge window
    uint256 public constant RESOLUTION_TIMEOUT = 48 hours;    // 48 hour resolution deadline
    uint256 public constant MAX_PENDING_PROOFS = 100;         // Maximum pending proofs per channel

    bytes32 public constant REASON_INVALID_PROOF = keccak256("INVALID_PROOF");
    bytes32 public constant REASON_FALSE_OBJECTION = keccak256("FALSE_OBJECTION");

    // ========== STORAGE ==========

    /// @custom:storage-location erc7201:tokamak.storage.BridgeObjectionManager
    struct BridgeObjectionManagerStorage {
        IBridgeCore bridge;
        IBridgeStakingManager stakingManager;
        ITokamakVerifier zkVerifier;
        // channelId => array of pending proofs
        mapping(bytes32 => PendingProof[]) pendingProofs;
        // channelId => array of objections
        mapping(bytes32 => Objection[]) objections;
        // channelId => number of active objections
        mapping(bytes32 => uint256) activeObjectionCount;
        // channelId => last confirmed proof index
        mapping(bytes32 => uint256) lastConfirmedProofIndex;
        // channelId => proofIndex => stored proof data hash
        mapping(bytes32 => mapping(uint256 => bytes32)) storedProofDataHashes;
    }

    bytes32 private constant BridgeObjectionManagerStorageLocation =
        0x3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a02;

    // ========== EVENTS ==========

    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event StakingManagerUpdated(address indexed oldManager, address indexed newManager);

    // ========== MODIFIERS ==========

    modifier onlyParticipant(bytes32 channelId) {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        require($.bridge.isChannelWhitelisted(channelId, msg.sender), "Not a participant");
        _;
    }

    modifier requireStake(bytes32 channelId) {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        require($.stakingManager.hasMinimumStake(channelId, msg.sender), "Insufficient stake");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ========== INITIALIZATION ==========

    function initialize(
        address _bridgeCore,
        address _stakingManager,
        address _zkVerifier,
        address _owner
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);

        require(_bridgeCore != address(0), "Invalid bridge address");
        require(_stakingManager != address(0), "Invalid staking manager");
        require(_zkVerifier != address(0), "Invalid verifier address");

        BridgeObjectionManagerStorage storage $ = _getStorage();
        $.bridge = IBridgeCore(_bridgeCore);
        $.stakingManager = IBridgeStakingManager(_stakingManager);
        $.zkVerifier = ITokamakVerifier(_zkVerifier);
    }

    // ========== PROOF SUBMISSION ==========

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function submitPendingProof(
        bytes32 channelId,
        ProofData calldata proofData,
        bytes32 previousStateRoot,
        bytes32 newStateRoot
    ) external nonReentrant onlyParticipant(channelId) requireStake(channelId) returns (uint256 proofIndex) {
        BridgeObjectionManagerStorage storage $ = _getStorage();

        // Verify channel is in valid state
        IBridgeCore.ChannelState state = $.bridge.getChannelState(channelId);
        require(
            state == IBridgeCore.ChannelState.Open || state == IBridgeCore.ChannelState.Disputing,
            "Channel not open"
        );

        // Check pending proof limit
        require($.pendingProofs[channelId].length < MAX_PENDING_PROOFS, "Too many pending proofs");

        // Compute proof hash for front-running protection
        bytes32 proofHash = keccak256(abi.encode(proofData.proofPart1, proofData.proofPart2, proofData.publicInputs));

        // Get proof index
        proofIndex = $.pendingProofs[channelId].length;

        // Validate state chain
        if (proofIndex == 0) {
            // First proof must reference initial state root
            bytes32 initialRoot = $.bridge.getChannelInitialStateRoot(channelId);
            require(previousStateRoot == initialRoot, "Must chain from initial state");
        } else {
            // Subsequent proofs must chain from previous
            PendingProof storage prevProof = $.pendingProofs[channelId][proofIndex - 1];
            require(previousStateRoot == prevProof.newStateRoot, "State chain broken");
        }

        // Store pending proof
        $.pendingProofs[channelId].push(PendingProof({
            channelId: channelId,
            proofHash: proofHash,
            previousStateRoot: previousStateRoot,
            newStateRoot: newStateRoot,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            challengeDeadline: block.timestamp + CHALLENGE_PERIOD,
            status: PendingProofStatus.Pending,
            proofIndex: proofIndex
        }));

        // Store proof data hash for later verification
        $.storedProofDataHashes[channelId][proofIndex] = proofHash;

        emit PendingProofSubmitted(channelId, proofIndex, msg.sender, proofHash, block.timestamp + CHALLENGE_PERIOD);

        return proofIndex;
    }

    // ========== OBJECTION FUNCTIONS ==========

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function raiseObjection(
        bytes32 channelId,
        uint256 proofIndex,
        bytes32 reason
    ) external nonReentrant onlyParticipant(channelId) requireStake(channelId) {
        BridgeObjectionManagerStorage storage $ = _getStorage();

        // Validate proof exists and is pending
        require(proofIndex < $.pendingProofs[channelId].length, "Invalid proof index");
        PendingProof storage proof = $.pendingProofs[channelId][proofIndex];
        require(proof.status == PendingProofStatus.Pending, "Proof not pending");
        require(block.timestamp <= proof.challengeDeadline, "Challenge period ended");

        // Cannot object to own proof
        require(msg.sender != proof.submitter, "Cannot object to own proof");

        // Mark proof as challenged
        proof.status = PendingProofStatus.Challenged;

        // Create objection
        $.objections[channelId].push(Objection({
            channelId: channelId,
            proofIndex: proofIndex,
            objector: msg.sender,
            reason: reason,
            raisedAt: block.timestamp,
            resolutionDeadline: block.timestamp + RESOLUTION_TIMEOUT,
            status: ObjectionStatus.Active
        }));

        $.activeObjectionCount[channelId]++;

        // Transition channel to Disputing state
        if ($.bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Open) {
            $.bridge.setChannelState(channelId, IBridgeCore.ChannelState.Disputing);
        }

        emit ObjectionRaised(
            channelId,
            proofIndex,
            msg.sender,
            reason,
            block.timestamp + RESOLUTION_TIMEOUT
        );
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function resolveObjection(
        bytes32 channelId,
        uint256 objectionIndex,
        ProofData calldata proofData
    ) external nonReentrant {
        BridgeObjectionManagerStorage storage $ = _getStorage();

        // Validate and get objection/proof data
        (Objection storage objection, PendingProof storage proof) = _validateObjectionResolution($, channelId, objectionIndex, proofData);

        // Verify proof on-chain
        bool proofValid = _verifyProofOnChain($, channelId, proofData);

        // Handle resolution outcome
        _handleResolutionOutcome($, channelId, objection, proof, proofValid);
    }

    function _validateObjectionResolution(
        BridgeObjectionManagerStorage storage $,
        bytes32 channelId,
        uint256 objectionIndex,
        ProofData calldata proofData
    ) internal view returns (Objection storage objection, PendingProof storage proof) {
        require(objectionIndex < $.objections[channelId].length, "Invalid objection index");
        objection = $.objections[channelId][objectionIndex];
        require(objection.status == ObjectionStatus.Active, "Objection not active");

        proof = $.pendingProofs[channelId][objection.proofIndex];
        require(proof.status == PendingProofStatus.Challenged, "Proof not challenged");

        // Verify proof data matches stored hash
        bytes32 computedHash = keccak256(abi.encode(proofData.proofPart1, proofData.proofPart2, proofData.publicInputs));
        require(computedHash == proof.proofHash, "Proof data mismatch");
    }

    function _verifyProofOnChain(
        BridgeObjectionManagerStorage storage $,
        bytes32 channelId,
        ProofData calldata proofData
    ) internal view returns (bool) {
        address targetContract = $.bridge.getChannelTargetContract(channelId);
        IBridgeCore.TargetContract memory targetData = $.bridge.getTargetContractData(targetContract);

        bytes32 funcSig = _extractFunctionSignature(proofData.publicInputs);

        for (uint256 i = 0; i < targetData.registeredFunctions.length; i++) {
            if (targetData.registeredFunctions[i].functionSignature == funcSig) {
                return $.zkVerifier.verify(
                    proofData.proofPart1,
                    proofData.proofPart2,
                    targetData.registeredFunctions[i].preprocessedPart1,
                    targetData.registeredFunctions[i].preprocessedPart2,
                    proofData.publicInputs,
                    proofData.smax
                );
            }
        }
        revert("Function not registered");
    }

    function _handleResolutionOutcome(
        BridgeObjectionManagerStorage storage $,
        bytes32 channelId,
        Objection storage objection,
        PendingProof storage proof,
        bool proofValid
    ) internal {
        if (proofValid) {
            _handleValidProof($, channelId, objection, proof);
        } else {
            _handleInvalidProof($, channelId, objection, proof);
        }

        $.activeObjectionCount[channelId]--;

        // If no more active objections, transition back to Open state
        if ($.activeObjectionCount[channelId] == 0 &&
            $.bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Disputing) {
            $.bridge.setChannelState(channelId, IBridgeCore.ChannelState.Open);
        }
    }

    function _handleValidProof(
        BridgeObjectionManagerStorage storage $,
        bytes32 channelId,
        Objection storage objection,
        PendingProof storage proof
    ) internal {
        objection.status = ObjectionStatus.Dismissed;
        proof.status = PendingProofStatus.Pending;
        proof.challengeDeadline = block.timestamp + CHALLENGE_PERIOD;

        $.stakingManager.slash(
            channelId,
            objection.objector,
            $.stakingManager.getFalseObjectionSlashPercentage(),
            REASON_FALSE_OBJECTION
        );

        uint256 rewardAmount = $.stakingManager.getRewardPoolBalance() / 4;
        if (rewardAmount > 0) {
            $.stakingManager.distributeReward(channelId, proof.submitter, rewardAmount);
        }

        emit ObjectionResolved(channelId, objection.proofIndex, ObjectionStatus.Dismissed, objection.objector);
    }

    function _handleInvalidProof(
        BridgeObjectionManagerStorage storage $,
        bytes32 channelId,
        Objection storage objection,
        PendingProof storage proof
    ) internal {
        objection.status = ObjectionStatus.Upheld;
        proof.status = PendingProofStatus.Rejected;

        $.stakingManager.slash(
            channelId,
            proof.submitter,
            $.stakingManager.getInvalidProofSlashPercentage(),
            REASON_INVALID_PROOF
        );

        uint256 rewardAmount = $.stakingManager.getRewardPoolBalance() / 2;
        if (rewardAmount > 0) {
            $.stakingManager.distributeReward(channelId, objection.objector, rewardAmount);
        }

        emit ProofRejected(channelId, objection.proofIndex, objection.reason);
        emit ObjectionResolved(channelId, objection.proofIndex, ObjectionStatus.Upheld, proof.submitter);
    }

    // ========== STATE CONFIRMATION ==========

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function confirmState(bytes32 channelId) external nonReentrant {
        BridgeObjectionManagerStorage storage $ = _getStorage();

        // Verify channel state
        IBridgeCore.ChannelState state = $.bridge.getChannelState(channelId);
        require(
            state == IBridgeCore.ChannelState.Open,
            "Channel not in confirmable state"
        );

        // Ensure no active objections
        require($.activeObjectionCount[channelId] == 0, "Active objections exist");

        // Find confirmable proofs
        uint256 lastConfirmed = $.lastConfirmedProofIndex[channelId];
        uint256 totalProofs = $.pendingProofs[channelId].length;

        require(totalProofs > lastConfirmed, "No new proofs to confirm");

        uint256 confirmableCount = 0;
        bytes32 latestConfirmableRoot;
        uint256 latestConfirmableIndex;

        for (uint256 i = lastConfirmed; i < totalProofs; i++) {
            PendingProof storage proof = $.pendingProofs[channelId][i];

            // Skip rejected proofs
            if (proof.status == PendingProofStatus.Rejected) {
                continue;
            }

            // Check if challenge period has passed
            if (block.timestamp > proof.challengeDeadline && proof.status == PendingProofStatus.Pending) {
                proof.status = PendingProofStatus.Confirmed;
                confirmableCount++;
                latestConfirmableRoot = proof.newStateRoot;
                latestConfirmableIndex = i;
            }
        }

        require(confirmableCount > 0, "No proofs ready for confirmation");

        // Update last confirmed index
        $.lastConfirmedProofIndex[channelId] = latestConfirmableIndex + 1;

        // Add confirmed state to bridge core
        $.bridge.addConfirmedState(channelId, latestConfirmableRoot, latestConfirmableIndex);

        emit StateConfirmed(channelId, latestConfirmableRoot, confirmableCount);
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function getPendingProof(bytes32 channelId, uint256 proofIndex)
        external
        view
        returns (PendingProof memory)
    {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        require(proofIndex < $.pendingProofs[channelId].length, "Invalid index");
        return $.pendingProofs[channelId][proofIndex];
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function getPendingProofCount(bytes32 channelId) external view returns (uint256) {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        return $.pendingProofs[channelId].length;
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function getObjection(bytes32 channelId, uint256 objectionIndex)
        external
        view
        returns (Objection memory)
    {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        require(objectionIndex < $.objections[channelId].length, "Invalid index");
        return $.objections[channelId][objectionIndex];
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function getObjectionCount(bytes32 channelId) external view returns (uint256) {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        return $.objections[channelId].length;
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function hasActiveObjections(bytes32 channelId) external view returns (bool) {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        return $.activeObjectionCount[channelId] > 0;
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function getLatestConfirmableProofIndex(bytes32 channelId) external view returns (int256) {
        BridgeObjectionManagerStorage storage $ = _getStorage();

        if ($.pendingProofs[channelId].length == 0) {
            return -1;
        }

        int256 latestIndex = -1;
        for (uint256 i = $.lastConfirmedProofIndex[channelId]; i < $.pendingProofs[channelId].length; i++) {
            PendingProof storage proof = $.pendingProofs[channelId][i];
            if (proof.status == PendingProofStatus.Pending && block.timestamp > proof.challengeDeadline) {
                latestIndex = int256(i);
            }
        }

        return latestIndex;
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function canConfirmState(bytes32 channelId) external view returns (bool) {
        BridgeObjectionManagerStorage storage $ = _getStorage();

        // Must be in Open state
        if ($.bridge.getChannelState(channelId) != IBridgeCore.ChannelState.Open) {
            return false;
        }

        // No active objections
        if ($.activeObjectionCount[channelId] > 0) {
            return false;
        }

        // Check for confirmable proofs
        for (uint256 i = $.lastConfirmedProofIndex[channelId]; i < $.pendingProofs[channelId].length; i++) {
            PendingProof storage proof = $.pendingProofs[channelId][i];
            if (proof.status == PendingProofStatus.Pending && block.timestamp > proof.challengeDeadline) {
                return true;
            }
        }

        return false;
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function getChallengePeriod() external pure returns (uint256) {
        return CHALLENGE_PERIOD;
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function getResolutionTimeout() external pure returns (uint256) {
        return RESOLUTION_TIMEOUT;
    }

    /**
     * @inheritdoc IBridgeObjectionManager
     */
    function getMaxPendingProofs() external pure returns (uint256) {
        return MAX_PENDING_PROOFS;
    }

    function getLastConfirmedProofIndex(bytes32 channelId) external view returns (uint256) {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        return $.lastConfirmedProofIndex[channelId];
    }

    function getActiveObjectionCount(bytes32 channelId) external view returns (uint256) {
        BridgeObjectionManagerStorage storage $ = _getStorage();
        return $.activeObjectionCount[channelId];
    }

    // ========== ADMIN FUNCTIONS ==========

    function updateBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        BridgeObjectionManagerStorage storage $ = _getStorage();
        $.bridge = IBridgeCore(_newBridge);
    }

    function updateStakingManager(address _newStakingManager) external onlyOwner {
        require(_newStakingManager != address(0), "Invalid staking manager");
        BridgeObjectionManagerStorage storage $ = _getStorage();
        address oldManager = address($.stakingManager);
        $.stakingManager = IBridgeStakingManager(_newStakingManager);
        emit StakingManagerUpdated(oldManager, _newStakingManager);
    }

    function updateVerifier(address _newVerifier) external onlyOwner {
        require(_newVerifier != address(0), "Invalid verifier address");
        BridgeObjectionManagerStorage storage $ = _getStorage();
        address oldVerifier = address($.zkVerifier);
        $.zkVerifier = ITokamakVerifier(_newVerifier);
        emit VerifierUpdated(oldVerifier, _newVerifier);
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _getStorage() internal pure returns (BridgeObjectionManagerStorage storage $) {
        assembly {
            $.slot := BridgeObjectionManagerStorageLocation
        }
    }

    function _extractFunctionSignature(uint256[] calldata publicInputs) internal pure returns (bytes32) {
        require(publicInputs.length >= 19, "Public inputs too short");
        uint256 selectorValue = publicInputs[14];
        bytes4 selector = bytes4(uint32(selectorValue));
        return bytes32(selector);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Returns the address of the current implementation contract
     * @dev Uses EIP-1967 standard storage slot for implementation address
     * @return implementation The address of the implementation contract
     */
    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    uint256[43] private __gap;
}
