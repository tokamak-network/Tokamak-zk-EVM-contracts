// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IChannelRegistry} from "./interface/IChannelRegistry.sol";
import {IStateTransitionVerifier} from "./interface/IStateTransitionVerifier.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/utils/cryptography/MessageHashUtils.sol";
import {IDisputeResolver} from "./interface/IDisputeResolver.sol";

/**
 * @title DisputeResolver
 * @notice Handles disputes in state channels including fraud proofs, censorship claims, and emergency resolutions
 */
contract DisputeResolver is Ownable, ReentrancyGuard, IDisputeResolver {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // Contracts
    IChannelRegistry public channelRegistry;
    IStateTransitionVerifier public stateTransitionVerifier;

    // State variables
    mapping(bytes32 => Dispute) public disputes; // disputeId => Dispute
    mapping(bytes32 => ChallengeResponse) public challengeResponses; // disputeId => Response
    mapping(bytes32 => uint256) public channelDisputeCount; // channelId => count
    mapping(address => uint256) public disputerStakes; // disputer => total stake
    
    uint256 public disputeCounter;
    uint256 public constant DISPUTE_STAKE = 0.1 ether;
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant MAX_DISPUTE_DURATION = 7 days;
    
    // Arbitrators (can be a DAO or trusted parties)
    mapping(address => bool) public arbitrators;
    uint256 public requiredArbitratorSignatures = 1;


    modifier onlyArbitrator() {
        if (!arbitrators[msg.sender]) {
            revert DisputeResolver__NotAuthorized();
        }
        _;
    }

    constructor(address _channelRegistry, address _stateTransitionVerifier) Ownable(msg.sender) {
        channelRegistry = IChannelRegistry(_channelRegistry);
        stateTransitionVerifier = IStateTransitionVerifier(_stateTransitionVerifier);
        arbitrators[msg.sender] = true;
    }

    /**
     * @notice Create a dispute against a channel participant
     * @param channelId The channel ID
     * @param accused The accused participant address
     * @param disputeType Type of dispute
     * @param evidence Evidence supporting the dispute
     */
    function createDispute(
        bytes32 channelId,
        address accused,
        DisputeType disputeType,
        bytes calldata evidence
    ) external payable nonReentrant returns (bytes32 disputeId) {
        if (msg.value < DISPUTE_STAKE) {
            revert DisputeResolver__InsufficientStake();
        }

        // Verify channel exists
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(channelId);
        if (channelInfo.leader == address(0)) {
            revert DisputeResolver__InvalidChannel();
        }

        // Verify accused is a participant or leader
        bool isParticipant = channelRegistry.isChannelParticipant(channelId, accused);
        bool isLeader = (channelInfo.leader == accused);
        if (!isParticipant && !isLeader) {
            revert DisputeResolver__InvalidEvidence();
        }

        // Generate dispute ID
        disputeId = keccak256(abi.encodePacked(channelId, msg.sender, disputeCounter++));

        // Create dispute
        disputes[disputeId] = Dispute({
            channelId: channelId,
            disputer: msg.sender,
            accused: accused,
            disputeType: disputeType,
            status: DisputeStatus.PENDING,
            stake: msg.value,
            createdAt: block.timestamp,
            challengeDeadline: block.timestamp + CHALLENGE_PERIOD,
            evidence: evidence,
            disputedStateRoot: channelInfo.currentStateRoot
        });

        disputerStakes[msg.sender] += msg.value;
        channelDisputeCount[channelId]++;

        emit DisputeCreated(disputeId, channelId, msg.sender, disputeType);
    }

    /**
     * @notice Challenge a dispute with counter-evidence
     * @param disputeId The dispute ID
     * @param proof Counter-evidence/proof
     */
    function challengeDispute(bytes32 disputeId, bytes calldata proof) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        
        if (dispute.disputer == address(0)) {
            revert DisputeResolver__DisputeNotFound();
        }
        
        if (dispute.status != DisputeStatus.PENDING) {
            revert DisputeResolver__DisputeNotPending();
        }
        
        if (block.timestamp > dispute.challengeDeadline) {
            revert DisputeResolver__DisputeExpired();
        }

        // Only accused or channel leader can challenge
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(dispute.channelId);
        if (msg.sender != dispute.accused && msg.sender != channelInfo.leader) {
            revert DisputeResolver__NotAuthorized();
        }

        dispute.status = DisputeStatus.CHALLENGED;
        
        challengeResponses[disputeId] = ChallengeResponse({
            proof: proof,
            witnesses: new bytes32[](0),
            timestamp: block.timestamp
        });

        emit DisputeChallenged(disputeId, proof);
    }

    /**
     * @notice Resolve a dispute based on evidence
     * @param disputeId The dispute ID
     * @param valid Whether the dispute is valid
     * @param slashAmount Amount to slash if valid
     */
    function resolveDispute(
        bytes32 disputeId,
        bool valid,
        uint256 slashAmount
    ) external onlyArbitrator nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        
        if (dispute.disputer == address(0)) {
            revert DisputeResolver__DisputeNotFound();
        }
        
        if (dispute.status == DisputeStatus.RESOLVED || dispute.status == DisputeStatus.REJECTED) {
            revert DisputeResolver__NotAuthorized();
        }

        // Check if expired
        if (block.timestamp > dispute.createdAt + MAX_DISPUTE_DURATION) {
            dispute.status = DisputeStatus.EXPIRED;
            _returnStake(dispute.disputer, dispute.stake);
            return;
        }

        if (valid) {
            dispute.status = DisputeStatus.RESOLVED;
            _executeResolution(dispute, slashAmount);
            // Return stake to disputer + reward
            _returnStake(dispute.disputer, dispute.stake + (slashAmount / 10)); // 10% reward
        } else {
            dispute.status = DisputeStatus.REJECTED;
            // Slash disputer's stake
            _distributeSlashedStake(dispute.stake, dispute.accused);
        }

        emit DisputeResolved(disputeId, valid, slashAmount);
    }

    /**
     * @notice Automatically resolve censorship disputes
     * @param disputeId The dispute ID
     */
    function resolveCensorshipDispute(bytes32 disputeId) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        
        if (dispute.disputeType != DisputeType.CENSORSHIP) {
            revert DisputeResolver__InvalidEvidence();
        }
        
        if (dispute.status != DisputeStatus.PENDING) {
            revert DisputeResolver__DisputeNotPending();
        }

        // If challenge period passed without response, censorship is proven
        if (block.timestamp > dispute.challengeDeadline) {
            dispute.status = DisputeStatus.RESOLVED;
            
            // Slash leader for censorship
            IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(dispute.channelId);
            if (channelInfo.leader == dispute.accused) {
                channelRegistry.slashLeader(dispute.accused, DISPUTE_STAKE, "Censorship");
            }
            
            // Return stake to disputer
            _returnStake(dispute.disputer, dispute.stake);
            
            emit DisputeResolved(disputeId, true, DISPUTE_STAKE);
        }
    }

    /**
     * @notice Verify an invalid state transition dispute
     * @param disputeId The dispute ID
     */
    function verifyInvalidStateTransition(bytes32 disputeId) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        
        if (dispute.disputeType != DisputeType.INVALID_STATE_TRANSITION) {
            revert DisputeResolver__InvalidEvidence();
        }

        // Decode evidence to get the invalid state update
        IStateTransitionVerifier.StateUpdate memory invalidUpdate = abi.decode(
            dispute.evidence,
            (IStateTransitionVerifier.StateUpdate)
        );

        // Try to verify the state transition
        try stateTransitionVerifier.verifyAndCommitStateUpdate(invalidUpdate) returns (bool success) {
            if (success) {
                // Transition was actually valid, reject dispute
                dispute.status = DisputeStatus.REJECTED;
                _distributeSlashedStake(dispute.stake, dispute.accused);
            }
        } catch {
            // Transition was invalid, resolve in favor of disputer
            dispute.status = DisputeStatus.RESOLVED;
            _executeResolution(dispute, DISPUTE_STAKE);
            _returnStake(dispute.disputer, dispute.stake + DISPUTE_STAKE / 10);
        }

        emit DisputeResolved(disputeId, dispute.status == DisputeStatus.RESOLVED, DISPUTE_STAKE);
    }

    /**
     * @notice Emergency pause a channel
     * @param channelId The channel ID
     * @param reason Reason for emergency action
     */
    function emergencyPauseChannel(
        bytes32 channelId,
        string calldata reason
    ) external onlyArbitrator {
        // Change channel status to CLOSING
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(channelId);
        
        // Use emergency state update to freeze the channel
        stateTransitionVerifier.emergencyStateUpdate(
            channelId,
            channelInfo.currentStateRoot // Keep current state
        );

        emit EmergencyActionTaken(channelId, string(abi.encodePacked("Emergency pause: ", reason)));
    }

    /**
     * @notice Force channel closure due to unresolved disputes
     * @param channelId The channel ID
     * @param finalBalances Final balance distribution
     */
    function forceChannelClosure(
        bytes32 channelId,
        IChannelRegistry.TokenBalance[] calldata finalBalances
    ) external onlyArbitrator {
        // Verify there are active disputes
        if (channelDisputeCount[channelId] == 0) {
            revert DisputeResolver__NotAuthorized();
        }

        // Create final state root from balances
        bytes32 finalStateRoot = keccak256(abi.encode(msg.sender, finalBalances));

        // Force update the state
        stateTransitionVerifier.emergencyStateUpdate(
            channelId,
            finalStateRoot
        );

        emit EmergencyActionTaken(channelId, "Forced closure");
    }

    /**
     * @notice Slash a participant who hasn't staked
     * @param channelId The channel ID
     * @param participant The participant address
     */
    function slashNonStakedParticipant(bytes32 channelId, address participant) external onlyArbitrator {
        channelRegistry.slashNonStakedParticipant(channelId, participant);
    }

    // Internal functions
    function _executeResolution(Dispute memory dispute, uint256 slashAmount) internal {
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(dispute.channelId);
        
        if (channelInfo.leader == dispute.accused) {
            // Slash leader
            channelRegistry.slashLeader(
                dispute.accused,
                slashAmount,
                keccak256(abi.encodePacked("Dispute:", dispute.disputeType))
            );
        } else {
            // For participants, we need different handling
            // Could implement participant slashing in ChannelRegistry
        }
    }

    function _returnStake(address to, uint256 amount) internal {
        disputerStakes[to] -= amount;
        payable(to).transfer(amount);
    }

    function _distributeSlashedStake(uint256 amount, address beneficiary) internal {
        // Send slashed stake to accused or treasury
        payable(beneficiary).transfer(amount);
    }

    // Admin functions
    function addArbitrator(address arbitrator) external onlyOwner {
        arbitrators[arbitrator] = true;
        emit ArbitratorAdded(arbitrator);
    }

    function removeArbitrator(address arbitrator) external onlyOwner {
        arbitrators[arbitrator] = false;
        emit ArbitratorRemoved(arbitrator);
    }

    function setRequiredArbitratorSignatures(uint256 required) external onlyOwner {
        requiredArbitratorSignatures = required;
    }

    function updateContracts(
        address _channelRegistry,
        address _stateTransitionVerifier
    ) external onlyOwner {
        channelRegistry = IChannelRegistry(_channelRegistry);
        stateTransitionVerifier = IStateTransitionVerifier(_stateTransitionVerifier);
    }

    // View functions
    function getDispute(bytes32 disputeId) external view returns (Dispute memory) {
        return disputes[disputeId];
    }

    function getChallengeResponse(bytes32 disputeId) external view returns (ChallengeResponse memory) {
        return challengeResponses[disputeId];
    }

    function getChannelDisputeCount(bytes32 channelId) external view returns (uint256) {
        return channelDisputeCount[channelId];
    }

    function isArbitrator(address account) external view returns (bool) {
        return arbitrators[account];
    }

    // Emergency withdrawal (only owner, with timelock in production)
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    receive() external payable {
        // Accept ETH for stakes
    }
}