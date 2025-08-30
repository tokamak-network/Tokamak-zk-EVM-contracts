// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/RollupBridge.sol";
import "../src/interface/IRollupBridge.sol";
import "../src/interface/IVerifier.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ArchitecturalOptimizationTest
 * @dev Test suite to verify RollupBridge functionality with embedded Merkle operations
 */
contract ArchitecturalOptimizationTest is Test {
    RollupBridge public bridge;
    MockVerifier public verifier;
    MockERC20 public token;

    address public owner = address(1);
    address public leader = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);

    address public l2User1 = address(13);
    address public l2User2 = address(14);
    address public l2User3 = address(15);

    uint256 public constant DEPOSIT_AMOUNT = 100 ether;

    function setUp() public {
        vm.startPrank(owner);

        verifier = new MockVerifier();
        token = new MockERC20();

        // Deploy RollupBridge with embedded Merkle operations
        RollupBridge bridgeImpl = new RollupBridge();
        bytes memory initData = abi.encodeCall(RollupBridge.initialize, (address(verifier), address(0), owner));
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(bridgeImpl), initData);
        bridge = RollupBridge(payable(address(bridgeProxy)));

        // Setup permissions
        bridge.authorizeCreator(leader);
        
        // Mint tokens for testing
        token.mint(user1, DEPOSIT_AMOUNT * 10);
        token.mint(user2, DEPOSIT_AMOUNT * 10);
        token.mint(user3, DEPOSIT_AMOUNT * 10);

        vm.stopPrank();

        // Give users ETH for gas
        vm.deal(leader, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    function test_ChannelCreationAndDeposits() public {
        vm.startPrank(leader);

        // Create channel with 3 participants
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;

        uint128[] memory preprocessedPart1 = new uint128[](1);
        preprocessedPart1[0] = 1;

        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart2[0] = 1;

        uint256 channelId = bridge.openChannel(
            address(token), participants, l2PublicKeys, preprocessedPart1, preprocessedPart2, 1 hours, bytes32(0)
        );

        vm.stopPrank();

        // Users make deposits
        vm.startPrank(user1);
        token.approve(address(bridge), DEPOSIT_AMOUNT);
        bridge.depositToken(channelId, address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(bridge), DEPOSIT_AMOUNT);
        bridge.depositToken(channelId, address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(bridge), DEPOSIT_AMOUNT);
        bridge.depositToken(channelId, address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Verify deposits
        assertEq(bridge.getParticipantDeposit(channelId, user1), DEPOSIT_AMOUNT);
        assertEq(bridge.getParticipantDeposit(channelId, user2), DEPOSIT_AMOUNT);
        assertEq(bridge.getParticipantDeposit(channelId, user3), DEPOSIT_AMOUNT);
    }

    function test_ChannelStateInitialization() public {
        vm.startPrank(leader);

        // Create channel
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;

        uint128[] memory preprocessedPart1 = new uint128[](1);
        preprocessedPart1[0] = 1;

        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart2[0] = 1;

        uint256 channelId = bridge.openChannel(
            address(token), participants, l2PublicKeys, preprocessedPart1, preprocessedPart2, 1 hours, bytes32(0)
        );

        vm.stopPrank();

        // Users make deposits
        vm.startPrank(user1);
        token.approve(address(bridge), DEPOSIT_AMOUNT);
        bridge.depositToken(channelId, address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(bridge), DEPOSIT_AMOUNT);
        bridge.depositToken(channelId, address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(bridge), DEPOSIT_AMOUNT);
        bridge.depositToken(channelId, address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Initialize channel state
        vm.prank(leader);
        bridge.initializeChannelState(channelId);

        // Verify channel is open
        (, IRollupBridge.ChannelState state,,,) = bridge.getChannelInfo(channelId);
        assertEq(uint256(state), uint256(IRollupBridge.ChannelState.Open));
    }

    function test_MultipleChannels() public {
        // Authorize user1 as another creator
        vm.prank(owner);
        bridge.authorizeCreator(user1);

        vm.startPrank(leader);

        address[] memory participants1 = new address[](3);
        participants1[0] = user1;
        participants1[1] = user2;
        participants1[2] = user3;

        address[] memory l2PublicKeys1 = new address[](3);
        l2PublicKeys1[0] = l2User1;
        l2PublicKeys1[1] = l2User2;
        l2PublicKeys1[2] = l2User3;

        uint128[] memory preprocessedPart1 = new uint128[](1);
        preprocessedPart1[0] = 1;

        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart2[0] = 1;

        // Create first channel with leader
        uint256 channelId1 = bridge.openChannel(
            address(token), participants1, l2PublicKeys1, preprocessedPart1, preprocessedPart2, 1 hours, bytes32(0)
        );

        vm.stopPrank();

        // Create second channel with different leader (user1)
        vm.startPrank(user1);

        address[] memory participants2 = new address[](3);
        participants2[0] = leader;
        participants2[1] = user2;
        participants2[2] = user3;

        address[] memory l2PublicKeys2 = new address[](3);
        l2PublicKeys2[0] = l2User1;
        l2PublicKeys2[1] = l2User2;
        l2PublicKeys2[2] = l2User3;

        uint256 channelId2 = bridge.openChannel(
            address(token), participants2, l2PublicKeys2, preprocessedPart1, preprocessedPart2, 1 hours, bytes32(0)
        );

        vm.stopPrank();

        assertEq(channelId1, 0);
        assertEq(channelId2, 1);
        assertEq(bridge.nextChannelId(), 2);
    }

    function test_EthDeposits() public {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;

        uint128[] memory preprocessedPart1 = new uint128[](1);
        preprocessedPart1[0] = 1;

        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart2[0] = 1;

        uint256 channelId = bridge.openChannel(
            address(1), participants, l2PublicKeys, preprocessedPart1, preprocessedPart2, 1 hours, bytes32(0)
        );

        vm.stopPrank();

        // Users deposit ETH
        vm.prank(user1);
        bridge.depositETH{value: 1 ether}(channelId);

        vm.prank(user2);
        bridge.depositETH{value: 2 ether}(channelId);

        vm.prank(user3);
        bridge.depositETH{value: 1.5 ether}(channelId);

        // Verify ETH deposits
        assertEq(bridge.getParticipantDeposit(channelId, user1), 1 ether);
        assertEq(bridge.getParticipantDeposit(channelId, user2), 2 ether);
        assertEq(bridge.getParticipantDeposit(channelId, user3), 1.5 ether);
    }
}

contract MockVerifier is IVerifier {
    function verify(
        uint128[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external pure returns (bool) {
        return true;
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Test Token", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}