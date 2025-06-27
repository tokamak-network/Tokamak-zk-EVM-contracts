// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IChannelRegistry} from "./interface/IChannelRegistry.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";

contract ChannelRegistry is IChannelRegistry, Ownable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // State variables
    mapping(bytes32 => ChannelInfo) private channels;
    mapping(bytes32 => mapping(address => ParticipantInfo)) private participantDetails;
    mapping(address => LeaderBond) private leaderBonds;

    // New Merkle-based balance tracking
    mapping(bytes32 => bytes32) private channelStateRoots;
    mapping(bytes32 => mapping(address => mapping(address => bool))) private hasWithdrawn; // channelId => participant => token => withdrawn

    // Channel deposits and configuration
    mapping(bytes32 => uint256) private channelDeposits;
    mapping(bytes32 => uint256) private minimumStakeRequired;
    mapping(bytes32 => address[]) private channelSupportedTokens;
    mapping(bytes32 => mapping(address => bool)) private isTokenSupported;
    mapping(bytes32 => mapping(address => uint256)) private channelTokenBalances; // Total deposited per token

    uint256 private channelCounter;
    address private verifier;
    address private closingManager;

    // Constants
    uint256 public constant MAX_PARTICIPANTS = 100;
    uint256 public constant MIN_LEADER_BOND = 1 ether;
    uint256 public constant MIN_PARTICIPANT_STAKE = 0.1 ether;
    uint256 public constant DEFAULT_CHALLENGE_PERIOD = 7 days;
    uint256 public constant BOND_LOCK_PERIOD = 30 days;
    uint256 public constant MAX_SUPPORTED_TOKENS = 10;
    address public constant ETH_TOKEN_ADDRESS = address(0);

    modifier onlyChannelLeader(bytes32 channelId) {
        if (channels[channelId].leader != msg.sender) {
            revert Channel__NotLeader();
        }
        _;
    }

    modifier channelExists(bytes32 channelId) {
        if (channels[channelId].leader == address(0)) {
            revert Channel__DoesNotExist();
        }
        _;
    }

    modifier onlyVerifier() {
        if (msg.sender != verifier) {
            revert Channel__NotVerifier();
        }
        _;
    }

    modifier onlyClosingManager() {
        if (msg.sender != closingManager) {
            revert Channel_NotClosingManager();
        }
        _;
    }

    modifier hasStaked(bytes32 channelId) {
        ParticipantInfo storage participant = participantDetails[channelId][msg.sender];
        require(participant.isActive, "Not an active participant");
        require(participant.stake > 0, "Must stake before participating");
        _;
    }

    constructor() Ownable(msg.sender) {}

    // Setup functions
    function setStateTransitionVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;
        emit VerifierUpdated(_verifier);
    }

    function setClosingManager(address _closingManager) external onlyOwner {
        closingManager = _closingManager;
        emit ClosingManagerUpdated(_closingManager);
    }

    // Leader bonding mechanism
    function bondAsLeader() external payable {
        if (msg.value < MIN_LEADER_BOND) {
            revert Channel__InsufficientLeaderBond();
        }

        LeaderBond storage bond = leaderBonds[msg.sender];
        bond.amount += msg.value;
        bond.lockPeriod = BOND_LOCK_PERIOD;
        bond.bondedAt = block.timestamp;

        emit LeaderBonded(msg.sender, msg.value);
    }

    function withdrawLeaderBond() external {
        LeaderBond storage bond = leaderBonds[msg.sender];
        require(bond.amount > 0, "No bond to withdraw");
        require(block.timestamp >= bond.bondedAt + bond.lockPeriod, "Bond still locked");

        uint256 amount = bond.amount;
        bond.amount = 0;

        payable(msg.sender).transfer(amount);
    }

    // Channel creation
    function createChannelWithParams(ChannelCreationParams calldata params, address[] calldata supportedTokens)
        external
        payable
        returns (bytes32 channelId)
    {
        // Validate leader has sufficient bond
        if (leaderBonds[params.leader].amount < MIN_LEADER_BOND) {
            revert Channel__InsufficientLeaderBond();
        }

        // Validate parameters
        require(params.preApprovedParticipants.length > 0, "Must have participants");
        require(params.preApprovedParticipants.length <= MAX_PARTICIPANTS, "Too many participants");
        require(params.participantCommitments.length == params.preApprovedParticipants.length, "Commitment mismatch");
        require(
            params.signatureThreshold > 0 && params.signatureThreshold <= params.preApprovedParticipants.length,
            "Invalid threshold"
        );
        require(supportedTokens.length <= MAX_SUPPORTED_TOKENS, "Too many supported tokens");

        // Generate unique channel ID
        channelId =
            keccak256(abi.encode(params.leader, channelCounter, block.timestamp, params.preApprovedParticipants));
        channelCounter++;

        // Check channel doesn't already exist
        if (channels[channelId].leader != address(0)) {
            revert Channel__AlreadyExists();
        }

        // Validate no duplicate participants
        for (uint256 i = 0; i < params.preApprovedParticipants.length; i++) {
            for (uint256 j = i + 1; j < params.preApprovedParticipants.length; j++) {
                if (params.preApprovedParticipants[i] == params.preApprovedParticipants[j]) {
                    revert Channel__DuplicateParticipant();
                }
            }
        }

        // Initialize channel
        ChannelInfo storage channel = channels[channelId];
        channel.leader = params.leader;
        channel.currentStateRoot = params.initialStateRoot;
        channel.signatureThreshold = params.signatureThreshold;
        channel.nonce = 0;
        channel.lastUpdateBlock = block.number;
        channel.lastUpdateTimestamp = block.timestamp;
        channel.status = ChannelStatus.ACTIVE;
        channel.challengePeriod = params.challengePeriod > 0 ? params.challengePeriod : DEFAULT_CHALLENGE_PERIOD;

        // Add all pre-approved participants
        for (uint256 i = 0; i < params.preApprovedParticipants.length; i++) {
            address participant = params.preApprovedParticipants[i];
            require(participant != address(0), "Invalid participant");

            channel.participants.push(participant);

            // Store participant details with commitment
            participantDetails[channelId][participant] = ParticipantInfo({
                isActive: true,
                stake: 0,
                commitment: params.participantCommitments[i],
                joinedAt: block.timestamp,
                hasExited: false
            });
        }

        // Store minimum stake requirement and initialize deposits
        minimumStakeRequired[channelId] = params.minimumStake;
        channelDeposits[channelId] = 0;

        // Setup supported tokens (ETH is always supported)
        channelSupportedTokens[channelId].push(ETH_TOKEN_ADDRESS);
        isTokenSupported[channelId][ETH_TOKEN_ADDRESS] = true;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            require(token != address(0), "Invalid token address");
            require(!isTokenSupported[channelId][token], "Duplicate token");

            channelSupportedTokens[channelId].push(token);
            isTokenSupported[channelId][token] = true;
            emit TokenSupported(channelId, token);
        }

        emit ChannelCreatedWithParams(channelId, params);
        emit ChannelCreated(channelId, params.leader);
    }

    // Participant staking
    function stakeAsParticipant(bytes32 channelId, bytes32 nonce) external payable channelExists(channelId) {
        ParticipantInfo storage participant = participantDetails[channelId][msg.sender];

        require(participant.isActive, "Not an approved participant");
        require(participant.stake == 0, "Already staked");

        bytes32 expectedCommitment = keccak256(abi.encode(msg.sender, nonce));
        if (participant.commitment != expectedCommitment) {
            revert Channel__InvalidCommitment();
        }

        uint256 requiredStake = minimumStakeRequired[channelId];
        if (msg.value < requiredStake) {
            revert Channel__InsufficientParticipantStake();
        }

        participant.stake = msg.value;
        channelDeposits[channelId] += msg.value;

        emit ParticipantStaked(channelId, msg.sender, msg.value);
        emit CommitmentRevealed(channelId, msg.sender, expectedCommitment);
    }

    // Token deposit functions - deposits are tracked globally, not per participant
    function depositToken(bytes32 channelId, address token, uint256 amount)
        external
        channelExists(channelId)
        hasStaked(channelId)
    {
        ParticipantInfo storage participant = participantDetails[channelId][msg.sender];
        require(participant.isActive, "Not an active participant");
        require(isTokenSupported[channelId][token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");

        if (token == ETH_TOKEN_ADDRESS) {
            revert("Use depositETH for ETH deposits");
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        channelTokenBalances[channelId][token] += amount;

        emit TokenDeposited(channelId, msg.sender, token, amount);
    }

    function depositETH(bytes32 channelId) external payable channelExists(channelId) hasStaked(channelId) {
        ParticipantInfo storage participant = participantDetails[channelId][msg.sender];
        require(participant.isActive, "Not an active participant");
        require(msg.value > 0, "Amount must be greater than 0");

        channelTokenBalances[channelId][ETH_TOKEN_ADDRESS] += msg.value;

        emit TokenDeposited(channelId, msg.sender, ETH_TOKEN_ADDRESS, msg.value);
    }

    // New Merkle-based balance update - O(1) gas cost!
    function updateStateRoot(bytes32 channelId, bytes32 newStateRoot) external onlyVerifier channelExists(channelId) {
        bytes32 oldRoot = channelStateRoots[channelId];
        channelStateRoots[channelId] = newStateRoot;

        emit BalanceRootUpdated(channelId, oldRoot, newStateRoot);
    }

    function withdrawWithProof(
        bytes32 channelId,
        address token,
        uint256 amount,
        TokenBalance[] calldata allBalances, // All balances for this participant
        bytes32[] calldata merkleProof
    ) external channelExists(channelId) hasStaked(channelId) {
        ChannelInfo storage channel = channels[channelId];
        require(
            channel.status == ChannelStatus.CLOSING || channel.status == ChannelStatus.CLOSED,
            "Channel not in withdrawal phase"
        );

        // Verify the participant is withdrawing their own balance
        require(allBalances.length > 0, "No balances provided");

        // Find the specific token balance
        uint256 tokenIndex = type(uint256).max;
        for (uint256 i = 0; i < allBalances.length; i++) {
            if (allBalances[i].token == token) {
                require(allBalances[i].amount == amount, "Amount mismatch");
                tokenIndex = i;
                break;
            }
        }
        require(tokenIndex != type(uint256).max, "Token not found in balances");

        // Check if already withdrawn
        require(!hasWithdrawn[channelId][msg.sender][token], "Already withdrawn");

        // Compute leaf from all balances
        bytes32 leaf = keccak256(abi.encode(msg.sender, allBalances));

        // Verify Merkle proof
        require(MerkleProof.verify(merkleProof, channelStateRoots[channelId], leaf), "Invalid balance proof");

        hasWithdrawn[channelId][msg.sender][token] = true;
        channelTokenBalances[channelId][token] -= amount;

        if (token == ETH_TOKEN_ADDRESS) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit TokenWithdrawn(channelId, msg.sender, token, amount);
    }

    // Slashing mechanism - can slash participants who haven't staked
    function slashNonStakedParticipant(bytes32 channelId, address participant) external channelExists(channelId) {
        ParticipantInfo storage participantInfo = participantDetails[channelId][participant];

        // Check if participant should have staked but didn't
        require(participantInfo.isActive, "Not an active participant");
        require(participantInfo.stake == 0, "Participant has staked");
        require(block.timestamp > participantInfo.joinedAt + 7 days, "Grace period not over");

        // Deactivate the participant
        participantInfo.isActive = false;

        emit ParticipantSlashed(channelId, participant);
    }

    // Participant exit mechanism
    function exitChannel(bytes32 channelId) external channelExists(channelId) {
        ChannelInfo storage channel = channels[channelId];

        require(
            channel.status == ChannelStatus.CLOSING || channel.status == ChannelStatus.CLOSED,
            "Can only exit during channel closure"
        );

        ParticipantInfo storage participant = participantDetails[channelId][msg.sender];
        require(participant.isActive, "Not an active participant");
        require(!participant.hasExited, "Already exited");

        participant.hasExited = true;
        participant.isActive = false;

        if (participant.stake > 0) {
            uint256 stakeToReturn = participant.stake;
            participant.stake = 0;
            payable(msg.sender).transfer(stakeToReturn);
        }
    }

    // Channel status management
    function updateChannelStatus(bytes32 _channelId, ChannelStatus _status)
        external
        channelExists(_channelId)
        onlyChannelLeader(_channelId)
    {
        ChannelInfo storage channel = channels[_channelId];
        ChannelStatus oldStatus = channel.status;

        if (!_isValidStatusTransition(oldStatus, _status)) {
            revert Channel__InvalidStatus();
        }

        if (_status == ChannelStatus.CLOSED) {
            revert Channel_AunauthorizedStatusTransition();
        }

        channel.status = _status;
        channel.lastUpdateBlock = block.number;
        channel.lastUpdateTimestamp = block.timestamp;

        emit ChannelStatusUpdated(_channelId, oldStatus, _status);
    }

    function transferLeadership(bytes32 _channelId, address _newLeader)
        external
        channelExists(_channelId)
        onlyChannelLeader(_channelId)
    {
        if (_newLeader == address(0)) {
            revert Channel__InvalidLeader();
        }

        if (leaderBonds[_newLeader].amount < MIN_LEADER_BOND) {
            revert Channel__InsufficientLeaderBond();
        }

        ChannelInfo storage channel = channels[_channelId];
        address oldLeader = channel.leader;

        ParticipantInfo storage newLeaderInfo = participantDetails[_channelId][_newLeader];
        require(newLeaderInfo.isActive, "New leader must be an active participant");

        channel.leader = _newLeader;
        channel.lastUpdateBlock = block.number;
        channel.lastUpdateTimestamp = block.timestamp;

        emit LeadershipTransferred(_channelId, oldLeader, _newLeader);
    }

    function closeChannel(bytes32 _channelId) external channelExists(_channelId) onlyClosingManager {
        ChannelInfo storage channel = channels[_channelId];

        if (channel.status != ChannelStatus.CLOSING && channel.status != ChannelStatus.CLOSED) {
            revert Channel__CannotCloseChannel();
        }

        // Ensure all funds have been withdrawn or sufficient time has passed
        require(
            _isChannelEmpty(_channelId) || block.timestamp > channel.lastUpdateTimestamp + 90 days,
            "Channel still has funds or waiting period not met"
        );

        // Return remaining stakes to participants who haven't exited
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i];
            ParticipantInfo storage participantInfo = participantDetails[_channelId][participant];

            if (participantInfo.stake > 0 && !participantInfo.hasExited) {
                uint256 stakeToReturn = participantInfo.stake;
                participantInfo.stake = 0;
                payable(participant).transfer(stakeToReturn);
            }

            delete participantDetails[_channelId][participant];
        }

        // Clean up storage
        delete channelSupportedTokens[_channelId];
        delete channels[_channelId];
        delete channelDeposits[_channelId];
        delete minimumStakeRequired[_channelId];
        delete channelStateRoots[_channelId];

        emit ChannelDeleted(_channelId);
    }

    // View functions
    function getChannelInfo(bytes32 channelId) external view returns (ChannelInfo memory) {
        ChannelInfo storage channel = channels[channelId];

        if (channel.leader == address(0)) {
            revert Channel__DoesNotExist();
        }

        return ChannelInfo({
            leader: channel.leader,
            participants: channel.participants,
            signatureThreshold: channel.signatureThreshold,
            currentStateRoot: channel.currentStateRoot,
            nonce: channel.nonce,
            lastUpdateBlock: channel.lastUpdateBlock,
            lastUpdateTimestamp: channel.lastUpdateTimestamp,
            status: channel.status,
            challengePeriod: channel.challengePeriod
        });
    }

    function getParticipantInfo(bytes32 channelId, address participant)
        external
        view
        returns (ParticipantInfo memory)
    {
        return participantDetails[channelId][participant];
    }

    function getLeaderBond(address leader) external view returns (LeaderBond memory) {
        return leaderBonds[leader];
    }

    function getTotalChannelDeposits(bytes32 channelId) external view returns (uint256) {
        return channelDeposits[channelId];
    }

    function getChannelStateRoot(bytes32 channelId) external view returns (bytes32) {
        return channelStateRoots[channelId];
    }

    function hasParticipantWithdrawn(bytes32 channelId, address participant, address token)
        external
        view
        returns (bool)
    {
        return hasWithdrawn[channelId][participant][token];
    }

    function getChannelTokenBalance(bytes32 channelId, address token) external view returns (uint256) {
        return channelTokenBalances[channelId][token];
    }

    function getSupportedTokens(bytes32 channelId) external view returns (address[] memory) {
        return channelSupportedTokens[channelId];
    }

    function isTokenSupportedInChannel(bytes32 channelId, address token) external view returns (bool) {
        return isTokenSupported[channelId][token];
    }

    function isChannelParticipant(bytes32 channelId, address participant) external view returns (bool) {
        return participantDetails[channelId][participant].isActive;
    }

    function hasParticipantStaked(bytes32 channelId, address participant) external view returns (bool) {
        return participantDetails[channelId][participant].stake > 0;
    }

    function getActiveParticipantCount(bytes32 channelId) external view returns (uint256) {
        ChannelInfo storage channel = channels[channelId];
        uint256 count = 0;
        for (uint256 i = 0; i < channel.participants.length; i++) {
            if (participantDetails[channelId][channel.participants[i]].isActive) {
                count++;
            }
        }
        return count;
    }

    // Get count of participants who have actually staked
    function getStakedParticipantCount(bytes32 channelId) external view returns (uint256) {
        ChannelInfo storage channel = channels[channelId];
        uint256 count = 0;
        for (uint256 i = 0; i < channel.participants.length; i++) {
            ParticipantInfo storage participant = participantDetails[channelId][channel.participants[i]];
            if (participant.isActive && participant.stake > 0) {
                count++;
            }
        }
        return count;
    }

    // Internal functions
    function _isValidStatusTransition(ChannelStatus from, ChannelStatus to) internal pure returns (bool) {
        if (from == ChannelStatus.INACTIVE) {
            return to == ChannelStatus.ACTIVE;
        } else if (from == ChannelStatus.ACTIVE) {
            return to == ChannelStatus.CLOSING || to == ChannelStatus.INACTIVE;
        } else if (from == ChannelStatus.CLOSING) {
            return to == ChannelStatus.CLOSED || to == ChannelStatus.ACTIVE;
        } else if (from == ChannelStatus.CLOSED) {
            return false;
        }
        return false;
    }

    function _isChannelEmpty(bytes32 channelId) internal view returns (bool) {
        address[] memory tokens = channelSupportedTokens[channelId];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (channelTokenBalances[channelId][tokens[i]] > 0) {
                return false;
            }
        }
        return true;
    }

    function getCurrentStateRoot(bytes32 _channelId) external view returns (bytes32) {
        return channels[_channelId].currentStateRoot;
    }

    function getLeaderAddress(bytes32 _channelId) external view returns (address) {
        return channels[_channelId].leader;
    }

    // Emergency functions
    receive() external payable {
        // Allow contract to receive ETH for bonding and staking
    }

    function emergencyWithdraw() external onlyOwner {
        // Emergency withdrawal function (should be governed by timelock in production)
        payable(owner()).transfer(address(this).balance);
    }
}
