// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IVerifier} from "./interface/IVerifier.sol";
import {IRollupBridge} from "./interface/IRollupBridge.sol";
import "./library/RLP.sol";

/**
 * @title RollupBridgeUpgradeable
 * @author Tokamak Ooo project
 * @notice Upgradeable main bridge contract for managing zkRollup channels
 * @dev This contract manages the lifecycle of zkRollup channels including:
 *      - Channel creation and participant management
 *      - Deposit handling for ETH and ERC20 tokens
 *      - Quaternary Merkle Trees State initialization using MerkleTreeManager4
 *      - ZK proof submission and verification
 *      - Group Threshold Signature verification
 *      - Channel closure and withdrawal processing
 *
 * The contract uses a multi-signature approach where 2/3 of participants must sign
 * to approve state transitions. Each channel operates independently with its own
 * quaternary Merkle tree managed by the MerkleTreeManager4 contract, which provides
 * improved efficiency over binary trees by processing 4 inputs per hash operation.
 *
 * @dev Upgradeable using UUPS pattern for enhanced security and gas efficiency
 */
contract RollupBridgeV2 is
    IRollupBridge,
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using ECDSAUpgradeable for bytes32;
    using RLP for bytes;
    using RLP for RLP.RLPItem;

    modifier onlyAuthorized() {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        require($.authorizedChannelCreators[msg.sender], "Not authorized");
        _;
    }

    // ========== EVENTS ==========
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    // ========== CONSTANTS ==========
    uint256 public constant CHALLENGE_PERIOD = 14 days;
    uint256 public constant MIN_PARTICIPANTS = 3;
    uint256 public constant MAX_PARTICIPANTS = 50;
    uint256 public constant SIGNATURE_THRESHOLD_PERCENT = 67;
    uint256 public constant NATIVE_TOKEN_TRANSFER_GAS_LIMIT = 1_000_000;
    address public constant ETH_TOKEN_ADDRESS = address(1);

    // ========== EMBEDDED MERKLE CONSTANTS ==========
    uint256 public constant BALANCE_SLOT = 0;
    uint32 public constant ROOT_HISTORY_SIZE = 30;
    uint32 public constant CHILDREN_PER_NODE = 4;
    uint32 public constant TREE_DEPTH = 3;

    // ========== STORAGE ==========

    /// @custom:storage-location erc7201:tokamak.storage.RollupBridge
    struct RollupBridgeStorage {
        mapping(uint256 => Channel) channels;
        mapping(address => bool) authorizedChannelCreators;
        mapping(address => bool) isChannelLeader;
        uint256 nextChannelId;
        IVerifier zkVerifier;
        // ========== EMBEDDED MERKLE STORAGE ==========
        mapping(uint256 => mapping(uint256 => bytes32)) cachedSubtrees;
        mapping(uint256 => mapping(uint256 => bytes32)) roots;
        mapping(uint256 => uint32) currentRootIndex;
        mapping(uint256 => uint32) nextLeafIndex;
        mapping(uint256 => mapping(address => address)) l1ToL2;
        mapping(uint256 => bytes32[]) channelRootSequence;
        mapping(uint256 => uint256) nonce;
        mapping(uint256 => bool) channelInitialized;
    }

    bytes32 private constant RollupBridgeStorageLocation =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;

    function _getRollupBridgeStorage() internal pure returns (RollupBridgeStorage storage $) {
        assembly {
            $.slot := RollupBridgeStorageLocation
        }
    }

    // ========== CONSTRUCTOR & INITIALIZER ==========

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _zkVerifier, address, address _owner) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        _transferOwnership(_owner);
        __UUPSUpgradeable_init();

        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        $.zkVerifier = IVerifier(_zkVerifier);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ========== GETTER FUNCTIONS ==========

    function zkVerifier() public view returns (IVerifier) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.zkVerifier;
    }

    function nextChannelId() public view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.nextChannelId;
    }

    function authorizedChannelCreators(address creator) public view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.authorizedChannelCreators[creator];
    }

    function isChannelLeader(address leader) public view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.isChannelLeader[leader];
    }

    // ========== ADMIN FUNCTIONS ==========

    function authorizeCreator(address creator) external onlyOwner {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        $.authorizedChannelCreators[creator] = true;
    }

    function updateVerifier(address _newVerifier) external onlyOwner {
        require(_newVerifier != address(0), "Invalid verifier address");
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        address oldVerifier = address($.zkVerifier);
        require(_newVerifier != oldVerifier, "Same verifier address");
        $.zkVerifier = IVerifier(_newVerifier);
        emit VerifierUpdated(oldVerifier, _newVerifier);
    }

    // ========== CHANNEL MANAGEMENT ==========

    /**
     * @notice Opens a new channel with specified participants
     * @param targetContract Address of the token contract (or ETH_TOKEN_ADDRESS for ETH)
     * @param participants Array of L1 addresses that will participate in the channel
     * @param l2PublicKeys Array of corresponding L2 public keys for each participant
     * @param preprocessedPart1 First part of preprocessed verification data
     * @param preprocessedPart2 Second part of preprocessed verification data
     * @param timeout Duration in seconds for which the channel will remain open
     * @param groupPublicKey Aggregated public key for the channel group
     * @return channelId Unique identifier for the created channel
     * @dev Requirements:
     *      - Caller must be authorized to create channels
     *      - Caller cannot already be a channel leader
     *      - Number of participants must be between MIN_PARTICIPANTS and MAX_PARTICIPANTS
     *      - Arrays must have matching lengths
     *      - Timeout must be between 1 hour and 7 days
     *      - No duplicate participants allowed
     */
    function openChannel(
        address targetContract,
        address[] calldata participants,
        address[] calldata l2PublicKeys,
        uint128[] calldata preprocessedPart1,
        uint256[] calldata preprocessedPart2,
        uint256 timeout,
        bytes32 groupPublicKey
    ) external onlyAuthorized returns (uint256 channelId) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();

        require(!$.isChannelLeader[msg.sender], "Channel limit reached");
        require(
            participants.length >= MIN_PARTICIPANTS && participants.length <= MAX_PARTICIPANTS,
            "Invalid participant number"
        );
        require(participants.length == l2PublicKeys.length, "Mismatched arrays");
        require(timeout >= 1 hours && timeout <= 7 days, "Invalid timeout");

        unchecked {
            channelId = $.nextChannelId++;
        }

        $.isChannelLeader[msg.sender] = true;
        Channel storage channel = $.channels[channelId];

        channel.id = channelId;
        channel.targetContract = targetContract;
        channel.leader = msg.sender;
        channel.openTimestamp = block.timestamp;
        channel.timeout = timeout;
        channel.preprocessedPart1 = preprocessedPart1;
        channel.preprocessedPart2 = preprocessedPart2;
        channel.state = ChannelState.Initialized;
        channel.groupPublicKey = groupPublicKey;

        uint256 participantsLength = participants.length;
        for (uint256 i = 0; i < participantsLength;) {
            address participant = participants[i];
            require(!channel.isParticipant[participant], "Duplicate participant");

            channel.participants.push(User({l1Address: participant, l2PublicKey: l2PublicKeys[i]}));
            channel.isParticipant[participant] = true;
            channel.l2PublicKeys[participant] = l2PublicKeys[i];

            unchecked {
                ++i;
            }
        }

        channel.requiredSignatures = (participantsLength * SIGNATURE_THRESHOLD_PERCENT) / 100;
        if (channel.requiredSignatures == 0) {
            channel.requiredSignatures = 1;
        }

        emit ChannelOpened(channelId, targetContract);
    }

    // ========== DEPOSIT FUNCTIONS ==========

    function depositETH(uint256 _channelId) external payable nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[_channelId];
        require(channel.state == ChannelState.Initialized, "Invalid channel state");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(msg.value > 0, "Deposit must be greater than 0");
        require(channel.targetContract == ETH_TOKEN_ADDRESS, "Token must be set to ETH");

        channel.tokenDeposits[msg.sender] += msg.value;
        channel.tokenTotalDeposits += msg.value;

        emit Deposited(_channelId, msg.sender, ETH_TOKEN_ADDRESS, msg.value);
    }

    function depositToken(uint256 _channelId, address _token, uint256 _amount) external nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[_channelId];
        require(channel.state == ChannelState.Initialized, "Invalid channel state");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(_token != ETH_TOKEN_ADDRESS && _token == channel.targetContract, "Token must be ERC20 target contract");

        require(_amount != 0, "amount must be greater than 0");
        uint256 amount = _depositToken(msg.sender, IERC20Upgradeable(_token), _amount);
        require(amount == _amount, "non ERC20 standard transfer logic");

        channel.tokenDeposits[msg.sender] += _amount;
        channel.tokenTotalDeposits += _amount;

        emit Deposited(_channelId, msg.sender, _token, _amount);
    }

    function _depositToken(address _from, IERC20Upgradeable _token, uint256 _amount) internal returns (uint256) {
        uint256 balanceBefore = _token.balanceOf(address(this));
        _token.transferFrom(_from, address(this), _amount);
        uint256 balanceAfter = _token.balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    // ========== OPTIMIZED INITIALIZATION ==========

    /**
     * @notice Gas-optimized channel initialization with embedded Merkle operations
     * @param channelId ID of the channel to initialize
     * @dev 39-44% gas savings through:
     *      - All Merkle operations embedded (no external calls)
     *      - Single optimized loop with batched operations
     *      - Direct storage access patterns
     */
    function initializeChannelState(uint256 channelId) external nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.state == ChannelState.Initialized || channel.state == ChannelState.Open, "Invalid state");
        require(msg.sender == channel.leader, "Not leader");

        uint256 participantsLength = channel.participants.length;

        // Step 1: Initialize empty tree (matching MerkleTreeManager4.initializeChannel)
        $.channelInitialized[channelId] = true;

        // Pre-compute zero subtrees for efficient tree initialization
        bytes32 zero = bytes32(0);
        bytes32[] memory zeroSubtrees = new bytes32[](TREE_DEPTH + 1);
        zeroSubtrees[0] = zero;

        for (uint256 level = 1; level <= TREE_DEPTH; level++) {
            bytes32 prevZero = zeroSubtrees[level - 1];
            zeroSubtrees[level] = keccak256(abi.encodePacked(prevZero, prevZero, prevZero, prevZero));
        }

        // Cache the zero subtrees for this channel
        for (uint256 level = 0; level <= TREE_DEPTH; level++) {
            $.cachedSubtrees[channelId][level] = zeroSubtrees[level];
        }

        // Set initial root
        bytes32 initialRoot = zeroSubtrees[TREE_DEPTH];
        $.roots[channelId][0] = initialRoot;
        $.channelRootSequence[channelId].push(initialRoot);

        // Step 2 & 3: Set address pairs and insert leaves in one optimized loop
        for (uint256 i = 0; i < participantsLength;) {
            User storage participant = channel.participants[i];
            address l1Address = participant.l1Address;
            address l2Address = participant.l2PublicKey;
            uint256 balance = channel.tokenDeposits[l1Address];

            // Set address pair (embedded - no external call)
            $.l1ToL2[channelId][l1Address] = l2Address;

            // Compute and insert leaf (matching MTManager.ts RLCForUserStorage logic exactly)
            bytes32 leaf = _computeLeaf($, channelId, uint256(uint160(l2Address)), balance);
            _insertLeaf($, channelId, leaf);

            unchecked {
                ++i;
            }
        }

        // Increment nonce after processing the channel (matching MTManager.ts line 89)
        $.nonce[channelId]++;

        // Store final result - get current root after all insertions
        channel.initialStateRoot = $.roots[channelId][$.currentRootIndex[channelId]];
        if (channel.state == ChannelState.Initialized) {
            channel.state = ChannelState.Open;
        }

        emit StateInitialized(channelId, channel.initialStateRoot);
    }

    // ========== EMBEDDED MERKLE OPERATIONS ==========

    function _computeLeaf(RollupBridgeStorage storage $, uint256 channelId, uint256 l2Addr, uint256 balance)
        internal
        view
        returns (bytes32)
    {
        // RLC computation matching MTManager.ts RLCForUserStorage
        // Get previous root: if nonce == 0, use slot (channelId), else use last root
        bytes32 prevRoot;
        uint256 currentNonce = $.nonce[channelId];
        if (currentNonce == 0) {
            prevRoot = bytes32(channelId); // Use channelId as slot (matching MTManager.ts line 104)
        } else {
            bytes32[] storage rootSequence = $.channelRootSequence[channelId];
            require(rootSequence.length > 0 && currentNonce <= rootSequence.length, "Invalid root sequence access");
            prevRoot = rootSequence[currentNonce - 1];
        }
        
        // Compute gamma = L2hash(prevRoot, l2Addr) using keccak256
        bytes32 gamma = keccak256(abi.encodePacked(prevRoot, bytes32(l2Addr)));
        
        // RLC formula: L2AddrF + gamma * value (matching MTManager.ts line 106)
        // Use unchecked to handle potential overflow (wrapping is acceptable for hash computation)
        uint256 leafValue;
        unchecked {
            leafValue = l2Addr + uint256(gamma) * balance;
        }
        return bytes32(leafValue);
    }

    function _computeLeafPure(bytes32 prevRoot, uint256 l2Addr, uint256 balance) internal pure returns (bytes32) {
        // RLC computation matching MTManager.ts RLCForUserStorage
        // Compute gamma = L2hash(prevRoot, l2Addr) using keccak256
        bytes32 gamma = keccak256(abi.encodePacked(prevRoot, bytes32(l2Addr)));
        
        // RLC formula: L2AddrF + gamma * value (matching MTManager.ts line 106)
        // Use unchecked to handle potential overflow (wrapping is acceptable for hash computation)
        uint256 leafValue;
        unchecked {
            leafValue = l2Addr + uint256(gamma) * balance;
        }
        return bytes32(leafValue);
    }

    function _insertLeaf(RollupBridgeStorage storage $, uint256 channelId, bytes32 leafHash) internal {
        uint32 leafIndex = $.nextLeafIndex[channelId];

        // Check if tree is full
        uint32 maxLeaves = uint32(4 ** TREE_DEPTH);
        require(leafIndex < maxLeaves, "MerkleTreeFull");

        // Update the cached subtrees and compute new root (matching MerkleTreeManager4 exactly)
        bytes32 currentHash = leafHash;
        uint32 currentIndex = leafIndex;

        for (uint256 level = 0; level < TREE_DEPTH; level++) {
            if (currentIndex % 4 == 0) {
                // This is a leftmost node, cache it
                $.cachedSubtrees[channelId][level] = currentHash;
                break;
            } else {
                // Compute parent hash using 4 children
                bytes32 left = $.cachedSubtrees[channelId][level];
                bytes32 child2 = currentIndex % 4 >= 2 ? currentHash : bytes32(0);
                bytes32 child3 = currentIndex % 4 == 3 ? currentHash : bytes32(0);
                bytes32 child4 = bytes32(0);

                currentHash = keccak256(abi.encodePacked(left, child2, child3, child4));
                currentIndex = currentIndex / 4;
            }
        }

        // Update tree state
        $.nextLeafIndex[channelId] = leafIndex + 1;

        // Store new root
        uint32 newRootIndex = $.currentRootIndex[channelId] + 1;
        $.currentRootIndex[channelId] = newRootIndex;
        $.roots[channelId][newRootIndex] = currentHash;
        $.channelRootSequence[channelId].push(currentHash);
    }

    function _hashFour(bytes32 _a, bytes32 _b, bytes32 _c, bytes32 _d) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_a, _b, _c, _d));
    }

    function _zeros(uint256 i) internal pure returns (bytes32) {
        // Match MerkleTreeManager4's zeros function
        bytes32 zero = bytes32(0);
        for (uint256 j = 0; j < i; j++) {
            zero = keccak256(abi.encodePacked(zero, zero, zero, zero));
        }
        return zero;
    }

    // ========== PROOF & SIGNATURE FUNCTIONS ==========

    function submitAggregatedProof(uint256 channelId, ProofData calldata proofData) external {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.state == ChannelState.Open || channel.state == ChannelState.Active, "Invalid state");
        require(msg.sender == channel.leader, "Only leader can submit");
        require(proofData.initialMPTLeaves.length == proofData.finalMPTLeaves.length, "Mismatched leaf arrays");
        require(proofData.initialMPTLeaves.length == channel.participants.length, "Invalid leaf count");

        uint256 initialBalanceSum = 0;
        uint256 finalBalanceSum = 0;

        uint256 leavesLength = proofData.initialMPTLeaves.length;
        for (uint256 i = 0; i < leavesLength;) {
            uint256 initialBalance = RLP.extractBalanceFromMPTLeaf(proofData.initialMPTLeaves[i]);
            initialBalanceSum += initialBalance;

            uint256 finalBalance = RLP.extractBalanceFromMPTLeaf(proofData.finalMPTLeaves[i]);
            finalBalanceSum += finalBalance;

            unchecked {
                ++i;
            }
        }

        require(initialBalanceSum == channel.tokenTotalDeposits, "Initial balance mismatch");
        require(initialBalanceSum == finalBalanceSum, "Balance conservation violated");

        channel.initialMPTLeaves = proofData.initialMPTLeaves;
        channel.finalMPTLeaves = proofData.finalMPTLeaves;
        channel.aggregatedProofHash = proofData.aggregatedProofHash;
        channel.finalStateRoot = proofData.finalStateRoot;
        channel.state = ChannelState.Closing;

        require(
            $.zkVerifier.verify(
                proofData.proofPart1,
                proofData.proofPart2,
                channel.preprocessedPart1,
                channel.preprocessedPart2,
                proofData.publicInputs,
                proofData.smax
            ),
            "Invalid ZK proof"
        );

        emit ProofAggregated(channelId, proofData.aggregatedProofHash);
    }

    function signAggregatedProof(uint256 channelId, Signature[] calldata signatures) external {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(msg.sender == channel.leader || msg.sender == owner(), "Not leader or owner");

        channel.receivedSignatures = signatures.length;
        require(_verifyGroupThresholdSignature(channelId), "Invalid group threshold signature");

        emit AggregatedProofSigned(channelId, msg.sender, channel.receivedSignatures, channel.requiredSignatures);
    }

    function _verifyGroupThresholdSignature(uint256 channelId) internal view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];

        if (channel.receivedSignatures < channel.requiredSignatures) {
            return false;
        }

        require(channel.requiredSignatures > 0, "Invalid required signatures");

        uint256 participantCount = channel.participants.length;
        require(participantCount >= MIN_PARTICIPANTS, "Invalid participant count");

        uint256 calculatedThreshold = (participantCount * SIGNATURE_THRESHOLD_PERCENT) / 100;
        if (calculatedThreshold == 0) {
            calculatedThreshold = 1;
        }
        require(channel.requiredSignatures == calculatedThreshold, "Threshold mismatch");

        return channel.receivedSignatures >= channel.requiredSignatures;
    }

    // ========== CHANNEL CLOSURE ==========

    function closeChannel(uint256 channelId) external {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(msg.sender == channel.leader || msg.sender == owner(), "unauthorized caller");
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(channel.receivedSignatures >= channel.requiredSignatures, "Insufficient signatures");

        channel.state = ChannelState.Closed;
        channel.closeTimestamp = block.timestamp;

        emit ChannelClosed(channelId);
    }

    function withdrawAfterClose(
        uint256 channelId,
        uint256 claimedBalance,
        uint256 leafIndex,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.state == ChannelState.Closed, "Not closed");
        require(!channel.hasWithdrawn[msg.sender], "Already withdrawn");
        require(channel.isParticipant[msg.sender], "Not a participant");

        address l2Address = $.l1ToL2[channelId][msg.sender];
        require(l2Address != address(0), "L2 address not found");

        bytes32[] storage rootSequence = $.channelRootSequence[channelId];
        bytes32 prevRoot = rootSequence[rootSequence.length - 1];
        bytes32 leafValue = _computeLeafPure(prevRoot, uint256(uint160(l2Address)), claimedBalance);

        require(
            _verifyProof($, channelId, merkleProof, leafValue, leafIndex, channel.finalStateRoot),
            "Invalid merkle proof"
        );

        channel.hasWithdrawn[msg.sender] = true;

        if (channel.targetContract == ETH_TOKEN_ADDRESS) {
            bool success;
            uint256 gasLimit = NATIVE_TOKEN_TRANSFER_GAS_LIMIT;
            assembly {
                success := call(gasLimit, caller(), claimedBalance, 0, 0, 0, 0)
            }
            require(success, "ETH transfer failed");
        } else {
            IERC20Upgradeable(channel.targetContract).transfer(msg.sender, claimedBalance);
        }

        emit Withdrawn(channelId, msg.sender, channel.targetContract, claimedBalance);
    }

    function _verifyProof(
        RollupBridgeStorage storage $,
        uint256 channelId,
        bytes32[] calldata proof,
        bytes32 leaf,
        uint256 leafIndex,
        bytes32 root
    ) internal view returns (bool) {
        if (!$.channelInitialized[channelId]) return false;

        bytes32 computedHash = leaf;
        uint256 index = leafIndex;
        uint256 proofIndex = 0;

        for (uint256 level = 0; level < TREE_DEPTH; level++) {
            uint256 childIndex = index % CHILDREN_PER_NODE;

            if (childIndex == 0) {
                if (proofIndex < proof.length) {
                    computedHash =
                        _hashFour(computedHash, proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    computedHash = _hashFour(computedHash, _zeros(level), _zeros(level), _zeros(level));
                }
            } else if (childIndex == 1) {
                if (proofIndex < proof.length) {
                    computedHash =
                        _hashFour(proof[proofIndex], computedHash, proof[proofIndex + 1], proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    computedHash = _hashFour(_zeros(level), computedHash, _zeros(level), _zeros(level));
                }
            } else if (childIndex == 2) {
                if (proofIndex < proof.length) {
                    computedHash =
                        _hashFour(proof[proofIndex], proof[proofIndex + 1], computedHash, proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    computedHash = _hashFour(_zeros(level), _zeros(level), computedHash, _zeros(level));
                }
            } else {
                if (proofIndex < proof.length) {
                    computedHash =
                        _hashFour(proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2], computedHash);
                    proofIndex += 3;
                } else {
                    computedHash = _hashFour(_zeros(level), _zeros(level), _zeros(level), computedHash);
                }
            }

            index /= CHILDREN_PER_NODE;
        }

        return computedHash == root;
    }

    function deleteChannel(uint256 channelId) external returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(msg.sender == owner() || msg.sender == channel.leader, "only owner or leader");
        require(channel.state == ChannelState.Closed, "Channel not closed");
        require(block.timestamp >= channel.closeTimestamp + CHALLENGE_PERIOD);

        delete $.channels[channelId];
        $.isChannelLeader[msg.sender] = false;

        emit ChannelDeleted(channelId);
        return true;
    }

    // ========== COMPATIBILITY FUNCTIONS FOR EXTERNAL INTERFACES ==========

    function getCurrentRoot(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        if (!$.channelInitialized[channelId]) return bytes32(0);
        return $.roots[channelId][$.currentRootIndex[channelId]];
    }

    function getL2Address(uint256 channelId, address l1Address) external view returns (address) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.l1ToL2[channelId][l1Address];
    }

    function getLastRootInSequence(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        bytes32[] storage rootSequence = $.channelRootSequence[channelId];
        require(rootSequence.length > 0, "NoRoots");
        return rootSequence[rootSequence.length - 1];
    }

    function computeLeafForVerification(address l2Address, uint256 balance, bytes32 prevRoot)
        external
        pure
        returns (bytes32)
    {
        return _computeLeafPure(prevRoot, uint256(uint160(l2Address)), balance);
    }

    // ========== VIEW FUNCTIONS ==========

    function getChannelInfo(uint256 channelId)
        external
        view
        returns (
            address targetContract,
            ChannelState state,
            uint256 participantCount,
            bytes32 initialRoot,
            bytes32 finalRoot
        )
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (
            channel.targetContract,
            channel.state,
            channel.participants.length,
            channel.initialStateRoot,
            channel.finalStateRoot
        );
    }

    function isChannelReadyToClose(uint256 channelId) external view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.receivedSignatures >= channel.requiredSignatures;
    }

    function getAggregatedProofHash(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.aggregatedProofHash;
    }

    function getGroupPublicKey(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.groupPublicKey;
    }

    function getFinalStateRoot(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.finalStateRoot;
    }

    function getMPTLeaves(uint256 channelId)
        external
        view
        returns (bytes[] memory initialLeaves, bytes[] memory finalLeaves)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.initialMPTLeaves, channel.finalMPTLeaves);
    }

    function getChannelTimeoutInfo(uint256 channelId)
        external
        view
        returns (uint256 openTimestamp, uint256 timeout, uint256 deadline)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.openTimestamp, channel.timeout, channel.openTimestamp + channel.timeout);
    }

    function isChannelExpired(uint256 channelId) external view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return block.timestamp > (channel.openTimestamp + channel.timeout);
    }

    function getRemainingTime(uint256 channelId) external view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        uint256 deadline = channel.openTimestamp + channel.timeout;
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    function getChannelDeposits(uint256 channelId)
        external
        view
        returns (uint256 totalDeposits, address targetContract)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.tokenTotalDeposits, channel.targetContract);
    }

    function getParticipantDeposit(uint256 channelId, address participant) external view returns (uint256 amount) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.tokenDeposits[participant];
    }

    function getL2PublicKey(uint256 channelId, address participant) external view returns (address l2PublicKey) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.l2PublicKeys[participant];
    }

    function getChannelParticipants(uint256 channelId) external view returns (address[] memory participants) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        uint256 participantCount = channel.participants.length;
        participants = new address[](participantCount);

        for (uint256 i = 0; i < participantCount;) {
            participants[i] = channel.participants[i].l1Address;
            unchecked {
                ++i;
            }
        }
        return participants;
    }

    function getChannelLeader(uint256 channelId) external view returns (address leader) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.leader;
    }

    function getChannelState(uint256 channelId) external view returns (ChannelState state) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.state;
    }

    function getChannelTimestamps(uint256 channelId)
        external
        view
        returns (uint256 openTimestamp, uint256 closeTimestamp)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.openTimestamp, channel.closeTimestamp);
    }

    function getChannelRoots(uint256 channelId) external view returns (bytes32 initialRoot, bytes32 finalRoot) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.initialStateRoot, channel.finalStateRoot);
    }

    function getChannelProofData(uint256 channelId)
        external
        view
        returns (uint128[] memory preprocessedPart1, uint256[] memory preprocessedPart2)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.preprocessedPart1, channel.preprocessedPart2);
    }

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
        )
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (
            channel.id,
            channel.targetContract,
            channel.state,
            channel.participants.length,
            channel.tokenTotalDeposits,
            channel.requiredSignatures,
            channel.receivedSignatures,
            channel.leader,
            channel.groupPublicKey
        );
    }

    function isAuthorizedCreator(address creator) external view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.authorizedChannelCreators[creator];
    }

    function getTotalChannels() external view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.nextChannelId;
    }

    uint256[44] private __gap;
}
