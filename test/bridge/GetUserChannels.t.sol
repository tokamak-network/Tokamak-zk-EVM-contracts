// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeAdminManager.sol";
import "../../src/interface/IBridgeCore.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title GetUserChannelsTest
 * @notice Test the new getUserChannels function
 */
contract GetUserChannelsTest is Test {
    BridgeCore bridgeCore;
    BridgeAdminManager adminManager;
    
    address constant TARGET_CONTRACT = address(0x123456);
    address constant USER1 = address(0x1001);
    address constant USER2 = address(0x1002);
    address constant USER3 = address(0x1003);

    function setUp() public {
        bridgeCore = new BridgeCore();
        adminManager = new BridgeAdminManager();
        
        ERC1967Proxy bridgeCoreProxy = new ERC1967Proxy(
            address(bridgeCore),
            abi.encodeCall(bridgeCore.initialize, (address(0), address(0), address(0), address(adminManager), address(this)))
        );
        bridgeCore = BridgeCore(address(bridgeCoreProxy));
        
        ERC1967Proxy adminManagerProxy = new ERC1967Proxy(
            address(adminManager),
            abi.encodeCall(adminManager.initialize, (address(bridgeCore), address(this)))
        );
        adminManager = BridgeAdminManager(address(adminManagerProxy));
        
        bridgeCore.updateManagerAddresses(address(0), address(0), address(0), address(adminManager));
        
        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        adminManager.setAllowedTargetContract(TARGET_CONTRACT, emptySlots, true);
    }

    function testGetUserChannelsBasic() public {
        console.log("=== Testing getUserChannels Function ===");
        
        // Initially, USER1 should have no channels
        (uint256[] memory channels, uint256 totalCount) = bridgeCore.getUserChannels(USER1, 0, 0);
        assertEq(channels.length, 0, "USER1 should initially have no channels");
        assertEq(totalCount, 0, "Total count should be 0");
        console.log("Initial state: USER1 has %d channels", totalCount);
        
        // Create channel 1 with USER1 and USER2
        address[] memory participants1 = new address[](2);
        participants1[0] = USER1;
        participants1[1] = USER2;
        
        BridgeCore.ChannelParams memory params1 = BridgeCore.ChannelParams({
            targetContract: TARGET_CONTRACT,
            whitelisted: participants1,
            enableFrostSignature: false
        });
        
        vm.startPrank(address(0x5001));
        uint256 channel1 = bridgeCore.openChannel(params1);
        vm.stopPrank();
        console.log("Created channel %d with USER1 and USER2", channel1);
        
        // Debug: check if USER1 is whitelisted in the channel
        bool isWhitelisted = bridgeCore.isChannelWhitelisted(channel1, USER1);
        console.log("Is USER1 whitelisted in channel %d: %s", channel1, isWhitelisted ? "true" : "false");
        
        // Check USER1's channels
        (channels, totalCount) = bridgeCore.getUserChannels(USER1, 0, 0);
        assertEq(channels.length, 1, "USER1 should have 1 channel");
        assertEq(totalCount, 1, "Total count should be 1");
        assertEq(channels[0], channel1, "Should return channel 1");
        console.log("USER1 now has %d channels: [%d]", totalCount, channels[0]);
        
        // Check USER2's channels
        (channels, totalCount) = bridgeCore.getUserChannels(USER2, 0, 0);
        assertEq(channels.length, 1, "USER2 should have 1 channel");
        assertEq(totalCount, 1, "Total count should be 1");
        assertEq(channels[0], channel1, "Should return channel 1");
        console.log("USER2 now has %d channels: [%d]", totalCount, channels[0]);
        
        // Check USER3's channels (should be empty)
        (channels, totalCount) = bridgeCore.getUserChannels(USER3, 0, 0);
        assertEq(channels.length, 0, "USER3 should have no channels");
        assertEq(totalCount, 0, "Total count should be 0");
        console.log("USER3 has %d channels", totalCount);
    }

    function testGetUserChannelsMultiple() public {
        console.log("=== Testing Multiple Channels ===");
        
        // Create channel 1 with USER1 and USER2
        address[] memory participants1 = new address[](2);
        participants1[0] = USER1;
        participants1[1] = USER2;
        
        vm.startPrank(address(0x5001));
        uint256 channel1 = bridgeCore.openChannel(BridgeCore.ChannelParams({
            targetContract: TARGET_CONTRACT,
            whitelisted: participants1,
            enableFrostSignature: false
        }));
        vm.stopPrank();
        
        // Create channel 2 with USER1 and USER3
        address[] memory participants2 = new address[](2);
        participants2[0] = USER1;
        participants2[1] = USER3;
        
        vm.startPrank(address(0x5002));
        uint256 channel2 = bridgeCore.openChannel(BridgeCore.ChannelParams({
            targetContract: TARGET_CONTRACT,
            whitelisted: participants2,
            enableFrostSignature: false
        }));
        vm.stopPrank();
        
        // Create channel 3 with USER2 and USER3 (no USER1)
        address[] memory participants3 = new address[](2);
        participants3[0] = USER2;
        participants3[1] = USER3;
        
        vm.startPrank(address(0x5003));
        uint256 channel3 = bridgeCore.openChannel(BridgeCore.ChannelParams({
            targetContract: TARGET_CONTRACT,
            whitelisted: participants3,
            enableFrostSignature: false
        }));
        vm.stopPrank();
        
        console.log("Created channels: %d, %d, %d", channel1, channel2, channel3);
        
        // Check USER1's channels (should have 2)
        (uint256[] memory channels, uint256 totalCount) = bridgeCore.getUserChannels(USER1, 0, 0);
        assertEq(totalCount, 2, "USER1 should have 2 channels");
        assertEq(channels.length, 2, "Should return 2 channels");
        
        console.log("USER1 channels: [%d, %d]", channels[0], channels[1]);
        assertTrue(
            (channels[0] == channel1 && channels[1] == channel2) ||
            (channels[0] == channel2 && channels[1] == channel1),
            "USER1 should have channels 1 and 2"
        );
        
        // Check USER2's channels (should have 2)
        (channels, totalCount) = bridgeCore.getUserChannels(USER2, 0, 0);
        assertEq(totalCount, 2, "USER2 should have 2 channels");
        console.log("USER2 channels: [%d, %d]", channels[0], channels[1]);
        
        // Check USER3's channels (should have 2)
        (channels, totalCount) = bridgeCore.getUserChannels(USER3, 0, 0);
        assertEq(totalCount, 2, "USER3 should have 2 channels");
        console.log("USER3 channels: [%d, %d]", channels[0], channels[1]);
    }

    function testGetUserChannelsPagination() public {
        console.log("=== Testing Pagination ===");
        
        // Create 5 channels with USER1
        uint256[] memory createdChannels = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            address[] memory participants = new address[](2);
            participants[0] = USER1;
            participants[1] = address(uint160(0x2000 + i)); // Different second participant each time
            
            vm.startPrank(address(uint160(0x5000 + i)));
            createdChannels[i] = bridgeCore.openChannel(BridgeCore.ChannelParams({
                targetContract: TARGET_CONTRACT,
                whitelisted: participants,
                enableFrostSignature: false
            }));
            vm.stopPrank();
        }
        
        console.log("Created 5 channels for USER1");
        
        // Test getting all channels
        (uint256[] memory channels, uint256 totalCount) = bridgeCore.getUserChannels(USER1, 0, 0);
        assertEq(totalCount, 5, "USER1 should have 5 channels total");
        assertEq(channels.length, 5, "Should return all 5 channels");
        console.log("Total channels for USER1: %d", totalCount);
        
        // Test pagination: get first 2 channels
        (channels, totalCount) = bridgeCore.getUserChannels(USER1, 2, 0);
        assertEq(totalCount, 5, "Total count should still be 5");
        assertEq(channels.length, 2, "Should return 2 channels");
        console.log("First 2 channels: [%d, %d]", channels[0], channels[1]);
        
        // Test pagination: get next 2 channels (offset 2)
        (channels, totalCount) = bridgeCore.getUserChannels(USER1, 2, 2);
        assertEq(totalCount, 5, "Total count should still be 5");
        assertEq(channels.length, 2, "Should return 2 channels");
        console.log("Next 2 channels (offset 2): [%d, %d]", channels[0], channels[1]);
        
        // Test pagination: get last channel (offset 4)
        (channels, totalCount) = bridgeCore.getUserChannels(USER1, 2, 4);
        assertEq(totalCount, 5, "Total count should still be 5");
        assertEq(channels.length, 1, "Should return 1 channel");
        console.log("Last channel (offset 4): [%d]", channels[0]);
        
        // Test out of bounds offset
        (channels, totalCount) = bridgeCore.getUserChannels(USER1, 2, 10);
        assertEq(totalCount, 5, "Total count should still be 5");
        assertEq(channels.length, 0, "Should return 0 channels for out of bounds offset");
        console.log("Out of bounds offset returns %d channels", channels.length);
    }
}