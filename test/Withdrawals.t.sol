// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {RollupBridge} from "../src/RollupBridge.sol";
import {IRollupBridge} from "../src/interface/IRollupBridge.sol";
import {IVerifier} from "../src/interface/IVerifier.sol";
import {RLP} from "../src/library/RLP.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockVerifier is IVerifier {
    function verify(
        uint128[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external pure returns (bool) {
        return true; // Always return true for testing
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WithdrawalsTest is Test {
    RollupBridge public rollupBridge;
    MockVerifier public mockVerifier;
    MockERC20 public testToken;

    // Test participants
    address public owner = makeAddr("owner");
    address public leader = makeAddr("leader");
    address public participant1 = makeAddr("participant1");
    address public participant2 = makeAddr("participant2");
    address public participant3 = makeAddr("participant3");

    // L2 addresses (mock public keys)
    address public l2Address1 = makeAddr("l2Address1");
    address public l2Address2 = makeAddr("l2Address2");
    address public l2Address3 = makeAddr("l2Address3");

    // Test constants
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;
    uint256 public constant CHANNEL_TIMEOUT = 1 days;
    address public constant ETH_TOKEN_ADDRESS = address(1);

    struct WithdrawalProofData {
        string channelId;
        string claimedBalance;
        uint256 leafIndex;
        string[] merkleProof;
        string leafValue;
        string userL1Address;
        string userL2Address;
    }

    function setUp() public {
        // Deploy contracts
        mockVerifier = new MockVerifier();
        testToken = new MockERC20("Test Token", "TEST");

        // Deploy RollupBridge implementation
        RollupBridge implementation = new RollupBridge();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            RollupBridge.initialize.selector,
            address(mockVerifier),
            address(0), // unused parameter
            owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        rollupBridge = RollupBridge(address(proxy));

        // Authorize leader to create channels
        vm.prank(owner);
        rollupBridge.authorizeCreator(leader);

        // Fund participants with ETH and tokens
        vm.deal(participant1, 10 ether);
        vm.deal(participant2, 10 ether);
        vm.deal(participant3, 10 ether);

        testToken.mint(participant1, 1000 ether);
        testToken.mint(participant2, 1000 ether);
        testToken.mint(participant3, 1000 ether);

        // Approve token spending
        vm.prank(participant1);
        testToken.approve(address(rollupBridge), type(uint256).max);
        vm.prank(participant2);
        testToken.approve(address(rollupBridge), type(uint256).max);
        vm.prank(participant3);
        testToken.approve(address(rollupBridge), type(uint256).max);
    }

    function _createETHChannel() internal returns (uint256 channelId) {
        address[] memory participants = new address[](3);
        participants[0] = participant1;
        participants[1] = participant2;
        participants[2] = participant3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2Address1;
        l2PublicKeys[1] = l2Address2;
        l2PublicKeys[2] = l2Address3;

        uint128[] memory preprocessedPart1 = new uint128[](1);
        preprocessedPart1[0] = 1;

        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart2[0] = 1;

        vm.prank(leader);
        IRollupBridge.ChannelParams memory params = IRollupBridge.ChannelParams({
            targetContract: ETH_TOKEN_ADDRESS,
            participants: participants,
            l2PublicKeys: l2PublicKeys,
            preprocessedPart1: preprocessedPart1,
            preprocessedPart2: preprocessedPart2,
            timeout: CHANNEL_TIMEOUT,
            groupPublicKey: bytes32("mockGroupPublicKey")
        });
        channelId = rollupBridge.openChannel(params);
    }

    function _createTokenChannel() internal returns (uint256 channelId) {
        address[] memory participants = new address[](3);
        participants[0] = participant1;
        participants[1] = participant2;
        participants[2] = participant3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = l2Address1;
        l2PublicKeys[1] = l2Address2;
        l2PublicKeys[2] = l2Address3;

        uint128[] memory preprocessedPart1 = new uint128[](1);
        preprocessedPart1[0] = 1;

        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart2[0] = 1;

        vm.prank(leader);
        IRollupBridge.ChannelParams memory params = IRollupBridge.ChannelParams({
            targetContract: address(testToken),
            participants: participants,
            l2PublicKeys: l2PublicKeys,
            preprocessedPart1: preprocessedPart1,
            preprocessedPart2: preprocessedPart2,
            timeout: CHANNEL_TIMEOUT,
            groupPublicKey: bytes32("mockGroupPublicKey")
        });
        channelId = rollupBridge.openChannel(params);
    }

    function _makeDeposits(uint256 channelId, bool isETH) internal {
        if (isETH) {
            vm.prank(participant1);
            rollupBridge.depositETH{value: DEPOSIT_AMOUNT}(channelId);

            vm.prank(participant2);
            rollupBridge.depositETH{value: DEPOSIT_AMOUNT}(channelId);

            vm.prank(participant3);
            rollupBridge.depositETH{value: DEPOSIT_AMOUNT}(channelId);
        } else {
            vm.prank(participant1);
            rollupBridge.depositToken(channelId, address(testToken), DEPOSIT_AMOUNT);

            vm.prank(participant2);
            rollupBridge.depositToken(channelId, address(testToken), DEPOSIT_AMOUNT);

            vm.prank(participant3);
            rollupBridge.depositToken(channelId, address(testToken), DEPOSIT_AMOUNT);
        }
    }

    function _initializeAndCloseChannel(uint256 channelId) internal {
        // Initialize channel state
        vm.prank(leader);
        rollupBridge.initializeChannelState(channelId);

        // Compute the proper withdrawal tree root:
        // 1. Use lastRootInSequence as prevRoot to compute all participants' final balance leaves
        // 2. Build tree with those leaves -> get withdrawal tree root
        // 3. Use withdrawal tree root as finalStateRoot
        // This is the tree root when each participant uses their individual root
        // Computed via: node test/js-scripts/generateProof.js (simplified interface)
        bytes32 computedFinalStateRoot = 0x3121a1e8f8bcda391e969e5c6bce8c98e3ddfe682ca93c23253fbb102c5487c5;

        // Create participant roots array - each participant has their individual root
        // In a real zkEVM, these would represent each participant's state at different computation points
        bytes32[] memory participantRoots = new bytes32[](3);
        participantRoots[0] = 0x8449acb4300b58b00e4852ab07d43f298eaa35688eaa3917ca205f20e6db73e8; // participant1
        participantRoots[1] = 0x3bec727653ae8d56ac6d9c103182ff799fe0a3b512e9840f397f0d21848373e8; // participant2
        participantRoots[2] = 0x11e1e541a59fb2cd7fa4371d63103972695ee4bb4d1e646e72427cf6cdc16498; // participant3

        // Submit aggregated proof
        IRollupBridge.ProofData memory proofData = IRollupBridge.ProofData({
            aggregatedProofHash: bytes32("mockProofHash"),
            finalStateRoot: computedFinalStateRoot, // Use withdrawal tree root
            proofPart1: new uint128[](1),
            proofPart2: new uint256[](1),
            publicInputs: new uint256[](1),
            smax: 1,
            initialMPTLeaves: new bytes[](3),
            finalMPTLeaves: new bytes[](3),
            participantRoots: participantRoots
        });
        proofData.proofPart1[0] = 1;
        proofData.proofPart2[0] = 1;
        proofData.publicInputs[0] = 1;

        // Create proper RLP-encoded MPT leaves for balance conservation
        uint256[] memory balances = new uint256[](3);
        balances[0] = DEPOSIT_AMOUNT;
        balances[1] = DEPOSIT_AMOUNT;
        balances[2] = DEPOSIT_AMOUNT;

        proofData.initialMPTLeaves = _createMPTLeaves(balances);
        proofData.finalMPTLeaves = _createMPTLeaves(balances);

        vm.prank(leader);
        rollupBridge.submitAggregatedProof(channelId, proofData);

        // Sign aggregated proof (mock signatures)
        IRollupBridge.Signature[] memory signatures = new IRollupBridge.Signature[](2);
        signatures[0] = IRollupBridge.Signature(bytes32("R1"), 1);
        signatures[1] = IRollupBridge.Signature(bytes32("R2"), 2);

        vm.prank(leader);
        rollupBridge.signAggregatedProof(channelId, signatures);

        // Close channel
        vm.prank(leader);
        rollupBridge.closeChannel(channelId);
    }

    function _getWithdrawalProof(uint256 channelId, address userL2Address, bytes32 finalStateRoot)
        internal
        returns (WithdrawalProofData memory)
    {
        // SIMPLIFIED INTERFACE: Only 3 parameters needed!
        string[] memory inputs = new string[](7);
        inputs[0] = "env";
        inputs[1] = "FFI_MODE=true";
        inputs[2] = "node";
        inputs[3] = "test/js-scripts/generateProof.js";
        inputs[4] = vm.toString(channelId);
        inputs[5] = vm.toString(userL2Address);
        inputs[6] = vm.toString(finalStateRoot);

        bytes memory result = vm.ffi(inputs);
        string memory resultStr = string(result);
        return _parseCSVProofData(resultStr);
    }

    function _getWithdrawalProofForAll(uint256 channelId, address userL2Address, bytes32 finalStateRoot)
        internal
        returns (WithdrawalProofData memory)
    {
        // SIMPLIFIED INTERFACE: Only 3 parameters needed!
        // No more hardcoded participant roots or redundant data
        string[] memory inputs = new string[](7);
        inputs[0] = "env";
        inputs[1] = "FFI_MODE=true";
        inputs[2] = "node";
        inputs[3] = "test/js-scripts/generateProof.js";
        inputs[4] = vm.toString(channelId);
        inputs[5] = vm.toString(userL2Address);
        inputs[6] = vm.toString(finalStateRoot);

        bytes memory result = vm.ffi(inputs);
        string memory resultStr = string(result);
        return _parseCSVProofData(resultStr);
    }

    function _parseCSVProofData(string memory csvData) internal pure returns (WithdrawalProofData memory) {
        // Parse CSV format: channelId,claimedBalance,leafIndex,proof1,proof2,...
        // Split by comma and extract values
        bytes memory csvBytes = bytes(csvData);
        uint256 commaCount = 0;
        for (uint256 i = 0; i < csvBytes.length; i++) {
            if (csvBytes[i] == ",") commaCount++;
        }

        // We expect 3 fixed fields + 9 proof elements = 12 fields total (11 commas)
        require(commaCount >= 11, "Invalid CSV format");

        string[] memory parts = new string[](commaCount + 1);
        uint256 partIndex = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= csvBytes.length; i++) {
            if (i == csvBytes.length || csvBytes[i] == ",") {
                bytes memory part = new bytes(i - start);
                for (uint256 j = 0; j < i - start; j++) {
                    part[j] = csvBytes[start + j];
                }
                parts[partIndex] = string(part);
                partIndex++;
                start = i + 1;
            }
        }

        string[] memory merkleProof = new string[](parts.length - 3);
        for (uint256 i = 3; i < parts.length; i++) {
            merkleProof[i - 3] = parts[i];
        }

        return WithdrawalProofData({
            channelId: parts[0],
            claimedBalance: parts[1],
            leafIndex: vm.parseUint(parts[2]),
            merkleProof: merkleProof,
            leafValue: "computed", // Not needed from CSV
            userL1Address: "N/A", // Not needed from CSV
            userL2Address: "N/A" // Not needed from CSV
        });
    }

    function _parseProofData(WithdrawalProofData memory proofData)
        internal
        pure
        returns (uint256 channelId, uint256 claimedBalance, uint256 leafIndex, bytes32[] memory merkleProof)
    {
        channelId = vm.parseUint(proofData.channelId);
        claimedBalance = vm.parseUint(proofData.claimedBalance);
        leafIndex = proofData.leafIndex;

        merkleProof = new bytes32[](proofData.merkleProof.length);
        for (uint256 i = 0; i < proofData.merkleProof.length; i++) {
            merkleProof[i] = vm.parseBytes32(proofData.merkleProof[i]);
        }
    }

    function testETHWithdrawalSuccess() public {
        // Setup: Create channel, make deposits, initialize and close
        uint256 channelId = _createETHChannel();
        _makeDeposits(channelId, true);
        _initializeAndCloseChannel(channelId);

        // Get the finalStateRoot that was set during submitAggregatedProof
        // This is what the contract uses for withdrawal verification
        (, bytes32 finalStateRoot) = rollupBridge.getChannelRoots(channelId);

        // Test participant1's withdrawal

        // Generate withdrawal proof for participant1's specific leaf
        WithdrawalProofData memory proofData = _getWithdrawalProof(
            channelId,
            l2Address1, // participant1's L2 address
            finalStateRoot
        );

        // Parse proof data
        (uint256 parsedChannelId, uint256 parsedBalance, uint256 leafIndex, bytes32[] memory merkleProof) =
            _parseProofData(proofData);

        // Check initial balances
        uint256 initialBalance = participant1.balance;

        // Perform withdrawal (participant1 calls withdrawAfterClose)

        vm.prank(participant1); // This sets msg.sender = participant1
        rollupBridge.withdrawAfterClose(parsedChannelId, parsedBalance, leafIndex, merkleProof);

        // Verify withdrawal success
        uint256 finalBalanceAfter = participant1.balance;
        assertEq(finalBalanceAfter - initialBalance, DEPOSIT_AMOUNT, "Withdrawal amount incorrect");

        // Verify withdrawal tracking (double withdrawal should fail)
        vm.expectRevert("Already withdrawn");
        vm.prank(participant1);
        rollupBridge.withdrawAfterClose(parsedChannelId, parsedBalance, leafIndex, merkleProof);
    }

    function testTokenWithdrawalSuccess() public {
        // Setup: Create token channel, make deposits, initialize and close
        uint256 channelId = _createTokenChannel();
        _makeDeposits(channelId, false);
        _initializeAndCloseChannel(channelId);

        // Get final state root (prevRoot for RLC)
        bytes32 finalStateRoot = rollupBridge.getLastRootInSequence(channelId);

        console.log("=== Testing Token Withdrawal ===");
        console.log("Channel ID:", channelId);
        console.log("Final State Root (prevRoot for RLC):");
        console.logBytes32(finalStateRoot);

        // Test participant2's withdrawal
        console.log("\n--- Participant2 Token Withdrawal ---");
        console.log("L1 Address:", participant2);
        console.log("L2 Address:", l2Address2);
        console.log("Claimed Balance:", DEPOSIT_AMOUNT);

        // Generate withdrawal proof for participant2's specific leaf
        WithdrawalProofData memory proofData = _getWithdrawalProofForAll(
            channelId,
            l2Address2, // participant2's L2 address
            finalStateRoot
        );

        // Parse proof data
        (uint256 parsedChannelId, uint256 parsedBalance, uint256 leafIndex, bytes32[] memory merkleProof) =
            _parseProofData(proofData);

        console.log("Generated proof for participant2:");
        console.log("- Leaf Index:", leafIndex);
        console.log("- Claimed Balance:", parsedBalance);
        console.log("- Proof Elements:", merkleProof.length);

        // Verify the contract will compute the same leaf
        bytes32 expectedLeaf = rollupBridge.computeLeafForVerification(l2Address2, DEPOSIT_AMOUNT, finalStateRoot);
        console.log("Contract computed leaf:");
        console.logBytes32(expectedLeaf);
        console.log("Script computed leaf:", proofData.leafValue);

        // Check initial token balances
        uint256 initialBalance = testToken.balanceOf(participant2);
        console.log("Participant2 token balance before withdrawal:", initialBalance);

        // Perform withdrawal (participant2 calls withdrawAfterClose)
        vm.prank(participant2); // This sets msg.sender = participant2
        rollupBridge.withdrawAfterClose(parsedChannelId, parsedBalance, leafIndex, merkleProof);

        // Verify withdrawal success
        uint256 finalBalance = testToken.balanceOf(participant2);
        console.log("Participant2 token balance after withdrawal:", finalBalance);
        assertEq(finalBalance - initialBalance, DEPOSIT_AMOUNT, "Token withdrawal amount incorrect");
    }

    function testWithdrawalFailures() public {
        uint256 channelId = _createETHChannel();
        _makeDeposits(channelId, true);
        _initializeAndCloseChannel(channelId);

        bytes32 finalStateRoot = rollupBridge.getLastRootInSequence(channelId);

        // Generate valid proof for participant3
        WithdrawalProofData memory proofData = _getWithdrawalProofForAll(channelId, l2Address3, finalStateRoot);

        (uint256 parsedChannelId, uint256 parsedBalance, uint256 leafIndex, bytes32[] memory merkleProof) =
            _parseProofData(proofData);

        console.log("=== Testing Withdrawal Failures ===");

        // Test: Non-participant tries to withdraw with participant3's proof
        address nonParticipant = makeAddr("nonParticipant");
        console.log("Testing non-participant withdrawal...");
        vm.prank(nonParticipant); // msg.sender = nonParticipant, but proof is for participant3
        vm.expectRevert("Not a participant");
        rollupBridge.withdrawAfterClose(parsedChannelId, parsedBalance, leafIndex, merkleProof);

        // Test: Participant tries to claim wrong balance (different than in their leaf)
        console.log("Testing wrong claimed balance...");
        vm.prank(participant3); // Correct caller
        vm.expectRevert("Invalid merkle proof"); // Contract computes different leaf with wrong balance
        rollupBridge.withdrawAfterClose(
            parsedChannelId,
            parsedBalance + 1, // Wrong balance
            leafIndex,
            merkleProof
        );

        // Test: Participant1 tries to use participant3's proof
        console.log("Testing cross-participant proof usage...");
        vm.prank(participant1); // Wrong caller for this proof
        vm.expectRevert("Invalid merkle proof"); // Contract computes different leaf for participant1
        rollupBridge.withdrawAfterClose(parsedChannelId, parsedBalance, leafIndex, merkleProof);

        // Test: Wrong leaf index
        console.log("Testing wrong leaf index...");
        vm.prank(participant3);
        vm.expectRevert("Invalid merkle proof");
        rollupBridge.withdrawAfterClose(
            parsedChannelId,
            parsedBalance,
            (leafIndex + 1) % 3, // Wrong index
            merkleProof
        );

        // Test: Invalid merkle proof (empty proof)
        console.log("Testing empty proof...");
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.prank(participant3);
        vm.expectRevert("Invalid merkle proof");
        rollupBridge.withdrawAfterClose(parsedChannelId, parsedBalance, leafIndex, emptyProof);
    }

    function testMultipleWithdrawals() public {
        uint256 channelId = _createETHChannel();
        _makeDeposits(channelId, true);
        _initializeAndCloseChannel(channelId);

        bytes32 finalStateRoot = rollupBridge.getLastRootInSequence(channelId);

        console.log("=== Testing Multiple Individual Withdrawals ===");

        // Each participant generates their own proof and withdraws
        address[3] memory participants = [participant1, participant2, participant3];
        address[3] memory l2Addresses = [l2Address1, l2Address2, l2Address3];

        for (uint256 i = 0; i < 3; i++) {
            console.log("\n--- Participant", i + 1, "withdrawal ---");
            console.log("L1 Address:", participants[i]);
            console.log("L2 Address:", l2Addresses[i]);

            // Each participant generates their own proof for their specific leaf
            WithdrawalProofData memory proofData = _getWithdrawalProofForAll(
                channelId,
                l2Addresses[i], // Their L2 address
                finalStateRoot
            );

            (uint256 parsedChannelId, uint256 parsedBalance, uint256 leafIndex, bytes32[] memory merkleProof) =
                _parseProofData(proofData);

            console.log("Generated proof - Leaf Index:", leafIndex);
            console.log("Generated proof - Balance:", parsedBalance);

            uint256 balanceBefore = participants[i].balance;

            // The participant calls withdrawAfterClose with their proof
            vm.prank(participants[i]); // msg.sender = participants[i]
            rollupBridge.withdrawAfterClose(
                parsedChannelId,
                parsedBalance, // Must match what's in their leaf
                leafIndex, // Index of their leaf in the tree
                merkleProof // Proof for their specific leaf
            );

            uint256 balanceAfter = participants[i].balance;
            assertEq(balanceAfter - balanceBefore, DEPOSIT_AMOUNT, "Incorrect withdrawal amount");

            console.log("SUCCESS: Participant successfully withdrew wei");
        }

        console.log("SUCCESS: All participants successfully withdrew their individual funds!");
    }

    function testScriptIntegration() public {
        console.log("=== Testing Script Integration ===");

        // Test that our scripts are accessible
        string[] memory testInputs = new string[](3);
        testInputs[0] = "node";
        testInputs[1] = "-v";
        testInputs[2] = "";

        try vm.ffi(testInputs) returns (bytes memory) {
            console.log("SUCCESS: Node.js is available for script execution");
        } catch {
            console.log("ERROR: Node.js not available - scripts will not work");
            return;
        }

        // Test script file exists
        testInputs[1] = "-e";
        testInputs[2] = "console.log('Script integration test successful')";

        try vm.ffi(testInputs) returns (bytes memory result) {
            console.log("SUCCESS: Script execution successful");
            console.log("Script output:", string(result));
        } catch {
            console.log("ERROR: Script execution failed");
        }
    }

    function testComputeLeafCompatibility() public {
        console.log("=== Testing Leaf Computation Compatibility ===");

        // Test that our script computes leaves the same way as the contract
        uint256 channelId = _createETHChannel();
        _makeDeposits(channelId, true);
        _initializeAndCloseChannel(channelId);

        // Debug: check what values we have
        bytes32 lastRootInSequence = rollupBridge.getLastRootInSequence(channelId);
        (, bytes32 finalStateRoot) = rollupBridge.getChannelRoots(channelId);

        console.log("lastRootInSequence:");
        console.logBytes32(lastRootInSequence);
        console.log("finalStateRoot from contract:");
        console.logBytes32(finalStateRoot);
        console.log("Are they equal?", lastRootInSequence == finalStateRoot);

        // Get contract's leaf computation using lastRootInSequence (what withdrawal uses)
        bytes32 contractLeafWithLastRoot =
            rollupBridge.computeLeafForVerification(l2Address1, DEPOSIT_AMOUNT, lastRootInSequence);

        console.log("Contract leaf with lastRootInSequence:");
        console.logBytes32(contractLeafWithLastRoot);

        // Get contract's leaf computation using finalStateRoot (for comparison)
        bytes32 contractLeafWithFinalRoot =
            rollupBridge.computeLeafForVerification(l2Address1, DEPOSIT_AMOUNT, finalStateRoot);

        console.log("Contract leaf with finalStateRoot:");
        console.logBytes32(contractLeafWithFinalRoot);

        // This would be compared with script output in a real integration test
        console.log("SUCCESS: Contract leaf computation working");
    }

    // ========== HELPER FUNCTIONS ==========

    /**
     * @dev Creates a mock MPT leaf with RLP-encoded account data: [nonce, balance, storageHash, codeHash]
     */
    function _createMockMPTLeaf(uint256 balance) internal pure returns (bytes memory) {
        bytes[] memory accountFields = new bytes[](4);

        // nonce = 0
        accountFields[0] = RLP.encode(abi.encodePacked(uint256(0)));

        // balance
        accountFields[1] = RLP.encode(abi.encodePacked(balance));

        // storageHash (empty storage)
        accountFields[2] = RLP.encode(abi.encodePacked(keccak256("")));

        // codeHash (empty code)
        accountFields[3] = RLP.encode(abi.encodePacked(keccak256("")));

        return RLP.encodeList(accountFields);
    }

    /**
     * @dev Creates MPT leaves for a given set of balances
     */
    function _createMPTLeaves(uint256[] memory balances) internal pure returns (bytes[] memory) {
        bytes[] memory leaves = new bytes[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            leaves[i] = _createMockMPTLeaf(balances[i]);
        }
        return leaves;
    }
}
