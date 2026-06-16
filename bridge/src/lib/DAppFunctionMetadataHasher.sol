// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "../BridgeStructs.sol";

library DAppFunctionMetadataHasher {
    bytes32 private constant FUNCTION_ITEM_DOMAIN = keccak256("dapp.metadata.v1.function-item");
    bytes32 private constant FUNCTION_MERKLE_NODE_DOMAIN = keccak256("dapp.metadata.v1.function-merkle-node");
    bytes32 private constant INSTANCE_LAYOUT_DOMAIN = keccak256("dapp.metadata.v1.instance-layout");
    bytes32 private constant EVENT_LOG_ROOT_DOMAIN = keccak256("dapp.metadata.v1.event-log-root");
    bytes32 private constant EVENT_LOG_ITEM_DOMAIN = keccak256("dapp.metadata.v1.event-log-item");

    function hashFunctionMetadata(BridgeStructs.DAppFunctionMetadata calldata fnMetadata)
        internal
        pure
        returns (bytes32)
    {
        bytes32 eventLogsHash = keccak256(abi.encode(EVENT_LOG_ROOT_DOMAIN, fnMetadata.instanceLayout.eventLogs.length));
        for (uint256 i = 0; i < fnMetadata.instanceLayout.eventLogs.length; i++) {
            BridgeStructs.EventLogMetadata calldata eventLog = fnMetadata.instanceLayout.eventLogs[i];
            eventLogsHash = keccak256(
                abi.encode(EVENT_LOG_ITEM_DOMAIN, eventLogsHash, eventLog.startOffsetWords, eventLog.topicCount)
            );
        }

        bytes32 instanceLayoutHash = keccak256(
            abi.encode(
                INSTANCE_LAYOUT_DOMAIN,
                fnMetadata.instanceLayout.entryContractOffsetWords,
                fnMetadata.instanceLayout.functionSigOffsetWords,
                fnMetadata.instanceLayout.currentRootVectorOffsetWords,
                fnMetadata.instanceLayout.updatedRootVectorOffsetWords,
                eventLogsHash
            )
        );

        return keccak256(
            abi.encode(
                FUNCTION_ITEM_DOMAIN,
                fnMetadata.entryContract,
                fnMetadata.functionSig,
                fnMetadata.preprocessInputHash,
                instanceLayoutHash
            )
        );
    }

    function computeFunctionMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 levelLength = leaves.length;
        while (levelLength > 1) {
            uint256 nextLength = (levelLength + 1) / 2;
            for (uint256 i = 0; i < nextLength; i++) {
                uint256 leftIndex = i * 2;
                uint256 rightIndex = leftIndex + 1;
                bytes32 left = leaves[leftIndex];
                bytes32 right = rightIndex < levelLength ? leaves[rightIndex] : left;
                leaves[i] = hashFunctionMerklePair(left, right);
            }
            levelLength = nextLength;
        }
        return leaves[0];
    }

    function hashFunctionMerklePair(bytes32 left, bytes32 right) internal pure returns (bytes32) {
        (bytes32 first, bytes32 second) = left <= right ? (left, right) : (right, left);
        return keccak256(abi.encode(FUNCTION_MERKLE_NODE_DOMAIN, first, second));
    }
}
