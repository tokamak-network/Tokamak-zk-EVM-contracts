// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {BridgeStructs} from "./BridgeStructs.sol";

contract BridgeAdminManager is Ownable {
    error EmptyStorageAddressList();
    error UnknownFunctionSignature(bytes4 functionSig);
    error UnknownStorageAddress(address storageAddr);

    uint16 public nTokamakPublicInputs;
    uint8 public nMerkleTreeLevels;

    mapping(bytes4 => BridgeStructs.FunctionConfig) private _functionConfigs;
    mapping(bytes4 => address[]) private _functionStorages;
    mapping(address => bytes32[]) private _preAllocatedKeys;
    mapping(address => uint8[]) private _userStorageSlots;

    bytes4[] private _registeredFunctionSigns;
    address[] private _registeredStorageAddresses;
    mapping(bytes4 => bool) private _knownFunctionSign;
    mapping(address => bool) private _knownStorageAddress;

    event MerkleTreeLevelsUpdated(uint8 levels);
    event TokamakPublicInputsUpdated(uint16 length);
    event StorageMetadataRegistered(address indexed storageAddr);
    event FunctionRegistered(
        bytes4 indexed functionSig,
        bytes32 instanceHash,
        bytes32 preprocessHash
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setTokamakPublicInputsLength(uint16 length_) external onlyOwner {
        nTokamakPublicInputs = length_;
        emit TokamakPublicInputsUpdated(length_);
    }

    function setMerkleTreeLevels(uint8 levels_) external onlyOwner {
        nMerkleTreeLevels = levels_;
        emit MerkleTreeLevelsUpdated(levels_);
    }

    function registerStorageMetadata(
        address storageAddr,
        bytes32[] calldata preAllocKeys,
        uint8[] calldata userSlots
    ) external onlyOwner {
        if (!_knownStorageAddress[storageAddr]) {
            _knownStorageAddress[storageAddr] = true;
            _registeredStorageAddresses.push(storageAddr);
        }

        delete _preAllocatedKeys[storageAddr];
        for (uint256 i = 0; i < preAllocKeys.length; i++) {
            _preAllocatedKeys[storageAddr].push(preAllocKeys[i]);
        }

        delete _userStorageSlots[storageAddr];
        for (uint256 i = 0; i < userSlots.length; i++) {
            _userStorageSlots[storageAddr].push(userSlots[i]);
        }

        emit StorageMetadataRegistered(storageAddr);
    }

    function registerFunction(
        bytes4 functionSig,
        address[] calldata storageAddrs,
        bytes32 instanceHash,
        bytes32 preprocessHash
    ) external onlyOwner {
        if (storageAddrs.length == 0) {
            revert EmptyStorageAddressList();
        }

        if (!_knownFunctionSign[functionSig]) {
            _knownFunctionSign[functionSig] = true;
            _registeredFunctionSigns.push(functionSig);
        }

        delete _functionStorages[functionSig];
        for (uint256 i = 0; i < storageAddrs.length; i++) {
            if (!_knownStorageAddress[storageAddrs[i]]) {
                revert UnknownStorageAddress(storageAddrs[i]);
            }
            _functionStorages[functionSig].push(storageAddrs[i]);
        }

        _functionConfigs[functionSig] = BridgeStructs.FunctionConfig({
            instanceHash: instanceHash,
            preprocessHash: preprocessHash,
            exists: true
        });

        emit FunctionRegistered(functionSig, instanceHash, preprocessHash);
    }

    function hasFunction(bytes4 functionSig) external view returns (bool) {
        return _functionConfigs[functionSig].exists;
    }

    function getFunctionConfig(bytes4 functionSig)
        external
        view
        returns (BridgeStructs.FunctionConfig memory)
    {
        if (!_functionConfigs[functionSig].exists) {
            revert UnknownFunctionSignature(functionSig);
        }
        return _functionConfigs[functionSig];
    }

    function getFunctionStorages(bytes4 functionSig) external view returns (address[] memory) {
        if (!_functionConfigs[functionSig].exists) {
            revert UnknownFunctionSignature(functionSig);
        }
        return _copyAddresses(_functionStorages[functionSig]);
    }

    function getPreAllocKeys(address storageAddr) external view returns (bytes32[] memory) {
        if (!_knownStorageAddress[storageAddr]) {
            revert UnknownStorageAddress(storageAddr);
        }
        return _copyBytes32(_preAllocatedKeys[storageAddr]);
    }

    function getUserSlots(address storageAddr) external view returns (uint8[] memory) {
        if (!_knownStorageAddress[storageAddr]) {
            revert UnknownStorageAddress(storageAddr);
        }
        return _copyUint8(_userStorageSlots[storageAddr]);
    }

    function getRegisteredFunctionSigns() external view returns (bytes4[] memory out) {
        out = new bytes4[](_registeredFunctionSigns.length);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = _registeredFunctionSigns[i];
        }
    }

    function getRegisteredStorageAddresses() external view returns (address[] memory) {
        return _copyAddresses(_registeredStorageAddresses);
    }

    function getMaxMerkleTreeLeaves() external view returns (uint256) {
        return uint256(1) << uint256(nMerkleTreeLevels);
    }

    function _copyAddresses(address[] storage source) private view returns (address[] memory out) {
        out = new address[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }

    function _copyBytes32(bytes32[] storage source) private view returns (bytes32[] memory out) {
        out = new bytes32[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }

    function _copyUint8(uint8[] storage source) private view returns (uint8[] memory out) {
        out = new uint8[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            out[i] = source[i];
        }
    }
}

