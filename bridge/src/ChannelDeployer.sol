// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BridgeStructs } from "./BridgeStructs.sol";
import { ChannelManager } from "./ChannelManager.sol";
import { DAppManager } from "./DAppManager.sol";
import { TokamakEnvironment } from "./generated/TokamakEnvironment.sol";

contract ChannelDeployer {
    error ManagedStorageCountMismatch(uint256 expectedCount, uint256 actualCount);

    function deployChannelManager(
        uint256 channelId,
        uint256 dappId,
        address leader,
        uint256 channelTokenVaultTreeIndex,
        address bridgeCore,
        BridgeStructs.DAppVerifierSnapshot calldata verifierSnapshot,
        bytes32 dappMetadataDigestSchema,
        bytes32 dappMetadataDigest,
        uint256 initialJoinFee,
        uint64 joinFeeRefundCutoff1,
        uint16 joinFeeRefundBps1,
        uint64 joinFeeRefundCutoff2,
        uint16 joinFeeRefundBps2,
        uint64 joinFeeRefundCutoff3,
        uint16 joinFeeRefundBps3,
        uint16 joinFeeRefundBps4,
        DAppManager dAppManager,
        uint256 expectedManagedStorageCount
    ) external returns (address manager) {
        address[] memory managedStorageAddresses = dAppManager.getManagedStorageAddresses(dappId);
        if (managedStorageAddresses.length != expectedManagedStorageCount) {
            revert ManagedStorageCountMismatch(
                expectedManagedStorageCount, managedStorageAddresses.length
            );
        }

        BridgeStructs.FunctionReference[] memory registeredFunctions =
            dAppManager.getRegisteredFunctions(dappId);

        bytes32[] memory initialRootVector = new bytes32[](managedStorageAddresses.length);
        for (uint256 i = 0; i < managedStorageAddresses.length; i++) {
            initialRootVector[i] = TokamakEnvironment.ZERO_FILLED_TREE_ROOT;
        }

        ChannelManager channelManager = new ChannelManager(
            channelId,
            dappId,
            leader,
            channelTokenVaultTreeIndex,
            initialRootVector,
            managedStorageAddresses,
            registeredFunctions,
            bridgeCore,
            verifierSnapshot,
            dappMetadataDigestSchema,
            dappMetadataDigest,
            initialJoinFee,
            joinFeeRefundCutoff1,
            joinFeeRefundBps1,
            joinFeeRefundCutoff2,
            joinFeeRefundBps2,
            joinFeeRefundCutoff3,
            joinFeeRefundBps3,
            joinFeeRefundBps4,
            dAppManager
        );

        return address(channelManager);
    }
}
