// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeCore.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SpecAlignmentTest is Test {
    BridgeCore internal bridge;

    address internal owner = makeAddr("owner");
    address internal leader = makeAddr("leader");
    address internal user1 = makeAddr("user1");
    address internal target = address(0xBEEF);

    function setUp() public {
        BridgeCore implementation = new BridgeCore();
        bytes memory initData = abi.encodeCall(BridgeCore.initialize, (owner, owner, owner, owner, owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        bridge = BridgeCore(address(proxy));

        vm.startPrank(owner);

        BridgeCore.PreAllocatedLeaf[] memory leaves = new BridgeCore.PreAllocatedLeaf[](1);
        leaves[0] = BridgeCore.PreAllocatedLeaf({value: 18, key: bytes32(uint256(0x07)), isActive: true});

        BridgeCore.UserStorageSlot[] memory userSlots = new BridgeCore.UserStorageSlot[](1);
        userSlots[0] =
            BridgeCore.UserStorageSlot({slotOffset: 0, getterFunctionSignature: bytes32(0), isLoadedOnChain: false});

        bridge.setAllowedTargetContract(target, leaves, userSlots, true);

        uint128[] memory preprocessedPart1 = new uint128[](2);
        preprocessedPart1[0] = 1;
        preprocessedPart1[1] = 2;
        uint256[] memory preprocessedPart2 = new uint256[](2);
        preprocessedPart2[0] = 3;
        preprocessedPart2[1] = 4;

        bridge.registerFunction(
            target,
            bytes32(bytes4(keccak256("transfer(address,uint256)"))),
            preprocessedPart1,
            preprocessedPart2,
            keccak256("instances")
        );

        vm.stopPrank();
    }

    function testSpecRelationGettersAndStateIndexRoots() public {
        bytes32 functionSignature = bytes32(bytes4(keccak256("transfer(address,uint256)")));

        // Admin manager relation layer
        address[] memory fcnStorages = bridge.getFcnStorages(functionSignature);
        assertEq(fcnStorages.length, 1);
        assertEq(fcnStorages[0], target);

        bytes32[] memory preAllocKeys = bridge.getPreAllocKeys(target);
        assertEq(preAllocKeys.length, 1);
        assertEq(preAllocKeys[0], bytes32(uint256(0x07)));

        uint8[] memory userSlots = bridge.getUserSlots(target);
        assertEq(userSlots.length, 1);
        assertEq(userSlots[0], 0);

        uint128[] memory expectedPart1 = new uint128[](2);
        expectedPart1[0] = 1;
        expectedPart1[1] = 2;
        uint256[] memory expectedPart2 = new uint256[](2);
        expectedPart2[0] = 3;
        expectedPart2[1] = 4;

        (bytes32 instancesHash, bytes32 preprocessHash) = bridge.getFcnCfg(functionSignature);
        assertEq(instancesHash, keccak256("instances"));
        assertEq(preprocessHash, keccak256(abi.encode(expectedPart1, expectedPart2)));

        // Open channel and populate participant state
        address[] memory whitelisted = new address[](1);
        whitelisted[0] = user1;

        vm.prank(leader);
        bytes32 channelId = bridge.openChannel(
            BridgeCore.ChannelParams({
                channelId: keccak256("spec-channel"),
                targetContract: target,
                whitelisted: whitelisted,
                enableFrostSignature: false
            })
        );

        vm.startPrank(owner);
        bridge.addParticipantOnDeposit(channelId, user1);

        uint256[] memory userKeys = new uint256[](1);
        userKeys[0] = 111;
        bridge.setChannelL2MptKeys(channelId, user1, userKeys);
        bridge.updateChannelUserDeposits(channelId, user1, 0, 10);

        bridge.setChannelInitialStateRoot(channelId, bytes32(uint256(1000)));
        bridge.setChannelFinalStateRoot(channelId, bytes32(uint256(2000)));
        vm.stopPrank();

        // Channel/projected getter layer
        address[] memory channelFcnStorages = bridge.getChannelFcnStorages(channelId, functionSignature);
        assertEq(channelFcnStorages.length, 1);
        assertEq(channelFcnStorages[0], target);

        bytes32[] memory channelPreAllocKeys = bridge.getChannelPreAllocKeys(channelId, target);
        assertEq(channelPreAllocKeys.length, 1);
        assertEq(channelPreAllocKeys[0], bytes32(uint256(0x07)));

        uint8[] memory channelUserSlots = bridge.getChannelUserSlots(channelId, target);
        assertEq(channelUserSlots.length, 1);
        assertEq(channelUserSlots[0], 0);

        uint256 channelUserKey = bridge.getChannelUserStorageKey(channelId, user1, target);
        assertEq(channelUserKey, 111);

        uint256 validatedValue = bridge.getChannelValidatedStorageValue(channelId, target, 111);
        assertEq(validatedValue, 10);

        uint256 preAllocValue = bridge.getChannelPreAllocValue(channelId, target, bytes32(uint256(0x07)));
        assertEq(preAllocValue, 18);

        bytes32 root0 = bridge.getChannelVerifiedStateRoot(channelId, target, 0);
        bytes32 root1 = bridge.getChannelVerifiedStateRoot(channelId, target, 1);
        assertEq(root0, bytes32(uint256(1000)));
        assertEq(root1, bytes32(uint256(2000)));

        (uint16[] memory stateIndices, bytes32[] memory roots) = bridge.getChannelProposedStateFork(channelId, 0);
        assertEq(stateIndices.length, 2);
        assertEq(roots.length, 2);
        assertEq(stateIndices[0], 0);
        assertEq(stateIndices[1], 1);
        assertEq(roots[0], bytes32(uint256(1000)));
        assertEq(roots[1], bytes32(uint256(2000)));

        assertEq(bridge.nTokamakPublicInputs(), 64);
        assertEq(bridge.nMerkleTreeLevels(), 7);
        assertEq(bridge.getChannelMerkleTreeLevels(channelId), 4);
    }
}
