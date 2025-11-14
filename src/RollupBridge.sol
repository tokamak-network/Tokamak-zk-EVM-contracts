// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "forge-std/console.sol";
import {ITokamakVerifier} from "./interface/ITokamakVerifier.sol";
import "./library/RLP.sol";
import {IZecFrost} from "./interface/IZecFrost.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./library/RollupBridgeLib.sol";
import "./interface/IGroth16Verifier64Leaves.sol";

/**
 * @title RollupBridgeUpgradeable
 * @author Tokamak Ooo project
 * @notice Upgradeable main bridge contract for managing zkRollup channels
 * @dev This contract manages the lifecycle of zkRollup channels including:
 *      - Channel creation and participant management
 *      - Deposit handling for ETH and ERC20 tokens
 *      - Merkle tree state verification using Groth16 proofs
 *      - ZK proof submission and verification
 *      - Group Threshold Signature verification
 *      - Channel closure and withdrawal processing
 *
 * The contract uses a multi-signature approach where 2/3 of participants must sign
 * to approve state transitions. Each channel operates independently with its own
 * quaternary Merkle tree verified by Groth16 proofs, which provides
 * cryptographically secure state verification with zero-knowledge properties.
 *
 * @dev Upgradeable using UUPS pattern for enhanced security and gas efficiency
 */
