// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/ZKRollupBridge.sol";
import "../src/interface/IZKRollupBridge.sol";
import "../src/interface/IVerifier.sol";
import "../src/merkleTree/MerkleTreeManager.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import {Poseidon2} from "@poseidon/src/Poseidon2.sol";

// Mock Contracts
contract MockVerifier is IVerifier {
    bool public shouldVerify = true;
    
    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }
    
    function verify(
        uint128[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external view override returns (bool) {
        return shouldVerify;
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ZKRollupBridgeTest is Test {
    ZKRollupBridge public bridge;
    MockVerifier public verifier;
    MockERC20 public token;
    Poseidon2 public poseidon;
    
    address public owner = address(1);
    address public leader = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    
    address public l2Leader = address(12);
    address public l2User1 = address(13);
    address public l2User2 = address(14);
    address public l2User3 = address(15);
    
    uint256 public constant INITIAL_BALANCE = 1000 ether;

    event ChannelOpened(uint256 indexed channelId, address indexed targetContract);
    event ProofAggregated(uint256 indexed channelId, bytes32 proofHash);
    event ChannelClosed(uint256 indexed channelId);
    event ChannelDeleted(uint256 indexed channelId);
    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event StateInitialized(uint256 indexed channelId, bytes32 currentStateRoot);
    
    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);
        
        verifier = new MockVerifier();
        poseidon = new Poseidon2();
        bridge = new ZKRollupBridge(address(verifier), address(poseidon));
        token = new MockERC20();
        
        // Setup initial state
        bridge.authorizeCreator(leader);
        
        // Fund test accounts
        vm.deal(leader, INITIAL_BALANCE);
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(user3, INITIAL_BALANCE);
        
        token.mint(user1, INITIAL_BALANCE);
        token.mint(user2, INITIAL_BALANCE);
        token.mint(user3, INITIAL_BALANCE);
        
        vm.stopPrank();
    }
    
    // ========== Channel Opening Tests ==========
    
    function testOpenChannel() public {
        vm.startPrank(leader);
        
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;
        
        uint128[] memory preprocessedPart1 = new uint128[](1);
        uint256[] memory preprocessedPart2 = new uint256[](1);
        
        uint256 channelId = bridge.openChannel(
            bridge.ETH_TOKEN_ADDRESS(),
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            1 days,
            bytes32(0)
        );
        
        assertEq(channelId, 0);
        
        (
            address targetContract,
            IZKRollupBridge.ChannelState state,
            uint256 participantCount,
            ,
        ) = bridge.getChannelInfo(channelId);
        
        assertEq(targetContract, bridge.ETH_TOKEN_ADDRESS());
        assertEq(uint8(state), uint8(IZKRollupBridge.ChannelState.Initialized));
        assertEq(participantCount, 3);
        
        vm.stopPrank();
    }

    // ========== Deposit Tests ==========
    
    function testDepositETH() public {
        uint256 channelId = _createChannel();
        uint256 depositAmount = 1 ether;
        
        vm.startPrank(user1);
        
        vm.expectEmit(true, true, true, true);
        emit Deposited(channelId, user1, bridge.ETH_TOKEN_ADDRESS(), depositAmount);
        
        bridge.depositETH{value: depositAmount}(channelId);
        
        // Check balance tracking
        // Note: We can't directly access tokenDeposits mapping, would need a getter
        
        vm.stopPrank();
    }
    
    function testDepositETHNotParticipant() public {
        uint256 channelId = _createChannel();
        
        vm.prank(address(999));
        vm.deal(address(999), 1 ether);
        vm.expectRevert("Not a participant");
        bridge.depositETH{value: 1 ether}(channelId);
    }
    
    function testDepositToken() public {
        uint256 channelId = _createTokenChannel();
        uint256 depositAmount = 100 * 10**18;
        
        vm.startPrank(user1);
        
        token.approve(address(bridge), depositAmount);
        
        vm.expectEmit(true, true, true, true);
        emit Deposited(channelId, user1, address(token), depositAmount);
        
        bridge.depositToken(channelId, address(token), depositAmount);
        
        assertEq(token.balanceOf(address(bridge)), depositAmount);
        
        vm.stopPrank();
    }
    
    // ========== State Initialization Tests ==========
    
    function testInitializeChannelState() public {
        uint256 channelId = _createChannel();
        
        // Make deposits
        vm.prank(user1);
        bridge.depositETH{value: 1 ether}(channelId);
        
        vm.prank(user2);
        bridge.depositETH{value: 2 ether}(channelId);
        
        vm.prank(user3);
        bridge.depositETH{value: 3 ether}(channelId);
        
        // Initialize state
        vm.prank(leader);
        bridge.initializeChannelState(channelId);
        
        (
            ,
            IZKRollupBridge.ChannelState state,
            ,
            bytes32 initialRoot,
            
        ) = bridge.getChannelInfo(channelId);
        
        assertEq(uint8(state), uint8(IZKRollupBridge.ChannelState.Open));
        assertTrue(initialRoot != bytes32(0));
    }
    
    function testInitialize_ChannelStateNotLeader() public {
        uint256 channelId = _createChannel();
        
        vm.prank(user1);
        vm.expectRevert("Not leader");
        bridge.initializeChannelState(channelId);
    }
    
    // ========== Proof Submission Tests ==========
    
    function testSubmitAggregatedProof() public {
        uint256 channelId = _initializeChannel();
        
        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");
        
        vm.prank(leader);
        
        vm.expectEmit(true, true, false, false);
        emit ProofAggregated(channelId, proofHash);
        
        bridge.submitAggregatedProof(channelId, proofHash, finalRoot);
        
        (
            ,
            IZKRollupBridge.ChannelState state,
            ,
            ,
            bytes32 storedFinalRoot
        ) = bridge.getChannelInfo(channelId);
        
        assertEq(uint8(state), uint8(IZKRollupBridge.ChannelState.Closing));
        assertEq(storedFinalRoot, finalRoot);
    }
    
    // ========== Signature Tests ==========
    
    function testSignAggregatedProof() public {
        uint256 channelId = _submitProof();
        
        IZKRollupBridge.Signature memory sig = IZKRollupBridge.Signature({
            R_x: 1,
            R_y: 2
        });
        
        vm.prank(user1);
        bridge.signAggregatedProof(channelId, sig);
        
        // Test double signing
        vm.prank(user1);
        vm.expectRevert("Already signed");
        bridge.signAggregatedProof(channelId, sig);
    }
    
    // ========== Channel Closing Tests ==========
    
    function testCloseChannel() public {
        uint256 channelId = _getSignedChannel();
        
        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);
        
        vm.prank(leader);
        
        vm.expectEmit(true, false, false, false);
        emit ChannelClosed(channelId);
        
        bridge.closeChannel(channelId, proofPart1, proofPart2, publicInputs, 0);
        
        (
            ,
            IZKRollupBridge.ChannelState state,
            ,
            ,
        ) = bridge.getChannelInfo(channelId);
        
        assertEq(uint8(state), uint8(IZKRollupBridge.ChannelState.Closed));
    }
    
    function testCloseChannelInvalidProof() public {
        uint256 channelId = _getSignedChannel();
        
        verifier.setShouldVerify(false);
        
        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);
        
        vm.prank(leader);
        vm.expectRevert("Invalid ZK proof");
        bridge.closeChannel(channelId, proofPart1, proofPart2, publicInputs, 0);
    }
    
    // ========== Withdrawal Tests ==========
    
    function testWithdrawAfterClose() public {
        uint256 channelId = _getClosedChannel();
        uint256 claimedBalance = 1 ether;
        uint256 leafIndex = 0;
        bytes32[] memory proof = new bytes32[](0);
        
        // This would fail in real scenario without proper merkle proof
        // For testing, we'd need to mock the MerkleTreeManager verification
        
        vm.prank(user1);
        vm.expectRevert(); // Will revert due to merkle proof verification
        bridge.withdrawAfterClose(channelId, claimedBalance, leafIndex, proof);
    }
    
    // ========== Channel Deletion Tests ==========
    
    function testDeleteChannel() public {
        uint256 channelId = _getClosedChannel();
        
        // Fast forward past challenge period
        vm.warp(block.timestamp + bridge.CHALLENGE_PERIOD() + 1);
        
        vm.prank(leader);
        
        vm.expectEmit(true, false, false, false);
        emit ChannelDeleted(channelId);
        
        bool success = bridge.deleteChannel(channelId);
        assertTrue(success);
        
        // Verify channel is deleted
        (
            address targetContract,
            ,
            ,
            ,
        ) = bridge.getChannelInfo(channelId);
        
        assertEq(targetContract, address(0));
    }
    
    function testDeleteChannelBeforeChallengePeriod() public {
        uint256 channelId = _getClosedChannel();
        
        vm.prank(leader);
        vm.expectRevert();
        bridge.deleteChannel(channelId);
    }
    
    // ========== Helper Functions ==========
    
    function _createChannel() internal returns (uint256) {
        vm.startPrank(leader);
        
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;
        
        uint128[] memory preprocessedPart1 = new uint128[](1);
        uint256[] memory preprocessedPart2 = new uint256[](1);
        
        uint256 channelId = bridge.openChannel(
            bridge.ETH_TOKEN_ADDRESS(),
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            1 days,
            bytes32(0)
        );
        
        vm.stopPrank();
        
        return channelId;
    }
    
    function _createTokenChannel() internal returns (uint256) {
        vm.startPrank(leader);
        
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;
        
        uint128[] memory preprocessedPart1 = new uint128[](1);
        uint256[] memory preprocessedPart2 = new uint256[](1);
        
        uint256 channelId = bridge.openChannel(
            address(token),
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            1 days,
            bytes32(0)
        );
        
        vm.stopPrank();
        
        return channelId;
    }
    
    function _initializeChannel() internal returns (uint256) {
        uint256 channelId = _createChannel();
        
        // Make deposits
        vm.prank(user1);
        bridge.depositETH{value: 1 ether}(channelId);
        
        vm.prank(user2);
        bridge.depositETH{value: 2 ether}(channelId);
        
        vm.prank(user3);
        bridge.depositETH{value: 3 ether}(channelId);
        
        // Initialize state
        vm.prank(leader);
        bridge.initializeChannelState(channelId);
        
        return channelId;
    }
    
    function _submitProof() internal returns (uint256) {
        uint256 channelId = _initializeChannel();
        
        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");
        
        vm.prank(leader);
        bridge.submitAggregatedProof(channelId, proofHash, finalRoot);
        
        return channelId;
    }
    
    function _getSignedChannel() internal returns (uint256) {
        uint256 channelId = _submitProof();
        
        IZKRollupBridge.Signature memory sig = IZKRollupBridge.Signature({
            R_x: 1,
            R_y: 2
        });
        
        // Get required signatures (2/3 of participants)
        vm.prank(user1);
        bridge.signAggregatedProof(channelId, sig);
        
        vm.prank(user2);
        bridge.signAggregatedProof(channelId, sig);
        
        return channelId;
    }
    
    function _getClosedChannel() internal returns (uint256) {
        uint256 channelId = _getSignedChannel();
        
        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);
        
        vm.prank(leader);
        bridge.closeChannel(channelId, proofPart1, proofPart2, publicInputs, 0);
        
        return channelId;
    }
    
    // ========== Fuzz Tests ==========
    
    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100 ether);
        
        uint256 channelId = _createChannel();
        
        vm.deal(user1, amount);
        vm.prank(user1);
        bridge.depositETH{value: amount}(channelId);
    }
    
    function testFuzzTimeout(uint256 timeout) public {
        vm.assume(timeout >= 1 hours && timeout <= 7 days);
        
        vm.startPrank(leader);
        
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;
        
        uint128[] memory preprocessedPart1 = new uint128[](1);
        uint256[] memory preprocessedPart2 = new uint256[](1);
        
        bridge.openChannel(
            bridge.ETH_TOKEN_ADDRESS(),
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            timeout,
            bytes32(0)
        );
        
        vm.stopPrank();
    }
    
    // ========== Integration Tests ==========
    
    function testFullChannelLifecycle() public {
        // 1. Open channel
        uint256 channelId = _createChannel();
        
        // 2. Make deposits
        vm.prank(user1);
        bridge.depositETH{value: 1 ether}(channelId);
        
        vm.prank(user2);
        bridge.depositETH{value: 2 ether}(channelId);
        
        vm.prank(user3);
        bridge.depositETH{value: 3 ether}(channelId);
        
        // 3. Initialize state
        vm.prank(leader);
        bridge.initializeChannelState(channelId);
        
        // 4. Submit proof
        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");
        
        vm.prank(leader);
        bridge.submitAggregatedProof(channelId, proofHash, finalRoot);
        
        // 5. Collect signatures
        IZKRollupBridge.Signature memory sig = IZKRollupBridge.Signature({
            R_x: 1,
            R_y: 2
        });
        
        vm.prank(user1);
        bridge.signAggregatedProof(channelId, sig);
        
        vm.prank(user2);
        bridge.signAggregatedProof(channelId, sig);
        
        // 6. Close channel
        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);
        
        vm.prank(leader);
        bridge.closeChannel(channelId, proofPart1, proofPart2, publicInputs, 0);
        
        // 7. Wait for challenge period
        vm.warp(block.timestamp + bridge.CHALLENGE_PERIOD() + 1);
        
        // 8. Delete channel
        vm.prank(leader);
        bool success = bridge.deleteChannel(channelId);
        assertTrue(success);
    }
}