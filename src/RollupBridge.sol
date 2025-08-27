// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import {IVerifier} from "./interface/IVerifier.sol";
import {IRollupBridge} from "./interface/IRollupBridge.sol";
import {IMerkleTreeManager} from "./interface/IMerkleTreeManager.sol";
import "./library/RLP.sol";

/**
 * @title RollupBridge
 * @author Tokamak Ooo project
 * @notice Main bridge contract for managing zkRollup channels
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
 */
contract RollupBridge is IRollupBridge, ReentrancyGuard, Ownable {
    using ECDSA for bytes32;
    using RLP for bytes;
    using RLP for RLP.RLPItem;

    /**
     * @dev Authorized channel creators only
     */
    modifier onlyAuthorized() {
        require(authorizedChannelCreators[msg.sender], "Not authorized");
        _;
    }

    // ========== CONSTANTS ==========
    uint256 public constant CHALLENGE_PERIOD = 14 days;
    uint256 public constant MIN_PARTICIPANTS = 3;
    uint256 public constant MAX_PARTICIPANTS = 50;
    uint256 public constant SIGNATURE_THRESHOLD_PERCENT = 67; // 2/3 threshold
    uint256 public constant NATIVE_TOKEN_TRANSFER_GAS_LIMIT = 1_000_000;
    address public constant ETH_TOKEN_ADDRESS = address(1);

    // ========== MAPPINGS ==========
    mapping(uint256 => Channel) public channels;
    mapping(address => bool) public authorizedChannelCreators;
    mapping(address => bool) public isChannelLeader;

    uint256 public nextChannelId;

    // ========== CONTRACTS ==========
    IVerifier public immutable zkVerifier;
    IMerkleTreeManager public immutable mtmanager;

    // ========== CONSTRUCTOR ==========
    constructor(address _zkVerifier, address _mtmanager) Ownable(msg.sender) {
        zkVerifier = IVerifier(_zkVerifier);
        mtmanager = IMerkleTreeManager(_mtmanager);
    }

    // ========== Channel Opening ==========

    /**
     * @notice Authorizes an address to create new channels
     * @param creator Address to authorize for channel creation
     * @dev Only callable by the contract owner
     */
    function authorizeCreator(address creator) external onlyOwner {
        authorizedChannelCreators[creator] = true;
    }

    /**
     * @notice Opens a new zkRollup channel with specified participants
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
        require(!isChannelLeader[msg.sender], "Channel limit reached");
        require(
            participants.length >= MIN_PARTICIPANTS && participants.length <= MAX_PARTICIPANTS,
            "Invalid participant number"
        );
        require(participants.length == l2PublicKeys.length, "Mismatched arrays");
        require(timeout >= 1 hours && timeout <= 7 days, "Invalid timeout");

        unchecked {
            channelId = nextChannelId++;
        }

        isChannelLeader[msg.sender] = true;
        Channel storage channel = channels[channelId];

        channel.id = channelId;
        channel.targetContract = targetContract;
        channel.leader = msg.sender;
        channel.openTimestamp = block.timestamp;
        channel.timeout = timeout;
        channel.preprocessedPart1 = preprocessedPart1;
        channel.preprocessedPart2 = preprocessedPart2;
        channel.state = ChannelState.Initialized;
        channel.groupPublicKey = groupPublicKey;

        // Register participants and their public keys
        for (uint256 i = 0; i < participants.length; ++i) {
            address participant = participants[i];
            require(!channel.isParticipant[participant], "Duplicate participant");

            // Create and push User struct
            channel.participants.push(User({l1Address: participant, l2PublicKey: l2PublicKeys[i]}));

            channel.isParticipant[participant] = true;

            // Also store in mapping for easy access
            channel.l2PublicKeys[participant] = l2PublicKeys[i];
        }

        // Calculate signature threshold (2/3 of participants)
        channel.requiredSignatures = (participants.length * SIGNATURE_THRESHOLD_PERCENT) / 100;
        if (channel.requiredSignatures == 0) {
            channel.requiredSignatures = 1;
        }

        emit ChannelOpened(channelId, targetContract);
    }

    // ========== Deposit Functions ==========

    /**
     * @notice Deposits ETH into a channel
     * @param _channelId ID of the channel to deposit into
     * @dev Requirements:
     *      - Channel must be in Initialized state
     *      - Caller must be a participant in the channel
     *      - Value must be greater than 0
     *      - Channel must be configured for ETH deposits
     */
    function depositETH(uint256 _channelId) external payable nonReentrant {
        Channel storage channel = channels[_channelId];
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
     * @param _channelId ID of the channel to deposit into
     * @param _token Address of the ERC20 token contract
     * @param _amount Amount of tokens to deposit
     * @dev Requirements:
     *      - Channel must be in Initialized state
     *      - Caller must be a participant in the channel
     *      - Token must match the channel's target contract
     *      - Amount must be greater than 0
     *      - Caller must have approved this contract for the token amount
     */
    function depositToken(uint256 _channelId, address _token, uint256 _amount) external nonReentrant {
        Channel storage channel = channels[_channelId];
        require(channel.state == ChannelState.Initialized, "Invalid channel state");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(_token != ETH_TOKEN_ADDRESS && _token == channel.targetContract, "Token must be ERC20 target contract");

        // Transfer tokens from user to this contract
        require(_amount != 0, "amount must be greater than 0"); // empty deposit
        uint256 amount = _depositToken(msg.sender, IERC20(_token), _amount);
        require(amount == _amount, "non ERC20 standard transfer logic"); // The token has non-standard transfer logic

        channel.tokenDeposits[msg.sender] += _amount;
        channel.tokenTotalDeposits += _amount;

        emit Deposited(_channelId, msg.sender, _token, _amount);
    }

    /**
     * @dev Internal function to handle token transfers with balance checking
     * @param _from Address to transfer tokens from
     * @param _token ERC20 token contract
     * @param _amount Amount to transfer
     * @return The actual amount transferred (handles fee-on-transfer tokens)
     */
    function _depositToken(address _from, IERC20 _token, uint256 _amount) internal returns (uint256) {
        uint256 balanceBefore = _token.balanceOf(address(this));
        _token.transferFrom(_from, address(this), _amount);
        uint256 balanceAfter = _token.balanceOf(address(this));

        return balanceAfter - balanceBefore;
    }

    // ========== MPT state management ==========

    /**
     * @notice Initializes the Merkle tree state for a channel with deposited balances
     * @param channelId ID of the channel to initialize
     * @dev This function:
     *      - Initializes a new Merkle tree for the channel
     *      - Sets up L1 to L2 address mappings
     *      - Adds all participants with their deposited balances to the tree
     *      - Transitions channel state from Initialized to Open
     *      Only callable by the channel leader
     */
    function initializeChannelState(uint256 channelId) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Initialized || channel.state == ChannelState.Open, "Invalid state");
        require(msg.sender == channel.leader, "Not leader");
        // Prepare arrays
        address[] memory l1Addresses = new address[](channel.participants.length);
        uint256[] memory balances = new uint256[](channel.participants.length);

        mtmanager.initializeChannel(channelId);

        // Single loop to set up mappings and prepare data
        for (uint256 i = 0; i < channel.participants.length; ++i) {
            address l1Address = channel.participants[i].l1Address;
            address l2Address = channel.participants[i].l2PublicKey;

            // Set address pair
            mtmanager.setAddressPair(channelId, l1Address, l2Address);

            // Prepare arrays for batch addition
            l1Addresses[i] = l1Address;
            balances[i] = channel.tokenDeposits[l1Address];
        }

        // Add all users to the merkle tree
        mtmanager.addUsers(channelId, l1Addresses, balances);

        // Store the initial merkle root
        channel.initialStateRoot = mtmanager.getCurrentRoot(channelId);
        if (channel.state == ChannelState.Initialized) {
            channel.state = ChannelState.Open;
        }

        emit StateInitialized(channelId, channel.initialStateRoot);
    }

    // ========== Proof submission and Signing ==========

    /**
     * @notice Submits an aggregated ZK proof for channel state transition with MPT leaves verification
     * @param channelId ID of the channel
     * @param proofData Struct containing all proof-related data including:
     *        - aggregatedProofHash: Hash of the aggregated proof data
     *        - finalStateRoot: New Merkle root representing the final state
     *        - proofPart1: First part of the ZK proof data
     *        - proofPart2: Second part of the ZK proof data
     *        - publicInputs: Public inputs for the ZK proof verification
     *        - smax: Maximum value for the proof verification
     *        - initialMPTLeaves: Array of initial MPT leaf values (off-chain state trie leaves representing deposited balances)
     *        - finalMPTLeaves: Array of final MPT leaf values (off-chain state trie leaves after L2 computation)
     * @dev Requirements:
     *      - Channel must be in Open or Active state
     *      - Only the channel leader can submit proofs
     *      - Sum of balances extracted from initial MPT leaves must equal total deposited amount
     *      - Sum of balances from final MPT leaves must equal sum from initial MPT leaves (conservation)
     *      - The ZK proof must be valid according to the verifier
     *      Transitions channel to Closing state upon successful submission
     */
    function submitAggregatedProof(uint256 channelId, ProofData calldata proofData) external {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Open || channel.state == ChannelState.Active, "Invalid state");
        require(msg.sender == channel.leader, "Only leader can submit");
        require(proofData.initialMPTLeaves.length == proofData.finalMPTLeaves.length, "Mismatched leaf arrays");
        require(proofData.initialMPTLeaves.length == channel.participants.length, "Invalid leaf count");

        // Extract and verify balance conservation from MPT leaves
        uint256 initialBalanceSum = 0;
        uint256 finalBalanceSum = 0;

        for (uint256 i = 0; i < proofData.initialMPTLeaves.length; ++i) {
            // Extract balance from initial MPT leaf (off-chain state trie format)
            uint256 initialBalance = _extractBalanceFromMPTLeaf(proofData.initialMPTLeaves[i]);
            initialBalanceSum += initialBalance;

            // Extract balance from final MPT leaf (off-chain state trie format)
            uint256 finalBalance = _extractBalanceFromMPTLeaf(proofData.finalMPTLeaves[i]);
            finalBalanceSum += finalBalance;
        }

        // Check that initial balance sum matches the total deposited amount
        require(initialBalanceSum == channel.tokenTotalDeposits, "Initial balance mismatch");

        // Check balance conservation: no tokens created or destroyed during L2 computation
        require(initialBalanceSum == finalBalanceSum, "Balance conservation violated");

        // Store the MPT leaves for later verification during channel closure
        channel.initialMPTLeaves = proofData.initialMPTLeaves;
        channel.finalMPTLeaves = proofData.finalMPTLeaves;

        channel.aggregatedProofHash = proofData.aggregatedProofHash;
        channel.finalStateRoot = proofData.finalStateRoot;
        channel.state = ChannelState.Closing;

        // Verify the aggregated ZK proof
        require(
            zkVerifier.verify(
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

    /**
     * @dev Assembly function to extract balance from an MPT leaf
     * @param mptLeaf The MPT leaf data in bytes format (RLP-encoded account data)
     * @return extractedBalance The balance value extracted from the leaf
     * @notice Efficient RLP parser for Ethereum account structure
     */
    function _extractBalanceFromMPTLeaf(bytes calldata mptLeaf) internal pure returns (uint256 extractedBalance) {
        assembly {
            let dataPtr := mptLeaf.offset
            let dataLen := mptLeaf.length

            // Minimal validation - revert with code 0x01 if empty
            if iszero(dataLen) {
                mstore(0, 0x01)
                revert(0, 0x20)
            }

            // Read first byte directly from calldata
            let firstByte := byte(0, calldataload(dataPtr))

            // Check if it's a list (>= 0xc0) - revert with code 0x02 if not
            if lt(firstByte, 0xc0) {
                mstore(0, 0x02)
                revert(0, 0x20)
            }

            // Calculate list content offset
            let contentOffset := 1

            // Handle list length encoding
            if gt(firstByte, 0xf7) {
                // Long list (0xf8+)
                let lenOfLen := sub(firstByte, 0xf7)
                contentOffset := add(1, lenOfLen)
            }

            // Move to list content
            dataPtr := add(dataPtr, contentOffset)

            // Read and skip nonce (first field)
            let nonceHeader := byte(0, calldataload(dataPtr))

            // Calculate how many bytes to skip for nonce
            let skipBytes := 1

            if gt(nonceHeader, 0x7f) {
                if lt(nonceHeader, 0xb8) {
                    // Short string (0x80-0xb7)
                    skipBytes := add(1, sub(nonceHeader, 0x80))
                }
                // For long strings (0xb8+), simplified handling
                if gt(nonceHeader, 0xb7) {
                    let lenOfLen := sub(nonceHeader, 0xb7)
                    let lengthBytes := byte(0, calldataload(add(dataPtr, 1)))
                    skipBytes := add(add(1, lenOfLen), lengthBytes)
                }
            }

            // Move pointer past nonce to balance field
            dataPtr := add(dataPtr, skipBytes)

            // Read balance header
            let balHeader := byte(0, calldataload(dataPtr))

            // Extract balance value based on encoding
            switch lt(balHeader, 0x80)
            case 1 {
                // Single byte (0x00-0x7f)
                extractedBalance := balHeader
            }
            default {
                switch eq(balHeader, 0x80)
                case 1 {
                    // Empty string = 0
                    extractedBalance := 0
                }
                default {
                    if lt(balHeader, 0xb8) {
                        // Short string (0x81-0xb7)
                        let balLen := sub(balHeader, 0x80)

                        // Read balance value (shift to get correct bytes)
                        let rawData := calldataload(add(dataPtr, 1))
                        extractedBalance := shr(sub(256, mul(8, balLen)), rawData)
                    }

                    if gt(balHeader, 0xb7) {
                        // Long string (0xb8+) - rare for balances
                        let lenOfLen := sub(balHeader, 0xb7)

                        // Read actual length
                        let lengthData := calldataload(add(dataPtr, 1))
                        let balLen := shr(sub(256, mul(8, lenOfLen)), lengthData)

                        // Revert if balance is too large (code 0x04)
                        if gt(balLen, 32) {
                            mstore(0, 0x04)
                            revert(0, 0x20)
                        }

                        // Read balance value
                        let rawData := calldataload(add(add(dataPtr, 1), lenOfLen))
                        extractedBalance := shr(sub(256, mul(8, balLen)), rawData)
                    }
                }
            }
        }
    }

    /**
     * @notice Allows participants to sign the aggregated proof
     * @param channelId ID of the channel
     * @param signatures Array of EdDSA signatures from the participants (R, S) as per documentation
     * @dev Requirements:
     *      - Channel must be in Closing state
     *      - Caller must be the channel leader or contract owner
     *      - Group threshold signature must be valid
     */
    function signAggregatedProof(uint256 channelId, Signature[] calldata signatures) external {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(msg.sender == channel.leader || msg.sender == owner(), "Not leader or owner");

        channel.receivedSignatures = signatures.length;

        require(_verifyGroupThresholdSignature(channelId), "Invalid group threshold signature");

        // Emit event for aggregated proof signing
        emit AggregatedProofSigned(channelId, msg.sender, channel.receivedSignatures, channel.requiredSignatures);
    }

    /**
     * @dev Verifies that the collected signatures meet the group threshold requirements
     * @param channelId The channel ID to verify
     * @return True if the group threshold signature verification passes
     */
    function _verifyGroupThresholdSignature(uint256 channelId) internal view returns (bool) {
        Channel storage channel = channels[channelId];

        // Check if we have enough signatures
        if (channel.receivedSignatures < channel.requiredSignatures) {
            return false;
        }

        // Validate that the required signatures is not zero
        require(channel.requiredSignatures > 0, "Invalid required signatures");

        // Validate that the participant count is valid
        uint256 participantCount = channel.participants.length;
        require(participantCount >= MIN_PARTICIPANTS, "Invalid participant count");

        // Verify the threshold calculation matches the stored value
        uint256 calculatedThreshold = (participantCount * SIGNATURE_THRESHOLD_PERCENT) / 100;
        if (calculatedThreshold == 0) {
            calculatedThreshold = 1; // Ensure at least 1 signature is required
        }
        require(channel.requiredSignatures == calculatedThreshold, "Threshold mismatch");

        // TODO: Implement proper group threshold signature verification
        // This would involve:
        // 1. Verifying the aggregated signature against the group public key
        // 2. Ensuring the threshold requirement is met
        // 3. Validating that the aggregated signature is cryptographically sound

        // For now, we'll use a simplified verification that checks the threshold
        // Basic threshold check - ensure we have at least the required number of signatures
        return channel.receivedSignatures >= channel.requiredSignatures;
    }

    // ========== Channel Closing ==========

    /**
     * @notice Closes a channel after sufficient signatures are collected
     * @param channelId ID of the channel to close
     * @dev Requirements:
     *      - Caller must be the channel leader or contract owner
     *      - Channel must be in Closing state
     *      - Required number of signatures must be collected
     *      Transitions channel to Closed state
     */
    function closeChannel(uint256 channelId) external {
        Channel storage channel = channels[channelId];
        require(msg.sender == channel.leader || msg.sender == owner(), "unauthorized caller");
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(channel.receivedSignatures >= channel.requiredSignatures, "Insufficient signatures");

        // Clear storage and close channel
        channel.state = ChannelState.Closed;
        channel.closeTimestamp = block.timestamp;

        emit ChannelClosed(channelId);
    }

    // ========== Withdraw Functions ==========

    /**
     * @notice Withdraws funds after channel closure using a Merkle proof
     * @param channelId ID of the channel to withdraw from
     * @param claimedBalance The final balance being claimed
     * @param leafIndex Index of the user's leaf in the Merkle tree
     * @param merkleProof Array of sibling hashes for Merkle proof verification
     * @dev Requirements:
     *      - Channel must be in Closed state
     *      - Caller must be a participant who hasn't withdrawn yet
     *      - Merkle proof must be valid for the claimed balance
     *      Transfers the verified balance to the caller
     */
    function withdrawAfterClose(
        uint256 channelId,
        uint256 claimedBalance,
        uint256 leafIndex,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Closed, "Not closed");
        require(!channel.hasWithdrawn[msg.sender], "Already withdrawn");
        require(channel.isParticipant[msg.sender], "Not a participant");

        // Get user's L2 address
        address l2Address = mtmanager.getL2Address(channelId, msg.sender);
        require(l2Address != address(0), "L2 address not found");

        // Get the previous root (last root before final state)
        bytes32 prevRoot = mtmanager.getLastRootInSequence(channelId);

        // Compute the leaf value for the claimed balance
        bytes32 leafValue = mtmanager.computeLeafForVerification(l2Address, claimedBalance, prevRoot);

        // Verify the merkle proof against the final state root
        require(
            mtmanager.verifyProof(channelId, merkleProof, leafValue, leafIndex, channel.finalStateRoot),
            "Invalid merkle proof"
        );

        // CEI pattern respected
        channel.hasWithdrawn[msg.sender] = true;

        // Process withdrawal with the verified balance
        if (channel.targetContract == ETH_TOKEN_ADDRESS) {
            bool success;
            uint256 gasLimit = NATIVE_TOKEN_TRANSFER_GAS_LIMIT;
            // use an assembly call to avoid loading large data into memory
            // input mem[in...(in+insize)]
            // output area mem[out...(out+outsize)]
            assembly {
                success :=
                    call(
                        gasLimit,
                        caller(),
                        claimedBalance,
                        0, // in
                        0, // insize
                        0, // out
                        0 // outsize
                    )
            }
            require(success, "ETH transfer failed");
        } else {
            IERC20(channel.targetContract).transfer(msg.sender, claimedBalance);
        }

        emit Withdrawn(channelId, msg.sender, channel.targetContract, claimedBalance);
    }

    // ====== Delete Channel Functions ======

    /**
     * @notice Deletes a channel after the challenge period has passed
     * @param channelId ID of the channel to delete
     * @return bool True if deletion was successful
     * @dev Requirements:
     *      - Caller must be the owner or channel leader
     *      - Channel must be in Closed state
     *      - Challenge period must have elapsed
     *      Removes all channel data and frees the leader to create new channels
     */
    function deleteChannel(uint256 channelId) external returns (bool) {
        Channel storage channel = channels[channelId];
        require(msg.sender == owner() || msg.sender == channel.leader, "only owner or leader");
        require(channel.state == ChannelState.Closed, "Channel not closed");
        require(block.timestamp >= channel.closeTimestamp + CHALLENGE_PERIOD);

        delete channels[channelId];
        isChannelLeader[msg.sender] = false;

        emit ChannelDeleted(channelId);
        return true;
    }

    // ========== View Functions ==========

    /**
     * @notice Retrieves comprehensive information about a channel
     * @param channelId ID of the channel to query
     * @return targetContract Address of the token contract for this channel
     * @return state Current state of the channel
     * @return participantCount Number of participants in the channel
     * @return initialRoot Initial Merkle tree root
     * @return finalRoot Final Merkle tree root after state transitions
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
        Channel storage channel = channels[channelId];
        return (
            channel.targetContract,
            channel.state,
            channel.participants.length,
            channel.initialStateRoot,
            channel.finalStateRoot
        );
    }

    /**
     * @notice Checks if a channel is ready to be closed (has enough signatures)
     * @param channelId ID of the channel
     * @return True if the channel has enough signatures to be closed
     */
    function isChannelReadyToClose(uint256 channelId) external view returns (bool) {
        Channel storage channel = channels[channelId];
        return channel.receivedSignatures >= channel.requiredSignatures;
    }

    /**
     * @notice Gets the aggregated proof hash that participants need to sign
     * @param channelId ID of the channel
     * @return The aggregated proof hash to be signed
     */
    function getAggregatedProofHash(uint256 channelId) external view returns (bytes32) {
        Channel storage channel = channels[channelId];
        return channel.aggregatedProofHash;
    }

    /**
     * @notice Gets the group public key for a channel
     * @param channelId ID of the channel
     * @return The group public key for signature verification
     */
    function getGroupPublicKey(uint256 channelId) external view returns (bytes32) {
        Channel storage channel = channels[channelId];
        return channel.groupPublicKey;
    }

    /**
     * @notice Gets the final state root for a channel
     * @param channelId ID of the channel
     * @return The final state root after proof aggregation
     */
    function getFinalStateRoot(uint256 channelId) external view returns (bytes32) {
        Channel storage channel = channels[channelId];
        return channel.finalStateRoot;
    }

    /**
     * @notice Gets the MPT leaves for a channel
     * @param channelId ID of the channel
     * @return initialLeaves Array of initial MPT leaf values
     * @return finalLeaves Array of final MPT leaf values
     */
    function getMPTLeaves(uint256 channelId)
        external
        view
        returns (bytes[] memory initialLeaves, bytes[] memory finalLeaves)
    {
        Channel storage channel = channels[channelId];
        return (channel.initialMPTLeaves, channel.finalMPTLeaves);
    }

    /**
     * @notice Gets the timeout information for a channel
     * @param channelId ID of the channel
     * @return openTimestamp When the channel was opened
     * @return timeout The timeout duration in seconds
     * @return deadline The absolute deadline timestamp
     */
    function getChannelTimeoutInfo(uint256 channelId)
        external
        view
        returns (uint256 openTimestamp, uint256 timeout, uint256 deadline)
    {
        Channel storage channel = channels[channelId];
        return (channel.openTimestamp, channel.timeout, channel.openTimestamp + channel.timeout);
    }

    /**
     * @notice Checks if a channel has expired
     * @param channelId ID of the channel
     * @return True if the channel has expired, false otherwise
     */
    function isChannelExpired(uint256 channelId) external view returns (bool) {
        Channel storage channel = channels[channelId];
        return block.timestamp > (channel.openTimestamp + channel.timeout);
    }

    /**
     * @notice Gets the remaining time before a channel expires
     * @param channelId ID of the channel
     * @return Remaining time in seconds (0 if expired)
     */
    function getRemainingTime(uint256 channelId) external view returns (uint256) {
        Channel storage channel = channels[channelId];
        uint256 deadline = channel.openTimestamp + channel.timeout;
        if (block.timestamp >= deadline) {
            return 0;
        }
        return deadline - block.timestamp;
    }

    /**
     * @notice Gets the total deposits for a channel
     * @param channelId ID of the channel
     * @return totalDeposits Total amount deposited in the channel
     * @return targetContract The token contract address (or ETH_TOKEN_ADDRESS for ETH)
     */
    function getChannelDeposits(uint256 channelId)
        external
        view
        returns (uint256 totalDeposits, address targetContract)
    {
        Channel storage channel = channels[channelId];
        return (channel.tokenTotalDeposits, channel.targetContract);
    }

    /**
     * @notice Gets the deposit amount for a specific participant
     * @param channelId ID of the channel
     * @param participant Address of the participant
     * @return amount The amount deposited by the participant
     */
    function getParticipantDeposit(uint256 channelId, address participant) external view returns (uint256 amount) {
        Channel storage channel = channels[channelId];
        return channel.tokenDeposits[participant];
    }

    /**
     * @notice Gets the L2 public key for a participant
     * @param channelId ID of the channel
     * @param participant Address of the participant
     * @return l2PublicKey The L2 public key for the participant
     */
    function getL2PublicKey(uint256 channelId, address participant) external view returns (address l2PublicKey) {
        Channel storage channel = channels[channelId];
        return channel.l2PublicKeys[participant];
    }

    /**
     * @notice Gets the list of all participants for a channel
     * @param channelId ID of the channel
     * @return participants Array of participant addresses
     */
    function getChannelParticipants(uint256 channelId) external view returns (address[] memory participants) {
        Channel storage channel = channels[channelId];
        uint256 participantCount = channel.participants.length;
        participants = new address[](participantCount);

        for (uint256 i = 0; i < participantCount; i++) {
            participants[i] = channel.participants[i].l1Address;
        }

        return participants;
    }

    /**
     * @notice Gets the channel leader
     * @param channelId ID of the channel
     * @return leader The address of the channel leader
     */
    function getChannelLeader(uint256 channelId) external view returns (address leader) {
        Channel storage channel = channels[channelId];
        return channel.leader;
    }

    /**
     * @notice Gets the current state of a channel
     * @param channelId ID of the channel
     * @return state The current state of the channel
     */
    function getChannelState(uint256 channelId) external view returns (ChannelState state) {
        Channel storage channel = channels[channelId];
        return channel.state;
    }

    /**
     * @notice Gets the timestamps for a channel
     * @param channelId ID of the channel
     * @return openTimestamp When the channel was opened
     * @return closeTimestamp When the channel was closed (0 if not closed)
     */
    function getChannelTimestamps(uint256 channelId)
        external
        view
        returns (uint256 openTimestamp, uint256 closeTimestamp)
    {
        Channel storage channel = channels[channelId];
        return (channel.openTimestamp, channel.closeTimestamp);
    }

    /**
     * @notice Gets the Merkle tree roots for a channel
     * @param channelId ID of the channel
     * @return initialRoot The initial state root
     * @return finalRoot The final state root (bytes32(0) if not set)
     */
    function getChannelRoots(uint256 channelId) external view returns (bytes32 initialRoot, bytes32 finalRoot) {
        Channel storage channel = channels[channelId];
        return (channel.initialStateRoot, channel.finalStateRoot);
    }

    /**
     * @notice Gets the preprocessed proof data for a channel
     * @param channelId ID of the channel
     * @return preprocessedPart1 First part of preprocessed verification data
     * @return preprocessedPart2 Second part of preprocessed verification data
     */
    function getChannelProofData(uint256 channelId)
        external
        view
        returns (uint128[] memory preprocessedPart1, uint256[] memory preprocessedPart2)
    {
        Channel storage channel = channels[channelId];
        return (channel.preprocessedPart1, channel.preprocessedPart2);
    }

    /**
     * @notice Gets comprehensive statistics for a channel
     * @param channelId ID of the channel
     * @return id The channel ID
     * @return targetContract The token contract address
     * @return state The current channel state
     * @return participantCount Total number of participants
     * @return totalDeposits Total amount deposited
     * @return requiredSignatures Number of signatures required
     * @return receivedSignatures Number of signatures collected
     * @return leader The channel leader address
     * @return groupPublicKey The group public key
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
            uint256 requiredSignatures,
            uint256 receivedSignatures,
            address leader,
            bytes32 groupPublicKey
        )
    {
        Channel storage channel = channels[channelId];
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

    /**
     * @notice Checks if an address is authorized to create channels
     * @param creator Address to check
     * @return True if the address is authorized, false otherwise
     */
    function isAuthorizedCreator(address creator) external view returns (bool) {
        return authorizedChannelCreators[creator];
    }
    /**
     * @notice Gets the total number of channels created
     * @return Total number of channels
     */

    function getTotalChannels() external view returns (uint256) {
        return nextChannelId;
    }
}
