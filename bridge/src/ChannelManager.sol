// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "./BridgeStructs.sol";
import {DAppManager} from "./DAppManager.sol";
import {ITokamakVerifier} from "./interfaces/ITokamakVerifier.sol";

contract ChannelManager {
    uint256 internal constant SPLIT_WORD_SIZE = 2;
    uint256 internal constant STORAGE_WRITE_VALUE_OFFSET = 2;

    error OnlyBridgeCore();
    error OnlyTokenVault();
    error TokenVaultAlreadySet();
    error StorageAddressVectorLengthMismatch();
    error UnexpectedCurrentRootVector();
    error UnsupportedChannelFunction(address entryContract, bytes4 functionSig);
    error TokamakProofRejected();
    error InvalidTokenVaultTreeIndex();
    error PreprocessInputHashMismatch(bytes32 expectedHash, bytes32 actualHash);
    error APubBlockHashMismatch(bytes32 expectedHash, bytes32 actualHash);
    error APubUserTooShort(uint256 expectedLength, uint256 actualLength);
    error APubUserWordOutOfRange(uint256 index, uint256 value);
    error EntryContractPublicInputOutOfRange(uint256 value);
    error FunctionSigPublicInputOutOfRange(uint256 value);
    error InvalidStorageWriteStorageIndex(uint8 storageAddrIndex);
    error TokenVaultRootUpdateWithoutStorageWrite();

    uint256 public immutable channelId;
    uint256 public immutable dappId;
    address public immutable leader;
    bytes32 public immutable aPubBlockHash;
    uint256 public immutable tokenVaultTreeIndex;
    address public immutable tokenVaultStorageAddress;
    address public immutable bridgeCore;
    ITokamakVerifier public immutable tokamakVerifier;

    address public tokenVault;
    bytes32 public currentRootVectorHash;

    bytes32[] private _currentRootVector;
    address[] private _managedStorageAddresses;

    mapping(bytes32 => bool) private _allowedFunctionKeys;
    mapping(bytes32 => BridgeStructs.FunctionConfig) private _functionConfigs;
    mapping(bytes32 => bytes32) private _functionKeyByPreprocessInputHash;
    mapping(bytes32 => uint8[]) private _functionTokenVaultWriteOffsets;
    BridgeStructs.FunctionReference[] private _allowedFunctions;

    mapping(uint256 => bytes32) private _latestTokenVaultLeaves;
    uint256[] private _storedLeafIndices;
    mapping(uint256 => bool) private _knownLeafIndex;

    event TokenVaultBound(address indexed tokenVault);
    event TokamakStateUpdateAccepted(bytes4 indexed functionSig, address indexed entryContract);
    event VaultRootUpdateApplied(bytes32 indexed currentRoot, bytes32 indexed updatedRoot, uint256 leafIndex);
    event RootVectorUpdated(bytes32 indexed rootVectorHash, bytes32[] rootVector);
    event StorageWriteObserved(address indexed storageAddr, uint256 leafIndex, uint256 value);

    constructor(
        uint256 channelId_,
        uint256 dappId_,
        address leader_,
        bytes32 aPubBlockHash_,
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
        aPubBlockHash = aPubBlockHash_;
        bridgeCore = bridgeCore_;
        tokamakVerifier = tokamakVerifier_;

        if (tokenVaultTreeIndex_ >= initialRootVector_.length) {
            revert InvalidTokenVaultTreeIndex();
        }
        tokenVaultTreeIndex = tokenVaultTreeIndex_;
        tokenVaultStorageAddress = managedStorageAddresses_[tokenVaultTreeIndex_];

        if (managedStorageAddresses_.length != initialRootVector_.length) {
            revert StorageAddressVectorLengthMismatch();
        }

        _replaceCurrentRootVector(initialRootVector_);
        _replaceManagedStorageAddresses(managedStorageAddresses_);

        for (uint256 i = 0; i < allowedFunctions_.length; i++) {
            bytes32 functionKey =
                _computeFunctionKey(allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig);
            _allowedFunctionKeys[functionKey] = true;
            _allowedFunctions.push(allowedFunctions_[i]);
            BridgeStructs.FunctionConfig memory functionConfig = dAppManager_.getFunctionMetadata(
                dappId_,
                allowedFunctions_[i].entryContract,
                allowedFunctions_[i].functionSig
            );
            _functionConfigs[functionKey] = functionConfig;
            _functionKeyByPreprocessInputHash[functionConfig.preprocessInputHash] = functionKey;

            address[] memory functionStorages =
                dAppManager_.getFunctionStorages(dappId_, allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig);
            BridgeStructs.StorageWriteMetadata[] memory storageWrites =
                dAppManager_.getFunctionStorageWrites(dappId_, allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig);
            for (uint256 j = 0; j < storageWrites.length; j++) {
                uint8 storageAddrIndex = storageWrites[j].storageAddrIndex;
                if (storageAddrIndex >= functionStorages.length) {
                    revert InvalidStorageWriteStorageIndex(storageAddrIndex);
                }
                if (functionStorages[storageAddrIndex] == tokenVaultStorageAddress) {
                    _functionTokenVaultWriteOffsets[functionKey].push(storageWrites[j].aPubOffsetWords);
                }
            }
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

    function executeChannelTransaction(BridgeStructs.TokamakProofPayload calldata payload) external returns (bool) {
        bytes32 actualPreprocessInputHash =
            keccak256(abi.encode(payload.functionPreprocessPart1, payload.functionPreprocessPart2));
        bytes32 functionKey = _functionKeyByPreprocessInputHash[actualPreprocessInputHash];
        if (!_allowedFunctionKeys[functionKey]) {
            revert UnsupportedChannelFunction(address(0), bytes4(0));
        }
        BridgeStructs.FunctionConfig memory functionConfig = _functionConfigs[functionKey];

        _assertAPubUserLayout(payload.aPubUser, functionConfig);
        _assertCurrentRootVectorFromAPubUser(payload.aPubUser, functionConfig.currentRootVectorOffsetWords);

        address entryContract = _decodeAddressFromAPubUser(payload.aPubUser, functionConfig.entryContractOffsetWords);
        bytes4 functionSig = _decodeFunctionSigFromAPubUser(payload.aPubUser, functionConfig.functionSigOffsetWords);
        if (_computeFunctionKey(entryContract, functionSig) != functionKey) {
            revert UnsupportedChannelFunction(entryContract, functionSig);
        }

        bytes32 expectedPreprocessInputHash = functionConfig.preprocessInputHash;
        if (actualPreprocessInputHash != expectedPreprocessInputHash) {
            revert PreprocessInputHashMismatch(expectedPreprocessInputHash, actualPreprocessInputHash);
        }
        bytes32 actualAPubBlockHash = keccak256(abi.encode(payload.aPubBlock));
        if (actualAPubBlockHash != aPubBlockHash) {
            revert APubBlockHashMismatch(aPubBlockHash, actualAPubBlockHash);
        }

        bytes32[] memory updatedRootVector =
            _decodeUpdatedRootVectorFromAPubUser(payload.aPubUser, functionConfig.updatedRootVectorOffsetWords);
        bytes32 currentTokenVaultRoot = _currentRootVector[tokenVaultTreeIndex];
        bytes32 updatedTokenVaultRoot = updatedRootVector[tokenVaultTreeIndex];
        bool hasTokenVaultStorageWrite = _hasTokenVaultStorageWrite(functionKey);

        if (updatedTokenVaultRoot != currentTokenVaultRoot && !hasTokenVaultStorageWrite) {
            revert TokenVaultRootUpdateWithoutStorageWrite();
        }

        bool ok = tokamakVerifier.verify(
            payload.proofPart1,
            payload.proofPart2,
            payload.functionPreprocessPart1,
            payload.functionPreprocessPart2,
            payload.aPubUser,
            payload.aPubBlock
        );
        if (!ok) revert TokamakProofRejected();

        if (!hasTokenVaultStorageWrite) {
            _replaceCurrentRootVector(updatedRootVector);
        } else {
            updatedRootVector[tokenVaultTreeIndex] = currentTokenVaultRoot;
            _setCurrentRootVector(updatedRootVector);
            _applyTokenVaultRootUpdate(currentTokenVaultRoot, updatedTokenVaultRoot);
            _observeStorageWrites(functionKey, payload.aPubUser, currentTokenVaultRoot, updatedTokenVaultRoot);
        }

        emit TokamakStateUpdateAccepted(functionSig, entryContract);
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

        _applyTokenVaultRootUpdate(currentTokenVaultRoot, updatedTokenVaultRoot);
        _applyVaultUpdate(currentTokenVaultRoot, updatedTokenVaultRoot, leafIndex, latestLeafValue);
        return true;
    }

    function getCurrentRootVector() external view returns (bytes32[] memory) {
        return _copyBytes32Array(_currentRootVector);
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

    function getFunctionTokenVaultWriteOffsets(address entryContract, bytes4 functionSig)
        external
        view
        returns (uint8[] memory out)
    {
        bytes32 functionKey = _computeFunctionKey(entryContract, functionSig);
        uint8[] storage source = _functionTokenVaultWriteOffsets[functionKey];
        out = new uint8[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }

    function _assertCurrentRootVectorFromAPubUser(uint256[] calldata aPubUser, uint256 currentRootVectorOffsetWords)
        private
        view
    {
        for (uint256 i = 0; i < _currentRootVector.length; i++) {
            if (
                _decodeBytes32FromAPubUser(aPubUser, currentRootVectorOffsetWords + i * SPLIT_WORD_SIZE)
                    != _currentRootVector[i]
            ) {
                revert UnexpectedCurrentRootVector();
            }
        }
    }

    function _replaceCurrentRootVector(bytes32[] memory newRootVector) private {
        _setCurrentRootVector(newRootVector);
        _publishCurrentRootVector(newRootVector);
    }

    function _setCurrentRootVector(bytes32[] memory newRootVector) private {
        delete _currentRootVector;
        for (uint256 i = 0; i < newRootVector.length; i++) {
            _currentRootVector.push(newRootVector[i]);
        }
    }

    function _replaceManagedStorageAddresses(address[] memory storageAddresses) private {
        delete _managedStorageAddresses;
        for (uint256 i = 0; i < storageAddresses.length; i++) {
            _managedStorageAddresses.push(storageAddresses[i]);
        }
    }

    function _assertAPubUserLayout(uint256[] calldata aPubUser, BridgeStructs.FunctionConfig memory functionConfig)
        private
        view
    {
        uint256 requiredLength = functionConfig.updatedRootVectorOffsetWords + _currentRootVector.length * SPLIT_WORD_SIZE;
        uint256 currentRootVectorRequiredLength =
            functionConfig.currentRootVectorOffsetWords + _currentRootVector.length * SPLIT_WORD_SIZE;
        if (currentRootVectorRequiredLength > requiredLength) {
            requiredLength = currentRootVectorRequiredLength;
        }
        uint256 entryContractRequiredLength = functionConfig.entryContractOffsetWords + SPLIT_WORD_SIZE;
        if (entryContractRequiredLength > requiredLength) {
            requiredLength = entryContractRequiredLength;
        }
        uint256 functionSigRequiredLength = functionConfig.functionSigOffsetWords + SPLIT_WORD_SIZE;
        if (functionSigRequiredLength > requiredLength) {
            requiredLength = functionSigRequiredLength;
        }
        if (aPubUser.length < requiredLength) {
            revert APubUserTooShort(requiredLength, aPubUser.length);
        }
    }

    function _decodeUpdatedRootVectorFromAPubUser(uint256[] calldata aPubUser, uint256 updatedRootVectorOffsetWords)
        private
        view
        returns (bytes32[] memory updatedRootVector)
    {
        updatedRootVector = new bytes32[](_currentRootVector.length);
        for (uint256 i = 0; i < _currentRootVector.length; i++) {
            updatedRootVector[i] =
                _decodeBytes32FromAPubUser(aPubUser, updatedRootVectorOffsetWords + i * SPLIT_WORD_SIZE);
        }
    }

    function _observeStorageWrites(
        bytes32 functionKey,
        uint256[] calldata aPubUser,
        bytes32 currentTokenVaultRoot,
        bytes32 updatedTokenVaultRoot
    ) private {
        uint8[] storage tokenVaultWriteOffsets = _functionTokenVaultWriteOffsets[functionKey];

        for (uint256 i = 0; i < tokenVaultWriteOffsets.length; i++) {
            uint256 aPubOffsetWords = tokenVaultWriteOffsets[i];
            uint256 leafIndex = _decodeSplitWord(aPubUser, aPubOffsetWords);
            uint256 value = _decodeSplitWord(aPubUser, aPubOffsetWords + STORAGE_WRITE_VALUE_OFFSET);

            emit StorageWriteObserved(tokenVaultStorageAddress, leafIndex, value);
            _applyVaultUpdate(currentTokenVaultRoot, updatedTokenVaultRoot, leafIndex, bytes32(value));
        }
    }

    function _hasTokenVaultStorageWrite(bytes32 functionKey) private view returns (bool) {
        return _functionTokenVaultWriteOffsets[functionKey].length != 0;
    }

    function _decodeBytes32FromAPubUser(uint256[] calldata aPubUser, uint256 startIndex)
        private
        pure
        returns (bytes32)
    {
        return bytes32(_decodeSplitWord(aPubUser, startIndex));
    }

    function _decodeAddressFromAPubUser(uint256[] calldata aPubUser, uint256 startIndex)
        private
        pure
        returns (address)
    {
        uint256 combined = _decodeSplitWord(aPubUser, startIndex);
        if (combined > type(uint160).max) {
            revert EntryContractPublicInputOutOfRange(combined);
        }
        return address(uint160(combined));
    }

    function _decodeFunctionSigFromAPubUser(uint256[] calldata aPubUser, uint256 startIndex)
        private
        pure
        returns (bytes4)
    {
        uint256 combined = _decodeSplitWord(aPubUser, startIndex);
        if (combined > type(uint32).max) {
            revert FunctionSigPublicInputOutOfRange(combined);
        }
        return bytes4(uint32(combined));
    }

    function _decodeSplitWord(uint256[] calldata words, uint256 startIndex) private pure returns (uint256 combined) {
        uint256 lower = words[startIndex];
        uint256 upper = words[startIndex + 1];
        if (lower > type(uint128).max) {
            revert APubUserWordOutOfRange(startIndex, lower);
        }
        if (upper > type(uint128).max) {
            revert APubUserWordOutOfRange(startIndex + 1, upper);
        }
        combined = lower | (upper << 128);
    }

    function _computeFunctionKey(address entryContract, bytes4 functionSig) private pure returns (bytes32) {
        return keccak256(abi.encode(entryContract, functionSig));
    }

    function _publishCurrentRootVector(bytes32[] memory rootVector) private {
        currentRootVectorHash = keccak256(abi.encode(rootVector));
        emit RootVectorUpdated(currentRootVectorHash, rootVector);
    }

    function _applyTokenVaultRootUpdate(bytes32 currentTokenVaultRoot, bytes32 updatedTokenVaultRoot) private {
        if (_currentRootVector[tokenVaultTreeIndex] != currentTokenVaultRoot) {
            revert UnexpectedCurrentRootVector();
        }

        _currentRootVector[tokenVaultTreeIndex] = updatedTokenVaultRoot;
        _publishCurrentRootVector(_copyBytes32Array(_currentRootVector));
    }

    function _applyVaultUpdate(
        bytes32 currentTokenVaultRoot,
        bytes32 updatedTokenVaultRoot,
        uint256 leafIndex,
        bytes32 latestLeafValue
    ) private {
        _setLatestTokenVaultLeaf(leafIndex, latestLeafValue);
        emit VaultRootUpdateApplied(currentTokenVaultRoot, updatedTokenVaultRoot, leafIndex);
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
