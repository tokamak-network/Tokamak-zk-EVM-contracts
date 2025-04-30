// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRollup, L2_LOG_ADDRESS_OFFSET, L2_LOG_KEY_OFFSET, L2_LOG_VALUE_OFFSET, LogProcessingOutput, PubdataSource, BLS_MODULUS, PUBDATA_COMMITMENT_SIZE, PUBDATA_COMMITMENT_CLAIMED_VALUE_OFFSET, PUBDATA_COMMITMENT_COMMITMENT_OFFSET, MAX_NUMBER_OF_BLOBS, TOTAL_BLOBS_IN_COMMITMENT, BLOB_SIZE_BYTES} from "./interface/IRollup.sol";
import {ReentrancyGuard} from "./common/ReentrancyGuard.sol";

contract Rollup is IRollup, ReentrancyGuard {

    /// @dev Process one batch commit using the previous batch StoredBatchInfo
    /// @dev returns new batch StoredBatchInfo
    /// @notice Does not change storage
    function _commitOneBatch(
        StoredBatchInfo memory _previousBatch,
        CommitBatchInfo calldata _newBatch,
        bytes32 _expectedSystemContractUpgradeTxHash
    ) internal view returns (StoredBatchInfo memory) {
        
    }

    /// @dev Check that L2 logs are proper and batch contain all meta information for them
    /// @dev The logs processed here should line up such that only one log for each key from the
    ///      SystemLogKey enum in Constants.sol is processed per new batch.
    /// @dev Data returned from here will be used to form the batch commitment.
    function _processL2Logs(
        CommitBatchInfo calldata _newBatch,
        bytes32 _expectedSystemContractUpgradeTxHash
    ) internal pure returns (LogProcessingOutput memory logOutput) {
        
    }

    /// @inheritdoc IRollup
    function commitBatches(
        StoredBatchInfo memory _lastCommittedBatchData,
        CommitBatchInfo[] calldata _newBatchesData
    ) external nonReentrant {
        _commitBatches(_lastCommittedBatchData, _newBatchesData);
    }

    function _commitBatches(
        StoredBatchInfo memory _lastCommittedBatchData,
        CommitBatchInfo[] calldata _newBatchesData
    ) internal {

    }

    function proveBatches(
        StoredBatchInfo calldata _prevBatch,
        StoredBatchInfo[] calldata _committedBatches,
        ProofInput calldata _proof
    ) external nonReentrant {

    }

    function executeBatches(
        StoredBatchInfo[] calldata _batchesData
    ) external nonReentrant {

    }

    function revertBatches(uint256 _newLastBatch) external nonReentrant {
        
    }


}