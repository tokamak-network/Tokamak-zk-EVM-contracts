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

    constructor(address _verifier, address _channelRegistry) Ownable(msg.sender) {
        if(_verifier == address(0)) {
            revert Invalid__Verifier();
        }
        if(_channelRegistry == address(0)) {
            revert Invalid__ChannelRegistry();
        }
        verifier = Verifier(_verifier);
        channelRegistry = IChannelRegistry(_channelRegistry);
    }

    function verifyAndCommitStateUpdate(StateUpdate calldata update) external returns(bool) {
        if(msg.sender != channelRegistry.getLeaderAddress(update.channelId)) {
            revert Invalid__Caller();
        }
        // Get channel info from registry
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(update.channelId);
        
        // Check channel is active
        if(channelInfo.status != IChannelRegistry.ChannelStatus.ACTIVE) {
            revert Invalid__ChannelNotActive();
        }
        
        // Verify nonce
        uint256 expectedNonce = channelNonces[update.channelId] + 1;
        if(update.nonce != expectedNonce) {
            revert Invalid__Nonce(update.nonce, expectedNonce);
        }
        
        // Verify old state root matches
        bytes32 currentRoot = channelRegistry.getCurrentStateRoot(update.channelId);
        if(update.oldStateRoot != currentRoot) {
            revert Invalid__OldStateRoot(update.oldStateRoot, currentRoot);
        }

        // Verify participant signatures
        _verifyParticipantSignatures(
            update,
            channelInfo.participants,
            channelInfo.signatureThreshold
        );

        // Verify zkSNARK proof
        if(!verifier.verify(update.proofPart1, update.proofPart2, update.publicInputs)) {
            revert Invalid__SnarkProof();
        }

        // Update state
        channelStateRoots[update.channelId] = update.newStateRoot;
        channelNonces[update.channelId] = update.nonce;

        //Update current root in channel registry
        channelRegistry.updateStateRoot(update.channelId, update.newStateRoot);

        emit StateUpdated(
            update.channelId,
            update.oldStateRoot,
            update.newStateRoot,
            update.nonce
        );

        return true;
    }

    function _verifyParticipantSignatures(
        StateUpdate calldata update,
        address[] memory participants,
        uint256 threshold
    ) internal pure {
        // Check array lengths match
        if(update.participantSignatures.length != update.signers.length) {
            revert Invalid__ArrayLengthMismatch();
        }
        
        // Check we have enough signatures
        if(update.participantSignatures.length < threshold) {
            revert Invalid__SignatureCount(update.participantSignatures.length, threshold);
        }

        // Create the message hash that participants should have signed
        bytes32 messageHash = keccak256(abi.encode(
            update.channelId,
            update.oldStateRoot,
            update.newStateRoot,
            update.nonce
        ));
        
        // Add Ethereum Signed Message prefix
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        // Track signers to prevent duplicates
        address[] memory seenSigners = new address[](update.signers.length);
        uint256 seenCount = 0;
        
        // Verify each signature
        for(uint256 i = 0; i < update.participantSignatures.length; i++) {
            address signer = update.signers[i];
            
            // Check for duplicate signers
            for(uint256 k = 0; k < seenCount; k++) {
                if(seenSigners[k] == signer) {
                    revert Invalid__DuplicateSigner(signer);
                }
            }
            seenSigners[seenCount] = signer;
            seenCount++;
            
            // Verify signer is a participant
            bool isParticipant = false;
            for(uint256 j = 0; j < participants.length; j++) {
                if(participants[j] == signer) {
                    isParticipant = true;
                    break;
                }
            }
            if(!isParticipant) {
                revert Invalid__Signer(signer);
            }
            
            // Recover signer from signature
            address recoveredSigner = ethSignedMessageHash.recover(update.participantSignatures[i]);
            
            // Verify signature matches claimed signer
            if(recoveredSigner != signer) {
                revert Invalid__Signature(signer, i);
            }
        }
    }

    function updateVerifier(address _verifier) external onlyOwner {
        if(_verifier == address(0)) {
            revert Invalid__Verifier();
        }
        address oldVerifier = address(verifier);
        verifier = Verifier(_verifier);
        emit VerifierUpdated(oldVerifier, _verifier);
    }
    
    function updateChannelRegistry(address _channelRegistry) external onlyOwner {
        if(_channelRegistry == address(0)) {
            revert Invalid__ChannelRegistry();
        }
        channelRegistry = IChannelRegistry(_channelRegistry);
    }

    // View functions
    function getChannelState(bytes32 channelId) external view returns (bytes32 stateRoot, uint256 nonce) {
        return (channelStateRoots[channelId], channelNonces[channelId]);
    }
}