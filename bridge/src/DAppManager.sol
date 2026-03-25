// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BridgeStructs} from "./BridgeStructs.sol";

contract DAppManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    error UnknownDApp(uint256 dappId);
    error DuplicateDApp(uint256 dappId);
    error EmptyStorageLayout(uint256 dappId);
    error EmptyFunctionList(uint256 dappId);
    error EmptyFunctionStorageList(bytes4 functionSig);
    error DuplicateStorageAddress(uint256 dappId, address storageAddr);
    error UnknownStorageAddress(uint256 dappId, address storageAddr);
    error DuplicateFunction(uint256 dappId, address entryContract, bytes4 functionSig);
    error UnsupportedChannelFunction(uint256 dappId, address entryContract, bytes4 functionSig);
    error MissingChannelTokenVaultStorageAddress(uint256 dappId);
    error MultipleChannelTokenVaultStorageAddresses(uint256 dappId, address firstStorageAddr, address secondStorageAddr);
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
        uint256 channelTokenVaultTreeIndex;
    }

    mapping(uint256 => DAppInfo) private _dapps;
    mapping(uint256 => mapping(bytes32 => bool)) private _supportedFunctions;
    mapping(uint256 => mapping(bytes32 => BridgeStructs.FunctionConfig)) private _functionConfigs;
    mapping(uint256 => mapping(bytes32 => BridgeStructs.StorageWriteMetadata[])) private _functionStorageWrites;
    mapping(uint256 => mapping(bytes32 => bool)) private _knownPreprocessInputHash;
    mapping(uint256 => BridgeStructs.FunctionReference[]) private _registeredFunctions;

    mapping(uint256 => address[]) private _managedStorageAddresses;
    mapping(uint256 => mapping(address => bool)) private _knownStorageAddress;
    mapping(uint256 => mapping(address => bool)) private _isChannelTokenVaultStorage;
    mapping(uint256 => mapping(address => bytes32[])) private _preAllocatedKeys;
    mapping(uint256 => mapping(address => uint8[])) private _userStorageSlots;

    event DAppRegistered(
        uint256 indexed dappId,
        bytes32 labelHash,
        uint256 storageCount,
        uint256 functionCount
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        if (initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }
    }

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

        (uint256 channelTokenVaultTreeIndex, address channelTokenVaultStorageAddress) = _storeStorageLayout(dappId, storages);
        _storeFunctions(dappId, functions, channelTokenVaultStorageAddress);

        _dapps[dappId] = DAppInfo({
            exists: true,
            labelHash: labelHash,
            channelTokenVaultTreeIndex: channelTokenVaultTreeIndex
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
        returns (BridgeStructs.StorageWriteMetadata[] memory out)
    {
        bytes32 functionKey = computeFunctionKey(entryContract, functionSig);
        if (!_supportedFunctions[dappId][functionKey]) {
            revert UnsupportedChannelFunction(dappId, entryContract, functionSig);
        }
        BridgeStructs.StorageWriteMetadata[] storage storageWrites = _functionStorageWrites[dappId][functionKey];
        out = new BridgeStructs.StorageWriteMetadata[](storageWrites.length);
        for (uint256 i = 0; i < storageWrites.length; i++) {
            out[i] = storageWrites[i];
        }
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

    function getManagedStorageAddresses(uint256 dappId) external view returns (address[] memory out) {
        _requireDApp(dappId);
        address[] storage managedStorageAddresses = _managedStorageAddresses[dappId];
        out = new address[](managedStorageAddresses.length);
        for (uint256 i = 0; i < managedStorageAddresses.length; i++) {
            out[i] = managedStorageAddresses[i];
        }
    }

    function getChannelTokenVaultTreeIndex(uint256 dappId) external view returns (uint256) {
        return _requireDApp(dappId).channelTokenVaultTreeIndex;
    }

    function getPreAllocKeys(uint256 dappId, address storageAddr) external view returns (bytes32[] memory out) {
        _requireKnownStorage(dappId, storageAddr);
        bytes32[] storage preAllocatedKeys = _preAllocatedKeys[dappId][storageAddr];
        out = new bytes32[](preAllocatedKeys.length);
        for (uint256 i = 0; i < preAllocatedKeys.length; i++) {
            out[i] = preAllocatedKeys[i];
        }
    }

    function getUserSlots(uint256 dappId, address storageAddr) external view returns (uint8[] memory out) {
        _requireKnownStorage(dappId, storageAddr);
        uint8[] storage userStorageSlots = _userStorageSlots[dappId][storageAddr];
        out = new uint8[](userStorageSlots.length);
        for (uint256 i = 0; i < userStorageSlots.length; i++) {
            out[i] = userStorageSlots[i];
        }
    }

    function isChannelTokenVaultStorageAddress(uint256 dappId, address storageAddr) external view returns (bool) {
        _requireKnownStorage(dappId, storageAddr);
        return _isChannelTokenVaultStorage[dappId][storageAddr];
    }

    function computeFunctionKey(address entryContract, bytes4 functionSig)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(entryContract, functionSig));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _storeStorageLayout(uint256 dappId, BridgeStructs.StorageMetadata[] calldata storages)
        private
        returns (uint256 channelTokenVaultTreeIndex, address channelTokenVaultStorageAddress)
    {
        channelTokenVaultTreeIndex = type(uint256).max;

        for (uint256 i = 0; i < storages.length; i++) {
            BridgeStructs.StorageMetadata calldata storageMetadata = storages[i];
            if (_knownStorageAddress[dappId][storageMetadata.storageAddr]) {
                revert DuplicateStorageAddress(dappId, storageMetadata.storageAddr);
            }

            _knownStorageAddress[dappId][storageMetadata.storageAddr] = true;
            _managedStorageAddresses[dappId].push(storageMetadata.storageAddr);
            _isChannelTokenVaultStorage[dappId][storageMetadata.storageAddr] =
                storageMetadata.isChannelTokenVaultStorage;

            for (uint256 j = 0; j < storageMetadata.preAllocatedKeys.length; j++) {
                _preAllocatedKeys[dappId][storageMetadata.storageAddr].push(storageMetadata.preAllocatedKeys[j]);
            }
            for (uint256 j = 0; j < storageMetadata.userStorageSlots.length; j++) {
                _userStorageSlots[dappId][storageMetadata.storageAddr].push(storageMetadata.userStorageSlots[j]);
            }

            if (storageMetadata.isChannelTokenVaultStorage) {
                if (channelTokenVaultStorageAddress != address(0)) {
                    revert MultipleChannelTokenVaultStorageAddresses(
                        dappId, channelTokenVaultStorageAddress, storageMetadata.storageAddr
                    );
                }
                channelTokenVaultStorageAddress = storageMetadata.storageAddr;
                channelTokenVaultTreeIndex = i;
            }
        }

        if (channelTokenVaultStorageAddress == address(0)) {
            revert MissingChannelTokenVaultStorageAddress(dappId);
        }
    }

    function _storeFunctions(
        uint256 dappId,
        BridgeStructs.DAppFunctionMetadata[] calldata functions,
        address channelTokenVaultStorageAddress
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

            for (uint256 j = 0; j < fnMetadata.instanceLayout.storageWrites.length; j++) {
                BridgeStructs.StorageWriteMetadata calldata storageWrite = fnMetadata.instanceLayout.storageWrites[j];
                if (storageWrite.storageAddrIndex >= _managedStorageAddresses[dappId].length) {
                    revert InvalidFunctionStorageWriteStorageIndex(
                        dappId,
                        fnMetadata.entryContract,
                        fnMetadata.functionSig,
                        storageWrite.storageAddrIndex
                    );
                }
                address storageAddr = _managedStorageAddresses[dappId][storageWrite.storageAddrIndex];
                if (
                    _isChannelTokenVaultStorage[dappId][storageAddr]
                        && storageAddr != channelTokenVaultStorageAddress
                ) {
                    revert MultipleChannelTokenVaultStorageAddresses(
                        dappId, channelTokenVaultStorageAddress, storageAddr
                    );
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
                entryContractOffsetWords: fnMetadata.instanceLayout.entryContractOffsetWords,
                functionSigOffsetWords: fnMetadata.instanceLayout.functionSigOffsetWords,
                currentRootVectorOffsetWords: fnMetadata.instanceLayout.currentRootVectorOffsetWords,
                updatedRootVectorOffsetWords: fnMetadata.instanceLayout.updatedRootVectorOffsetWords,
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

}
