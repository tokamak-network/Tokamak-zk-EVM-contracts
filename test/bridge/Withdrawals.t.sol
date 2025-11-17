// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {RollupBridge} from "../../src/RollupBridge.sol";
import {ITokamakVerifier} from "../../src/interface/ITokamakVerifier.sol";
import {IGroth16Verifier16Leaves} from "../../src/interface/IGroth16Verifier16Leaves.sol";
import {Groth16Verifier16Leaves} from "../../src/verifier/Groth16Verifier16Leaves.sol";
import {ZecFrost} from "../../src/library/ZecFrost.sol";
import {RLP} from "../../src/library/RLP.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockTokamakVerifier is ITokamakVerifier {
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
    MockTokamakVerifier public mockTokamakVerifier;
    Groth16Verifier16Leaves public groth16Verifier; // Real Groth16 verifier
    ZecFrost public mockZecFrost;
    MockERC20 public testToken;

    // Test participants
    address public owner = makeAddr("owner");
    address public leader = makeAddr("leader");
    address public participant1 = 0xd96b35D012879d89cfBA6fE215F1015863a6f6d0; // Address that FROST signature 1 recovers to
    address public participant2 = 0x012C2171f631e27C4bA9f7f8262af2a48956939A; // Address that FROST signature 2 recovers to
    address public participant3 = makeAddr("participant3"); // Third participant

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
        mockTokamakVerifier = new MockTokamakVerifier();
        groth16Verifier = new Groth16Verifier16Leaves(); // Real Groth16 verifier
        testToken = new MockERC20("Test Token", "TEST");

        // Deploy RollupBridge implementation
        RollupBridge implementation = new RollupBridge();

        // Deploy proxy
        mockZecFrost = new ZecFrost();

        bytes memory initData = abi.encodeWithSelector(
            RollupBridge.initialize.selector,
            address(mockTokamakVerifier),
            address(mockZecFrost),
            address(groth16Verifier),
            owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        rollupBridge = RollupBridge(address(proxy));

        // Allow the token contract for testing
        vm.startPrank(owner);
        uint128[] memory preprocessedPart1 = new uint128[](4);
        preprocessedPart1[0] = 0x1186b2f2b6871713b10bc24ef04a9a39;
        preprocessedPart1[1] = 0x02b36b71d4948be739d14bb0e8f4a887;
        preprocessedPart1[2] = 0x18e54aba379045c9f5c18d8aefeaa8cc;
        preprocessedPart1[3] = 0x08df3e052d4b1c0840d73edcea3f85e7;
        uint256[] memory preprocessedPart2 = new uint256[](4);
        preprocessedPart2[0] = 0x7e084b3358f7f1404f0a4ee1acc6d254997032f77fd77593fab7c896b7cfce1e;
        preprocessedPart2[1] = 0xe2dfa30cd1fca5558bfe26343dc755a0a52ef6115b9aef97d71b047ed5d830c8;
        preprocessedPart2[2] = 0xf68408df0b8dda3f529522a67be22f2934970885243a9d2cf17d140f2ac1bb10;
        preprocessedPart2[3] = 0x4b0d9a6ffeb25101ff57e35d7e527f2080c460edc122f2480f8313555a71d3ac;
        rollupBridge.setAllowedTargetContract(
            address(testToken), preprocessedPart1, preprocessedPart2, bytes1(0x00), true
        );
        vm.stopPrank();

        // Fund participants with ETH and tokens
        vm.deal(leader, 10 ether);
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

        vm.startPrank(leader);

        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = ETH_TOKEN_ADDRESS;

        RollupBridge.ChannelParams memory params = RollupBridge.ChannelParams({
            allowedTokens: allowedTokens,
            participants: participants,
            timeout: CHANNEL_TIMEOUT,
            pkx: 0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            pky: 0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        });
        channelId = rollupBridge.openChannel{value: rollupBridge.LEADER_BOND_REQUIRED()}(params);
        vm.stopPrank();
    }

    function _createTokenChannel() internal returns (uint256 channelId) {
        address[] memory participants = new address[](3);
        participants[0] = participant1;
        participants[1] = participant2;
        participants[2] = participant3;

        vm.startPrank(leader);

        address[] memory allowedTokensForToken = new address[](1);
        allowedTokensForToken[0] = address(testToken);

        RollupBridge.ChannelParams memory params = RollupBridge.ChannelParams({
            allowedTokens: allowedTokensForToken,
            participants: participants,
            timeout: CHANNEL_TIMEOUT,
            pkx: 0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            pky: 0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        });
        channelId = rollupBridge.openChannel{value: rollupBridge.LEADER_BOND_REQUIRED()}(params);
        vm.stopPrank();
    }

    // ========== Groth16 Proof Generation using FFI ==========

    struct Groth16ProofResult {
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
        bytes32 merkleRoot;
    }

    function generateGroth16Proof(uint256[] memory mptKeys, uint256[] memory balances)
        internal
        pure
        returns (Groth16ProofResult memory result)
    {
        require(mptKeys.length == balances.length, "Mismatched arrays");
        require(mptKeys.length <= 3, "Too many participants for test");

        // For testing purposes, return mock values
        // In a real implementation, this would generate actual Groth16 proofs
        result.pA = [uint256(1), uint256(2), uint256(3), uint256(4)];
        result.pB = [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)];
        result.pC = [uint256(13), uint256(14), uint256(15), uint256(16)];

        // Generate a deterministic merkle root based on the inputs
        result.merkleRoot = keccak256(abi.encodePacked(mptKeys, balances));

        return result;
    }

    function _createMPTLeaves(uint256[] memory balances) internal pure returns (bytes[] memory) {
        bytes[] memory leaves = new bytes[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            leaves[i] = abi.encode(balances[i]);
        }
        return leaves;
    }

    // ========== Test Functions ==========

    // TODO: Re-enable this test after completing Groth16 integration
    /* function testWithdrawAfterChannelCloseWithGroth16() public {
        // This test needs additional setup for the new Groth16 architecture
        // 1. Create a token channel
        uint256 channelId = _createTokenChannel();
        
        // 2. Participants make deposits
        uint256[] memory depositAmounts = new uint256[](3);
        depositAmounts[0] = 1 ether;
        depositAmounts[1] = 2 ether;
        depositAmounts[2] = 3 ether;
        
        address[] memory participants = new address[](3);
        participants[0] = participant1;
        participants[1] = participant2;
        participants[2] = participant3;
        
        // Make deposits
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(participants[i]);
            testToken.approve(address(rollupBridge), depositAmounts[i]);
            rollupBridge.depositToken(channelId, address(testToken), depositAmounts[i], bytes32(uint256(uint160(l2User1))));
            vm.stopPrank();
        }
        
        // 3. Generate Groth16 proof for channel initialization
        uint256[] memory mptKeys = new uint256[](3);
        mptKeys[0] = uint256(uint160(participant1));
        mptKeys[1] = uint256(uint160(participant2));
        mptKeys[2] = uint256(uint160(participant3));
        
        Groth16ProofResult memory proofResult = generateGroth16Proof(mptKeys, depositAmounts);
        
        // 4. Initialize channel state with Groth16 proof
        vm.startPrank(leader);
        RollupBridge.ChannelInitializationProof memory initProof = RollupBridge.ChannelInitializationProof({
            pA: proofResult.pA,
            pB: proofResult.pB,
            pC: proofResult.pC,
            merkleRoot: proofResult.merkleRoot
        });
        
        rollupBridge.initializeChannelState(channelId, initProof);
        vm.stopPrank();
        
        // Verify channel state
        assertEq(uint(rollupBridge.getChannelState(channelId)), uint(RollupBridge.ChannelState.Open));
        
        // 5. Fast-forward past timeout
        vm.warp(block.timestamp + CHANNEL_TIMEOUT + 1);
        
        // 6. Submit aggregated proof with final balances
        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = depositAmounts[0] + 0.1 ether; // Some state change
        finalBalances[1] = depositAmounts[1] + 0.2 ether;
        finalBalances[2] = depositAmounts[2] + 0.3 ether;
        
        bytes[] memory initialMPTLeaves = new bytes[](3);
        bytes[] memory finalMPTLeaves = new bytes[](3);
        bytes32[] memory participantRoots = new bytes32[](3);
        
        for (uint i = 0; i < 3; i++) {
            initialMPTLeaves[i] = abi.encode(depositAmounts[i]);
            finalMPTLeaves[i] = abi.encode(finalBalances[i]);
            participantRoots[i] = keccak256(abi.encodePacked("participant", i));
        }
        
        RollupBridge.ProofData memory proofData = RollupBridge.ProofData({
            aggregatedProofHash: keccak256("aggregated_proof"),
            finalStateRoot: keccak256("final_state"),
            proofPart1: new uint128[](0),
            proofPart2: new uint256[](0),
            publicInputs: new uint256[](0),
            smax: 0,
            initialMPTLeaves: initialMPTLeaves,
            finalMPTLeaves: finalMPTLeaves,
            participantRoots: participantRoots
        });
        
        vm.startPrank(leader);
        rollupBridge.submitAggregatedProof(channelId, proofData);
        
        // 7. Sign and finalize channel
        RollupBridge.Signature memory signature = RollupBridge.Signature({
            message: 0x08f58e86bd753e86f2e0172081576b4c58909be5c2e70a8e30439d3a12d091be,
            rx: 0x1fb4c0436e9054ae0b237cde3d7a478ce82405b43fdbb5bf1d63c9f8d912dd5d,
            ry: 0x3a7784df441925a8859b9f3baf8d570d488493506437db3ccf230a4b43b27c1e,
            z: 0xc7fdcb364dd8577e47dd479185ca659adbfcd1b8675e5cbb36e5f93ca4e15b25
        });
        
        rollupBridge.signAggregatedProof(channelId, signature);
        rollupBridge.closeAndFinalizeChannel(channelId);
        vm.stopPrank();
        
        // 8. Test withdrawals
        for (uint i = 0; i < 3; i++) {
            address participant = participants[i];
            uint256 expectedWithdrawable = finalBalances[i];
            
            // Check withdrawable amount
            uint256 withdrawableAmount = rollupBridge.getWithdrawableAmount(channelId, participant);
            assertEq(withdrawableAmount, expectedWithdrawable, "Withdrawable amount mismatch");
            
            // Record balance before withdrawal
            uint256 balanceBefore = testToken.balanceOf(participant);
            
            // Perform withdrawal
            vm.startPrank(participant);
            rollupBridge.withdrawAfterClose(channelId, address(testToken));
            vm.stopPrank();
            
            // Check balance after withdrawal
            uint256 balanceAfter = testToken.balanceOf(participant);
            assertEq(balanceAfter, balanceBefore + expectedWithdrawable, "Balance not updated correctly");
            
            // Verify participant can't withdraw again
            assertEq(rollupBridge.getWithdrawableAmount(channelId, participant), 0, "Withdrawable amount should be 0");
            
            vm.startPrank(participant);
            vm.expectRevert("No withdrawable amount or already withdrawn");
            rollupBridge.withdrawAfterClose(channelId, address(testToken));
            vm.stopPrank();
        }
    } */

    function _makeDeposits(uint256 channelId, bool isETH) internal {
        if (isETH) {
            vm.prank(participant1);
            rollupBridge.depositETH{value: DEPOSIT_AMOUNT}(channelId, bytes32(uint256(uint160(l2Address1))));

            vm.prank(participant2);
            rollupBridge.depositETH{value: DEPOSIT_AMOUNT}(channelId, bytes32(uint256(uint160(l2Address1))));

            vm.prank(participant3);
            rollupBridge.depositETH{value: DEPOSIT_AMOUNT}(channelId, bytes32(uint256(uint160(l2Address1))));
        } else {
            vm.prank(participant1);
            rollupBridge.depositToken(
                channelId, address(testToken), DEPOSIT_AMOUNT, bytes32(uint256(uint160(l2Address1)))
            );

            vm.prank(participant2);
            rollupBridge.depositToken(
                channelId, address(testToken), DEPOSIT_AMOUNT, bytes32(uint256(uint160(l2Address1)))
            );

            vm.prank(participant3);
            rollupBridge.depositToken(
                channelId, address(testToken), DEPOSIT_AMOUNT, bytes32(uint256(uint160(l2Address1)))
            );
        }
    }

    function _initializeAndCloseChannel(uint256 channelId) internal {
        // Initialize channel state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        RollupBridge.ChannelInitializationProof memory mockProof = RollupBridge.ChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });
        vm.prank(leader);
        rollupBridge.initializeChannelState(channelId, mockProof);

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
        RollupBridge.ProofData memory proofData = RollupBridge.ProofData({
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

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + CHANNEL_TIMEOUT + 1);

        vm.prank(leader);
        rollupBridge.submitAggregatedProof(channelId, proofData);

        // Sign aggregated proof
        RollupBridge.Signature memory signature = RollupBridge.Signature({
            message: 0x08f58e86bd753e86f2e0172081576b4c58909be5c2e70a8e30439d3a12d091be,
            rx: 0x1fb4c0436e9054ae0b237cde3d7a478ce82405b43fdbb5bf1d63c9f8d912dd5d,
            ry: 0x3a7784df441925a8859b9f3baf8d570d488493506437db3ccf230a4b43b27c1e,
            z: 0xc7fdcb364dd8577e47dd479185ca659adbfcd1b8675e5cbb36e5f93ca4e15b25
        });

        vm.prank(leader);
        rollupBridge.signAggregatedProof(channelId, signature);

        // Close channel
        // Close and finalize channel directly (no challenge period needed when signature verified)
        vm.prank(leader);
        rollupBridge.closeAndFinalizeChannel(channelId);
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
}
