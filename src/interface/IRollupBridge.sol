// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IRollupBridge {
    // =========== STRUCTS ===========

    struct Signature {
        bytes32 R; // Compressed commitment point (R_bytes)
        uint256 S; // EdDSA signature scalar component (S_bytes as uint256)
    }

    struct User {
        address l1Address;
        address l2PublicKey;
    }

    struct ProofData {
        bytes32 aggregatedProofHash;
        bytes32 finalStateRoot;
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
        uint256 smax;
        bytes[] initialMPTLeaves;
        bytes[] finalMPTLeaves;
    }

    struct Channel {
        uint256 id;
        address targetContract;
        bytes32 initialStateRoot; // Root after initialization
        bytes32 finalStateRoot; // Root after closing
        // Participants
        User[] participants;
        mapping(address => address) l2PublicKeys; // L1 => L2 address mapping
        mapping(address => bool) isParticipant;
        // Deposits
        mapping(address => uint256) tokenDeposits; //  user => amount
        uint256 tokenTotalDeposits; // total deposited
        // Channel state
        ChannelState state;
        uint256 openTimestamp;
        uint256 closeTimestamp;
        uint256 timeout;
        address leader;
        // ZK Proof commitments
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
        // Closing process
        bytes32 aggregatedProofHash;
        uint256 requiredSignatures;
        uint256 receivedSignatures;
        mapping(address => bool) hasWithdrawn;
        // Group/threshold signature support
        bytes32 groupPublicKey;
        bytes[] initialMPTLeaves;
        bytes[] finalMPTLeaves;
    }

    // ============= ENUM =============

    enum ChannelState {
        None,
        Initialized,
        Open,
        Active,
        Closing,
        Closed
    }

    // ============ EVENTS ============

    event L2AddressAssigned(address indexed l1Address, address indexed l2Address);
    event ChannelOpened(uint256 indexed channelId, address indexed targetContract);
    event StateConverted(uint256 indexed channelId, bytes32[] zkRoots);
    event ProofAggregated(uint256 indexed channelId, bytes32 proofHash);
    event ChannelClosed(uint256 indexed channelId);
    event ChannelDeleted(uint256 indexed channelId);
    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event EmergencyWithdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event StateInitialized(uint256 indexed channelId, bytes32 currentStateRoot);
    event AggregatedProofSigned(
        uint256 indexed channelId, address indexed signer, uint256 signatureCount, uint256 requiredSignatures
    );

    // =========== FUNCTIONS ===========

    function authorizeCreator(address creator) external;

    function openChannel(
        address targetContract,
        address[] calldata participants,
        address[] calldata l2PublicKeys,
        uint128[] calldata preprocessedPart1,
        uint256[] calldata preprocessedPart2,
        uint256 timeout,
        bytes32 groupPublicKey
    ) external returns (uint256 channelId);

    function depositETH(uint256 _channelId) external payable;

    function depositToken(uint256 _channelId, address _token, uint256 _amount) external;

    function withdrawAfterClose(
        uint256 channelId,
        uint256 claimedBalance,
        uint256 leafIndex,
        bytes32[] calldata merkleProof
    ) external;

    function initializeChannelState(uint256 channelId) external;

    function submitAggregatedProof(uint256 channelId, ProofData calldata proofData) external;

    function signAggregatedProof(uint256 channelId, Signature[] calldata signatures) external;

    function closeChannel(uint256 channelId) external;

    function getChannelInfo(uint256 channelId)
        external
        view
        returns (
            address targetContract,
            ChannelState state,
            uint256 participantCount,
            bytes32 initialRoot,
            bytes32 finalRoot
        );

    function isChannelReadyToClose(uint256 channelId) external view returns (bool);

    function getAggregatedProofHash(uint256 channelId) external view returns (bytes32);

    function getGroupPublicKey(uint256 channelId) external view returns (bytes32);

    function getFinalStateRoot(uint256 channelId) external view returns (bytes32);

    function getMPTLeaves(uint256 channelId)
        external
        view
        returns (bytes[] memory initialLeaves, bytes[] memory finalLeaves);

    function getChannelTimeoutInfo(uint256 channelId)
        external
        view
        returns (uint256 openTimestamp, uint256 timeout, uint256 deadline);

    function isChannelExpired(uint256 channelId) external view returns (bool);

    function getRemainingTime(uint256 channelId) external view returns (uint256);

    function getChannelDeposits(uint256 channelId)
        external
        view
        returns (uint256 totalDeposits, address targetContract);

    function getParticipantDeposit(uint256 channelId, address participant) external view returns (uint256 amount);

    function getL2PublicKey(uint256 channelId, address participant) external view returns (address l2PublicKey);

    function getChannelParticipants(uint256 channelId) external view returns (address[] memory participants);

    function getChannelLeader(uint256 channelId) external view returns (address leader);

    function getChannelState(uint256 channelId) external view returns (ChannelState state);

    function getChannelTimestamps(uint256 channelId)
        external
        view
        returns (uint256 openTimestamp, uint256 closeTimestamp);

    function getChannelRoots(uint256 channelId) external view returns (bytes32 initialRoot, bytes32 finalRoot);

    function getChannelProofData(uint256 channelId)
        external
        view
        returns (uint128[] memory preprocessedPart1, uint256[] memory preprocessedPart2);

    function getChannelStats(uint256 channelId)
        external
        view
        returns (
            uint256 id,
            address targetContract,
            ChannelState state,
            uint256 participantCount,
            uint256 totalDeposits,
            uint256 requiredSignatures,
            uint256 receivedSignatures,
            address leader,
            bytes32 groupPublicKey
        );

    function isAuthorizedCreator(address creator) external view returns (bool);

    function getTotalChannels() external view returns (uint256);
}
