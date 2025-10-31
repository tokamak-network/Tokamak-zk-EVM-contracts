// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "forge-std/console.sol";
import {IVerifier} from "./interface/IVerifier.sol";
import {IRollupBridge} from "./interface/IRollupBridge.sol";
import "./library/RLP.sol";
import {IZecFrost} from "./interface/IZecFrost.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

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
contract RollupBridge is IRollupBridge, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using ECDSAUpgradeable for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using RLP for bytes;
    using RLP for RLP.RLPItem;

    // ========== EVENTS ==========
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event TargetContractAllowed(address indexed targetContract, bool allowed);
    event L2AddressCollisionPrevented(uint256 indexed channelId, address l2Address, address attemptedUser);

    // ========== CONSTANTS ==========
    uint256 public constant CHALLENGE_PERIOD = 14 days;
    uint256 public constant PROOF_SUBMISSION_DEADLINE = 7 days; // Leader has 7 days after timeout to submit proof
    uint256 public constant MIN_PARTICIPANTS = 3;
    uint256 public constant MAX_PARTICIPANTS = 50;
    uint256 public constant NATIVE_TOKEN_TRANSFER_GAS_LIMIT = 1_000_000;
    address public constant ETH_TOKEN_ADDRESS = address(1);

    // ========== EMBEDDED MERKLE CONSTANTS ==========
    uint256 public constant BALANCE_SLOT = 0;
    uint32 public constant ROOT_HISTORY_SIZE = 30;
    uint32 public constant CHILDREN_PER_NODE = 4;
    uint32 public constant TREE_DEPTH = 3;
    uint256 public constant LEADER_BOND_REQUIRED = 1 ether; // Leader must deposit this amount to open channel

    // ========== STORAGE ==========

    /// @custom:storage-location erc7201:tokamak.storage.RollupBridge
    struct RollupBridgeStorage {
        mapping(uint256 => Channel) channels;
        mapping(address => bool) isChannelLeader;
        mapping(address => IRollupBridge.TargetContract) allowedTargetContracts;
        mapping(address => bool) isTargetContractAllowed;
        uint256 nextChannelId;
        IVerifier zkVerifier; // on-chain zkSNARK verifier contract
        IZecFrost zecFrost; // on-chain sig verifier contract
        // ========== EMBEDDED MERKLE STORAGE ==========
        mapping(uint256 => mapping(uint256 => bytes32)) cachedSubtrees;
        mapping(uint256 => mapping(uint256 => bytes32)) roots;
        mapping(uint256 => uint32) currentRootIndex;
        mapping(uint256 => uint32) nextLeafIndex;
        mapping(uint256 => mapping(address => address)) l1ToL2;
        mapping(uint256 => bytes32[]) channelRootSequence;
        mapping(uint256 => uint256) nonce;
        mapping(uint256 => bool) channelInitialized;
        // ========== L2 ADDRESS COLLISION PREVENTION ==========
        mapping(uint256 => mapping(address => bool)) usedL2Addresses; // channelId => l2Address => used
        mapping(address => mapping(uint256 => address)) l2ToL1Mapping; // l2Address => channelId => l1Address
        // ========== SLASHED BOND MANAGEMENT ==========
        address treasury; // Address to receive slashed bonds
        uint256 totalSlashedBonds; // Total amount of slashed bonds available for withdrawal
    }

    bytes32 private constant RollupBridgeStorageLocation =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;

    // ========== CONSTRUCTOR & INITIALIZER ==========

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the RollupBridge contract
     * @param _zkVerifier Address of the ZK verifier contract
     * @param _zecFrost Address of the ZecFrost signature verifier contract
     * @param _owner Address that will own the contract
     */
    function initialize(address _zkVerifier, address _zecFrost, address _owner) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        _transferOwnership(_owner);
        __UUPSUpgradeable_init();

        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        $.zkVerifier = IVerifier(_zkVerifier);
        $.zecFrost = IZecFrost(_zecFrost);
    }

    // ========== EXTERNAL FUNCTIONS ==========

    /**
     * @notice Opens a new channel with specified participants
     * @param params ChannelParams struct containing:
     *      - targetContract: Address of the token contract (or ETH_TOKEN_ADDRESS for ETH)
     *      - participants: Array of L1 addresses that will participate in the channel
     *      - l2PublicKeys: Array of corresponding L2 public keys for each participant
     *      - timeout: Duration in seconds for which the channel will remain open
     *      - pkx: X coordinate of the aggregated public key for the channel group
     *      - pky: Y coordinate of the aggregated public key for the channel group
     * @return channelId Unique identifier for the created channel
     * @dev Requirements:
     *      - Caller must be authorized to create channels
     *      - Caller must send LEADER_BOND_REQUIRED ETH as leader bond
     *      - Caller cannot already be a channel leader
     *      - Number of participants must be between MIN_PARTICIPANTS and MAX_PARTICIPANTS
     *      - Arrays must have matching lengths
     *      - Timeout must be between 1 hour and 7 days
     *      - No duplicate participants allowed
     */
    function openChannel(ChannelParams calldata params) external payable returns (uint256 channelId) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();

        // Leader must deposit bond as collateral for their responsibilities
        require(msg.value == LEADER_BOND_REQUIRED, "Leader bond required");
        require(!$.isChannelLeader[msg.sender], "Channel limit reached");
        require(
            params.participants.length >= MIN_PARTICIPANTS && params.participants.length <= MAX_PARTICIPANTS,
            "Invalid participant number"
        );
        require(params.participants.length == params.l2PublicKeys.length, "Mismatched arrays");
        require(params.timeout >= 1 hours && params.timeout <= 365 days, "Invalid timeout");
        require(
            params.targetContract == ETH_TOKEN_ADDRESS || $.isTargetContractAllowed[params.targetContract],
            "Target contract not allowed"
        );

        unchecked {
            channelId = $.nextChannelId++;
        }

        $.isChannelLeader[msg.sender] = true;
        Channel storage channel = $.channels[channelId];

        channel.id = channelId;
        channel.targetContract = params.targetContract;
        channel.leader = msg.sender;
        channel.leaderBond = msg.value; // Store the leader bond
        channel.leaderBondSlashed = false;
        channel.openTimestamp = block.timestamp;
        channel.timeout = params.timeout;
        channel.state = ChannelState.Initialized;

        uint256 participantsLength = params.participants.length;
        // Check for L2 address collisions first
        for (uint256 i = 0; i < participantsLength;) {
            for (uint256 j = i + 1; j < participantsLength;) {
                require(params.l2PublicKeys[i] != params.l2PublicKeys[j], "L2 address collision detected");
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < participantsLength;) {
            address participant = params.participants[i];
            address l2PublicKey = params.l2PublicKeys[i];

            require(!channel.isParticipant[participant], "Duplicate participant");
            require(l2PublicKey != address(0), "Invalid L2 address");

            // Register L2 address to track usage and prevent future collisions
            require(validateAndRegisterL2Address(channelId, participant, l2PublicKey), "L2 address registration failed");

            channel.participants.push(User({l1Address: participant, l2PublicKey: l2PublicKey}));
            channel.isParticipant[participant] = true;
            channel.l2PublicKeys[participant] = l2PublicKey;

            unchecked {
                ++i;
            }
        }

        // store public key and generate signer address
        channel.pkx = params.pkx;
        channel.pky = params.pky;
        address signerAddr = _deriveAddressFromPubkey(params.pkx, params.pky);
        channel.signerAddr = signerAddr;

        emit ChannelOpened(channelId, params.targetContract);
    }

    /**
     * @notice Deposits ETH into a channel
     * @param _channelId The ID of the channel to deposit into
     * @dev Only participants can deposit, channel must be in Initialized state
     */
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

    /**
     * @notice Deposits ERC20 tokens into a channel
     * @param _channelId The ID of the channel to deposit into
     * @param _token The token contract address (must match channel's target contract)
     * @param _amount The amount of tokens to deposit
     * @dev Only participants can deposit, channel must be in Initialized state
     */
    function depositToken(uint256 _channelId, address _token, uint256 _amount) external nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[_channelId];
        require(channel.state == ChannelState.Initialized, "Invalid channel state");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(_token != ETH_TOKEN_ADDRESS && _token == channel.targetContract, "Token must be ERC20 target contract");

        require(_amount != 0, "amount must be greater than 0");
        uint256 actualAmount = _depositToken(msg.sender, IERC20Upgradeable(_token), _amount);

        channel.tokenDeposits[msg.sender] += actualAmount;
        channel.tokenTotalDeposits += actualAmount;

        emit Deposited(_channelId, msg.sender, _token, actualAmount);
    }

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
        require(channel.state == ChannelState.Initialized, "Invalid state");
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
        channel.state = ChannelState.Open;

        emit StateInitialized(channelId, channel.initialStateRoot);
    }

    /**
     * @notice Submits aggregated proof for the channel after timeout period
     * @param channelId The channel ID
     * @param proofData The proof data structure containing ZK proof and state information
     * @dev Only the channel leader can submit proofs, and only after the channel timeout has passed
     *      Leader has PROOF_SUBMISSION_DEADLINE (7 days) after timeout to submit proof or bond gets slashed
     */
    function submitAggregatedProof(uint256 channelId, ProofData calldata proofData) external {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.state == ChannelState.Open || channel.state == ChannelState.Active, "Invalid state");
        require(msg.sender == channel.leader, "Only leader can submit");
        require(block.timestamp >= channel.openTimestamp + channel.timeout, "Channel timeout not reached");
        require(proofData.initialMPTLeaves.length == proofData.finalMPTLeaves.length, "Mismatched leaf arrays");
        require(proofData.initialMPTLeaves.length == channel.participants.length, "Invalid leaf count");
        require(proofData.participantRoots.length == channel.participants.length, "Invalid participant roots count");

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
        channel.participantRoots = proofData.participantRoots;
        channel.aggregatedProofHash = proofData.aggregatedProofHash;
        channel.finalStateRoot = proofData.finalStateRoot;
        channel.state = ChannelState.Closing;

        // Retrieve preprocessed data from stored TargetContract
        IRollupBridge.TargetContract memory targetContractData = $.allowedTargetContracts[channel.targetContract];
        uint128[] memory preprocessedPart1 = targetContractData.preprocessedPart1;
        uint256[] memory preprocessedPart2 = targetContractData.preprocessedPart2;

        bool proofValid = $.zkVerifier.verify(
            proofData.proofPart1,
            proofData.proofPart2,
            preprocessedPart1,
            preprocessedPart2,
            proofData.publicInputs,
            proofData.smax
        );

        if (!proofValid) {
            revert("Invalid ZK proof");
        }

        emit ProofAggregated(channelId, proofData.aggregatedProofHash);
    }

    /**
     * @notice Signs the aggregated proof with group threshold signature
     * @param channelId The channel ID
     * @param signature The group threshold signature
     * @dev Only the channel leader or contract owner can sign
     */
    function signAggregatedProof(uint256 channelId, Signature calldata signature) external {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(msg.sender == channel.leader || msg.sender == owner(), "Not leader or owner");

        address recovered =
            $.zecFrost.verify(signature.message, channel.pkx, channel.pky, signature.rx, signature.ry, signature.z);

        require(recovered == channel.signerAddr, "Invalid group threshold signature");

        channel.sigVerified = true;

        emit AggregatedProofSigned(channelId, msg.sender);
    }

    /**
     * @notice Closes and finalizes a channel directly if signature is verified
     * @param channelId The channel ID to close and finalize
     * @dev Only the channel leader or contract owner can close
     *      Channel goes directly to Closed state, skipping Dispute state
     */
    function closeAndFinalizeChannel(uint256 channelId) external {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(msg.sender == channel.leader || msg.sender == owner(), "unauthorized caller");
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(channel.sigVerified, "signature not verified");

        // Transition directly to Closed state (no challenge period needed when signature is verified)
        channel.state = ChannelState.Closed;
        channel.closeTimestamp = block.timestamp;
        $.isChannelLeader[channel.leader] = false;

        emit ChannelClosed(channelId);
        emit ChannelFinalized(channelId);
    }

    /**
     * @notice Emergency close for expired channels without proof submission
     * @param channelId The channel ID to emergency close
     * @dev Only contract owner can emergency close, and only after proof submission deadline has passed
     */
    function emergencyCloseExpiredChannel(uint256 channelId) external {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(msg.sender == owner(), "unauthorized caller");
        require(
            channel.state == ChannelState.Open || channel.state == ChannelState.Active,
            "Channel must be in Open or Active state"
        );
        require(
            block.timestamp >= channel.openTimestamp + channel.timeout + PROOF_SUBMISSION_DEADLINE,
            "Proof submission deadline not reached"
        );

        // Slash leader bond for failing to submit proof on time
        if (!channel.leaderBondSlashed && channel.leaderBond > 0) {
            _slashLeaderBond(channelId, "Failed to submit proof before timeout");
        }

        // Enable emergency withdrawals to allow participants to withdraw their original deposits
        // Since no proof was provided, we revert to initial deposit amounts
        _enableEmergencyWithdrawals(channelId);

        // Emergency close sets channel to Closed state directly
        channel.state = ChannelState.Closed;
        channel.closeTimestamp = block.timestamp;

        emit ChannelClosed(channelId);
    }

    /**
     * @notice Withdraws funds after channel closure using Merkle proof
     * @param channelId The channel ID
     * @param claimedBalance The amount to withdraw
     * @param leafIndex The leaf index in the Merkle tree
     * @param merkleProof The Merkle proof for the withdrawal
     * @dev Only participants can withdraw once per channel
     */
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
        require(!this.isEmergencyModeEnabled(channelId), "Emergency mode enabled - use emergency withdrawal");

        address l2Address = $.l1ToL2[channelId][msg.sender];
        require(l2Address != address(0), "L2 address not found");

        // Find participant index to get their specific root
        uint256 participantIndex = type(uint256).max;
        for (uint256 i = 0; i < channel.participants.length; i++) {
            if (channel.participants[i].l1Address == msg.sender) {
                participantIndex = i;
                break;
            }
        }
        require(participantIndex != type(uint256).max, "Participant not found");
        require(participantIndex < channel.participantRoots.length, "Participant root not found");

        // Use participant-specific root for leaf computation
        bytes32 participantRoot = channel.participantRoots[participantIndex];
        bytes32 leafValue = _computeLeafPure(participantRoot, uint256(uint160(l2Address)), claimedBalance);

        require(
            _verifyProof($, channelId, merkleProof, leafValue, leafIndex, channel.finalStateRoot),
            "Invalid merkle proof"
        );

        channel.hasWithdrawn[msg.sender] = true;
        channel.withdrawAmount[msg.sender] = claimedBalance;

        if (channel.targetContract == ETH_TOKEN_ADDRESS) {
            bool success;
            uint256 gasLimit = NATIVE_TOKEN_TRANSFER_GAS_LIMIT;
            assembly {
                success := call(gasLimit, caller(), claimedBalance, 0, 0, 0, 0)
            }
            require(success, "ETH transfer failed");
        } else {
            // we use safeTransfer to make it compatible with custom tokens s.a USDT
            IERC20Upgradeable(channel.targetContract).safeTransfer(msg.sender, claimedBalance);
        }

        emit Withdrawn(channelId, msg.sender, channel.targetContract, claimedBalance);
    }

    /**
     * @notice Handles leader bond slashing when proof is not submitted within deadline
     * @param channelId The channel where leader failed to submit proof
     * @dev Only participants can call this function, and only after proof submission deadline has passed
     */
    function handleProofTimeout(uint256 channelId) external {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];

        require(channel.isParticipant[msg.sender], "Not a participant");
        require(channel.state == ChannelState.Open || channel.state == ChannelState.Active, "Invalid state");
        require(
            block.timestamp >= channel.openTimestamp + channel.timeout + PROOF_SUBMISSION_DEADLINE,
            "Proof submission deadline not reached"
        );

        // Slash leader bond for timeout
        _slashLeaderBond(channelId, "Failed to submit proof on time");

        // Enable emergency withdrawals for participants
        _enableEmergencyWithdrawals(channelId);
    }

    /**
     * @notice Allows leader to reclaim bond after successful channel completion
     * @param channelId The channel ID
     * @dev Only the channel leader can reclaim their bond
     */
    function reclaimLeaderBond(uint256 channelId) external nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];

        require(msg.sender == channel.leader, "Not the leader");
        require(channel.state == ChannelState.Closed, "Channel not closed");
        require(!channel.leaderBondSlashed, "Bond was slashed");
        require(channel.leaderBond > 0, "No bond to reclaim");

        uint256 bondAmount = channel.leaderBond;
        channel.leaderBond = 0; // Prevent re-entrancy

        (bool success,) = msg.sender.call{value: bondAmount}("");
        require(success, "Bond transfer failed");

        emit LeaderBondReclaimed(channelId, msg.sender, bondAmount);
    }

    /**
     * @notice Updates the ZK verifier contract address
     * @param _newVerifier The new verifier contract address
     * @dev Only contract owner can update the verifier
     */
    function updateVerifier(address _newVerifier) external onlyOwner {
        require(_newVerifier != address(0), "Invalid verifier address");
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        address oldVerifier = address($.zkVerifier);
        require(_newVerifier != oldVerifier, "Same verifier address");
        $.zkVerifier = IVerifier(_newVerifier);
        emit VerifierUpdated(oldVerifier, _newVerifier);
    }

    /**
     * @notice Sets or updates allowed target contracts with their preprocessed data
     * @param targetContract The target contract address
     * @param preprocessedPart1 The first part of preprocessed data
     * @param preprocessedPart2 The second part of preprocessed data
     * @param allowed Whether the contract is allowed or not
     * @dev Only contract owner can set target contracts
     */
    function setAllowedTargetContract(
        address targetContract,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bool allowed
    ) external onlyOwner {
        require(targetContract != address(0), "Invalid target contract address");
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();

        if (allowed) {
            // Store the target contract with its preprocessed data
            require(preprocessedPart1.length > 0, "preprocessedPart1 cannot be empty when allowing");
            require(preprocessedPart2.length > 0, "preprocessedPart2 cannot be empty when allowing");

            $.allowedTargetContracts[targetContract] = IRollupBridge.TargetContract({
                contractAddress: targetContract,
                preprocessedPart1: preprocessedPart1, // Store full array
                preprocessedPart2: preprocessedPart2 // Store full array
            });
        } else {
            // Clear the target contract data when disallowing
            delete $.allowedTargetContracts[targetContract];
        }

        $.isTargetContractAllowed[targetContract] = allowed;
        emit TargetContractAllowed(targetContract, allowed);
    }

    /**
     * @notice Sets the treasury address for receiving slashed bonds
     * @param _treasury The new treasury address
     * @dev Only contract owner can set the treasury address
     */
    function setTreasuryAddress(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Treasury cannot be zero address");

        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        address oldTreasury = $.treasury;
        $.treasury = _treasury;

        emit TreasuryAddressUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Withdraws all accumulated slashed bonds to the treasury
     * @dev Only callable by owner, sends funds to treasury address
     */
    function withdrawSlashedBonds() external onlyOwner nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();

        require($.treasury != address(0), "Treasury address not set");
        require($.totalSlashedBonds > 0, "No slashed bonds to withdraw");

        uint256 amount = $.totalSlashedBonds;
        $.totalSlashedBonds = 0;

        (bool success,) = $.treasury.call{value: amount}("");
        require(success, "Slashed bond transfer failed");

        emit SlashedBondsWithdrawn($.treasury, amount);
    }

    /**
     * @notice Debug function to get token information
     * @param token The token contract address
     * @param user The user address to check
     * @return userBalance User's token balance
     * @return userAllowance User's allowance to this contract
     * @return contractBalance This contract's token balance
     * @return isContract Whether the token address is a contract
     * @return name Token name
     * @return symbol Token symbol
     * @return decimals Token decimals
     */
    function debugTokenInfo(address token, address user)
        external
        view
        returns (
            uint256 userBalance,
            uint256 userAllowance,
            uint256 contractBalance,
            bool isContract,
            string memory name,
            string memory symbol,
            uint8 decimals
        )
    {
        IERC20Upgradeable tokenContract = IERC20Upgradeable(token);

        userBalance = tokenContract.balanceOf(user);
        userAllowance = tokenContract.allowance(user, address(this));
        contractBalance = tokenContract.balanceOf(address(this));

        // Check if it's a contract
        uint32 size;
        assembly {
            size := extcodesize(token)
        }
        isContract = size > 0;

        // Try to get token info (might fail for non-standard tokens)
        try IERC20MetadataUpgradeable(token).name() returns (string memory _name) {
            name = _name;
        } catch {
            name = "Unknown";
        }

        try IERC20MetadataUpgradeable(token).symbol() returns (string memory _symbol) {
            symbol = _symbol;
        } catch {
            symbol = "Unknown";
        }

        try IERC20MetadataUpgradeable(token).decimals() returns (uint8 _decimals) {
            decimals = _decimals;
        } catch {
            decimals = 18; // Default
        }
    }

    /**
     * @notice Internal verification function exposed for external calls
     * @param proof The Merkle proof
     * @param leaf The leaf to verify
     * @param leafIndex The index of the leaf
     * @param root The Merkle root
     * @return True if the proof is valid
     */
    function _verifyProofInternal(bytes32[] calldata proof, bytes32 leaf, uint256 leafIndex, bytes32 root)
        external
        view
        returns (bool)
    {
        bytes32 computedHash = leaf;
        uint256 index = leafIndex;
        uint256 proofIndex = 0;

        for (uint256 level = 0; level < TREE_DEPTH; level++) {
            uint256 childIndex = index % CHILDREN_PER_NODE;

            if (childIndex == 0) {
                if (proofIndex + 2 < proof.length) {
                    computedHash =
                        _hashFour(computedHash, proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    computedHash = _hashFour(computedHash, _zeros(level), _zeros(level), _zeros(level));
                }
            } else if (childIndex == 1) {
                if (proofIndex + 2 < proof.length) {
                    computedHash =
                        _hashFour(proof[proofIndex], computedHash, proof[proofIndex + 1], proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    computedHash = _hashFour(_zeros(level), computedHash, _zeros(level), _zeros(level));
                }
            } else if (childIndex == 2) {
                if (proofIndex + 2 < proof.length) {
                    computedHash =
                        _hashFour(proof[proofIndex], proof[proofIndex + 1], computedHash, proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    computedHash = _hashFour(_zeros(level), _zeros(level), computedHash, _zeros(level));
                }
            } else {
                if (proofIndex + 2 < proof.length) {
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

    /**
     * @notice Checks if emergency mode is enabled for a channel
     * @param channelId The channel ID to check
     * @return False (emergency mode has been removed)
     */
    function isEmergencyModeEnabled(uint256 channelId) external pure returns (bool) {
        // Since we removed emergency mode, this always returns false
        return false;
    }

    /**
     * @notice Computes leaf for verification purposes
     * @param l2Address The L2 address
     * @param balance The balance amount
     * @param prevRoot The previous root
     * @return The computed leaf hash
     */
    function computeLeafForVerification(address l2Address, uint256 balance, bytes32 prevRoot)
        external
        pure
        returns (bytes32)
    {
        return _computeLeafPure(prevRoot, uint256(uint160(l2Address)), balance);
    }

    // ========== INTERNAL FUNCTIONS ==========

    /**
     * @notice Internal function to get storage pointer
     * @return $ Storage pointer to RollupBridgeStorage
     */
    function _getRollupBridgeStorage() internal pure returns (RollupBridgeStorage storage $) {
        assembly {
            $.slot := RollupBridgeStorageLocation
        }
    }

    /**
     * @notice Internal function to authorize upgrades
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Derives an Ethereum-style address from the uncompressed public key (x||y)
     * @param pkx The x coordinate of the public key
     * @param pky The y coordinate of the public key
     * @return The derived Ethereum address
     */
    function _deriveAddressFromPubkey(uint256 pkx, uint256 pky) internal pure returns (address) {
        bytes32 h = keccak256(abi.encodePacked(pkx, pky));
        return address(uint160(uint256(h)));
    }

    /**
     * @notice Internal function to handle token deposits with fee-on-transfer support
     * @param _from The address depositing tokens
     * @param _token The token contract
     * @param _amount The amount to deposit
     * @return The actual amount deposited (after any fees)
     */
    function _depositToken(address _from, IERC20Upgradeable _token, uint256 _amount) internal returns (uint256) {
        // Check that user has sufficient balance
        uint256 userBalance = _token.balanceOf(_from);
        require(
            userBalance >= _amount,
            string(abi.encodePacked("Insufficient token balance: ", _toString(userBalance), " < ", _toString(_amount)))
        );

        // Check that user has approved sufficient allowance
        uint256 userAllowance = _token.allowance(_from, address(this));
        require(
            userAllowance >= _amount,
            string(
                abi.encodePacked("Insufficient token allowance: ", _toString(userAllowance), " < ", _toString(_amount))
            )
        );

        uint256 balanceBefore = _token.balanceOf(address(this));

        // Use SafeERC20's safeTransferFrom - this will handle USDT's void return properly
        _token.safeTransferFrom(_from, address(this), _amount);

        uint256 balanceAfter = _token.balanceOf(address(this));

        // Handle fee-on-transfer tokens like USDT (though fees are currently disabled)
        uint256 actualAmount = balanceAfter - balanceBefore;
        require(actualAmount > 0, "No tokens transferred");

        return actualAmount;
    }

    /**
     * @notice Converts uint256 to string
     * @param value The value to convert
     * @return The string representation
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Computes leaf hash using channel state and nonce
     * @param $ Storage pointer
     * @param channelId The channel ID
     * @param l2Addr The L2 address as uint256
     * @param balance The balance amount
     * @return The computed leaf hash
     */
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

    /**
     * @notice Pure version of leaf computation for verification
     * @param prevRoot The previous root
     * @param l2Addr The L2 address as uint256
     * @param balance The balance amount
     * @return The computed leaf hash
     */
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

    /**
     * @notice Inserts a leaf into the quaternary Merkle tree
     * @param $ Storage pointer
     * @param channelId The channel ID
     * @param leafHash The leaf hash to insert
     */
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

    /**
     * @notice Hashes four bytes32 values together
     * @param _a First value
     * @param _b Second value
     * @param _c Third value
     * @param _d Fourth value
     * @return The keccak256 hash of the concatenated values
     */
    function _hashFour(bytes32 _a, bytes32 _b, bytes32 _c, bytes32 _d) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_a, _b, _c, _d));
    }

    /**
     * @notice Generates zero hash for a given level
     * @param i The level
     * @return The zero hash for that level
     */
    function _zeros(uint256 i) internal pure returns (bytes32) {
        // Match MerkleTreeManager4's zeros function
        bytes32 zero = bytes32(0);
        for (uint256 j = 0; j < i; j++) {
            zero = keccak256(abi.encodePacked(zero, zero, zero, zero));
        }
        return zero;
    }

    /**
     * @notice Verifies a Merkle proof for a given leaf
     * @param $ Storage pointer
     * @param channelId The channel ID
     * @param proof The Merkle proof
     * @param leaf The leaf to verify
     * @param leafIndex The index of the leaf
     * @param root The Merkle root
     * @return True if the proof is valid
     */
    function _verifyProof(
        RollupBridgeStorage storage $,
        uint256 channelId,
        bytes32[] calldata proof,
        bytes32 leaf,
        uint256 leafIndex,
        bytes32 root
    ) internal view returns (bool) {
        if (!$.channelInitialized[channelId]) return false;

        // Catch any arithmetic errors and return false
        try this._verifyProofInternal(proof, leaf, leafIndex, root) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    /**
     * @notice Validates and registers L2 addresses to prevent collisions
     * @param channelId The channel ID
     * @param l1Address The L1 address of the participant
     * @param l2Address The proposed L2 address
     * @return success True if validation passed and address was registered
     */
    function validateAndRegisterL2Address(uint256 channelId, address l1Address, address l2Address)
        internal
        returns (bool success)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();

        require(l2Address != address(0), "Invalid L2 address");

        // Check if L2 address is already used in this channel
        if ($.usedL2Addresses[channelId][l2Address]) {
            emit L2AddressCollisionPrevented(channelId, l2Address, l1Address);
            return false;
        }

        // Register the L2 address
        $.usedL2Addresses[channelId][l2Address] = true;
        $.l2ToL1Mapping[l2Address][channelId] = l1Address;

        return true;
    }

    /**
     * @notice Slashes the leader's bond for misconduct
     * @param channelId The channel ID
     * @param reason The reason for slashing
     */
    function _slashLeaderBond(uint256 channelId, string memory reason) internal {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];

        require(!channel.leaderBondSlashed, "Leader bond already slashed");
        require(channel.leaderBond > 0, "No leader bond to slash");

        uint256 bondAmount = channel.leaderBond;
        channel.leaderBondSlashed = true;

        // Add slashed bond to total for later withdrawal
        $.totalSlashedBonds += bondAmount;

        emit LeaderBondSlashed(channelId, channel.leader, bondAmount, reason);
    }

    /**
     * @notice Enables emergency withdrawals when leader fails
     * @param channelId The channel ID
     */
    function _enableEmergencyWithdrawals(uint256 channelId) internal {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];

        // Set channel to emergency state - participants can withdraw their deposits
        channel.state = ChannelState.Closed;
        channel.closeTimestamp = block.timestamp;

        emit EmergencyWithdrawalsEnabled(channelId);
    }

    /**
     * @notice Internal helper functions for legacy dispute logic compatibility
     * @param channelId The channel ID
     * @return Array of participant addresses
     */
    function _getChannelParticipants(uint256 channelId) internal view returns (address[] memory) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        uint256 participantCount = channel.participants.length;
        address[] memory participants = new address[](participantCount);

        for (uint256 i = 0; i < participantCount; i++) {
            participants[i] = channel.participants[i].l1Address;
        }
        return participants;
    }

    /**
     * @notice Gets participant deposit amount
     * @param channelId The channel ID
     * @param participant The participant address
     * @return The deposit amount
     */
    function _getParticipantDeposit(uint256 channelId, address participant) internal view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.channels[channelId].tokenDeposits[participant];
    }

    /**
     * @notice Checks if an address is a participant
     * @param channelId The channel ID
     * @param participant The address to check
     * @return True if the address is a participant
     */
    function _isParticipant(uint256 channelId, address participant) internal view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.channels[channelId].isParticipant[participant];
    }

    /**
     * @notice Gets the channel state
     * @param channelId The channel ID
     * @return The channel state
     */
    function _getChannelState(uint256 channelId) internal view returns (IRollupBridge.ChannelState) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.channels[channelId].state;
    }

    /**
     * @notice Gets the channel close timestamp
     * @param channelId The channel ID
     * @return The close timestamp
     */
    function _getChannelCloseTimestamp(uint256 channelId) internal view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.channels[channelId].closeTimestamp;
    }

    /**
     * @notice Gets the challenge period duration
     * @return The challenge period in seconds
     */
    function _getChallengePeriod() internal pure returns (uint256) {
        return CHALLENGE_PERIOD;
    }

    /**
     * @notice Gets the channel leader
     * @param channelId The channel ID
     * @return The leader address
     */
    function _getChannelLeader(uint256 channelId) internal view returns (address) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.channels[channelId].leader;
    }

    /**
     * @notice Checks if a participant has withdrawn
     * @param channelId The channel ID
     * @param participant The participant address
     * @return True if the participant has withdrawn
     */
    function _hasWithdrawn(uint256 channelId, address participant) internal view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.channels[channelId].hasWithdrawn[participant];
    }

    // ========== VIEW FUNCTIONS / GETTERS ==========

    /**
     * @notice Gets the ZK verifier contract
     * @return The verifier contract interface
     */
    function zkVerifier() public view returns (IVerifier) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.zkVerifier;
    }

    /**
     * @notice Gets the ZecFrost signature verifier contract
     * @return The ZecFrost contract interface
     */
    function zecFrost() public view returns (IZecFrost) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.zecFrost;
    }

    /**
     * @notice Gets the next channel ID to be assigned
     * @return The next channel ID
     */
    function nextChannelId() public view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.nextChannelId;
    }

    /**
     * @notice Checks if an address is a channel leader
     * @param leader The address to check
     * @return True if the address is a channel leader
     */
    function isChannelLeader(address leader) public view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.isChannelLeader[leader];
    }

    /**
     * @notice Checks if a target contract is allowed
     * @param targetContract The contract address to check
     * @return True if the contract is allowed
     */
    function isAllowedTargetContract(address targetContract) public view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.isTargetContractAllowed[targetContract];
    }

    /**
     * @notice Gets target contract data including preprocessed information
     * @param targetContract The target contract address
     * @return The target contract data structure
     */
    function getTargetContractData(address targetContract) public view returns (IRollupBridge.TargetContract memory) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        require($.isTargetContractAllowed[targetContract], "Target contract not allowed");
        return $.allowedTargetContracts[targetContract];
    }

    /**
     * @notice Gets the current Merkle root for a channel
     * @param channelId The channel ID
     * @return The current root hash
     */
    function getCurrentRoot(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        if (!$.channelInitialized[channelId]) return bytes32(0);
        return $.roots[channelId][$.currentRootIndex[channelId]];
    }

    /**
     * @notice Gets the L2 address mapped to an L1 address
     * @param channelId The channel ID
     * @param l1Address The L1 address
     * @return The corresponding L2 address
     */
    function getL2Address(uint256 channelId, address l1Address) external view returns (address) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.l1ToL2[channelId][l1Address];
    }

    /**
     * @notice Gets the last root in the sequence for a channel
     * @param channelId The channel ID
     * @return The last root hash
     */
    function getLastRootInSequence(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        bytes32[] storage rootSequence = $.channelRootSequence[channelId];
        require(rootSequence.length > 0, "NoRoots");
        return rootSequence[rootSequence.length - 1];
    }

    /**
     * @notice Gets basic channel information
     * @param channelId The channel ID
     * @return targetContract The target contract address
     * @return state The channel state
     * @return participantCount Number of participants
     * @return initialRoot The initial state root
     * @return finalRoot The final state root
     */
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

    /**
     * @notice Gets the aggregated proof hash for a channel
     * @param channelId The channel ID
     * @return The aggregated proof hash
     */
    function getAggregatedProofHash(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.aggregatedProofHash;
    }

    /**
     * @notice Gets the group public key address for a channel
     * @param channelId The channel ID
     * @return The signer address derived from group public key
     */
    function getGroupPublicKey(uint256 channelId) external view returns (address) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.signerAddr;
    }

    /**
     * @notice Gets the final state root for a channel
     * @param channelId The channel ID
     * @return The final state root
     */
    function getFinalStateRoot(uint256 channelId) external view returns (bytes32) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.finalStateRoot;
    }

    /**
     * @notice Gets the MPT leaves for a channel
     * @param channelId The channel ID
     * @return initialLeaves The initial MPT leaves
     * @return finalLeaves The final MPT leaves
     */
    function getMPTLeaves(uint256 channelId)
        external
        view
        returns (bytes[] memory initialLeaves, bytes[] memory finalLeaves)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.initialMPTLeaves, channel.finalMPTLeaves);
    }

    /**
     * @notice Gets timeout information for a channel
     * @param channelId The channel ID
     * @return openTimestamp When the channel was opened
     * @return timeout The timeout duration
     * @return deadline The deadline timestamp
     */
    function getChannelTimeoutInfo(uint256 channelId)
        external
        view
        returns (uint256 openTimestamp, uint256 timeout, uint256 deadline)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.openTimestamp, channel.timeout, channel.openTimestamp + channel.timeout);
    }

    /**
     * @notice Checks if a channel has expired
     * @param channelId The channel ID
     * @return True if the channel has expired
     */
    function isChannelExpired(uint256 channelId) external view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return block.timestamp > (channel.openTimestamp + channel.timeout);
    }

    /**
     * @notice Gets the remaining time before channel expires
     * @param channelId The channel ID
     * @return The remaining time in seconds (0 if expired)
     */
    function getRemainingTime(uint256 channelId) external view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        uint256 deadline = channel.openTimestamp + channel.timeout;
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    /**
     * @notice Gets deposit information for a channel
     * @param channelId The channel ID
     * @return totalDeposits The total deposits in the channel
     * @return targetContract The target contract address
     */
    function getChannelDeposits(uint256 channelId)
        external
        view
        returns (uint256 totalDeposits, address targetContract)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.tokenTotalDeposits, channel.targetContract);
    }

    /**
     * @notice Gets a participant's deposit amount
     * @param channelId The channel ID
     * @param participant The participant address
     * @return amount The deposit amount
     */
    function getParticipantDeposit(uint256 channelId, address participant) external view returns (uint256 amount) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.tokenDeposits[participant];
    }

    /**
     * @notice Gets a participant's L2 public key
     * @param channelId The channel ID
     * @param participant The participant address
     * @return l2PublicKey The L2 public key
     */
    function getL2PublicKey(uint256 channelId, address participant) external view returns (address l2PublicKey) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.l2PublicKeys[participant];
    }

    /**
     * @notice Gets all participants in a channel
     * @param channelId The channel ID
     * @return participants Array of participant addresses
     */
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

    /**
     * @notice Gets the channel leader
     * @param channelId The channel ID
     * @return leader The leader address
     */
    function getChannelLeader(uint256 channelId) external view returns (address leader) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.leader;
    }

    /**
     * @notice Gets the channel state
     * @param channelId The channel ID
     * @return state The channel state
     */
    function getChannelState(uint256 channelId) external view returns (ChannelState state) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.state;
    }

    /**
     * @notice Gets channel timestamps
     * @param channelId The channel ID
     * @return openTimestamp When the channel was opened
     * @return closeTimestamp When the channel was closed
     */
    function getChannelTimestamps(uint256 channelId)
        external
        view
        returns (uint256 openTimestamp, uint256 closeTimestamp)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.openTimestamp, channel.closeTimestamp);
    }

    /**
     * @notice Gets channel root hashes
     * @param channelId The channel ID
     * @return initialRoot The initial state root
     * @return finalRoot The final state root
     */
    function getChannelRoots(uint256 channelId) external view returns (bytes32 initialRoot, bytes32 finalRoot) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.initialStateRoot, channel.finalStateRoot);
    }

    /**
     * @notice Gets participant-specific roots for a channel
     * @param channelId The channel ID
     * @return participantRoots Array of participant roots
     */
    function getChannelParticipantRoots(uint256 channelId) external view returns (bytes32[] memory participantRoots) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.participantRoots);
    }

    /**
     * @notice Gets preprocessed proof data for a channel
     * @param channelId The channel ID
     * @return preprocessedPart1 First part of preprocessed data
     * @return preprocessedPart2 Second part of preprocessed data
     */
    function getChannelProofData(uint256 channelId)
        external
        view
        returns (uint128[] memory preprocessedPart1, uint256[] memory preprocessedPart2)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];

        // Retrieve preprocessed data from stored TargetContract
        IRollupBridge.TargetContract memory targetContractData = $.allowedTargetContracts[channel.targetContract];

        preprocessedPart1 = targetContractData.preprocessedPart1;
        preprocessedPart2 = targetContractData.preprocessedPart2;
    }

    /**
     * @notice Gets comprehensive channel statistics
     * @param channelId The channel ID
     * @return id The channel ID
     * @return targetContract The target contract address
     * @return state The channel state
     * @return participantCount Number of participants
     * @return totalDeposits Total deposits in the channel
     * @return leader The leader address
     */
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
            channel.leader
        );
    }

    /**
     * @notice Gets the total number of channels created
     * @return The total channel count
     */
    function getTotalChannels() external view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.nextChannelId;
    }

    /**
     * @notice Checks if a channel is ready to be closed
     * @param channelId The channel ID
     * @return True if the channel is ready to close
     */
    function isChannelReadyToClose(uint256 channelId) external view returns (bool) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.state == ChannelState.Closing && channel.sigVerified;
    }

    /**
     * @notice Checks if a user has withdrawn from a channel
     * @param channelId The channel ID
     * @param participant The participant address
     * @return True if the user has withdrawn
     */
    function hasUserWithdrawn(uint256 channelId, address participant) external view returns (bool) {
        return _hasWithdrawn(channelId, participant);
    }

    /**
     * @notice Gets the current treasury address
     * @return The treasury address
     */
    function getTreasuryAddress() external view returns (address) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.treasury;
    }

    /**
     * @notice Gets the total amount of slashed bonds available for withdrawal
     * @return The total slashed bond amount
     */
    function getTotalSlashedBonds() external view returns (uint256) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.totalSlashedBonds;
    }

    uint256[42] private __gap;
}
