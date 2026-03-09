// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Owned} from "./Owned.sol";
import {BridgeAdminManager} from "./BridgeAdminManager.sol";

interface IGroth16Verifier {
    function verifyProof(uint256[16] calldata proof, uint256[5] calldata publicInput) external view returns (bool);
}

interface ITokamakVerifier {
    function verifyProof(
        uint256[42] calldata proof,
        uint256[4] calldata preprocess,
        uint256[] calldata publicInput
    ) external view returns (bool);
}

contract Channel is Owned {
    struct FcnCfg {
        bytes32 instanceHash;
        bytes32 preprocessHash;
    }

    struct UserStorageKeyBinding {
        bool exists;
        bytes32 key;
    }

    error InvalidAdminManager();
    error EmptyAppFunctionSet();
    error UnknownFunctionSignature();
    error UnknownStorageAddress();
    error UnknownFork();
    error RootConflict();
    error RootNotField255();
    error RootUnchanged();
    error MissingGroth16Verifier();
    error MissingTokamakVerifier();
    error InvalidVectorLength();
    error InvalidLeafWidth();
    error UnsupportedStorageKey();
    error UserNotRegistered();
    error UserStorageKeyConflict();
    error PreAllocKeyCollision();
    error UnverifiedProposal();
    error UnknownVerifiedRoot();
    error InvalidStateSync();

    BridgeAdminManager public immutable adminManager;
    uint16 public immutable nTokamakPublicInputs;
    uint8 public immutable nMerkleTreeLevels;
    uint16 public immutable nAppStorages;
    uint256 public immutable nMerkleLeaves;

    IGroth16Verifier public groth16Verifier;
    ITokamakVerifier public tokamakVerifier;

    bytes4[] private _appFunctionSigs;
    uint160[] private _appStorageAddrs;
    uint256[] private _users;
    uint8[] private _forkIds;
    uint16[] private _verifiedIndices;

    mapping(bytes4 => bool) private _appFunctionSeen;
    mapping(uint160 => bool) private _appStorageSeen;

    mapping(bytes4 => uint160[]) private _appFcnStorages;
    mapping(bytes4 => FcnCfg) private _appFcnCfg;

    mapping(uint160 => bytes32[]) private _appPreAllocKeys;
    mapping(uint160 => mapping(bytes32 => bool)) private _appPreAllocKeySeenByStorage;
    mapping(bytes32 => bool) private _appPreAllocKeyGlobal;

    mapping(uint160 => uint8[]) private _appUserSlots;
    mapping(uint160 => mapping(uint8 => bool)) private _appUserSlotSeenByStorage;

    mapping(uint256 => bool) private _userSeen;
    mapping(uint256 => mapping(uint160 => UserStorageKeyBinding)) private _userStorageKeyByPair;

    mapping(bytes32 => bool) private _userChannelStorageKeySeen;
    mapping(bytes32 => bytes32) private _userChannelStorageKeyOwner;

    mapping(uint160 => mapping(bytes32 => bool)) private _storageKeyAllowed;
    mapping(uint160 => mapping(bytes32 => bool)) private _userChannelKeyByStorage;
    mapping(uint160 => mapping(bytes32 => bool)) private _preAllocKeyByStorage;

    mapping(uint160 => mapping(bytes32 => bytes32)) private _validatedValueByStorageAndKey;
    mapping(uint160 => mapping(bytes32 => bool)) private _validatedValueExists;

    mapping(bytes32 => bool) private _verifiedRootSeen;
    mapping(uint16 => mapping(uint160 => bytes32)) private _verifiedRootByIndexStorage;
    mapping(uint16 => mapping(uint160 => bool)) private _verifiedRootExistsByIndexStorage;
    mapping(uint16 => bool) private _verifiedIndexSeen;
    bool private _hasVerifiedStates;
    uint16 private _maxVerifiedStateIndex;

    mapping(uint8 => bool) private _forkSeen;
    mapping(uint8 => uint16[]) private _forkIndices;
    mapping(uint8 => mapping(uint16 => bool)) private _forkIndexSeen;

    mapping(uint8 => mapping(uint16 => mapping(uint160 => bytes32))) private _proposedRootByForkIndexStorage;
    mapping(uint8 => mapping(uint16 => mapping(uint160 => bool))) private _proposedRootExistsByForkIndexStorage;

    mapping(uint8 => mapping(uint16 => bool)) private _proposalVerified;

    bool private _hasProposedStates;
    uint16 private _maxProposedStateIndex;

    event UserAdded(uint256 indexed userAddr);
    event UserStorageKeyBound(uint256 indexed userAddr, uint160 indexed storageAddr, bytes32 indexed userChannelStorageKey);
    event Groth16VerifierUpdated(address indexed verifier);
    event TokamakVerifierUpdated(address indexed verifier);
    event SingleStateLeafUpdated(uint160 indexed storageAddr, bytes32 indexed userChannelStorageKey, bytes32 updatedStorageValue);
    event ProposedStateRootsVerified(uint8 indexed forkId, uint16 indexed proposedStateIndex);
    event ProposedStateRootsPromoted(uint8 indexed forkId, uint16 indexed proposedStateIndex);
    event VerifiedStateSynchronizedToFork(uint8 indexed forkId);

    constructor(address initialOwner, BridgeAdminManager adminManager_, bytes4[] memory appFunctionSigs_) Owned(initialOwner) {
        if (address(adminManager_) == address(0)) revert InvalidAdminManager();
        if (appFunctionSigs_.length == 0) revert EmptyAppFunctionSet();

        adminManager = adminManager_;
        nTokamakPublicInputs = adminManager_.nTokamakPublicInputs();
        nMerkleTreeLevels = adminManager_.nMerkleTreeLevels();
        nMerkleLeaves = uint256(1) << nMerkleTreeLevels;

        for (uint256 i = 0; i < appFunctionSigs_.length; ++i) {
            _registerAppFunction(appFunctionSigs_[i]);
        }

        if (_appStorageAddrs.length > type(uint16).max) revert InvalidVectorLength();
        nAppStorages = uint16(_appStorageAddrs.length);
    }

    function setGroth16Verifier(address verifier) external onlyOwner {
        groth16Verifier = IGroth16Verifier(verifier);
        emit Groth16VerifierUpdated(verifier);
    }

    function setTokamakVerifier(address verifier) external onlyOwner {
        tokamakVerifier = ITokamakVerifier(verifier);
        emit TokamakVerifierUpdated(verifier);
    }

    function addUser(uint256 userAddr) external onlyOwner {
        if (_userSeen[userAddr]) return;
        _userSeen[userAddr] = true;
        _users.push(userAddr);
        emit UserAdded(userAddr);
    }

    function setUserStorageKey(
        uint256 userAddr,
        uint160 appStorageAddr,
        bytes32 userChannelStorageKey,
        bytes32 initialValidatedValue
    ) external onlyOwner {
        if (!_userSeen[userAddr]) revert UserNotRegistered();
        if (!_appStorageSeen[appStorageAddr]) revert UnknownStorageAddress();
        if (_appPreAllocKeyGlobal[userChannelStorageKey]) revert PreAllocKeyCollision();

        bytes32 ownerKey = keccak256(abi.encode(userAddr, appStorageAddr));
        if (_userChannelStorageKeySeen[userChannelStorageKey]) {
            if (_userChannelStorageKeyOwner[userChannelStorageKey] != ownerKey) revert UserStorageKeyConflict();
        }

        UserStorageKeyBinding storage binding = _userStorageKeyByPair[userAddr][appStorageAddr];
        if (binding.exists && binding.key != userChannelStorageKey) revert UserStorageKeyConflict();

        if (!binding.exists) {
            binding.exists = true;
            binding.key = userChannelStorageKey;
            _userChannelStorageKeySeen[userChannelStorageKey] = true;
            _userChannelStorageKeyOwner[userChannelStorageKey] = ownerKey;
            _storageKeyAllowed[appStorageAddr][userChannelStorageKey] = true;
            _userChannelKeyByStorage[appStorageAddr][userChannelStorageKey] = true;
            emit UserStorageKeyBound(userAddr, appStorageAddr, userChannelStorageKey);
        }

        _setValidatedValue(appStorageAddr, userChannelStorageKey, initialValidatedValue);
    }

    function updateSingleStateLeaf(
        uint160 appStorageAddr,
        bytes32 userChannelStorageKey,
        bytes32 updatedStorageValue,
        bytes32 updatedRoot,
        uint256[16] calldata proofGroth16,
        uint256[5] calldata publicInputGroth16
    ) external onlyOwner returns (bool) {
        if (!_appStorageSeen[appStorageAddr]) revert UnknownStorageAddress();
        if (!_userChannelKeyByStorage[appStorageAddr][userChannelStorageKey]) revert UnsupportedStorageKey();
        if (!_verifiedRootSeen[updatedRoot]) revert UnknownVerifiedRoot();

        IGroth16Verifier verifier = groth16Verifier;
        if (address(verifier) == address(0)) revert MissingGroth16Verifier();

        if (!verifier.verifyProof(proofGroth16, publicInputGroth16)) {
            return false;
        }

        _setValidatedValue(appStorageAddr, userChannelStorageKey, updatedStorageValue);

        emit SingleStateLeafUpdated(appStorageAddr, userChannelStorageKey, updatedStorageValue);
        return true;
    }

    function verifyProposedStateRoots(
        uint8 forkId,
        uint16 proposedStateIndex,
        uint160[] calldata appStorageAddrs,
        bytes32[][] calldata storageKeys,
        bytes32[][] calldata updatedStorageValues,
        bytes32[] calldata updatedRoots,
        uint256[42] calldata proofTokamak,
        uint256[4] calldata preprocessTokamak,
        uint256[] calldata publicInputTokamak
    ) external onlyOwner returns (bool) {
        _validateProposalShape(appStorageAddrs, storageKeys, updatedStorageValues, updatedRoots, publicInputTokamak);

        ITokamakVerifier verifier = tokamakVerifier;
        if (address(verifier) == address(0)) revert MissingTokamakVerifier();

        if (!verifier.verifyProof(proofTokamak, preprocessTokamak, publicInputTokamak)) {
            return false;
        }

        _ensureForkExists(forkId);
        _ensureForkIndexExists(forkId, proposedStateIndex);

        for (uint256 i = 0; i < appStorageAddrs.length; ++i) {
            uint160 storageAddr = appStorageAddrs[i];
            bytes32 updatedRoot = updatedRoots[i];
            if (!_isField255(updatedRoot)) revert RootNotField255();

            _checkProposedTransition(forkId, proposedStateIndex, storageAddr, updatedRoot);
            _setProposedRoot(forkId, proposedStateIndex, storageAddr, updatedRoot);

            for (uint256 j = 0; j < nMerkleLeaves; ++j) {
                bytes32 storageKey = storageKeys[i][j];
                if (!_storageKeyAllowed[storageAddr][storageKey]) revert UnsupportedStorageKey();
                _setValidatedValue(storageAddr, storageKey, updatedStorageValues[i][j]);
            }
        }

        _proposalVerified[forkId][proposedStateIndex] = true;
        if (!_hasProposedStates || proposedStateIndex > _maxProposedStateIndex) {
            _maxProposedStateIndex = proposedStateIndex;
        }
        _hasProposedStates = true;

        emit ProposedStateRootsVerified(forkId, proposedStateIndex);
        return true;
    }

    function promoteProposedStateRoots(uint8 forkId, uint16 proposedStateIndex) external onlyOwner {
        if (!_proposalVerified[forkId][proposedStateIndex]) revert UnverifiedProposal();

        if (!_verifiedIndexSeen[proposedStateIndex]) {
            _verifiedIndexSeen[proposedStateIndex] = true;
            _verifiedIndices.push(proposedStateIndex);
        }

        for (uint256 i = 0; i < _appStorageAddrs.length; ++i) {
            uint160 storageAddr = _appStorageAddrs[i];
            if (!_proposedRootExistsByForkIndexStorage[forkId][proposedStateIndex][storageAddr]) revert UnverifiedProposal();
            bytes32 root = _proposedRootByForkIndexStorage[forkId][proposedStateIndex][storageAddr];
            _setVerifiedRoot(proposedStateIndex, storageAddr, root);
        }

        if (!_hasVerifiedStates || proposedStateIndex > _maxVerifiedStateIndex) {
            _maxVerifiedStateIndex = proposedStateIndex;
        }
        _hasVerifiedStates = true;

        emit ProposedStateRootsPromoted(forkId, proposedStateIndex);
    }

    function synchronizeVerifiedStateToFreshFork(uint8 forkId) external onlyOwner {
        if (_forkSeen[forkId]) revert InvalidStateSync();
        if (!_hasVerifiedStates) revert InvalidStateSync();
        if (_hasProposedStates && _maxVerifiedStateIndex <= _maxProposedStateIndex) revert InvalidStateSync();

        _forkSeen[forkId] = true;
        _forkIds.push(forkId);

        for (uint256 i = 0; i < _verifiedIndices.length; ++i) {
            uint16 stateIndex = _verifiedIndices[i];
            _forkIndexSeen[forkId][stateIndex] = true;
            _forkIndices[forkId].push(stateIndex);

            for (uint256 j = 0; j < _appStorageAddrs.length; ++j) {
                uint160 storageAddr = _appStorageAddrs[j];
                bytes32 root = _verifiedRootByIndexStorage[stateIndex][storageAddr];
                _proposedRootByForkIndexStorage[forkId][stateIndex][storageAddr] = root;
                _proposedRootExistsByForkIndexStorage[forkId][stateIndex][storageAddr] = true;
            }

            _proposalVerified[forkId][stateIndex] = true;
        }

        _hasProposedStates = true;
        if (_maxVerifiedStateIndex > _maxProposedStateIndex) {
            _maxProposedStateIndex = _maxVerifiedStateIndex;
        }

        emit VerifiedStateSynchronizedToFork(forkId);
    }

    function getUsers() external view returns (uint256[] memory) {
        return _users;
    }

    function getAppFunctionSigs() external view returns (bytes4[] memory) {
        return _appFunctionSigs;
    }

    function getAppStorageAddrs() external view returns (uint160[] memory) {
        return _appStorageAddrs;
    }

    function getForkIds() external view returns (uint8[] memory) {
        return _forkIds;
    }

    function getAppFcnStorages(bytes4 functionSig) external view returns (uint160[] memory) {
        if (!_appFunctionSeen[functionSig]) revert UnknownFunctionSignature();
        return _appFcnStorages[functionSig];
    }

    function getAppPreAllocKeys(uint160 storageAddr) external view returns (bytes32[] memory) {
        if (!_appStorageSeen[storageAddr]) revert UnknownStorageAddress();
        return _appPreAllocKeys[storageAddr];
    }

    function getAppUserSlots(uint160 storageAddr) external view returns (uint8[] memory) {
        if (!_appStorageSeen[storageAddr]) revert UnknownStorageAddress();
        return _appUserSlots[storageAddr];
    }

    function getAppFcnCfg(bytes4 functionSig) external view returns (bytes32 instanceHash, bytes32 preprocessHash) {
        if (!_appFunctionSeen[functionSig]) revert UnknownFunctionSignature();
        FcnCfg memory cfg = _appFcnCfg[functionSig];
        return (cfg.instanceHash, cfg.preprocessHash);
    }

    function getAppUserStorageKey(uint256 userAddr, uint160 appStorageAddr) external view returns (bytes32) {
        UserStorageKeyBinding memory binding = _userStorageKeyByPair[userAddr][appStorageAddr];
        if (!binding.exists) revert UnsupportedStorageKey();
        return binding.key;
    }

    function getAppValidatedStorageValue(uint160 appStorageAddr, bytes32 userChannelStorageKey) external view returns (bytes32) {
        if (!_userChannelKeyByStorage[appStorageAddr][userChannelStorageKey]) revert UnsupportedStorageKey();
        if (!_validatedValueExists[appStorageAddr][userChannelStorageKey]) revert UnsupportedStorageKey();
        return _validatedValueByStorageAndKey[appStorageAddr][userChannelStorageKey];
    }

    function getAppPreAllocValue(uint160 appStorageAddr, bytes32 preAllocKey) external view returns (bytes32) {
        if (!_preAllocKeyByStorage[appStorageAddr][preAllocKey]) revert UnsupportedStorageKey();
        if (!_validatedValueExists[appStorageAddr][preAllocKey]) revert UnsupportedStorageKey();
        return _validatedValueByStorageAndKey[appStorageAddr][preAllocKey];
    }

    function getVerifiedStateRoot(uint160 appStorageAddr, uint16 stateIndex) external view returns (bytes32) {
        if (!_verifiedRootExistsByIndexStorage[stateIndex][appStorageAddr]) revert UnknownVerifiedRoot();
        return _verifiedRootByIndexStorage[stateIndex][appStorageAddr];
    }

    function getProposedStateRoot(uint8 forkId, uint160 appStorageAddr, uint16 stateIndex) external view returns (bytes32) {
        if (!_proposedRootExistsByForkIndexStorage[forkId][stateIndex][appStorageAddr]) revert UnknownFork();
        return _proposedRootByForkIndexStorage[forkId][stateIndex][appStorageAddr];
    }

    function getProposedStateFork(
        uint8 forkId
    ) external view returns (uint16[] memory stateIndices, uint160[] memory appStorageAddrs, bytes32[] memory roots) {
        if (!_forkSeen[forkId]) revert UnknownFork();

        uint16[] memory indices = _forkIndices[forkId];
        uint256 total = indices.length * _appStorageAddrs.length;

        stateIndices = new uint16[](total);
        appStorageAddrs = new uint160[](total);
        roots = new bytes32[](total);

        uint256 cursor = 0;
        for (uint256 i = 0; i < indices.length; ++i) {
            uint16 stateIndex = indices[i];
            for (uint256 j = 0; j < _appStorageAddrs.length; ++j) {
                uint160 storageAddr = _appStorageAddrs[j];
                stateIndices[cursor] = stateIndex;
                appStorageAddrs[cursor] = storageAddr;
                roots[cursor] = _proposedRootByForkIndexStorage[forkId][stateIndex][storageAddr];
                ++cursor;
            }
        }
    }

    function hasVerifiedStates() external view returns (bool) {
        return _hasVerifiedStates;
    }

    function maxVerifiedStateIndex() external view returns (uint16) {
        return _maxVerifiedStateIndex;
    }

    function maxProposedStateIndex() external view returns (uint16) {
        return _maxProposedStateIndex;
    }

    function _registerAppFunction(bytes4 functionSig) internal {
        if (_appFunctionSeen[functionSig]) return;

        bool registered = adminManager.isFunctionRegistered(functionSig);
        if (!registered) revert UnknownFunctionSignature();

        uint160[] memory storages = adminManager.getFcnStorages(functionSig);
        if (storages.length == 0) revert UnknownFunctionSignature();

        _appFunctionSeen[functionSig] = true;
        _appFunctionSigs.push(functionSig);

        (bytes32 instanceHash, bytes32 preprocessHash) = adminManager.getFcnCfg(functionSig);
        _appFcnCfg[functionSig] = FcnCfg({instanceHash: instanceHash, preprocessHash: preprocessHash});

        for (uint256 i = 0; i < storages.length; ++i) {
            uint160 storageAddr = storages[i];
            _appFcnStorages[functionSig].push(storageAddr);

            if (_appStorageSeen[storageAddr]) continue;
            _appStorageSeen[storageAddr] = true;
            _appStorageAddrs.push(storageAddr);
            _hydrateStorageMetadata(storageAddr);
        }
    }

    function _hydrateStorageMetadata(uint160 storageAddr) internal {
        bytes32[] memory preAllocKeys = adminManager.getPreAllocKeys(storageAddr);
        for (uint256 i = 0; i < preAllocKeys.length; ++i) {
            bytes32 preAllocKey = preAllocKeys[i];
            if (_appPreAllocKeySeenByStorage[storageAddr][preAllocKey]) continue;

            _appPreAllocKeySeenByStorage[storageAddr][preAllocKey] = true;
            _appPreAllocKeyGlobal[preAllocKey] = true;
            _preAllocKeyByStorage[storageAddr][preAllocKey] = true;
            _storageKeyAllowed[storageAddr][preAllocKey] = true;
            _appPreAllocKeys[storageAddr].push(preAllocKey);

            // Pre-allocated pairs must always have a validated value entry.
            _setValidatedValue(storageAddr, preAllocKey, bytes32(0));
        }

        uint8[] memory slots = adminManager.getUserSlots(storageAddr);
        for (uint256 i = 0; i < slots.length; ++i) {
            uint8 userSlot = slots[i];
            if (_appUserSlotSeenByStorage[storageAddr][userSlot]) continue;
            _appUserSlotSeenByStorage[storageAddr][userSlot] = true;
            _appUserSlots[storageAddr].push(userSlot);
        }
    }

    function _setValidatedValue(uint160 storageAddr, bytes32 storageKey, bytes32 value) internal {
        if (!_storageKeyAllowed[storageAddr][storageKey]) revert UnsupportedStorageKey();
        _validatedValueByStorageAndKey[storageAddr][storageKey] = value;
        _validatedValueExists[storageAddr][storageKey] = true;
    }

    function _validateProposalShape(
        uint160[] calldata appStorageAddrs,
        bytes32[][] calldata storageKeys,
        bytes32[][] calldata updatedStorageValues,
        bytes32[] calldata updatedRoots,
        uint256[] calldata publicInputTokamak
    ) internal view {
        if (appStorageAddrs.length != nAppStorages) revert InvalidVectorLength();
        if (storageKeys.length != nAppStorages) revert InvalidVectorLength();
        if (updatedStorageValues.length != nAppStorages) revert InvalidVectorLength();
        if (updatedRoots.length != nAppStorages) revert InvalidVectorLength();
        if (publicInputTokamak.length != nTokamakPublicInputs) revert InvalidVectorLength();

        for (uint256 i = 0; i < nAppStorages; ++i) {
            if (appStorageAddrs[i] != _appStorageAddrs[i]) revert InvalidVectorLength();
            if (storageKeys[i].length != nMerkleLeaves) revert InvalidLeafWidth();
            if (updatedStorageValues[i].length != nMerkleLeaves) revert InvalidLeafWidth();
        }
    }

    function _ensureForkExists(uint8 forkId) internal {
        if (_forkSeen[forkId]) return;
        _forkSeen[forkId] = true;
        _forkIds.push(forkId);
    }

    function _ensureForkIndexExists(uint8 forkId, uint16 stateIndex) internal {
        if (_forkIndexSeen[forkId][stateIndex]) return;
        _forkIndexSeen[forkId][stateIndex] = true;
        _forkIndices[forkId].push(stateIndex);
    }

    function _setProposedRoot(uint8 forkId, uint16 stateIndex, uint160 storageAddr, bytes32 root) internal {
        if (_proposedRootExistsByForkIndexStorage[forkId][stateIndex][storageAddr]) {
            if (_proposedRootByForkIndexStorage[forkId][stateIndex][storageAddr] != root) revert RootConflict();
            return;
        }

        _proposedRootByForkIndexStorage[forkId][stateIndex][storageAddr] = root;
        _proposedRootExistsByForkIndexStorage[forkId][stateIndex][storageAddr] = true;
    }

    function _setVerifiedRoot(uint16 stateIndex, uint160 storageAddr, bytes32 root) internal {
        if (!_isField255(root)) revert RootNotField255();

        if (_verifiedRootExistsByIndexStorage[stateIndex][storageAddr]) {
            if (_verifiedRootByIndexStorage[stateIndex][storageAddr] != root) revert RootConflict();
            return;
        }

        _checkVerifiedTransition(stateIndex, storageAddr, root);

        _verifiedRootByIndexStorage[stateIndex][storageAddr] = root;
        _verifiedRootExistsByIndexStorage[stateIndex][storageAddr] = true;
        _verifiedRootSeen[root] = true;
    }

    function _checkProposedTransition(uint8 forkId, uint16 stateIndex, uint160 storageAddr, bytes32 root) internal view {
        if (stateIndex > 0 && _proposedRootExistsByForkIndexStorage[forkId][stateIndex - 1][storageAddr]) {
            if (_proposedRootByForkIndexStorage[forkId][stateIndex - 1][storageAddr] == root) revert RootUnchanged();
        }

        if (stateIndex < type(uint16).max && _proposedRootExistsByForkIndexStorage[forkId][stateIndex + 1][storageAddr]) {
            if (_proposedRootByForkIndexStorage[forkId][stateIndex + 1][storageAddr] == root) revert RootUnchanged();
        }
    }

    function _checkVerifiedTransition(uint16 stateIndex, uint160 storageAddr, bytes32 root) internal view {
        if (stateIndex > 0 && _verifiedRootExistsByIndexStorage[stateIndex - 1][storageAddr]) {
            if (_verifiedRootByIndexStorage[stateIndex - 1][storageAddr] == root) revert RootUnchanged();
        }

        if (stateIndex < type(uint16).max && _verifiedRootExistsByIndexStorage[stateIndex + 1][storageAddr]) {
            if (_verifiedRootByIndexStorage[stateIndex + 1][storageAddr] == root) revert RootUnchanged();
        }
    }

    function _isField255(bytes32 value) internal pure returns (bool) {
        return uint256(value) < (uint256(1) << 255);
    }
}
