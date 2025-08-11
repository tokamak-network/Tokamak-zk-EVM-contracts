// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import {IVerifier} from "./interface/IVerifier.sol";
import {IZKRollupBridge} from "./interface/IZKRollupBridge.sol";
import "./merkleTree/MerkleTreeManager.sol";
import {Poseidon2} from "@poseidon/src/Poseidon2.sol";

interface ITargetContract {
    function balanceOf(address account) external view returns (uint256);
}

// ==================== Main Bridge Contract ====================

contract ZKRollupBridge is IZKRollupBridge, ReentrancyGuard, Ownable {
    using ECDSA for bytes32;

    modifier onlyAuthorized() {
        require(authorizedChannelCreators[msg.sender], "Not authorized");
        _;
    }

    // ========== CONSTANTS ==========
    uint256 public constant LOCK_TIMEOUT = 7 days;
    uint256 public constant CHALLENGE_PERIOD = 14 days;
    uint256 public constant MIN_PARTICIPANTS = 3;
    uint256 public constant MAX_PARTICIPANTS = 50;
    uint256 public constant SIGNATURE_THRESHOLD_PERCENT = 67; // 2/3 threshold
    address public constant ETH_TOKEN_ADDRESS = address(1);
    uint256 public constant BALANCE_SLOT = 0;
    uint32 public constant MERKLE_TREE_DEPTH = 6;

    // ========== MAPPINGS ==========
    mapping(uint256 => Channel) public channels;
    mapping(address => bool) public authorizedChannelCreators;
    mapping(address => bool) public isChannelLeader;

    // Poseidon hasher address
    address public immutable poseidonHasher;

    uint256 public nextChannelId;

    // ========== CONTRACTS ==========
    IVerifier public immutable zkVerifier;

    // ========== CONSTRUCTOR ==========
    constructor(address _zkVerifier, address _poseidonHasher) Ownable(msg.sender) {
        zkVerifier = IVerifier(_zkVerifier);
        poseidonHasher = _poseidonHasher;
    }

    // ========== Channel Opening ==========

    function authorizeCreator(address creator) external onlyOwner {
        authorizedChannelCreators[creator] = true;
    }

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

        // Deploy new MerkleTreeManager instance for this channel
        MerkleTreeManager merkleTree = new MerkleTreeManager(poseidonHasher, MERKLE_TREE_DEPTH);
        channel.merkleTreeContract = address(merkleTree);
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
            require(participant.code.length == 0, "Participant must be EOA");

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

    /// @dev Transfers tokens from the depositor address to the smart contract address.
    /// @return The difference between the contract balance before and after the transferring of funds.
    function _depositToken(address _from, IERC20 _token, uint256 _amount) internal returns (uint256) {
        uint256 balanceBefore = _token.balanceOf(address(this));
        _token.transferFrom(_from, address(this), _amount);
        uint256 balanceAfter = _token.balanceOf(address(this));

        return balanceAfter - balanceBefore;
    }

    // ========== MPT state management ==========

    /**
     * @dev Initialize channel state with MerkleTreeWrapper
     */
    function initializeChannelState(uint256 channelId) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Initialized, "Invalid state");
        require(msg.sender == channel.leader, "Not leader");

        MerkleTreeManager merkleTree = MerkleTreeManager(channel.merkleTreeContract);

        // Prepare arrays
        address[] memory l1Addresses = new address[](channel.participants.length);
        uint256[] memory balances = new uint256[](channel.participants.length);

        // Single loop to set up mappings and prepare data
        for (uint256 i = 0; i < channel.participants.length; ++i) {
            address l1Address = channel.participants[i].l1Address;
            address l2Address = channel.participants[i].l2PublicKey;
            
            // Set address pair
            merkleTree.setAddressPair(l1Address, l2Address);
            
            // Prepare arrays for batch addition
            l1Addresses[i] = l1Address;
            balances[i] = channel.tokenDeposits[l1Address];
        }

        // Add all users to the merkle tree
        merkleTree.addUsers(l1Addresses, balances);

        // Store the initial merkle root
        channel.initialStateRoot = merkleTree.getCurrentRoot();
        channel.state = ChannelState.Open;

        emit StateInitialized(channelId, channel.initialStateRoot);
    }

    // ========== Proof submission and Signing ==========

    function submitAggregatedProof(uint256 channelId, bytes32 aggregatedProofHash, bytes32 finalStateRoot) external {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Open || channel.state == ChannelState.Active, "Invalid state");
        require(msg.sender == channel.leader, "Only leader can submit");

        channel.aggregatedProofHash = aggregatedProofHash;
        channel.finalStateRoot = finalStateRoot;
        channel.state = ChannelState.Closing;

        emit ProofAggregated(channelId, aggregatedProofHash);
    }

    function signAggregatedProof(uint256 channelId, Signature calldata signature) external {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(!channel.hasSigned[msg.sender], "Already signed");

        // Get l2PublicKey from the mapping
        address l2PublicKey = channel.l2PublicKeys[msg.sender];
        require(l2PublicKey != address(0), "L2 public key not found");

        // Verify EdDSA signature on aggregated proof
        bytes32 message = keccak256(abi.encodePacked(channel.aggregatedProofHash, channel.finalStateRoot, channelId));

        // In production, implement proper EdDSA verification
        require(_verifyEdDSA(message, signature, l2PublicKey), "Invalid signature");

        channel.hasSigned[msg.sender] = true;
        channel.receivedSignatures++;
    }

    // ========== Channel Closing ==========

    function closeChannel(
        uint256 channelId,
        uint128[] calldata proofPart1,
        uint256[] calldata proofPart2,
        uint256[] calldata publicInputs,
        uint256 smax
    ) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(msg.sender == channel.leader || msg.sender == owner(), "unauthorized caller");
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(channel.receivedSignatures >= channel.requiredSignatures, "Insufficient signatures");

        // Verify the aggregated ZK proof
        require(
            zkVerifier.verify(
                proofPart1, proofPart2, channel.preprocessedPart1, channel.preprocessedPart2, publicInputs, smax
            ),
            "Invalid ZK proof"
        );

        // Clear storage and close channel
        channel.state = ChannelState.Closed;
        channel.closeTimestamp = block.timestamp;

        emit ChannelClosed(channelId);
    }

    // ========== Withdraw Functions ==========

    /**
     * @dev Withdraw after channel closure with merkle proof
     * @param channelId The channel ID
     * @param claimedBalance The claimed final balance
     * @param leafIndex The index of the user's leaf in the merkle tree
     * @param merkleProof Array of sibling hashes for the merkle proof
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

        MerkleTreeManager merkleTree = MerkleTreeManager(channel.merkleTreeContract);

        // Get user's L2 address
        address l2Address = merkleTree.getL2Address(msg.sender);
        require(l2Address != address(0), "L2 address not found");

        // Get the previous root (last root before final state)
        bytes32 prevRoot = merkleTree.getLastRootInSequence();

        // Compute the leaf value for the claimed balance
        bytes32 leafValue = merkleTree.computeLeafForVerification(l2Address, claimedBalance, prevRoot);

        // Verify the merkle proof against the final state root
        require(
            merkleTree.verifyProof(merkleProof, leafValue, leafIndex, channel.finalStateRoot), "Invalid merkle proof"
        );

        channel.hasWithdrawn[msg.sender] = true;

        // Process withdrawal with the verified balance
        if (channel.targetContract == ETH_TOKEN_ADDRESS) {
            (bool success,) = msg.sender.call{value: claimedBalance}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(channel.targetContract).transfer(msg.sender, claimedBalance);
        }

        emit Withdrawn(channelId, msg.sender, channel.targetContract, claimedBalance);
    }
    // ====== Delete Channel Functions ======

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

    // ========== Helper Functions ==========

    function _verifyEdDSA(bytes32 message, Signature calldata signature, address publicKey)
        internal
        pure
        returns (bool)
    {
        require(message != bytes32(0), "wrong message");
        require(signature.R_x != signature.R_y, "wrong signature");
        require(publicKey != address(0), "wrong publicKey");
        // Simplified EdDSA verification
        // In production, implement proper EdDSA verification
        return true;
    }

    /**
     * @dev Read contract storage helper
     */
    function _readContractStorage(address target, uint256 slot) internal view returns (bytes32 value) {
        assembly ("memory-safe") {
            value := sload(slot)
        }

        // For external contracts, we need to use staticcall
        if (target != address(this)) {
            (bool success, bytes memory data) = target.staticcall(abi.encodeWithSignature("storageAt(uint256)", slot));

            if (success && data.length > 0) {
                value = abi.decode(data, (bytes32));
            }
        }
    }

    /**
     * @dev Get contract bytecode
     */
    function _getContractCode(address target) internal view returns (bytes memory) {
        uint256 size;
        assembly ("memory-safe") {
            size := extcodesize(target)
        }

        bytes memory code = new bytes(size);
        assembly ("memory-safe") {
            extcodecopy(target, add(code, 0x20), 0, size)
        }

        return code;
    }

    // ========== View Functions ==========

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
}
