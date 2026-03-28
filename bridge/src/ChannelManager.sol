// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "./BridgeStructs.sol";
import {DAppManager} from "./DAppManager.sol";
import {ITokamakVerifier} from "./interfaces/ITokamakVerifier.sol";

contract ChannelManager {
    uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = 68;
    uint256 internal constant TOKAMAK_PREVIOUS_BLOCK_HASHES = 4;
    uint256 internal constant TOKEN_VAULT_MT_LEAF_COUNT = uint256(1) << 12;
    uint256 internal constant SPLIT_WORD_SIZE = 2;
    uint256 internal constant STORAGE_WRITE_VALUE_OFFSET = 2;

    struct CachedStorageWrite {
        address storageAddr;
        uint8 aPubOffsetWords;
        bool isChannelTokenVault;
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
    error ChannelTokenVaultLeafIndexOutOfRange(uint256 leafIndex);
    error ChannelTokenVaultLeafIndexMismatch(uint256 expectedLeafIndex, uint256 actualLeafIndex);

    uint256 public immutable channelId;
    uint256 public immutable dappId;
    uint256 public genesisBlockNumber;
    address public immutable leader;
    bytes32 public immutable aPubBlockHash;
    uint256 public immutable channelTokenVaultTreeIndex;
    address public immutable channelTokenVaultStorageAddress;
    address public immutable bridgeCore;
    ITokamakVerifier public immutable tokamakVerifier;

    address public bridgeTokenVault;
    bytes32 public currentRootVectorHash;

    address[] private _managedStorageAddresses;

    mapping(bytes32 => bool) private _allowedFunctionKeys;
    mapping(bytes32 => BridgeStructs.FunctionConfig) private _functionConfigs;
    mapping(bytes32 => bytes32) private _functionKeyByPreprocessInputHash;
    mapping(bytes32 => CachedStorageWrite[]) private _functionStorageWrites;
    mapping(bytes32 => bool) private _functionHasChannelTokenVaultWrite;
    BridgeStructs.FunctionReference[] private _allowedFunctions;

    mapping(uint256 => bytes32) private _latestChannelTokenVaultLeaves;
    mapping(address => BridgeStructs.ChannelTokenVaultRegistration) private _channelTokenVaultRegistrations;
    mapping(bytes32 => address) private _channelTokenVaultKeyOwners;
    mapping(uint256 => address) private _channelTokenVaultLeafOwners;

    event BridgeTokenVaultBound(address indexed bridgeTokenVault);
    event ChannelTokenVaultIdentityRegistered(
        address indexed l1Address, address indexed l2Address, bytes32 indexed channelTokenVaultKey, uint256 leafIndex
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
        DAppManager dAppManager_,
        ITokamakVerifier tokamakVerifier_
    ) {
        channelId = channelId_;
        dappId = dappId_;
        genesisBlockNumber = block.number;
        leader = leader_;
        bridgeCore = bridgeCore_;
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
                dappId_,
                allowedFunctions_[i].entryContract,
                allowedFunctions_[i].functionSig
            );
            _functionConfigs[functionKey] = functionConfig;
            _functionKeyByPreprocessInputHash[functionConfig.preprocessInputHash] = functionKey;

            BridgeStructs.StorageWriteMetadata[] memory storageWrites =
                dAppManager_.getFunctionStorageWrites(dappId_, allowedFunctions_[i].entryContract, allowedFunctions_[i].functionSig);
            for (uint256 j = 0; j < storageWrites.length; j++) {
                uint8 storageAddrIndex = storageWrites[j].storageAddrIndex;
                if (storageAddrIndex >= managedStorageAddresses_.length) {
                    revert InvalidStorageWriteStorageIndex(storageAddrIndex);
                }
                _functionStorageWrites[functionKey].push(
                    CachedStorageWrite({
                        storageAddr: managedStorageAddresses_[storageAddrIndex],
                        aPubOffsetWords: storageWrites[j].aPubOffsetWords,
                        isChannelTokenVault: managedStorageAddresses_[storageAddrIndex] == channelTokenVaultStorageAddress
                    })
                );
                if (managedStorageAddresses_[storageAddrIndex] == channelTokenVaultStorageAddress) {
                    _functionHasChannelTokenVaultWrite[functionKey] = true;
                }
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

    function registerChannelTokenVaultIdentity(address l2Address, bytes32 channelTokenVaultKey, uint256 leafIndex)
        external
    {
        if (l2Address == address(0)) revert InvalidL2Address();
        if (_channelTokenVaultRegistrations[msg.sender].exists) {
            revert ChannelTokenVaultIdentityAlreadyRegistered(msg.sender);
        }
        if (leafIndex >= TOKEN_VAULT_MT_LEAF_COUNT) {
            revert ChannelTokenVaultLeafIndexOutOfRange(leafIndex);
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
            leafIndex: leafIndex
        });
        _channelTokenVaultKeyOwners[channelTokenVaultKey] = msg.sender;
        _channelTokenVaultLeafOwners[leafIndex] = msg.sender;

        emit ChannelTokenVaultIdentityRegistered(msg.sender, l2Address, channelTokenVaultKey, leafIndex);
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
}
