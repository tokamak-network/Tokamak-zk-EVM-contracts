// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ITokamakVerifier} from "./interface/ITokamakVerifier.sol";
import {IZecFrost} from "./interface/IZecFrost.sol";
import "./interface/IGroth16Verifier16Leaves.sol";
import "./interface/IGroth16Verifier32Leaves.sol";
import "./interface/IGroth16Verifier64Leaves.sol";
import "./interface/IGroth16Verifier128Leaves.sol";
import "./library/RollupBridgeLib.sol";
import "./interface/IRollupBridgeCore.sol";

contract RollupBridgeProofManager is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    struct ChannelInitializationProof {
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
        bytes32 merkleRoot;
    }

    struct ProofData {
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
        uint256 smax;
        IRollupBridgeCore.RegisteredFunction[] functions;
        uint256[][] finalBalances;
    }

    struct Signature {
        bytes32 message;
        uint256 rx;
        uint256 ry;
        uint256 z;
    }

    IRollupBridgeCore public rollupBridge;
    ITokamakVerifier public zkVerifier;
    IZecFrost public zecFrost;
    IGroth16Verifier16Leaves public groth16Verifier16;
    IGroth16Verifier32Leaves public groth16Verifier32;
    IGroth16Verifier64Leaves public groth16Verifier64;
    IGroth16Verifier128Leaves public groth16Verifier128;

    event StateInitialized(uint256 indexed channelId, bytes32 currentStateRoot);
    event AggregatedProofSigned(uint256 indexed channelId, address indexed signer);

    modifier onlyBridge() {
        require(msg.sender == address(rollupBridge), "Only bridge can call");
        _;
    }

    function initialize(
        address _rollupBridge,
        address _zkVerifier,
        address _zecFrost,
        address[4] memory _groth16Verifiers,
        address _owner
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        _transferOwnership(_owner);

        require(_rollupBridge != address(0), "Invalid bridge address");
        rollupBridge = IRollupBridgeCore(_rollupBridge);
        zkVerifier = ITokamakVerifier(_zkVerifier);
        zecFrost = IZecFrost(_zecFrost);
        groth16Verifier16 = IGroth16Verifier16Leaves(_groth16Verifiers[0]);
        groth16Verifier32 = IGroth16Verifier32Leaves(_groth16Verifiers[1]);
        groth16Verifier64 = IGroth16Verifier64Leaves(_groth16Verifiers[2]);
        groth16Verifier128 = IGroth16Verifier128Leaves(_groth16Verifiers[3]);
    }

    function initializeChannelState(uint256 channelId, ChannelInitializationProof calldata proof)
        external
        nonReentrant
    {
        require(rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Initialized, "Invalid state");
        require(msg.sender == rollupBridge.getChannelLeader(channelId), "Not leader");

        address[] memory participants = rollupBridge.getChannelParticipants(channelId);
        address[] memory allowedTokens = rollupBridge.getChannelAllowedTokens(channelId);
        uint256 treeSize = rollupBridge.getChannelTreeSize(channelId);

        uint256 totalEntries = participants.length * allowedTokens.length;
        require(totalEntries <= treeSize, "Too many participant-token combinations for circuit");

        uint256 publicSignalsLength = treeSize * 2 + 1;
        uint256[] memory publicSignals = new uint256[](publicSignalsLength);

        publicSignals[0] = uint256(proof.merkleRoot);

        uint256 entryIndex = 0;
        for (uint256 j = 0; j < allowedTokens.length;) {
            address token = allowedTokens[j];

            for (uint256 i = 0; i < participants.length;) {
                address l1Address = participants[i];
                uint256 balance = rollupBridge.getParticipantTokenDeposit(channelId, l1Address, token);
                uint256 l2MptKey = rollupBridge.getL2MptKey(channelId, l1Address, token);

                if (balance > 0) {
                    require(l2MptKey != 0, "Participant MPT key not set for token");
                }

                uint256 modedL2MptKey = l2MptKey % R_MOD;
                uint256 modedBalance = balance % R_MOD;

                publicSignals[entryIndex + 1] = modedL2MptKey;
                publicSignals[entryIndex + 1 + treeSize] = modedBalance;

                unchecked {
                    ++i;
                    ++entryIndex;
                }
            }

            unchecked {
                ++j;
            }
        }

        for (uint256 i = totalEntries; i < treeSize;) {
            publicSignals[i + 1] = 0;
            publicSignals[i + 1 + treeSize] = 0;
            unchecked {
                ++i;
            }
        }

        bool proofValid = RollupBridgeLib.verifyGroth16Proof(
            treeSize,
            groth16Verifier16,
            groth16Verifier32,
            groth16Verifier64,
            groth16Verifier128,
            proof.pA,
            proof.pB,
            proof.pC,
            publicSignals
        );

        require(proofValid, "Invalid Groth16 proof");

        rollupBridge.setChannelInitialStateRoot(channelId, proof.merkleRoot);
        rollupBridge.setChannelState(channelId, IRollupBridgeCore.ChannelState.Open);

        emit StateInitialized(channelId, proof.merkleRoot);
    }

    function submitProofAndSignature(uint256 channelId, ProofData calldata proofData, Signature calldata signature)
        external
    {
        require(
            rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Open
                || rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Active,
            "Invalid state"
        );
        require(msg.sender == rollupBridge.getChannelLeader(channelId), "Only leader can submit");

        address[] memory participants = rollupBridge.getChannelParticipants(channelId);
        address[] memory allowedTokens = rollupBridge.getChannelAllowedTokens(channelId);

        require(proofData.functions.length > 0 && proofData.functions.length <= 5, "Must provide 1-5 functions");
        require(proofData.finalBalances.length == participants.length, "Invalid final balances length");

        for (uint256 i = 0; i < proofData.finalBalances.length; i++) {
            require(proofData.finalBalances[i].length == allowedTokens.length, "Invalid token balances length");
        }

        // Consolidated loop: validate functions and verify ZK proofs
        for (uint256 i = 0; i < proofData.functions.length; i++) {
            bytes32 funcSig = proofData.functions[i].functionSignature;
            IRollupBridgeCore.RegisteredFunction memory registeredFunc = rollupBridge.getRegisteredFunction(funcSig);
            require(registeredFunc.functionSignature != bytes32(0), "Function not registered");

            bool proofValid = zkVerifier.verify(
                proofData.proofPart1,
                proofData.proofPart2,
                registeredFunc.preprocessedPart1,
                registeredFunc.preprocessedPart2,
                proofData.publicInputs,
                proofData.smax
            );

            require(proofValid, "Invalid ZK proof");
        }

        // Validate token balance conservation
        for (uint256 tokenIdx = 0; tokenIdx < allowedTokens.length; tokenIdx++) {
            address token = allowedTokens[tokenIdx];
            uint256 totalFinalBalance = 0;

            for (uint256 participantIdx = 0; participantIdx < participants.length; participantIdx++) {
                totalFinalBalance += proofData.finalBalances[participantIdx][tokenIdx];
            }

            uint256 totalDeposited = rollupBridge.getChannelTotalDeposits(channelId, token);
            require(totalFinalBalance == totalDeposited, "Balance conservation violated for token");
        }

        (uint256 pkx, uint256 pky) = rollupBridge.getChannelPublicKey(channelId);
        address signerAddr = rollupBridge.getChannelSignerAddr(channelId);

        address recovered = zecFrost.verify(signature.message, pkx, pky, signature.rx, signature.ry, signature.z);
        require(recovered == signerAddr, "Invalid group threshold signature");

        rollupBridge.setChannelWithdrawAmounts(channelId, participants, allowedTokens, proofData.finalBalances);
        rollupBridge.setChannelSignatureVerified(channelId, true);
        rollupBridge.setChannelState(channelId, IRollupBridgeCore.ChannelState.Closing);

        emit AggregatedProofSigned(channelId, msg.sender);
    }

    function updateVerifier(address _newVerifier) external onlyOwner {
        require(_newVerifier != address(0), "Invalid verifier address");
        zkVerifier = ITokamakVerifier(_newVerifier);
    }

    function updateZecFrost(address _newZecFrost) external onlyOwner {
        require(_newZecFrost != address(0), "Invalid ZecFrost address");
        zecFrost = IZecFrost(_newZecFrost);
    }

    function updateGroth16Verifiers(address[4] memory _newVerifiers) external onlyOwner {
        groth16Verifier16 = IGroth16Verifier16Leaves(_newVerifiers[0]);
        groth16Verifier32 = IGroth16Verifier32Leaves(_newVerifiers[1]);
        groth16Verifier64 = IGroth16Verifier64Leaves(_newVerifiers[2]);
        groth16Verifier128 = IGroth16Verifier128Leaves(_newVerifiers[3]);
    }


    uint256[43] private __gap;
}
