// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IChannelRegistry {
    // Enhanced enums
    enum ChannelStatus {
        INACTIVE,
        ACTIVE,
        CLOSING,
        CLOSED
    }

    // Enhanced structs
    struct ChannelInfo {
        address leader;
        address[] participants;
        uint256 signatureThreshold;
        bytes32 currentStateRoot;
        uint256 nonce;
        uint256 lastUpdateBlock;
        uint256 lastUpdateTimestamp;
        ChannelStatus status;
        uint256 challengePeriod;  // New field
    }

    struct ChannelCreationParams {
        address leader;
        address[] preApprovedParticipants;
        uint256 minimumStake;
        bytes32[] participantCommitments;
        uint256 signatureThreshold;
        uint256 challengePeriod;
        bytes32 initialStateRoot;
    }

    struct ParticipantInfo {
        bool isActive;
        uint256 stake;
        bytes32 commitment;
        uint256 joinedAt;
        bool hasExited;
    }

    struct TokenDeposit {
        address token;
        uint256 amount;
    }

    struct BalanceUpdate {
        address participant;
        address token;
        uint256 newBalance;
    }

    struct LeaderBond {
        uint256 amount;
        uint256 lockPeriod;
        uint256 slashingHistory;
        uint256 bondedAt;
    }

    // Events
    event ChannelCreated(bytes32 indexed channelId, address indexed leader);
    event ChannelCreatedWithParams(bytes32 indexed channelId, ChannelCreationParams params);
    event ParticipantAdded(bytes32 indexed channelId, address indexed participant);
    event ParticipantStaked(bytes32 indexed channelId, address indexed participant, uint256 amount);
    event ChannelStatusUpdated(bytes32 indexed channelId, ChannelStatus oldStatus, ChannelStatus newStatus);
    event LeadershipTransferred(bytes32 indexed channelId, address indexed oldLeader, address indexed newLeader);
    event ChannelDeleted(bytes32 indexed channelId);
    event VerifierUpdated(address indexed newVerifier);
    event ClosingManagerUpdated(address indexed newClosingManager);
    event LeaderBonded(address indexed leader, uint256 amount);
    event LeaderSlashed(address indexed leader, uint256 amount, bytes32 reason);
    event CommitmentRevealed(bytes32 indexed channelId, address indexed participant, bytes32 commitment);
    event TokenDeposited(bytes32 indexed channelId, address indexed participant, address indexed token, uint256 amount);
    event TokenWithdrawn(bytes32 indexed channelId, address indexed participant, address indexed token, uint256 amount);
    event BalancesUpdated(bytes32 indexed channelId, BalanceUpdate[] updates);
    event TokenSupported(bytes32 indexed channelId, address indexed token);

    // Custom errors
    error Channel__NotLeader();
    error Channel__DoesNotExist();
    error Channel__AlreadyExists();
    error Channel__InvalidLeader();
    error Channel__InvalidParticipant();
    error Channel__ParticipantAlreadyExists();
    error Channel__MaxParticipantsReached();
    error Channel__InvalidStatus();
    error Channel__CannotDeleteChannel();
    error Channel__NotVerifier();
    error Channel_NotClosingManager();
    error Channel_AunauthorizedStatusTransition();
    error Channel__InsufficientLeaderBond();
    error Channel__InsufficientParticipantStake();
    error Channel__InvalidCommitment();
    error Channel__CommitmentAlreadyRevealed();
    error Channel__ParticipantMismatch();
    error Channel__DuplicateParticipant();
    error Channel__NotAuthorizedToSlash();
    error Channel__NotAuthorized();
    error Channel__TokenNotSupported();
    error Channel__MaxTokensReached();
    error Channel__InvalidTokenAmount();
    error Channel__InsufficientBalance();

    // Core functions
    function createChannelWithParams(
        ChannelCreationParams calldata params,
        address[] calldata supportedTokens
    ) external payable returns (bytes32 channelId);
    function bondAsLeader() external payable;
    function stakeAsParticipant(bytes32 channelId, bytes32 nonce) external payable;
    function exitChannel(bytes32 channelId) external;
    function slashLeader(address leader, uint256 amount, bytes32 reason) external;
    
    // Token functions
    function depositToken(bytes32 channelId, address token, uint256 amount) external;
    function depositETH(bytes32 channelId) external payable;
    function withdrawTokens(bytes32 channelId, address token, uint256 amount) external;
    function updateParticipantBalances(bytes32 channelId, BalanceUpdate[] calldata updates) external;
    
    // Legacy functions (deprecated)
    function createChannel(address _leader) external returns (bytes32 channelId);
    function addParticipant(bytes32 channelId, address _user) external returns (bool);
    
    // Management functions
    function updateChannelStatus(bytes32 _channelId, ChannelStatus _status) external;
    function transferLeadership(bytes32 _channelId, address _newLeader) external;
    function deleteChannel(bytes32 _channelId) external;
    function updateStateRoot(bytes32 _channelId, bytes32 _newStateRoot) external;
    
    // View functions
    function getChannelInfo(bytes32 channelId) external view returns (ChannelInfo memory);
    function getParticipantInfo(bytes32 channelId, address participant) external view returns (ParticipantInfo memory);
    function getLeaderBond(address leader) external view returns (LeaderBond memory);
    function getTotalChannelDeposits(bytes32 channelId) external view returns (uint256);
    function isChannelParticipant(bytes32 channelId, address participant) external view returns (bool);
    function getActiveParticipantCount(bytes32 channelId) external view returns (uint256);
    function getCurrentStateRoot(bytes32 _channelId) external view returns (bytes32);
    function getLeaderAddress(bytes32 _channelId) external view returns (address);
    
    // Token view functions
    function getParticipantTokenBalance(bytes32 channelId, address participant, address token) external view returns (uint256);
    function getChannelTokenBalance(bytes32 channelId, address token) external view returns (uint256);
    function getSupportedTokens(bytes32 channelId) external view returns (address[] memory);
    function isTokenSupportedInChannel(bytes32 channelId, address token) external view returns (bool);
    function getParticipantAllBalances(bytes32 channelId, address participant) external view returns (TokenDeposit[] memory);
}