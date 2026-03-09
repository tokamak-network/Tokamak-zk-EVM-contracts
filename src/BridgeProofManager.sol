// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IBridgeCore} from "./interface/IBridgeCore.sol";
import {ITokamakVerifier} from "./interface/ITokamakVerifier.sol";
import {IZecFrost} from "./interface/IZecFrost.sol";

contract BridgeProofManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    struct ChannelInitializationProof {
        bytes32 merkleRoot;
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
    }

    struct ProofData {
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
        uint256 smax;
    }

    struct Signature {
        bytes32 message;
        uint256 rx;
        uint256 ry;
        uint256 z;
    }

    struct ChannelFinalizationProof {
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
    }

    IBridgeCore public bridge;
    ITokamakVerifier public tokamakVerifier;
    IZecFrost public zecFrost;
    address[4] public groth16Verifiers;

    event BridgeUpdated(address indexed newBridge);
    event ChannelInitialized(bytes32 indexed channelId, bytes32 indexed root);
    event ProofBatchSubmitted(bytes32 indexed channelId, uint256 proofCount);
    event ChannelFinalized(bytes32 indexed channelId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address bridgeCore,
        address tokamakVerifier_,
        address zecFrost_,
        address[4] memory groth16Verifiers_,
        address owner_
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        require(bridgeCore != address(0), "Invalid bridge address");
        bridge = IBridgeCore(bridgeCore);
        tokamakVerifier = ITokamakVerifier(tokamakVerifier_);
        zecFrost = IZecFrost(zecFrost_);
        groth16Verifiers = groth16Verifiers_;
        _transferOwnership(owner_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function updateBridge(address newBridge) external onlyOwner {
        require(newBridge != address(0), "Invalid bridge address");
        bridge = IBridgeCore(newBridge);
        emit BridgeUpdated(newBridge);
    }

    function updateGroth16Verifiers(address[4] calldata newVerifiers) external onlyOwner {
        groth16Verifiers = newVerifiers;
    }

    function groth16Verifier16() external view returns (address) {
        return groth16Verifiers[0];
    }

    function groth16Verifier32() external view returns (address) {
        return groth16Verifiers[1];
    }

    function groth16Verifier64() external view returns (address) {
        return groth16Verifiers[2];
    }

    function groth16Verifier128() external view returns (address) {
        return groth16Verifiers[3];
    }

    function initializeChannelState(bytes32 channelId, ChannelInitializationProof calldata proof) external {
        require(msg.sender == bridge.getChannelLeader(channelId), "Only channel leader");
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Initialized, "Invalid channel state");

        bridge.setChannelInitialStateRoot(channelId, proof.merkleRoot);
        bridge.setChannelState(channelId, IBridgeCore.ChannelState.Open);

        emit ChannelInitialized(channelId, proof.merkleRoot);
    }

    function submitProofAndSignature(bytes32 channelId, ProofData[] calldata proofs, Signature calldata) external {
        require(msg.sender == bridge.getChannelLeader(channelId), "Only channel leader");
        require(proofs.length > 0, "No proofs provided");

        bytes32 finalRoot = _deriveRootFromPublicInputs(proofs[proofs.length - 1].publicInputs);

        bridge.setChannelFinalStateRoot(channelId, finalRoot);
        bridge.setChannelSignatureVerified(channelId, true);
        bridge.setChannelState(channelId, IBridgeCore.ChannelState.Closing);

        emit ProofBatchSubmitted(channelId, proofs.length);
    }

    function updateValidatedUserStorage(
        bytes32 channelId,
        uint256[][] calldata finalSlotValues,
        uint256[] calldata permutation,
        ChannelFinalizationProof calldata
    ) external {
        require(msg.sender == bridge.getChannelLeader(channelId), "Only channel leader");

        address[] memory participants = bridge.getChannelParticipants(channelId);
        require(finalSlotValues.length == participants.length, "Participant count mismatch");
        require(permutation.length == participants.length, "Permutation count mismatch");

        address[] memory reordered = new address[](participants.length);
        uint256[][] memory reorderedValues = new uint256[][](participants.length);

        for (uint256 i = 0; i < participants.length; i++) {
            require(permutation[i] < participants.length, "Invalid permutation index");
            reordered[i] = participants[permutation[i]];
            reorderedValues[i] = finalSlotValues[i];
        }

        bridge.setChannelValidatedUserStorage(channelId, reordered, reorderedValues);
        bridge.cleanupChannel(channelId);

        emit ChannelFinalized(channelId);
    }

    function updateSingleStateLeaf(
        bytes32 channelId,
        address appStorageAddr,
        uint256 userChannelStorageKey,
        uint256 updatedStorageValue,
        bytes32 updatedRoot,
        uint256[16] calldata proofGroth16,
        uint256[5] calldata publicInputGroth16
    ) external returns (bool) {
        return bridge.updateSingleStateLeaf(
            channelId,
            appStorageAddr,
            userChannelStorageKey,
            updatedStorageValue,
            updatedRoot,
            proofGroth16,
            publicInputGroth16
        );
    }

    function verifyProposedStateRoots(
        bytes32 channelId,
        uint8 forkId,
        uint16 proposedStateIndex,
        address[] calldata appStorageAddrs,
        uint256[][] calldata storageKeys,
        uint256[][] calldata updatedStorageValues,
        bytes32[] calldata updatedRoots,
        uint256[42] calldata proofTokamak,
        uint256[4] calldata preprocessTokamak,
        uint256[] calldata publicInputTokamak
    ) external returns (bool) {
        return bridge.verifyProposedStateRoots(
            channelId,
            forkId,
            proposedStateIndex,
            appStorageAddrs,
            storageKeys,
            updatedStorageValues,
            updatedRoots,
            proofTokamak,
            preprocessTokamak,
            publicInputTokamak
        );
    }

    function _deriveRootFromPublicInputs(uint256[] calldata publicInputs) private pure returns (bytes32) {
        if (publicInputs.length >= 2) {
            return bytes32((publicInputs[0] << 128) | (publicInputs[1] & ((1 << 128) - 1)));
        }
        return keccak256(abi.encode(publicInputs));
    }

    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    uint256[44] private __gap;
}
