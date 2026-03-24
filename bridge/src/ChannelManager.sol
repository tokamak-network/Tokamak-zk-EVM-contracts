// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "./BridgeStructs.sol";
import {DAppManager} from "./DAppManager.sol";
import {ITokamakVerifier} from "./interfaces/ITokamakVerifier.sol";

contract ChannelManager {
    uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = 78;
    uint256 internal constant TOKAMAK_PREVIOUS_BLOCK_HASHES = 4;
    uint256 internal constant TOKEN_VAULT_MT_LEAF_COUNT = uint256(1) << 12;
    uint256 internal constant SPLIT_WORD_SIZE = 2;
    uint256 internal constant STORAGE_WRITE_VALUE_OFFSET = 2;

    struct CachedStorageWrite {
        address storageAddr;
        uint8 aPubOffsetWords;
        bool isTokenVault;
    }

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
    error APubBlockTooLong(uint256 expectedLength, uint256 actualLength);
    error APubUserTooShort(uint256 expectedLength, uint256 actualLength);
    error APubUserWordOutOfRange(uint256 index, uint256 value);
    error EntryContractPublicInputOutOfRange(uint256 value);
    error FunctionSigPublicInputOutOfRange(uint256 value);
    error InvalidStorageWriteStorageIndex(uint8 storageAddrIndex);
    error TokenVaultRootUpdateWithoutStorageWrite();
    error InvalidL2Address();
    error TokenVaultIdentityAlreadyRegistered(address user);
    error TokenVaultKeyAlreadyRegistered(bytes32 key);
    error TokenVaultLeafIndexAlreadyRegistered(uint256 leafIndex);
    error TokenVaultLeafIndexOutOfRange(uint256 leafIndex);
    error TokenVaultLeafIndexMismatch(uint256 expectedLeafIndex, uint256 actualLeafIndex);

    uint256 public immutable channelId;
    uint256 public immutable dappId;
    uint256 public genesisBlockNumber;
    address public immutable leader;
    bytes32 public immutable aPubBlockHash;
    uint256 public immutable tokenVaultTreeIndex;
    address public immutable tokenVaultStorageAddress;
    address public immutable bridgeCore;
    ITokamakVerifier public immutable tokamakVerifier;

    address public tokenVault;
    bytes32 public currentRootVectorHash;

    address[] private _managedStorageAddresses;

    mapping(bytes32 => bool) private _allowedFunctionKeys;
    mapping(bytes32 => BridgeStructs.FunctionConfig) private _functionConfigs;
    mapping(bytes32 => bytes32) private _functionKeyByPreprocessInputHash;
    mapping(bytes32 => CachedStorageWrite[]) private _functionStorageWrites;
    mapping(bytes32 => bool) private _functionHasTokenVaultWrite;
    BridgeStructs.FunctionReference[] private _allowedFunctions;

    mapping(uint256 => bytes32) private _latestTokenVaultLeaves;
    mapping(address => BridgeStructs.TokenVaultRegistration) private _tokenVaultRegistrations;
    mapping(bytes32 => address) private _tokenVaultKeyOwners;
    mapping(uint256 => address) private _tokenVaultLeafOwners;

    event TokenVaultBound(address indexed tokenVault);
    event TokenVaultIdentityRegistered(
        address indexed l1Address, address indexed l2Address, bytes32 indexed l2TokenVaultKey, uint256 leafIndex
    );
    event TokamakStateUpdateAccepted(bytes4 indexed functionSig, address indexed entryContract);
    event CurrentRootVectorObserved(bytes32 indexed rootVectorHash, bytes32[] rootVector);
    event StorageWriteObserved(address indexed storageAddr, uint256 storageKey, uint256 value);

    constructor(
        uint256 channelId_,
        uint256 dappId_,
        address leader_,
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
        genesisBlockNumber = block.number;
        leader = leader_;
        aPubBlockHash = _hashCurrentBlockInfo();
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

        currentRootVectorHash = keccak256(abi.encode(initialRootVector_));
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
                        isTokenVault: managedStorageAddresses_[storageAddrIndex] == tokenVaultStorageAddress
                    })
                );
                if (managedStorageAddresses_[storageAddrIndex] == tokenVaultStorageAddress) {
                    _functionHasTokenVaultWrite[functionKey] = true;
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

    function registerTokenVaultIdentity(address l2Address, bytes32 l2TokenVaultKey, uint256 leafIndex) external {
        if (l2Address == address(0)) revert InvalidL2Address();
        if (_tokenVaultRegistrations[msg.sender].exists) {
            revert TokenVaultIdentityAlreadyRegistered(msg.sender);
        }
        if (leafIndex >= TOKEN_VAULT_MT_LEAF_COUNT) {
            revert TokenVaultLeafIndexOutOfRange(leafIndex);
        }

        uint256 expectedLeafIndex = _deriveLeafIndexFromStorageKey(uint256(l2TokenVaultKey));
        if (leafIndex != expectedLeafIndex) {
            revert TokenVaultLeafIndexMismatch(expectedLeafIndex, leafIndex);
        }
        if (_tokenVaultKeyOwners[l2TokenVaultKey] != address(0)) {
            revert TokenVaultKeyAlreadyRegistered(l2TokenVaultKey);
        }
        if (_tokenVaultLeafOwners[leafIndex] != address(0)) {
            revert TokenVaultLeafIndexAlreadyRegistered(leafIndex);
        }

        _tokenVaultRegistrations[msg.sender] = BridgeStructs.TokenVaultRegistration({
            exists: true,
            l2Address: l2Address,
            l2TokenVaultKey: l2TokenVaultKey,
            leafIndex: leafIndex
        });
        _tokenVaultKeyOwners[l2TokenVaultKey] = msg.sender;
        _tokenVaultLeafOwners[leafIndex] = msg.sender;

        emit TokenVaultIdentityRegistered(msg.sender, l2Address, l2TokenVaultKey, leafIndex);
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

        address entryContract = _decodeAddressFromAPubUser(payload.aPubUser, functionConfig.entryContractOffsetWords);
        bytes4 functionSig = _decodeFunctionSigFromAPubUser(payload.aPubUser, functionConfig.functionSigOffsetWords);
        if (_computeFunctionKey(entryContract, functionSig) != functionKey) {
            revert UnsupportedChannelFunction(entryContract, functionSig);
        }

        bytes32 expectedPreprocessInputHash = functionConfig.preprocessInputHash;
        if (actualPreprocessInputHash != expectedPreprocessInputHash) {
            revert PreprocessInputHashMismatch(expectedPreprocessInputHash, actualPreprocessInputHash);
        }
        bytes32 actualAPubBlockHash = _hashNormalizedAPubBlock(payload.aPubBlock);
        if (actualAPubBlockHash != aPubBlockHash) {
            revert APubBlockHashMismatch(aPubBlockHash, actualAPubBlockHash);
        }

        bytes32[] memory currentRootVector =
            _decodeRootVectorFromAPubUser(payload.aPubUser, functionConfig.currentRootVectorOffsetWords);
        if (keccak256(abi.encode(currentRootVector)) != currentRootVectorHash) {
            revert UnexpectedCurrentRootVector();
        }
        bytes32[] memory updatedRootVector =
            _decodeUpdatedRootVectorFromAPubUser(payload.aPubUser, functionConfig.updatedRootVectorOffsetWords);
        bytes32 currentTokenVaultRoot = currentRootVector[tokenVaultTreeIndex];
        bytes32 updatedTokenVaultRoot = updatedRootVector[tokenVaultTreeIndex];
        bool hasTokenVaultStorageWrite = _functionHasTokenVaultWrite[functionKey];

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

        emit CurrentRootVectorObserved(currentRootVectorHash, currentRootVector);
        _observeStorageWrites(functionKey, payload.aPubUser);
        currentRootVectorHash = keccak256(abi.encode(updatedRootVector));

        emit TokamakStateUpdateAccepted(functionSig, entryContract);
        return true;
    }

    function applyVaultUpdate(
        bytes32[] calldata currentRootVector,
        bytes32 updatedTokenVaultRoot,
        uint256 leafIndex,
        bytes32 latestLeafValue
    ) external onlyTokenVault returns (bool) {
        if (currentRootVector.length != _managedStorageAddresses.length) {
            revert APubUserTooShort(_managedStorageAddresses.length, currentRootVector.length);
        }
        if (keccak256(abi.encode(currentRootVector)) != currentRootVectorHash) {
            revert UnexpectedCurrentRootVector();
        }

        emit CurrentRootVectorObserved(currentRootVectorHash, currentRootVector);
        _applyVaultLeaf(leafIndex, latestLeafValue);
        currentRootVectorHash = _deriveUpdatedRootVectorHash(currentRootVector, updatedTokenVaultRoot);
        return true;
    }

    function getManagedStorageAddresses() external view returns (address[] memory) {
        return _copyAddresses(_managedStorageAddresses);
    }

    function getLatestTokenVaultLeaf(uint256 leafIndex) external view returns (bytes32) {
        return _latestTokenVaultLeaves[leafIndex];
    }

    function getTokenVaultRegistration(address l1Address)
        external
        view
        returns (BridgeStructs.TokenVaultRegistration memory)
    {
        return _tokenVaultRegistrations[l1Address];
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
        if (aPubUser.length < requiredLength) {
            revert APubUserTooShort(requiredLength, aPubUser.length);
        }
    }

    function _decodeUpdatedRootVectorFromAPubUser(uint256[] calldata aPubUser, uint256 updatedRootVectorOffsetWords)
        private
        view
        returns (bytes32[] memory updatedRootVector)
    {
        uint256 rootVectorLength = _managedStorageAddresses.length;
        updatedRootVector = new bytes32[](rootVectorLength);
        for (uint256 i = 0; i < rootVectorLength;) {
            updatedRootVector[i] =
                _decodeBytes32FromAPubUser(aPubUser, updatedRootVectorOffsetWords + i * SPLIT_WORD_SIZE);
            unchecked {
                ++i;
            }
        }
    }

    function _decodeRootVectorFromAPubUser(uint256[] calldata aPubUser, uint256 rootVectorOffsetWords)
        private
        view
        returns (bytes32[] memory rootVector)
    {
        uint256 rootVectorLength = _managedStorageAddresses.length;
        rootVector = new bytes32[](rootVectorLength);
        for (uint256 i = 0; i < rootVectorLength;) {
            rootVector[i] = _decodeBytes32FromAPubUser(aPubUser, rootVectorOffsetWords + i * SPLIT_WORD_SIZE);
            unchecked {
                ++i;
            }
        }
    }

    function _observeStorageWrites(bytes32 functionKey, uint256[] calldata aPubUser) private {
        CachedStorageWrite[] storage storageWrites = _functionStorageWrites[functionKey];

        for (uint256 i = 0; i < storageWrites.length; i++) {
            CachedStorageWrite storage storageWrite = storageWrites[i];
            uint256 aPubOffsetWords = storageWrite.aPubOffsetWords;
            uint256 storageKey = _decodeSplitWord(aPubUser, aPubOffsetWords);
            uint256 value = _decodeSplitWord(aPubUser, aPubOffsetWords + STORAGE_WRITE_VALUE_OFFSET);

            emit StorageWriteObserved(storageWrite.storageAddr, storageKey, value);
            if (storageWrite.isTokenVault) {
                uint256 leafIndex = _deriveLeafIndexFromStorageKey(storageKey);
                _applyVaultLeaf(leafIndex, bytes32(value));
            }
        }
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

    function _hashCurrentBlockInfo() private view returns (bytes32) {
        uint256[] memory aPubBlock = new uint256[](TOKAMAK_APUB_BLOCK_LENGTH);
        uint256 selfBalance;
        assembly ("memory-safe") {
            selfBalance := selfbalance()
        }

        _writeSplitWord(aPubBlock, 0, uint256(uint160(address(block.coinbase))));
        _writeSplitWord(aPubBlock, 2, block.timestamp);
        _writeSplitWord(aPubBlock, 4, block.number);
        _writeSplitWord(aPubBlock, 6, uint256(block.prevrandao));
        _writeSplitWord(aPubBlock, 8, block.gaslimit);
        _writeSplitWord(aPubBlock, 10, block.chainid);
        _writeSplitWord(aPubBlock, 12, selfBalance);
        _writeSplitWord(aPubBlock, 14, block.basefee);

        uint256 offsetWords = 16;
        for (uint256 i = 1; i <= TOKAMAK_PREVIOUS_BLOCK_HASHES; i++) {
            uint256 blockHashNumber = block.number > i ? block.number - i : 0;
            _writeSplitWord(aPubBlock, offsetWords, uint256(blockhash(blockHashNumber)));
            unchecked {
                offsetWords += SPLIT_WORD_SIZE;
            }
        }

        return keccak256(abi.encode(aPubBlock));
    }

    function _hashNormalizedAPubBlock(uint256[] calldata aPubBlock) private pure returns (bytes32) {
        if (aPubBlock.length > TOKAMAK_APUB_BLOCK_LENGTH) {
            revert APubBlockTooLong(TOKAMAK_APUB_BLOCK_LENGTH, aPubBlock.length);
        }

        uint256[] memory normalized = new uint256[](TOKAMAK_APUB_BLOCK_LENGTH);
        for (uint256 i = 0; i < aPubBlock.length; i++) {
            normalized[i] = aPubBlock[i];
        }
        return keccak256(abi.encode(normalized));
    }

    function _writeSplitWord(uint256[] memory words, uint256 startIndex, uint256 value) private pure {
        words[startIndex] = uint256(uint128(value));
        words[startIndex + 1] = value >> 128;
    }

    function _computeFunctionKey(address entryContract, bytes4 functionSig) private pure returns (bytes32) {
        return keccak256(abi.encode(entryContract, functionSig));
    }

    function _deriveUpdatedRootVectorHash(bytes32[] calldata currentRootVector, bytes32 updatedTokenVaultRoot)
        private
        view
        returns (bytes32)
    {
        bytes32[] memory updatedRootVector = new bytes32[](currentRootVector.length);
        for (uint256 i = 0; i < currentRootVector.length; i++) {
            updatedRootVector[i] = currentRootVector[i];
        }
        updatedRootVector[tokenVaultTreeIndex] = updatedTokenVaultRoot;
        return keccak256(abi.encode(updatedRootVector));
    }

    function _applyVaultLeaf(uint256 leafIndex, bytes32 leafValue) private {
        _latestTokenVaultLeaves[leafIndex] = leafValue;
    }

    function _deriveLeafIndexFromStorageKey(uint256 storageKey) private pure returns (uint256) {
        return storageKey % TOKEN_VAULT_MT_LEAF_COUNT;
    }

    function _copyAddresses(address[] storage source) private view returns (address[] memory out) {
        out = new address[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }
}
