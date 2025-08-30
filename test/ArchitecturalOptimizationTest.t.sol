// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/RollupBridgeV1.sol";
import "../src/RollupBridgeV2.sol";
import "../src/interface/IRollupBridge.sol";
import "../src/interface/IVerifier.sol";
import "../src/merkleTree/MerkleTreeManager4.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ArchitecturalOptimizationTest
 * @dev Test suite to verify major gas optimization through architectural redesign
 */
contract ArchitecturalOptimizationTest is Test {
    RollupBridgeV1 public originalBridge;
    RollupBridgeV2 public redesignedBridge;

    MerkleTreeManager4 public originalMtmanager;
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

        // Deploy original version with MerkleTreeManager
        originalMtmanager = new MerkleTreeManager4();
        RollupBridgeV1 originalImpl = new RollupBridgeV1();
        bytes memory originalInitData =
            abi.encodeCall(RollupBridgeV1.initialize, (address(verifier), address(originalMtmanager), owner));
        ERC1967Proxy originalProxy = new ERC1967Proxy(address(originalImpl), originalInitData);
        originalBridge = RollupBridgeV1(address(originalProxy));
        originalMtmanager.setBridge(address(originalBridge));

        // Deploy redesigned version with embedded Merkle operations
        RollupBridgeV2 redesignedImpl = new RollupBridgeV2();
        bytes memory redesignedInitData = abi.encodeCall(
            RollupBridgeV2.initialize,
            (address(verifier), address(0), owner) // No external MerkleTreeManager needed
        );
        ERC1967Proxy redesignedProxy = new ERC1967Proxy(address(redesignedImpl), redesignedInitData);
        redesignedBridge = RollupBridgeV2(address(redesignedProxy));

        originalBridge.authorizeCreator(leader);
        redesignedBridge.authorizeCreator(leader);

        // Fund accounts
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);

        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);
        token.mint(user3, 1000 ether);

        vm.stopPrank();
    }

    function testMajorArchitecturalOptimization() public {
        console.log("=== MAJOR ARCHITECTURAL OPTIMIZATION TEST ===");

        // Setup identical channels
        uint256 originalChannelId = _setupChannel(address(originalBridge));
        uint256 redesignedChannelId = _setupChannel(address(redesignedBridge));

        // Make identical deposits
        _makeDeposits(address(originalBridge), originalChannelId);
        _makeDeposits(address(redesignedBridge), redesignedChannelId);

        console.log("1. Testing functional equivalence...");

        // Measure gas for original approach
        uint256 originalGasBefore = gasleft();
        vm.prank(leader);
        originalBridge.initializeChannelState(originalChannelId);
        uint256 originalGasUsed = originalGasBefore - gasleft();

        // Measure gas for redesigned approach
        uint256 redesignedGasBefore = gasleft();
        vm.prank(leader);
        redesignedBridge.initializeChannelState(redesignedChannelId);
        uint256 redesignedGasUsed = redesignedGasBefore - gasleft();

        console.log("2. Verifying functional equivalence...");

        // Compare final results
        (,, uint256 originalParticipantCount, bytes32 originalInitialRoot,) =
            originalBridge.getChannelInfo(originalChannelId);
        (,, uint256 redesignedParticipantCount, bytes32 redesignedInitialRoot,) =
            redesignedBridge.getChannelInfo(redesignedChannelId);

        console.log("Original root: %s", vm.toString(originalInitialRoot));
        console.log("Redesigned root: %s", vm.toString(redesignedInitialRoot));

        // Verify functional equivalence
        assertEq(originalParticipantCount, redesignedParticipantCount, "Participant count mismatch");
        assertEq(originalInitialRoot, redesignedInitialRoot, "Root hashes must match!");

        console.log("SUCCESS: Both versions produce identical results!");

        console.log("3. Measuring gas improvements...");

        // Calculate savings
        uint256 gasSaved = originalGasUsed - redesignedGasUsed;
        uint256 percentSaved = (gasSaved * 100) / originalGasUsed;

        console.log("Original gas used: %d", originalGasUsed);
        console.log("Redesigned gas used: %d", redesignedGasUsed);
        console.log("Gas saved: %d (%d%% reduction)", gasSaved, percentSaved);

        // Verify significant gas savings
        assertGt(gasSaved, 200000, "Should save at least 200K gas through architectural redesign");
        assertGt(percentSaved, 25, "Should save at least 25% through architectural improvements");

        console.log("SUCCESS: Achieved %d%% gas reduction through architectural redesign!", percentSaved);
    }

    function testScalabilityWith5Users() public {
        console.log("=== SCALABILITY TEST: 5 USERS ===");

        // Setup 5-user channels
        uint256 originalChannelId = _setupChannelWithUsers(address(originalBridge), 5);
        uint256 redesignedChannelId = _setupChannelWithUsers(address(redesignedBridge), 5);

        // Make deposits for all users
        _makeDepositsForUsers(address(originalBridge), originalChannelId, 5);
        _makeDepositsForUsers(address(redesignedBridge), redesignedChannelId, 5);

        // Measure gas consumption
        uint256 originalGasBefore = gasleft();
        vm.prank(leader);
        originalBridge.initializeChannelState(originalChannelId);
        uint256 originalGasUsed = originalGasBefore - gasleft();

        uint256 redesignedGasBefore = gasleft();
        vm.prank(leader);
        redesignedBridge.initializeChannelState(redesignedChannelId);
        uint256 redesignedGasUsed = redesignedGasBefore - gasleft();

        uint256 gasSaved = originalGasUsed - redesignedGasUsed;
        uint256 percentSaved = (gasSaved * 100) / originalGasUsed;

        console.log("5 Users - Original: %d gas", originalGasUsed);
        console.log("5 Users - Redesigned: %d gas", redesignedGasUsed);
        console.log("5 Users - Saved: %d gas (%d%% reduction)", gasSaved, percentSaved);

        // Verify scaling benefits
        assertGt(gasSaved, 300000, "Should save even more gas with more users");
        assertGt(percentSaved, 25, "Should maintain significant percentage savings");

        console.log("SUCCESS: Architectural benefits scale with user count!");
    }

    function testScalabilityWith40Users() public {
        console.log("=== LARGE SCALE TEST: 40 USERS ===");

        // Deploy fresh instances to avoid any limits
        vm.startPrank(owner);

        MockVerifier freshVerifier = new MockVerifier();
        MockERC20 freshToken = new MockERC20();

        // Deploy fresh original version
        MerkleTreeManager4 freshOriginalMtmanager = new MerkleTreeManager4();
        RollupBridgeV1 freshOriginalImpl = new RollupBridgeV1();
        bytes memory freshOriginalInitData =
            abi.encodeCall(RollupBridgeV1.initialize, (address(freshVerifier), address(freshOriginalMtmanager), owner));
        ERC1967Proxy freshOriginalProxy = new ERC1967Proxy(address(freshOriginalImpl), freshOriginalInitData);
        RollupBridgeV1 freshOriginalBridge = RollupBridgeV1(address(freshOriginalProxy));
        freshOriginalMtmanager.setBridge(address(freshOriginalBridge));

        // Deploy fresh redesigned version
        RollupBridgeV2 freshRedesignedImpl = new RollupBridgeV2();
        bytes memory freshRedesignedInitData =
            abi.encodeCall(RollupBridgeV2.initialize, (address(freshVerifier), address(0), owner));
        ERC1967Proxy freshRedesignedProxy = new ERC1967Proxy(address(freshRedesignedImpl), freshRedesignedInitData);
        RollupBridgeV2 freshRedesignedBridge = RollupBridgeV2(address(freshRedesignedProxy));

        freshOriginalBridge.authorizeCreator(leader);
        freshRedesignedBridge.authorizeCreator(leader);

        vm.stopPrank();

        // Setup 40-user channels
        uint256 originalChannelId = _setupChannelWithUsers40(address(freshOriginalBridge), freshToken);
        uint256 redesignedChannelId = _setupChannelWithUsers40(address(freshRedesignedBridge), freshToken);

        // Make deposits for all 40 users
        _makeDepositsFor40Users(address(freshOriginalBridge), originalChannelId, freshToken);
        _makeDepositsFor40Users(address(freshRedesignedBridge), redesignedChannelId, freshToken);

        console.log("Setup complete. Measuring gas consumption...");

        // Measure gas consumption for original
        uint256 originalGasBefore = gasleft();
        vm.prank(leader);
        freshOriginalBridge.initializeChannelState(originalChannelId);
        uint256 originalGasUsed = originalGasBefore - gasleft();

        // Measure gas consumption for redesigned
        uint256 redesignedGasBefore = gasleft();
        vm.prank(leader);
        freshRedesignedBridge.initializeChannelState(redesignedChannelId);
        uint256 redesignedGasUsed = redesignedGasBefore - gasleft();

        // Calculate metrics
        uint256 gasSaved = originalGasUsed - redesignedGasUsed;
        uint256 percentSaved = (gasSaved * 100) / originalGasUsed;

        // Verify functional equivalence
        (,, uint256 originalParticipantCount, bytes32 originalRoot,) =
            freshOriginalBridge.getChannelInfo(originalChannelId);
        (,, uint256 redesignedParticipantCount, bytes32 redesignedRoot,) =
            freshRedesignedBridge.getChannelInfo(redesignedChannelId);

        assertEq(originalParticipantCount, 40, "Original should have 40 participants");
        assertEq(redesignedParticipantCount, 40, "Redesigned should have 40 participants");
        assertEq(originalRoot, redesignedRoot, "Root hashes must match for functional equivalence");

        console.log("=== 40 USERS SCALING RESULTS ===");
        console.log("Original gas used: %d", originalGasUsed);
        console.log("Redesigned gas used: %d", redesignedGasUsed);
        console.log("Gas saved: %d (%d%% reduction)", gasSaved, percentSaved);
        console.log("Gas per user (original): %d", originalGasUsed / 40);
        console.log("Gas per user (redesigned): %d", redesignedGasUsed / 40);
        console.log("Root hash (both): %s", vm.toString(originalRoot));

        // Verify significant savings even at scale
        assertGt(gasSaved, 1000000, "Should save at least 1M gas with 40 users");
        assertGt(percentSaved, 25, "Should maintain significant percentage savings at scale");

        console.log("SUCCESS: Architecture optimization scales effectively to 40 users!");
        console.log("Functional equivalence maintained at large scale!");
    }

    function testDetailedGasBreakdown() public {
        console.log("=== DETAILED GAS BREAKDOWN ANALYSIS ===");

        uint256 originalChannelId = _setupChannel(address(originalBridge));
        uint256 redesignedChannelId = _setupChannel(address(redesignedBridge));

        _makeDeposits(address(originalBridge), originalChannelId);
        _makeDeposits(address(redesignedBridge), redesignedChannelId);

        // Detailed analysis of where gas is saved
        console.log("Analyzing gas consumption patterns...");

        // Original approach breakdown
        console.log("\nOriginal approach operations:");
        console.log("- initializeChannel() external call");
        console.log("- setAddressPair() x3 external calls");
        console.log("- addUsers() external call with internal loop");
        console.log("- getCurrentRoot() external call");
        console.log("- Multiple cross-contract validations and modifiers");

        // Redesigned approach breakdown
        console.log("\nRedesigned approach operations:");
        console.log("- All operations embedded in single function");
        console.log("- No external contract calls");
        console.log("- Direct storage access");
        console.log("- Optimized single loop with batched operations");

        // Run the test
        uint256 originalGasBefore = gasleft();
        vm.prank(leader);
        originalBridge.initializeChannelState(originalChannelId);
        uint256 originalGasUsed = originalGasBefore - gasleft();

        uint256 redesignedGasBefore = gasleft();
        vm.prank(leader);
        redesignedBridge.initializeChannelState(redesignedChannelId);
        uint256 redesignedGasUsed = redesignedGasBefore - gasleft();

        console.log("\nGas Usage Results:");
        console.log("Original (external calls): %d gas", originalGasUsed);
        console.log("Redesigned (embedded): %d gas", redesignedGasUsed);

        uint256 gasSaved = originalGasUsed - redesignedGasUsed;
        console.log("Total gas saved: %d", gasSaved);

        // Estimate breakdown of savings
        uint256 estimatedCallOverhead = gasSaved / 2; // Approximately half from eliminating external calls
        uint256 estimatedOptimizations = gasSaved - estimatedCallOverhead;

        console.log("Estimated savings from eliminating external calls: ~%d gas", estimatedCallOverhead);
        console.log("Estimated savings from optimizations: ~%d gas", estimatedOptimizations);

        assertGt(gasSaved, 200000, "Total architectural savings should be substantial");
    }

    function testEdgeCaseCompatibility() public {
        console.log("=== EDGE CASE COMPATIBILITY TEST ===");

        // Test minimum participants
        uint256 originalChannelId = _setupChannel(address(originalBridge));
        uint256 redesignedChannelId = _setupChannel(address(redesignedBridge));

        _makeDeposits(address(originalBridge), originalChannelId);
        _makeDeposits(address(redesignedBridge), redesignedChannelId);

        // Test with minimum participants (3)
        vm.prank(leader);
        originalBridge.initializeChannelState(originalChannelId);

        vm.prank(leader);
        redesignedBridge.initializeChannelState(redesignedChannelId);

        // Verify both work with edge cases
        (,, uint256 originalCount, bytes32 originalRoot,) = originalBridge.getChannelInfo(originalChannelId);
        (,, uint256 redesignedCount, bytes32 redesignedRoot,) = redesignedBridge.getChannelInfo(redesignedChannelId);

        assertEq(originalCount, 3, "Original should handle minimum participants");
        assertEq(redesignedCount, 3, "Redesigned should handle minimum participants");
        assertEq(originalRoot, redesignedRoot, "Both should produce same results for edge cases");

        console.log("SUCCESS: Edge case compatibility verified!");
    }

    function testComprehensiveComparison() public {
        console.log("=== COMPREHENSIVE ARCHITECTURAL OPTIMIZATION ANALYSIS ===");

        // Deploy fresh instances to avoid channel limit issues
        vm.startPrank(owner);

        MockVerifier freshVerifier = new MockVerifier();
        MockERC20 freshToken = new MockERC20();

        // Deploy fresh original version
        MerkleTreeManager4 freshOriginalMtmanager = new MerkleTreeManager4();
        RollupBridgeV1 freshOriginalImpl = new RollupBridgeV1();
        bytes memory freshOriginalInitData =
            abi.encodeCall(RollupBridgeV1.initialize, (address(freshVerifier), address(freshOriginalMtmanager), owner));
        ERC1967Proxy freshOriginalProxy = new ERC1967Proxy(address(freshOriginalImpl), freshOriginalInitData);
        RollupBridgeV1 freshOriginalBridge = RollupBridgeV1(address(freshOriginalProxy));
        freshOriginalMtmanager.setBridge(address(freshOriginalBridge));

        // Deploy fresh redesigned version
        RollupBridgeV2 freshRedesignedImpl = new RollupBridgeV2();
        bytes memory freshRedesignedInitData =
            abi.encodeCall(RollupBridgeV2.initialize, (address(freshVerifier), address(0), owner));
        ERC1967Proxy freshRedesignedProxy = new ERC1967Proxy(address(freshRedesignedImpl), freshRedesignedInitData);
        RollupBridgeV2 freshRedesignedBridge = RollupBridgeV2(address(freshRedesignedProxy));

        freshOriginalBridge.authorizeCreator(leader);
        freshRedesignedBridge.authorizeCreator(leader);

        vm.stopPrank();

        // Setup channels and test with fresh instances
        uint256 originalChannelId = _setupChannelWithFreshBridge(address(freshOriginalBridge), freshToken);
        uint256 redesignedChannelId = _setupChannelWithFreshBridge(address(freshRedesignedBridge), freshToken);

        _makeDepositsWithFreshToken(address(freshOriginalBridge), originalChannelId, freshToken);
        _makeDepositsWithFreshToken(address(freshRedesignedBridge), redesignedChannelId, freshToken);

        // Test gas optimization
        uint256 originalGasBefore = gasleft();
        vm.prank(leader);
        freshOriginalBridge.initializeChannelState(originalChannelId);
        uint256 originalGasUsed = originalGasBefore - gasleft();

        uint256 redesignedGasBefore = gasleft();
        vm.prank(leader);
        freshRedesignedBridge.initializeChannelState(redesignedChannelId);
        uint256 redesignedGasUsed = redesignedGasBefore - gasleft();

        // Verify results
        (,, uint256 originalParticipantCount, bytes32 originalRoot,) =
            freshOriginalBridge.getChannelInfo(originalChannelId);
        (,, uint256 redesignedParticipantCount, bytes32 redesignedRoot,) =
            freshRedesignedBridge.getChannelInfo(redesignedChannelId);

        assertEq(originalParticipantCount, redesignedParticipantCount, "Participant count mismatch");
        assertEq(originalRoot, redesignedRoot, "Root hashes must match!");

        uint256 gasSaved = originalGasUsed - redesignedGasUsed;
        uint256 percentSaved = (gasSaved * 100) / originalGasUsed;

        assertGt(gasSaved, 200000, "Should save significant gas");
        assertGt(percentSaved, 25, "Should save significant percentage");

        console.log("\n=== FINAL ARCHITECTURE OPTIMIZATION RESULTS ===");
        console.log("Functional equivalence: VERIFIED");
        console.log("Major gas optimization: ACHIEVED (%d%% reduction)", percentSaved);
        console.log("Gas saved: %d", gasSaved);
        console.log("Architectural redesign: SUCCESSFUL");
    }

    function _setupChannelWithFreshBridge(address bridge, MockERC20 freshToken) internal returns (uint256 channelId) {
        address[] memory participants = new address[](3);
        address[] memory l2PublicKeys = new address[](3);

        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;

        // Fund users with fresh token
        freshToken.mint(user1, 1000 ether);
        freshToken.mint(user2, 1000 ether);
        freshToken.mint(user3, 1000 ether);

        uint128[] memory preprocessedPart1 = new uint128[](1);
        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart1[0] = 12345;
        preprocessedPart2[0] = 67890;

        vm.prank(leader);
        channelId = IRollupBridge(bridge).openChannel(
            address(freshToken),
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            3600,
            bytes32(uint256(1))
        );
    }

    function _makeDepositsWithFreshToken(address bridge, uint256 channelId, MockERC20 freshToken) internal {
        address[3] memory users = [user1, user2, user3];

        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(users[i]);
            freshToken.approve(bridge, DEPOSIT_AMOUNT);
            IRollupBridge(bridge).depositToken(channelId, address(freshToken), DEPOSIT_AMOUNT);
            vm.stopPrank();
        }
    }

    // ========== HELPER FUNCTIONS ==========

    function _setupChannel(address bridge) internal returns (uint256 channelId) {
        return _setupChannelWithUsers(bridge, 3);
    }

    function _setupChannelWithUsers(address bridge, uint256 userCount) internal returns (uint256 channelId) {
        address[] memory participants = new address[](userCount);
        address[] memory l2PublicKeys = new address[](userCount);

        // Setup basic 3 users
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;
        l2PublicKeys[0] = l2User1;
        l2PublicKeys[1] = l2User2;
        l2PublicKeys[2] = l2User3;

        // Add additional users if needed
        if (userCount > 3) {
            for (uint256 i = 3; i < userCount; i++) {
                participants[i] = address(uint160(100 + i));
                l2PublicKeys[i] = address(uint160(200 + i));

                // Fund additional users
                vm.deal(participants[i], 1000 ether);
                token.mint(participants[i], 1000 ether);
            }
        }

        uint128[] memory preprocessedPart1 = new uint128[](1);
        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart1[0] = 12345;
        preprocessedPart2[0] = 67890;

        vm.prank(leader);
        channelId = IRollupBridge(bridge).openChannel(
            address(token), participants, l2PublicKeys, preprocessedPart1, preprocessedPart2, 3600, bytes32(uint256(1))
        );
    }

    function _makeDeposits(address bridge, uint256 channelId) internal {
        _makeDepositsForUsers(bridge, channelId, 3);
    }

    function _makeDepositsForUsers(address bridge, uint256 channelId, uint256 userCount) internal {
        address[] memory users = new address[](userCount);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        // Add additional users if needed
        if (userCount > 3) {
            for (uint256 i = 3; i < userCount; i++) {
                users[i] = address(uint160(100 + i));
            }
        }

        for (uint256 i = 0; i < userCount; i++) {
            vm.startPrank(users[i]);
            token.approve(bridge, DEPOSIT_AMOUNT);
            IRollupBridge(bridge).depositToken(channelId, address(token), DEPOSIT_AMOUNT);
            vm.stopPrank();
        }
    }

    function _setupChannelWithUsers40(address bridge, MockERC20 freshToken) internal returns (uint256 channelId) {
        address[] memory participants = new address[](40);
        address[] memory l2PublicKeys = new address[](40);

        // Setup all 40 participants
        for (uint256 i = 0; i < 40; i++) {
            participants[i] = address(uint160(1000 + i));
            l2PublicKeys[i] = address(uint160(2000 + i));

            // Fund each user
            vm.deal(participants[i], 1000 ether);
            freshToken.mint(participants[i], 1000 ether);
        }

        uint128[] memory preprocessedPart1 = new uint128[](1);
        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart1[0] = 12345;
        preprocessedPart2[0] = 67890;

        vm.prank(leader);
        channelId = IRollupBridge(bridge).openChannel(
            address(freshToken),
            participants,
            l2PublicKeys,
            preprocessedPart1,
            preprocessedPart2,
            3600,
            bytes32(uint256(1))
        );
    }

    function _makeDepositsFor40Users(address bridge, uint256 channelId, MockERC20 freshToken) internal {
        for (uint256 i = 0; i < 40; i++) {
            address user = address(uint160(1000 + i));
            vm.startPrank(user);
            freshToken.approve(bridge, DEPOSIT_AMOUNT);
            IRollupBridge(bridge).depositToken(channelId, address(freshToken), DEPOSIT_AMOUNT);
            vm.stopPrank();
        }
    }
}

// Mock contracts
contract MockVerifier is IVerifier {
    function verify(
        uint128[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external pure override returns (bool) {
        return true;
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
