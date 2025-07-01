// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {Verifier} from "../src/Verifier.sol";
import {StateTransitionVerifier} from "../src/StateTransitionVerifier.sol";
import {IStateTransitionVerifier} from "../src/interface/IStateTransitionVerifier.sol";
import {ChannelRegistry} from "../src/ChannelRegistry.sol";
import {IChannelRegistry} from "../src/interface/IChannelRegistry.sol";
import {MessageHashUtils} from "@openzeppelin/utils/cryptography/MessageHashUtils.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";

import "forge-std/console.sol";

contract testStateTransitionVerifier is Test {
    using MessageHashUtils for bytes32;

    address owner;
    uint256 ownerPrivateKey;
    address leader;
    uint256 leaderPrivateKey;
    address participant1;
    uint256 participant1PrivateKey;
    address participant2;
    uint256 participant2PrivateKey;

    Verifier verifier;
    StateTransitionVerifier stateTransitionVerifier;
    ChannelRegistry channelRegistry;

    IStateTransitionVerifier.StateUpdate internal newStateUpdate;

    // Mock tokens for testing
    ERC20Mock token1;
    ERC20Mock token2;

    uint128[] public serializedProofPart1;
    uint256[] public serializedProofPart2;
    uint256[] public publicInputs;
    uint256 public smax;

    bytes32 public channelId;
    bytes32 public newStateRoot;
    bytes32 public newBalanceRoot;

    uint256 constant MIN_LEADER_BOND = 1 ether;
    uint256 constant MIN_PARTICIPANT_STAKE = 0.1 ether;

    function setUp() public virtual {
        verifier = new Verifier();

        // Create test accounts with known private keys
        ownerPrivateKey = 0x1234;
        owner = vm.addr(ownerPrivateKey);

        leaderPrivateKey = 0x5678;
        leader = vm.addr(leaderPrivateKey);

        participant1PrivateKey = 0x9abc;
        participant1 = vm.addr(participant1PrivateKey);

        participant2PrivateKey = 0xdef0;
        participant2 = vm.addr(participant2PrivateKey);

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(leader, 10 ether);
        vm.deal(participant1, 5 ether);
        vm.deal(participant2, 5 ether);

        vm.startPrank(owner);
        // Deploy mock tokens
        token1 = new ERC20Mock("Token1", "TK1");
        token2 = new ERC20Mock("Token2", "TK2");

        // Mint some tokens for testing
        token1.mint(participant1, 1000 * 10 ** 18);
        token1.mint(participant2, 1000 * 10 ** 18);
        token2.mint(participant1, 1000 * 10 ** 18);
        token2.mint(participant2, 1000 * 10 ** 18);

        channelRegistry = new ChannelRegistry();
        stateTransitionVerifier = new StateTransitionVerifier(address(verifier), address(channelRegistry));
        channelRegistry.setStateTransitionVerifier(address(stateTransitionVerifier));
        vm.stopPrank();

        // Create channel with enhanced parameters
        channelId = _createTestChannelWithStakes();

        newStateRoot = bytes32(uint256(0x789));
        newBalanceRoot = bytes32(uint256(0xabc));

        _initializeProofData();
    }

    function _createTestChannelWithStakes() internal returns (bytes32) {
        // Leader bonds first
        vm.prank(leader);
        channelRegistry.bondAsLeader{value: MIN_LEADER_BOND}();

        // Create commitments
        bytes32 leaderNonce = keccak256("leader_nonce");
        bytes32 participant1Nonce = keccak256("participant1_nonce");
        bytes32 participant2Nonce = keccak256("participant2_nonce");

        address[] memory participants = new address[](3);
        participants[0] = leader;
        participants[1] = participant1;
        participants[2] = participant2;

        bytes32[] memory commitments = new bytes32[](3);
        commitments[0] = keccak256(abi.encode(keccak256(abi.encode(leader, leaderNonce))));
        commitments[1] = keccak256(abi.encode(keccak256(abi.encode(participant1, participant1Nonce))));
        commitments[2] = keccak256(abi.encode(keccak256(abi.encode(participant2, participant2Nonce))));

        IChannelRegistry.ChannelCreationParams memory params = IChannelRegistry.ChannelCreationParams({
            leader: leader,
            preApprovedParticipants: participants,
            participantCommitments: commitments,
            signatureThreshold: 2, // Require 2 out of 3 signatures
            initialStateRoot: bytes32(0),
            challengePeriod: 7 days,
            minimumStake: MIN_PARTICIPANT_STAKE
        });

        // Add supported tokens
        address[] memory supportedTokens = new address[](2);
        supportedTokens[0] = address(token1);
        supportedTokens[1] = address(token2);

        vm.prank(leader);
        bytes32 newChannelId = channelRegistry.createChannelWithParams(params, supportedTokens);

        // All participants stake
        vm.prank(leader);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE}(newChannelId, leaderNonce);

        vm.prank(participant1);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE}(newChannelId, participant1Nonce);

        vm.prank(participant2);
        channelRegistry.stakeAsParticipant{value: MIN_PARTICIPANT_STAKE}(newChannelId, participant2Nonce);

        return newChannelId;
    }

    function testVerifyAndCommitStateUpdateWithMultipleSignatures() public {
        // Create the message hash that participants need to sign
        bytes32 messageHash = keccak256(
            abi.encode(
                channelId,
                bytes32(0),
                newStateRoot,
                uint256(1) // nonce
            )
        );

        // Add Ethereum Signed Message prefix
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        // Sign with leader and participant1 (2 out of 3 signatures)
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(leaderPrivateKey, ethSignedMessageHash);
        bytes memory leaderSignature = abi.encodePacked(r1, s1, v1);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(participant1PrivateKey, ethSignedMessageHash);
        bytes memory participant1Signature = abi.encodePacked(r2, s2, v2);

        // Create arrays for signatures and signers
        bytes[] memory participantSignatures = new bytes[](2);
        participantSignatures[0] = leaderSignature;
        participantSignatures[1] = participant1Signature;

        address[] memory signers = new address[](2);
        signers[0] = leader;
        signers[1] = participant1;

        newStateUpdate = IStateTransitionVerifier.StateUpdate({
            channelId: channelId,
            oldStateRoot: bytes32(0),
            newStateRoot: newStateRoot,
            nonce: 1,
            proofPart1: serializedProofPart1,
            proofPart2: serializedProofPart2,
            publicInputs: publicInputs,
            smax: smax,
            participantSignatures: participantSignatures,
            signers: signers
        });

        // Only leader can submit state updates
        vm.prank(leader);
        bool result = stateTransitionVerifier.verifyAndCommitStateUpdate(newStateUpdate);
        assertTrue(result);

        // Verify state was updated
        (bytes32 currentRoot, uint256 nonce) = stateTransitionVerifier.getChannelState(channelId);
        assertEq(currentRoot, newStateRoot);
        assertEq(nonce, 1);
    }

    function testCannotSubmitWithInsufficientSignatures() public {
        // Create the message hash
        bytes32 messageHash = keccak256(abi.encode(channelId, bytes32(0), newStateRoot, uint256(1)));

        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        // Only sign with leader (1 out of 3, but threshold is 2)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(leaderPrivateKey, ethSignedMessageHash);
        bytes memory leaderSignature = abi.encodePacked(r, s, v);

        bytes[] memory participantSignatures = new bytes[](1);
        participantSignatures[0] = leaderSignature;

        address[] memory signers = new address[](1);
        signers[0] = leader;

        newStateUpdate = IStateTransitionVerifier.StateUpdate({
            channelId: channelId,
            oldStateRoot: bytes32(0),
            newStateRoot: newStateRoot,
            nonce: 1,
            proofPart1: serializedProofPart1,
            proofPart2: serializedProofPart2,
            publicInputs: publicInputs,
            smax: smax,
            participantSignatures: participantSignatures,
            signers: signers
        });

        vm.prank(leader);
        vm.expectRevert(abi.encodeWithSelector(IStateTransitionVerifier.Invalid__SignatureCount.selector, 1, 2));
        stateTransitionVerifier.verifyAndCommitStateUpdate(newStateUpdate);
    }

    function testCannotSubmitFromNonLeader() public {
        bytes32 messageHash = keccak256(abi.encode(channelId, bytes32(0), newStateRoot, uint256(1)));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(leaderPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes[] memory participantSignatures = new bytes[](1);
        participantSignatures[0] = signature;

        address[] memory signers = new address[](1);
        signers[0] = leader;

        newStateUpdate = IStateTransitionVerifier.StateUpdate({
            channelId: channelId,
            oldStateRoot: bytes32(0),
            newStateRoot: newStateRoot,
            nonce: 1,
            proofPart1: serializedProofPart1,
            proofPart2: serializedProofPart2,
            publicInputs: publicInputs,
            smax: smax,
            participantSignatures: participantSignatures,
            signers: signers
        });

        // Try to submit from participant1 instead of leader
        vm.prank(participant1);
        vm.expectRevert(IStateTransitionVerifier.Invalid__Caller.selector);
        stateTransitionVerifier.verifyAndCommitStateUpdate(newStateUpdate);
    }

    function testVerifyClosingStateUpdate() public {
        // First, set channel to closing status
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        // For closing state, we need ALL remaining participants to sign
        bytes32 messageHash = keccak256(abi.encode(channelId, bytes32(0), newStateRoot, uint256(1)));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        // Get signatures from all 3 participants
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(leaderPrivateKey, ethSignedMessageHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(participant1PrivateKey, ethSignedMessageHash);
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(participant2PrivateKey, ethSignedMessageHash);

        bytes[] memory participantSignatures = new bytes[](3);
        participantSignatures[0] = abi.encodePacked(r1, s1, v1);
        participantSignatures[1] = abi.encodePacked(r2, s2, v2);
        participantSignatures[2] = abi.encodePacked(r3, s3, v3);

        address[] memory signers = new address[](3);
        signers[0] = leader;
        signers[1] = participant1;
        signers[2] = participant2;

        newStateUpdate = IStateTransitionVerifier.StateUpdate({
            channelId: channelId,
            oldStateRoot: bytes32(0),
            newStateRoot: newStateRoot,
            nonce: 1,
            proofPart1: serializedProofPart1,
            proofPart2: serializedProofPart2,
            publicInputs: publicInputs,
            smax: smax,
            participantSignatures: participantSignatures,
            signers: signers
        });

        vm.prank(leader);
        bool result = stateTransitionVerifier.verifyClosingStateUpdate(newStateUpdate);
        assertTrue(result);
    }

    function testGetActiveParticipantCount() public {
        uint256 activeCount = stateTransitionVerifier.getActiveParticipantCount(channelId);
        assertEq(activeCount, 3); // All participants should be active

        // Test after one participant exits during closure
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        vm.prank(participant1);
        channelRegistry.exitChannel(channelId);

        uint256 newActiveCount = stateTransitionVerifier.getActiveParticipantCount(channelId);
        assertEq(newActiveCount, 2); // Should have 2 active participants
    }

    function testGetRequiredSignatureThreshold() public {
        uint256 threshold = stateTransitionVerifier.getRequiredSignatureThreshold(channelId);
        assertEq(threshold, 2); // Original threshold

        // Test after participants exit
        vm.prank(leader);
        channelRegistry.updateChannelStatus(channelId, IChannelRegistry.ChannelStatus.CLOSING);

        vm.prank(participant1);
        channelRegistry.exitChannel(channelId);

        vm.prank(participant2);
        channelRegistry.exitChannel(channelId);

        uint256 newThreshold = stateTransitionVerifier.getRequiredSignatureThreshold(channelId);
        assertEq(newThreshold, 1); // Should require all remaining participants (just leader)
    }

    function testEmergencyStateUpdate() public {
        bytes32 emergencyStateRoot = bytes32(uint256(0x999));

        vm.prank(owner); // Owner can call emergency function
        stateTransitionVerifier.emergencyStateUpdate(channelId, emergencyStateRoot);

        (bytes32 currentRoot, uint256 nonce) = stateTransitionVerifier.getChannelState(channelId);
        assertEq(currentRoot, emergencyStateRoot);
        assertEq(nonce, 1);
    }

    function testCannotCallEmergencyFromUnauthorized() public {
        bytes32 emergencyStateRoot = bytes32(uint256(0x999));

        vm.prank(participant1);
        vm.expectRevert("Unauthorized");
        stateTransitionVerifier.emergencyStateUpdate(channelId, emergencyStateRoot);
    }

    function _initializeProofData() internal {
        // serializedProofPart1: First 16 bytes (32 hex chars) of each coordinate
        // serializedProofPart2: Last 32 bytes (64 hex chars) of each coordinate

        // SERIALIZED PROOF PART 1 (First 16 bytes - 32 hex chars)
        serializedProofPart1.push(0x0d8838cc826baa7ccd8cfe0692e8a13d); // s^{(0)}(x,y)_X
        serializedProofPart1.push(0x103aeb959c53fdd5f13b70a350363881); // s^{(0)}(x,y)_Y
        serializedProofPart1.push(0x09f0f94fd2dc8976bfeab5da30e1fa04); // s^{(1)}(x,y)_X
        serializedProofPart1.push(0x17cb62f5e698fe087b0f334e2fb2439c); // s^{(1)}(x,y)_Y
        serializedProofPart1.push(0x05b4f308ff641adb31b740431cee5d70); // U_X
        serializedProofPart1.push(0x12ae9a8d3ec9c65c98664e311e634d64); // U_Y
        serializedProofPart1.push(0x08e6d6c1e6691e932692e3942a6cbef7); // V_X
        serializedProofPart1.push(0x12cdafbf7bf8b80338459969b4c54bcb); // V_Y
        serializedProofPart1.push(0x0c2fe4549b4508fa6db64b438661f36c); // W_X
        serializedProofPart1.push(0x00ba5ce79b6c3ee1f9323076cd019f51); // W_Y
        serializedProofPart1.push(0x10d2a2a6b5d9b0f74e5ca7207cbb10b2); // O_mid_X
        serializedProofPart1.push(0x143fc4f52ca987f2e47885310ca5693b); // O_mid_Y
        serializedProofPart1.push(0x0d0d110f829d162dc4e1e76a7544188b); // O_prv_X
        serializedProofPart1.push(0x01c43cc10d4ec71dd398bcdbbd6f8eb7); // O_prv_Y
        serializedProofPart1.push(0x180d963ee9bd02f3e9367614105c95f3); // Q_{AX}_X
        serializedProofPart1.push(0x13efcb0e014478ce79000206e8b39ea5); // Q_{AX}_Y
        serializedProofPart1.push(0x0bc733812b8bba788f2f4fff4751f70d); // Q_{AY}_X
        serializedProofPart1.push(0x0afb2ae78cb743b453868f07e92b466a); // Q_{AY}_Y
        serializedProofPart1.push(0x04897b34fcba759c43efbe8834f279b3); // Q_{CX}_X
        serializedProofPart1.push(0x0af44a63032292984463891d0c1555ee); // Q_{CX}_Y
        serializedProofPart1.push(0x12e0faf1eaaca9e9e0f5be64eb013c9d); // Q_{CY}_X
        serializedProofPart1.push(0x151e4f845009fdef5cf50bde3c38d42c); // Q_{CY}_Y
        serializedProofPart1.push(0x07ec505b12d1d7337382721371829fa1); // Π_{χ}_X
        serializedProofPart1.push(0x167afb06ffb4c89b5e04a598139f20f0); // Π_{χ}_Y
        serializedProofPart1.push(0x09468040e794eaa40c964c3b8f4fa252); // Π_{ζ}_X
        serializedProofPart1.push(0x1395d5b79c0a1e3915974a4899d5b00b); // Π_{ζ}_Y
        serializedProofPart1.push(0x07ba876a95322207b596d39ed0490997); // B_X
        serializedProofPart1.push(0x13adce13779790b3bfbee74b54bfa42b); // B_Y
        serializedProofPart1.push(0x0516cebd5e7b3d9eca97a4959737c8af); // R_X
        serializedProofPart1.push(0x18d3891d0f746a6e4de8d9f0973c55f3); // R_Y
        serializedProofPart1.push(0x16911127fce9f466f95506edd9eae5ff); // M_ζ_X (M_Y_X)
        serializedProofPart1.push(0x05438bddfb750e22c41a713494c7c5e9); // M_ζ_Y (M_Y_Y)
        serializedProofPart1.push(0x0ac8be4b1cb6a9c8354fcf35e5d7a339); // M_χ_X (M_X_X)
        serializedProofPart1.push(0x16695706d77185cdfdad3d70e8d73e87); // M_χ_Y (M_X_Y)
        serializedProofPart1.push(0x172dfe9a0767dda975f5fbde45ed1ae0); // N_ζ_X (N_Y_X)
        serializedProofPart1.push(0x17b91c24ec6ce0e74426041d668c329a); // N_ζ_Y (N_Y_Y)
        serializedProofPart1.push(0x0ac8be4b1cb6a9c8354fcf35e5d7a339); // N_χ_X (N_X_X)
        serializedProofPart1.push(0x16695706d77185cdfdad3d70e8d73e87); // N_χ_Y (N_X_Y)
        serializedProofPart1.push(0x0883ed3c97b3e674ebfc683481742daa); // O_pub_X
        serializedProofPart1.push(0x0f697de543d92f067e8ff95912513e49); // O_pub_Y
        serializedProofPart1.push(0x097d7a0fe6430f3dfe4e10c2db6ec878); // A_X
        serializedProofPart1.push(0x104de32201c5ba649cc17df4cf759a1f); // A_Y

        // SERIALIZED PROOF PART 2 (Last 32 bytes - 64 hex chars)
        serializedProofPart2.push(0xbbae56c781b300594dac0753e75154a00b83cc4e6849ef3f07bb56610a02c828); // s^{(0)}(x,y)_X
        serializedProofPart2.push(0xf3447285889202e7e24cd08a058a758a76ee4c8440131be202ad8bc0cc91ee70); // s^{(0)}(x,y)_Y
        serializedProofPart2.push(0x76e577ad778dc4476b10709945e71e289be5ca05c412ca04c133c485ae8bc757); // s^{(1)}(x,y)_X
        serializedProofPart2.push(0x7ada41cb993109dc7c194693dbcc461f8512755054966319bcbdea3a1da86938); // s^{(1)}(x,y)_Y
        serializedProofPart2.push(0x12f31df6476c99289584549ae13292a824df5e10f546a9659d08479cf55b3bb2); // U_X
        serializedProofPart2.push(0xd28e43565c5c0a0b6d625a4572e02fbb6de2b255911ebe90f551a43a48c52ec0); // U_Y
        serializedProofPart2.push(0x185457d5b78e0dd03fb83b4af872c2f9800e0d4d3bbb1e36ca85a9d8ce763e55); // V_X
        serializedProofPart2.push(0x559b5cc09730db68b632e905b9ff96bbaffedfdf89e91dadbd7b49dbe2d89960); // V_Y
        serializedProofPart2.push(0xb0f667aff5ec036e5324a9e11b04f1390d31e422fb358943b6e9834ceafc2d45); // W_X
        serializedProofPart2.push(0x5831b2fcca492d422c2c5b78cfd02bbb55bd9ef574d764400661c44345712a95); // W_Y
        serializedProofPart2.push(0xea67be102035f7f79a8e8ebd8cffb3ce8dd14458c20a93e1a99e31e6756f33ee); // O_mid_X
        serializedProofPart2.push(0x430617634aa53978ade5412f3ebdb29a91d21a1ddb39eab112df55ef2d2740e4); // O_mid_Y
        serializedProofPart2.push(0x9a3aa207f182acea8ec2ab6fdbe9a293e2996e1770815135af9dc7dcab829cd5); // O_prv_X
        serializedProofPart2.push(0xe54e2e3f05333664792be98ebfe73b8b224acc83074196478593e852ceb2cbef); // O_prv_Y
        serializedProofPart2.push(0x2a2f967e8490650c5dd5893db46c1f61a6bf38ead27c0065c44077656ac88e8d); // Q_{AX}_X
        serializedProofPart2.push(0x3a25dec62a83cf44cb5356420caf0dcbc4d94b9a0025349a2680b67582d4ceef); // Q_{AX}_Y
        serializedProofPart2.push(0xec308bd22c38acd83cb466e91c0a977b03bc7ab87b5655e1a844c97fa1ad8bed); // Q_{AY}_X
        serializedProofPart2.push(0xfddfd77793b5af2206625e7dbd3840d179aae985bf5673d02484a0685b803930); // Q_{AY}_Y
        serializedProofPart2.push(0x04acda4fdb36bb30b7aea7540d1fd469fdcb01b32b2ba74de53870a6fbd93dad); // Q_{CX}_X
        serializedProofPart2.push(0x9e2b3794cd4fe439fe02788fac15f5d5de8a38a35431df4d17b817bd091ffdb1); // Q_{CX}_Y
        serializedProofPart2.push(0x38848585c4de95f0ccd6c77cbcb630593e9bf245e78d126978b1229e771580a4); // Q_{CY}_X
        serializedProofPart2.push(0x8691e07a7670c43a463111b013e9050325b870219c35603d55bc09e800c0da61); // Q_{CY}_Y
        serializedProofPart2.push(0x99377148bd378731f820de792040dc114dbac2a120de8e26820cb39c24f2d255); // Π_{χ}_X
        serializedProofPart2.push(0xffef9a993e7c0e2e1991d0722671e8c1544d336bbcaff45e94d80a2fd4a68a2b); // Π_{χ}_Y
        serializedProofPart2.push(0xca315029695dcddb58ec2ffab2e8931a9f0cdfe16456a5ddaa820f129566b3c2); // Π_{ζ}_X
        serializedProofPart2.push(0x6a5d94033876ebad48b9d9f3af72e0b39eac4d020bd642e21571e9eb88d918e9); // Π_{ζ}_Y
        serializedProofPart2.push(0x31a915839974262e523f24f696dd93c7928481d3765e8f70454d3fe7ea9cc04d); // B_X
        serializedProofPart2.push(0x88b8b73587f6030d3a536801b4376a684b428f0cf2c9a10b74b874e342bd9a33); // B_Y
        serializedProofPart2.push(0xa6237eb1a20b4a5602933a791965281782f0311ba6c490b6f3909ca35bfd0528); // R_X
        serializedProofPart2.push(0xe6e0afccccf07f40dc377094e188610dd3fda0bc42131d84c3512ef14a7df6a4); // R_Y
        serializedProofPart2.push(0x953ba795920785f216d6016142f26c42c17ce081c0637c35b13f8896345f422d); // M_ζ_X
        serializedProofPart2.push(0x6290c529a10345bc54f7ac860765dc9a6b1fbaf282e6e58ead695c718b484ecd); // M_ζ_Y
        serializedProofPart2.push(0x091e748f260d20003c2a1a29d6f58cfb8f28c065bbeee13a4a51d71e91922d17); // M_χ_X
        serializedProofPart2.push(0x92069bad6f6cf9ce5c4623a2799e610dbee116e00ca9247881d67ccd5b808bc7); // M_χ_Y
        serializedProofPart2.push(0x36a63f824b54a0f7379d756244f27bbb31cefb4600be600034454e3d93f194a8); // N_ζ_X
        serializedProofPart2.push(0xd53a583d68a44600fa4150e55c74c5def7a96ccc4ea89602f25942eb479e1d0e); // N_ζ_Y
        serializedProofPart2.push(0x091e748f260d20003c2a1a29d6f58cfb8f28c065bbeee13a4a51d71e91922d17); // N_χ_X
        serializedProofPart2.push(0x92069bad6f6cf9ce5c4623a2799e610dbee116e00ca9247881d67ccd5b808bc7); // N_χ_Y
        serializedProofPart2.push(0xda9079a92f7bfe749313cd11fd1faf480cbd6829a27de4e182a9c699a459af59); // O_pub_X
        serializedProofPart2.push(0x9c500eac60a728c7e61f88269a1ed9317e763608e3917f78a9697bda457c9955); // O_pub_Y
        serializedProofPart2.push(0x4d66b638321b58bbfdf6b0a17a44a9d9cda67b1a74eea5d0846a99769f18bb17); // A_X
        serializedProofPart2.push(0x4109049c345548f5d1c05fc481a4594d4764dc966bb22dd42a45cc10cd38a7e2); // A_Y

        // evaluations
        serializedProofPart2.push(0x556e7206f0462de3787e80eba2a7ea0eaced54f3bc4386e7f442a2227caafb5e); // R_eval
        serializedProofPart2.push(0x52b690b1abedd5d98d6dc1da501896a0d24d16b4ac50b2b91705c9eacbf4ac0b); // R_omegaX_eval
        serializedProofPart2.push(0x416c2033250efefa6a38b627ba05c7ba67e800b681f9783a079f27c15f2aac32); // R_omegaX_omegaY_eval
        serializedProofPart2.push(0x130694604026116d02cbb135233c3219dce6a8527f02960cb4217dc0b8b17d17); // V_eval

        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        ///////////////////////////////////             PUBLIC INPUTS             ////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

        // Elements 0-31
        publicInputs.push(0x00000000000000000000000000000000392a2d1a05288b172f205541a56fc20d);
        publicInputs.push(0x00000000000000000000000000000000000000000000000000000000c2c30e79);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x00000000000000000000000000000000392a2d1a05288b172f205541a56fc20d);
        publicInputs.push(0x00000000000000000000000000000000000000000000000000000000c2c30e79);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x00000000000000000000000000000000d4ad12e56e54018313761487d2d1fee9);
        publicInputs.push(0x000000000000000000000000000000000000000000000000000000000ce8f6c9);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x00000000000000000000000000000000d4ad12e56e54018313761487d2d1fee9);
        publicInputs.push(0x000000000000000000000000000000000000000000000000000000000ce8f6c9);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);

        // Elements 32-63 (all zeros)
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);

        // Elements 64-71 (non-zero values)
        publicInputs.push(0x0000000000000000000000000000000020af07748adbb0932a59cfb9ad012354);
        publicInputs.push(0x00000000000000000000000000000000f903343320db59a6e85d0dbb1bc7d722);
        publicInputs.push(0x0000000000000000000000000000000020af07748adbb0932a59cfb9ad012354);
        publicInputs.push(0x00000000000000000000000000000000f903343320db59a6e85d0dbb1bc7d722);
        publicInputs.push(0x000000000000000000000000000000001f924fe321c5cf7ad7a47b57891fbcb0);
        publicInputs.push(0x0000000000000000000000000000000081f4f96b68c216b824fb32a8c09bd5a8);
        publicInputs.push(0x000000000000000000000000000000001f924fe321c5cf7ad7a47b57891fbcb0);
        publicInputs.push(0x0000000000000000000000000000000081f4f96b68c216b824fb32a8c09bd5a8);

        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);

        smax = 64;
    }
}
