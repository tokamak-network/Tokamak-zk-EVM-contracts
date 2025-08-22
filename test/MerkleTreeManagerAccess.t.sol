// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/merkleTree/MerkleTreeManager4.sol";
import {IPoseidon4Yul} from "../src/interface/IPoseidon4Yul.sol";
import {MockPoseidon4Yul} from "./MockPoseidon4Yul.sol";

contract MerkleTreeManagerAccessTest is Test {
    MerkleTreeManager4 public mtManager;
    IPoseidon4Yul public poseidon;

    address public owner = address(1);
    address public bridge = address(2);
    address public attacker = address(666);

    address public user1 = address(3);
    address public user2 = address(4);
    address public l2User1 = address(13);
    address public l2User2 = address(14);

    uint256 public constant CHANNEL_ID = 1;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy Poseidon hasher
        poseidon = new MockPoseidon4Yul();

        // Deploy MerkleTreeManager
        mtManager = new MerkleTreeManager4(address(poseidon));

        // Set the bridge address
        mtManager.setBridge(bridge);

        vm.stopPrank();
    }

    function testOnlyBridgeCanInitializeChannel() public {
        // Bridge can initialize
        vm.prank(bridge);
        mtManager.initializeChannel(CHANNEL_ID);

        // Attacker cannot initialize another channel
        vm.prank(attacker);
        vm.expectRevert("Only bridge can call");
        mtManager.initializeChannel(2);
    }

    function testOnlyBridgeCanSetAddressPair() public {
        // First initialize channel as bridge
        vm.prank(bridge);
        mtManager.initializeChannel(CHANNEL_ID);

        // Bridge can set address pair
        vm.prank(bridge);
        mtManager.setAddressPair(CHANNEL_ID, user1, l2User1);

        // Verify it was set
        assertEq(mtManager.getL2Address(CHANNEL_ID, user1), l2User1);

        // Attacker cannot set address pair
        vm.prank(attacker);
        vm.expectRevert("Only bridge can call");
        mtManager.setAddressPair(CHANNEL_ID, user2, l2User2);
    }

    function testOnlyBridgeCanAddUsers() public {
        // Setup: Initialize channel and set address pairs
        vm.startPrank(bridge);
        mtManager.initializeChannel(CHANNEL_ID);
        mtManager.setAddressPair(CHANNEL_ID, user1, l2User1);
        mtManager.setAddressPair(CHANNEL_ID, user2, l2User2);
        vm.stopPrank();

        // Prepare arrays for addUsers
        address[] memory l1Addresses = new address[](2);
        l1Addresses[0] = user1;
        l1Addresses[1] = user2;

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1 ether;
        balances[1] = 2 ether;

        // Attacker tries to add users - should fail
        vm.prank(attacker);
        vm.expectRevert("Only bridge can call");
        mtManager.addUsers(CHANNEL_ID, l1Addresses, balances);

        // Bridge can add users successfully
        vm.prank(bridge);
        mtManager.addUsers(CHANNEL_ID, l1Addresses, balances);

        // Verify users were added
        assertEq(mtManager.getBalance(CHANNEL_ID, user1), 1 ether);
        assertEq(mtManager.getBalance(CHANNEL_ID, user2), 2 ether);
    }

    function testOnlyOwnerCanSetBridge() public {
        // Deploy a new MerkleTreeManager without bridge set
        MerkleTreeManager4 newMtManager = new MerkleTreeManager4(address(poseidon));

        // Attacker cannot set bridge
        vm.prank(attacker);
        vm.expectRevert(); // Will revert with Ownable's "OwnableUnauthorizedAccount" error
        newMtManager.setBridge(attacker);

        // Owner can set bridge
        vm.prank(address(this)); // Test contract is the owner of newMtManager
        newMtManager.setBridge(bridge);

        assertEq(newMtManager.bridge(), bridge);
        assertTrue(newMtManager.bridgeSet());
    }

    function testBridgeCanOnlyBeSetOnce() public {
        // Deploy a new MerkleTreeManager
        MerkleTreeManager4 newMtManager = new MerkleTreeManager4(address(poseidon));

        // Set bridge once
        newMtManager.setBridge(bridge);

        // Try to set bridge again - should fail
        vm.expectRevert("Bridge already set");
        newMtManager.setBridge(address(999));

        // Bridge remains unchanged
        assertEq(newMtManager.bridge(), bridge);
    }

    function testAttackerCannotBypassThroughBridge() public {
        // This test simulates if an attacker somehow got control of the bridge contract
        // or tried to call MerkleTreeManager directly pretending to be the bridge

        // Setup channel properly first
        vm.startPrank(bridge);
        mtManager.initializeChannel(CHANNEL_ID);
        mtManager.setAddressPair(CHANNEL_ID, user1, l2User1);
        vm.stopPrank();

        // Even if attacker knows the channel ID and user addresses,
        // they cannot call addUsers directly
        address[] memory l1Addresses = new address[](1);
        l1Addresses[0] = user1;

        uint256[] memory balances = new uint256[](1);
        balances[0] = 1000 ether; // Attacker tries to set huge balance

        vm.prank(attacker);
        vm.expectRevert("Only bridge can call");
        mtManager.addUsers(CHANNEL_ID, l1Addresses, balances);

        // Balance remains 0
        assertEq(mtManager.getBalance(CHANNEL_ID, user1), 0);
    }

    function testPublicViewFunctionsAreAccessible() public {
        // Setup a channel
        vm.startPrank(bridge);
        mtManager.initializeChannel(CHANNEL_ID);
        mtManager.setAddressPair(CHANNEL_ID, user1, l2User1);

        address[] memory l1Addresses = new address[](1);
        l1Addresses[0] = user1;
        uint256[] memory balances = new uint256[](1);
        balances[0] = 1 ether;

        mtManager.addUsers(CHANNEL_ID, l1Addresses, balances);
        vm.stopPrank();

        // Anyone (including attacker) can read data
        vm.startPrank(attacker);

        // All these view functions should work
        uint256 balance = mtManager.getBalance(CHANNEL_ID, user1);
        assertEq(balance, 1 ether);

        address l2Addr = mtManager.getL2Address(CHANNEL_ID, user1);
        assertEq(l2Addr, l2User1);

        bytes32 currentRoot = mtManager.getCurrentRoot(CHANNEL_ID);
        assertTrue(currentRoot != bytes32(0));

        bytes32 latestRoot = mtManager.getLatestRoot(CHANNEL_ID);
        assertEq(currentRoot, latestRoot);

        uint256 seqLength = mtManager.getRootSequenceLength(CHANNEL_ID);
        assertTrue(seqLength > 0);

        // Verify proof function is accessible
        // Test with actual leaf and root values from the tree
        bytes32 actualLeaf = mtManager.computeLeafForVerification(l2User1, 1 ether, bytes32(0));
        bytes32 actualRoot = mtManager.getLatestRoot(CHANNEL_ID);

        // Test with matching values - this should return true
        bytes32[] memory emptyProof = new bytes32[](0);
        bool valid = mtManager.verifyProof(CHANNEL_ID, emptyProof, actualLeaf, 0, actualRoot);
        assertTrue(valid); // Returns true because computedHash matches root

        // Test with non-matching values - this should return false
        bool invalid = mtManager.verifyProof(CHANNEL_ID, emptyProof, bytes32(uint256(1)), 0, actualRoot);
        assertFalse(invalid); // Returns false because computedHash (1) != root

        vm.stopPrank();
    }

    function testInitializeChannelStateFunctionFlow() public {
        // This simulates the actual flow from ZKRollupBridge.initializeChannelState()

        // 1. Bridge initializes the channel
        vm.prank(bridge);
        mtManager.initializeChannel(CHANNEL_ID);

        // 2. Bridge sets address pairs (simulating the loop in initializeChannelState)
        vm.startPrank(bridge);
        mtManager.setAddressPair(CHANNEL_ID, user1, l2User1);
        mtManager.setAddressPair(CHANNEL_ID, user2, l2User2);

        // 3. Bridge adds users with balances
        address[] memory l1Addresses = new address[](2);
        l1Addresses[0] = user1;
        l1Addresses[1] = user2;

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1 ether;
        balances[1] = 2 ether;

        mtManager.addUsers(CHANNEL_ID, l1Addresses, balances);
        vm.stopPrank();

        // 4. Verify the state was properly initialized
        assertEq(mtManager.getBalance(CHANNEL_ID, user1), 1 ether);
        assertEq(mtManager.getBalance(CHANNEL_ID, user2), 2 ether);

        // 5. Attacker tries to manipulate the state after initialization
        vm.prank(attacker);
        vm.expectRevert("Only bridge can call");
        mtManager.addUsers(CHANNEL_ID, l1Addresses, balances); // Try to add users again

        // 6. Even the owner cannot call addUsers
        vm.prank(owner);
        vm.expectRevert("Only bridge can call");
        mtManager.addUsers(CHANNEL_ID, l1Addresses, balances);

        // 7. Verify that users cannot be added twice even by bridge
        vm.prank(bridge);
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.UsersAlreadyAdded.selector, CHANNEL_ID));
        mtManager.addUsers(CHANNEL_ID, l1Addresses, balances);
    }

    function testCompleteAccessControlMatrix() public {
        // This test verifies all access control combinations

        vm.prank(bridge);
        mtManager.initializeChannel(CHANNEL_ID);

        // Test all protected functions with different callers
        address[] memory callers = new address[](3);
        callers[0] = attacker;
        callers[1] = owner;
        callers[2] = user1;

        for (uint256 i = 0; i < callers.length; i++) {
            address caller = callers[i];

            // Test initializeChannel
            vm.prank(caller);
            vm.expectRevert("Only bridge can call");
            mtManager.initializeChannel(100 + i);

            // Test setAddressPair
            vm.prank(caller);
            vm.expectRevert("Only bridge can call");
            mtManager.setAddressPair(CHANNEL_ID, address(uint160(100 + i)), address(uint160(200 + i)));

            // Test addUsers
            address[] memory testAddresses = new address[](1);
            testAddresses[0] = address(uint160(100 + i));
            uint256[] memory testBalances = new uint256[](1);
            testBalances[0] = 1 ether;

            vm.prank(caller);
            vm.expectRevert("Only bridge can call");
            mtManager.addUsers(CHANNEL_ID, testAddresses, testBalances);
        }

        // Verify bridge can still perform all operations
        vm.startPrank(bridge);
        mtManager.initializeChannel(999);
        mtManager.setAddressPair(999, address(999), address(1999));

        address[] memory finalAddresses = new address[](1);
        finalAddresses[0] = address(999);
        uint256[] memory finalBalances = new uint256[](1);
        finalBalances[0] = 999 ether;

        mtManager.addUsers(999, finalAddresses, finalBalances);
        vm.stopPrank();

        assertEq(mtManager.getBalance(999, address(999)), 999 ether);
    }
}
