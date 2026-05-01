// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Initializable } from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { BridgeStructs } from "./BridgeStructs.sol";
import { IGrothVerifier } from "./interfaces/IGrothVerifier.sol";
import { ITokamakVerifier } from "./interfaces/ITokamakVerifier.sol";

interface IBridgeVerifierSource {
    function grothVerifier() external view returns (IGrothVerifier);
    function tokamakVerifier() external view returns (ITokamakVerifier);
}

contract DAppManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 internal constant LOCAL_CHAIN_ID = 31337;
    bytes32 public constant DAPP_METADATA_DIGEST_SCHEMA =
        keccak256("tokamak.zk-evm.bridge.dapp-metadata-digest.v1");
    bytes32 private constant STORAGE_ROOT_DOMAIN = keccak256("dapp.metadata.v1.storage-root");
    bytes32 private constant STORAGE_ITEM_DOMAIN = keccak256("dapp.metadata.v1.storage-item");
    bytes32 private constant PREALLOC_ROOT_DOMAIN = keccak256("dapp.metadata.v1.prealloc-root");
    bytes32 private constant PREALLOC_ITEM_DOMAIN = keccak256("dapp.metadata.v1.prealloc-item");
    bytes32 private constant USER_SLOT_ROOT_DOMAIN = keccak256("dapp.metadata.v1.user-slot-root");
    bytes32 private constant USER_SLOT_ITEM_DOMAIN = keccak256("dapp.metadata.v1.user-slot-item");
    bytes32 private constant FUNCTION_ROOT_DOMAIN = keccak256("dapp.metadata.v1.function-root");
    bytes32 private constant FUNCTION_ITEM_DOMAIN = keccak256("dapp.metadata.v1.function-item");
    bytes32 private constant INSTANCE_LAYOUT_DOMAIN = keccak256("dapp.metadata.v1.instance-layout");
    bytes32 private constant EVENT_LOG_ROOT_DOMAIN = keccak256("dapp.metadata.v1.event-log-root");
    bytes32 private constant EVENT_LOG_ITEM_DOMAIN = keccak256("dapp.metadata.v1.event-log-item");
    bytes32 private constant VERIFIER_SNAPSHOT_DOMAIN =
        keccak256("dapp.metadata.v1.verifier-snapshot");

    error UnknownDApp(uint256 dappId);
    error DuplicateDApp(uint256 dappId);
    error InvalidDAppLabelHash(uint256 dappId);
    error EmptyStorageLayout(uint256 dappId);
    error EmptyFunctionList(uint256 dappId);
    error InvalidStorageAddress(uint256 dappId, address storageAddr);
    error DuplicateStorageAddress(uint256 dappId, address storageAddr);
    error UnknownStorageAddress(uint256 dappId, address storageAddr);
    error InvalidFunctionEntryContract(uint256 dappId, address entryContract, bytes4 functionSig);
    error DuplicateFunction(uint256 dappId, address entryContract, bytes4 functionSig);
    error UnsupportedChannelFunction(uint256 dappId, address entryContract, bytes4 functionSig);
    error MissingChannelTokenVaultStorageAddress(uint256 dappId);
    error MultipleChannelTokenVaultStorageAddresses(
        uint256 dappId, address firstStorageAddr, address secondStorageAddr
    );
    error MissingPreprocessInputHash(uint256 dappId, address entryContract, bytes4 functionSig);
    error DuplicatePreprocessInputHash(uint256 dappId, bytes32 preprocessInputHash);
    error InvalidFunctionEventTopicCount(
        uint256 dappId, address entryContract, bytes4 functionSig, uint8 topicCount
    );
    error DAppDeletionDisabled();
    error InvalidBridgeCore();
    error BridgeCoreAlreadyBound(address existingBridgeCore);
    error BridgeCoreNotBound();

    struct DAppInfo {
        bool exists;
        bytes32 labelHash;
        uint256 channelTokenVaultTreeIndex;
        bytes32 metadataDigestSchema;
        bytes32 metadataDigest;
    }

    struct DAppMetadataDigestParts {
        uint256 channelTokenVaultTreeIndex;
        bytes32 storageRoot;
        bytes32 functionRoot;
    }

    address public bridgeCore;

    mapping(uint256 => DAppInfo) private _dapps;
    mapping(uint256 => BridgeStructs.DAppVerifierSnapshot) private _verifierSnapshots;
    mapping(uint256 => mapping(bytes32 => bool)) private _supportedFunctions;
    mapping(uint256 => mapping(bytes32 => BridgeStructs.FunctionConfig)) private _functionConfigs;
    mapping(uint256 => mapping(bytes32 => BridgeStructs.EventLogMetadata[])) private
        _functionEventLogs;
    mapping(uint256 => mapping(bytes32 => bool)) private _knownPreprocessInputHash;
    mapping(uint256 => BridgeStructs.FunctionReference[]) private _registeredFunctions;

    mapping(uint256 => address[]) private _managedStorageAddresses;
    mapping(uint256 => mapping(address => bool)) private _knownStorageAddress;
    mapping(uint256 => mapping(address => bool)) private _isChannelTokenVaultStorage;
    mapping(uint256 => mapping(address => bytes32[])) private _preAllocatedKeys;
    mapping(uint256 => mapping(address => uint8[])) private _userStorageSlots;

    event DAppRegistered(
        uint256 indexed dappId, bytes32 labelHash, uint256 storageCount, uint256 functionCount
    );
    event DAppMetadataUpdated(
        uint256 indexed dappId, bytes32 labelHash, uint256 storageCount, uint256 functionCount
    );
    event DAppMetadataDigestUpdated(
        uint256 indexed dappId, bytes32 indexed schema, bytes32 indexed digest
    );
    event DAppDeleted(uint256 indexed dappId, bytes32 labelHash);
    event BridgeCoreBound(address indexed bridgeCore);

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
        if (bridgeCore_ == address(0)) {
            revert InvalidBridgeCore();
        }
        if (bridgeCore != address(0)) {
            if (bridgeCore == bridgeCore_) {
                return;
            }
            revert BridgeCoreAlreadyBound(bridgeCore);
        }
        bridgeCore = bridgeCore_;
        emit BridgeCoreBound(bridgeCore_);
    }

    function deleteDApp(uint256 dappId) external onlyOwner {
        DAppInfo memory info = _requireDApp(dappId);
        if (block.chainid != SEPOLIA_CHAIN_ID && block.chainid != LOCAL_CHAIN_ID) {
            revert DAppDeletionDisabled();
        }

        _clearDAppRuntimeMetadata(dappId);
        delete _verifierSnapshots[dappId];
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
        if (labelHash == bytes32(0)) {
            revert InvalidDAppLabelHash(dappId);
        }
        DAppMetadataDigestParts memory digestParts =
            _storeDAppRuntimeMetadata(dappId, storages, functions);
        BridgeStructs.DAppVerifierSnapshot memory verifierSnapshot =
            _snapshotCurrentVerifiers(dappId);
        bytes32 metadataDigest =
            _computeDAppMetadataDigest(dappId, labelHash, digestParts, verifierSnapshot);
        _dapps[dappId] = DAppInfo({
            exists: true,
            labelHash: labelHash,
            channelTokenVaultTreeIndex: digestParts.channelTokenVaultTreeIndex,
            metadataDigestSchema: DAPP_METADATA_DIGEST_SCHEMA,
            metadataDigest: metadataDigest
        });
        emit DAppRegistered(dappId, labelHash, storages.length, functions.length);
        emit DAppMetadataDigestUpdated(dappId, DAPP_METADATA_DIGEST_SCHEMA, metadataDigest);
    }

    function updateDAppMetadata(
        uint256 dappId,
        BridgeStructs.StorageMetadata[] calldata storages,
        BridgeStructs.DAppFunctionMetadata[] calldata functions
    ) external onlyOwner {
        DAppInfo memory info = _requireDApp(dappId);
        _clearDAppRuntimeMetadata(dappId);
        DAppMetadataDigestParts memory digestParts =
            _storeDAppRuntimeMetadata(dappId, storages, functions);
        BridgeStructs.DAppVerifierSnapshot memory verifierSnapshot =
            _snapshotCurrentVerifiers(dappId);
        bytes32 metadataDigest =
            _computeDAppMetadataDigest(dappId, info.labelHash, digestParts, verifierSnapshot);
        _dapps[dappId] = DAppInfo({
            exists: true,
            labelHash: info.labelHash,
            channelTokenVaultTreeIndex: digestParts.channelTokenVaultTreeIndex,
            metadataDigestSchema: DAPP_METADATA_DIGEST_SCHEMA,
            metadataDigest: metadataDigest
        });
        emit DAppMetadataUpdated(dappId, info.labelHash, storages.length, functions.length);
        emit DAppMetadataDigestUpdated(dappId, DAPP_METADATA_DIGEST_SCHEMA, metadataDigest);
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

    function getDAppVerifierSnapshot(uint256 dappId)
        external
        view
        returns (BridgeStructs.DAppVerifierSnapshot memory)
    {
        _requireDApp(dappId);
        return _verifierSnapshots[dappId];
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

    function getManagedStorageAddresses(uint256 dappId)
        external
        view
        returns (address[] memory out)
    {
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

    function getPreAllocKeys(uint256 dappId, address storageAddr)
        external
        view
        returns (bytes32[] memory out)
    {
        _requireKnownStorage(dappId, storageAddr);
        bytes32[] storage preAllocatedKeys = _preAllocatedKeys[dappId][storageAddr];
        out = new bytes32[](preAllocatedKeys.length);
        for (uint256 i = 0; i < preAllocatedKeys.length; i++) {
            out[i] = preAllocatedKeys[i];
        }
    }

    function getUserSlots(uint256 dappId, address storageAddr)
        external
        view
        returns (uint8[] memory out)
    {
        _requireKnownStorage(dappId, storageAddr);
        uint8[] storage userStorageSlots = _userStorageSlots[dappId][storageAddr];
        out = new uint8[](userStorageSlots.length);
        for (uint256 i = 0; i < userStorageSlots.length; i++) {
            out[i] = userStorageSlots[i];
        }
    }

    function isChannelTokenVaultStorageAddress(uint256 dappId, address storageAddr)
        external
        view
        returns (bool)
    {
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

    function _authorizeUpgrade(address) internal override onlyOwner { }

    function _storeDAppRuntimeMetadata(
        uint256 dappId,
        BridgeStructs.StorageMetadata[] calldata storages,
        BridgeStructs.DAppFunctionMetadata[] calldata functions
    ) private returns (DAppMetadataDigestParts memory digestParts) {
        if (storages.length == 0) {
            revert EmptyStorageLayout(dappId);
        }
        if (functions.length == 0) {
            revert EmptyFunctionList(dappId);
        }

        digestParts.channelTokenVaultTreeIndex = type(uint256).max;
        digestParts.storageRoot = keccak256(abi.encode(STORAGE_ROOT_DOMAIN, storages.length));
        digestParts.functionRoot = keccak256(abi.encode(FUNCTION_ROOT_DOMAIN, functions.length));
        address channelTokenVaultStorageAddress;

        for (uint256 i = 0; i < storages.length; i++) {
            BridgeStructs.StorageMetadata calldata storageMetadata = storages[i];
            if (storageMetadata.storageAddr == address(0)) {
                revert InvalidStorageAddress(dappId, storageMetadata.storageAddr);
            }
            if (storageMetadata.storageAddr.code.length == 0) {
                revert InvalidStorageAddress(dappId, storageMetadata.storageAddr);
            }
            if (_knownStorageAddress[dappId][storageMetadata.storageAddr]) {
                revert DuplicateStorageAddress(dappId, storageMetadata.storageAddr);
            }

            _knownStorageAddress[dappId][storageMetadata.storageAddr] = true;
            _managedStorageAddresses[dappId].push(storageMetadata.storageAddr);
            _isChannelTokenVaultStorage[dappId][storageMetadata.storageAddr] =
            storageMetadata.isChannelTokenVaultStorage;

            for (uint256 j = 0; j < storageMetadata.preAllocatedKeys.length; j++) {
                _preAllocatedKeys[dappId][storageMetadata.storageAddr].push(
                    storageMetadata.preAllocatedKeys[j]
                );
            }
            for (uint256 j = 0; j < storageMetadata.userStorageSlots.length; j++) {
                _userStorageSlots[dappId][storageMetadata.storageAddr].push(
                    storageMetadata.userStorageSlots[j]
                );
            }

            if (storageMetadata.isChannelTokenVaultStorage) {
                if (channelTokenVaultStorageAddress != address(0)) {
                    revert MultipleChannelTokenVaultStorageAddresses(
                        dappId, channelTokenVaultStorageAddress, storageMetadata.storageAddr
                    );
                }
                channelTokenVaultStorageAddress = storageMetadata.storageAddr;
                digestParts.channelTokenVaultTreeIndex = i;
            }
            digestParts.storageRoot = keccak256(
                abi.encode(digestParts.storageRoot, _hashStorageMetadata(storageMetadata))
            );
        }

        if (channelTokenVaultStorageAddress == address(0)) {
            revert MissingChannelTokenVaultStorageAddress(dappId);
        }

        for (uint256 i = 0; i < functions.length; i++) {
            bytes32 functionMetadataHash = _storeFunctionMetadata(dappId, functions[i]);
            digestParts.functionRoot =
                keccak256(abi.encode(digestParts.functionRoot, functionMetadataHash));
        }
    }

    function _storeFunctionMetadata(
        uint256 dappId,
        BridgeStructs.DAppFunctionMetadata calldata fnMetadata
    ) private returns (bytes32 functionMetadataHash) {
        bytes32 functionKey = computeFunctionKey(fnMetadata.entryContract, fnMetadata.functionSig);
        if (fnMetadata.entryContract == address(0)) {
            revert InvalidFunctionEntryContract(
                dappId, fnMetadata.entryContract, fnMetadata.functionSig
            );
        }
        if (fnMetadata.entryContract.code.length == 0) {
            revert InvalidFunctionEntryContract(
                dappId, fnMetadata.entryContract, fnMetadata.functionSig
            );
        }
        if (_supportedFunctions[dappId][functionKey]) {
            revert DuplicateFunction(dappId, fnMetadata.entryContract, fnMetadata.functionSig);
        }
        if (fnMetadata.preprocessInputHash == bytes32(0)) {
            revert MissingPreprocessInputHash(
                dappId, fnMetadata.entryContract, fnMetadata.functionSig
            );
        }
        if (_knownPreprocessInputHash[dappId][fnMetadata.preprocessInputHash]) {
            revert DuplicatePreprocessInputHash(dappId, fnMetadata.preprocessInputHash);
        }

        _supportedFunctions[dappId][functionKey] = true;
        _knownPreprocessInputHash[dappId][fnMetadata.preprocessInputHash] = true;
        _registeredFunctions[dappId].push(
            BridgeStructs.FunctionReference({
                entryContract: fnMetadata.entryContract, functionSig: fnMetadata.functionSig
            })
        );

        for (uint256 j = 0; j < fnMetadata.instanceLayout.eventLogs.length; j++) {
            BridgeStructs.EventLogMetadata calldata eventLog =
                fnMetadata.instanceLayout.eventLogs[j];
            if (eventLog.topicCount > 4) {
                revert InvalidFunctionEventTopicCount(
                    dappId, fnMetadata.entryContract, fnMetadata.functionSig, eventLog.topicCount
                );
            }
            _functionEventLogs[dappId][functionKey].push(
                BridgeStructs.EventLogMetadata({
                    startOffsetWords: eventLog.startOffsetWords, topicCount: eventLog.topicCount
                })
            );
        }

        functionMetadataHash = _hashFunctionMetadata(fnMetadata);
        _functionConfigs[dappId][functionKey] = BridgeStructs.FunctionConfig({
            preprocessInputHash: fnMetadata.preprocessInputHash,
            entryContractOffsetWords: fnMetadata.instanceLayout.entryContractOffsetWords,
            functionSigOffsetWords: fnMetadata.instanceLayout.functionSigOffsetWords,
            currentRootVectorOffsetWords: fnMetadata.instanceLayout.currentRootVectorOffsetWords,
            updatedRootVectorOffsetWords: fnMetadata.instanceLayout.updatedRootVectorOffsetWords
        });
    }

    function _clearDAppRuntimeMetadata(uint256 dappId) private {
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
    }

    function _snapshotCurrentVerifiers(uint256 dappId)
        private
        returns (BridgeStructs.DAppVerifierSnapshot memory verifierSnapshot)
    {
        if (bridgeCore == address(0)) {
            revert BridgeCoreNotBound();
        }
        IGrothVerifier grothVerifier = IBridgeVerifierSource(bridgeCore).grothVerifier();
        ITokamakVerifier tokamakVerifier = IBridgeVerifierSource(bridgeCore).tokamakVerifier();
        verifierSnapshot = BridgeStructs.DAppVerifierSnapshot({
            grothVerifier: address(grothVerifier),
            grothVerifierCompatibleBackendVersion: grothVerifier.compatibleBackendVersion(),
            tokamakVerifier: address(tokamakVerifier),
            tokamakVerifierCompatibleBackendVersion: tokamakVerifier.compatibleBackendVersion()
        });
        _verifierSnapshots[dappId] = verifierSnapshot;
    }

    function _computeDAppMetadataDigest(
        uint256 dappId,
        bytes32 labelHash,
        DAppMetadataDigestParts memory digestParts,
        BridgeStructs.DAppVerifierSnapshot memory verifierSnapshot
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DAPP_METADATA_DIGEST_SCHEMA,
                dappId,
                labelHash,
                digestParts.channelTokenVaultTreeIndex,
                digestParts.storageRoot,
                digestParts.functionRoot,
                _hashVerifierSnapshot(verifierSnapshot)
            )
        );
    }

    function _hashStorageMetadata(BridgeStructs.StorageMetadata calldata storageMetadata)
        private
        pure
        returns (bytes32)
    {
        bytes32 preAllocatedKeysHash = keccak256(
            abi.encode(PREALLOC_ROOT_DOMAIN, storageMetadata.preAllocatedKeys.length)
        );
        for (uint256 i = 0; i < storageMetadata.preAllocatedKeys.length; i++) {
            preAllocatedKeysHash = keccak256(
                abi.encode(
                    PREALLOC_ITEM_DOMAIN, preAllocatedKeysHash, storageMetadata.preAllocatedKeys[i]
                )
            );
        }

        bytes32 userStorageSlotsHash =
            keccak256(abi.encode(USER_SLOT_ROOT_DOMAIN, storageMetadata.userStorageSlots.length));
        for (uint256 i = 0; i < storageMetadata.userStorageSlots.length; i++) {
            userStorageSlotsHash = keccak256(
                abi.encode(
                    USER_SLOT_ITEM_DOMAIN, userStorageSlotsHash, storageMetadata.userStorageSlots[i]
                )
            );
        }

        return keccak256(
            abi.encode(
                STORAGE_ITEM_DOMAIN,
                storageMetadata.storageAddr,
                preAllocatedKeysHash,
                userStorageSlotsHash,
                storageMetadata.isChannelTokenVaultStorage
            )
        );
    }

    function _hashFunctionMetadata(BridgeStructs.DAppFunctionMetadata calldata fnMetadata)
        private
        pure
        returns (bytes32)
    {
        bytes32 eventLogsHash = keccak256(
            abi.encode(EVENT_LOG_ROOT_DOMAIN, fnMetadata.instanceLayout.eventLogs.length)
        );
        for (uint256 i = 0; i < fnMetadata.instanceLayout.eventLogs.length; i++) {
            BridgeStructs.EventLogMetadata calldata eventLog =
                fnMetadata.instanceLayout.eventLogs[i];
            eventLogsHash = keccak256(
                abi.encode(
                    EVENT_LOG_ITEM_DOMAIN,
                    eventLogsHash,
                    eventLog.startOffsetWords,
                    eventLog.topicCount
                )
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

    function _hashVerifierSnapshot(BridgeStructs.DAppVerifierSnapshot memory verifierSnapshot)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                VERIFIER_SNAPSHOT_DOMAIN,
                verifierSnapshot.grothVerifier,
                keccak256(bytes(verifierSnapshot.grothVerifierCompatibleBackendVersion)),
                verifierSnapshot.tokamakVerifier,
                keccak256(bytes(verifierSnapshot.tokamakVerifierCompatibleBackendVersion))
            )
        );
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
