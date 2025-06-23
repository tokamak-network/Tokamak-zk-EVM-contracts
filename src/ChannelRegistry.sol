// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IChannelRegistry} from "./interface/IChannelRegistry.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

contract ChannelRegistry is IChannelRegistry, Ownable {
    // State variables
    mapping(bytes32 => ChannelInfo) private channels;
    mapping(bytes32 => mapping(address => bool)) private isParticipant;
    mapping(bytes32 => mapping(bytes32 => uint256)) private stateApprovals;
    
    uint256 private channelCounter;
    address private verifier;

    // Constants
    uint256 public constant MAX_PARTICIPANTS = 100;
    uint256 public constant DEFAULT_SIGNATURE_THRESHOLD = 1;
    
    modifier onlyChannelLeader(bytes32 channelId) {
        if(channels[channelId].leader != msg.sender) {
            revert Channel__NotLeader();
        }
        _;
    }
    
    modifier channelExists(bytes32 channelId) {
        if(channels[channelId].leader == address(0)) {
            revert Channel__DoesNotExist();
        }
        _;
    }

    modifier onlyVerifier() {
        if(msg.sender != verifier) {
            revert Channel__NotVerifier();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setStateTransitionVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;
        emit VerifierUpdated(_verifier);
    }

    function createChannel(
        address _leader,
        bytes32 _initialStateRoot
    ) external onlyOwner returns (bytes32 channelId) {
        if(_leader == address(0)) {
            revert Channel__InvalidLeader();
        }
        
        // Generate unique channel ID
        channelId = keccak256(abi.encode(_leader, channelCounter, block.timestamp));
        channelCounter++;
        
        // Check channel doesn't already exist
        if(channels[channelId].leader != address(0)) {
            revert Channel__AlreadyExists();
        }
        
        // Initialize channel
        ChannelInfo storage channel = channels[channelId];
        channel.leader = _leader;
        channel.currentStateRoot = _initialStateRoot;
        channel.signatureThreshold = DEFAULT_SIGNATURE_THRESHOLD;
        channel.nonce = 0;
        channel.lastUpdateBlock = block.number;
        channel.lastUpdateTimestamp = block.timestamp;
        channel.status = ChannelStatus.ACTIVE;
        
        // Add leader as first participant
        channel.participants.push(_leader);
        isParticipant[channelId][_leader] = true;
        
        emit ChannelCreated(channelId, _leader, _initialStateRoot);
    }

    function addParticipant(
        bytes32 channelId,
        address _user
    ) external channelExists(channelId) onlyChannelLeader(channelId) returns (bool) {
        if(_user == address(0)) {
            revert Channel__InvalidParticipant();
        }
        
        if(isParticipant[channelId][_user]) {
            revert Channel__ParticipantAlreadyExists();
        }
        
        ChannelInfo storage channel = channels[channelId];
        
        if(channel.participants.length >= MAX_PARTICIPANTS) {
            revert Channel__MaxParticipantsReached();
        }
        
        // Add participant
        channel.participants.push(_user);
        isParticipant[channelId][_user] = true;
        
        // Update signature threshold if needed (e.g., require majority)
        uint256 newThreshold = (channel.participants.length + 1) / 2;
        if(newThreshold > channel.signatureThreshold) {
            channel.signatureThreshold = newThreshold;
        }
        
        emit ParticipantAdded(channelId, _user);
        
        return true;
    }

    function updateChannelStatus(
        bytes32 _channelId,
        ChannelStatus _status
    ) external channelExists(_channelId) onlyChannelLeader(_channelId) {
        ChannelInfo storage channel = channels[_channelId];
        ChannelStatus oldStatus = channel.status;
        
        // Validate status transition
        if(!_isValidStatusTransition(oldStatus, _status)) {
            revert Channel__InvalidStatus();
        }
        
        channel.status = _status;
        channel.lastUpdateBlock = block.number;
        channel.lastUpdateTimestamp = block.timestamp;
        
        emit ChannelStatusUpdated(_channelId, oldStatus, _status);
    }

    function transferLeadership(
        bytes32 _channelId,
        address _newLeader
    ) external channelExists(_channelId) onlyChannelLeader(_channelId) {
        if(_newLeader == address(0)) {
            revert Channel__InvalidLeader();
        }
        
        ChannelInfo storage channel = channels[_channelId];
        address oldLeader = channel.leader;
        
        // Ensure new leader is a participant
        if(!isParticipant[_channelId][_newLeader]) {
            // Add new leader as participant if not already
            if(channel.participants.length >= MAX_PARTICIPANTS) {
                revert Channel__MaxParticipantsReached();
            }
            channel.participants.push(_newLeader);
            isParticipant[_channelId][_newLeader] = true;
        }
        
        channel.leader = _newLeader;
        channel.lastUpdateBlock = block.number;
        channel.lastUpdateTimestamp = block.timestamp;
        
        emit LeadershipTransferred(_channelId, oldLeader, _newLeader);
    }

    function deleteChannel(
        bytes32 _channelId
    ) external channelExists(_channelId) onlyChannelLeader(_channelId) {
        ChannelInfo storage channel = channels[_channelId];
        
        // Only allow deletion of closed channels
        if(channel.status != ChannelStatus.CLOSED) {
            revert Channel__CannotDeleteActiveChannel();
        }
        
        // Clean up participants mapping
        for(uint256 i = 0; i < channel.participants.length; i++) {
            delete isParticipant[_channelId][channel.participants[i]];
        }
        
        // Delete channel
        delete channels[_channelId];
        
        emit ChannelDeleted(_channelId);
    }

    function getChannelInfo(bytes32 channelId) external view returns (ChannelInfo memory) {
        ChannelInfo storage channel = channels[channelId];
        
        if(channel.leader == address(0)) {
            revert Channel__DoesNotExist();
        }
        
        // Create memory copy to return
        ChannelInfo memory info = ChannelInfo({
            leader: channel.leader,
            participants: channel.participants,
            signatureThreshold: channel.signatureThreshold,
            currentStateRoot: channel.currentStateRoot,
            nonce: channel.nonce,
            lastUpdateBlock: channel.lastUpdateBlock,
            lastUpdateTimestamp: channel.lastUpdateTimestamp,
            status: channel.status
        });
        
        return info;
    }
    
    // Additional helper functions
    
    function setSignatureThreshold(
        bytes32 channelId,
        uint256 threshold
    ) external channelExists(channelId) onlyChannelLeader(channelId) {
        ChannelInfo storage channel = channels[channelId];
        
        // Threshold must be at least 1 and not more than participants
        require(threshold > 0 && threshold <= channel.participants.length, "Invalid threshold");
        
        channel.signatureThreshold = threshold;
    }
    
    function isChannelParticipant(
        bytes32 channelId,
        address participant
    ) external view returns (bool) {
        return isParticipant[channelId][participant];
    }
    
    function getParticipantCount(bytes32 channelId) external view returns (uint256) {
        return channels[channelId].participants.length;
    }
    
    function approveStateRoot(
        bytes32 channelId,
        bytes32 stateRoot
    ) external channelExists(channelId) {
        require(isParticipant[channelId][msg.sender], "Not a participant");
        
        stateApprovals[channelId][stateRoot]++;
    }
    
    function getStateApprovals(
        bytes32 channelId,
        bytes32 stateRoot
    ) external view returns (uint256) {
        return stateApprovals[channelId][stateRoot];
    }
    
    // Internal functions
    
    function _isValidStatusTransition(
        ChannelStatus from,
        ChannelStatus to
    ) internal pure returns (bool) {
        if(from == ChannelStatus.INACTIVE) {
            return to == ChannelStatus.ACTIVE;
        } else if(from == ChannelStatus.ACTIVE) {
            return to == ChannelStatus.CLOSING || to == ChannelStatus.INACTIVE;
        } else if(from == ChannelStatus.CLOSING) {
            return to == ChannelStatus.CLOSED || to == ChannelStatus.ACTIVE;
        } else if(from == ChannelStatus.CLOSED) {
            return false; // Cannot transition from CLOSED
        }
        return false;
    }

    function updateStateRoot(bytes32 _channelId, bytes32 _newStateRoot) external onlyVerifier {
        channels[_channelId].currentStateRoot = _newStateRoot;
    }

    function getCurrentStateRoot(bytes32 _channelId) external view returns(bytes32) {
        return channels[_channelId].currentStateRoot;
    }

    function getLeaderAddress(bytes32 _channelId) external view returns(address) {
        return channels[_channelId].leader;
    }
}