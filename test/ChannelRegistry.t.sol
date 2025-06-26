// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {ChannelRegistry} from "../src/ChannelRegistry.sol";
import {IChannelRegistry} from "../src/interface/IChannelRegistry.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";
import {BalanceMerkleTree} from "../src/libraries/BalanceMerkleTree.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";

import "forge-std/console.sol";

contract testChannelRegistry is Test {
    using BalanceMerkleTree for *;

    address owner;
    address leader;
    address participant1;
    address participant2;
    address participant3;
    ChannelRegistry channelRegistry;

    // Mock tokens for testing
    ERC20Mock token1;
    ERC20Mock token2;

    uint256 constant MIN_LEADER_BOND = 1 ether;
    uint256 constant MIN_PARTICIPANT_STAKE = 0.1 ether;

    function setUp() public virtual {
        owner = makeAddr("owner");
        leader = makeAddr("leader");
        participant1 = makeAddr("participant1");
        participant2 = makeAddr("participant2");
        participant3 = makeAddr("participant3");

        vm.startPrank(owner);
        channelRegistry = new ChannelRegistry();

        // Deploy mock tokens
        token1 = new ERC20Mock("Token1", "TK1");
        token2 = new ERC20Mock("Token2", "TK2");
        vm.stopPrank();

        // Fund accounts
        vm.deal(leader, 10 ether);
        vm.deal(participant1, 5 ether);
        vm.deal(participant2, 5 ether);
        vm.deal(participant3, 5 ether);

        // Mint some tokens for testing
        token1.mint(participant1, 1000 * 10 ** 18);
        token1.mint(participant2, 1000 * 10 ** 18);
        token2.mint(participant1, 1000 * 10 ** 18);
        token2.mint(participant2, 1000 * 10 ** 18);
    }

    function testLeaderBonding() public {
        vm.prank(leader);
        channelRegistry.bondAsLeader{value: MIN_LEADER_BOND}();

        IChannelRegistry.LeaderBond memory bond = channelRegistry.getLeaderBond(leader);
        assertEq(bond.amount, MIN_LEADER_BOND);
        assertGt(bond.bondedAt, 0);
    }

    function testCannotBondInsufficientAmount() public {
        vm.prank(leader);
        vm.expectRevert(IChannelRegistry.Channel__InsufficientLeaderBond.selector);
        channelRegistry.bondAsLeader{value: MIN_LEADER_BOND - 1}();
    }

    function testCreateChannelWithParams() public {
        // First, leader must bond
        vm.prank(leader);
        channelRegistry.bondAsLeader{value: MIN_LEADER_BOND}();

        // Create commitments for participants
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 commitment1 = keccak256(abi.encode(participant1, nonce1));
        bytes32 commitment2 = keccak256(abi.encode(participant2, nonce2));

        // Prepare channel creation parameters
        address[] memory participants = new address[](3);
        participants[0] = leader;
        participants[1] = participant1;
        participants[2] = participant2;

        bytes32[] memory commitments = new bytes32[](3);
        commitments[0] = keccak256(abi.encode(leader, keccak256("leader_nonce")));
        commitments[1] = commitment1;
        commitments[2] = commitment2;

        // Create initial balance root (empty tree)
        bytes32 initialBalanceRoot = bytes32(0);

        IChannelRegistry.ChannelCreationParams memory params = IChannelRegistry.ChannelCreationParams({
            leader: leader,
            preApprovedParticipants: participants,
            minimumStake: MIN_PARTICIPANT_STAKE,
            participantCommitments: commitments,
            signatureThreshold: 2,
            challengePeriod: 7 days,
            initialStateRoot: bytes32(0),
            initialBalanceRoot: initialBalanceRoot
        });

        // Add supported tokens
        address[] memory supportedTokens = new address[](2);
        supportedTokens[0] = address(token1);
        supportedTokens[1] = address(token2);

        vm.prank(leader);
        bytes32 channelId = channelRegistry.createChannelWithParams(params, supportedTokens);

        // Verify channel creation
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(channelId);
        assertEq(channelInfo.leader, leader);
        assertEq(channelInfo.participants.length, 3);
        assertEq(channelInfo.signatureThreshold, 2);
        assertEq(channelInfo.challengePeriod, 7 days);
        assertEq(uint256(channelInfo.status), uint256(IChannelRegistry.ChannelStatus.ACTIVE));

        // Verify participants are registered
        assertTrue(channelRegistry.isChannelParticipant(channelId, leader));
        assertTrue(channelRegistry.isChannelParticipant(channelId, participant1));
        assertTrue(channelRegistry.isChannelParticipant(channelId, participant2));

        // Verify supported tokens
        address[] memory tokens = channelRegistry.getSupportedTokens(channelId);
        assertEq(tokens.length, 3); // ETH + 2 tokens
        assertEq(tokens[0], address(0)); // ETH
        assertEq(tokens[1], address(token1));
        assertEq(tokens[2], address(token2));

        // Verify initial balance root
        assertEq(channelRegistry.getChannelBalanceRoot(channelId), initialBalanceRoot);
    }

    function testParticipantStaking() public {
        // Setup channel
        bytes32 channelId = _createTestChannel();

        // Participant1 stakes with correct commitment
        bytes32 nonce1 = keccak256("nonce1");
        vm.prank(participant1);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE}(channelId, nonce1);

        // Verify staking
        IChannelRegistry.ParticipantInfo memory participantInfo =
            channelRegistry.getParticipantInfo(channelId, participant1);
        assertEq(participantInfo.stake, MIN_PARTICIPANT_STAKE);
        assertTrue(participantInfo.isActive);
        assertFalse(participantInfo.hasExited);
    }

    function testDepositToken() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Approve and deposit token1
        uint256 depositAmount = 100 * 10 ** 18;
        vm.startPrank(participant1);
        token1.approve(address(channelRegistry), depositAmount);
        channelRegistry.depositToken(channelId, address(token1), depositAmount);
        vm.stopPrank();

        // Note: Individual balances are no longer tracked on-chain
        // Only total channel balance is tracked
        uint256 channelBalance = channelRegistry.getChannelTokenBalance(channelId, address(token1));
        assertEq(channelBalance, depositAmount);
    }

    function testDepositETH() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Deposit ETH
        uint256 depositAmount = 0.5 ether;
        vm.prank(participant1);
        channelRegistry.depositETH{value: depositAmount}(channelId);

        // Verify channel total balance
        uint256 channelBalance = channelRegistry.getChannelTokenBalance(channelId, address(0));
        assertEq(channelBalance, depositAmount);
    }

    function testUpdateBalanceRoot() public {
        bytes32 channelId = _createTestChannelWithStakes();
        
        // Set up verifier address
        vm.prank(owner);
        channelRegistry.setStateTransitionVerifier(address(this));
        
        // Create a new balance root
        bytes32 newBalanceRoot = keccak256("new balance root");
        
        // Update balance root (only verifier can do this)
        channelRegistry.updateBalanceRoot(channelId, newBalanceRoot);
        
        // Verify update
        assertEq(channelRegistry.getChannelBalanceRoot(channelId), newBalanceRoot);
    }

    function testWithdrawWithProof() public {
        bytes32 channelId = _createTestChannelWithStakes();
        
        // Deposit tokens first
        uint256 depositAmount = 100 * 10 ** 18;
        vm.startPrank(participant1);
        token1.approve(address(channelRegistry), depositAmount);
        channelRegistry.depositToken(channelId, address(token1), depositAmount);
        vm.stopPrank();
        
        // Set up verifier
        vm.prank(owner);
        channelRegistry.setStateTransitionVerifier(address(this));
        
        // Create balance data for Merkle tree
        uint256 participant1Balance = 60 * 10 ** 18;
        uint256 participant2Balance = 40 * 10 ** 18;
        
        // Create Merkle tree (off-chain computation)
        bytes32 leaf1 = keccak256(abi.encodePacked(participant1, address(token1), participant1Balance));
        bytes32 leaf2 = keccak256(abi.encodePacked(participant2, address(token1), participant2Balance));
        bytes32 root = _computeRoot(leaf1, leaf2);
        
        // Update balance root
        channelRegistry.updateBalanceRoot(channelId, root);
        
        // Change status to CLOSING
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);
        
        // Create Merkle proof for participant1
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;
        
        // Withdraw with proof
        uint256 balanceBefore = token1.balanceOf(participant1);
        
        vm.prank(participant1);
        channelRegistry.withdrawWithProof(channelId, address(token1), participant1Balance, proof);
        
        // Verify withdrawal
        uint256 balanceAfter = token1.balanceOf(participant1);
        assertEq(balanceAfter - balanceBefore, participant1Balance);
        
        // Verify cannot withdraw again
        vm.prank(participant1);
        vm.expectRevert("Already withdrawn");
        channelRegistry.withdrawWithProof(channelId, address(token1), participant1Balance, proof);
    }

    function testCannotExitActiveChannel() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Try to exit active channel - should fail
        vm.prank(participant1);
        vm.expectRevert("Can only exit during channel closure");
        channelRegistry.exitChannel(channelId);
    }

    function testExitDuringChannelClosure() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Leader changes status to CLOSING
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        // Now participant can exit
        uint256 balanceBefore = participant1.balance;
        vm.prank(participant1);
        channelRegistry.exitChannel(channelId);

        // Verify stake was returned
        uint256 balanceAfter = participant1.balance;
        assertEq(balanceAfter - balanceBefore, MIN_PARTICIPANT_STAKE);

        // Verify participant status
        IChannelRegistry.ParticipantInfo memory participantInfo =
            channelRegistry.getParticipantInfo(channelId, participant1);
        assertFalse(participantInfo.isActive);
        assertTrue(participantInfo.hasExited);
        assertEq(participantInfo.stake, 0);
    }

    function testDeprecatedFunctions() public {
        bytes32 channelId = _createTestChannelWithStakes();
        
        // Test deprecated getParticipantTokenBalance - should return 0
        uint256 balance = channelRegistry.getParticipantTokenBalance(channelId, participant1, address(token1));
        assertEq(balance, 0);
        
        // Test deprecated getParticipantAllBalances - should return empty array
        IChannelRegistry.TokenDeposit[] memory balances = 
            channelRegistry.getParticipantAllBalances(channelId, participant1);
        assertEq(balances.length, 0);
    }

    // Helper functions
    function _createTestChannel() internal returns (bytes32) {
        // Leader bonds first
        vm.prank(leader);
        channelRegistry.bondAsLeader{value: MIN_LEADER_BOND}();

        // Create commitments
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 leaderNonce = keccak256("leader_nonce");

        address[] memory participants = new address[](3);
        participants[0] = leader;
        participants[1] = participant1;
        participants[2] = participant2;

        bytes32[] memory commitments = new bytes32[](3);
        commitments[0] = keccak256(abi.encode(leader, leaderNonce));
        commitments[1] = keccak256(abi.encode(participant1, nonce1));
        commitments[2] = keccak256(abi.encode(participant2, nonce2));

        IChannelRegistry.ChannelCreationParams memory params = IChannelRegistry.ChannelCreationParams({
            leader: leader,
            preApprovedParticipants: participants,
            minimumStake: MIN_PARTICIPANT_STAKE,
            participantCommitments: commitments,
            signatureThreshold: 2,
            challengePeriod: 7 days,
            initialStateRoot: bytes32(0),
            initialBalanceRoot: bytes32(0)
        });

        // Add supported tokens
        address[] memory supportedTokens = new address[](2);
        supportedTokens[0] = address(token1);
        supportedTokens[1] = address(token2);

        vm.prank(leader);
        return channelRegistry.createChannelWithParams(params, supportedTokens);
    }

    function _createTestChannelWithStakes() internal returns (bytes32) {
        bytes32 channelId = _createTestChannel();

        // All participants stake
        vm.prank(leader);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE}(channelId, keccak256("leader_nonce"));

        vm.prank(participant1);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE}(channelId, keccak256("nonce1"));

        vm.prank(participant2);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE}(channelId, keccak256("nonce2"));

        return channelId;
    }
    
    function _computeRoot(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}