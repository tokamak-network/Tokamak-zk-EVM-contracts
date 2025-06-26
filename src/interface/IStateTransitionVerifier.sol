// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IChannelRegistry} from "./IChannelRegistry.sol";

interface IStateTransitionVerifier {
    struct StateUpdate {
        bytes32 channelId;
        bytes32 oldStateRoot;
        bytes32 newStateRoot;
        uint256 nonce;
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
        bytes[] participantSignatures;
        address[] signers;
        IChannelRegistry.BalanceUpdate[] balanceUpdates; // New field for balance updates
    }

    // Events
    event StateUpdated(bytes32 indexed channelId, bytes32 oldStateRoot, bytes32 newStateRoot, uint256 nonce);
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event EmergencyStateUpdate(bytes32 indexed channelId, bytes32 oldStateRoot, bytes32 newStateRoot, uint256 nonce);

    // Custom errors
    error Invalid__Verifier();
    error Invalid__ChannelRegistry();
    error Invalid__Caller();
    error Invalid__ChannelNotActive();
    error Invalid__Nonce(uint256 provided, uint256 expected);
    error Invalid__OldStateRoot(bytes32 provided, bytes32 expected);
    error Invalid__ArrayLengthMismatch();
    error Invalid__SignatureCount(uint256 provided, uint256 required);
    error Invalid__DuplicateSigner(address signer);
    error Invalid__Signer(address signer);
    error Invalid__Signature(address signer, uint256 index);
    error Invalid__SnarkProof();

    // Core functions
    function verifyAndCommitStateUpdate(StateUpdate calldata update) external returns (bool);
    function verifyClosingStateUpdate(StateUpdate calldata update) external returns (bool);
    function emergencyStateUpdate(bytes32 channelId, bytes32 newStateRoot, bytes calldata disputeProof) external;
    
    // Management functions
    function updateVerifier(address _verifier) external;
    function updateChannelRegistry(address _channelRegistry) external;
    
    // View functions
    function getChannelState(bytes32 channelId) external view returns (bytes32 stateRoot, uint256 nonce);
    function getActiveParticipantCount(bytes32 channelId) external view returns (uint256);
    function getRequiredSignatureThreshold(bytes32 channelId) external view returns (uint256);
}