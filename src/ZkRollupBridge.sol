// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import {IVerifier} from "./interface/IVerifier.sol";
import {IZKRollupBridge} from "./interface/IZKRollupBridge.sol";
import "./MerklePatriciaTrie.sol";

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

    // ========== MAPPINGS ==========
    mapping(uint256 => Channel) public channels;
    mapping(address => bool) public authorizedChannelCreators;
    mapping(address => bool) public isChannelLeader;

    // MPT instance for each channel
    mapping(uint256 => address) public channelMPTs;

    uint256 public nextChannelId;

    // ========== CONTRACTS ==========
    IVerifier public immutable zkVerifier;

    // ========== CONSTRUCTOR ==========
    constructor(address _zkVerifier) Ownable(msg.sender) {
        zkVerifier = IVerifier(_zkVerifier);
    }

    // ========== Channel Opening ==========

    function authorizeCreator(address creator) external onlyOwner {
        authorizedChannelCreators[creator] = true;
    }

    function openChannel(
        address targetContract,
        bytes32 computationType,
        address[] calldata participants,
        address[] calldata l2PublicKeys,
        uint256[] calldata contractSlots,
        uint128[] calldata preprocessedPart1,
        uint256[] calldata preprocessedPart2,
        uint256 timeout
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

        // Deploy new MPT instance for this channel
        MerklePatriciaTrie mpt = new MerklePatriciaTrie();
        channel.mptContract = address(mpt);
        channelMPTs[channelId] = address(mpt);
        channel.contractSlots = contractSlots;
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

        channel.tokenDeposits[ETH_TOKEN_ADDRESS][msg.sender] += msg.value;
        channel.tokenTotalDeposits[ETH_TOKEN_ADDRESS] += msg.value;

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

        channel.tokenDeposits[_token][msg.sender] += _amount;
        channel.tokenTotalDeposits[_token] += _amount;

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
     * @dev Initialize channel state with MPT
     */
    function initializeChannelState(uint256 channelId) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Initialized, "Invalid state");
        require(msg.sender == channel.leader, "Not leader");

        MerklePatriciaTrie mpt = MerklePatriciaTrie(channel.mptContract);

        // Initialize user balances in MPT
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i].l1Address;
            uint256 balance = channel.tokenDeposits[channel.targetContract][participant];

            // Put user balance into MPT
            mpt.putStorage(participant, bytes32(BALANCE_SLOT), bytes32(balance));
        }

        // Initialize contract storage in MPT
        if (channel.targetContract != ETH_TOKEN_ADDRESS) {
            for (uint256 i = 0; i < channel.contractSlots.length; i++) {
                uint256 slot = channel.contractSlots[i];
                bytes32 value = _readContractStorage(channel.targetContract, slot);

                // Store contract slot value
                // Using address(0) for contract-wide storage
                mpt.putStorage(address(0), bytes32(slot), value);
            }

            // Store contract bytecode hash
            bytes memory code = _getContractCode(channel.targetContract);
            bytes32 codeHash = keccak256(code);
            mpt.put(abi.encodePacked(keccak256("codehash")), abi.encodePacked(codeHash));
        }

        // Get initial state root
        channel.currentStateRoot = mpt.stateRoot();
        channel.state = ChannelState.Open;

        emit StateInitialized(channelId, channel.currentStateRoot);
    }

    /**
     * @dev Simulate transaction and update MPT
     */
    function simulateTransaction(uint256 channelId, address from, address to, uint256 amount)
        internal
        returns (bytes32 newStateRoot)
    {
        Channel storage channel = channels[channelId];
        MerklePatriciaTrie mpt = MerklePatriciaTrie(channel.mptContract);

        // Get current balances
        bytes32 fromBalance = mpt.getStorage(from, bytes32(BALANCE_SLOT));
        bytes32 toBalance = mpt.getStorage(to, bytes32(BALANCE_SLOT));

        uint256 fromBalanceUint = uint256(fromBalance);
        uint256 toBalanceUint = uint256(toBalance);

        require(fromBalanceUint >= amount, "Insufficient balance");

        // Update balances in MPT
        mpt.putStorage(from, bytes32(BALANCE_SLOT), bytes32(fromBalanceUint - amount));
        mpt.putStorage(to, bytes32(BALANCE_SLOT), bytes32(toBalanceUint + amount));

        // Return new state root
        return mpt.stateRoot();
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
     * @dev Withdraw using MPT proof
     */
    function withdrawAfterClose(uint256 channelId, uint256 claimedBalance) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Closed, "Not closed");
        require(!channel.hasWithdrawn[msg.sender], "Already withdrawn");

        MerklePatriciaTrie mpt = MerklePatriciaTrie(channel.mptContract);

        // Verify balance directly from MPT
        bytes32 storedBalance = mpt.getStorage(msg.sender, bytes32(BALANCE_SLOT));
        require(uint256(storedBalance) == claimedBalance, "Balance mismatch");

        // Additional proof verification could be added here
        // to ensure the MPT state matches the closed channel state

        channel.hasWithdrawn[msg.sender] = true;

        // Process withdrawal
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

    function _verifyMultiSig(bytes32 message, bytes calldata signature, Channel storage channel)
        internal
        pure
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
        returns (address targetContract, ChannelState state, uint256 participantCount, bytes32[] memory zkRoots)
    {
        Channel storage channel = channels[channelId];
        return (channel.targetContract, channel.state, channel.participants.length, channel.zkMerkleRoots);
    }
}
