// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IChannelRegistry {
    // Enums
    enum ChannelStatus {
        INACTIVE,
        ACTIVE,
        CLOSING,
        CLOSED
    }

    // Structs
    struct ChannelInfo {
        address leader;
        address[] participants;
        uint256 signatureThreshold;
        bytes32 currentStateRoot;
        uint256 nonce;
        uint256 lastUpdateBlock;
        uint256 lastUpdateTimestamp;
        ChannelStatus status;
        uint256 challengePeriod;
    }

    struct ParticipantInfo {
        bool isActive;
        uint256 stake;
        bytes32 commitment;
        uint256 joinedAt;
        bool hasExited;
    }
    // Note: individual token balances are now stored in Merkle tree off-chain

    struct LeaderBond {
        uint256 amount;
        uint256 lockPeriod;
        uint256 bondedAt;
        uint256 slashingHistory;
    }

    struct ChannelCreationParams {
        address leader;
        address[] preApprovedParticipants;
        bytes32[] participantCommitments;
        uint256 signatureThreshold;
        bytes32 initialStateRoot;
        bytes32 initialBalanceRoot; // New: initial Merkle root of balances
        uint256 challengePeriod;
        uint256 minimumStake;
    }

    struct BalanceUpdate {
        address participant;
        address token;
        uint256 newBalance;
    }

    struct TokenDeposit {
        address token;
        uint256 amount;
    }

    // Events
    event ChannelCreated(bytes32 indexed channelId, address indexed leader);
    event ChannelCreatedWithParams(bytes32 indexed channelId, ChannelCreationParams params);
    event ParticipantAdded(bytes32 indexed channelId, address indexed participant);
    event ParticipantRemoved(bytes32 indexed channelId, address indexed participant);
    event ChannelStatusUpdated(bytes32 indexed channelId, ChannelStatus oldStatus, ChannelStatus newStatus);
    event LeadershipTransferred(bytes32 indexed channelId, address indexed oldLeader, address indexed newLeader);
    event ChannelDeleted(bytes32 indexed channelId);
    event VerifierUpdated(address indexed newVerifier);
    event ClosingManagerUpdated(address indexed newClosingManager);
    event LeaderBonded(address indexed leader, uint256 amount);
    event LeaderSlashed(address indexed leader, uint256 amount, bytes32 reason);
    event ParticipantStaked(bytes32 indexed channelId, address indexed participant, uint256 amount);
    event CommitmentRevealed(bytes32 indexed channelId, address indexed participant, bytes32 commitment);
    event TokenSupported(bytes32 indexed channelId, address indexed token);
    event TokenDeposited(bytes32 indexed channelId, address indexed participant, address indexed token, uint256 amount);
    event TokenWithdrawn(bytes32 indexed channelId, address indexed participant, address indexed token, uint256 amount);
    event BalancesUpdated(bytes32 indexed channelId, BalanceUpdate[] updates);
    event BalanceRootUpdated(bytes32 indexed channelId, bytes32 oldRoot, bytes32 newRoot);
    event EmergencyWithdrawal(
        bytes32 indexed channelId, address indexed participant, address indexed token, uint256 amount
    );

    // Errors
    error Channel__NotLeader();
    error Channel__DoesNotExist();
    error Channel__AlreadyExists();
    error Channel__InvalidLeader();
    error Channel__InvalidStatus();
    error Channel__NotVerifier();
    error Channel_NotClosingManager();
    error Channel__NotAuthorized();
    error Channel__ParticipantAlreadyAdded();
    error Channel__ParticipantNotFound();
    error Channel__TooManyParticipants();
    error Channel__CannotCloseChannel();
    error Channel_AunauthorizedStatusTransition();
    error Channel__InsufficientLeaderBond();
    error Channel__InsufficientParticipantStake();
    error Channel__InvalidCommitment();
    error Channel__DuplicateParticipant();

    // Functions
    function createChannel(address _leader) external returns (bytes32 channelId);
    function createChannelWithParams(ChannelCreationParams calldata params, address[] calldata supportedTokens)
        external
        payable
        returns (bytes32 channelId);
    function updateChannelStatus(bytes32 _channelId, ChannelStatus _status) external;
    function transferLeadership(bytes32 _channelId, address _newLeader) external;
    function closeChannel(bytes32 _channelId) external;
    function updateStateRoot(bytes32 _channelId, bytes32 _newStateRoot) external;
    function getChannelInfo(bytes32 channelId) external view returns (ChannelInfo memory);
    function getCurrentStateRoot(bytes32 _channelId) external view returns (bytes32);
    function getLeaderAddress(bytes32 _channelId) external view returns (address);
    function setStateTransitionVerifier(address _verifier) external;
    function setClosingManager(address _closingManager) external;
    function setDisputeResolver(address _disputeResolver) external;
    function bondAsLeader() external payable;
    function withdrawLeaderBond() external;
    function stakeAsParticipant(bytes32 channelId, bytes32 nonce) external payable;
    function depositToken(bytes32 channelId, address token, uint256 amount) external;
    function depositETH(bytes32 channelId) external payable;

    // Merkle-based functions
    function updateBalanceRoot(bytes32 channelId, bytes32 newBalanceRoot) external;
    function withdrawWithProof(bytes32 channelId, address token, uint256 amount, bytes32[] calldata merkleProof)
        external;
    function getChannelBalanceRoot(bytes32 channelId) external view returns (bytes32);
    function hasParticipantWithdrawn(bytes32 channelId, address participant, address token)
        external
        view
        returns (bool);

    // Other functions
    function slashLeader(address leader, uint256 amount, bytes32 reason) external;
    function exitChannel(bytes32 channelId) external;
    function getParticipantInfo(bytes32 channelId, address participant)
        external
        view
        returns (ParticipantInfo memory);
    function getLeaderBond(address leader) external view returns (LeaderBond memory);
    function getTotalChannelDeposits(bytes32 channelId) external view returns (uint256);
    function getParticipantTokenBalance(bytes32 channelId, address participant, address token)
        external
        view
        returns (uint256);
    function getChannelTokenBalance(bytes32 channelId, address token) external view returns (uint256);
    function getSupportedTokens(bytes32 channelId) external view returns (address[] memory);
    function isTokenSupportedInChannel(bytes32 channelId, address token) external view returns (bool);
    function getParticipantAllBalances(bytes32 channelId, address participant)
        external
        view
        returns (TokenDeposit[] memory);
    function isChannelParticipant(bytes32 channelId, address participant) external view returns (bool);
    function getActiveParticipantCount(bytes32 channelId) external view returns (uint256);
}
