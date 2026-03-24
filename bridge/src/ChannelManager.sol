// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "./BridgeStructs.sol";
import {DAppManager} from "./DAppManager.sol";
import {ITokamakVerifier} from "./interfaces/ITokamakVerifier.sol";

contract ChannelManager {
    // These offsets follow the current Tokamak synthesizer instance_description.json layout.
    uint256 internal constant UPDATED_ROOT_VECTOR_OFFSET = 0;
    uint256 internal constant ENTRY_CONTRACT_OFFSET = 22;
    uint256 internal constant FUNCTION_SIG_OFFSET = 24;
    uint256 internal constant CURRENT_ROOT_VECTOR_OFFSET = 26;
    uint256 internal constant SPLIT_WORD_SIZE = 2;

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
    error RootVectorExceedsAPubUserLayout(uint256 rootCount);
    error APubUserWordOutOfRange(uint256 index, uint256 value);
    error EntryContractPublicInputOutOfRange(uint256 value);
    error FunctionSigPublicInputOutOfRange(uint256 value);

    uint256 public immutable channelId;
    uint256 public immutable dappId;
    address public immutable leader;
    bytes32 public immutable aPubBlockHash;
    uint256 public immutable tokenVaultTreeIndex;
    address public immutable bridgeCore;
    ITokamakVerifier public immutable tokamakVerifier;

    address public tokenVault;
    bytes32 public currentRootVectorHash;

    bytes32[] private _currentRootVector;
    address[] private _managedStorageAddresses;

    mapping(bytes32 => bool) private _allowedFunctionKeys;
    mapping(bytes32 => bytes32) private _preprocessInputHashes;
    BridgeStructs.FunctionReference[] private _allowedFunctions;

    mapping(uint256 => bytes32) private _latestTokenVaultLeaves;
    uint256[] private _storedLeafIndices;
    mapping(uint256 => bool) private _knownLeafIndex;

    event TokenVaultBound(address indexed tokenVault);
    event TokamakStateUpdateAccepted(bytes4 indexed functionSig, address indexed entryContract);
    event VaultRootUpdateApplied(bytes32 indexed currentRoot, bytes32 indexed updatedRoot, uint256 leafIndex);
    event RootVectorUpdated(bytes32 indexed rootVectorHash, bytes32[] rootVector);

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
            _preprocessInputHashes[functionKey] = functionConfig.preprocessInputHash;
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

    function submitTokamakProof(BridgeStructs.TokamakProofPayload calldata payload) external returns (bool) {
        _assertAPubUserLayout(payload.aPubUser);
        _assertCurrentRootVectorFromAPubUser(payload.aPubUser);

        address entryContract = _decodeAddressFromAPubUser(payload.aPubUser, ENTRY_CONTRACT_OFFSET);
        bytes4 functionSig = _decodeFunctionSigFromAPubUser(payload.aPubUser, FUNCTION_SIG_OFFSET);

        bytes32 functionKey = _computeFunctionKey(entryContract, functionSig);
        if (!_allowedFunctionKeys[functionKey]) {
            revert UnsupportedChannelFunction(entryContract, functionSig);
        }

        bytes32 actualPreprocessInputHash =
            keccak256(abi.encode(payload.functionPreprocessPart1, payload.functionPreprocessPart2));
        bytes32 expectedPreprocessInputHash = _preprocessInputHashes[functionKey];
        if (actualPreprocessInputHash != expectedPreprocessInputHash) {
            revert PreprocessInputHashMismatch(expectedPreprocessInputHash, actualPreprocessInputHash);
        }
        bytes32 actualAPubBlockHash = keccak256(abi.encode(payload.aPubBlock));
        if (actualAPubBlockHash != aPubBlockHash) {
            revert APubBlockHashMismatch(aPubBlockHash, actualAPubBlockHash);
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

        _replaceCurrentRootVector(_decodeUpdatedRootVectorFromAPubUser(payload.aPubUser));
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

        _currentRootVector[tokenVaultTreeIndex] = updatedTokenVaultRoot;
        _publishCurrentRootVector(_copyBytes32Array(_currentRootVector));
        _setLatestTokenVaultLeaf(leafIndex, latestLeafValue);

        emit VaultRootUpdateApplied(currentTokenVaultRoot, updatedTokenVaultRoot, leafIndex);
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

    function _assertCurrentRootVectorFromAPubUser(uint256[] calldata aPubUser) private view {
        for (uint256 i = 0; i < _currentRootVector.length; i++) {
            if (_decodeBytes32FromAPubUser(aPubUser, CURRENT_ROOT_VECTOR_OFFSET + i * 2) != _currentRootVector[i]) {
                revert UnexpectedCurrentRootVector();
            }
        }
    }

    function _replaceCurrentRootVector(bytes32[] memory newRootVector) private {
        delete _currentRootVector;
        for (uint256 i = 0; i < newRootVector.length; i++) {
            _currentRootVector.push(newRootVector[i]);
        }
        _publishCurrentRootVector(newRootVector);
    }

    function _replaceManagedStorageAddresses(address[] memory storageAddresses) private {
        delete _managedStorageAddresses;
        for (uint256 i = 0; i < storageAddresses.length; i++) {
            _managedStorageAddresses.push(storageAddresses[i]);
        }
    }

    function _assertAPubUserLayout(uint256[] calldata aPubUser) private view {
        if (_currentRootVector.length * SPLIT_WORD_SIZE > ENTRY_CONTRACT_OFFSET) {
            revert RootVectorExceedsAPubUserLayout(_currentRootVector.length);
        }
        uint256 requiredLength = CURRENT_ROOT_VECTOR_OFFSET + _currentRootVector.length * SPLIT_WORD_SIZE;
        if (aPubUser.length < requiredLength) {
            revert APubUserTooShort(requiredLength, aPubUser.length);
        }
    }

    function _decodeUpdatedRootVectorFromAPubUser(uint256[] calldata aPubUser)
        private
        view
        returns (bytes32[] memory updatedRootVector)
    {
        updatedRootVector = new bytes32[](_currentRootVector.length);
        for (uint256 i = 0; i < _currentRootVector.length; i++) {
            updatedRootVector[i] = _decodeBytes32FromAPubUser(aPubUser, UPDATED_ROOT_VECTOR_OFFSET + i * 2);
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
