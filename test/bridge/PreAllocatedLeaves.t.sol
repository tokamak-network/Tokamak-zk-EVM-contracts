// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeAdminManager.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000 ether);
    }
}

/**
 * @title PreAllocatedLeavesTest
 * @notice Test the pre-allocated leaves system
 */
contract PreAllocatedLeavesTest is Test {
    BridgeCore public bridge;
    BridgeAdminManager public adminManager;
    TestToken public testToken;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        vm.startPrank(owner);

        testToken = new TestToken();

        // Deploy core contract with proxy
        BridgeCore implementation = new BridgeCore();
        bytes memory bridgeInitData = abi.encodeCall(
            BridgeCore.initialize,
            (address(0), address(0), address(0), address(0), owner)
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(implementation), bridgeInitData);
        bridge = BridgeCore(address(bridgeProxy));

        // Deploy admin manager
        BridgeAdminManager adminManagerImpl = new BridgeAdminManager();
        bytes memory adminInitData = abi.encodeCall(BridgeAdminManager.initialize, (address(bridge), owner));
        ERC1967Proxy adminProxy = new ERC1967Proxy(address(adminManagerImpl), adminInitData);
        adminManager = BridgeAdminManager(address(adminProxy));

        // Update bridge with manager addresses
        bridge.updateManagerAddresses(address(0), address(0), address(0), address(adminManager));

        vm.stopPrank();
    }

    function testSetupTonTransferPreAllocatedLeaf() public {
        vm.startPrank(owner);

        // First allow the target contract
        adminManager.setAllowedTargetContract(address(testToken), bytes1(0x00), true);

        // Setup TON transfer pre-allocated leaf
        adminManager.setupTonTransferPreAllocatedLeaf(address(testToken));

        // Verify the pre-allocated leaf was set correctly
        (uint256 value, bool exists) = adminManager.getPreAllocatedLeaf(address(testToken), bytes32(uint256(0x07)));
        assertTrue(exists, "Pre-allocated leaf should exist");
        assertEq(value, 18, "Pre-allocated leaf value should be 18 (decimals)");

        // Check that max participants is reduced by 1
        uint256 maxParticipants = adminManager.getMaxAllowedParticipants(address(testToken));
        assertEq(maxParticipants, 127, "Max participants should be 127 (128 - 1 pre-allocated)");

        // Get all pre-allocated keys
        bytes32[] memory keys = adminManager.getPreAllocatedKeys(address(testToken));
        assertEq(keys.length, 1, "Should have 1 pre-allocated key");
        assertEq(keys[0], bytes32(uint256(0x07)), "First key should be 0x07");

        vm.stopPrank();
    }

    function testCustomPreAllocatedLeaf() public {
        vm.startPrank(owner);

        // First allow the target contract
        adminManager.setAllowedTargetContract(address(testToken), bytes1(0x00), true);

        // Set a custom pre-allocated leaf
        bytes32 customKey = bytes32(uint256(0x42));
        uint256 customValue = 1337;
        adminManager.setPreAllocatedLeaf(address(testToken), customKey, customValue);

        // Verify the custom pre-allocated leaf
        (uint256 value, bool exists) = adminManager.getPreAllocatedLeaf(address(testToken), customKey);
        assertTrue(exists, "Custom pre-allocated leaf should exist");
        assertEq(value, customValue, "Custom pre-allocated leaf value should match");

        // Check that max participants is reduced
        uint256 maxParticipants = adminManager.getMaxAllowedParticipants(address(testToken));
        assertEq(maxParticipants, 127, "Max participants should be 127 (128 - 1 pre-allocated)");

        vm.stopPrank();
    }

    function testMultiplePreAllocatedLeaves() public {
        vm.startPrank(owner);

        // First allow the target contract
        adminManager.setAllowedTargetContract(address(testToken), bytes1(0x00), true);

        // Set multiple pre-allocated leaves
        adminManager.setPreAllocatedLeaf(address(testToken), bytes32(uint256(0x01)), 100);
        adminManager.setPreAllocatedLeaf(address(testToken), bytes32(uint256(0x02)), 200);
        adminManager.setPreAllocatedLeaf(address(testToken), bytes32(uint256(0x03)), 300);

        // Check that max participants is reduced by 3
        uint256 maxParticipants = adminManager.getMaxAllowedParticipants(address(testToken));
        assertEq(maxParticipants, 125, "Max participants should be 125 (128 - 3 pre-allocated)");

        // Get all pre-allocated keys
        bytes32[] memory keys = adminManager.getPreAllocatedKeys(address(testToken));
        assertEq(keys.length, 3, "Should have 3 pre-allocated keys");

        vm.stopPrank();
    }

    function testRemovePreAllocatedLeaf() public {
        vm.startPrank(owner);

        // First allow the target contract
        adminManager.setAllowedTargetContract(address(testToken), bytes1(0x00), true);

        // Set a pre-allocated leaf
        bytes32 testKey = bytes32(uint256(0x42));
        adminManager.setPreAllocatedLeaf(address(testToken), testKey, 1337);

        // Verify it exists
        (uint256 value, bool exists) = adminManager.getPreAllocatedLeaf(address(testToken), testKey);
        assertTrue(exists, "Pre-allocated leaf should exist");

        // Remove it
        adminManager.removePreAllocatedLeaf(address(testToken), testKey);

        // Verify it no longer exists
        (value, exists) = adminManager.getPreAllocatedLeaf(address(testToken), testKey);
        assertFalse(exists, "Pre-allocated leaf should not exist after removal");

        // Check that max participants is back to normal
        uint256 maxParticipants = adminManager.getMaxAllowedParticipants(address(testToken));
        assertEq(maxParticipants, 128, "Max participants should be back to 128");

        vm.stopPrank();
    }

    function testChannelOpeningWithPreAllocatedLeaves() public {
        vm.startPrank(owner);

        // First allow the target contract
        adminManager.setAllowedTargetContract(address(testToken), bytes1(0x00), true);

        // Setup TON transfer pre-allocated leaf (1 leaf)
        adminManager.setupTonTransferPreAllocatedLeaf(address(testToken));

        vm.stopPrank();

        // Create participants (max should be 127 now due to 1 pre-allocated leaf)
        address[] memory participants = new address[](127);
        for (uint256 i = 0; i < 127; i++) {
            participants[i] = address(uint160(i + 1));
        }

        vm.startPrank(user1);

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(testToken),
            participants: participants,
            timeout: 1 days
        });

        // This should succeed with 127 participants
        uint256 channelId = bridge.openChannel(params);

        // Verify the channel has the correct pre-allocated leaves count
        uint256 preAllocatedCount = bridge.getChannelPreAllocatedLeavesCount(channelId);
        assertEq(preAllocatedCount, 1, "Channel should have 1 pre-allocated leaf");

        vm.stopPrank();
    }

    function testChannelOpeningFailsWithTooManyParticipants() public {
        vm.startPrank(owner);

        // First allow the target contract
        adminManager.setAllowedTargetContract(address(testToken), bytes1(0x00), true);

        // Setup TON transfer pre-allocated leaf (1 leaf)
        adminManager.setupTonTransferPreAllocatedLeaf(address(testToken));

        vm.stopPrank();

        // Try to create with 128 participants (should fail due to pre-allocated leaf)
        address[] memory participants = new address[](128);
        for (uint256 i = 0; i < 128; i++) {
            participants[i] = address(uint160(i + 1));
        }

        vm.startPrank(user1);

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(testToken),
            participants: participants,
            timeout: 1 days
        });

        // This should fail
        vm.expectRevert("Invalid participant count considering pre-allocated leaves");
        bridge.openChannel(params);

        vm.stopPrank();
    }
}