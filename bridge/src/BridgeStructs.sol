// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library BridgeStructs {
    struct NoteReceivePubKey {
        bytes32 x;
        uint8 yParity;
    }

    struct ChannelTokenVaultRegistration {
        bool exists;
        address l2Address;
        bytes32 channelTokenVaultKey;
        uint256 leafIndex;
        uint256 joinFeePaid;
        uint64 joinedAt;
        NoteReceivePubKey noteReceivePubKey;
        bool isZeroBalance;
    }

    struct EventLogMetadata {
        uint16 startOffsetWords;
        uint8 topicCount;
    }

    struct StorageMetadata {
        address storageAddr;
        bytes32[] preAllocatedKeys;
        uint8[] userStorageSlots;
        bool isChannelTokenVaultStorage;
    }

    struct InstanceLayout {
        uint8 entryContractOffsetWords;
        uint8 functionSigOffsetWords;
        uint8 currentRootVectorOffsetWords;
        uint8 updatedRootVectorOffsetWords;
        EventLogMetadata[] eventLogs;
    }

    struct DAppFunctionMetadata {
        address entryContract;
        bytes4 functionSig;
        bytes32 preprocessInputHash;
        InstanceLayout instanceLayout;
    }

    struct DAppVerifierSnapshot {
        address grothVerifier;
        string grothVerifierCompatibleBackendVersion;
        address tokamakVerifier;
        string tokamakVerifierCompatibleBackendVersion;
    }

    struct GrothProof {
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
    }

    struct FunctionReference {
        address entryContract;
        bytes4 functionSig;
    }

    struct FunctionConfig {
        bytes32 preprocessInputHash;
        uint8 entryContractOffsetWords;
        uint8 functionSigOffsetWords;
        uint8 currentRootVectorOffsetWords;
        uint8 updatedRootVectorOffsetWords;
    }

    struct GrothUpdate {
        bytes32[] currentRootVector;
        bytes32 updatedRoot;
        bytes32 currentUserKey;
        uint256 currentUserValue;
        bytes32 updatedUserKey;
        uint256 updatedUserValue;
    }

    struct TokamakProofPayload {
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint128[] functionPreprocessPart1;
        uint256[] functionPreprocessPart2;
        uint256[] aPubUser;
        uint256[] aPubBlock;
    }
}
