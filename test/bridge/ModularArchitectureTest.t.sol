// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/RollupBridgeCore.sol";
import "../../src/RollupBridgeProofManager.sol";
import "../../src/RollupBridgeDepositManager.sol";
import "../../src/RollupBridgeAdminManager.sol";
import "../../src/interface/ITokamakVerifier.sol";
import "../../src/interface/IZecFrost.sol";
import "../../src/interface/IGroth16Verifier16Leaves.sol";
import "../../src/library/ZecFrost.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

// Mock contracts for testing
contract MockTokamakVerifier is ITokamakVerifier {
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

contract MockGroth16Verifier is IGroth16Verifier16Leaves {
    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[33] calldata)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title ModularArchitectureTest
 * @notice Test that demonstrates the working modular architecture
 */
contract ModularArchitectureTest is Test {
    RollupBridgeCore public bridge;
    RollupBridgeProofManager public proofManager;
    RollupBridgeDepositManager public depositManager;
    RollupBridgeAdminManager public adminManager;

    MockTokamakVerifier public tokamakVerifier;
    MockGroth16Verifier public groth16Verifier;
    ZecFrost public zecFrost;
    TestToken public testToken;

    address public owner = makeAddr("owner");
    address public leader = makeAddr("leader");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        tokamakVerifier = new MockTokamakVerifier();
        groth16Verifier = new MockGroth16Verifier();
        zecFrost = new ZecFrost();
        testToken = new TestToken();

        // Deploy manager implementations
        RollupBridgeDepositManager depositManagerImpl = new RollupBridgeDepositManager();
        RollupBridgeProofManager proofManagerImpl = new RollupBridgeProofManager();
        RollupBridgeAdminManager adminManagerImpl = new RollupBridgeAdminManager();

        // Deploy core contract with proxy first
        RollupBridgeCore implementation = new RollupBridgeCore();
        bytes memory bridgeInitData = abi.encodeCall(
            RollupBridgeCore.initialize,
            (address(0), address(0), address(0), address(0), owner) // Temporary addresses
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(implementation), bridgeInitData);
        bridge = RollupBridgeCore(address(bridgeProxy));

        // Deploy manager proxies with bridge address
        bytes memory depositInitData = abi.encodeCall(RollupBridgeDepositManager.initialize, (address(bridge), owner));
        ERC1967Proxy depositProxy = new ERC1967Proxy(address(depositManagerImpl), depositInitData);
        depositManager = RollupBridgeDepositManager(address(depositProxy));

        address[4] memory groth16Verifiers =
            [address(groth16Verifier), address(groth16Verifier), address(groth16Verifier), address(groth16Verifier)];
        bytes memory proofInitData = abi.encodeCall(
            RollupBridgeProofManager.initialize,
            (address(bridge), address(tokamakVerifier), address(zecFrost), groth16Verifiers, owner)
        );
        ERC1967Proxy proofProxy = new ERC1967Proxy(address(proofManagerImpl), proofInitData);
        proofManager = RollupBridgeProofManager(address(proofProxy));

        bytes memory adminInitData = abi.encodeCall(RollupBridgeAdminManager.initialize, (address(bridge), owner));
        ERC1967Proxy adminProxy = new ERC1967Proxy(address(adminManagerImpl), adminInitData);
        adminManager = RollupBridgeAdminManager(address(adminProxy));

        // Update bridge with manager addresses
        bridge.updateManagerAddresses(address(depositManager), address(proofManager), address(0), address(adminManager));

        // Register the test token and its transfer function
        uint128[] memory preprocessedPart1 = new uint128[](4);
        uint256[] memory preprocessedPart2 = new uint256[](4);
        bytes32 transferSig = keccak256("transfer(address,uint256)");

        adminManager.setAllowedTargetContract(address(testToken), bytes1(0x00), true);
        adminManager.registerFunction(transferSig, preprocessedPart1, preprocessedPart2);

        // Fund test accounts
        vm.deal(leader, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);

        // Mint test tokens for users
        testToken.mint(user1, 1000 ether);
        testToken.mint(user2, 1000 ether);
        testToken.mint(user3, 1000 ether);

        vm.stopPrank();
    }

    function testModularArchitectureBasic() public view {
        // Test that all contracts are properly deployed
        assertEq(bridge.owner(), owner);
        assertEq(depositManager.owner(), owner);
        assertEq(proofManager.owner(), owner);

        // Test that managers are properly linked
        assertEq(address(depositManager.rollupBridge()), address(bridge));
        assertEq(address(proofManager.rollupBridge()), address(bridge));
    }

    function testGetImplementationAddress() public view {
        // Test that getImplementation() returns the correct implementation addresses
        address bridgeImpl = bridge.getImplementation();
        address depositImpl = depositManager.getImplementation();
        address proofImpl = proofManager.getImplementation();

        // Verify that implementation addresses are not zero and not the proxy addresses
        assertTrue(bridgeImpl != address(0), "Bridge implementation should not be zero");
        assertTrue(depositImpl != address(0), "Deposit manager implementation should not be zero");
        assertTrue(proofImpl != address(0), "Proof manager implementation should not be zero");

        assertTrue(bridgeImpl != address(bridge), "Implementation should not equal proxy address");
        assertTrue(depositImpl != address(depositManager), "Implementation should not equal proxy address");
        assertTrue(proofImpl != address(proofManager), "Implementation should not equal proxy address");

        console.log("Bridge proxy:", address(bridge));
        console.log("Bridge implementation:", bridgeImpl);
        console.log("Deposit manager proxy:", address(depositManager));
        console.log("Deposit manager implementation:", depositImpl);
        console.log("Proof manager proxy:", address(proofManager));
        console.log("Proof manager implementation:", proofImpl);
    }

    function testChannelCreationAndDeposits() public {
        // Create a channel
        vm.startPrank(leader);

        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = address(testToken);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        RollupBridgeCore.ChannelParams memory params =
            RollupBridgeCore.ChannelParams({allowedTokens: allowedTokens, participants: participants, timeout: 1 days});

        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(channelId, 1, 2);
        vm.stopPrank();

        // Verify channel creation
        assertEq(channelId, 0);
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(RollupBridgeCore.ChannelState.Initialized));

        // Test deposit using DepositManager
        vm.startPrank(user1);
        testToken.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId, address(testToken), 1 ether, bytes32(uint256(123)));
        vm.stopPrank();

        // Verify deposit was recorded
        assertEq(bridge.getParticipantTokenDeposit(channelId, user1, address(testToken)), 1 ether);
        assertEq(bridge.getL2MptKey(channelId, user1, address(testToken)), 123);
    }

    function testChannelStateInitialization() public {
        // Create and deposit to a channel
        uint256 channelId = _createChannelWithDeposits();

        // Get the actual leader who created the channel
        address actualLeader = bridge.getChannelLeader(channelId);

        // Initialize channel state using ProofManager (leader is the channel creator)
        vm.startPrank(actualLeader);
        proofManager.initializeChannelState(
            channelId,
            RollupBridgeProofManager.ChannelInitializationProof({
                pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
                pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
                pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
                merkleRoot: keccak256(abi.encodePacked("mockRoot"))
            })
        );
        vm.stopPrank();

        // Verify state transition
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(RollupBridgeCore.ChannelState.Open));
    }

    function _createChannelWithDeposits() internal returns (uint256 channelId) {
        vm.startPrank(leader);

        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = address(testToken);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        RollupBridgeCore.ChannelParams memory params =
            RollupBridgeCore.ChannelParams({allowedTokens: allowedTokens, participants: participants, timeout: 1 days});

        channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(channelId, 1, 2);
        vm.stopPrank();

        // Add deposits
        vm.startPrank(user1);
        testToken.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId, address(testToken), 1 ether, bytes32(uint256(123)));
        vm.stopPrank();

        vm.startPrank(user2);
        testToken.approve(address(depositManager), 2 ether);
        depositManager.depositToken(channelId, address(testToken), 2 ether, bytes32(uint256(456)));
        vm.stopPrank();

        vm.startPrank(user3);
        testToken.approve(address(depositManager), 3 ether);
        depositManager.depositToken(channelId, address(testToken), 3 ether, bytes32(uint256(789)));
        vm.stopPrank();
    }
}
