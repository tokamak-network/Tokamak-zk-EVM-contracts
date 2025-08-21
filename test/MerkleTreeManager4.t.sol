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
            
            // Simple hash: input1 + input2 + input3 + input4
            let result := addmod(input1, input2, 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
            result := addmod(result, input3, 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
            result := addmod(result, input4, 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001)
            
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
    
    function testZeros() public {
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
}
