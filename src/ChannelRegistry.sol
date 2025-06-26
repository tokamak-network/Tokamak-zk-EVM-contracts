// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IChannelRegistry} from "./interface/IChannelRegistry.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract ChannelRegistry is IChannelRegistry, Ownable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // State variables
    mapping(bytes32 => ChannelInfo) private channels;
    mapping(bytes32 => mapping(address => ParticipantInfo)) private participantDetails;
    mapping(address => LeaderBond) private leaderBonds;
    mapping(bytes32 => uint256) private channelDeposits;
    mapping(bytes32 => uint256) private minimumStakeRequired;
    mapping(bytes32 => address[]) private channelSupportedTokens;
    mapping(bytes32 => mapping(address => bool)) private isTokenSupported;
    mapping(bytes32 => mapping(address => uint256)) private channelTokenBalances;

    // Separate mapping for participant token balances
    mapping(bytes32 => mapping(address => mapping(address => uint256))) private participantTokenBalances;

    uint256 private channelCounter;
    address private verifier;
    address private closingManager;
    address private disputeResolver;

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

    modifier onlyDisputeResolver() {
        if (msg.sender != disputeResolver) {
            revert Channel__NotAuthorized();
        }
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

    function setDisputeResolver(address _disputeResolver) external onlyOwner {
        disputeResolver = _disputeResolver;
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

    // Token deposit functions
    function depositToken(bytes32 channelId, address token, uint256 amount) external channelExists(channelId) {
        ParticipantInfo storage participant = participantDetails[channelId][msg.sender];
        require(participant.isActive, "Not an active participant");
        require(isTokenSupported[channelId][token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");

        if (token == ETH_TOKEN_ADDRESS) {
            revert("Use depositETH for ETH deposits");
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Update balances using separate mapping
        participantTokenBalances[channelId][msg.sender][token] += amount;
        channelTokenBalances[channelId][token] += amount;

        emit TokenDeposited(channelId, msg.sender, token, amount);
    }

    function depositETH(bytes32 channelId) external payable channelExists(channelId) {
        ParticipantInfo storage participant = participantDetails[channelId][msg.sender];
        require(participant.isActive, "Not an active participant");
        require(msg.value > 0, "Amount must be greater than 0");

        // Update balances using separate mapping
        participantTokenBalances[channelId][msg.sender][ETH_TOKEN_ADDRESS] += msg.value;
        channelTokenBalances[channelId][ETH_TOKEN_ADDRESS] += msg.value;

        emit TokenDeposited(channelId, msg.sender, ETH_TOKEN_ADDRESS, msg.value);
    }

    // Balance update function
    function updateParticipantBalances(bytes32 channelId, BalanceUpdate[] calldata updates)
        external
        onlyVerifier
        channelExists(channelId)
    {
        for (uint256 i = 0; i < updates.length; i++) {
            BalanceUpdate memory update = updates[i];
            ParticipantInfo storage participant = participantDetails[channelId][update.participant];

            require(participant.isActive || participant.hasExited, "Invalid participant");
            require(isTokenSupported[channelId][update.token], "Token not supported");

            // Update participant balance using separate mapping
            uint256 oldBalance = participantTokenBalances[channelId][update.participant][update.token];
            participantTokenBalances[channelId][update.participant][update.token] = update.newBalance;

            // Update channel total balance
            if (update.newBalance > oldBalance) {
                channelTokenBalances[channelId][update.token] += (update.newBalance - oldBalance);
            } else {
                channelTokenBalances[channelId][update.token] -= (oldBalance - update.newBalance);
            }
        }

        emit BalancesUpdated(channelId, updates);
    }

    // Withdrawal function
    function withdrawTokens(bytes32 channelId, address token, uint256 amount) external channelExists(channelId) {
        ChannelInfo storage channel = channels[channelId];
        require(
            channel.status == ChannelStatus.CLOSING || channel.status == ChannelStatus.CLOSED, "Channel not closing"
        );

        uint256 balance = participantTokenBalances[channelId][msg.sender][token];
        require(balance >= amount, "Insufficient balance");

        // Update balances
        participantTokenBalances[channelId][msg.sender][token] -= amount;
        channelTokenBalances[channelId][token] -= amount;

        // Transfer tokens
        if (token == ETH_TOKEN_ADDRESS) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit TokenWithdrawn(channelId, msg.sender, token, amount);
    }

    // Slashing mechanism
    function slashLeader(address leader, uint256 amount, bytes32 reason) external onlyDisputeResolver {
        LeaderBond storage bond = leaderBonds[leader];
        require(bond.amount >= amount, "Insufficient bond to slash");

        bond.amount -= amount;
        bond.slashingHistory += amount;

        payable(disputeResolver).transfer(amount);

        emit LeaderSlashed(leader, amount, reason);
    }

    // Legacy create function
    function createChannel(address _leader) external onlyOwner returns (bytes32 channelId) {
        require(false, "Use createChannelWithParams instead");
    }

    // Participant management
    function addParticipant(bytes32 channelId, address _user)
        external
        channelExists(channelId)
        onlyChannelLeader(channelId)
        returns (bool)
    {
        revert("Participants must be pre-approved during channel creation");
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

    function deleteChannel(bytes32 _channelId) external channelExists(_channelId) onlyClosingManager {
        ChannelInfo storage channel = channels[_channelId];

        if (channel.status != ChannelStatus.CLOSING && channel.status != ChannelStatus.CLOSED) {
            revert Channel__CannotDeleteChannel();
        }

        // Return remaining stakes and token balances to participants
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i];
            ParticipantInfo storage participantInfo = participantDetails[_channelId][participant];

            if (participantInfo.stake > 0 && !participantInfo.hasExited) {
                uint256 stakeToReturn = participantInfo.stake;
                participantInfo.stake = 0;
                payable(participant).transfer(stakeToReturn);
            }

            // Return all token balances
            address[] memory tokens = channelSupportedTokens[_channelId];
            for (uint256 j = 0; j < tokens.length; j++) {
                address token = tokens[j];
                uint256 balance = participantTokenBalances[_channelId][participant][token];

                if (balance > 0) {
                    participantTokenBalances[_channelId][participant][token] = 0;

                    if (token == ETH_TOKEN_ADDRESS) {
                        payable(participant).transfer(balance);
                    } else {
                        IERC20(token).safeTransfer(participant, balance);
                    }
                }
            }

            delete participantDetails[_channelId][participant];
        }

        delete channelSupportedTokens[_channelId];
        delete channels[_channelId];
        delete channelDeposits[_channelId];
        delete minimumStakeRequired[_channelId];

        emit ChannelDeleted(_channelId);
    }

    function updateStateRoot(bytes32 _channelId, bytes32 _newStateRoot) external onlyVerifier {
        channels[_channelId].currentStateRoot = _newStateRoot;
        channels[_channelId].nonce++;
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

    function getParticipantTokenBalance(bytes32 channelId, address participant, address token)
        external
        view
        returns (uint256)
    {
        return participantTokenBalances[channelId][participant][token];
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

    function getParticipantAllBalances(bytes32 channelId, address participant)
        external
        view
        returns (TokenDeposit[] memory)
    {
        address[] memory tokens = channelSupportedTokens[channelId];
        TokenDeposit[] memory balances = new TokenDeposit[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] =
                TokenDeposit({token: tokens[i], amount: participantTokenBalances[channelId][participant][tokens[i]]});
        }

        return balances;
    }

    function isChannelParticipant(bytes32 channelId, address participant) external view returns (bool) {
        return participantDetails[channelId][participant].isActive;
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
