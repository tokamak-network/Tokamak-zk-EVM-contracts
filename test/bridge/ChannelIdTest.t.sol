// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeAdminManager.sol";
import "../../src/interface/IBridgeCore.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ChannelIdTest
 * @notice Test the new bytes32 channelId system
 */
contract ChannelIdTest is Test {
    BridgeCore bridgeCore;
    BridgeAdminManager adminManager;
    
    address constant TARGET_CONTRACT = address(0x123456);
    address constant USER1 = address(0x1001);
    address constant USER2 = address(0x1002);

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

    function testNewChannelIdSystem() public {
        // Generate a channel ID
        bytes32 salt = bytes32(uint256(12345));
        bytes32 channelId = bridgeCore.generateChannelId(address(this), salt);
        
        assertNotEq(channelId, bytes32(0), "Channel ID should not be zero");
        
        // Create channel with generated ID
        address[] memory participants = new address[](2);
        participants[0] = USER1;
        participants[1] = USER2;
        
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: TARGET_CONTRACT,
            whitelisted: participants,
            enableFrostSignature: false
        });
        
        bytes32 returnedChannelId = bridgeCore.openChannel(params);
        assertEq(returnedChannelId, channelId, "Returned channel ID should match input");
        
        // Verify channel exists
        BridgeCore.ChannelState state = bridgeCore.getChannelState(channelId);
        assertEq(uint256(state), uint256(BridgeCore.ChannelState.Initialized), "Channel should be initialized");
        
        address leader = bridgeCore.getChannelLeader(channelId);
        assertEq(leader, address(this), "Channel leader should be correct");
    }

    function testDuplicateChannelId() public {
        bytes32 channelId = keccak256("test-channel");
        
        address[] memory participants = new address[](2);
        participants[0] = USER1;
        participants[1] = USER2;
        
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: TARGET_CONTRACT,
            whitelisted: participants,
            enableFrostSignature: false
        });
        
        // First call should succeed
        bridgeCore.openChannel(params);
        
        // Second call with same ID should fail
        vm.expectRevert("Channel ID already exists");
        bridgeCore.openChannel(params);
    }

    function testZeroChannelId() public {
        address[] memory participants = new address[](2);
        participants[0] = USER1;
        participants[1] = USER2;
        
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: bytes32(0),
            targetContract: TARGET_CONTRACT,
            whitelisted: participants,
            enableFrostSignature: false
        });
        
        vm.expectRevert("Channel ID cannot be zero");
        bridgeCore.openChannel(params);
    }

    function testGenerateChannelId() public view {
        address leader = address(0x123);
        bytes32 salt1 = bytes32(uint256(1));
        bytes32 salt2 = bytes32(uint256(2));
        
        bytes32 id1 = bridgeCore.generateChannelId(leader, salt1);
        bytes32 id2 = bridgeCore.generateChannelId(leader, salt2);
        
        // Different salts should produce different IDs
        assertNotEq(id1, id2, "Different salts should produce different channel IDs");
        
        // Same inputs should produce same ID
        bytes32 id3 = bridgeCore.generateChannelId(leader, salt1);
        assertEq(id1, id3, "Same inputs should produce same channel ID");
    }
}