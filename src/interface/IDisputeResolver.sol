// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IChannelRegistry} from "./IChannelRegistry.sol";

interface IDisputeResolver {
    // Enums
    enum DisputeType {
        INVALID_STATE_TRANSITION,
        CENSORSHIP,
        BALANCE_MISMATCH,
        UNAUTHORIZED_ACTION,
        DATA_UNAVAILABILITY
    }

    enum DisputeStatus {
        PENDING,
        CHALLENGED,
        RESOLVED,
        REJECTED,
        EXPIRED
    }

    // Structs
    struct Dispute {
        bytes32 channelId;
        address disputer;
        address accused;
        DisputeType disputeType;
        DisputeStatus status;
        uint256 stake;
        uint256 createdAt;
        uint256 challengeDeadline;
        bytes evidence;
        bytes32 disputedStateRoot;
    }

    struct ChallengeResponse {
        bytes proof;
        bytes32[] witnesses;
        uint256 timestamp;
    }

    // Events
    event DisputeCreated(
        bytes32 indexed disputeId,
        bytes32 indexed channelId,
        address indexed disputer,
        DisputeType disputeType
    );
    event DisputeChallenged(bytes32 indexed disputeId, bytes proof);
    event DisputeResolved(bytes32 indexed disputeId, bool valid, uint256 slashAmount);
    event ArbitratorAdded(address indexed arbitrator);
    event ArbitratorRemoved(address indexed arbitrator);
    event EmergencyActionTaken(bytes32 indexed channelId, string action);

    // Errors
    error DisputeResolver__InsufficientStake();
    error DisputeResolver__InvalidChannel();
    error DisputeResolver__DisputeNotFound();
    error DisputeResolver__DisputeNotPending();
    error DisputeResolver__InvalidEvidence();
    error DisputeResolver__ChallengePeriodActive();
    error DisputeResolver__NotAuthorized();
    error DisputeResolver__InvalidProof();
    error DisputeResolver__DisputeExpired();

    // Functions
    function createDispute(
        bytes32 channelId,
        address accused,
        DisputeType disputeType,
        bytes calldata evidence
    ) external payable returns (bytes32 disputeId);

    function challengeDispute(bytes32 disputeId, bytes calldata proof) external;

    function resolveDispute(
        bytes32 disputeId,
        bool valid,
        uint256 slashAmount
    ) external;

    function resolveCensorshipDispute(bytes32 disputeId) external;
    function verifyInvalidStateTransition(bytes32 disputeId) external;
    
    function emergencyPauseChannel(bytes32 channelId, string calldata reason) external;
    function forceChannelClosure(
        bytes32 channelId,
        IChannelRegistry.TokenBalance[] calldata finalBalances
    ) external;
    
    function slashNonStakedParticipant(bytes32 channelId, address participant) external;

    // Admin functions
    function addArbitrator(address arbitrator) external;
    function removeArbitrator(address arbitrator) external;
    function setRequiredArbitratorSignatures(uint256 required) external;
    function updateContracts(address _channelRegistry, address _stateTransitionVerifier) external;

    // View functions
    function getDispute(bytes32 disputeId) external view returns (Dispute memory);
    function getChallengeResponse(bytes32 disputeId) external view returns (ChallengeResponse memory);
    function getChannelDisputeCount(bytes32 channelId) external view returns (uint256);
    function isArbitrator(address account) external view returns (bool);
}