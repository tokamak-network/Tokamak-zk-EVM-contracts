// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import {IVerifier} from "./interface/IVerifier.sol";
import {MerkleTree} from "./library/MerkleTree.sol";

interface ITargetContract {
    function balanceOf(address account) external view returns (uint256);
}

// ==================== Main Bridge Contract ====================

contract ZKRollupBridge is ReentrancyGuard, Ownable {
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

    enum ChannelState {
        None,
        Initialized,
        Open,
        Active,
        Closing,
        Closed
    }

    modifier onlyAuthorized() {
        require(authorizedChannelCreators[msg.sender], "Not authorized");
        _;
    }

    // Mappings
    mapping(uint256 => Channel) public channels;
    mapping(address => bool) public authorizedChannelCreators;
    mapping(address => bool) public isChannelLeader;

    uint256 public nextChannelId;

    // Constants
    uint256 public constant LOCK_TIMEOUT = 7 days;
    uint256 public constant CHALLENGE_PERIOD = 14 days;
    uint256 public constant MIN_PARTICIPANTS = 3;
    uint256 public constant MAX_PARTICIPANTS = 50;
    uint256 public constant SIGNATURE_THRESHOLD_PERCENT = 67; // 2/3 threshold
    address public constant ETH_TOKEN_ADDRESS = address(1);

    // Contracts
    IVerifier public immutable zkVerifier;

    // Events
    event L2AddressAssigned(address indexed l1Address, address indexed l2Address);
    event ChannelOpened(uint256 indexed channelId, address indexed targetContract);
    event StateConverted(uint256 indexed channelId, bytes32[] zkRoots);
    event ProofAggregated(uint256 indexed channelId, bytes32 proofHash);
    event ChannelClosed(uint256 indexed channelId);
    event ChannelDeleted(uint256 indexed channelId);
    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event EmergencyWithdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);

    // ========== Constructor ==========

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

            // Create and push User struct
            channel.participants.push(User({
                l1Address: participant,
                l2PublicKey: l2PublicKeys[i]
            }));
            
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

    // ========== Deposit and Withdraw Functions ==========

    function depositETH(uint256 _channelId) external payable nonReentrant {
        Channel storage channel = channels[_channelId];
        require(
            channel.state == ChannelState.Initialized || channel.state == ChannelState.Open, "Invalid channel state"
        );
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(msg.value > 0, "Deposit must be greater than 0");
        require(channel.targetContract == ETH_TOKEN_ADDRESS, "Token must be set to ETH");

        channel.tokenDeposits[ETH_TOKEN_ADDRESS][msg.sender] += msg.value;
        channel.tokenTotalDeposits[ETH_TOKEN_ADDRESS] += msg.value;

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

    function withdrawAfterClose(
        uint256 channelId,
        uint256 claimedBalance,
        bytes32[] calldata merkleProof,
        uint256 leafIndex  // User's index in the participants array
    ) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Closed, "Channel not closed");
        require(channel.isParticipant[msg.sender], "Not a participant");
        require(!channel.hasWithdrawn[msg.sender], "Already withdrawn");
        
        // Verify the leafIndex corresponds to msg.sender
        require(leafIndex < channel.participants.length, "Invalid leaf index");
        require(channel.participants[leafIndex].l1Address == msg.sender, "Leaf index mismatch");
        
        // Construct the leaf hash (must match the format used in _convertToZKTrees)
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, claimedBalance));
        
        // Verify the Merkle proof against the finalStateRoot WITH INDEX
        require(
            MerkleTree.verifyProof(
                merkleProof,
                channel.finalStateRoot,
                leaf,
                leafIndex  
            ),
            "Invalid Merkle proof"
        );
        
        // Mark as withdrawn to prevent double claims
        channel.hasWithdrawn[msg.sender] = true;
        
        // Process withdrawal based on channel type
        if (channel.targetContract == ETH_TOKEN_ADDRESS) {
            // ETH withdrawal
            require(claimedBalance > 0, "Nothing to withdraw");
            (bool success,) = msg.sender.call{value: claimedBalance}("");
            require(success, "ETH transfer failed");
            emit Withdrawn(channelId, msg.sender, ETH_TOKEN_ADDRESS, claimedBalance);
        } else {
            // Token withdrawal
            require(claimedBalance > 0, "Nothing to withdraw");
            IERC20(channel.targetContract).transfer(msg.sender, claimedBalance);
            emit Withdrawn(channelId, msg.sender, channel.targetContract, claimedBalance);
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
        uint256 ethDeposit = channel.tokenDeposits[ETH_TOKEN_ADDRESS][msg.sender];
        if (ethDeposit > 0) {
            channel.tokenDeposits[ETH_TOKEN_ADDRESS][msg.sender] = 0;
            (bool success,) = msg.sender.call{value: ethDeposit}("");
            require(success, "ETH transfer failed");
            emit EmergencyWithdrawn(channelId, msg.sender, address(0), ethDeposit);
        } else {
            // Return token deposits
            address token = channel.targetContract;
            uint256 tokenDeposit = channel.tokenDeposits[token][msg.sender];
            if (tokenDeposit > 0) {
                channel.tokenDeposits[token][msg.sender] = 0;
                IERC20(token).transfer(msg.sender, tokenDeposit);
                emit EmergencyWithdrawn(channelId, msg.sender, token, tokenDeposit);
            }
        }
    }

    // ========== Generate first state root ==========

    function channelsFirstStateRoot(uint256 channelId, bytes calldata multiSigSignature) external nonReentrant {
        Channel storage channel = channels[channelId];
        require(channel.state == ChannelState.Initialized, "Invalid channel state");
        require(msg.sender == channel.leader, "Not leader");

        // Convert MPT to ZK-friendly Merkle trees
        _convertToZKTrees(channelId);

        channel.state = ChannelState.Open;
    }

    function _convertToZKTrees(uint256 channelId) internal {
        Channel storage channel = channels[channelId];

        // Extract values and create Merkle trees
        bytes32[] memory balanceLeaves = new bytes32[](channel.participants.length);

        for (uint256 i = 0; i < channel.participants.length; i++) {
            // Access the User struct and get the l1Address
            address participant = channel.participants[i].l1Address;

            // Use deposited amounts for the computation
            uint256 tokenBalance = channel.tokenDeposits[channel.targetContract][participant];

            // Create leaf: hash(address, tokenBalance)
            balanceLeaves[i] = keccak256(abi.encodePacked(participant, tokenBalance));
        }

        // Compute and store root
        bytes32 balanceRoot = MerkleTree.computeRoot(balanceLeaves);
        channel.zkMerkleRoots.push(balanceRoot);

        emit StateConverted(channelId, channel.zkMerkleRoots);
    }

    // ========== Proof Aggregation and Signing ==========

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
