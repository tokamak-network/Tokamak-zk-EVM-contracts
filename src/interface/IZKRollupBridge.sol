// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IZKRollupBridge {
    // =========== STRUCTS ===========

    struct Signature {
        uint256 R_x;
        uint256 R_y;
        uint256 s;
    }

    struct User {
        address l1Address;
        address l2PublicKey;
    }

    struct Channel {
        uint256 id;
        address targetContract;
        bytes32 computationType; // e.g., keccak256("TON_TRANSFER")
        // State roots
        bytes32 mptSnapshotRoot;
        bytes32[] zkMerkleRoots; // Multiple trees for different state components
        // Participants
        User[] participants;
        mapping(address => address) l2PublicKeys;
        mapping(address => bool) isParticipant;
        mapping(address => uint256) tokenTotalDeposits;
        mapping(address => mapping(address => uint256)) tokenDeposits; // token => user => amount
        // Channel state
        ChannelState state;
        uint256 openTimestamp;
        uint256 closeTimestamp;
        uint256 timeout;
        address leader;
        // Commitments for preprocessing
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
        // Final state
        bytes32 finalStateRoot;
        bytes32 aggregatedProofHash;
        uint256 requiredSignatures;
        uint256 receivedSignatures;
        mapping(address => bool) hasSigned;
        mapping(address => bool) hasWithdrawn;
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

    // =========== FUNCTIONS ===========

    function authorizeCreator(address creator) external;

    function openChannel(
        address targetContract,
        bytes32 computationType,
        address[] calldata participants,
        address[] calldata l2PublicKeys,
        uint128[] calldata preprocessedPart1,
        uint256[] calldata preprocessedPart2,
        uint256 timeout
    ) external returns (uint256);

    function depositETH(uint256 _channelId) external payable;

    function depositToken(uint256 _channelId, address _token, uint256 _amount) external;

    function withdrawAfterClose(
        uint256 channelId,
        uint256 claimedBalance,
        bytes32[] calldata merkleProof
    ) external;

    function emergencyWithdraw(uint256 channelId) external;

    function channelsFirstStateRoot(uint256 channelId) external;

    function submitAggregatedProof(uint256 channelId, bytes32 aggregatedProofHash, bytes32 finalStateRoot) external;

    function signAggregatedProof(uint256 channelId, Signature calldata signature) external;

    function getChannelInfo(uint256 channelId)
        external
        view
        returns (address, ChannelState, uint256, bytes32[] memory);
}
