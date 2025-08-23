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
        mapping(address => bool) hasSigned;
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

    function signAggregatedProof(uint256 channelId, Signature calldata signature) external;

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
}
