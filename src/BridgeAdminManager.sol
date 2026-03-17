// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Owned} from "./Owned.sol";

contract BridgeAdminManager is Owned {
    struct FcnCfg {
        bytes32 instanceHash;
        bytes32 preprocessHash;
        bool exists;
    }

    error InvalidFunctionSignature();
    error FunctionAlreadyRegistered();
    error FunctionNotRegistered();
    error EmptyStorageSet();
    error DuplicateConfiguration();
    error InvalidStorageAddress();
    error InvalidMerkleLevel();

    uint16 public nTokamakPublicInputs;
    uint8 public nMerkleTreeLevels;

    bytes4[] private _fcnSigns;
    uint160[] private _storageAddrs;

    mapping(bytes4 => bool) private _fcnRegistered;
    mapping(uint160 => bool) private _storageRegistered;

    mapping(bytes4 => uint160[]) private _fcnStorages;
    mapping(bytes4 => mapping(uint160 => bool)) private _fcnStorageSeen;

    mapping(uint160 => bytes32[]) private _preAllocKeys;
    mapping(uint160 => mapping(bytes32 => bool)) private _preAllocKeySeen;
    mapping(bytes32 => bool) private _globalPreAllocKeySeen;

    mapping(uint160 => uint8[]) private _userSlots;
    mapping(uint160 => mapping(uint8 => bool)) private _userSlotSeen;

    mapping(bytes4 => FcnCfg) private _fcnCfg;
    mapping(bytes32 => bytes4) private _cfgToFunction;
    mapping(bytes32 => bool) private _cfgSeen;

    event FunctionRegistered(bytes4 indexed functionSig, bytes32 indexed instanceHash, bytes32 indexed preprocessHash);
    event FunctionStorageAdded(bytes4 indexed functionSig, uint160 indexed storageAddr);
    event PreAllocKeyAdded(uint160 indexed storageAddr, bytes32 indexed preAllocKey);
    event UserSlotAdded(uint160 indexed storageAddr, uint8 indexed userSlot);
    event TokamakParamsUpdated(uint16 nTokamakPublicInputs, uint8 nMerkleTreeLevels);

    constructor(address initialOwner, uint16 tokamakPublicInputs, uint8 merkleTreeLevels) Owned(initialOwner) {
        if (merkleTreeLevels > 32) revert InvalidMerkleLevel();
        nTokamakPublicInputs = tokamakPublicInputs;
        nMerkleTreeLevels = merkleTreeLevels;
    }

    function setTokamakParams(uint16 tokamakPublicInputs, uint8 merkleTreeLevels) external onlyOwner {
        if (merkleTreeLevels > 32) revert InvalidMerkleLevel();
        nTokamakPublicInputs = tokamakPublicInputs;
        nMerkleTreeLevels = merkleTreeLevels;
        emit TokamakParamsUpdated(tokamakPublicInputs, merkleTreeLevels);
    }

    function registerFunction(
        bytes4 functionSig,
        uint160[] calldata storageAddrs,
        bytes32 instanceHash,
        bytes32 preprocessHash
    ) external onlyOwner {
        if (functionSig == bytes4(0)) revert InvalidFunctionSignature();
        if (_fcnRegistered[functionSig]) revert FunctionAlreadyRegistered();
        if (storageAddrs.length == 0) revert EmptyStorageSet();

        bytes32 cfgId = keccak256(abi.encode(instanceHash, preprocessHash));
        if (_cfgSeen[cfgId]) revert DuplicateConfiguration();

        _cfgSeen[cfgId] = true;
        _cfgToFunction[cfgId] = functionSig;

        _fcnRegistered[functionSig] = true;
        _fcnSigns.push(functionSig);
        _fcnCfg[functionSig] = FcnCfg({instanceHash: instanceHash, preprocessHash: preprocessHash, exists: true});

        for (uint256 i = 0; i < storageAddrs.length; ++i) {
            _addFunctionStorage(functionSig, storageAddrs[i]);
        }

        emit FunctionRegistered(functionSig, instanceHash, preprocessHash);
    }

    function addFunctionStorage(bytes4 functionSig, uint160 storageAddr) external onlyOwner {
        if (!_fcnRegistered[functionSig]) revert FunctionNotRegistered();
        _addFunctionStorage(functionSig, storageAddr);
    }

    function addPreAllocKey(uint160 storageAddr, bytes32 preAllocKey) external onlyOwner {
        if (!_storageRegistered[storageAddr]) revert InvalidStorageAddress();
        if (_preAllocKeySeen[storageAddr][preAllocKey]) return;

        _preAllocKeySeen[storageAddr][preAllocKey] = true;
        _globalPreAllocKeySeen[preAllocKey] = true;
        _preAllocKeys[storageAddr].push(preAllocKey);

        emit PreAllocKeyAdded(storageAddr, preAllocKey);
    }

    function addUserSlot(uint160 storageAddr, uint8 userSlot) external onlyOwner {
        if (!_storageRegistered[storageAddr]) revert InvalidStorageAddress();
        if (_userSlotSeen[storageAddr][userSlot]) return;

        _userSlotSeen[storageAddr][userSlot] = true;
        _userSlots[storageAddr].push(userSlot);

        emit UserSlotAdded(storageAddr, userSlot);
    }

    function isFunctionRegistered(bytes4 functionSig) external view returns (bool) {
        return _fcnRegistered[functionSig];
    }

    function isStorageRegistered(uint160 storageAddr) external view returns (bool) {
        return _storageRegistered[storageAddr];
    }

    function isPreAllocKey(bytes32 preAllocKey) external view returns (bool) {
        return _globalPreAllocKeySeen[preAllocKey];
    }

    function getFcnSigns() external view returns (bytes4[] memory) {
        return _fcnSigns;
    }

    function getStorageAddrs() external view returns (uint160[] memory) {
        return _storageAddrs;
    }

    function getFcnStorages(bytes4 functionSig) external view returns (uint160[] memory) {
        return _fcnStorages[functionSig];
    }

    function getPreAllocKeys(uint160 storageAddr) external view returns (bytes32[] memory) {
        return _preAllocKeys[storageAddr];
    }

    function getUserSlots(uint160 storageAddr) external view returns (uint8[] memory) {
        return _userSlots[storageAddr];
    }

    function getFcnCfg(bytes4 functionSig) external view returns (bytes32 instanceHash, bytes32 preprocessHash) {
        FcnCfg memory cfg = _fcnCfg[functionSig];
        if (!cfg.exists) revert FunctionNotRegistered();
        return (cfg.instanceHash, cfg.preprocessHash);
    }

    function _addFunctionStorage(bytes4 functionSig, uint160 storageAddr) internal {
        if (storageAddr == uint160(0)) revert InvalidStorageAddress();
        if (_fcnStorageSeen[functionSig][storageAddr]) return;

        _fcnStorageSeen[functionSig][storageAddr] = true;
        _fcnStorages[functionSig].push(storageAddr);

        if (!_storageRegistered[storageAddr]) {
            _storageRegistered[storageAddr] = true;
            _storageAddrs.push(storageAddr);
        }

        emit FunctionStorageAdded(functionSig, storageAddr);
    }
}
