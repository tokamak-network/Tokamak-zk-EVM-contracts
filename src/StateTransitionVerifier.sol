// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Verifier} from "./Verifier.sol";
import {IStateTransitionVerifier} from "./interface/IStateTransitionVerifier.sol";
import {IChannelRegistry} from "./interface/IChannelRegistry.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/utils/cryptography/MessageHashUtils.sol";

contract StateTransitionVerifier is IStateTransitionVerifier, Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    Verifier public verifier;

    // Channel state roots
    mapping(bytes32 => bytes32) public channelStateRoots;

    // Channel registry reference
    IChannelRegistry public channelRegistry;

    // Nonce for replay protection
    mapping(bytes32 => uint256) public channelNonces;

    // Enhanced tracking for active participants only
    mapping(bytes32 => mapping(address => bool)) private activeParticipantCache;

    constructor(address _verifier, address _channelRegistry) Ownable(msg.sender) {
        if (_verifier == address(0)) {
            revert Invalid__Verifier();
        }
        if (_channelRegistry == address(0)) {
            revert Invalid__ChannelRegistry();
        }
        verifier = Verifier(_verifier);
        channelRegistry = IChannelRegistry(_channelRegistry);
    }

    function verifyAndCommitStateUpdate(StateUpdate calldata update) external returns (bool) {
        // Only channel leader can submit updates
        if (msg.sender != channelRegistry.getLeaderAddress(update.channelId)) {
            revert Invalid__Caller();
        }

        // Get channel info from registry
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(update.channelId);

        // Check channel is active
        if (channelInfo.status != IChannelRegistry.ChannelStatus.ACTIVE) {
            revert Invalid__ChannelNotActive();
        }

        // Verify nonce
        uint256 expectedNonce = channelNonces[update.channelId] + 1;
        if (update.nonce != expectedNonce) {
            revert Invalid__Nonce(update.nonce, expectedNonce);
        }

        // Verify old state root matches
        bytes32 currentRoot = channelRegistry.getCurrentStateRoot(update.channelId);
        if (update.oldStateRoot != currentRoot) {
            revert Invalid__OldStateRoot(update.oldStateRoot, currentRoot);
        }

        // Get only active participants for signature verification
        address[] memory activeParticipants = _getActiveParticipants(update.channelId, channelInfo.participants);

        // Calculate dynamic threshold based on active participants
        uint256 activeThreshold = _calculateActiveThreshold(activeParticipants.length, channelInfo.signatureThreshold);

        // Verify participant signatures with active participants only
        _verifyParticipantSignatures(update, activeParticipants, activeThreshold);

        // Verify zkSNARK proof
        if (!verifier.verify(update.proofPart1, update.proofPart2, update.publicInputs, update.smax)) {
            revert Invalid__SnarkProof();
        }

        // Update state
        channelStateRoots[update.channelId] = update.newStateRoot;
        channelNonces[update.channelId] = update.nonce;

        // Update balance root if provided (O(1) operation!)
        if (update.newStateRoot != bytes32(0)) {
            channelRegistry.updateStateRoot(update.channelId, update.newStateRoot);
        }

        emit StateUpdated(update.channelId, update.oldStateRoot, update.newStateRoot, update.nonce);

        return true;
    }

    function _getActiveParticipants(bytes32 channelId, address[] memory allParticipants)
        internal
        view
        returns (address[] memory)
    {
        // Count active participants first
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allParticipants.length; i++) {
            if (channelRegistry.isChannelParticipant(channelId, allParticipants[i])) {
                activeCount++;
            }
        }

        // Create array of active participants
        address[] memory activeParticipants = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allParticipants.length; i++) {
            if (channelRegistry.isChannelParticipant(channelId, allParticipants[i])) {
                activeParticipants[index] = allParticipants[i];
                index++;
            }
        }

        return activeParticipants;
    }

    function _calculateActiveThreshold(uint256 activeParticipantCount, uint256 originalThreshold)
        internal
        pure
        returns (uint256)
    {
        // If more than half participants have exited, require all remaining participants
        if (activeParticipantCount <= originalThreshold) {
            return activeParticipantCount;
        }

        // Otherwise use original threshold
        return originalThreshold;
    }

    function _verifyParticipantSignatures(
        StateUpdate calldata update,
        address[] memory activeParticipants,
        uint256 threshold
    ) internal pure {
        // Check array lengths match
        if (update.participantSignatures.length != update.signers.length) {
            revert Invalid__ArrayLengthMismatch();
        }

        // Check we have enough signatures
        if (update.participantSignatures.length < threshold) {
            revert Invalid__SignatureCount(update.participantSignatures.length, threshold);
        }

        // Create the message hash that participants should have signed
        bytes32 messageHash =
            keccak256(abi.encode(update.channelId, update.oldStateRoot, update.newStateRoot, update.nonce));

        // Add Ethereum Signed Message prefix
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        // Track signers to prevent duplicates
        address[] memory seenSigners = new address[](update.signers.length);
        uint256 seenCount = 0;

        // Verify each signature
        for (uint256 i = 0; i < update.participantSignatures.length; i++) {
            address signer = update.signers[i];

            // Check for duplicate signers
            for (uint256 k = 0; k < seenCount; k++) {
                if (seenSigners[k] == signer) {
                    revert Invalid__DuplicateSigner(signer);
                }
            }
            seenSigners[seenCount] = signer;
            seenCount++;

            // Verify signer is an active participant
            bool isActiveParticipant = false;
            for (uint256 j = 0; j < activeParticipants.length; j++) {
                if (activeParticipants[j] == signer) {
                    isActiveParticipant = true;
                    break;
                }
            }
            if (!isActiveParticipant) {
                revert Invalid__Signer(signer);
            }

            // Recover signer from signature
            address recoveredSigner = ethSignedMessageHash.recover(update.participantSignatures[i]);

            // Verify signature matches claimed signer
            if (recoveredSigner != signer) {
                revert Invalid__Signature(signer, i);
            }
        }
    }

    // Enhanced verification for channels in closing state
    function verifyClosingStateUpdate(StateUpdate calldata update) external returns (bool) {
        // Only channel leader can submit updates
        if (msg.sender != channelRegistry.getLeaderAddress(update.channelId)) {
            revert Invalid__Caller();
        }

        // Get channel info from registry
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(update.channelId);

        // Only allow updates during closing process
        if (channelInfo.status != IChannelRegistry.ChannelStatus.CLOSING) {
            revert Invalid__ChannelNotActive();
        }

        // Verify nonce
        uint256 expectedNonce = channelNonces[update.channelId] + 1;
        if (update.nonce != expectedNonce) {
            revert Invalid__Nonce(update.nonce, expectedNonce);
        }

        // Verify old state root matches
        bytes32 currentRoot = channelRegistry.getCurrentStateRoot(update.channelId);
        if (update.oldStateRoot != currentRoot) {
            revert Invalid__OldStateRoot(update.oldStateRoot, currentRoot);
        }

        // For closing channels, require ALL remaining active participants to sign
        address[] memory activeParticipants = _getActiveParticipants(update.channelId, channelInfo.participants);

        // During closure, require unanimous consent from remaining participants
        _verifyParticipantSignatures(update, activeParticipants, activeParticipants.length);

        // Verify zkSNARK proof
        if (!verifier.verify(update.proofPart1, update.proofPart2, update.publicInputs, update.smax)) {
            revert Invalid__SnarkProof();
        }

        // Update state
        channelStateRoots[update.channelId] = update.newStateRoot;
        channelNonces[update.channelId] = update.nonce;

        // Update current state root in channel registry
        channelRegistry.updateStateRoot(update.channelId, update.newStateRoot);

        emit StateUpdated(update.channelId, update.oldStateRoot, update.newStateRoot, update.nonce);

        return true;
    }

    // Emergency update function (only for dispute resolution)
    function emergencyStateUpdate(bytes32 channelId, bytes32 newStateRoot) external {
        // Only dispute resolver can call this
        require(msg.sender == owner() || msg.sender == address(channelRegistry), "Unauthorized");

        // Additional verification logic for dispute proof would go here
        // For now, we'll just update the state

        uint256 newNonce = channelNonces[channelId] + 1;
        bytes32 oldRoot = channelStateRoots[channelId];

        channelStateRoots[channelId] = newStateRoot;
        channelNonces[channelId] = newNonce;

        // Update registry
        channelRegistry.updateStateRoot(channelId, newStateRoot);

        emit EmergencyStateUpdate(channelId, oldRoot, newStateRoot, newNonce);
    }

    function updateVerifier(address _verifier) external onlyOwner {
        if (_verifier == address(0)) {
            revert Invalid__Verifier();
        }
        address oldVerifier = address(verifier);
        verifier = Verifier(_verifier);
        emit VerifierUpdated(oldVerifier, _verifier);
    }

    function updateChannelRegistry(address _channelRegistry) external onlyOwner {
        if (_channelRegistry == address(0)) {
            revert Invalid__ChannelRegistry();
        }
        channelRegistry = IChannelRegistry(_channelRegistry);
    }

    // View functions
    function getChannelState(bytes32 channelId) external view returns (bytes32 stateRoot, uint256 nonce) {
        return (channelStateRoots[channelId], channelNonces[channelId]);
    }

    function getActiveParticipantCount(bytes32 channelId) external view returns (uint256) {
        return channelRegistry.getActiveParticipantCount(channelId);
    }

    function getRequiredSignatureThreshold(bytes32 channelId) external view returns (uint256) {
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(channelId);
        uint256 activeCount = channelRegistry.getActiveParticipantCount(channelId);
        return _calculateActiveThreshold(activeCount, channelInfo.signatureThreshold);
    }
}
