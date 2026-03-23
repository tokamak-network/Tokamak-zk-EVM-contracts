// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "./BridgeStructs.sol";
import {DAppManager} from "./DAppManager.sol";
import {ITokamakVerifier} from "./interfaces/ITokamakVerifier.sol";

contract ChannelManager {
    error OnlyBridgeCore();
    error OnlyTokenVault();
    error TokenVaultAlreadySet();
    error RootVectorLengthMismatch();
    error StorageAddressVectorLengthMismatch();
    error UnexpectedCurrentRootVector();
    error UnsupportedChannelFunction(address entryContract, bytes4 functionSig);
    error TokamakProofRejected();
    error InvalidTokenVaultTreeIndex();

    uint256 public immutable channelId;
    uint256 public immutable dappId;
    address public immutable leader;
    bytes32 public immutable channelInstanceHash;
    uint256 public immutable tokenVaultTreeIndex;
    address public immutable bridgeCore;
    DAppManager public immutable dAppManager;
    ITokamakVerifier public immutable tokamakVerifier;

    address public tokenVault;

    bytes32[] private _currentRootVector;
    bytes32[][] private _rootHistory;
    address[] private _managedStorageAddresses;

    mapping(bytes32 => bool) private _allowedFunctionKeys;
    BridgeStructs.FunctionReference[] private _allowedFunctions;

    mapping(uint256 => bytes32) private _latestTokenVaultLeaves;
    uint256[] private _storedLeafIndices;
    mapping(uint256 => bool) private _knownLeafIndex;

    event TokenVaultBound(address indexed tokenVault);
    event TokamakStateUpdateAccepted(bytes4 indexed functionSig, address indexed entryContract);
    event VaultRootUpdateApplied(bytes32 indexed currentRoot, bytes32 indexed updatedRoot, uint256 leafIndex);

    constructor(
        uint256 channelId_,
        uint256 dappId_,
        address leader_,
        bytes32 channelInstanceHash_,
        uint256 tokenVaultTreeIndex_,
        bytes32[] memory initialRootVector_,
        address[] memory managedStorageAddresses_,
        BridgeStructs.FunctionReference[] memory allowedFunctions_,
        address bridgeCore_,
        DAppManager dAppManager_,
        ITokamakVerifier tokamakVerifier_
    ) {
        channelId = channelId_;
        dappId = dappId_;
        leader = leader_;
        channelInstanceHash = channelInstanceHash_;
        bridgeCore = bridgeCore_;
        dAppManager = dAppManager_;
        tokamakVerifier = tokamakVerifier_;

        if (tokenVaultTreeIndex_ >= initialRootVector_.length) {
            revert InvalidTokenVaultTreeIndex();
        }
        tokenVaultTreeIndex = tokenVaultTreeIndex_;

        if (managedStorageAddresses_.length != initialRootVector_.length) {
            revert StorageAddressVectorLengthMismatch();
        }

        _replaceCurrentRootVector(initialRootVector_);
        _replaceManagedStorageAddresses(managedStorageAddresses_);

        for (uint256 i = 0; i < allowedFunctions_.length; i++) {
            bytes32 functionKey =
                dAppManager.computeFunctionKey(allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig);
            _allowedFunctionKeys[functionKey] = true;
            _allowedFunctions.push(allowedFunctions_[i]);
        }
    }

    modifier onlyBridgeCore() {
        if (msg.sender != bridgeCore) revert OnlyBridgeCore();
        _;
    }

    modifier onlyTokenVault() {
        if (msg.sender != tokenVault) revert OnlyTokenVault();
        _;
    }

    function bindTokenVault(address tokenVault_) external onlyBridgeCore {
        if (tokenVault != address(0)) revert TokenVaultAlreadySet();
        tokenVault = tokenVault_;
        emit TokenVaultBound(tokenVault_);
    }

    function submitTokamakProof(
        bytes calldata proof,
        BridgeStructs.TokamakTransactionInstance calldata instance
    ) external returns (bool) {
        _assertCurrentRootVector(instance.currentRootVector);

        bytes32 functionKey = dAppManager.computeFunctionKey(instance.entryContract, instance.functionSig);
        if (!_allowedFunctionKeys[functionKey]) {
            revert UnsupportedChannelFunction(instance.entryContract, instance.functionSig);
        }

        BridgeStructs.FunctionConfig memory cfg =
            dAppManager.getFunctionMetadata(dappId, instance.entryContract, instance.functionSig);

        bool ok = tokamakVerifier.verifyTokamakProof(
            proof, instance, channelInstanceHash, cfg.instanceHash, cfg.preprocessHash
        );
        if (!ok) revert TokamakProofRejected();

        _replaceCurrentRootVector(instance.updatedRootVector);
        emit TokamakStateUpdateAccepted(instance.functionSig, instance.entryContract);
        return true;
    }

    function applyVaultUpdate(
        bytes32 currentTokenVaultRoot,
        bytes32 updatedTokenVaultRoot,
        uint256 leafIndex,
        bytes32 latestLeafValue
    ) external onlyTokenVault returns (bool) {
        if (_currentRootVector[tokenVaultTreeIndex] != currentTokenVaultRoot) {
            revert UnexpectedCurrentRootVector();
        }

        _currentRootVector[tokenVaultTreeIndex] = updatedTokenVaultRoot;
        _pushHistorySnapshot(_currentRootVector);
        _setLatestTokenVaultLeaf(leafIndex, latestLeafValue);

        emit VaultRootUpdateApplied(currentTokenVaultRoot, updatedTokenVaultRoot, leafIndex);
        return true;
    }

    function getCurrentRootVector() external view returns (bytes32[] memory) {
        return _copyBytes32Array(_currentRootVector);
    }

    function getRootHistoryLength() external view returns (uint256) {
        return _rootHistory.length;
    }

    function getRootHistorySnapshot(uint256 index) external view returns (bytes32[] memory) {
        return _copyBytes32Array(_rootHistory[index]);
    }

    function getManagedStorageAddresses() external view returns (address[] memory) {
        return _copyAddresses(_managedStorageAddresses);
    }

    function getManagedStorageAddress(uint256 index) external view returns (address) {
        return _managedStorageAddresses[index];
    }

    function getAllowedFunctions() external view returns (BridgeStructs.FunctionReference[] memory out) {
        out = new BridgeStructs.FunctionReference[](_allowedFunctions.length);
        for (uint256 i = 0; i < _allowedFunctions.length; i++) {
            out[i] = _allowedFunctions[i];
        }
    }

    function getStoredLeafIndices() external view returns (uint256[] memory out) {
        out = new uint256[](_storedLeafIndices.length);
        for (uint256 i = 0; i < _storedLeafIndices.length; i++) {
            out[i] = _storedLeafIndices[i];
        }
    }

    function getLatestTokenVaultLeaf(uint256 leafIndex) external view returns (bytes32) {
        return _latestTokenVaultLeaves[leafIndex];
    }

    function _assertCurrentRootVector(bytes32[] calldata candidateCurrentRootVector) private view {
        if (candidateCurrentRootVector.length != _currentRootVector.length) {
            revert RootVectorLengthMismatch();
        }
        for (uint256 i = 0; i < candidateCurrentRootVector.length; i++) {
            if (candidateCurrentRootVector[i] != _currentRootVector[i]) {
                revert UnexpectedCurrentRootVector();
            }
        }
    }

    function _replaceCurrentRootVector(bytes32[] memory newRootVector) private {
        delete _currentRootVector;
        for (uint256 i = 0; i < newRootVector.length; i++) {
            _currentRootVector.push(newRootVector[i]);
        }
        _pushHistorySnapshot(newRootVector);
    }

    function _pushHistorySnapshot(bytes32[] memory snapshot) private {
        _rootHistory.push();
        uint256 snapshotIndex = _rootHistory.length - 1;
        for (uint256 i = 0; i < snapshot.length; i++) {
            _rootHistory[snapshotIndex].push(snapshot[i]);
        }
    }

    function _replaceManagedStorageAddresses(address[] memory storageAddresses) private {
        delete _managedStorageAddresses;
        for (uint256 i = 0; i < storageAddresses.length; i++) {
            _managedStorageAddresses.push(storageAddresses[i]);
        }
    }

    function _setLatestTokenVaultLeaf(uint256 leafIndex, bytes32 leafValue) private {
        if (!_knownLeafIndex[leafIndex]) {
            _knownLeafIndex[leafIndex] = true;
            _storedLeafIndices.push(leafIndex);
        }
        _latestTokenVaultLeaves[leafIndex] = leafValue;
    }

    function _copyBytes32Array(bytes32[] storage source) private view returns (bytes32[] memory out) {
        out = new bytes32[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }

    function _copyAddresses(address[] storage source) private view returns (address[] memory out) {
        out = new address[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }
}
