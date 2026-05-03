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
        bytes32 functionRoot,
        uint256 initialJoinToll,
        uint64 joinTollRefundCutoff1,
        uint16 joinTollRefundBps1,
        uint64 joinTollRefundCutoff2,
        uint16 joinTollRefundBps2,
        uint64 joinTollRefundCutoff3,
        uint16 joinTollRefundBps3,
        uint16 joinTollRefundBps4,
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
            functionRoot,
            initialJoinToll,
            joinTollRefundCutoff1,
            joinTollRefundBps1,
            joinTollRefundCutoff2,
            joinTollRefundBps2,
            joinTollRefundCutoff3,
            joinTollRefundBps3,
            joinTollRefundBps4,
            dAppManager,
            expectedManagedStorageCount
        );

        return address(channelManager);
    }
}
