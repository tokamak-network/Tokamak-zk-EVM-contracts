// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BridgeStructs } from "./BridgeStructs.sol";
import { ChannelManager } from "./ChannelManager.sol";
import { DAppManager } from "./DAppManager.sol";

contract ChannelDeployer {
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
        ChannelManager channelManager = new ChannelManager(
            channelId,
            dappId,
            leader,
            channelTokenVaultTreeIndex,
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
            dAppManager,
            expectedManagedStorageCount
        );

        return address(channelManager);
    }
}
