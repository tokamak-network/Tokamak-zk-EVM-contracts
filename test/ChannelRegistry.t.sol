// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {ChannelRegistry} from "../src/ChannelRegistry.sol";
import {IChannelRegistry} from "../src/interface/IChannelRegistry.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";

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
    }

    function testCreateChannelWithNoExtraTokens() public {
        // Test creating a channel with only ETH support (empty token array)
        vm.prank(leader);
        channelRegistry.bondAsLeader{value: MIN_LEADER_BOND}();

        address[] memory participants = new address[](1);
        participants[0] = leader;

        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = keccak256(abi.encode(leader, keccak256("leader_nonce")));

        IChannelRegistry.ChannelCreationParams memory params = IChannelRegistry.ChannelCreationParams({
            leader: leader,
            preApprovedParticipants: participants,
            minimumStake: MIN_PARTICIPANT_STAKE,
            participantCommitments: commitments,
            signatureThreshold: 1,
            challengePeriod: 7 days,
            initialStateRoot: bytes32(0)
        });

        address[] memory supportedTokens = new address[](0); // Empty array

        vm.prank(leader);
        bytes32 channelId = channelRegistry.createChannelWithParams(params, supportedTokens);

        // Verify only ETH is supported
        address[] memory tokens = channelRegistry.getSupportedTokens(channelId);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(0)); // Only ETH
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

        // Verify deposit
        uint256 balance = channelRegistry.getParticipantTokenBalance(channelId, participant1, address(token1));
        assertEq(balance, depositAmount);

        // Verify channel total balance
        uint256 channelBalance = channelRegistry.getChannelTokenBalance(channelId, address(token1));
        assertEq(channelBalance, depositAmount);
    }

    function testDepositETH() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Deposit ETH
        uint256 depositAmount = 0.5 ether;
        vm.prank(participant1);
        channelRegistry.depositETH{value: depositAmount}(channelId);

        // Verify deposit
        uint256 balance = channelRegistry.getParticipantTokenBalance(channelId, participant1, address(0));
        assertEq(balance, depositAmount);
    }

    function testCannotDepositUnsupportedToken() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Create a new token that wasn't added during channel creation
        ERC20Mock unsupportedToken = new ERC20Mock("Unsupported", "UNS");
        unsupportedToken.mint(participant1, 1000 * 10 ** 18);

        // Try to deposit unsupported token
        vm.startPrank(participant1);
        unsupportedToken.approve(address(channelRegistry), 100 * 10 ** 18);
        vm.expectRevert("Token not supported");
        channelRegistry.depositToken(channelId, address(unsupportedToken), 100 * 10 ** 18);
        vm.stopPrank();
    }

    function testWithdrawTokensDuringClosure() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Deposit some tokens first
        uint256 depositAmount = 100 * 10 ** 18;
        vm.startPrank(participant1);
        token1.approve(address(channelRegistry), depositAmount);
        channelRegistry.depositToken(channelId, address(token1), depositAmount);
        vm.stopPrank();

        // Change status to CLOSING
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        // Withdraw tokens
        uint256 withdrawAmount = 50 * 10 ** 18;
        uint256 balanceBefore = token1.balanceOf(participant1);

        vm.prank(participant1);
        channelRegistry.withdrawTokens(channelId, address(token1), withdrawAmount);

        // Verify withdrawal
        uint256 balanceAfter = token1.balanceOf(participant1);
        assertEq(balanceAfter - balanceBefore, withdrawAmount);

        // Verify remaining balance
        uint256 remainingBalance = channelRegistry.getParticipantTokenBalance(channelId, participant1, address(token1));
        assertEq(remainingBalance, depositAmount - withdrawAmount);
    }

    function testCannotStakeWithWrongCommitment() public {
        bytes32 channelId = _createTestChannel();

        // Try to stake with wrong nonce
        bytes32 wrongNonce = keccak256("wrong_nonce");
        vm.prank(participant1);
        vm.expectRevert(IChannelRegistry.Channel__InvalidCommitment.selector);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE}(channelId, wrongNonce);
    }

    function testCannotStakeInsufficientAmount() public {
        bytes32 channelId = _createTestChannel();

        bytes32 nonce1 = keccak256("nonce1");
        vm.prank(participant1);
        vm.expectRevert(IChannelRegistry.Channel__InsufficientParticipantStake.selector);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE - 1}(channelId, nonce1);
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

    function testCannotCreateChannelWithoutBond() public {
        address[] memory participants = new address[](1);
        participants[0] = leader;

        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = keccak256(abi.encode(leader, keccak256("nonce")));

        IChannelRegistry.ChannelCreationParams memory params = IChannelRegistry.ChannelCreationParams({
            leader: leader,
            preApprovedParticipants: participants,
            minimumStake: MIN_PARTICIPANT_STAKE,
            participantCommitments: commitments,
            signatureThreshold: 1,
            challengePeriod: 7 days,
            initialStateRoot: bytes32(0)
        });

        address[] memory supportedTokens = new address[](0);

        vm.prank(leader);
        vm.expectRevert(IChannelRegistry.Channel__InsufficientLeaderBond.selector);
        channelRegistry.createChannelWithParams(params, supportedTokens);
    }

    function testCannotCreateChannelWithDuplicateParticipants() public {
        vm.prank(leader);
        channelRegistry.bondAsLeader{value: MIN_LEADER_BOND}();

        address[] memory participants = new address[](2);
        participants[0] = participant1;
        participants[1] = participant1; // Duplicate

        bytes32[] memory commitments = new bytes32[](2);
        commitments[0] = keccak256(abi.encode(participant1, keccak256("nonce1")));
        commitments[1] = keccak256(abi.encode(participant1, keccak256("nonce2")));

        IChannelRegistry.ChannelCreationParams memory params = IChannelRegistry.ChannelCreationParams({
            leader: leader,
            preApprovedParticipants: participants,
            minimumStake: MIN_PARTICIPANT_STAKE,
            participantCommitments: commitments,
            signatureThreshold: 1,
            challengePeriod: 7 days,
            initialStateRoot: bytes32(0)
        });

        address[] memory supportedTokens = new address[](0);

        vm.prank(leader);
        vm.expectRevert(IChannelRegistry.Channel__DuplicateParticipant.selector);
        channelRegistry.createChannelWithParams(params, supportedTokens);
    }

    function testTransferLeadership() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // participant2 bonds to become eligible for leadership
        vm.prank(participant2);
        channelRegistry.bondAsLeader{value: MIN_LEADER_BOND}();

        // Transfer leadership
        vm.prank(leader);
        channelRegistry.transferLeadership(channelId, participant2);

        // Verify leadership transfer
        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(channelId);
        assertEq(channelInfo.leader, participant2);
    }

    function testCannotTransferLeadershipWithoutBond() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Try to transfer to unbonded participant
        vm.prank(leader);
        vm.expectRevert(IChannelRegistry.Channel__InsufficientLeaderBond.selector);
        channelRegistry.transferLeadership(channelId, participant2);
    }

    function testLegacyCreateChannelReverts() public {
        vm.prank(owner);
        vm.expectRevert("Use createChannelWithParams instead");
        channelRegistry.createChannel(leader);
    }

    function testGetActiveParticipantCount() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // All participants should be active initially
        assertEq(channelRegistry.getActiveParticipantCount(channelId), 3);

        // Change to closing status and have one participant exit
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        vm.prank(participant1);
        channelRegistry.exitChannel(channelId);

        // Should have 2 active participants now
        assertEq(channelRegistry.getActiveParticipantCount(channelId), 2);
    }

    function testGetParticipantAllBalances() public {
        bytes32 channelId = _createTestChannelWithStakes();

        // Deposit various tokens
        uint256 ethAmount = 0.5 ether;
        uint256 token1Amount = 100 * 10 ** 18;
        uint256 token2Amount = 200 * 10 ** 18;

        vm.startPrank(participant1);

        // Deposit ETH
        channelRegistry.depositETH{value: ethAmount}(channelId);

        // Deposit token1
        token1.approve(address(channelRegistry), token1Amount);
        channelRegistry.depositToken(channelId, address(token1), token1Amount);

        // Deposit token2
        token2.approve(address(channelRegistry), token2Amount);
        channelRegistry.depositToken(channelId, address(token2), token2Amount);

        vm.stopPrank();

        // Get all balances
        IChannelRegistry.TokenDeposit[] memory balances =
            channelRegistry.getParticipantAllBalances(channelId, participant1);

        assertEq(balances.length, 3); // ETH + 2 tokens
        assertEq(balances[0].token, address(0)); // ETH
        assertEq(balances[0].amount, ethAmount);
        assertEq(balances[1].token, address(token1));
        assertEq(balances[1].amount, token1Amount);
        assertEq(balances[2].token, address(token2));
        assertEq(balances[2].amount, token2Amount);
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
}
