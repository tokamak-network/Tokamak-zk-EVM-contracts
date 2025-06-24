// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {ChannelRegistry} from "../src/ChannelRegistry.sol";
import {IChannelRegistry} from "../src/interface/IChannelRegistry.sol";

import "forge-std/console.sol";

contract testChannelRegistry is Test {
    address owner;
    ChannelRegistry channelRegistry;

    function setUp() public virtual {
        owner = makeAddr("owner");
        vm.startPrank(owner);
        channelRegistry = new ChannelRegistry();
        vm.stopPrank();
    }

    function testCreateChannel() public {
        vm.prank(owner);
        bytes32 channelId = channelRegistry.createChannel(owner);

        IChannelRegistry.ChannelInfo memory channelInfo = channelRegistry.getChannelInfo(channelId);

        assertEq(channelInfo.leader, owner);
        assertEq(channelInfo.currentStateRoot, bytes32(0));
        assertEq(uint256(channelInfo.status), uint256(IChannelRegistry.ChannelStatus.ACTIVE));
        assertEq(channelInfo.participants.length, 1);
        assertEq(channelInfo.participants[0], owner);
        assertEq(channelInfo.signatureThreshold, 1);
        assertEq(channelInfo.nonce, 0);
    }

    function testCreateChannelFullFlow() public {
        address leader = address(0x123);
        bytes32 initialStateRoot = bytes32(0);

        vm.prank(owner);
        bytes32 channelId = channelRegistry.createChannel(leader);

        // Verify channel exists
        IChannelRegistry.ChannelInfo memory info = channelRegistry.getChannelInfo(channelId);

        assertEq(info.leader, leader);
        assertEq(info.currentStateRoot, initialStateRoot);
        assertEq(uint256(info.status), uint256(IChannelRegistry.ChannelStatus.ACTIVE));
        assertEq(info.participants.length, 1);
        assertEq(info.participants[0], leader);

        // Verify leader is a participant
        assertTrue(channelRegistry.isChannelParticipant(channelId, leader));
        assertEq(channelRegistry.getParticipantCount(channelId), 1);
    }

    function testCannotCreateChannelWithZeroLeader() public {
        vm.prank(owner);
        vm.expectRevert(IChannelRegistry.Channel__InvalidLeader.selector);
        channelRegistry.createChannel(address(0));
    }

    function testCannotGetNonExistentChannel() public {
        bytes32 fakeChannelId = keccak256("fake");
        vm.expectRevert(IChannelRegistry.Channel__DoesNotExist.selector);
        channelRegistry.getChannelInfo(fakeChannelId);
    }
}
