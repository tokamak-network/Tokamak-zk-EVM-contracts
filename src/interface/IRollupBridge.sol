// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IRollupBridge {
    // =========== STRUCTS ===========

    struct Signature {
        bytes32 message;
        uint256 rx;
        uint256 ry;
        uint256 z;
    }

    struct User {
        address l1Address;
        address l2PublicKey;
    }

    struct TargetContract {
        address contractAddress;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    struct ChannelParams {
        address targetContract;
        address[] participants;
        address[] l2PublicKeys;
        uint256 timeout;
        uint256 pkx;
        uint256 pky;
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
        bytes32[] participantRoots; // Root used for each participant's leaf computation
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
        uint256 leaderBond; // ETH bond deposited by leader as collateral
        bool leaderBondSlashed; // Whether leader bond has been slashed
        // ZK Proof commitments removed - now retrieved from TargetContract
        // Closing process
        bytes32 aggregatedProofHash;
        mapping(address => bool) hasWithdrawn;
        mapping(address => uint256) withdrawAmount;
        uint256 pkx; // signer public key X (secp256k1)
        uint256 pky; // signer public key Y (secp256k1)
        address signerAddr; // keccak256(pkx||pky) last 20 bytes
        bool sigVerified;
        bytes[] initialMPTLeaves;
        bytes[] finalMPTLeaves;
        bytes32[] participantRoots; // Root used for each participant's leaf computation
    }

    // ============= ENUM =============

    enum ChannelState {
        None,
        Initialized,
        Open,
        Active,
        Closing,
        Dispute,
        Closed
    }

    // ============ EVENTS ============

    event L2AddressAssigned(address indexed l1Address, address indexed l2Address);
    event ChannelOpened(uint256 indexed channelId, address indexed targetContract);
    event StateConverted(uint256 indexed channelId, bytes32[] zkRoots);
    event ProofAggregated(uint256 indexed channelId, bytes32 proofHash);
    event ChannelClosed(uint256 indexed channelId);
    event ChannelFinalized(uint256 indexed channelId);
    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event EmergencyWithdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event StateInitialized(uint256 indexed channelId, bytes32 currentStateRoot);
    event AggregatedProofSigned(uint256 indexed channelId, address indexed signer);
    event LeaderBondSlashed(uint256 indexed channelId, address indexed leader, uint256 bondAmount, string reason);
    event LeaderBondReclaimed(uint256 indexed channelId, address indexed leader, uint256 bondAmount);
    event EmergencyWithdrawalsEnabled(uint256 indexed channelId);

    // =========== FUNCTIONS ===========

    function openChannel(ChannelParams calldata params) external payable returns (uint256 channelId);

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

    function isChannelReadyToClose(uint256 channelId) external view returns (bool);

    function getAggregatedProofHash(uint256 channelId) external view returns (bytes32);

    function getGroupPublicKey(uint256 channelId) external view returns (address);

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
            address leader
        );

    function getTotalChannels() external view returns (uint256);
}
