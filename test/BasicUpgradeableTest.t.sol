// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/RollupBridgeUpgradeable.sol";
import "../src/merkleTree/MerkleTreeManager4Upgradeable.sol";
import "../src/verifier/Verifier.sol";

import {IERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title MockERC20Upgradeable
 * @dev Mock ERC20 token for testing purposes
 */
contract MockERC20Upgradeable is ERC20Upgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockVerifier
 * @dev Mock verifier for testing - always returns true
 */
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

/**
 * @title RollupBridgeUpgradeableV2
 * @dev V2 implementation for upgrade testing - adds new functionality
 */
contract RollupBridgeUpgradeableV2 is RollupBridgeUpgradeable {
    // Additional events for V2
    event EmergencyPauseActivated();
    event BatchVerifierUpdate(address[] oldVerifiers, address[] newVerifiers);

    /**
     * @notice New function added in V2
     * @return version The contract version
     */
    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    /**
     * @notice New emergency pause functionality
     */
    function emergencyPause() external onlyOwner {
        // Emergency pause logic would go here
        emit EmergencyPauseActivated();
    }

    /**
     * @notice Enhanced verifier management - batch updates (V2 feature)
     * @param _newVerifiers Array of verifier addresses to cycle through
     * @dev Example of how V2 could add enhanced verifier management
     */
    function batchUpdateVerifiers(address[] calldata _newVerifiers) external onlyOwner {
        require(_newVerifiers.length > 0, "Empty verifiers array");

        // In a real implementation, this might store multiple verifiers
        // or implement a rotation system
        address[] memory oldVerifiers = new address[](1);
        oldVerifiers[0] = address(zkVerifier());

        // For demo, just update to the first verifier
        // Note: In a real implementation, we'd have a more sophisticated approach
        // Access storage directly since we're already in onlyOwner context
        require(_newVerifiers[0] != address(0), "Invalid verifier address");
        require(_newVerifiers[0] != oldVerifiers[0], "Same verifier address");

        RollupBridgeStorage storage $ = _getRollupBridgeStorage();
        $.zkVerifier = IVerifier(_newVerifiers[0]);

        emit VerifierUpdated(oldVerifiers[0], _newVerifiers[0]);
        emit BatchVerifierUpdate(oldVerifiers, _newVerifiers);
    }

    /**
     * @notice Get verifier info (V2 enhancement)
     * @return verifier Current verifier address
     * @return isValid Whether the verifier appears to be valid
     */
    function getVerifierInfo() external view returns (address verifier, bool isValid) {
        verifier = address(zkVerifier());
        // Basic validation - in real implementation might check interface support
        isValid = verifier != address(0) && verifier.code.length > 0;
    }
}

/**
 * @title MerkleTreeManager4UpgradeableV2
 * @dev V2 implementation for upgrade testing - adds new functionality
 */
contract MerkleTreeManager4UpgradeableV2 is MerkleTreeManager4Upgradeable {
    /**
     * @notice New function added in V2
     * @return version The contract version
     */
    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    /**
     * @notice New batch operation functionality
     * @param channelId ID of the channel
     * @param operations Array of operation types
     */
    function batchOperations(uint256 channelId, uint8[] calldata operations) external onlyOwner {
        // Batch operations logic would go here
        emit BatchOperationsExecuted(channelId, operations.length);
    }

    event BatchOperationsExecuted(uint256 indexed channelId, uint256 operationCount);
}

/**
 * @title BasicUpgradeableTest
 * @dev Basic test suite for UUPS upgradeable contracts using ERC1967Proxy directly
 */
contract BasicUpgradeableTest is Test {
    // Test addresses
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public attacker = makeAddr("attacker");

    // Contract instances
    ERC1967Proxy public rollupBridgeProxy;
    ERC1967Proxy public merkleTreeManagerProxy;
    MockERC20Upgradeable public token;
    MockVerifier public verifier;

    RollupBridgeUpgradeable public rollupBridge;
    MerkleTreeManager4Upgradeable public merkleTreeManager;

    // Test data
    uint32 public constant TREE_DEPTH = 4;
    address public constant ETH_TOKEN_ADDRESS = address(1);

    event ChannelOpened(uint256 indexed channelId, address indexed targetContract);
    event Upgraded(address indexed implementation);
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event BatchVerifierUpdate(address[] oldVerifiers, address[] newVerifiers);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        verifier = new MockVerifier();

        // Deploy implementation contracts
        RollupBridgeUpgradeable rollupBridgeImpl = new RollupBridgeUpgradeable();
        MerkleTreeManager4Upgradeable merkleTreeManagerImpl = new MerkleTreeManager4Upgradeable();

        // Deploy proxies
        merkleTreeManagerProxy = new ERC1967Proxy(
            address(merkleTreeManagerImpl),
            abi.encodeCall(MerkleTreeManager4Upgradeable.initialize, (TREE_DEPTH, owner))
        );
        merkleTreeManager = MerkleTreeManager4Upgradeable(address(merkleTreeManagerProxy));

        rollupBridgeProxy = new ERC1967Proxy(
            address(rollupBridgeImpl),
            abi.encodeCall(
                RollupBridgeUpgradeable.initialize, (address(verifier), address(merkleTreeManagerProxy), owner)
            )
        );
        rollupBridge = RollupBridgeUpgradeable(payable(address(rollupBridgeProxy)));

        // Set bridge in merkle tree manager
        merkleTreeManager.setBridge(address(rollupBridgeProxy));

        // Deploy and setup mock ERC20
        MockERC20Upgradeable tokenImpl = new MockERC20Upgradeable();
        ERC1967Proxy tokenProxy = new ERC1967Proxy(
            address(tokenImpl), abi.encodeCall(MockERC20Upgradeable.initialize, ("Test Token", "TEST"))
        );
        token = MockERC20Upgradeable(address(tokenProxy));

        // Mint tokens for testing
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);
        token.mint(user3, 1000 ether);

        vm.stopPrank();

        // Give users ETH
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    // ============ Deployment Tests ============

    function test_InitialDeployment() public {
        // Check RollupBridge initialization
        assertEq(rollupBridge.owner(), owner);
        assertEq(address(rollupBridge.zkVerifier()), address(verifier));
        assertEq(address(rollupBridge.mtmanager()), address(merkleTreeManagerProxy));
        assertEq(rollupBridge.nextChannelId(), 0);

        // Check MerkleTreeManager initialization
        assertEq(merkleTreeManager.owner(), owner);
        assertEq(merkleTreeManager.depth(), TREE_DEPTH);
        assertEq(merkleTreeManager.bridge(), address(rollupBridgeProxy));
        assertTrue(merkleTreeManager.bridgeSet());
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        rollupBridge.initialize(address(verifier), address(merkleTreeManagerProxy), owner);

        vm.expectRevert();
        merkleTreeManager.initialize(TREE_DEPTH, owner);
    }

    // ============ Basic Functionality Tests ============

    function test_BasicChannelFlow() public {
        vm.startPrank(owner);

        // Authorize user1 as creator
        rollupBridge.authorizeCreator(user1);

        vm.stopPrank();
        vm.startPrank(user1);

        // Prepare channel data
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = makeAddr("l2user1");
        l2PublicKeys[1] = makeAddr("l2user2");
        l2PublicKeys[2] = makeAddr("l2user3");

        uint128[] memory preprocessedPart1 = new uint128[](2);
        preprocessedPart1[0] = 1;
        preprocessedPart1[1] = 2;

        uint256[] memory preprocessedPart2 = new uint256[](2);
        preprocessedPart2[0] = 3;
        preprocessedPart2[1] = 4;

        // Open channel
        vm.expectEmit(true, true, false, true);
        emit ChannelOpened(0, ETH_TOKEN_ADDRESS);

        uint256 channelId = rollupBridge.openChannel(
            ETH_TOKEN_ADDRESS,
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            1 hours,
            bytes32(uint256(123)) // groupPublicKey
        );

        assertEq(channelId, 0);
        assertTrue(rollupBridge.isChannelLeader(user1));

        // Deposit ETH
        rollupBridge.depositETH{value: 1 ether}(channelId);
        assertEq(rollupBridge.getParticipantDeposit(channelId, user1), 1 ether);

        vm.stopPrank();
    }

    // ============ Manual Upgrade Tests ============

    function test_UpgradeRollupBridge() public {
        // Store initial state
        vm.prank(owner);
        rollupBridge.authorizeCreator(user1);

        assertTrue(rollupBridge.isAuthorizedCreator(user1));
        uint256 initialChannelId = rollupBridge.nextChannelId();

        // Deploy new implementation
        RollupBridgeUpgradeableV2 rollupBridgeV2Impl = new RollupBridgeUpgradeableV2();

        vm.prank(owner);
        // Upgrade to V2 using upgradeTo (without calling)
        rollupBridge.upgradeTo(address(rollupBridgeV2Impl));

        RollupBridgeUpgradeableV2 rollupBridgeV2 = RollupBridgeUpgradeableV2(payable(address(rollupBridgeProxy)));

        // Check state preservation
        assertEq(rollupBridgeV2.owner(), owner);
        assertEq(address(rollupBridgeV2.zkVerifier()), address(verifier));
        assertEq(address(rollupBridgeV2.mtmanager()), address(merkleTreeManagerProxy));
        assertTrue(rollupBridgeV2.isAuthorizedCreator(user1));
        assertEq(rollupBridgeV2.nextChannelId(), initialChannelId);

        // Test new functionality
        assertEq(rollupBridgeV2.version(), "2.0.0");

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit RollupBridgeUpgradeableV2.EmergencyPauseActivated();
        rollupBridgeV2.emergencyPause();
    }

    function test_UpgradeMerkleTreeManager() public {
        // Store initial state
        uint32 initialDepth = merkleTreeManager.depth();
        address initialBridge = merkleTreeManager.bridge();
        bool initialBridgeSet = merkleTreeManager.bridgeSet();

        // Deploy new implementation
        MerkleTreeManager4UpgradeableV2 merkleTreeManagerV2Impl = new MerkleTreeManager4UpgradeableV2();

        vm.prank(owner);
        // Upgrade to V2 using upgradeTo (without calling)
        merkleTreeManager.upgradeTo(address(merkleTreeManagerV2Impl));

        MerkleTreeManager4UpgradeableV2 merkleTreeManagerV2 =
            MerkleTreeManager4UpgradeableV2(address(merkleTreeManagerProxy));

        // Check state preservation
        assertEq(merkleTreeManagerV2.owner(), owner);
        assertEq(merkleTreeManagerV2.depth(), initialDepth);
        assertEq(merkleTreeManagerV2.bridge(), initialBridge);
        assertEq(merkleTreeManagerV2.bridgeSet(), initialBridgeSet);

        // Test new functionality
        assertEq(merkleTreeManagerV2.version(), "2.0.0");

        uint8[] memory operations = new uint8[](3);
        operations[0] = 1;
        operations[1] = 2;
        operations[2] = 3;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit MerkleTreeManager4UpgradeableV2.BatchOperationsExecuted(0, 3);
        merkleTreeManagerV2.batchOperations(0, operations);
    }

    // ============ Access Control Tests ============

    function test_OnlyOwnerCanUpgrade() public {
        RollupBridgeUpgradeableV2 rollupBridgeV2Impl = new RollupBridgeUpgradeableV2();

        vm.prank(attacker);
        vm.expectRevert();
        rollupBridge.upgradeTo(address(rollupBridgeV2Impl));

        MerkleTreeManager4UpgradeableV2 merkleTreeManagerV2Impl = new MerkleTreeManager4UpgradeableV2();

        vm.prank(attacker);
        vm.expectRevert();
        merkleTreeManager.upgradeTo(address(merkleTreeManagerV2Impl));
    }

    // ============ Storage Layout Tests ============

    function test_StorageLayoutPreservation() public {
        // Setup initial state with complex data
        vm.startPrank(owner);
        rollupBridge.authorizeCreator(user1);
        rollupBridge.authorizeCreator(user2);
        vm.stopPrank();

        // Create a channel with deposits
        vm.startPrank(user1);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = makeAddr("l2user1");
        l2PublicKeys[1] = makeAddr("l2user2");
        l2PublicKeys[2] = makeAddr("l2user3");

        uint128[] memory preprocessedPart1 = new uint128[](2);
        preprocessedPart1[0] = 100;
        preprocessedPart1[1] = 200;

        uint256[] memory preprocessedPart2 = new uint256[](2);
        preprocessedPart2[0] = 300;
        preprocessedPart2[1] = 400;

        uint256 channelId = rollupBridge.openChannel(
            address(token),
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            2 hours,
            bytes32(uint256(456))
        );

        // Approve and deposit tokens
        token.approve(address(rollupBridgeProxy), 100 ether);
        rollupBridge.depositToken(channelId, address(token), 50 ether);

        vm.stopPrank();

        // Store pre-upgrade state
        (
            address targetContract,
            IRollupBridge.ChannelState state,
            uint256 participantCount,
            bytes32 initialRoot,
            bytes32 finalRoot
        ) = rollupBridge.getChannelInfo(channelId);

        uint256 deposit = rollupBridge.getParticipantDeposit(channelId, user1);
        uint256 nextChannelId = rollupBridge.nextChannelId();
        bool isAuthorizedUser1 = rollupBridge.isAuthorizedCreator(user1);
        bool isAuthorizedUser2 = rollupBridge.isAuthorizedCreator(user2);
        bool isLeader = rollupBridge.isChannelLeader(user1);

        // Upgrade contract
        RollupBridgeUpgradeableV2 rollupBridgeV2Impl = new RollupBridgeUpgradeableV2();

        vm.prank(owner);
        rollupBridge.upgradeTo(address(rollupBridgeV2Impl));

        RollupBridgeUpgradeableV2 rollupBridgeV2 = RollupBridgeUpgradeableV2(payable(address(rollupBridgeProxy)));

        // Verify all state preserved after upgrade
        (
            address newTargetContract,
            IRollupBridge.ChannelState newState,
            uint256 newParticipantCount,
            bytes32 newInitialRoot,
            bytes32 newFinalRoot
        ) = rollupBridgeV2.getChannelInfo(channelId);

        assertEq(newTargetContract, targetContract);
        assertEq(uint256(newState), uint256(state));
        assertEq(newParticipantCount, participantCount);
        assertEq(newInitialRoot, initialRoot);
        assertEq(newFinalRoot, finalRoot);

        assertEq(rollupBridgeV2.getParticipantDeposit(channelId, user1), deposit);
        assertEq(rollupBridgeV2.nextChannelId(), nextChannelId);
        assertEq(rollupBridgeV2.isAuthorizedCreator(user1), isAuthorizedUser1);
        assertEq(rollupBridgeV2.isAuthorizedCreator(user2), isAuthorizedUser2);
        assertEq(rollupBridgeV2.isChannelLeader(user1), isLeader);

        // Verify contracts still work after upgrade
        vm.startPrank(user2);
        token.approve(address(rollupBridgeProxy), 100 ether);
        rollupBridgeV2.depositToken(channelId, address(token), 25 ether);
        assertEq(rollupBridgeV2.getParticipantDeposit(channelId, user2), 25 ether);
        vm.stopPrank();
    }

    // ============ Integration Tests ============

    function test_FullChannelLifecycleAfterUpgrade() public {
        // Upgrade both contracts first
        RollupBridgeUpgradeableV2 rollupBridgeV2Impl = new RollupBridgeUpgradeableV2();
        MerkleTreeManager4UpgradeableV2 merkleTreeManagerV2Impl = new MerkleTreeManager4UpgradeableV2();

        vm.startPrank(owner);
        rollupBridge.upgradeTo(address(rollupBridgeV2Impl));
        merkleTreeManager.upgradeTo(address(merkleTreeManagerV2Impl));

        RollupBridgeUpgradeableV2 rollupBridgeV2 = RollupBridgeUpgradeableV2(payable(address(rollupBridgeProxy)));
        MerkleTreeManager4UpgradeableV2 merkleTreeManagerV2 =
            MerkleTreeManager4UpgradeableV2(address(merkleTreeManagerProxy));

        // Authorize user1 as creator
        rollupBridgeV2.authorizeCreator(user1);
        vm.stopPrank();

        // Test full channel lifecycle with upgraded contracts
        vm.startPrank(user1);

        // Open channel
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = makeAddr("l2user1");
        l2PublicKeys[1] = makeAddr("l2user2");
        l2PublicKeys[2] = makeAddr("l2user3");

        uint128[] memory preprocessedPart1 = new uint128[](1);
        preprocessedPart1[0] = 1;

        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart2[0] = 1;

        uint256 channelId = rollupBridgeV2.openChannel(
            ETH_TOKEN_ADDRESS,
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            1 hours,
            bytes32(uint256(789))
        );

        // Deposit ETH
        rollupBridgeV2.depositETH{value: 1 ether}(channelId);

        vm.stopPrank();

        // Other users deposit
        vm.prank(user2);
        rollupBridgeV2.depositETH{value: 2 ether}(channelId);

        vm.prank(user3);
        rollupBridgeV2.depositETH{value: 1.5 ether}(channelId);

        // Initialize channel state
        vm.prank(user1);
        rollupBridgeV2.initializeChannelState(channelId);

        // Verify channel state
        (, IRollupBridge.ChannelState state,,,) = rollupBridgeV2.getChannelInfo(channelId);
        assertEq(uint256(state), uint256(IRollupBridge.ChannelState.Open));

        // Verify Merkle tree manager has users
        assertEq(merkleTreeManagerV2.getUserCount(channelId), 3);
        assertTrue(merkleTreeManagerV2.channelInitialized(channelId));

        // Test new V2 functionality
        assertEq(rollupBridgeV2.version(), "2.0.0");
        assertEq(merkleTreeManagerV2.version(), "2.0.0");
    }

    // ============ Verifier Update Tests ============

    function test_UpdateVerifier() public {
        // Deploy new mock verifier
        MockVerifier newVerifier = new MockVerifier();
        address oldVerifier = address(rollupBridge.zkVerifier());

        // Update verifier (owner only)
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit VerifierUpdated(oldVerifier, address(newVerifier));
        rollupBridge.updateVerifier(address(newVerifier));

        // Verify verifier was updated
        assertEq(address(rollupBridge.zkVerifier()), address(newVerifier));
        assertTrue(address(rollupBridge.zkVerifier()) != oldVerifier);
    }

    function test_UpdateVerifierOnlyOwner() public {
        MockVerifier newVerifier = new MockVerifier();

        // Non-owner cannot update verifier
        vm.prank(attacker);
        vm.expectRevert();
        rollupBridge.updateVerifier(address(newVerifier));

        // User cannot update verifier
        vm.prank(user1);
        vm.expectRevert();
        rollupBridge.updateVerifier(address(newVerifier));
    }

    function test_UpdateVerifierInvalidAddress() public {
        // Cannot set verifier to zero address
        vm.prank(owner);
        vm.expectRevert("Invalid verifier address");
        rollupBridge.updateVerifier(address(0));
    }

    function test_UpdateVerifierSameAddress() public {
        address currentVerifier = address(rollupBridge.zkVerifier());

        // Cannot update to same address
        vm.prank(owner);
        vm.expectRevert("Same verifier address");
        rollupBridge.updateVerifier(currentVerifier);
    }

    function test_VerifierUpdatePreservesState() public {
        // Setup initial state
        vm.prank(owner);
        rollupBridge.authorizeCreator(user1);

        // Deploy new verifier
        MockVerifier newVerifier = new MockVerifier();

        // Update verifier
        vm.prank(owner);
        rollupBridge.updateVerifier(address(newVerifier));

        // Verify state is preserved
        assertTrue(rollupBridge.isAuthorizedCreator(user1));
        assertEq(rollupBridge.nextChannelId(), 0);
        assertEq(rollupBridge.owner(), owner);
    }

    function test_VerifierUpdateAfterUpgrade() public {
        // First upgrade the contract
        RollupBridgeUpgradeableV2 rollupBridgeV2Impl = new RollupBridgeUpgradeableV2();

        vm.prank(owner);
        rollupBridge.upgradeTo(address(rollupBridgeV2Impl));

        RollupBridgeUpgradeableV2 rollupBridgeV2 = RollupBridgeUpgradeableV2(payable(address(rollupBridgeProxy)));

        // Then update verifier on upgraded contract
        MockVerifier newVerifier = new MockVerifier();
        address oldVerifier = address(rollupBridgeV2.zkVerifier());

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit VerifierUpdated(oldVerifier, address(newVerifier));
        rollupBridgeV2.updateVerifier(address(newVerifier));

        // Verify update worked
        assertEq(address(rollupBridgeV2.zkVerifier()), address(newVerifier));

        // Verify V2 functionality still works
        assertEq(rollupBridgeV2.version(), "2.0.0");
    }

    function test_V2VerifierEnhancements() public {
        // Upgrade to V2 first
        RollupBridgeUpgradeableV2 rollupBridgeV2Impl = new RollupBridgeUpgradeableV2();

        vm.prank(owner);
        rollupBridge.upgradeTo(address(rollupBridgeV2Impl));

        RollupBridgeUpgradeableV2 rollupBridgeV2 = RollupBridgeUpgradeableV2(payable(address(rollupBridgeProxy)));

        // Test V2 verifier info function
        (address currentVerifier, bool isValid) = rollupBridgeV2.getVerifierInfo();
        assertTrue(isValid);
        assertTrue(currentVerifier != address(0));

        // Test batch verifier update
        address[] memory newVerifiers = new address[](2);
        newVerifiers[0] = address(new MockVerifier());
        newVerifiers[1] = address(new MockVerifier());

        address oldVerifier = address(rollupBridgeV2.zkVerifier());

        vm.prank(owner);
        rollupBridgeV2.batchUpdateVerifiers(newVerifiers);

        // Verify verifier was updated to first in array
        assertEq(address(rollupBridgeV2.zkVerifier()), newVerifiers[0]);

        // Verify it's different from the old one
        assertTrue(address(rollupBridgeV2.zkVerifier()) != oldVerifier);
    }

    // ============ Gas Usage Tests ============

    function test_UpgradeGasCost() public {
        RollupBridgeUpgradeableV2 rollupBridgeV2Impl = new RollupBridgeUpgradeableV2();

        uint256 gasBefore = gasleft();

        vm.prank(owner);
        rollupBridge.upgradeTo(address(rollupBridgeV2Impl));

        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for RollupBridge upgrade:", gasUsed);

        // Upgrade should be reasonable (less than 200k gas)
        assertLt(gasUsed, 200_000);
    }

    receive() external payable {}
}
