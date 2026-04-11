// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "./BridgeStructs.sol";
import {DAppManager} from "./DAppManager.sol";
import {IGrothVerifier} from "./interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "./interfaces/ITokamakVerifier.sol";

contract ChannelManager {
    uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = 63;
    uint256 internal constant TOKAMAK_PREVIOUS_BLOCK_HASHES = 4;
    uint256 internal constant TOKEN_VAULT_MT_LEAF_COUNT = uint256(1) << 12;
    uint256 internal constant SPLIT_WORD_SIZE = 2;
    uint256 internal constant STORAGE_WRITE_VALUE_OFFSET = 2;

    struct CachedStorageWrite {
        address storageAddr;
        uint8 aPubOffsetWords;
        bool isChannelTokenVault;
    }

    struct CachedEventLog {
        uint16 startOffsetWords;
        uint8 topicCount;
    }

    error OnlyBridgeCore();
    error OnlyBridgeTokenVault();
    error BridgeTokenVaultAlreadySet();
    error StorageAddressVectorLengthMismatch();
    error UnexpectedCurrentRootVector();
    error UnsupportedChannelFunction(address entryContract, bytes4 functionSig);
    error TokamakProofRejected();
    error InvalidChannelTokenVaultTreeIndex();
    error PreprocessInputHashMismatch(bytes32 expectedHash, bytes32 actualHash);
    error APubBlockHashMismatch(bytes32 expectedHash, bytes32 actualHash);
    error APubBlockLengthMismatch(uint256 expectedLength, uint256 actualLength);
    error APubUserTooShort(uint256 expectedLength, uint256 actualLength);
    error APubUserWordOutOfRange(uint256 index, uint256 value);
    error EntryContractPublicInputOutOfRange(uint256 value);
    error FunctionSigPublicInputOutOfRange(uint256 value);
    error InvalidStorageWriteStorageIndex(uint8 storageAddrIndex);
    error ChannelTokenVaultRootUpdateWithoutStorageWrite();
    error InvalidL2Address();
    error ChannelTokenVaultIdentityAlreadyRegistered(address user);
    error ChannelTokenVaultKeyAlreadyRegistered(bytes32 key);
    error ChannelTokenVaultLeafIndexAlreadyRegistered(uint256 leafIndex);
    error ChannelTokenVaultL2AddressAlreadyRegistered(address l2Address);
    error ChannelTokenVaultLeafIndexOutOfRange(uint256 leafIndex);
    error ChannelTokenVaultLeafIndexMismatch(uint256 expectedLeafIndex, uint256 actualLeafIndex);
    error InvalidNoteReceivePubKey();
    error InvalidNoteReceivePubKeyYParity(uint8 yParity);
    error UnsupportedObservedEventTopicCount(uint8 topicCount);
    error InvalidObservedEventBoundary(uint16 startOffsetWords, uint256 endOffsetWords);
    error InvalidObservedEventDataLength(uint16 startOffsetWords, uint256 dataWordLength);

    uint256 public immutable channelId;
    uint256 public immutable dappId;
    uint256 public genesisBlockNumber;
    address public immutable leader;
    bytes32 public immutable aPubBlockHash;
    uint256 public immutable channelTokenVaultTreeIndex;
    address public immutable channelTokenVaultStorageAddress;
    address public immutable bridgeCore;
    IGrothVerifier public immutable grothVerifier;
    ITokamakVerifier public immutable tokamakVerifier;

    address public bridgeTokenVault;
    bytes32 public currentRootVectorHash;

    address[] private _managedStorageAddresses;

    mapping(bytes32 => bool) private _allowedFunctionKeys;
    mapping(bytes32 => BridgeStructs.FunctionConfig) private _functionConfigs;
    mapping(bytes32 => bytes32) private _functionKeyByPreprocessInputHash;
    mapping(bytes32 => CachedStorageWrite[]) private _functionStorageWrites;
    mapping(bytes32 => CachedEventLog[]) private _functionEventLogs;
    mapping(bytes32 => bool) private _functionHasChannelTokenVaultWrite;
    BridgeStructs.FunctionReference[] private _allowedFunctions;

    mapping(uint256 => bytes32) private _latestChannelTokenVaultLeaves;
    mapping(address => BridgeStructs.ChannelTokenVaultRegistration) private _channelTokenVaultRegistrations;
    mapping(bytes32 => address) private _channelTokenVaultKeyOwners;
    mapping(uint256 => address) private _channelTokenVaultLeafOwners;
    mapping(address => address) private _channelTokenVaultL2AddressOwners;

    event BridgeTokenVaultBound(address indexed bridgeTokenVault);
    event ChannelTokenVaultIdentityRegistered(
        address indexed l1Address,
        address indexed l2Address,
        bytes32 indexed channelTokenVaultKey,
        uint256 leafIndex,
        bytes32 noteReceivePubKeyX,
        uint8 noteReceivePubKeyYParity
    );
    event CurrentRootVectorObserved(bytes32 indexed rootVectorHash, bytes32[] rootVector);
    event StorageWriteObserved(address indexed storageAddr, uint256 storageKey, uint256 value);

    constructor(
        uint256 channelId_,
        uint256 dappId_,
        address leader_,
        uint256 channelTokenVaultTreeIndex_,
        bytes32[] memory initialRootVector_,
        address[] memory managedStorageAddresses_,
        BridgeStructs.FunctionReference[] memory allowedFunctions_,
        address bridgeCore_,
        IGrothVerifier grothVerifier_,
        ITokamakVerifier tokamakVerifier_,
        DAppManager dAppManager_
    ) {
        channelId = channelId_;
        dappId = dappId_;
        genesisBlockNumber = block.number;
        leader = leader_;
        bridgeCore = bridgeCore_;
        grothVerifier = grothVerifier_;
        tokamakVerifier = tokamakVerifier_;

        uint256[] memory aPubBlock = new uint256[](TOKAMAK_APUB_BLOCK_LENGTH);
        uint256 selfBalance;
        assembly ("memory-safe") {
            selfBalance := selfbalance()
        }
        aPubBlock[0] = uint256(uint128(uint256(uint160(address(block.coinbase)))));
        aPubBlock[1] = uint256(uint160(address(block.coinbase))) >> 128;
        aPubBlock[2] = uint256(uint128(block.timestamp));
        aPubBlock[3] = block.timestamp >> 128;
        aPubBlock[4] = uint256(uint128(block.number));
        aPubBlock[5] = block.number >> 128;
        aPubBlock[6] = uint256(uint128(uint256(block.prevrandao)));
        aPubBlock[7] = uint256(block.prevrandao) >> 128;
        aPubBlock[8] = uint256(uint128(block.gaslimit));
        aPubBlock[9] = block.gaslimit >> 128;
        aPubBlock[10] = uint256(uint128(block.chainid));
        aPubBlock[11] = block.chainid >> 128;
        aPubBlock[12] = uint256(uint128(selfBalance));
        aPubBlock[13] = selfBalance >> 128;
        aPubBlock[14] = uint256(uint128(block.basefee));
        aPubBlock[15] = block.basefee >> 128;
        uint256 offsetWords = 16;
        for (uint256 i = 1; i <= TOKAMAK_PREVIOUS_BLOCK_HASHES; i++) {
            uint256 blockHashNumber = block.number > i ? block.number - i : 0;
            uint256 blockHashValue = uint256(blockhash(blockHashNumber));
            aPubBlock[offsetWords] = uint256(uint128(blockHashValue));
            aPubBlock[offsetWords + 1] = blockHashValue >> 128;
            unchecked {
                offsetWords += SPLIT_WORD_SIZE;
            }
        }
        aPubBlockHash = keccak256(abi.encode(aPubBlock));

        if (channelTokenVaultTreeIndex_ >= initialRootVector_.length) {
            revert InvalidChannelTokenVaultTreeIndex();
        }
        channelTokenVaultTreeIndex = channelTokenVaultTreeIndex_;
        channelTokenVaultStorageAddress = managedStorageAddresses_[channelTokenVaultTreeIndex_];

        if (managedStorageAddresses_.length != initialRootVector_.length) {
            revert StorageAddressVectorLengthMismatch();
        }

        currentRootVectorHash = keccak256(abi.encode(initialRootVector_));
        for (uint256 i = 0; i < managedStorageAddresses_.length; i++) {
            _managedStorageAddresses.push(managedStorageAddresses_[i]);
        }

        for (uint256 i = 0; i < allowedFunctions_.length; i++) {
            bytes32 functionKey =
                _computeFunctionKey(allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig);
            _allowedFunctionKeys[functionKey] = true;
            _allowedFunctions.push(allowedFunctions_[i]);
            BridgeStructs.FunctionConfig memory functionConfig = dAppManager_.getFunctionMetadata(
                dappId_, allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig
            );
            _functionConfigs[functionKey] = functionConfig;
            _functionKeyByPreprocessInputHash[functionConfig.preprocessInputHash] = functionKey;

            BridgeStructs.StorageWriteMetadata[] memory storageWrites = dAppManager_.getFunctionStorageWrites(
                dappId_, allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig
            );
            for (uint256 j = 0; j < storageWrites.length; j++) {
                uint8 storageAddrIndex = storageWrites[j].storageAddrIndex;
                if (storageAddrIndex >= managedStorageAddresses_.length) {
                    revert InvalidStorageWriteStorageIndex(storageAddrIndex);
                }
                _functionStorageWrites[functionKey].push(
                    CachedStorageWrite({
                        storageAddr: managedStorageAddresses_[storageAddrIndex],
                        aPubOffsetWords: storageWrites[j].aPubOffsetWords,
                        isChannelTokenVault: managedStorageAddresses_[storageAddrIndex]
                            == channelTokenVaultStorageAddress
                    })
                );
                if (managedStorageAddresses_[storageAddrIndex] == channelTokenVaultStorageAddress) {
                    _functionHasChannelTokenVaultWrite[functionKey] = true;
                }
            }

            BridgeStructs.EventLogMetadata[] memory eventLogs = dAppManager_.getFunctionEventLogs(
                dappId_, allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig
            );
            for (uint256 j = 0; j < eventLogs.length; j++) {
                _functionEventLogs[functionKey].push(
                    CachedEventLog({
                        startOffsetWords: eventLogs[j].startOffsetWords, topicCount: eventLogs[j].topicCount
                    })
                );
            }
        }
    }

    modifier onlyBridgeCore() {
        if (msg.sender != bridgeCore) revert OnlyBridgeCore();
        _;
    }

    modifier onlyBridgeTokenVault() {
        if (msg.sender != bridgeTokenVault) revert OnlyBridgeTokenVault();
        _;
    }

    function bindBridgeTokenVault(address bridgeTokenVault_) external onlyBridgeCore {
        if (bridgeTokenVault != address(0)) revert BridgeTokenVaultAlreadySet();
        bridgeTokenVault = bridgeTokenVault_;
        emit BridgeTokenVaultBound(bridgeTokenVault_);
    }

    function registerChannelTokenVaultIdentity(
        address l2Address,
        bytes32 channelTokenVaultKey,
        uint256 leafIndex,
        BridgeStructs.NoteReceivePubKey calldata noteReceivePubKey
    ) external {
        if (l2Address == address(0)) revert InvalidL2Address();
        if (_channelTokenVaultRegistrations[msg.sender].exists) {
            revert ChannelTokenVaultIdentityAlreadyRegistered(msg.sender);
        }
        if (_channelTokenVaultL2AddressOwners[l2Address] != address(0)) {
            revert ChannelTokenVaultL2AddressAlreadyRegistered(l2Address);
        }
        if (leafIndex >= TOKEN_VAULT_MT_LEAF_COUNT) {
            revert ChannelTokenVaultLeafIndexOutOfRange(leafIndex);
        }
        if (noteReceivePubKey.x == bytes32(0)) {
            revert InvalidNoteReceivePubKey();
        }
        if (noteReceivePubKey.yParity > 1) {
            revert InvalidNoteReceivePubKeyYParity(noteReceivePubKey.yParity);
        }

        uint256 expectedLeafIndex = _deriveLeafIndexFromStorageKey(uint256(channelTokenVaultKey));
        if (leafIndex != expectedLeafIndex) {
            revert ChannelTokenVaultLeafIndexMismatch(expectedLeafIndex, leafIndex);
        }
        if (_channelTokenVaultKeyOwners[channelTokenVaultKey] != address(0)) {
            revert ChannelTokenVaultKeyAlreadyRegistered(channelTokenVaultKey);
        }
        if (_channelTokenVaultLeafOwners[leafIndex] != address(0)) {
            revert ChannelTokenVaultLeafIndexAlreadyRegistered(leafIndex);
        }

        _channelTokenVaultRegistrations[msg.sender] = BridgeStructs.ChannelTokenVaultRegistration({
            exists: true,
            l2Address: l2Address,
            channelTokenVaultKey: channelTokenVaultKey,
            leafIndex: leafIndex,
            noteReceivePubKey: BridgeStructs.NoteReceivePubKey({
                x: noteReceivePubKey.x, yParity: noteReceivePubKey.yParity
            })
        });
        _channelTokenVaultKeyOwners[channelTokenVaultKey] = msg.sender;
        _channelTokenVaultLeafOwners[leafIndex] = msg.sender;
        _channelTokenVaultL2AddressOwners[l2Address] = msg.sender;

        emit ChannelTokenVaultIdentityRegistered(
            msg.sender, l2Address, channelTokenVaultKey, leafIndex, noteReceivePubKey.x, noteReceivePubKey.yParity
        );
    }

    function executeChannelTransaction(BridgeStructs.TokamakProofPayload calldata payload) external returns (bool) {
        bytes32 actualPreprocessInputHash =
            keccak256(abi.encode(payload.functionPreprocessPart1, payload.functionPreprocessPart2));
        bytes32 functionKey = _functionKeyByPreprocessInputHash[actualPreprocessInputHash];
        if (!_allowedFunctionKeys[functionKey]) {
            revert UnsupportedChannelFunction(address(0), bytes4(0));
        }
        BridgeStructs.FunctionConfig memory functionConfig = _functionConfigs[functionKey];

        uint256 rootVectorLength = _managedStorageAddresses.length;
        uint256 requiredLength = functionConfig.updatedRootVectorOffsetWords + rootVectorLength * SPLIT_WORD_SIZE;
        uint256 currentRootVectorRequiredLength =
            functionConfig.currentRootVectorOffsetWords + rootVectorLength * SPLIT_WORD_SIZE;
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
        if (payload.aPubUser.length < requiredLength) {
            revert APubUserTooShort(requiredLength, payload.aPubUser.length);
        }

        uint256 entryContractValue = _decodeSplitWord(payload.aPubUser, functionConfig.entryContractOffsetWords);
        if (entryContractValue > type(uint160).max) {
            revert EntryContractPublicInputOutOfRange(entryContractValue);
        }
        address entryContract = address(uint160(entryContractValue));
        uint256 functionSigValue = _decodeSplitWord(payload.aPubUser, functionConfig.functionSigOffsetWords);
        if (functionSigValue > type(uint32).max) {
            revert FunctionSigPublicInputOutOfRange(functionSigValue);
        }
        bytes4 functionSig = bytes4(uint32(functionSigValue));
        if (_computeFunctionKey(entryContract, functionSig) != functionKey) {
            revert UnsupportedChannelFunction(entryContract, functionSig);
        }

        bytes32 expectedPreprocessInputHash = functionConfig.preprocessInputHash;
        if (actualPreprocessInputHash != expectedPreprocessInputHash) {
            revert PreprocessInputHashMismatch(expectedPreprocessInputHash, actualPreprocessInputHash);
        }
        if (payload.aPubBlock.length != TOKAMAK_APUB_BLOCK_LENGTH) {
            revert APubBlockLengthMismatch(TOKAMAK_APUB_BLOCK_LENGTH, payload.aPubBlock.length);
        }
        bytes32 actualAPubBlockHash = keccak256(abi.encode(payload.aPubBlock));
        if (actualAPubBlockHash != aPubBlockHash) {
            revert APubBlockHashMismatch(aPubBlockHash, actualAPubBlockHash);
        }

        bytes32[] memory currentRootVector =
            _decodeRootVectorFromAPubUser(payload.aPubUser, functionConfig.currentRootVectorOffsetWords);
        if (keccak256(abi.encode(currentRootVector)) != currentRootVectorHash) {
            revert UnexpectedCurrentRootVector();
        }
        bytes32[] memory updatedRootVector =
            _decodeRootVectorFromAPubUser(payload.aPubUser, functionConfig.updatedRootVectorOffsetWords);
        bytes32 currentChannelTokenVaultRoot = currentRootVector[channelTokenVaultTreeIndex];
        bytes32 updatedChannelTokenVaultRoot = updatedRootVector[channelTokenVaultTreeIndex];
        bool hasChannelTokenVaultStorageWrite = _functionHasChannelTokenVaultWrite[functionKey];

        if (updatedChannelTokenVaultRoot != currentChannelTokenVaultRoot && !hasChannelTokenVaultStorageWrite) {
            revert ChannelTokenVaultRootUpdateWithoutStorageWrite();
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

        CachedStorageWrite[] storage storageWrites = _functionStorageWrites[functionKey];
        for (uint256 i = 0; i < storageWrites.length; i++) {
            CachedStorageWrite storage storageWrite = storageWrites[i];
            uint256 aPubOffsetWords = storageWrite.aPubOffsetWords;
            uint256 storageKey = _decodeSplitWord(payload.aPubUser, aPubOffsetWords);
            uint256 value = _decodeSplitWord(payload.aPubUser, aPubOffsetWords + STORAGE_WRITE_VALUE_OFFSET);

            emit StorageWriteObserved(storageWrite.storageAddr, storageKey, value);
            if (storageWrite.isChannelTokenVault) {
                uint256 leafIndex = _deriveLeafIndexFromStorageKey(storageKey);
                _applyChannelTokenVaultLeaf(leafIndex, bytes32(value));
            }
        }
        _emitObservedEventLogs(payload.aPubUser, functionConfig, _functionEventLogs[functionKey]);
        currentRootVectorHash = keccak256(abi.encode(updatedRootVector));
        emit CurrentRootVectorObserved(currentRootVectorHash, updatedRootVector);

        return true;
    }

    function applyVaultUpdate(
        bytes32[] calldata currentRootVector,
        bytes32 updatedChannelTokenVaultRoot,
        uint256 leafIndex,
        bytes32 latestLeafValue
    ) external onlyBridgeTokenVault returns (bool) {
        if (currentRootVector.length != _managedStorageAddresses.length) {
            revert APubUserTooShort(_managedStorageAddresses.length, currentRootVector.length);
        }
        if (keccak256(abi.encode(currentRootVector)) != currentRootVectorHash) {
            revert UnexpectedCurrentRootVector();
        }

        _applyChannelTokenVaultLeaf(leafIndex, latestLeafValue);
        bytes32[] memory updatedRootVector = new bytes32[](currentRootVector.length);
        for (uint256 i = 0; i < currentRootVector.length; i++) {
            updatedRootVector[i] = currentRootVector[i];
        }
        updatedRootVector[channelTokenVaultTreeIndex] = updatedChannelTokenVaultRoot;
        currentRootVectorHash = keccak256(abi.encode(updatedRootVector));
        emit CurrentRootVectorObserved(currentRootVectorHash, updatedRootVector);
        return true;
    }

    function getManagedStorageAddresses() external view returns (address[] memory out) {
        out = new address[](_managedStorageAddresses.length);
        for (uint256 i = 0; i < _managedStorageAddresses.length; i++) {
            out[i] = _managedStorageAddresses[i];
        }
    }

    function getLatestChannelTokenVaultLeaf(uint256 leafIndex) external view returns (bytes32) {
        return _latestChannelTokenVaultLeaves[leafIndex];
    }

    function getChannelTokenVaultRegistration(address l1Address)
        external
        view
        returns (BridgeStructs.ChannelTokenVaultRegistration memory)
    {
        return _channelTokenVaultRegistrations[l1Address];
    }

    function getChannelTokenVaultRegistrationByL2Address(address l2Address)
        external
        view
        returns (BridgeStructs.ChannelTokenVaultRegistration memory)
    {
        address l1Address = _channelTokenVaultL2AddressOwners[l2Address];
        if (l1Address == address(0)) {
            return BridgeStructs.ChannelTokenVaultRegistration({
                exists: false,
                l2Address: address(0),
                channelTokenVaultKey: bytes32(0),
                leafIndex: 0,
                noteReceivePubKey: BridgeStructs.NoteReceivePubKey({x: bytes32(0), yParity: 0})
            });
        }
        return _channelTokenVaultRegistrations[l1Address];
    }

    function getNoteReceivePubKeyByL2Address(address l2Address)
        external
        view
        returns (BridgeStructs.NoteReceivePubKey memory)
    {
        address l1Address = _channelTokenVaultL2AddressOwners[l2Address];
        if (l1Address == address(0)) {
            return BridgeStructs.NoteReceivePubKey({x: bytes32(0), yParity: 0});
        }
        return _channelTokenVaultRegistrations[l1Address].noteReceivePubKey;
    }

    function _decodeRootVectorFromAPubUser(uint256[] calldata aPubUser, uint256 rootVectorOffsetWords)
        private
        view
        returns (bytes32[] memory rootVector)
    {
        uint256 rootVectorLength = _managedStorageAddresses.length;
        rootVector = new bytes32[](rootVectorLength);
        for (uint256 i = 0; i < rootVectorLength;) {
            rootVector[i] = bytes32(_decodeSplitWord(aPubUser, rootVectorOffsetWords + i * SPLIT_WORD_SIZE));
            unchecked {
                ++i;
            }
        }
    }

    function _decodeSplitWord(uint256[] calldata words, uint256 startIndex) private pure returns (uint256 combined) {
        uint256 lower;
        uint256 upper;
        assembly ("memory-safe") {
            let dataOffset := words.offset
            lower := calldataload(add(dataOffset, shl(5, startIndex)))
            upper := calldataload(add(dataOffset, shl(5, add(startIndex, 1))))
        }
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

    function _applyChannelTokenVaultLeaf(uint256 leafIndex, bytes32 leafValue) private {
        _latestChannelTokenVaultLeaves[leafIndex] = leafValue;
    }

    function _deriveLeafIndexFromStorageKey(uint256 storageKey) private pure returns (uint256) {
        return storageKey % TOKEN_VAULT_MT_LEAF_COUNT;
    }

    function _emitObservedEventLogs(
        uint256[] calldata aPubUser,
        BridgeStructs.FunctionConfig memory functionConfig,
        CachedEventLog[] storage eventLogs
    ) private {
        for (uint256 i = 0; i < eventLogs.length; i++) {
            CachedEventLog storage eventLog = eventLogs[i];
            if (eventLog.topicCount > 4) {
                revert UnsupportedObservedEventTopicCount(eventLog.topicCount);
            }

            uint256 eventEndOffset = _resolveObservedEventBoundary(functionConfig, eventLogs, i);
            uint256 dataStartOffset =
                uint256(eventLog.startOffsetWords) + uint256(eventLog.topicCount) * SPLIT_WORD_SIZE;
            if (eventEndOffset < dataStartOffset) {
                revert InvalidObservedEventBoundary(eventLog.startOffsetWords, eventEndOffset);
            }
            uint256 dataWordLength = eventEndOffset - dataStartOffset;
            if (dataWordLength % SPLIT_WORD_SIZE != 0) {
                revert InvalidObservedEventDataLength(eventLog.startOffsetWords, dataWordLength);
            }

            uint256[4] memory topics;
            for (uint256 topicIndex = 0; topicIndex < eventLog.topicCount; topicIndex++) {
                topics[topicIndex] =
                    _decodeSplitWord(aPubUser, uint256(eventLog.startOffsetWords) + topicIndex * SPLIT_WORD_SIZE);
            }

            bytes memory logData = new bytes((dataWordLength / SPLIT_WORD_SIZE) * 32);
            for (uint256 wordIndex = 0; wordIndex < dataWordLength / SPLIT_WORD_SIZE; wordIndex++) {
                uint256 value = _decodeSplitWord(aPubUser, dataStartOffset + wordIndex * SPLIT_WORD_SIZE);
                assembly ("memory-safe") {
                    mstore(add(add(logData, 0x20), mul(wordIndex, 0x20)), value)
                }
            }

            _emitRawLog(logData, eventLog.topicCount, topics);
        }
    }

    function _resolveObservedEventBoundary(
        BridgeStructs.FunctionConfig memory functionConfig,
        CachedEventLog[] storage eventLogs,
        uint256 eventLogIndex
    ) private view returns (uint256 boundary) {
        CachedEventLog storage eventLog = eventLogs[eventLogIndex];
        boundary = type(uint256).max;

        if (eventLogIndex + 1 < eventLogs.length) {
            uint256 nextStartOffset = eventLogs[eventLogIndex + 1].startOffsetWords;
            if (nextStartOffset > eventLog.startOffsetWords) {
                boundary = nextStartOffset;
            }
        }

        boundary =
            _minObservedBoundary(boundary, functionConfig.updatedRootVectorOffsetWords, eventLog.startOffsetWords);
        boundary = _minObservedBoundary(boundary, functionConfig.entryContractOffsetWords, eventLog.startOffsetWords);
        boundary = _minObservedBoundary(boundary, functionConfig.functionSigOffsetWords, eventLog.startOffsetWords);
        boundary =
            _minObservedBoundary(boundary, functionConfig.currentRootVectorOffsetWords, eventLog.startOffsetWords);

        if (boundary == type(uint256).max) {
            revert InvalidObservedEventBoundary(eventLog.startOffsetWords, boundary);
        }
    }

    function _minObservedBoundary(uint256 currentBoundary, uint256 candidateBoundary, uint16 startOffsetWords)
        private
        pure
        returns (uint256)
    {
        if (candidateBoundary > startOffsetWords && candidateBoundary < currentBoundary) {
            return candidateBoundary;
        }
        return currentBoundary;
    }

    function _emitRawLog(bytes memory logData, uint8 topicCount, uint256[4] memory topics) private {
        uint256 dataLength = logData.length;
        assembly ("memory-safe") {
            let dataPtr := add(logData, 0x20)
            switch topicCount
            case 0 { log0(dataPtr, dataLength) }
            case 1 { log1(dataPtr, dataLength, mload(add(topics, 0x20))) }
            case 2 { log2(dataPtr, dataLength, mload(add(topics, 0x20)), mload(add(topics, 0x40))) }
            case 3 {
                log3(dataPtr, dataLength, mload(add(topics, 0x20)), mload(add(topics, 0x40)), mload(add(topics, 0x60)))
            }
            case 4 {
                log4(
                    dataPtr,
                    dataLength,
                    mload(add(topics, 0x20)),
                    mload(add(topics, 0x40)),
                    mload(add(topics, 0x60)),
                    mload(add(topics, 0x80))
                )
            }
        }
    }
}
