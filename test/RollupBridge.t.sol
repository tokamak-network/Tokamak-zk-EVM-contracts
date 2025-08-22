// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/RollupBridge.sol";
import "../src/interface/IRollupBridge.sol";
import "../src/interface/IVerifier.sol";
import {Verifier} from "../src/verifier/Verifier.sol";
import "../src/merkleTree/MerkleTreeManager4.sol";
import "../src/library/RLP.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import {IPoseidon4Yul} from "../src/interface/IPoseidon4Yul.sol";
import {MockPoseidon4Yul} from "./MockPoseidon4Yul.sol";

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
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RollupBridgeTest is Test {
    using RLP for bytes;

    RollupBridge public bridge;
    MockVerifier public verifier;
    MerkleTreeManager4 public mtmanager;
    MockERC20 public token;
    IPoseidon4Yul public poseidon;

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
        poseidon = new MockPoseidon4Yul();
        mtmanager = new MerkleTreeManager4(address(poseidon));
        bridge = new RollupBridge(address(verifier), address(mtmanager));
        mtmanager.setBridge(address(bridge));
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

    // ========== Helper Functions for MPT Leaves ==========

    /**
     * @dev Creates a mock MPT leaf with RLP-encoded account data: [nonce, balance, storageHash, codeHash]
     */
    function _createMockMPTLeaf(uint256 balance) internal pure returns (bytes memory) {
        bytes[] memory accountFields = new bytes[](4);

        // nonce = 0
        accountFields[0] = RLP.encode(abi.encodePacked(uint256(0)));

        // balance
        accountFields[1] = RLP.encode(abi.encodePacked(balance));

        // storageHash (empty storage)
        accountFields[2] = RLP.encode(abi.encodePacked(keccak256("")));

        // codeHash (empty code)
        accountFields[3] = RLP.encode(abi.encodePacked(keccak256("")));

        return RLP.encodeList(accountFields);
    }

    /**
     * @dev Creates MPT leaves for a given set of balances
     */
    function _createMPTLeaves(uint256[] memory balances) internal pure returns (bytes[] memory) {
        bytes[] memory leaves = new bytes[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            leaves[i] = _createMockMPTLeaf(balances[i]);
        }
        return leaves;
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

        (address targetContract, IRollupBridge.ChannelState state, uint256 participantCount,,) =
            bridge.getChannelInfo(channelId);

        assertEq(targetContract, bridge.ETH_TOKEN_ADDRESS());
        assertEq(uint8(state), uint8(IRollupBridge.ChannelState.Initialized));
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
        uint256 depositAmount = 100 * 10 ** 18;

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

        (, IRollupBridge.ChannelState state,, bytes32 initialRoot,) = bridge.getChannelInfo(channelId);

        assertEq(uint8(state), uint8(IRollupBridge.ChannelState.Open));
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

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);

        // Create MPT leaves matching the deposited amounts (1, 2, 3 ether)
        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;

        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 6 ether; // Changed distribution but same total
        finalBalances[1] = 0 ether;
        finalBalances[2] = 0 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(initialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(finalBalances);

        vm.prank(leader);
        vm.expectEmit(true, true, false, false);
        emit ProofAggregated(channelId, proofHash);
        bridge.submitAggregatedProof(
            channelId, proofHash, finalRoot, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );
    }

    function test_SubmitAggregatedProofBalanceMismatch() public {
        uint256 channelId = _initializeChannel();

        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);

        // Create MPT leaves with wrong initial balances
        uint256[] memory wrongInitialBalances = new uint256[](3);
        wrongInitialBalances[0] = 2 ether; // Wrong - should be 1 ether
        wrongInitialBalances[1] = 2 ether;
        wrongInitialBalances[2] = 3 ether;

        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 2 ether;
        finalBalances[1] = 2 ether;
        finalBalances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(wrongInitialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(finalBalances);

        vm.prank(leader);
        vm.expectRevert("Initial balance mismatch");
        bridge.submitAggregatedProof(
            channelId, proofHash, finalRoot, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );
    }

    function test_SubmitAggregatedProofConservationViolation() public {
        uint256 channelId = _initializeChannel();

        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);

        // Create MPT leaves with correct initial but wrong final balances
        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;

        uint256[] memory wrongFinalBalances = new uint256[](3);
        wrongFinalBalances[0] = 2 ether;
        wrongFinalBalances[1] = 2 ether;
        wrongFinalBalances[2] = 4 ether; // Extra ether created!

        bytes[] memory initialMPTLeaves = _createMPTLeaves(initialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(wrongFinalBalances);

        vm.prank(leader);
        vm.expectRevert("Balance conservation violated");
        bridge.submitAggregatedProof(
            channelId, proofHash, finalRoot, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );
    }

    function test_SubmitAggregatedProofMismatchedArrays() public {
        uint256 channelId = _initializeChannel();

        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);

        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;

        uint256[] memory finalBalances = new uint256[](2); // Wrong length!
        finalBalances[0] = 3 ether;
        finalBalances[1] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(initialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(finalBalances);

        vm.prank(leader);
        vm.expectRevert("Mismatched leaf arrays");
        bridge.submitAggregatedProof(
            channelId, proofHash, finalRoot, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );
    }

    function test_SubmitAggregatedProofGasUsage() public {
        uint256 channelId = _initializeChannel();

        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");

        uint128[] memory proofPart1 = new uint128[](10); // Larger proof data
        uint256[] memory proofPart2 = new uint256[](10);
        uint256[] memory publicInputs = new uint256[](5);

        // Fill with some data to simulate realistic proof sizes
        for (uint256 i = 0; i < proofPart1.length; i++) {
            proofPart1[i] = uint128(i + 1);
        }
        for (uint256 i = 0; i < proofPart2.length; i++) {
            proofPart2[i] = i + 1;
        }
        for (uint256 i = 0; i < publicInputs.length; i++) {
            publicInputs[i] = i + 1;
        }

        // Create MPT leaves matching the deposited amounts (1, 2, 3 ether)
        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;

        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 2 ether; // Redistributed balances
        finalBalances[1] = 1 ether;
        finalBalances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(initialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(finalBalances);

        vm.prank(leader);

        uint256 gasBefore = gasleft();
        bridge.submitAggregatedProof(
            channelId, proofHash, finalRoot, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );
        uint256 gasAfter = gasleft();

        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Gas used for submitAggregatedProof:", gasUsed);

        // Assert reasonable gas usage (adjust threshold as needed)
        assertTrue(gasUsed < 10000000, "Gas usage too high");
        assertTrue(gasUsed > 50000, "Gas usage suspiciously low");
    }

    function test_SubmitAggregatedProofGasUsageWithRealVerifier() public {
        // Deploy real verifier instead of mock
        vm.startPrank(owner);
        Verifier realVerifier = new Verifier();
        MerkleTreeManager4 mtmanager2 = new MerkleTreeManager4(address(poseidon));
        RollupBridge realBridge = new RollupBridge(address(realVerifier), address(mtmanager2));
        mtmanager2.setBridge(address(realBridge));

        // Setup for real bridge
        realBridge.authorizeCreator(user1);
        vm.stopPrank();

        // Create channel with real bridge
        vm.startPrank(user1);
        address[] memory participants = new address[](4);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;
        participants[3] = leader;

        address[] memory l2PublicKeys = new address[](4);
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;
        l2PublicKeys[3] = l2Leader;

        // Get real proof data
        (
            uint128[] memory proofPart1,
            uint256[] memory proofPart2,
            uint128[] memory prepPart1,
            uint256[] memory prepPart2,
            uint256[] memory pubInputs,
            uint256 smaxValue
        ) = _getRealProofData();

        uint256 channelId = realBridge.openChannel(
            realBridge.ETH_TOKEN_ADDRESS(), participants, l2PublicKeys, prepPart1, prepPart2, 1 days, bytes32(0)
        );
        vm.stopPrank();

        // Make deposits
        vm.prank(user1);
        realBridge.depositETH{value: 1 ether}(channelId);
        vm.prank(user2);
        realBridge.depositETH{value: 2 ether}(channelId);
        vm.prank(user3);
        realBridge.depositETH{value: 3 ether}(channelId);
        vm.prank(leader);
        realBridge.depositETH{value: 4 ether}(channelId);

        // Initialize state
        vm.prank(user1);
        realBridge.initializeChannelState(channelId);

        // Create MPT leaves
        uint256[] memory initialBalances = new uint256[](4);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;
        initialBalances[3] = 4 ether;

        uint256[] memory finalBalances = new uint256[](4);
        finalBalances[0] = 2 ether;
        finalBalances[1] = 1 ether;
        finalBalances[2] = 3 ether;
        finalBalances[3] = 4 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(initialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(finalBalances);

        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");

        vm.prank(user1);
        uint256 gasBefore = gasleft();
        realBridge.submitAggregatedProof(
            channelId,
            proofHash,
            finalRoot,
            proofPart1,
            proofPart2,
            pubInputs,
            smaxValue,
            initialMPTLeaves,
            finalMPTLeaves
        );
        uint256 gasAfter = gasleft();

        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Gas used for submitAggregatedProof with real verifier:", gasUsed);

        // Assert reasonable gas usage (ZK verification is expensive)
        assertTrue(gasUsed < 10000000, "Gas usage too high");
        assertTrue(gasUsed > 100000, "Gas usage suspiciously low");
    }

    // ========== Signature Tests ==========

    function testSignAggregatedProof() public {
        uint256 channelId = _submitProof();

        IRollupBridge.Signature memory sig = IRollupBridge.Signature({R_x: 1, R_y: 2});

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

        vm.prank(leader);

        vm.expectEmit(true, false, false, false);
        emit ChannelClosed(channelId);

        bridge.closeChannel(channelId);

        (, IRollupBridge.ChannelState state,,,) = bridge.getChannelInfo(channelId);

        assertEq(uint8(state), uint8(IRollupBridge.ChannelState.Closed));
    }

    function testCloseChannelInvalidProof() public {
        uint256 channelId = _initializeChannel();

        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);

        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        verifier.setShouldVerify(false);

        vm.prank(leader);
        vm.expectRevert("Invalid ZK proof");
        bridge.submitAggregatedProof(
            channelId, proofHash, finalRoot, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );
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
        (address targetContract,,,,) = bridge.getChannelInfo(channelId);

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
            address(token), participants, l2PublicKeys, preprocessedPart1, preprocessedPart2, 1 days, bytes32(0)
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

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);

        // Create MPT leaves matching the deposited amounts
        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        vm.prank(leader);
        bridge.submitAggregatedProof(
            channelId, proofHash, finalRoot, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );

        return channelId;
    }

    function _getSignedChannel() internal returns (uint256) {
        uint256 channelId = _submitProof();

        IRollupBridge.Signature memory sig = IRollupBridge.Signature({R_x: 1, R_y: 2});

        // Get required signatures (2/3 of participants)
        vm.prank(user1);
        bridge.signAggregatedProof(channelId, sig);

        vm.prank(user2);
        bridge.signAggregatedProof(channelId, sig);

        return channelId;
    }

    function _getClosedChannel() internal returns (uint256) {
        uint256 channelId = _getSignedChannel();

        vm.prank(leader);
        bridge.closeChannel(channelId);

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

        // 4. Submit proof with MPT leaves
        bytes32 proofHash = keccak256("proof");
        bytes32 finalRoot = keccak256("finalRoot");

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](1);

        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        vm.prank(leader);
        bridge.submitAggregatedProof(
            channelId, proofHash, finalRoot, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );

        // 5. Collect signatures
        IRollupBridge.Signature memory sig = IRollupBridge.Signature({R_x: 1, R_y: 2});

        vm.prank(user1);
        bridge.signAggregatedProof(channelId, sig);

        vm.prank(user2);
        bridge.signAggregatedProof(channelId, sig);

        // 6. Close channel
        vm.prank(leader);
        bridge.closeChannel(channelId);

        // 7. Wait for challenge period
        vm.warp(block.timestamp + bridge.CHALLENGE_PERIOD() + 1);

        // 8. Delete channel
        vm.prank(leader);
        bool success = bridge.deleteChannel(channelId);
        assertTrue(success);
    }

    function _getRealProofData()
        internal
        pure
        returns (
            uint128[] memory serializedProofPart1,
            uint256[] memory serializedProofPart2,
            uint128[] memory preprocessedPart1,
            uint256[] memory preprocessedPart2,
            uint256[] memory publicInputs,
            uint256 smax
        )
    {
        // Initialize arrays
        serializedProofPart1 = new uint128[](38);
        serializedProofPart2 = new uint256[](42);
        preprocessedPart1 = new uint128[](4);
        preprocessedPart2 = new uint256[](4);
        publicInputs = new uint256[](64);

        // PREPROCESSED PART 1 (First 16 bytes - 32 hex chars)
        preprocessedPart1[0] = (0x042df2d7ba82218503dbadeaa9e87792);
        preprocessedPart1[1] = (0x0801f08b0423c3bb6cc7640b59e2ad81);
        preprocessedPart1[2] = (0x14d6acdf7112c181e4b618ae54cf2dbb);
        preprocessedPart1[3] = (0x0620aa348ac912429c4397e4083ba707);

        // PREPROCESSED PART 2 (Last 32 bytes - 64 hex chars)
        preprocessedPart2[0] = (0xebcab00c3413baa3b039e936e26e87f30a8ed8e4260497bfd1dc2227674f0d02);
        preprocessedPart2[1] = (0xb3cb4d475bbb5b22058c8ce67c59d218277dbdb6ae79e1e083cc74bc2197b283);
        preprocessedPart2[2] = (0x9fde9d8a778d5c673020961f56a2976b4cde817a6b617b2dd830da65787a21cd);
        preprocessedPart2[3] = (0x8c800ff423029764962680ccc47ad3244a8669361f84ad5922f8659e5b8a678e);

        // SERIALIZED PROOF PART 1 (First 16 bytes - 32 hex chars)
        serializedProofPart1[0] = (0x0c24fdec12d53a11da4d980c17d4e1a0);
        serializedProofPart1[1] = (0x17a05805dfe64737462cc7905747825b);
        serializedProofPart1[2] = (0x0896a633d5adf4b47c13d51806d66a35);
        serializedProofPart1[3] = (0x0a083a0932bebfbe2075aaf972cc5af7);
        serializedProofPart1[4] = (0x0a28401cd04c6e2e0bf2677b09d43a4c);
        serializedProofPart1[5] = (0x182ee1ed2f42610a39b255b4a0e84ee5);
        serializedProofPart1[6] = (0x0bd00d0783c76029e7d10c85d8b7a054);
        serializedProofPart1[7] = (0x087cbceebc924fadbff19a7059e44a68);
        serializedProofPart1[8] = (0x0ab348bc443f0fae8b8cf657e1c970ce);
        serializedProofPart1[9] = (0x1445acc8d6f02dddd0e17eaafd98d200);
        serializedProofPart1[10] = (0x001708378a5785dc70d0e217112197b9);
        serializedProofPart1[11] = (0x0783caf01311feb7b0896a179ad220d2);
        serializedProofPart1[12] = (0x0c5479dab696569b5943662da9194b3b);
        serializedProofPart1[13] = (0x0cabc8d2b5e630fd8b5698e2d4ce9370);
        serializedProofPart1[14] = (0x11d4bbafa0da1fc302112e38300bd9a1);
        serializedProofPart1[15] = (0x0a3c0cc511d40fa513a97ab0fae9da99);
        serializedProofPart1[16] = (0x03dbeb7f79d515638ed23e5ce018f592);
        serializedProofPart1[17] = (0x0d1c6c26b1f7d69bb0441eb8fde52aa4);
        serializedProofPart1[18] = (0x04be84681792a0a5afabba29ed3fcfb8);
        serializedProofPart1[19] = (0x05fb88f7324750e43d173a23aee8181e);
        serializedProofPart1[20] = (0x170f46f976ef61677cbebcdefb74feeb);
        serializedProofPart1[21] = (0x0b17a6a12b6fb13eca79be94abc8582b);
        serializedProofPart1[22] = (0x064aac9536b7b2ce667f9ba6a28cb1d3);
        serializedProofPart1[23] = (0x15f89d14f23e7cd275787c22e59b7cfb);
        serializedProofPart1[24] = (0x1768019026542d286a58258435158b31);
        serializedProofPart1[25] = (0x0a61414b5c2ccfe907df78c2b39bcd2e);
        serializedProofPart1[26] = (0x04f4c3891678a4e32c90b78e11a6ade1);
        serializedProofPart1[27] = (0x1982759528c860a8757bc2afc9f7fda4);
        serializedProofPart1[28] = (0x158ca44f01aac0407705fe5cc4d44f5c);
        serializedProofPart1[29] = (0x0a03d544f26007212ab4d53d3a8fcb87);
        serializedProofPart1[30] = (0x086ece3d5d70f8815d8b1c3659ca8a8a);
        serializedProofPart1[31] = (0x10b90670319cd41cf4af3e0b474be4ca);
        serializedProofPart1[32] = (0x158ca44f01aac0407705fe5cc4d44f5c);
        serializedProofPart1[33] = (0x0a03d544f26007212ab4d53d3a8fcb87);
        serializedProofPart1[34] = (0x126cbc300279a36e774d9e1c1953e9dc);
        serializedProofPart1[35] = (0x0ee0a0e6d60e1f8527d56093560223f5);
        serializedProofPart1[36] = (0x18ab22994ea4cb2eb9ebea8af602f8dd);
        serializedProofPart1[37] = (0x129eab9c15fcd487d09de770171b6912);

        // SERIALIZED PROOF PART 2 (Last 32 bytes - 64 hex chars)
        serializedProofPart2[0] = (0x29afb6b437675cf15e0324fe3bad032c88bd9addc36ff22855acb73a5c3f4cef);
        serializedProofPart2[1] = (0xdd670e5cdb1a14f5842e418357b752ee2200d5eab40a3990615224f2467c985a);
        serializedProofPart2[2] = (0xa379b716417a5870cc2f334e28cd91a388c5e3f18012f24700a103ea0c2aacb2);
        serializedProofPart2[3] = (0xffaac16f6dc2f74a0e7e18fba4e5585b4e5d642ded1156a1f58f48853e59aa42);
        serializedProofPart2[4] = (0xa23bfdfdfca0f91636ecc5527ac26058e20d58bac954eb642bae8bd626ef7010);
        serializedProofPart2[5] = (0x6f9598e15cdb8c85c5ac7ac0a78e1385446815324b91f17efacada8c544d2196);
        serializedProofPart2[6] = (0xba1b4b3bc86fb24b15799faa6c863b93de799bcb6a7aa6b000dff5e3dab2471f);
        serializedProofPart2[7] = (0xec6e41cb9cf3cc5910993ea9f08f40bd100ddf83f93f04e6bdd316797ef0beb0);
        serializedProofPart2[8] = (0xe9df3c6debe8c19110bc1d660e4deb5a52301ac37ecc90879bd68ecc8d97bdd2);
        serializedProofPart2[9] = (0x00fc98c6635577ff28950f2143aa83508c93095237abd83d69e2b24886dea95a);
        serializedProofPart2[10] = (0x63914eaba1999e91128214fdc6658ecfbc495062ceef8457ca7a1ec6c0d0e0eb);
        serializedProofPart2[11] = (0xd5bbef14f885ccbe203d48b0014ffdb943845363b278c4ab5be13674a2378134);
        serializedProofPart2[12] = (0x3d07b6d0abc0874227371ff6317cac98105f2f6fc1181cd1d66a4e4ec946cc65);
        serializedProofPart2[13] = (0x3f31b28005195499d4af392ca85edb0cee55452f39d4237641476955548e12af);
        serializedProofPart2[14] = (0xa66c27ac6a19f296259e0979530c4fcd90cb9e74249871c0c6489485404d9063);
        serializedProofPart2[15] = (0xd72bca363ba9ae574db315d4336478d0042b3e0e61270a4792a28368185a3194);
        serializedProofPart2[16] = (0xed8921adcbf1cf3805b293511a1b11363907a3aac8f481d8fd94374c040e5d6b);
        serializedProofPart2[17] = (0xd434523ed473b876e8ec1d784d149db6f706deac4d472677587a1fce0a161b3b);
        serializedProofPart2[18] = (0x6ea759852f22461d6206b877123aa7b5e0c8c2f252bcfd67e7db9e270f4f89f0);
        serializedProofPart2[19] = (0x58673a8bd4ce54d417f3f4611f1a17babe9ae036c26dbd1c090b5aa21b103e7e);
        serializedProofPart2[20] = (0x795bb282127eb89f0f74f3ac4225110c7f6ba1d28ee3585c5d2f9fd87407a076);
        serializedProofPart2[21] = (0x1c5f55837e396d3133e3327a1d55181c43e70a40175eec9830f504196143addc);
        serializedProofPart2[22] = (0xd6f85a33ffc841e63ffb0f7397933fbc479255bc76350181f60e8a674ce4a511);
        serializedProofPart2[23] = (0x042e8d8894ad3c74b0a4e53b6d4ed6ef593d6c289192c995573db09388ff6d11);
        serializedProofPart2[24] = (0x1569d3423b1b51e0bc46ba0eb5cc6a5d85d824a38380712cc45cf82afaf207a5);
        serializedProofPart2[25] = (0x1ab0450608bd2e5ba51dc73326511bf150fc5641615ae710a50b693b243642c7);
        serializedProofPart2[26] = (0x08daa13bff0ada0a5bc43ed4d7cea70dd8f326ceb3b4e45c371dd2700ef6f0c6);
        serializedProofPart2[27] = (0x4b3655e123391a00b8d3071defdab3c8b8417c0f5a547d6b589dcd20ecd33e7e);
        serializedProofPart2[28] = (0xc6e1ae5fca24804ade878f6ef38651c10c05a135e3f97bfd2d904fda94c7a9b1);
        serializedProofPart2[29] = (0x7a4e463b9e70b0b696dfbdf889158587a97fef29a5ccec0e9280623518965f4d);
        serializedProofPart2[30] = (0xcc5b7968dccd9e745adadb83015cd9e23c93952cb531f2f4288da589c0069574);
        serializedProofPart2[31] = (0xe7f91b230e048be6e77b32dc40b244236168ca832273465751c4f2ccc01cbf64);
        serializedProofPart2[32] = (0xc6e1ae5fca24804ade878f6ef38651c10c05a135e3f97bfd2d904fda94c7a9b1);
        serializedProofPart2[33] = (0x7a4e463b9e70b0b696dfbdf889158587a97fef29a5ccec0e9280623518965f4d);
        serializedProofPart2[34] = (0xbaea13ee7c8871272649ac7715c915a9a56ed50a8dea0571e2eff309d40f58ab);
        serializedProofPart2[35] = (0x82225a228142d0995337f879f93baf9f33e98586d1fc033a7dacbef88a99fe20);
        serializedProofPart2[36] = (0x4f776b37f90ad57ce6ea738d9aa08ab70f7b59b4f3936d07b1232bb77dc23b49);
        serializedProofPart2[37] = (0x9186c52b1e29b407b2ced700d98969bd27ef020d51bedc925a12759bc01b277d);
        serializedProofPart2[38] = (0x5cbd85f2d305fe00912332e05075b9f0de9c10f44ec7ab91b1f62084281f248c);
        serializedProofPart2[39] = (0x72369709049708f987668022c05c3ff71329e24dbda58f5107687c2c1c019bc3);
        serializedProofPart2[40] = (0x54bf083810754a2f2e0ea1a9c2cc1cd0dff97d8fd62a463be309018d5e482d10);
        serializedProofPart2[41] = (0x4f95625e828ae72498ff9d6e15029b414cd6cc9a8ba6d8f1dc1366f2879c76a8);

        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        ///////////////////////////////////             PUBLIC INPUTS             ////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

        publicInputs[0] = (0x00000000000000000000000000000000ad92adf90254df20eb73f68015e9a000);
        publicInputs[1] = (0x0000000000000000000000000000000000000000000000000000000001e371b2);
        publicInputs[2] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[3] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[4] = (0x00000000000000000000000000000000ad92adf90254df20eb73f68015e9a000);
        publicInputs[5] = (0x0000000000000000000000000000000000000000000000000000000001e371b2);
        publicInputs[6] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[7] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[8] = (0x00000000000000000000000000000000bcbd36a06b28bf1d5459edbe7dea2c85);
        publicInputs[9] = (0x00000000000000000000000000000000000000000000000000000000fc284778);
        publicInputs[10] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[11] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[12] = (0x00000000000000000000000000000000bcbd36a06b28bf1d5459edbe7dea2c85);
        publicInputs[13] = (0x00000000000000000000000000000000000000000000000000000000fc284778);
        publicInputs[14] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[15] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[16] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[17] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[18] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[19] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[20] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[21] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[22] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[23] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[24] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[25] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[26] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[27] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[28] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[29] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[30] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[31] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[32] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[33] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[34] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[35] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[36] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[37] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[38] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[39] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[40] = (0x000000000000000000000000000000004c9920779783843241d6b450935960df);
        publicInputs[41] = (0x00000000000000000000000000000000e69a44d2db21957ed88948127ec06b10);
        publicInputs[42] = (0x000000000000000000000000000000004c9920779783843241d6b450935960df);
        publicInputs[43] = (0x00000000000000000000000000000000e69a44d2db21957ed88948127ec06b10);
        publicInputs[44] = (0x000000000000000000000000000000004cba917fb9796a16f3ca5bc38b943d00);
        publicInputs[45] = (0x0000000000000000000000000000000099377efdd5f7e86f7648b87c1eccd6a8);
        publicInputs[46] = (0x000000000000000000000000000000004cba917fb9796a16f3ca5bc38b943d00);
        publicInputs[47] = (0x0000000000000000000000000000000099377efdd5f7e86f7648b87c1eccd6a8);
        publicInputs[48] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[49] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[50] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[51] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[52] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[53] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[54] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[55] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[56] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[57] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[58] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[59] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[60] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[61] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[62] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[63] = (0x0000000000000000000000000000000000000000000000000000000000000000);

        smax = 512;
    }
}
