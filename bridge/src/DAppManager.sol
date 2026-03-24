// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {BridgeStructs} from "./BridgeStructs.sol";

contract DAppManager is Ownable {
    error UnknownDApp(uint256 dappId);
    error DuplicateDApp(uint256 dappId);
    error EmptyStorageLayout(uint256 dappId);
    error EmptyFunctionList(uint256 dappId);
    error EmptyFunctionStorageList(bytes4 functionSig);
    error DuplicateStorageAddress(uint256 dappId, address storageAddr);
    error UnknownStorageAddress(uint256 dappId, address storageAddr);
    error DuplicateFunction(uint256 dappId, address entryContract, bytes4 functionSig);
    error UnsupportedChannelFunction(uint256 dappId, address entryContract, bytes4 functionSig);
    error MissingTokenVaultStorageAddress(uint256 dappId);
    error MultipleTokenVaultStorageAddresses(uint256 dappId, address firstStorageAddr, address secondStorageAddr);
    error MissingPreprocessInputHash(uint256 dappId, address entryContract, bytes4 functionSig);
    error DuplicatePreprocessInputHash(uint256 dappId, bytes32 preprocessInputHash);
    error InvalidFunctionStorageWriteStorageIndex(
        uint256 dappId,
        address entryContract,
        bytes4 functionSig,
        uint8 storageAddrIndex
    );

    struct DAppInfo {
        bool exists;
        bytes32 labelHash;
        uint256 tokenVaultTreeIndex;
    }

    mapping(uint256 => DAppInfo) private _dapps;
    mapping(uint256 => mapping(bytes32 => bool)) private _supportedFunctions;
    mapping(uint256 => mapping(bytes32 => BridgeStructs.FunctionConfig)) private _functionConfigs;
    mapping(uint256 => mapping(bytes32 => BridgeStructs.StorageWriteMetadata[])) private _functionStorageWrites;
    mapping(uint256 => mapping(bytes32 => bool)) private _knownPreprocessInputHash;
    mapping(uint256 => BridgeStructs.FunctionReference[]) private _registeredFunctions;

    mapping(uint256 => address[]) private _managedStorageAddresses;
    mapping(uint256 => mapping(address => bool)) private _knownStorageAddress;
    mapping(uint256 => mapping(address => bool)) private _isTokenVaultStorage;
    mapping(uint256 => mapping(address => bytes32[])) private _preAllocatedKeys;
    mapping(uint256 => mapping(address => uint8[])) private _userStorageSlots;

    event DAppRegistered(
        uint256 indexed dappId,
        bytes32 labelHash,
        uint256 storageCount,
        uint256 functionCount
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function registerDApp(
        uint256 dappId,
        bytes32 labelHash,
        BridgeStructs.StorageMetadata[] calldata storages,
        BridgeStructs.DAppFunctionMetadata[] calldata functions
    ) external onlyOwner {
        if (_dapps[dappId].exists) {
            revert DuplicateDApp(dappId);
        }
        if (storages.length == 0) {
            revert EmptyStorageLayout(dappId);
        }
        if (functions.length == 0) {
            revert EmptyFunctionList(dappId);
        }

        (uint256 tokenVaultTreeIndex, address tokenVaultStorageAddress) = _storeStorageLayout(dappId, storages);
        _storeFunctions(dappId, functions, tokenVaultStorageAddress);

        _dapps[dappId] = DAppInfo({
            exists: true,
            labelHash: labelHash,
            tokenVaultTreeIndex: tokenVaultTreeIndex
        });

        emit DAppRegistered(dappId, labelHash, storages.length, functions.length);
    }

    function isSupportedFunction(uint256 dappId, address entryContract, bytes4 functionSig)
        external
        view
        returns (bool)
    {
        if (!_dapps[dappId].exists) {
            return false;
        }
        return _supportedFunctions[dappId][computeFunctionKey(entryContract, functionSig)];
    }

    function getFunctionMetadata(uint256 dappId, address entryContract, bytes4 functionSig)
        external
        view
        returns (BridgeStructs.FunctionConfig memory)
    {
        bytes32 functionKey = computeFunctionKey(entryContract, functionSig);
        if (!_supportedFunctions[dappId][functionKey]) {
            revert UnsupportedChannelFunction(dappId, entryContract, functionSig);
        }
        return _functionConfigs[dappId][functionKey];
    }

    function getFunctionStorageWrites(uint256 dappId, address entryContract, bytes4 functionSig)
        external
        view
        returns (BridgeStructs.StorageWriteMetadata[] memory)
    {
        bytes32 functionKey = computeFunctionKey(entryContract, functionSig);
        if (!_supportedFunctions[dappId][functionKey]) {
            revert UnsupportedChannelFunction(dappId, entryContract, functionSig);
        }
        return _copyStorageWrites(_functionStorageWrites[dappId][functionKey]);
    }

    function getDAppInfo(uint256 dappId) external view returns (DAppInfo memory) {
        if (!_dapps[dappId].exists) {
            revert UnknownDApp(dappId);
        }
        return _dapps[dappId];
    }

    function getRegisteredFunctions(uint256 dappId)
        external
        view
        returns (BridgeStructs.FunctionReference[] memory out)
    {
        _requireDApp(dappId);

        BridgeStructs.FunctionReference[] storage refs = _registeredFunctions[dappId];
        out = new BridgeStructs.FunctionReference[](refs.length);
        for (uint256 i = 0; i < refs.length; i++) {
            out[i] = refs[i];
        }
    }

    function getManagedStorageAddresses(uint256 dappId) external view returns (address[] memory) {
        _requireDApp(dappId);
        return _copyAddresses(_managedStorageAddresses[dappId]);
    }

    function getTokenVaultTreeIndex(uint256 dappId) external view returns (uint256) {
        return _requireDApp(dappId).tokenVaultTreeIndex;
    }

    function getPreAllocKeys(uint256 dappId, address storageAddr) external view returns (bytes32[] memory) {
        _requireKnownStorage(dappId, storageAddr);
        return _copyBytes32(_preAllocatedKeys[dappId][storageAddr]);
    }

    function getUserSlots(uint256 dappId, address storageAddr) external view returns (uint8[] memory) {
        _requireKnownStorage(dappId, storageAddr);
        return _copyUint8(_userStorageSlots[dappId][storageAddr]);
    }

    function isTokenVaultStorageAddress(uint256 dappId, address storageAddr) external view returns (bool) {
        _requireKnownStorage(dappId, storageAddr);
        return _isTokenVaultStorage[dappId][storageAddr];
    }

    function computeFunctionKey(address entryContract, bytes4 functionSig)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(entryContract, functionSig));
    }

    function _storeStorageLayout(uint256 dappId, BridgeStructs.StorageMetadata[] calldata storages)
        private
        returns (uint256 tokenVaultTreeIndex, address tokenVaultStorageAddress)
    {
        tokenVaultTreeIndex = type(uint256).max;

        for (uint256 i = 0; i < storages.length; i++) {
            BridgeStructs.StorageMetadata calldata storageMetadata = storages[i];
            if (_knownStorageAddress[dappId][storageMetadata.storageAddr]) {
                revert DuplicateStorageAddress(dappId, storageMetadata.storageAddr);
            }

            _knownStorageAddress[dappId][storageMetadata.storageAddr] = true;
            _managedStorageAddresses[dappId].push(storageMetadata.storageAddr);
            _isTokenVaultStorage[dappId][storageMetadata.storageAddr] = storageMetadata.isTokenVaultStorage;

            for (uint256 j = 0; j < storageMetadata.preAllocatedKeys.length; j++) {
                _preAllocatedKeys[dappId][storageMetadata.storageAddr].push(storageMetadata.preAllocatedKeys[j]);
            }
            for (uint256 j = 0; j < storageMetadata.userStorageSlots.length; j++) {
                _userStorageSlots[dappId][storageMetadata.storageAddr].push(storageMetadata.userStorageSlots[j]);
            }

            if (storageMetadata.isTokenVaultStorage) {
                if (tokenVaultStorageAddress != address(0)) {
                    revert MultipleTokenVaultStorageAddresses(
                        dappId, tokenVaultStorageAddress, storageMetadata.storageAddr
                    );
                }
                tokenVaultStorageAddress = storageMetadata.storageAddr;
                tokenVaultTreeIndex = i;
            }
        }

        if (tokenVaultStorageAddress == address(0)) {
            revert MissingTokenVaultStorageAddress(dappId);
        }
    }

    function _storeFunctions(
        uint256 dappId,
        BridgeStructs.DAppFunctionMetadata[] calldata functions,
        address tokenVaultStorageAddress
    ) private {
        for (uint256 i = 0; i < functions.length; i++) {
            BridgeStructs.DAppFunctionMetadata calldata fnMetadata = functions[i];
            bytes32 functionKey = computeFunctionKey(fnMetadata.entryContract, fnMetadata.functionSig);
            if (_supportedFunctions[dappId][functionKey]) {
                revert DuplicateFunction(dappId, fnMetadata.entryContract, fnMetadata.functionSig);
            }
            if (fnMetadata.preprocessInputHash == bytes32(0)) {
                revert MissingPreprocessInputHash(dappId, fnMetadata.entryContract, fnMetadata.functionSig);
            }
            if (_knownPreprocessInputHash[dappId][fnMetadata.preprocessInputHash]) {
                revert DuplicatePreprocessInputHash(dappId, fnMetadata.preprocessInputHash);
            }

            _supportedFunctions[dappId][functionKey] = true;
            _knownPreprocessInputHash[dappId][fnMetadata.preprocessInputHash] = true;
            _registeredFunctions[dappId].push(
                BridgeStructs.FunctionReference({
                    entryContract: fnMetadata.entryContract,
                    functionSig: fnMetadata.functionSig
                })
            );

            for (uint256 j = 0; j < fnMetadata.storageWrites.length; j++) {
                BridgeStructs.StorageWriteMetadata calldata storageWrite = fnMetadata.storageWrites[j];
                if (storageWrite.storageAddrIndex >= _managedStorageAddresses[dappId].length) {
                    revert InvalidFunctionStorageWriteStorageIndex(
                        dappId,
                        fnMetadata.entryContract,
                        fnMetadata.functionSig,
                        storageWrite.storageAddrIndex
                    );
                }
                address storageAddr = _managedStorageAddresses[dappId][storageWrite.storageAddrIndex];
                if (_isTokenVaultStorage[dappId][storageAddr] && storageAddr != tokenVaultStorageAddress) {
                    revert MultipleTokenVaultStorageAddresses(dappId, tokenVaultStorageAddress, storageAddr);
                }
                _functionStorageWrites[dappId][functionKey].push(
                    BridgeStructs.StorageWriteMetadata({
                        aPubOffsetWords: storageWrite.aPubOffsetWords,
                        storageAddrIndex: storageWrite.storageAddrIndex
                    })
                );
            }

            _functionConfigs[dappId][functionKey] = BridgeStructs.FunctionConfig({
                preprocessInputHash: fnMetadata.preprocessInputHash,
                entryContractOffsetWords: fnMetadata.entryContractOffsetWords,
                functionSigOffsetWords: fnMetadata.functionSigOffsetWords,
                currentRootVectorOffsetWords: fnMetadata.currentRootVectorOffsetWords,
                updatedRootVectorOffsetWords: fnMetadata.updatedRootVectorOffsetWords,
                exists: true
            });
        }
    }

    function _requireDApp(uint256 dappId) private view returns (DAppInfo memory info) {
        info = _dapps[dappId];
        if (!info.exists) {
            revert UnknownDApp(dappId);
        }
    }

    function _requireKnownStorage(uint256 dappId, address storageAddr) private view {
        _requireDApp(dappId);
        if (!_knownStorageAddress[dappId][storageAddr]) {
            revert UnknownStorageAddress(dappId, storageAddr);
        }
    }

    function _copyAddresses(address[] storage source) private view returns (address[] memory out) {
        out = new address[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }

    function _copyBytes32(bytes32[] storage source) private view returns (bytes32[] memory out) {
        out = new bytes32[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }

    function _copyUint8(uint8[] storage source) private view returns (uint8[] memory out) {
        out = new uint8[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }

    function _copyStorageWrites(BridgeStructs.StorageWriteMetadata[] storage source)
        private
        view
        returns (BridgeStructs.StorageWriteMetadata[] memory out)
    {
        out = new BridgeStructs.StorageWriteMetadata[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }
}
