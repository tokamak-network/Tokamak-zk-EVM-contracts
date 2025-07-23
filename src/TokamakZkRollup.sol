// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import {IVerifier} from "./interface/IVerifier.sol";
import {MerkleTree} from "./library/MerkleTree.sol";

interface ITargetContract {
    function balanceOf(address account) external view returns (uint256);
}

// ==================== Main Bridge Contract ====================

contract ZKRollupBridge is ReentrancyGuard {
    using ECDSA for bytes32;

    // ========== State Variables ==========
    struct Signature {
        uint256 R_x;
        uint256 R_y;
        uint256 s;
    }

    struct User {
        address l1Address;
        address l2PublicKey;
        bool isLocked;
        uint256 lockedAmount;
        uint256 lockTimestamp;
        mapping(address => uint256) tokenBalances; // token => amount
    }

    struct Channel {
        uint256 id;
        address targetContract;
        bytes32 computationType; // e.g., keccak256("TON_TRANSFER")
        // State roots
        bytes32 mptSnapshotRoot;
        bytes32[] zkMerkleRoots; // Multiple trees for different state components
        // Participants
        address[] participants;
        mapping(address => bool) isParticipant;
        mapping(address => uint256) participantDeposits; // ETH deposits
        mapping(address => mapping(address => uint256)) tokenDeposits; // token => user => amount
        // Channel state
        ChannelState state;
        uint256 openTimestamp;
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
        // Final balances after L2 computation
        mapping(address => uint256) finalEthBalances;
        mapping(address => mapping(address => uint256)) finalTokenBalances;
    }

    enum ChannelState {
        None,
        Initialized,
        Open,
        Active,
        Closing,
        Closed
    }

    // Mappings
    mapping(address => address) public l1ToL2Address;
    mapping(address => User) public users;
    mapping(uint256 => Channel) public channels;
    uint256 public nextChannelId;

    // Constants
    uint256 constant LOCK_TIMEOUT = 7 days;
    uint256 constant MIN_PARTICIPANTS = 3;
    uint256 constant SIGNATURE_THRESHOLD_PERCENT = 67; // 2/3 threshold
    address constant ETH_TOKEN_ADDRESS = address(1);

    // Contracts
    IVerifier public immutable zkVerifier;

    // Events
    event L2AddressAssigned(address indexed l1Address, address indexed l2Address);
    event ChannelOpened(uint256 indexed channelId, address indexed targetContract);
    event StateConverted(uint256 indexed channelId, bytes32[] zkRoots);
    event UserStateLocked(uint256 indexed channelId, address indexed user);
    event ProofAggregated(uint256 indexed channelId, bytes32 proofHash);
    event ChannelClosed(uint256 indexed channelId);
    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event EmergencyWithdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);

    // ========== Constructor ==========

    constructor(address _zkVerifier) {
        zkVerifier = IVerifier(_zkVerifier);
    }

    // ========== L2 Address Assignment ==========

    function assignL2Address(address l2Address, address l2PublicKey) external {
        require(l1ToL2Address[msg.sender] == address(0), "L2 address already assigned");

        l1ToL2Address[msg.sender] = l2Address;
        users[msg.sender].l1Address = msg.sender;
        users[msg.sender].l2PublicKey = l2PublicKey;

        emit L2AddressAssigned(msg.sender, l2Address);
    }

    // ========== Channel Opening ==========

    function openChannel(
        address targetContract,
        bytes32 computationType,
        address[] calldata participants,
        address[] calldata publicKeys,
        uint128[] calldata preprocessedPart1,
        uint256[] calldata preprocessedPart2,
        uint256 timeout
    ) external returns (uint256 channelId) {
        require(participants.length >= MIN_PARTICIPANTS, "Insufficient participants");
        require(participants.length == publicKeys.length, "Mismatched arrays");
        require(timeout >= 1 hours && timeout <= 7 days, "Invalid timeout");

        channelId = nextChannelId++;
        Channel storage channel = channels[channelId];

        channel.id = channelId;
        channel.targetContract = targetContract;
        channel.computationType = computationType;
        channel.leader = msg.sender;
        channel.openTimestamp = block.timestamp;
        channel.timeout = timeout;
        channel.preprocessedPart1 = preprocessedPart1;
        channel.preprocessedPart2 = preprocessedPart2;
        channel.state = ChannelState.Initialized;

        // Register participants and their public keys
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            require(!channel.isParticipant[participant], "Duplicate participant");

            channel.participants.push(participant);
            channel.isParticipant[participant] = true;

            // Store public keys for signature verification
            if (users[participant].l2PublicKey == address(0)) {
                users[participant].l2PublicKey = publicKeys[i];
            }
        }

        // Calculate signature threshold (2/3 of participants)
        channel.requiredSignatures = (participants.length * SIGNATURE_THRESHOLD_PERCENT) / 100;
        if (channel.requiredSignatures == 0) {
            channel.requiredSignatures = 1;
        }

        emit ChannelOpened(channelId, targetContract);
    }

    // ========== Deposit and Withdraw Functions ==========

    function depositETH(uint256 _channelId) external payable nonReentrant {
        Channel storage channel = channels[_channelId];
        require(
            channel.state == ChannelState.Initialized || channel.state == ChannelState.Open, "Invalid channel state"
        );
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(msg.value > 0, "Deposit must be greater than 0");
        require(channel.targetContract == ETH_TOKEN_ADDRESS, "Token must be set to ETH");

        channel.participantDeposits[msg.sender] += msg.value;

        emit Deposited(_channelId, msg.sender, ETH_TOKEN_ADDRESS, msg.value);
    }

    function depositToken(uint256 _channelId, address _token, uint256 _amount) external nonReentrant {
        Channel storage channel = channels[_channelId];
        require(
            channel.state == ChannelState.Initialized || channel.state == ChannelState.Open, "Invalid channel state"
        );
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(_token != ETH_TOKEN_ADDRESS && _token == channel.targetContract, "Token must be ERC20 target contract");

        // Transfer tokens from user to this contract
        require(_amount != 0, "amount must be greater than 0"); // empty deposit
        uint256 amount = _depositToken(msg.sender, IERC20(_token), _amount);
        require(amount == _amount, "non ERC20 standard transfer logic"); // The token has non-standard transfer logic

        channel.tokenDeposits[_token][msg.sender] += _amount;
        users[msg.sender].tokenBalances[_token] += _amount;

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

    function withdrawAfterClose(uint256 channelId) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Closed, "Channel not closed");
        require(channel.isParticipant[msg.sender], "Not a participant");

        // Withdraw ETH based on final balance
        uint256 ethAmount = channel.finalEthBalances[msg.sender];
        if (ethAmount > 0) {
            channel.finalEthBalances[msg.sender] = 0;
            (bool success,) = msg.sender.call{value: ethAmount}("");
            require(success, "ETH transfer failed");
            emit Withdrawn(channelId, msg.sender, ETH_TOKEN_ADDRESS, ethAmount);
        }

        // Withdraw tokens based on final balances
        address token = channel.targetContract;
        uint256 tokenAmount = channel.finalTokenBalances[token][msg.sender];
        if (tokenAmount > 0) {
            channel.finalTokenBalances[token][msg.sender] = 0;
            IERC20(token).transfer(msg.sender, tokenAmount);
            emit Withdrawn(channelId, msg.sender, token, tokenAmount);
        }
    }

    function emergencyWithdraw(uint256 channelId) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(
            block.timestamp >= channel.openTimestamp + channel.timeout + LOCK_TIMEOUT, "Emergency timeout not reached"
        );
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(channel.state != ChannelState.Closed, "Already closed");

        // Return original deposits
        uint256 ethDeposit = channel.participantDeposits[msg.sender];
        if (ethDeposit > 0) {
            channel.participantDeposits[msg.sender] = 0;
            (bool success,) = msg.sender.call{value: ethDeposit}("");
            require(success, "ETH transfer failed");
            emit EmergencyWithdrawn(channelId, msg.sender, address(0), ethDeposit);
        }

        // Return token deposits
        address token = channel.targetContract;
        uint256 tokenDeposit = channel.tokenDeposits[token][msg.sender];
        if (tokenDeposit > 0) {
            channel.tokenDeposits[token][msg.sender] = 0;
            IERC20(token).transfer(msg.sender, tokenDeposit);
            emit EmergencyWithdrawn(channelId, msg.sender, token, tokenDeposit);
        }
    }

    // ========== State Locking and Conversion ==========

    function lockStateAndConvert(uint256 channelId, bytes calldata multiSigSignature) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Initialized, "Invalid channel state");
        require(channel.isParticipant[msg.sender], "Not a participant");

        // Verify multisig for state locking
        bytes32 lockMessage = keccak256(abi.encodePacked("LOCK_STATE", channelId, channel.participants));

        // In production, implement proper multisig verification
        // For now, simplified signature check
        require(_verifyMultiSig(lockMessage, multiSigSignature, channel), "Invalid multisig");

        // Lock participants' states
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i];
            User storage user = users[participant];

            require(!user.isLocked, "User already locked");

            // Lock user's deposited amounts
            uint256 ethBalance = channel.participantDeposits[participant];
            uint256 tokenBalance = channel.tokenDeposits[channel.targetContract][participant];

            require(ethBalance > 0 || tokenBalance > 0, "No deposits to lock");

            user.isLocked = true;
            user.lockedAmount = tokenBalance; // For token-specific channels
            user.lockTimestamp = block.timestamp;

            emit UserStateLocked(channelId, participant);
        }

        // Convert MPT to ZK-friendly Merkle trees
        _convertToZKTrees(channelId);

        channel.state = ChannelState.Open;
    }

    function _convertToZKTrees(uint256 channelId) internal {
        Channel storage channel = channels[channelId];

        // Extract values and create Merkle trees
        bytes32[] memory balanceLeaves = new bytes32[](channel.participants.length);

        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i];

            // Use deposited amounts for the computation
            uint256 tokenBalance = channel.tokenDeposits[channel.targetContract][participant];
            uint256 ethBalance = channel.participantDeposits[participant];

            // Create leaf: hash(address, tokenBalance, ethBalance)
            balanceLeaves[i] = keccak256(abi.encodePacked(participant, tokenBalance, ethBalance));
        }

        // Compute and store root
        bytes32 balanceRoot = MerkleTree.computeRoot(balanceLeaves);
        channel.zkMerkleRoots.push(balanceRoot);

        // Could add more trees for different state components
        // (e.g., allowances, nonces, etc.)

        emit StateConverted(channelId, channel.zkMerkleRoots);
    }

    // ========== Auto-unlock Mechanism ==========

    function autoUnlock(uint256 channelId) external {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Open || channel.state == ChannelState.Active, "Invalid state for unlock");
        require(block.timestamp >= channel.openTimestamp + channel.timeout, "Timeout not reached");

        // Unlock all participants
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i];
            User storage user = users[participant];

            if (user.isLocked) {
                user.isLocked = false;
                // In production, would restore original state
            }
        }

        channel.state = ChannelState.Closed;
    }

    // ========== Proof Aggregation and Signing ==========

    function submitAggregatedProof(
        uint256 channelId,
        bytes32 aggregatedProofHash,
        bytes32 finalStateRoot
    ) external {
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

        // Verify EdDSA signature on aggregated proof
        User storage user = users[msg.sender];
        bytes32 message = keccak256(abi.encodePacked(channel.aggregatedProofHash, channel.finalStateRoot, channelId));

        // In production, implement proper EdDSA verification
        require(_verifyEdDSA(message, signature, user.l2PublicKey), "Invalid signature");

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
        require(channel.state == ChannelState.Closing, "Not in closing state");
        require(channel.receivedSignatures >= channel.requiredSignatures, "Insufficient signatures");

        // Verify the aggregated ZK proof
        require(
            zkVerifier.verify(proofPart1, proofPart2, channel.preprocessedPart1, channel.preprocessedPart2, publicInputs, smax),
            "Invalid ZK proof"
        );

        // Verify public inputs match the channel state
        require(keccak256(abi.encodePacked(publicInputs)) == channel.aggregatedProofHash, "Proof mismatch");

        // Unlock users and update state
        _updateL1State(channelId);

        // Clear storage and close channel
        channel.state = ChannelState.Closed;

        emit ChannelClosed(channelId);
    }

    function _updateL1State(uint256 channelId) internal {
        Channel storage channel = channels[channelId];

        // In production, would:
        // 1. Reconstruct final balances from ZK proof public inputs
        // 2. Verify the final state matches the proof
        // 3. Update channel final balances

        // For demonstration, assuming final balances are provided in the proof
        // In reality, these would be extracted from the ZK proof's public inputs
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i];
            User storage user = users[participant];

            if (user.isLocked) {
                user.isLocked = false;

                // Set final balances based on L2 computation results
                // These values would come from the ZK proof
                // For now, using original deposits as placeholder
                channel.finalEthBalances[participant] = channel.participantDeposits[participant];
                channel.finalTokenBalances[channel.targetContract][participant] =
                    channel.tokenDeposits[channel.targetContract][participant];
            }
        }
    }

    // ========== Helper Functions ==========

    function _verifyMultiSig(bytes32 message, bytes calldata signature, Channel storage channel)
        internal
        view
        returns (bool)
    {
        // Simplified multisig verification
        // In production, implement proper threshold signature scheme
        return true;
    }

    function _verifyEdDSA(bytes32 message, Signature calldata signature, address publicKey)
        internal
        pure
        returns (bool)
    {
        // Simplified EdDSA verification
        // In production, implement proper EdDSA verification
        return true;
    }

    // ========== View Functions ==========

    function getChannelInfo(uint256 channelId)
        external
        view
        returns (address targetContract, ChannelState state, uint256 participantCount, bytes32[] memory zkRoots)
    {
        Channel storage channel = channels[channelId];
        return (channel.targetContract, channel.state, channel.participants.length, channel.zkMerkleRoots);
    }

    function getUserLockStatus(address user)
        external
        view
        returns (bool isLocked, uint256 lockedAmount, uint256 lockTimestamp)
    {
        User storage u = users[user];
        return (u.isLocked, u.lockedAmount, u.lockTimestamp);
    }
}
