// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BridgeStructs} from "./BridgeStructs.sol";

contract DAppManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    error UnknownDApp(uint256 dappId);
    error DuplicateDApp(uint256 dappId);
    error InvalidBridgeCore();
    error BridgeCoreAlreadyBound(address currentBridgeCore, address candidateBridgeCore);
    error EmptyStorageLayout(uint256 dappId);
    error EmptyFunctionList(uint256 dappId);
    error DuplicateStorageAddress(uint256 dappId, address storageAddr);
    error UnknownStorageAddress(uint256 dappId, address storageAddr);
    error DuplicateFunction(uint256 dappId, address entryContract, bytes4 functionSig);
    error UnsupportedChannelFunction(uint256 dappId, address entryContract, bytes4 functionSig);
    error MissingChannelTokenVaultStorageAddress(uint256 dappId);
    error MultipleChannelTokenVaultStorageAddresses(uint256 dappId, address firstStorageAddr, address secondStorageAddr);
    error MissingPreprocessInputHash(uint256 dappId, address entryContract, bytes4 functionSig);
    error DuplicatePreprocessInputHash(uint256 dappId, bytes32 preprocessInputHash);
    error InvalidFunctionEventTopicCount(uint256 dappId, address entryContract, bytes4 functionSig, uint8 topicCount);
    error DAppDeletionDisabled();

    struct DAppInfo {
        bool exists;
        bytes32 labelHash;
        uint256 channelTokenVaultTreeIndex;
    }

    address public bridgeCore;

    mapping(uint256 => DAppInfo) private _dapps;
    mapping(uint256 => mapping(bytes32 => bool)) private _supportedFunctions;
    mapping(uint256 => mapping(bytes32 => BridgeStructs.FunctionConfig)) private _functionConfigs;
    mapping(uint256 => mapping(bytes32 => BridgeStructs.EventLogMetadata[])) private _functionEventLogs;
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
    event BridgeCoreBound(address indexed bridgeCore);
    event DAppDeleted(uint256 indexed dappId, bytes32 labelHash);

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

    function bindBridgeCore(address bridgeCore_) external onlyOwner {
        if (bridgeCore_ == address(0)) revert InvalidBridgeCore();
        if (bridgeCore != address(0)) {
            revert BridgeCoreAlreadyBound(bridgeCore, bridgeCore_);
        }
        bridgeCore = bridgeCore_;
        emit BridgeCoreBound(bridgeCore_);
    }

    function deleteDApp(uint256 dappId) external onlyOwner {
        DAppInfo memory info = _requireDApp(dappId);
        if (block.chainid != SEPOLIA_CHAIN_ID) revert DAppDeletionDisabled();

        BridgeStructs.FunctionReference[] storage refs = _registeredFunctions[dappId];
        for (uint256 i = 0; i < refs.length; i++) {
            bytes32 functionKey = computeFunctionKey(refs[i].entryContract, refs[i].functionSig);
            bytes32 preprocessInputHash = _functionConfigs[dappId][functionKey].preprocessInputHash;
            if (preprocessInputHash != bytes32(0)) {
                delete _knownPreprocessInputHash[dappId][preprocessInputHash];
            }
            delete _supportedFunctions[dappId][functionKey];
            delete _functionConfigs[dappId][functionKey];
            delete _functionEventLogs[dappId][functionKey];
        }
        delete _registeredFunctions[dappId];

        address[] storage managedStorageAddresses = _managedStorageAddresses[dappId];
        for (uint256 i = 0; i < managedStorageAddresses.length; i++) {
            address storageAddr = managedStorageAddresses[i];
            delete _knownStorageAddress[dappId][storageAddr];
            delete _isChannelTokenVaultStorage[dappId][storageAddr];
            delete _preAllocatedKeys[dappId][storageAddr];
            delete _userStorageSlots[dappId][storageAddr];
        }
        delete _managedStorageAddresses[dappId];
        delete _dapps[dappId];

        emit DAppDeleted(dappId, info.labelHash);
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

        uint256 channelTokenVaultTreeIndex = type(uint256).max;
        address channelTokenVaultStorageAddress;

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

            for (uint256 j = 0; j < fnMetadata.instanceLayout.eventLogs.length; j++) {
                BridgeStructs.EventLogMetadata calldata eventLog = fnMetadata.instanceLayout.eventLogs[j];
                if (eventLog.topicCount > 4) {
                    revert InvalidFunctionEventTopicCount(
                        dappId,
                        fnMetadata.entryContract,
                        fnMetadata.functionSig,
                        eventLog.topicCount
                    );
                }
                _functionEventLogs[dappId][functionKey].push(
                    BridgeStructs.EventLogMetadata({
                        startOffsetWords: eventLog.startOffsetWords,
                        topicCount: eventLog.topicCount
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

    function getFunctionEventLogs(uint256 dappId, address entryContract, bytes4 functionSig)
        external
        view
        returns (BridgeStructs.EventLogMetadata[] memory out)
    {
        bytes32 functionKey = computeFunctionKey(entryContract, functionSig);
        if (!_supportedFunctions[dappId][functionKey]) {
            revert UnsupportedChannelFunction(dappId, entryContract, functionSig);
        }
        BridgeStructs.EventLogMetadata[] storage eventLogs = _functionEventLogs[dappId][functionKey];
        out = new BridgeStructs.EventLogMetadata[](eventLogs.length);
        for (uint256 i = 0; i < eventLogs.length; i++) {
            out[i] = eventLogs[i];
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