contract RollupBridge is ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using ECDSAUpgradeable for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using RLP for bytes;
    using RLP for RLP.RLPItem;

    // ========== ENUMS ==========
    enum ChannelState {
        None,
        Initialized,
        Open,
        Active,
        Closing,
        Closed
    }

    // ========== STRUCTS ==========
    struct Signature {
        bytes32 message;
        uint256 rx;
        uint256 ry;
        uint256 z;
    }

    struct ChannelParams {
        address[] allowedTokens;
        address[] participants;
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
        bytes32[] participantRoots;
    }

    struct ChannelInitializationProof {
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
        bytes32 merkleRoot;
    }

    struct TargetContract {
        address contractAddress;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
        bytes1 storageSlot;
    }

    struct Channel {
        uint256 id;
        address[] allowedTokens;
        mapping(address => bool) isTokenAllowed;
        mapping(address => mapping(address => uint256)) tokenDeposits; // token => participant => amount
        mapping(address => uint256) tokenTotalDeposits; // token => total amount
        bytes32 initialStateRoot;
        bytes32 finalStateRoot;
        address[] participants;
        mapping(address => mapping(address => uint256)) l2MptKeys; // participant => token => L2 MPT key
        mapping(address => bool) isParticipant;
        ChannelState state;
        uint256 openTimestamp;
        uint256 closeTimestamp;
        uint256 timeout;
        address leader;
        uint256 leaderBond;
        bool leaderBondSlashed;
        bytes32 aggregatedProofHash;
        mapping(address => bool) hasWithdrawn;
        mapping(address => mapping(address => uint256)) withdrawAmount; // token => participant => amount
        uint256 pkx;
        uint256 pky;
        address signerAddr;
        bool sigVerified;
        bytes[] initialMPTLeaves;
        bytes[] finalMPTLeaves;
        bytes32[] participantRoots;
    }

    // ========== EVENTS ==========
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event TargetContractAllowed(address indexed targetContract, bool allowed);
    event L2AddressCollisionPrevented(uint256 indexed channelId, address l2Address, address attemptedUser);
    event ChannelOpened(uint256 indexed channelId, address[] allowedTokens);
    event StateInitialized(uint256 indexed channelId, bytes32 currentStateRoot);
    event ChannelClosed(uint256 indexed channelId);
    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event AggregatedProofSigned(uint256 indexed channelId, address indexed signer);
    event LeaderBondSlashed(uint256 indexed channelId, address indexed leader, uint256 bondAmount, string reason);
    event LeaderBondReclaimed(uint256 indexed channelId, address indexed leader, uint256 bondAmount);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);
    event SlashedBondsWithdrawn(address indexed treasury, uint256 amount);
    event ProofAggregated(uint256 indexed channelId, bytes32 proofHash);
    event ChannelFinalized(uint256 indexed channelId);
    event EmergencyWithdrawalsEnabled(uint256 indexed channelId);

    // ========== CONSTANTS ==========
    uint256 public constant PROOF_SUBMISSION_DEADLINE = 7 days; // Leader has 7 days after timeout to submit proof
    uint256 public constant MIN_PARTICIPANTS = 3;
    uint256 public constant MAX_PARTICIPANTS = 64;
    uint256 public constant NATIVE_TOKEN_TRANSFER_GAS_LIMIT = 1_000_000;
    address public constant ETH_TOKEN_ADDRESS = address(1);

    uint256 public constant LEADER_BOND_REQUIRED = 0.001 ether; // Leader must deposit this amount to open channel

    // ========== STORAGE ==========

    /// @custom:storage-location erc7201:tokamak.storage.RollupBridge
    struct RollupBridgeStorage {
        mapping(uint256 => Channel) channels;
        mapping(address => bool) isChannelLeader;
        mapping(address => TargetContract) allowedTargetContracts;
        mapping(address => bool) isTargetContractAllowed;
        uint256 nextChannelId;
        ITokamakVerifier zkVerifier; // on-chain zkSNARK verifier contract
        IZecFrost zecFrost; // on-chain sig verifier contract
        IGroth16Verifier64Leaves groth16Verifier; // Groth16 proof verifier contract
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
     * @param _groth16Verifier Address of the Groth16 verifier contract
     * @param _owner Address that will own the contract
     */
    function initialize(address _zkVerifier, address _zecFrost, address _groth16Verifier, address _owner)
        public
        initializer
    {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        _transferOwnership(_owner);
        __UUPSUpgradeable_init();

        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        $.zkVerifier = ITokamakVerifier(_zkVerifier);
        $.zecFrost = IZecFrost(_zecFrost);
        $.groth16Verifier = IGroth16Verifier64Leaves(_groth16Verifier);
    }

    // ========== EXTERNAL FUNCTIONS ==========

    /**
     * @notice Opens a new multi-token channel with specified participants and allowed tokens
     * @param params ChannelParams struct containing:
     *      - allowedTokens: Array of token contract addresses that can be deposited in this channel
     *                      (use ETH_TOKEN_ADDRESS for ETH). Each token must be pre-approved via setAllowedTargetContract
     *      - participants: Array of L1 addresses that will participate in the channel
     *      - timeout: Duration in seconds for which the channel will remain open
     *      - pkx: X coordinate of the aggregated public key for the channel group
     *      - pky: Y coordinate of the aggregated public key for the channel group
     * @return channelId Unique identifier for the created channel
     * @dev Requirements:
     *      - Caller must be authorized to create channels
     *      - Caller must send LEADER_BOND_REQUIRED ETH as leader bond
     *      - Caller cannot already be a channel leader
     *      - Must specify at least one allowed token
     *      - All specified tokens must be pre-approved via setAllowedTargetContract
     *      - Maximum participants = 64 / number_of_allowed_tokens (circuit capacity constraint)
     *      - Number of participants must be between 1 and calculated maximum
     *      - Timeout must be between 1 hour and 7 days
     *      - No duplicate participants or tokens allowed
     * @dev Each participant can deposit different tokens and must provide token-specific L2 MPT keys
     */
    function openChannel(ChannelParams calldata params) external payable returns (uint256 channelId) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();

        // Leader must deposit bond as collateral for their responsibilities
        require(msg.value == LEADER_BOND_REQUIRED, "Leader bond required");
        require(!$.isChannelLeader[msg.sender], "Channel limit reached");
        require(params.allowedTokens.length > 0, "Must specify at least one token");
        require(params.allowedTokens.length <= 4, "Maximum 4 tokens allowed");
        require(params.timeout >= 1 hours && params.timeout <= 365 days, "Invalid timeout");

        // Calculate maximum participants based on number of tokens
        // 64 circuit capacity / number_of_tokens = max participants
        uint256 maxParticipants = MAX_PARTICIPANTS / params.allowedTokens.length;
        require(
            params.participants.length >= MIN_PARTICIPANTS && params.participants.length <= maxParticipants,
            "Invalid participant number for token count"
        );

        // Validate all tokens are allowed
        uint256 tokensLength = params.allowedTokens.length;
        for (uint256 i = 0; i < tokensLength;) {
            address token = params.allowedTokens[i];
            require(token == ETH_TOKEN_ADDRESS || $.isTargetContractAllowed[token], "Token not allowed");

            // Check for duplicate tokens
            for (uint256 j = i + 1; j < tokensLength;) {
                require(params.allowedTokens[j] != token, "Duplicate token");
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        unchecked {
            channelId = $.nextChannelId++;
        }

        $.isChannelLeader[msg.sender] = true;
        Channel storage channel = $.channels[channelId];

        channel.id = channelId;
        channel.leader = msg.sender;
        channel.leaderBond = msg.value;
        channel.leaderBondSlashed = false;
        channel.openTimestamp = block.timestamp;
        channel.timeout = params.timeout;
        channel.state = ChannelState.Initialized;

        // Store allowed tokens
        for (uint256 i = 0; i < tokensLength;) {
            channel.allowedTokens.push(params.allowedTokens[i]);
            channel.isTokenAllowed[params.allowedTokens[i]] = true;
            unchecked {
                ++i;
            }
        }

        uint256 participantsLength = params.participants.length;
        for (uint256 i = 0; i < participantsLength;) {
            address participant = params.participants[i];

            require(!channel.isParticipant[participant], "Duplicate participant");

            channel.participants.push(participant);
            channel.isParticipant[participant] = true;

            unchecked {
                ++i;
            }
        }

        // store public key and generate signer address
        channel.pkx = params.pkx;
        channel.pky = params.pky;
        address signerAddr = RollupBridgeLib.deriveAddressFromPubkey(params.pkx, params.pky);
        channel.signerAddr = signerAddr;

        emit ChannelOpened(channelId, params.allowedTokens);
    }

    /**
     * @notice Deposits ETH into a channel
     * @param _channelId The ID of the channel to deposit into
     * @param _mptKey The MPT key for the participant (single bytes32)
     * @dev Only participants can deposit, channel must be in Initialized state
     */
    function depositETH(uint256 _channelId, bytes32 _mptKey) external payable nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[_channelId];
        require(channel.state == ChannelState.Initialized, "Invalid channel state");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(msg.value > 0, "Deposit must be greater than 0");
        require(channel.isTokenAllowed[ETH_TOKEN_ADDRESS], "ETH not allowed in this channel");
        require(_mptKey != bytes32(0), "Invalid MPT key");

        // Store the L2 MPT key for this participant and token
        channel.l2MptKeys[msg.sender][ETH_TOKEN_ADDRESS] = uint256(_mptKey);

        channel.tokenDeposits[ETH_TOKEN_ADDRESS][msg.sender] += msg.value;
        channel.tokenTotalDeposits[ETH_TOKEN_ADDRESS] += msg.value;

        emit Deposited(_channelId, msg.sender, ETH_TOKEN_ADDRESS, msg.value);
    }

    /**
     * @notice Deposits ERC20 tokens into a channel
     * @param _channelId The ID of the channel to deposit into
     * @param _token The token contract address (must match channel's target contract)
     * @param _amount The amount of tokens to deposit
     * @param _mptKey The MPT key for the participant (single bytes32)
     * @dev Only participants can deposit, channel must be in Initialized state
     */
    function depositToken(uint256 _channelId, address _token, uint256 _amount, bytes32 _mptKey) external nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[_channelId];
        require(channel.state == ChannelState.Initialized, "Invalid channel state");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(_token != ETH_TOKEN_ADDRESS, "Use depositETH for ETH deposits");
        require(channel.isTokenAllowed[_token], "Token not allowed in this channel");
        require(_mptKey != bytes32(0), "Invalid MPT key");

        // Store the L2 MPT key for this participant and token
        channel.l2MptKeys[msg.sender][_token] = uint256(_mptKey);

        require(_amount != 0, "amount must be greater than 0");
        uint256 actualAmount = RollupBridgeLib.depositToken(msg.sender, IERC20Upgradeable(_token), _amount);

        channel.tokenDeposits[_token][msg.sender] += actualAmount;
        channel.tokenTotalDeposits[_token] += actualAmount;

        emit Deposited(_channelId, msg.sender, _token, actualAmount);
    }

    /**
     * @notice Initializes channel state with Groth16 proof verification
     * @param channelId ID of the channel to initialize
     * @param proof Groth16 proof data containing pA, pB, pC components and merkle root
     * @dev The proof verifies that the provided merkle root correctly represents
     *      the channel participants and their deposit balances
     */
    function initializeChannelState(uint256 channelId, ChannelInitializationProof calldata proof)
        external
        nonReentrant
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.state == ChannelState.Initialized, "Invalid state");
        require(msg.sender == channel.leader, "Not leader");

        uint256 participantsLength = channel.participants.length;
        uint256 tokensLength = channel.allowedTokens.length;
        uint256 totalEntries = participantsLength * tokensLength;
        require(totalEntries <= 64, "Too many participant-token combinations for circuit");

        // Build public signals array for Groth16 verification
        uint256[129] memory publicSignals;

        // Fill merkle keys (L2 MPT keys) and storage values (balances)
        // Each participant has entries for each token type
        uint256 entryIndex = 0;
        for (uint256 i = 0; i < participantsLength;) {
            address l1Address = channel.participants[i];

            for (uint256 j = 0; j < tokensLength;) {
                address token = channel.allowedTokens[j];
                uint256 balance = channel.tokenDeposits[token][l1Address];
                uint256 l2MptKey = channel.l2MptKeys[l1Address][token];

                // If participant has deposited this token, they must have provided MPT key during deposit
                if (balance > 0) {
                    require(l2MptKey != 0, "Participant MPT key not set for token");
                }

                // Add to public signals:
                // - first 64 are merkle_keys (L2 MPT keys)
                // - next 64 are storage_values (balances)
                publicSignals[entryIndex] = l2MptKey; // L2 MPT key for specific token
                publicSignals[entryIndex + 64] = balance; // storage value

                unchecked {
                    ++j;
                    ++entryIndex;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Pad remaining slots with zeros (circuit expects exactly 64 entries)
        for (uint256 i = totalEntries; i < 64;) {
            publicSignals[i] = 0; // merkle key (L2 MPT key)
            publicSignals[i + 64] = 0; // storage value
            unchecked {
                ++i;
            }
        }

        // The 129th element is the computed merkle root (output of the circuit)
        publicSignals[128] = uint256(proof.merkleRoot);

        // Verify the Groth16 proof
        bool proofValid = $.groth16Verifier.verifyProof(proof.pA, proof.pB, proof.pC, publicSignals);

        require(proofValid, "Invalid Groth16 proof");

        // Store the verified merkle root and update state
        channel.initialStateRoot = proof.merkleRoot;
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

        // Get first token for simplified single-token proof verification (TODO: handle multiple tokens properly)
        address firstToken = channel.allowedTokens.length > 0 ? channel.allowedTokens[0] : ETH_TOKEN_ADDRESS;

        uint256 leavesLength = proofData.initialMPTLeaves.length;
        for (uint256 i = 0; i < leavesLength;) {
            uint256 initialBalance = RLP.extractBalanceFromMPTLeaf(proofData.initialMPTLeaves[i]);
            initialBalanceSum += initialBalance;

            uint256 finalBalance = RLP.extractBalanceFromMPTLeaf(proofData.finalMPTLeaves[i]);
            finalBalanceSum += finalBalance;

            // Store the withdrawable amount for each participant (using first token for now)
            address participantAddress = channel.participants[i];
            channel.withdrawAmount[firstToken][participantAddress] = finalBalance;

            unchecked {
                ++i;
            }
        }

        // For now, verify against first token total deposits (TODO: handle multiple tokens properly)
        require(initialBalanceSum == channel.tokenTotalDeposits[firstToken], "Initial balance mismatch");
        require(initialBalanceSum == finalBalanceSum, "Balance conservation violated");

        channel.initialMPTLeaves = proofData.initialMPTLeaves;
        channel.finalMPTLeaves = proofData.finalMPTLeaves;
        channel.participantRoots = proofData.participantRoots;
        channel.aggregatedProofHash = proofData.aggregatedProofHash;
        channel.finalStateRoot = proofData.finalStateRoot;
        channel.state = ChannelState.Closing;

        // Retrieve preprocessed data from stored TargetContract (using first token for now)
        TargetContract memory targetContractData = $.allowedTargetContracts[firstToken];
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
     * @notice Withdraws funds after channel closure
     * @param channelId The channel ID
     * @dev Only participants can withdraw once per channel
     *      The withdrawable amount was determined during proof verification
     */
    function withdrawAfterClose(uint256 channelId, address token) external nonReentrant {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];

        require(channel.state == ChannelState.Closed, "Not closed");
        require(!channel.hasWithdrawn[msg.sender], "Already withdrawn");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(channel.isTokenAllowed[token], "Token not allowed in this channel");

        // Get the withdrawable amount that was verified and stored during proof submission
        uint256 withdrawAmount = channel.withdrawAmount[token][msg.sender];
        require(withdrawAmount > 0, "No withdrawable amount or already withdrawn");

        channel.hasWithdrawn[msg.sender] = true;
        // Clear the withdrawable amount to prevent re-withdrawal
        channel.withdrawAmount[token][msg.sender] = 0;

        if (token == ETH_TOKEN_ADDRESS) {
            bool success;
            uint256 gasLimit = NATIVE_TOKEN_TRANSFER_GAS_LIMIT;
            assembly {
                success := call(gasLimit, caller(), withdrawAmount, 0, 0, 0, 0)
            }
            require(success, "ETH transfer failed");
        } else {
            // we use safeTransfer to make it compatible with custom tokens s.a USDT
            IERC20Upgradeable(token).safeTransfer(msg.sender, withdrawAmount);
        }

        emit Withdrawn(channelId, msg.sender, token, withdrawAmount);
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
        $.zkVerifier = ITokamakVerifier(_newVerifier);
        emit VerifierUpdated(oldVerifier, _newVerifier);
    }

    /**
     * @notice Updates the Groth16 verifier contract
     * @param _newGroth16Verifier Address of the new Groth16 verifier
     * @dev Only contract owner can update the Groth16 verifier
     */
    function updateGroth16Verifier(address _newGroth16Verifier) external onlyOwner {
        require(_newGroth16Verifier != address(0), "Invalid Groth16Verifier address");
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        $.groth16Verifier = IGroth16Verifier64Leaves(_newGroth16Verifier);
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
        bytes1 _storageSlot,
        bool allowed
    ) external onlyOwner {
        require(targetContract != address(0), "Invalid target contract address");
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();

        if (allowed) {
            // Store the target contract with its preprocessed data
            require(preprocessedPart1.length > 0, "preprocessedPart1 cannot be empty when allowing");
            require(preprocessedPart2.length > 0, "preprocessedPart2 cannot be empty when allowing");

            $.allowedTargetContracts[targetContract] = TargetContract({
                contractAddress: targetContract,
                preprocessedPart1: preprocessedPart1, // Store full array
                preprocessedPart2: preprocessedPart2, // Store full array
                storageSlot: _storageSlot
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
            participants[i] = channel.participants[i];
        }
        return participants;
    }

    /**
     * @notice Gets participant deposit amount for a specific token
     * @param channelId The channel ID
     * @param participant The participant address
     * @param token The token address
     * @return The deposit amount
     */
    function _getParticipantTokenDeposit(uint256 channelId, address participant, address token)
        internal
        view
        returns (uint256)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.channels[channelId].tokenDeposits[token][participant];
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
    function _getChannelState(uint256 channelId) internal view returns (ChannelState) {
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
    function zkVerifier() public view returns (ITokamakVerifier) {
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
    function getTargetContractData(address targetContract) public view returns (TargetContract memory) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        require($.isTargetContractAllowed[targetContract], "Target contract not allowed");
        return $.allowedTargetContracts[targetContract];
    }

    /**
     * @notice Gets the channel state
     * @param channelId The channel ID
     * @return state The channel state
     */
    function getChannelState(uint256 channelId) external view returns (ChannelState) {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.state;
    }

    /**
     * @notice Gets a participant's deposit amount for a specific token
     * @param channelId The channel ID
     * @param participant The participant address
     * @param token The token address
     * @return amount The deposit amount
     */
    function getParticipantTokenDeposit(uint256 channelId, address participant, address token)
        external
        view
        returns (uint256)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return channel.tokenDeposits[token][participant];
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
     * @notice Gets basic channel information
     * @param channelId The channel ID
     * @return allowedTokens Array of allowed token addresses
     * @return state The channel state
     * @return participantCount Number of participants
     * @return initialRoot The initial state root
     * @return finalRoot The final state root
     */
    function getChannelInfo(uint256 channelId)
        external
        view
        returns (
            address[] memory allowedTokens,
            ChannelState state,
            uint256 participantCount,
            bytes32 initialRoot,
            bytes32 finalRoot
        )
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (
            channel.allowedTokens,
            channel.state,
            channel.participants.length,
            channel.initialStateRoot,
            channel.finalStateRoot
        );
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
            participants[i] = channel.participants[i];
            unchecked {
                ++i;
            }
        }
        return participants;
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

        // Retrieve preprocessed data from stored TargetContract (using first token for now)
        address firstToken = channel.allowedTokens.length > 0 ? channel.allowedTokens[0] : ETH_TOKEN_ADDRESS;
        TargetContract memory targetContractData = $.allowedTargetContracts[firstToken];

        preprocessedPart1 = targetContractData.preprocessedPart1;
        preprocessedPart2 = targetContractData.preprocessedPart2;
    }

    /**
     * @notice Gets comprehensive channel statistics
     * @param channelId The channel ID
     * @return id The channel ID
     * @return allowedTokens Array of allowed token addresses
     * @return state The channel state
     * @return participantCount Number of participants
     * @return leader The leader address
     */
    function getChannelStats(uint256 channelId)
        external
        view
        returns (
            uint256 id,
            address[] memory allowedTokens,
            ChannelState state,
            uint256 participantCount,
            address leader
        )
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.id, channel.allowedTokens, channel.state, channel.participants.length, channel.leader);
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

    /**
     * @notice Gets the withdrawable amount for a participant in a channel for a specific token
     * @param channelId The channel ID
     * @param participant The participant address
     * @param token The token address
     * @return The withdrawable amount
     */
    function getWithdrawableAmount(uint256 channelId, address participant, address token)
        external
        view
        returns (uint256)
    {
        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        return $.channels[channelId].withdrawAmount[token][participant];
    }

    uint256[42] private __gap;
}
