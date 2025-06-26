// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IChannelRegistry} from "./IChannelRegistry.sol";

interface IStateTransitionVerifier {
    // Updated StateUpdate struct with balance root instead of individual updates
    struct StateUpdate {
        bytes32 channelId;
        bytes32 oldStateRoot;
        bytes32 newStateRoot;
        uint256 nonce;
        bytes[] participantSignatures;
        address[] signers;
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
    }

    // Events
    event StateUpdated(
        bytes32 indexed channelId, bytes32 indexed oldStateRoot, bytes32 indexed newStateRoot, uint256 nonce
    );

    event EmergencyStateUpdate(bytes32 indexed channelId, bytes32 oldStateRoot, bytes32 newStateRoot, uint256 nonce);

    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    // Errors
    error Invalid__Caller();
    error Invalid__ChannelNotActive();
    error Invalid__Nonce(uint256 provided, uint256 expected);
    error Invalid__OldStateRoot(bytes32 provided, bytes32 expected);
    error Invalid__SignatureCount(uint256 provided, uint256 required);
    error Invalid__Signer(address signer);
    error Invalid__Signature(address claimed, uint256 index);
    error Invalid__SnarkProof();
    error Invalid__ArrayLengthMismatch();
    error Invalid__DuplicateSigner(address signer);
    error Invalid__Verifier();
    error Invalid__ChannelRegistry();

    // Functions
    function verifyAndCommitStateUpdate(StateUpdate calldata update) external returns (bool);
    function verifyClosingStateUpdate(StateUpdate calldata update) external returns (bool);
    function emergencyStateUpdate(bytes32 channelId, bytes32 newStateRoot) external;
    function updateVerifier(address _verifier) external;
    function updateChannelRegistry(address _channelRegistry) external;
    function getChannelState(bytes32 channelId) external view returns (bytes32 stateRoot, uint256 nonce);
    function getActiveParticipantCount(bytes32 channelId) external view returns (uint256);
    function getRequiredSignatureThreshold(bytes32 channelId) external view returns (uint256);
}
