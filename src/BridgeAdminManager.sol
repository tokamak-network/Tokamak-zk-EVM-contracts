// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "./BridgeAccessControl.sol";

contract BridgeAdminManager is BridgeOwnable {
    struct FcnCfg {
        bytes32 instancesHash;
        bytes32 preprocessHash;
        bool exists;
    }

    uint16 public nTokamakPublicInputs;
    uint8 public nMerkleTreeLevels;

    mapping(bytes4 => address[]) private _fcnStorages;
    mapping(bytes4 => mapping(address => bool)) private _hasFcnStorage;

    mapping(address => bytes32[]) private _preAllocKeys;
    mapping(address => mapping(bytes32 => bool)) private _hasPreAllocKey;

    mapping(address => uint8[]) private _userSlots;
    mapping(address => mapping(uint8 => bool)) private _hasUserSlot;

    mapping(bytes4 => FcnCfg) private _fcnCfgs;

    event ProofParamsUpdated(uint16 nTokamakPublicInputs, uint8 nMerkleTreeLevels);
    event FcnStoragesUpdated(bytes4 indexed fcnSig, uint256 storageCount);
    event PreAllocKeysUpdated(address indexed storageAddr, uint256 keyCount);
    event UserSlotsUpdated(address indexed storageAddr, uint256 slotCount);
    event FcnCfgUpdated(bytes4 indexed fcnSig, bytes32 instancesHash, bytes32 preprocessHash);

    constructor(uint16 _nTokamakPublicInputs, uint8 _nMerkleTreeLevels, address initialOwner)
        BridgeOwnable(initialOwner)
    {
        require(_nMerkleTreeLevels > 0, "Invalid merkle levels");
        nTokamakPublicInputs = _nTokamakPublicInputs;
        nMerkleTreeLevels = _nMerkleTreeLevels;
    }

    function setProofParams(uint16 _nTokamakPublicInputs, uint8 _nMerkleTreeLevels) external onlyOwner {
        require(_nMerkleTreeLevels > 0, "Invalid merkle levels");
        nTokamakPublicInputs = _nTokamakPublicInputs;
        nMerkleTreeLevels = _nMerkleTreeLevels;
        emit ProofParamsUpdated(_nTokamakPublicInputs, _nMerkleTreeLevels);
    }

    function setFcnStorages(bytes4 fcnSig, address[] calldata storageAddrs) external onlyOwner {
        require(fcnSig != bytes4(0), "Invalid function signature");
        _clearFcnStorages(fcnSig);

        for (uint256 i = 0; i < storageAddrs.length; i++) {
            address storageAddr = storageAddrs[i];
            require(storageAddr != address(0), "Invalid storage address");

            if (!_hasFcnStorage[fcnSig][storageAddr]) {
                _hasFcnStorage[fcnSig][storageAddr] = true;
                _fcnStorages[fcnSig].push(storageAddr);
            }
        }

        emit FcnStoragesUpdated(fcnSig, _fcnStorages[fcnSig].length);
    }

    function setPreAllocKeys(address storageAddr, bytes32[] calldata keys) external onlyOwner {
        require(storageAddr != address(0), "Invalid storage address");
        _clearPreAllocKeys(storageAddr);

        for (uint256 i = 0; i < keys.length; i++) {
            bytes32 key = keys[i];

            if (!_hasPreAllocKey[storageAddr][key]) {
                _hasPreAllocKey[storageAddr][key] = true;
                _preAllocKeys[storageAddr].push(key);
            }
        }

        emit PreAllocKeysUpdated(storageAddr, _preAllocKeys[storageAddr].length);
    }

    function setUserSlots(address storageAddr, uint8[] calldata slots) external onlyOwner {
        require(storageAddr != address(0), "Invalid storage address");
        _clearUserSlots(storageAddr);

        for (uint256 i = 0; i < slots.length; i++) {
            uint8 slot = slots[i];

            if (!_hasUserSlot[storageAddr][slot]) {
                _hasUserSlot[storageAddr][slot] = true;
                _userSlots[storageAddr].push(slot);
            }
        }

        emit UserSlotsUpdated(storageAddr, _userSlots[storageAddr].length);
    }

    function setFcnCfg(bytes4 fcnSig, bytes32 instancesHash, bytes32 preprocessHash) external onlyOwner {
        require(fcnSig != bytes4(0), "Invalid function signature");
        _fcnCfgs[fcnSig] = FcnCfg({instancesHash: instancesHash, preprocessHash: preprocessHash, exists: true});
        emit FcnCfgUpdated(fcnSig, instancesHash, preprocessHash);
    }

    function hasFcnCfg(bytes4 fcnSig) external view returns (bool) {
        return _fcnCfgs[fcnSig].exists;
    }

    function getFcnStorages(bytes4 fcnSig) external view returns (address[] memory) {
        return _fcnStorages[fcnSig];
    }

    function getPreAllocKeys(address storageAddr) external view returns (bytes32[] memory) {
        return _preAllocKeys[storageAddr];
    }

    function getUserSlots(address storageAddr) external view returns (uint8[] memory) {
        return _userSlots[storageAddr];
    }

    function getFcnCfg(bytes4 fcnSig) external view returns (bytes32 instancesHash, bytes32 preprocessHash) {
        FcnCfg memory cfg = _fcnCfgs[fcnSig];
        require(cfg.exists, "Function config not found");
        return (cfg.instancesHash, cfg.preprocessHash);
    }

    function _clearFcnStorages(bytes4 fcnSig) internal {
        address[] storage storages = _fcnStorages[fcnSig];
        for (uint256 i = 0; i < storages.length; i++) {
            _hasFcnStorage[fcnSig][storages[i]] = false;
        }
        delete _fcnStorages[fcnSig];
    }

    function _clearPreAllocKeys(address storageAddr) internal {
        bytes32[] storage keys = _preAllocKeys[storageAddr];
        for (uint256 i = 0; i < keys.length; i++) {
            _hasPreAllocKey[storageAddr][keys[i]] = false;
        }
        delete _preAllocKeys[storageAddr];
    }

    function _clearUserSlots(address storageAddr) internal {
        uint8[] storage slots = _userSlots[storageAddr];
        for (uint256 i = 0; i < slots.length; i++) {
            _hasUserSlot[storageAddr][slots[i]] = false;
        }
        delete _userSlots[storageAddr];
    }
}
