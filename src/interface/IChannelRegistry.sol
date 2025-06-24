pragma solidity 0.8.23;

interface IChannelRegistry {
    enum ChannelStatus {
        INACTIVE,
        ACTIVE,
        CLOSING,
        CLOSED
    }

    struct ChannelInfo {
        address leader;
        address[] participants;
        uint256 signatureThreshold;
        bytes32 currentStateRoot;
        uint256 nonce;
        uint256 lastUpdateBlock;
        uint256 lastUpdateTimestamp;
        ChannelStatus status;
    }

    // Events
    event ChannelCreated(bytes32 indexed channelId, address indexed leader);

    event ParticipantAdded(bytes32 indexed channelId, address indexed participant);

    event ChannelStatusUpdated(bytes32 indexed channelId, ChannelStatus oldStatus, ChannelStatus newStatus);

    event LeadershipTransferred(bytes32 indexed channelId, address indexed oldLeader, address indexed newLeader);

    event VerifierUpdated(address verifier);

    event ClosingManagerUpdated(address closingManager);

    event ChannelDeleted(bytes32 indexed channelId);

    // Custom errors
    error Channel__AlreadyExists();
    error Channel__DoesNotExist();
    error Channel__NotLeader();
    error Channel__InvalidLeader();
    error Channel__InvalidParticipant();
    error Channel__ParticipantAlreadyExists();
    error Channel__CannotDeleteChannel();
    error Channel__InvalidStatus();
    error Channel__MaxParticipantsReached();
    error Channel__NotVerifier();
    error Channel_NotClosingManager();
    error Channel_AunauthorizedStatusTransition();

    function addParticipant(bytes32 channelId, address _user) external returns (bool);

    function createChannel(address _leader) external returns (bytes32 channelId);

    function updateChannelStatus(bytes32 _channelId, ChannelStatus _status) external;

    function transferLeadership(bytes32 _channelId, address _newLeader) external;

    function deleteChannel(bytes32 _channelId) external;

    function setSignatureThreshold(bytes32 channelId, uint256 threshold) external;

    function updateStateRoot(bytes32 _channelId, bytes32 _newStateRoot) external;

    function setStateTransitionVerifier(address verifier) external;

    function setClosingManager(address closingManager) external;

    function isChannelParticipant(bytes32 channelId, address participant) external view returns (bool);

    function getChannelInfo(bytes32 channelId) external view returns (ChannelInfo memory);

    function getParticipantCount(bytes32 channelId) external view returns (uint256);

    function getCurrentStateRoot(bytes32 _channelId) external view returns (bytes32);

    function getLeaderAddress(bytes32 _channelId) external view returns (address);
}
