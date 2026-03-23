// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "./BridgeStructs.sol";
import {BridgeAdminManager} from "./BridgeAdminManager.sol";
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
    error RootVectorLengthMismatch();
    error StorageAddressVectorLengthMismatch();
    error UnexpectedCurrentRootVector();
    error UnsupportedChannelFunction(address entryContract, bytes4 functionSig);
    error TokamakProofRejected();
    error InvalidTokenVaultTreeIndex();
    error PreprocessInputHashMismatch(bytes32 expectedHash, bytes32 actualHash);
    error APubBlockHashMismatch(bytes32 expectedHash, bytes32 actualHash);
    error TokamakPublicInputsLengthMismatch(uint256 expectedLength, uint256 actualLength);
    error APubUserTooShort(uint256 expectedLength, uint256 actualLength);
    error RootVectorExceedsAPubUserLayout(uint256 rootCount);
    error APubUserWordOutOfRange(uint256 index, uint256 value);
    error EntryContractPublicInputOutOfRange(uint256 value);
    error FunctionSigPublicInputOutOfRange(uint256 value);
    error UpdatedRootVectorPublicInputMismatch(uint256 index, bytes32 expectedRoot, bytes32 actualRoot);
    error CurrentRootVectorPublicInputMismatch(uint256 index, bytes32 expectedRoot, bytes32 actualRoot);
    error EntryContractPublicInputMismatch(address expectedEntryContract, address actualEntryContract);
    error FunctionSigPublicInputMismatch(bytes4 expectedFunctionSig, bytes4 actualFunctionSig);

    uint256 public immutable channelId;
    uint256 public immutable dappId;
    address public immutable leader;
    bytes32 public immutable aPubBlockHash;
    uint256 public immutable tokenVaultTreeIndex;
    address public immutable bridgeCore;
    BridgeAdminManager public immutable adminManager;
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
        bytes32 aPubBlockHash_,
        uint256 tokenVaultTreeIndex_,
        bytes32[] memory initialRootVector_,
        address[] memory managedStorageAddresses_,
        BridgeStructs.FunctionReference[] memory allowedFunctions_,
        address bridgeCore_,
        BridgeAdminManager adminManager_,
        DAppManager dAppManager_,
        ITokamakVerifier tokamakVerifier_
    ) {
        channelId = channelId_;
        dappId = dappId_;
        leader = leader_;
        aPubBlockHash = aPubBlockHash_;
        bridgeCore = bridgeCore_;
        adminManager = adminManager_;
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
        if (instance.updatedRootVector.length != instance.currentRootVector.length) {
            revert RootVectorLengthMismatch();
        }
        BridgeStructs.TokamakProofPayload memory payload = abi.decode(proof, (BridgeStructs.TokamakProofPayload));
        _assertTokamakPublicInputLength(payload.aPubUser.length + payload.aPubBlock.length);
        _assertTransactionInstanceMatchesAPubUser(instance, payload.aPubUser);
        _assertCurrentRootVector(instance.currentRootVector);

        bytes32 functionKey = dAppManager.computeFunctionKey(instance.entryContract, instance.functionSig);
        if (!_allowedFunctionKeys[functionKey]) {
            revert UnsupportedChannelFunction(instance.entryContract, instance.functionSig);
        }

        BridgeStructs.FunctionConfig memory cfg =
            dAppManager.getFunctionMetadata(dappId, instance.entryContract, instance.functionSig);
        if (cfg.preprocessInputHash != bytes32(0)) {
            bytes32 actualPreprocessInputHash =
                keccak256(abi.encode(payload.functionPreprocessPart1, payload.functionPreprocessPart2));
            if (actualPreprocessInputHash != cfg.preprocessInputHash) {
                revert PreprocessInputHashMismatch(cfg.preprocessInputHash, actualPreprocessInputHash);
            }
        }
        if (aPubBlockHash != bytes32(0)) {
            bytes32 actualAPubBlockHash = keccak256(abi.encode(payload.aPubBlock));
            if (actualAPubBlockHash != aPubBlockHash) {
                revert APubBlockHashMismatch(aPubBlockHash, actualAPubBlockHash);
            }
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

    function _assertTokamakPublicInputLength(uint256 actualLength) private view {
        uint256 expectedLength = adminManager.nTokamakPublicInputs();
        if (expectedLength != 0 && actualLength != expectedLength) {
            revert TokamakPublicInputsLengthMismatch(expectedLength, actualLength);
        }
    }

    function _assertTransactionInstanceMatchesAPubUser(
        BridgeStructs.TokamakTransactionInstance calldata instance,
        uint256[] memory aPubUser
    ) private pure {
        if (instance.updatedRootVector.length * SPLIT_WORD_SIZE > ENTRY_CONTRACT_OFFSET) {
            revert RootVectorExceedsAPubUserLayout(instance.updatedRootVector.length);
        }
        uint256 requiredLength = CURRENT_ROOT_VECTOR_OFFSET + instance.currentRootVector.length * SPLIT_WORD_SIZE;
        if (aPubUser.length < requiredLength) {
            revert APubUserTooShort(requiredLength, aPubUser.length);
        }

        for (uint256 i = 0; i < instance.updatedRootVector.length; i++) {
            bytes32 actualUpdatedRoot = _decodeBytes32FromAPubUser(aPubUser, UPDATED_ROOT_VECTOR_OFFSET + i * 2);
            if (actualUpdatedRoot != instance.updatedRootVector[i]) {
                revert UpdatedRootVectorPublicInputMismatch(i, instance.updatedRootVector[i], actualUpdatedRoot);
            }
        }

        address actualEntryContract = _decodeAddressFromAPubUser(aPubUser, ENTRY_CONTRACT_OFFSET);
        if (actualEntryContract != instance.entryContract) {
            revert EntryContractPublicInputMismatch(instance.entryContract, actualEntryContract);
        }

        bytes4 actualFunctionSig = _decodeFunctionSigFromAPubUser(aPubUser, FUNCTION_SIG_OFFSET);
        if (actualFunctionSig != instance.functionSig) {
            revert FunctionSigPublicInputMismatch(instance.functionSig, actualFunctionSig);
        }

        for (uint256 i = 0; i < instance.currentRootVector.length; i++) {
            bytes32 actualCurrentRoot = _decodeBytes32FromAPubUser(aPubUser, CURRENT_ROOT_VECTOR_OFFSET + i * 2);
            if (actualCurrentRoot != instance.currentRootVector[i]) {
                revert CurrentRootVectorPublicInputMismatch(i, instance.currentRootVector[i], actualCurrentRoot);
            }
        }
    }

    function _decodeBytes32FromAPubUser(uint256[] memory aPubUser, uint256 startIndex) private pure returns (bytes32) {
        return bytes32(_decodeSplitWord(aPubUser, startIndex));
    }

    function _decodeAddressFromAPubUser(uint256[] memory aPubUser, uint256 startIndex) private pure returns (address) {
        uint256 combined = _decodeSplitWord(aPubUser, startIndex);
        if (combined > type(uint160).max) {
            revert EntryContractPublicInputOutOfRange(combined);
        }
        return address(uint160(combined));
    }

    function _decodeFunctionSigFromAPubUser(uint256[] memory aPubUser, uint256 startIndex)
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

    function _decodeSplitWord(uint256[] memory words, uint256 startIndex) private pure returns (uint256 combined) {
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
