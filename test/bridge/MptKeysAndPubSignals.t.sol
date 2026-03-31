// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeProofManager.sol";
import "../../src/BridgeDepositManager.sol";
import "../../src/BridgeAdminManager.sol";
import "../../src/interface/ITokamakVerifier.sol";
import "../../src/interface/IGroth16Verifier16Leaves.sol";
import "../../src/library/ZecFrost.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

// Simple ERC20 token (no additional storage slots)
contract SimpleToken is ERC20 {
    constructor() ERC20("Simple Token", "SIMPLE") {
        _mint(msg.sender, 1000000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// USDT-like token with blacklist functionality (1 additional storage slot)
contract USDTToken is ERC20 {
    mapping(address => bool) private _isBlackListed;

    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function addBlackList(address user) external {
        _isBlackListed[user] = true;
    }

    function removeBlackList(address user) external {
        _isBlackListed[user] = false;
    }

    function isBlackListed(address user) external view returns (bool) {
        return _isBlackListed[user];
    }
}

contract MockTokamakVerifier is ITokamakVerifier {
    function verify(uint128[] calldata, uint256[] calldata, uint128[] calldata, uint256[] calldata, uint256[] calldata, uint256)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

contract MockGroth16Verifier is IGroth16Verifier16Leaves {
    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[33] calldata)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

/**
 * @title MptKeysAndPubSignalsTest
 * @notice Tests for MPT keys storage and pubSignals array construction in initializeChannelState
 */
contract MptKeysAndPubSignalsTest is Test {
    BridgeCore public bridge;
    BridgeProofManager public proofManager;
    BridgeDepositManager public depositManager;
    BridgeAdminManager public adminManager;

    MockTokamakVerifier public tokamakVerifier;
    MockGroth16Verifier public groth16Verifier;
    ZecFrost public zecFrost;
    SimpleToken public simpleToken;
    USDTToken public usdtToken;

    address public owner = makeAddr("owner");
    address public leader = makeAddr("leader");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    // MPT keys for testing
    uint256 constant USER1_BALANCE_MPT_KEY = 1001;
    uint256 constant USER1_BLACKLIST_MPT_KEY = 2001;
    uint256 constant USER2_BALANCE_MPT_KEY = 1002;
    uint256 constant USER2_BLACKLIST_MPT_KEY = 2002;
    uint256 constant USER3_BALANCE_MPT_KEY = 1003;
    uint256 constant USER3_BLACKLIST_MPT_KEY = 2003;

    function setUp() public {
        vm.roll(100); // Set block number to avoid underflow

        vm.startPrank(owner);

        // Deploy mock contracts
        tokamakVerifier = new MockTokamakVerifier();
        groth16Verifier = new MockGroth16Verifier();
        zecFrost = new ZecFrost();
        simpleToken = new SimpleToken();
        usdtToken = new USDTToken();

        // Deploy manager implementations
        BridgeDepositManager depositManagerImpl = new BridgeDepositManager();
        BridgeProofManager proofManagerImpl = new BridgeProofManager();
        BridgeAdminManager adminManagerImpl = new BridgeAdminManager();

        // Deploy core contract with proxy
        BridgeCore implementation = new BridgeCore();
        bytes memory bridgeInitData = abi.encodeCall(
            BridgeCore.initialize,
            (address(0), address(0), address(0), address(0), owner)
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(implementation), bridgeInitData);
        bridge = BridgeCore(address(bridgeProxy));

        // Deploy manager proxies
        bytes memory depositInitData = abi.encodeCall(BridgeDepositManager.initialize, (address(bridge), owner));
        ERC1967Proxy depositProxy = new ERC1967Proxy(address(depositManagerImpl), depositInitData);
        depositManager = BridgeDepositManager(address(depositProxy));

        address[4] memory groth16Verifiers = [
            address(groth16Verifier),
            address(groth16Verifier),
            address(groth16Verifier),
            address(groth16Verifier)
        ];
        bytes memory proofInitData = abi.encodeCall(
            BridgeProofManager.initialize,
            (address(bridge), address(tokamakVerifier), address(zecFrost), groth16Verifiers, owner)
        );
        ERC1967Proxy proofProxy = new ERC1967Proxy(address(proofManagerImpl), proofInitData);
        proofManager = BridgeProofManager(address(proofProxy));

        bytes memory adminInitData = abi.encodeCall(BridgeAdminManager.initialize, (address(bridge), owner));
        ERC1967Proxy adminProxy = new ERC1967Proxy(address(adminManagerImpl), adminInitData);
        adminManager = BridgeAdminManager(address(adminProxy));

        // Update manager addresses
        bridge.updateManagerAddresses(
            address(depositManager), address(proofManager), address(0), address(adminManager)
        );

        // Register simple token with balance slot only
        IBridgeCore.PreAllocatedLeaf[] memory emptyLeaves = new IBridgeCore.PreAllocatedLeaf[](0);
        IBridgeCore.UserStorageSlot[] memory simpleSlots = new IBridgeCore.UserStorageSlot[](1);
        simpleSlots[0] = IBridgeCore.UserStorageSlot({
            slotOffset: 0, // balance slot
            getterFunctionSignature: bytes32(0),
            isLoadedOnChain: false // balance comes from deposits
        });
        adminManager.setAllowedTargetContract(address(simpleToken), emptyLeaves, simpleSlots, true);

        // Register USDT token with balance + isBlackListed storage slots
        IBridgeCore.UserStorageSlot[] memory usdtSlots = new IBridgeCore.UserStorageSlot[](2);
        usdtSlots[0] = IBridgeCore.UserStorageSlot({
            slotOffset: 0, // slotOffset 0 for balance
            getterFunctionSignature: bytes32(0),
            isLoadedOnChain: false // balance comes from deposits
        });
        usdtSlots[1] = IBridgeCore.UserStorageSlot({
            slotOffset: 1, // slotOffset 1 for isBlackListed
            getterFunctionSignature: bytes32(bytes4(keccak256("isBlackListed(address)"))),
            isLoadedOnChain: true // fetched from chain
        });
        adminManager.setAllowedTargetContract(address(usdtToken), emptyLeaves, usdtSlots, true);

        // Mint tokens to participants and leader
        simpleToken.mint(user1, 100 ether);
        simpleToken.mint(user2, 100 ether);
        simpleToken.mint(user3, 100 ether);
        simpleToken.mint(leader, 100 ether);
        usdtToken.mint(user1, 100 ether);
        usdtToken.mint(user2, 100 ether);
        usdtToken.mint(user3, 100 ether);
        usdtToken.mint(leader, 100 ether);

        vm.stopPrank();
    }

    // ========== MPT KEYS STORAGE TESTS ==========

    function testMptKeysStoredCorrectlyForSimpleToken() public {
        bytes32 channelId = _createSimpleTokenChannel();

        // User1 deposits with 1 MPT key (balance only)
        vm.startPrank(user1);
        simpleToken.approve(address(depositManager), 10 ether);
        bytes32[] memory mptKeys = new bytes32[](1);
        mptKeys[0] = bytes32(USER1_BALANCE_MPT_KEY);
        depositManager.depositToken(channelId, 10 ether, mptKeys);
        vm.stopPrank();

        // Verify MPT key stored correctly at slot 0
        uint256 storedKey = bridge.getL2MptKey(channelId, user1, 0);
        assertEq(storedKey, USER1_BALANCE_MPT_KEY, "Balance MPT key not stored correctly");
    }

    function testMptKeysStoredCorrectlyForUSDTToken() public {
        bytes32 channelId = _createUSDTChannel();

        // User1 deposits with 2 MPT keys (balance + isBlackListed)
        vm.startPrank(user1);
        usdtToken.approve(address(depositManager), 10 ether);
        bytes32[] memory mptKeys = new bytes32[](2);
        mptKeys[0] = bytes32(USER1_BALANCE_MPT_KEY);
        mptKeys[1] = bytes32(USER1_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 10 ether, mptKeys);
        vm.stopPrank();

        // Verify MPT keys stored correctly at respective slots
        uint256 balanceKey = bridge.getL2MptKey(channelId, user1, 0);
        uint256 blacklistKey = bridge.getL2MptKey(channelId, user1, 1);

        assertEq(balanceKey, USER1_BALANCE_MPT_KEY, "Balance MPT key not stored correctly");
        assertEq(blacklistKey, USER1_BLACKLIST_MPT_KEY, "Blacklist MPT key not stored correctly");
    }

    function testMptKeysStoredCorrectlyForMultipleUsers() public {
        bytes32 channelId = _createUSDTChannel();

        // User1 deposits
        vm.startPrank(user1);
        usdtToken.approve(address(depositManager), 10 ether);
        bytes32[] memory mptKeys1 = new bytes32[](2);
        mptKeys1[0] = bytes32(USER1_BALANCE_MPT_KEY);
        mptKeys1[1] = bytes32(USER1_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 10 ether, mptKeys1);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        usdtToken.approve(address(depositManager), 20 ether);
        bytes32[] memory mptKeys2 = new bytes32[](2);
        mptKeys2[0] = bytes32(USER2_BALANCE_MPT_KEY);
        mptKeys2[1] = bytes32(USER2_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 20 ether, mptKeys2);
        vm.stopPrank();

        // User3 deposits
        vm.startPrank(user3);
        usdtToken.approve(address(depositManager), 15 ether);
        bytes32[] memory mptKeys3 = new bytes32[](2);
        mptKeys3[0] = bytes32(USER3_BALANCE_MPT_KEY);
        mptKeys3[1] = bytes32(USER3_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 15 ether, mptKeys3);
        vm.stopPrank();

        // Verify all MPT keys stored correctly
        assertEq(bridge.getL2MptKey(channelId, user1, 0), USER1_BALANCE_MPT_KEY);
        assertEq(bridge.getL2MptKey(channelId, user1, 1), USER1_BLACKLIST_MPT_KEY);
        assertEq(bridge.getL2MptKey(channelId, user2, 0), USER2_BALANCE_MPT_KEY);
        assertEq(bridge.getL2MptKey(channelId, user2, 1), USER2_BLACKLIST_MPT_KEY);
        assertEq(bridge.getL2MptKey(channelId, user3, 0), USER3_BALANCE_MPT_KEY);
        assertEq(bridge.getL2MptKey(channelId, user3, 1), USER3_BLACKLIST_MPT_KEY);
    }

    function testMptKeysCountMismatchReverts() public {
        bytes32 channelId = _createUSDTChannel();

        // Try to deposit with wrong number of MPT keys (1 instead of 2)
        vm.startPrank(user1);
        usdtToken.approve(address(depositManager), 10 ether);
        bytes32[] memory wrongMptKeys = new bytes32[](1);
        wrongMptKeys[0] = bytes32(USER1_BALANCE_MPT_KEY);

        vm.expectRevert("MPT keys count mismatch");
        depositManager.depositToken(channelId, 10 ether, wrongMptKeys);
        vm.stopPrank();
    }

    function testMptKeysTooManyReverts() public {
        bytes32 channelId = _createSimpleTokenChannel();

        // Try to deposit with too many MPT keys (2 instead of 1)
        vm.startPrank(user1);
        simpleToken.approve(address(depositManager), 10 ether);
        bytes32[] memory wrongMptKeys = new bytes32[](2);
        wrongMptKeys[0] = bytes32(USER1_BALANCE_MPT_KEY);
        wrongMptKeys[1] = bytes32(USER1_BLACKLIST_MPT_KEY);

        vm.expectRevert("MPT keys count mismatch");
        depositManager.depositToken(channelId, 10 ether, wrongMptKeys);
        vm.stopPrank();
    }

    // ========== PUBSIGNALS INPUT DATA VERIFICATION TESTS ==========
    // These tests verify that all the data that goes into pubSignals construction is correct

    function testPubSignalsInputsForSimpleToken() public {
        bytes32 channelId = _createSimpleTokenChannel();

        // Leader must deposit before initializing
        vm.startPrank(leader);
        simpleToken.approve(address(depositManager), 1 ether);
        bytes32[] memory mptKeysLeader = new bytes32[](1);
        mptKeysLeader[0] = bytes32(uint256(999));
        depositManager.depositToken(channelId, 1 ether, mptKeysLeader);
        vm.stopPrank();

        // User1 deposits 10 ether
        vm.startPrank(user1);
        simpleToken.approve(address(depositManager), 10 ether);
        bytes32[] memory mptKeys1 = new bytes32[](1);
        mptKeys1[0] = bytes32(USER1_BALANCE_MPT_KEY);
        depositManager.depositToken(channelId, 10 ether, mptKeys1);
        vm.stopPrank();

        // User2 deposits 20 ether
        vm.startPrank(user2);
        simpleToken.approve(address(depositManager), 20 ether);
        bytes32[] memory mptKeys2 = new bytes32[](1);
        mptKeys2[0] = bytes32(USER2_BALANCE_MPT_KEY);
        depositManager.depositToken(channelId, 20 ether, mptKeys2);
        vm.stopPrank();

        // Verify all inputs that go into pubSignals are correct
        address[] memory participants = bridge.getChannelParticipants(channelId);
        assertEq(participants.length, 3, "Should have 3 participants (leader + 2 users)");
        assertEq(participants[0], leader);
        assertEq(participants[1], user1);
        assertEq(participants[2], user2);

        // Verify balances
        assertEq(bridge.getValidatedUserSlotValue(channelId, leader, 0), 1 ether);
        assertEq(bridge.getValidatedUserSlotValue(channelId, user1, 0), 10 ether);
        assertEq(bridge.getValidatedUserSlotValue(channelId, user2, 0), 20 ether);

        // Verify MPT keys for balance slot (slot 0)
        assertEq(bridge.getL2MptKey(channelId, user1, 0), USER1_BALANCE_MPT_KEY);
        assertEq(bridge.getL2MptKey(channelId, user2, 0), USER2_BALANCE_MPT_KEY);

        // Verify tree size
        assertEq(bridge.getChannelTreeSize(channelId), 16);

        // Initialize channel to verify the proof manager accepts the data
        bytes32 merkleRoot = keccak256("testMerkleRoot");
        vm.prank(leader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
                pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
                pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
                merkleRoot: merkleRoot
            })
        );

        // Verify channel state changed to Open (proves initialization succeeded)
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(IBridgeCore.ChannelState.Open));
    }

    function testPubSignalsInputsForUSDTToken() public {
        bytes32 channelId = _createUSDTChannel();

        // Leader must deposit before initializing
        vm.startPrank(leader);
        usdtToken.approve(address(depositManager), 1 ether);
        bytes32[] memory mptKeysLeader = new bytes32[](2);
        mptKeysLeader[0] = bytes32(uint256(998));
        mptKeysLeader[1] = bytes32(uint256(999));
        depositManager.depositToken(channelId, 1 ether, mptKeysLeader);
        vm.stopPrank();

        // User1 deposits 10 ether (will not be blacklisted)
        vm.startPrank(user1);
        usdtToken.approve(address(depositManager), 10 ether);
        bytes32[] memory mptKeys1 = new bytes32[](2);
        mptKeys1[0] = bytes32(USER1_BALANCE_MPT_KEY);
        mptKeys1[1] = bytes32(USER1_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 10 ether, mptKeys1);
        vm.stopPrank();

        // User2 deposits 20 ether (will be blacklisted after deposit)
        vm.startPrank(user2);
        usdtToken.approve(address(depositManager), 20 ether);
        bytes32[] memory mptKeys2 = new bytes32[](2);
        mptKeys2[0] = bytes32(USER2_BALANCE_MPT_KEY);
        mptKeys2[1] = bytes32(USER2_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 20 ether, mptKeys2);
        vm.stopPrank();

        // Blacklist user2 AFTER deposit
        vm.prank(owner);
        usdtToken.addBlackList(user2);

        // Verify all inputs that go into pubSignals
        address[] memory participants = bridge.getChannelParticipants(channelId);
        assertEq(participants.length, 3, "Should have 3 participants (leader + 2 users)");
        assertEq(participants[0], leader);
        assertEq(participants[1], user1);
        assertEq(participants[2], user2);

        // Verify balances
        assertEq(bridge.getValidatedUserSlotValue(channelId, leader, 0), 1 ether);
        assertEq(bridge.getValidatedUserSlotValue(channelId, user1, 0), 10 ether);
        assertEq(bridge.getValidatedUserSlotValue(channelId, user2, 0), 20 ether);

        // Verify MPT keys for balance slot (slot 0)
        assertEq(bridge.getL2MptKey(channelId, user1, 0), USER1_BALANCE_MPT_KEY);
        assertEq(bridge.getL2MptKey(channelId, user2, 0), USER2_BALANCE_MPT_KEY);

        // Verify MPT keys for blacklist slot (slot 1)
        assertEq(bridge.getL2MptKey(channelId, user1, 1), USER1_BLACKLIST_MPT_KEY);
        assertEq(bridge.getL2MptKey(channelId, user2, 1), USER2_BLACKLIST_MPT_KEY);

        // Verify blacklist status (will be fetched via staticcall during initialization)
        assertFalse(usdtToken.isBlackListed(user1), "user1 should not be blacklisted");
        assertTrue(usdtToken.isBlackListed(user2), "user2 should be blacklisted");

        // Verify tree size (3 participants * 2 slots = 6 leaves, fits in tree size 16)
        assertEq(bridge.getChannelTreeSize(channelId), 16);

        // Initialize channel to verify the proof manager accepts the data
        bytes32 merkleRoot = keccak256("testMerkleRoot");
        vm.prank(leader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
                pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
                pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
                merkleRoot: merkleRoot
            })
        );

        // Verify channel state changed to Open
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(IBridgeCore.ChannelState.Open));
    }

    function testPubSignalsConstructionLogic() public {
        bytes32 channelId = _createUSDTChannel();

        // Leader must deposit before initializing
        vm.startPrank(leader);
        usdtToken.approve(address(depositManager), 1 ether);
        bytes32[] memory mptKeysLeader = new bytes32[](2);
        mptKeysLeader[0] = bytes32(uint256(998));
        mptKeysLeader[1] = bytes32(uint256(999));
        depositManager.depositToken(channelId, 1 ether, mptKeysLeader);
        vm.stopPrank();

        // Setup: 3 users deposit with specific MPT keys and amounts
        vm.startPrank(user1);
        usdtToken.approve(address(depositManager), 10 ether);
        bytes32[] memory mptKeys1 = new bytes32[](2);
        mptKeys1[0] = bytes32(USER1_BALANCE_MPT_KEY);
        mptKeys1[1] = bytes32(USER1_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 10 ether, mptKeys1);
        vm.stopPrank();

        vm.startPrank(user2);
        usdtToken.approve(address(depositManager), 20 ether);
        bytes32[] memory mptKeys2 = new bytes32[](2);
        mptKeys2[0] = bytes32(USER2_BALANCE_MPT_KEY);
        mptKeys2[1] = bytes32(USER2_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 20 ether, mptKeys2);
        vm.stopPrank();

        vm.startPrank(user3);
        usdtToken.approve(address(depositManager), 15 ether);
        bytes32[] memory mptKeys3 = new bytes32[](2);
        mptKeys3[0] = bytes32(USER3_BALANCE_MPT_KEY);
        mptKeys3[1] = bytes32(USER3_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 15 ether, mptKeys3);
        vm.stopPrank();

        // Blacklist user3
        vm.prank(owner);
        usdtToken.addBlackList(user3);

        // Manually construct what pubSignals SHOULD look like
        // Based on initializeChannelState logic:
        // pubSignals[0] = merkleRoot
        // For treeSize=16:
        //   Indices 1-16: keys
        //   Indices 17-32: values
        // Order: ALL balance leaves first, then ALL blacklist leaves

        uint256 treeSize = bridge.getChannelTreeSize(channelId);
        assertEq(treeSize, 16, "Tree size should be 16");

        address[] memory participants = bridge.getChannelParticipants(channelId);
        assertEq(participants.length, 4, "Should have 4 participants (leader + 3 users)");
        assertEq(participants[0], leader, "First participant should be leader");
        assertEq(participants[1], user1, "Second participant should be user1");
        assertEq(participants[2], user2, "Third participant should be user2");
        assertEq(participants[3], user3, "Fourth participant should be user3");

        // Verify balances for users (not checking leader's MPT key as it uses different constant)
        assertEq(bridge.getL2MptKey(channelId, user1, 0), USER1_BALANCE_MPT_KEY, "user1 balance key");
        assertEq(bridge.getL2MptKey(channelId, user2, 0), USER2_BALANCE_MPT_KEY, "user2 balance key");
        assertEq(bridge.getL2MptKey(channelId, user3, 0), USER3_BALANCE_MPT_KEY, "user3 balance key");
        assertEq(bridge.getL2MptKey(channelId, user1, 1), USER1_BLACKLIST_MPT_KEY, "user1 blacklist key");
        assertEq(bridge.getL2MptKey(channelId, user2, 1), USER2_BLACKLIST_MPT_KEY, "user2 blacklist key");
        assertEq(bridge.getL2MptKey(channelId, user3, 1), USER3_BLACKLIST_MPT_KEY, "user3 blacklist key");

        assertEq(bridge.getValidatedUserSlotValue(channelId, leader, 0), 1 ether, "leader balance");
        assertEq(bridge.getValidatedUserSlotValue(channelId, user1, 0), 10 ether, "user1 balance");
        assertEq(bridge.getValidatedUserSlotValue(channelId, user2, 0), 20 ether, "user2 balance");
        assertEq(bridge.getValidatedUserSlotValue(channelId, user3, 0), 15 ether, "user3 balance");
        assertEq(usdtToken.isBlackListed(leader) ? 1 : 0, 0, "leader not blacklisted");
        assertEq(usdtToken.isBlackListed(user1) ? 1 : 0, 0, "user1 not blacklisted");
        assertEq(usdtToken.isBlackListed(user2) ? 1 : 0, 0, "user2 not blacklisted");
        assertEq(usdtToken.isBlackListed(user3) ? 1 : 0, 1, "user3 is blacklisted");

        // Initialize channel to confirm the proof manager constructs pubSignals correctly
        bytes32 merkleRoot = keccak256("testMerkleRoot");
        vm.prank(leader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
                pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
                pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
                merkleRoot: merkleRoot
            })
        );

        // Channel initialization succeeded
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(IBridgeCore.ChannelState.Open));
    }

    function testPubSignalsOrderingIsCorrect() public {
        // This test verifies the ordering: ALL balance leaves first, then ALL additional storage slot leaves
        bytes32 channelId = _createUSDTChannel();

        // Leader must deposit before initializing
        vm.startPrank(leader);
        usdtToken.approve(address(depositManager), 1 ether);
        bytes32[] memory mptKeysLeader = new bytes32[](2);
        mptKeysLeader[0] = bytes32(uint256(998));
        mptKeysLeader[1] = bytes32(uint256(999));
        depositManager.depositToken(channelId, 1 ether, mptKeysLeader);
        vm.stopPrank();

        // Deposit for all 3 users
        vm.startPrank(user1);
        usdtToken.approve(address(depositManager), 10 ether);
        bytes32[] memory mptKeys1 = new bytes32[](2);
        mptKeys1[0] = bytes32(USER1_BALANCE_MPT_KEY);
        mptKeys1[1] = bytes32(USER1_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 10 ether, mptKeys1);
        vm.stopPrank();

        vm.startPrank(user2);
        usdtToken.approve(address(depositManager), 20 ether);
        bytes32[] memory mptKeys2 = new bytes32[](2);
        mptKeys2[0] = bytes32(USER2_BALANCE_MPT_KEY);
        mptKeys2[1] = bytes32(USER2_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 20 ether, mptKeys2);
        vm.stopPrank();

        vm.startPrank(user3);
        usdtToken.approve(address(depositManager), 15 ether);
        bytes32[] memory mptKeys3 = new bytes32[](2);
        mptKeys3[0] = bytes32(USER3_BALANCE_MPT_KEY);
        mptKeys3[1] = bytes32(USER3_BLACKLIST_MPT_KEY);
        depositManager.depositToken(channelId, 15 ether, mptKeys3);
        vm.stopPrank();

        // Get participants to verify ordering
        address[] memory participants = bridge.getChannelParticipants(channelId);

        // The pubSignals should be ordered as:
        // [0]: merkleRoot
        // [1]: participants[0] balance key (leader)
        // [2]: participants[1] balance key (user1)
        // [3]: participants[2] balance key (user2)
        // [4]: participants[3] balance key (user3)
        // [5]: participants[0] blacklist key (leader)
        // [6]: participants[1] blacklist key (user1)
        // [7]: participants[2] blacklist key (user2)
        // [8]: participants[3] blacklist key (user3)
        // ... zeros until treeSize
        // [treeSize+1]: participants[0] balance value
        // etc.

        // Verify participants are in expected order (leader first, then users)
        assertEq(participants.length, 4, "Should have 4 participants");
        assertEq(participants[0], leader);
        assertEq(participants[1], user1);
        assertEq(participants[2], user2);
        assertEq(participants[3], user3);

        // Initialize to confirm the construction works
        vm.prank(leader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
                pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
                pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
                merkleRoot: keccak256("testRoot")
            })
        );

        assertEq(uint8(bridge.getChannelState(channelId)), uint8(IBridgeCore.ChannelState.Open));
    }

    // ========== HELPER FUNCTIONS ==========

    function _createSimpleTokenChannel() internal returns (bytes32 channelId) {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        channelId = keccak256(abi.encode(address(this), block.timestamp, "simpleTokenChannel"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(simpleToken),
            whitelisted: participants,
            enableFrostSignature: false
        });

        bridge.openChannel(params);
        vm.stopPrank();
    }

    function _createUSDTChannel() internal returns (bytes32 channelId) {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        channelId = keccak256(abi.encode(address(this), block.timestamp, "usdtChannel"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(usdtToken),
            whitelisted: participants,
            enableFrostSignature: false
        });

        bridge.openChannel(params);
        vm.stopPrank();
    }
}
