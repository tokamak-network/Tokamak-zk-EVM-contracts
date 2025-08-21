// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {MerkleTreeManager4} from "../src/merkleTree/MerkleTreeManager4.sol";
import {IPoseidon4Yul} from "../src/interface/IPoseidon4Yul.sol";
import {Field} from "@poseidon/Field.sol";

contract MockPoseidon4Yul is IPoseidon4Yul {
    // Mock implementation for testing - returns a simple hash of the inputs
    fallback() external {
        assembly {
            let input1 := calldataload(0)
            let input2 := calldataload(0x20)
            let input3 := calldataload(0x40)
            let input4 := calldataload(0x60)
            
            // Simple hash: input1 + input2 + input3 + input4 + 1 (to avoid zero)
            let result := addmod(input1, input2, 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
            result := addmod(result, input3, 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
            result := addmod(result, input4, 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
            result := addmod(result, 1, 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
            
            mstore(0, result)
            return(0, 32)
        }
    }
}

contract MerkleTreeManager4Test is Test {
    MerkleTreeManager4 public merkleTree;
    MockPoseidon4Yul public mockPoseidon;
    
    address public bridge = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);
    address public user3 = address(0xABC);
    
    uint256 public channelId = 1;
    
    function setUp() public {
        mockPoseidon = new MockPoseidon4Yul();
        merkleTree = new MerkleTreeManager4(address(mockPoseidon), 4); // 4 levels deep
        
        // Set bridge
        merkleTree.setBridge(bridge);
        
        // Initialize channel
        vm.prank(bridge);
        merkleTree.initializeChannel(channelId);
        
        // Set address pairs
        vm.prank(bridge);
        merkleTree.setAddressPair(channelId, user1, address(0x111));
        vm.prank(bridge);
        merkleTree.setAddressPair(channelId, user2, address(0x222));
        vm.prank(bridge);
        merkleTree.setAddressPair(channelId, user3, address(0x333));
    }
    
    function testConstructor() public {
        assertEq(address(merkleTree.poseidonHasher()), address(mockPoseidon));
        assertEq(merkleTree.depth(), 4);
        assertEq(merkleTree.bridge(), bridge);
        assertTrue(merkleTree.bridgeSet());
    }
    
    function testInitializeChannel() public {
        uint256 newChannelId = 2;
        
        vm.prank(bridge);
        merkleTree.initializeChannel(newChannelId);
        
        assertTrue(merkleTree.channelInitialized(newChannelId));
        assertEq(merkleTree.getLatestRoot(newChannelId), merkleTree.zeros(4));
    }
    
    function testAddUsers() public {
        address[] memory l1Addresses = new address[](3);
        l1Addresses[0] = user1;
        l1Addresses[1] = user2;
        l1Addresses[2] = user3;
        
        uint256[] memory balances = new uint256[](3);
        balances[0] = 100;
        balances[1] = 200;
        balances[2] = 300;
        
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses, balances);
        
        assertEq(merkleTree.getBalance(channelId, user1), 100);
        assertEq(merkleTree.getBalance(channelId, user2), 200);
        assertEq(merkleTree.getBalance(channelId, user3), 300);
        
        assertEq(merkleTree.nextLeafIndex(channelId), 3);
        assertEq(merkleTree.getRootSequenceLength(channelId), 4); // Initial + 3 users
    }
    
    function testHashFour() public {
        bytes32 a = bytes32(uint256(1));
        bytes32 b = bytes32(uint256(2));
        bytes32 c = bytes32(uint256(3));
        bytes32 d = bytes32(uint256(4));
        
        bytes32 result = merkleTree.hashFour(a, b, c, d);
        
        // Should not be zero
        assertTrue(result != bytes32(0));
    }
    
    function testVerifyProof() public {
        // Add users first
        address[] memory l1Addresses = new address[](1);
        l1Addresses[0] = user1;
        
        uint256[] memory balances = new uint256[](1);
        balances[0] = 100;
        
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses, balances);
        
        bytes32 leaf = merkleTree.computeLeafForVerification(
            address(0x111), 
            100, 
            bytes32(0)
        );
        
        bytes32 root = merkleTree.getLatestRoot(channelId);
        
        // For a single leaf, proof should be empty
        bytes32[] memory proof = new bytes32[](0);
        
        bool isValid = merkleTree.verifyProof(channelId, proof, leaf, 0, root);
        assertTrue(isValid);
    }
    
    function testZeros() public view {
        bytes32 zero0 = merkleTree.zeros(0);
        bytes32 zero1 = merkleTree.zeros(1);
        bytes32 zero2 = merkleTree.zeros(2);
        
        assertTrue(zero0 != bytes32(0));
        assertTrue(zero1 != bytes32(0));
        assertTrue(zero2 != bytes32(0));
        assertTrue(zero0 != zero1);
        assertTrue(zero1 != zero2);
    }
    
    function testDepthLimits() public {
        // Test minimum depth
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.DepthTooSmall.selector, 0));
        new MerkleTreeManager4(address(mockPoseidon), 0);
        
        // Test maximum depth (should be < 16 for quaternary trees)
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.DepthTooLarge.selector, 16));
        new MerkleTreeManager4(address(mockPoseidon), 16);
    }
    
    function testOnlyBridgeModifier() public {
        address nonBridge = address(0x999);
        
        vm.expectRevert("Only bridge can call");
        vm.prank(nonBridge);
        merkleTree.initializeChannel(5);
        
        vm.expectRevert("Only bridge can call");
        vm.prank(nonBridge);
        merkleTree.setAddressPair(channelId, address(0x444), address(0x555));
        
        vm.expectRevert("Only bridge can call");
        vm.prank(nonBridge);
        address[] memory l1Addresses = new address[](1);
        uint256[] memory balances = new uint256[](1);
        l1Addresses[0] = address(0x444);
        balances[0] = 100;
        merkleTree.addUsers(channelId, l1Addresses, balances);
    }
    
    function testChannelNotInitialized() public {
        uint256 uninitializedChannel = 999;
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ChannelNotInitialized.selector, uninitializedChannel));
        merkleTree.getLatestRoot(uninitializedChannel);
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ChannelNotInitialized.selector, uninitializedChannel));
        merkleTree.isKnownRoot(uninitializedChannel, bytes32(0));
    }
    
    function testGetUserAddresses() public {
        address[] memory l1Addresses = new address[](2);
        l1Addresses[0] = user1;
        l1Addresses[1] = user2;
        
        uint256[] memory balances = new uint256[](2);
        balances[0] = 100;
        balances[1] = 200;
        
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses, balances);
        
        (address[] memory retrievedL1, address[] memory retrievedL2) = merkleTree.getUserAddresses(channelId);
        
        assertEq(retrievedL1.length, 2);
        assertEq(retrievedL2.length, 2);
        assertEq(retrievedL1[0], user1);
        assertEq(retrievedL1[1], user2);
        assertEq(retrievedL2[0], address(0x111));
        assertEq(retrievedL2[1], address(0x222));
    }

    // ============ EDGE CASES AND ADDITIONAL TESTS ============

    function testSetBridgeEdgeCases() public {
        // Test setting bridge twice
        vm.expectRevert("Bridge already set");
        merkleTree.setBridge(address(0x999));
        
        // Test only owner can set bridge
        vm.prank(address(0x999));
        vm.expectRevert();
        merkleTree.setBridge(address(0x888));
        
        // Test setting bridge to zero address (should fail before bridge already set check)
        // We need to create a new instance for this test
        MerkleTreeManager4 newTree = new MerkleTreeManager4(address(mockPoseidon), 4);
        vm.expectRevert("Invalid bridge address");
        newTree.setBridge(address(0));
    }

    function testInitializeChannelEdgeCases() public {
        // Test initializing same channel twice
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ChannelAlreadyInitialized.selector, channelId));
        vm.prank(bridge);
        merkleTree.initializeChannel(channelId);
        
        // Test initializing channel 0
        vm.prank(bridge);
        merkleTree.initializeChannel(0);
        assertTrue(merkleTree.channelInitialized(0));
    }

    function testSetAddressPairEdgeCases() public {
        // Test setting address pair for uninitialized channel
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ChannelNotInitialized.selector, 999));
        vm.prank(bridge);
        merkleTree.setAddressPair(999, address(0x444), address(0x555));
        
        // Test setting address pair to zero address
        vm.prank(bridge);
        merkleTree.setAddressPair(channelId, address(0x444), address(0));
        assertEq(merkleTree.getL2Address(channelId, address(0x444)), address(0));
    }

    function testAddUsersEdgeCases() public {
        // Test adding users with mismatched array lengths
        address[] memory l1Addresses = new address[](2);
        uint256[] memory balances = new uint256[](1);
        l1Addresses[0] = user1;
        l1Addresses[1] = user2;
        balances[0] = 100;
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.LengthMismatch.selector));
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses, balances);
        
        // Test adding users to uninitialized channel
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ChannelNotInitialized.selector, 999));
        vm.prank(bridge);
        merkleTree.addUsers(999, l1Addresses, balances);
        
        // Test adding users when L2 address not set
        address[] memory l1Addresses2 = new address[](1);
        uint256[] memory balances2 = new uint256[](1);
        l1Addresses2[0] = address(0x444);
        balances2[0] = 100;
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.L2AddressNotSet.selector));
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses2, balances2);
        
        // Test adding users twice to same channel
        address[] memory l1Addresses3 = new address[](1);
        uint256[] memory balances3 = new uint256[](1);
        l1Addresses3[0] = user1;
        balances3[0] = 100;
        
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses3, balances3);
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.UsersAlreadyAdded.selector, channelId));
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses3, balances3);
    }

    function testHashFourEdgeCases() public {
        // Test with zero values
        bytes32 result1 = merkleTree.hashFour(bytes32(0), bytes32(0), bytes32(0), bytes32(0));
        assertTrue(result1 != bytes32(0));
        
        // Test with maximum field values
        bytes32 maxValue = bytes32(0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000);
        bytes32 result2 = merkleTree.hashFour(maxValue, maxValue, maxValue, maxValue);
        assertTrue(result2 != bytes32(0));
        
        // Test with values just below field size
        bytes32 nearMax = bytes32(0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000);
        bytes32 result3 = merkleTree.hashFour(nearMax, nearMax, nearMax, nearMax);
        assertTrue(result3 != bytes32(0));
        
        // Test with different values to ensure variety
        bytes32 result4 = merkleTree.hashFour(bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)), bytes32(uint256(4)));
        assertTrue(result4 != bytes32(0));
        assertTrue(result4 != result1);
    }

    function testHashFourValueOutOfRange() public {
        // Test with values above field size
        bytes32 aboveField = bytes32(0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000002);
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ValueOutOfRange.selector, aboveField));
        merkleTree.hashFour(aboveField, bytes32(uint256(1)), bytes32(uint256(1)), bytes32(uint256(1)));
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ValueOutOfRange.selector, aboveField));
        merkleTree.hashFour(bytes32(uint256(1)), aboveField, bytes32(uint256(1)), bytes32(uint256(1)));
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ValueOutOfRange.selector, aboveField));
        merkleTree.hashFour(bytes32(uint256(1)), bytes32(uint256(1)), aboveField, bytes32(uint256(1)));
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.ValueOutOfRange.selector, aboveField));
        merkleTree.hashFour(bytes32(uint256(1)), bytes32(uint256(1)), bytes32(uint256(1)), aboveField);
    }

    function testComputeLeafForVerification() public {
        // Test with zero balance
        bytes32 leaf1 = merkleTree.computeLeafForVerification(address(0x111), 0, bytes32(0));
        assertTrue(leaf1 != bytes32(0));
        
        // Test with large balance
        bytes32 leaf2 = merkleTree.computeLeafForVerification(address(0x111), type(uint256).max, bytes32(0));
        assertTrue(leaf2 != bytes32(0));
        
        // Test with different prevRoot values
        bytes32 leaf3 = merkleTree.computeLeafForVerification(address(0x111), 100, bytes32(uint256(123)));
        assertTrue(leaf3 != bytes32(0));
        assertTrue(leaf3 != leaf1);
    }

    function testVerifyProofEdgeCases() public {
        // Add multiple users to test proof verification
        address[] memory l1Addresses = new address[](4);
        uint256[] memory balances = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            l1Addresses[i] = address(uint160(0x1000 + i));
            balances[i] = 100 + i;
            vm.prank(bridge);
            merkleTree.setAddressPair(channelId, l1Addresses[i], address(uint160(0x2000 + i)));
        }
        
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses, balances);
        
        // Test verification with wrong leaf
        bytes32 wrongLeaf = bytes32(uint256(0x123));
        bytes32 root = merkleTree.getLatestRoot(channelId);
        bytes32[] memory proof = new bytes32[](0);
        
        bool isValid = merkleTree.verifyProof(channelId, proof, wrongLeaf, 0, root);
        assertFalse(isValid);
        
        // Test verification with wrong root
        bytes32 correctLeaf = merkleTree.computeLeafForVerification(address(0x1000), 100, bytes32(0));
        bytes32 wrongRoot = bytes32(uint256(0x456));
        
        bool isValid2 = merkleTree.verifyProof(channelId, proof, correctLeaf, 0, wrongRoot);
        assertFalse(isValid2);
    }

    function testMerkleTreeFull() public {
        // Create a tree with depth 1 (supports only 4 leaves)
        MerkleTreeManager4 smallTree = new MerkleTreeManager4(address(mockPoseidon), 1);
        smallTree.setBridge(bridge);
        
        vm.prank(bridge);
        smallTree.initializeChannel(999);
        
        // Set address pairs for 5 users (more than the tree can hold)
        address[] memory l1Addresses = new address[](5);
        uint256[] memory balances = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            l1Addresses[i] = address(uint160(0x1000 + i));
            balances[i] = 100 + i;
            vm.prank(bridge);
            smallTree.setAddressPair(999, l1Addresses[i], address(uint160(0x2000 + i)));
        }
        
        // Try to add 5 users to a depth-1 tree (should fail with MerkleTreeFull)
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.MerkleTreeFull.selector, 4));
        vm.prank(bridge);
        smallTree.addUsers(999, l1Addresses, balances);
    }

    function testZerosEdgeCases() public {
        // Test zeros function with valid depths
        for (uint256 i = 0; i <= 15; i++) {
            bytes32 zero = merkleTree.zeros(i);
            assertTrue(zero != bytes32(0));
        }
        
        // Test zeros function with invalid depth
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.IndexOutOfBounds.selector, 16));
        merkleTree.zeros(16);
        
        vm.expectRevert(abi.encodeWithSelector(MerkleTreeManager4.IndexOutOfBounds.selector, 100));
        merkleTree.zeros(100);
    }

    function testRootHistoryAndSequence() public {
        // Add users to generate root history
        address[] memory l1Addresses = new address[](5);
        uint256[] memory balances = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            l1Addresses[i] = address(uint160(0x1000 + i));
            balances[i] = 100 + i;
            vm.prank(bridge);
            merkleTree.setAddressPair(channelId, l1Addresses[i], address(uint160(0x2000 + i)));
        }
        
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses, balances);
        
        // Test root sequence functions
        assertEq(merkleTree.getRootSequenceLength(channelId), 6); // Initial + 5 users
        assertEq(merkleTree.getLastRootInSequence(channelId), merkleTree.getLatestRoot(channelId));
        
        // Test getting root at specific index
        bytes32 rootAtIndex = merkleTree.getRootAtIndex(channelId, 0);
        assertEq(rootAtIndex, bytes32(0)); // Initial root is BALANCE_SLOT (0)
        
        // Test getting root at invalid index
        vm.expectRevert("Index out of bounds");
        merkleTree.getRootAtIndex(channelId, 10);
    }

    function testIsKnownRoot() public {
        // Test with zero root
        assertFalse(merkleTree.isKnownRoot(channelId, bytes32(0)));
        
        // Test with current root
        bytes32 currentRoot = merkleTree.getLatestRoot(channelId);
        assertTrue(merkleTree.isKnownRoot(channelId, currentRoot));
        
        // Test with unknown root
        bytes32 unknownRoot = bytes32(uint256(0x123));
        assertFalse(merkleTree.isKnownRoot(channelId, unknownRoot));
    }

    function testGetBalanceEdgeCases() public {
        // Test getting balance for non-existent user
        uint256 balance = merkleTree.getBalance(channelId, address(0x999));
        assertEq(balance, 0);
        
        // Test getting balance for user with zero balance
        address[] memory l1Addresses = new address[](1);
        uint256[] memory balances = new uint256[](1);
        l1Addresses[0] = address(0x444);
        balances[0] = 0;
        
        vm.prank(bridge);
        merkleTree.setAddressPair(channelId, address(0x444), address(0x444));
        vm.prank(bridge);
        merkleTree.addUsers(channelId, l1Addresses, balances);
        
        uint256 zeroBalance = merkleTree.getBalance(channelId, address(0x444));
        assertEq(zeroBalance, 0);
    }

    function testHashLeftRight() public {
        // Test the hashLeftRight function (interface compatibility)
        bytes32 left = bytes32(uint256(1));
        bytes32 right = bytes32(uint256(2));
        
        bytes32 result = merkleTree.hashLeftRight(left, right);
        assertTrue(result != bytes32(0));
        
        // Test that it's equivalent to hashFour with zeros
        bytes32 expected = merkleTree.hashFour(left, right, bytes32(0), bytes32(0));
        assertEq(result, expected);
    }

    function testFuzzAddUsers(uint256[5] memory balances) public {
        // Fuzz test for adding users with random balances
        vm.assume(balances[0] > 0 && balances[1] > 0 && balances[2] > 0 && balances[3] > 0 && balances[4] > 0);
        vm.assume(balances[0] < type(uint256).max / 2);
        vm.assume(balances[1] < type(uint256).max / 2);
        vm.assume(balances[2] < type(uint256).max / 2);
        vm.assume(balances[3] < type(uint256).max / 2);
        vm.assume(balances[4] < type(uint256).max / 2);
        
        vm.prank(bridge);
        merkleTree.initializeChannel(channelId + 100);
        
        address[] memory l1Addresses = new address[](5);
        uint256[] memory balanceArray = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            l1Addresses[i] = address(uint160(0x1000 + i));
            balanceArray[i] = balances[i];
            vm.prank(bridge);
            merkleTree.setAddressPair(channelId + 100, l1Addresses[i], address(uint160(0x2000 + i)));
        }
        
        vm.prank(bridge);
        merkleTree.addUsers(channelId + 100, l1Addresses, balanceArray);
        
        // Verify all users were added
        for (uint256 i = 0; i < 5; i++) {
            assertEq(merkleTree.getBalance(channelId + 100, l1Addresses[i]), balanceArray[i]);
        }
    }

    function testFuzzHashFour(uint256[4] memory inputs) public {
        // Fuzz test for hashFour function
        vm.assume(inputs[0] < 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001);
        vm.assume(inputs[1] < 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001);
        vm.assume(inputs[2] < 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001);
        vm.assume(inputs[3] < 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001);
        
        bytes32 a = bytes32(inputs[0]);
        bytes32 b = bytes32(inputs[1]);
        bytes32 c = bytes32(inputs[2]);
        bytes32 d = bytes32(inputs[3]);
        
        bytes32 result = merkleTree.hashFour(a, b, c, d);
        assertTrue(result != bytes32(0));
    }
}
