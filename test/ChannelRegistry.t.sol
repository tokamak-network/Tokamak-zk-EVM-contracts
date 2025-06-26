// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {ChannelRegistry} from "../src/ChannelRegistry.sol";
import {IChannelRegistry} from "../src/interface/IChannelRegistry.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";

import "forge-std/console.sol";

contract testChannelRegistry is Test {
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

        IChannelRegistry.ChannelCreationParams memory params = IChannelRegistry.ChannelCreationParams({
            leader: leader,
            preApprovedParticipants: participants,
            minimumStake: MIN_PARTICIPANT_STAKE,
            participantCommitments: commitments,
            signatureThreshold: 2,
            challengePeriod: 7 days,
            initialStateRoot: bytes32(0)
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
        assertEq(channelRegistry.getChannelStateRoot(channelId), bytes32(0));
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

    function testUpdateStateRoot() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Set up verifier address
        vm.prank(owner);
        channelRegistry.setStateTransitionVerifier(address(this));

        // Create a new balance root
        bytes32 newStateRoot = keccak256("new state root");

        // Update balance root (only verifier can do this)
        channelRegistry.updateStateRoot(channelId, newStateRoot);

        // Verify update
        assertEq(channelRegistry.getChannelStateRoot(channelId), newStateRoot);
    }

    function testWithdrawWithProofAccountBased() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Deposit tokens first
        uint256 depositAmount = 100 * 10 ** 18;
        vm.startPrank(participant1);
        token1.approve(address(channelRegistry), depositAmount);
        channelRegistry.depositToken(channelId, address(token1), depositAmount);
        token2.approve(address(channelRegistry), 50 * 10 ** 18);
        channelRegistry.depositToken(channelId, address(token2), 50 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(participant2);
        token1.approve(address(channelRegistry), 40 * 10 ** 18);
        channelRegistry.depositToken(channelId, address(token1), 40 * 10 ** 18);
        vm.stopPrank();

        // Set up verifier
        vm.prank(owner);
        channelRegistry.setStateTransitionVerifier(address(this));

        // Create account states for Merkle tree
        // Participant1 has multiple tokens
        IChannelRegistry.TokenBalance[] memory p1Balances = new IChannelRegistry.TokenBalance[](3);
        p1Balances[0] = IChannelRegistry.TokenBalance({
            token: address(0), // ETH
            amount: 0.2 ether
        });
        p1Balances[1] = IChannelRegistry.TokenBalance({
            token: address(token1),
            amount: 60 * 10 ** 18
        });
        p1Balances[2] = IChannelRegistry.TokenBalance({
            token: address(token2),
            amount: 50 * 10 ** 18
        });

        // Participant2 has only one token
        IChannelRegistry.TokenBalance[] memory p2Balances = new IChannelRegistry.TokenBalance[](1);
        p2Balances[0] = IChannelRegistry.TokenBalance({
            token: address(token1),
            amount: 40 * 10 ** 18
        });

        // Create leaves - one per account
        bytes32 leaf1 = keccak256(abi.encode(participant1, p1Balances));
        bytes32 leaf2 = keccak256(abi.encode(participant2, p2Balances));
        
        // Simple 2-participant tree
        bytes32 root = _computeRoot(leaf1, leaf2);

        // Update state root
        channelRegistry.updateStateRoot(channelId, root);

        // Change status to CLOSING
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        // Create Merkle proof for participant1
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;

        // Withdraw token1 with proof - must provide all balances
        uint256 balanceBefore = token1.balanceOf(participant1);

        vm.prank(participant1);
        channelRegistry.withdrawWithProof(
            channelId, 
            address(token1), 
            60 * 10 ** 18, 
            p1Balances,
            proof
        );

        // Verify withdrawal
        uint256 balanceAfter = token1.balanceOf(participant1);
        assertEq(balanceAfter - balanceBefore, 60 * 10 ** 18);

        // Verify cannot withdraw same token again
        vm.prank(participant1);
        vm.expectRevert("Already withdrawn");
        channelRegistry.withdrawWithProof(
            channelId,
            address(token1),
            60 * 10 ** 18,
            p1Balances,
            proof
        );

        // But can withdraw different token
        uint256 token2BalanceBefore = token2.balanceOf(participant1);
        
        vm.prank(participant1);
        channelRegistry.withdrawWithProof(
            channelId,
            address(token2),
            50 * 10 ** 18,
            p1Balances,
            proof
        );

        uint256 token2BalanceAfter = token2.balanceOf(participant1);
        assertEq(token2BalanceAfter - token2BalanceBefore, 50 * 10 ** 18);
    }

    function testCannotWithdrawWithWrongBalances() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Deposit tokens
        uint256 depositAmount = 100 * 10 ** 18;
        vm.startPrank(participant1);
        token1.approve(address(channelRegistry), depositAmount);
        channelRegistry.depositToken(channelId, address(token1), depositAmount);
        vm.stopPrank();

        // Set up verifier
        vm.prank(owner);
        channelRegistry.setStateTransitionVerifier(address(this));

        // Create correct account state
        IChannelRegistry.TokenBalance[] memory correctBalances = new IChannelRegistry.TokenBalance[](1);
        correctBalances[0] = IChannelRegistry.TokenBalance({
            token: address(token1),
            amount: 100 * 10 ** 18
        });

        // Create wrong account state (trying to claim more)
        IChannelRegistry.TokenBalance[] memory wrongBalances = new IChannelRegistry.TokenBalance[](1);
        wrongBalances[0] = IChannelRegistry.TokenBalance({
            token: address(token1),
            amount: 200 * 10 ** 18
        });

        // Create leaves
        bytes32 correctLeaf = keccak256(abi.encode(participant1, correctBalances));
        bytes32 participant2Leaf = keccak256(abi.encode(participant2, new IChannelRegistry.TokenBalance[](0)));
        
        bytes32 root = _computeRoot(correctLeaf, participant2Leaf);
        channelRegistry.updateStateRoot(channelId, root);

        // Change to CLOSING
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        // Try to withdraw with wrong balances
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = participant2Leaf;

        vm.prank(participant1);
        vm.expectRevert("Invalid balance proof");
        channelRegistry.withdrawWithProof(
            channelId,
            address(token1),
            200 * 10 ** 18,
            wrongBalances, // Wrong balances array
            proof
        );
    }

    function testWithdrawWithMismatchedAmount() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Setup and deposits...
        uint256 depositAmount = 100 * 10 ** 18;
        vm.startPrank(participant1);
        token1.approve(address(channelRegistry), depositAmount);
        channelRegistry.depositToken(channelId, address(token1), depositAmount);
        vm.stopPrank();

        vm.prank(owner);
        channelRegistry.setStateTransitionVerifier(address(this));

        // Create account state
        IChannelRegistry.TokenBalance[] memory balances = new IChannelRegistry.TokenBalance[](1);
        balances[0] = IChannelRegistry.TokenBalance({
            token: address(token1),
            amount: 100 * 10 ** 18
        });

        bytes32 leaf1 = keccak256(abi.encode(participant1, balances));
        bytes32 leaf2 = keccak256(abi.encode(participant2, new IChannelRegistry.TokenBalance[](0)));
        bytes32 root = _computeRoot(leaf1, leaf2);
        
        channelRegistry.updateStateRoot(channelId, root);

        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;

        // Try to withdraw different amount than in balances array
        vm.prank(participant1);
        vm.expectRevert("Amount mismatch");
        channelRegistry.withdrawWithProof(
            channelId,
            address(token1),
            50 * 10 ** 18, // Different from balances array
            balances,
            proof
        );
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
            initialStateRoot: bytes32(0)
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