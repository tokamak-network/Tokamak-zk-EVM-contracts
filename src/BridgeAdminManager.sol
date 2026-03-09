// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IBridgeCore} from "./interface/IBridgeCore.sol";

contract BridgeAdminManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    IBridgeCore public bridge;

    event BridgeUpdated(address indexed newBridge);
    event TargetContractAllowed(address indexed targetContract, bool allowed);
    event FunctionRegistered(bytes32 indexed functionSignature, address indexed storageAddr);
    event FunctionUnregistered(bytes32 indexed functionSignature, address indexed storageAddr);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address bridgeCore, address owner_) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        require(bridgeCore != address(0), "Invalid bridge address");
        bridge = IBridgeCore(bridgeCore);
        _transferOwnership(owner_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function updateBridge(address newBridge) external onlyOwner {
        require(newBridge != address(0), "Invalid bridge address");
        bridge = IBridgeCore(newBridge);
        emit BridgeUpdated(newBridge);
    }

    function setAllowedTargetContract(
        address targetContract,
        IBridgeCore.PreAllocatedLeaf[] memory leaves,
        IBridgeCore.UserStorageSlot[] memory userStorageSlots,
        bool allowed
    ) external onlyOwner {
        bridge.setAllowedTargetContract(targetContract, leaves, userStorageSlots, allowed);
        emit TargetContractAllowed(targetContract, allowed);
    }

    function registerFunction(
        address storageAddr,
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bytes32 instancesHash
    ) external onlyOwner {
        bridge.registerFunction(storageAddr, functionSignature, preprocessedPart1, preprocessedPart2, instancesHash);
        emit FunctionRegistered(functionSignature, storageAddr);
    }

    function unregisterFunction(address storageAddr, bytes32 functionSignature) external onlyOwner {
        bridge.unregisterFunction(storageAddr, functionSignature);
        emit FunctionUnregistered(functionSignature, storageAddr);
    }

    function setPreAllocatedLeaf(address storageAddr, bytes32 key, uint256 value) external onlyOwner {
        bridge.setPreAllocatedLeaf(storageAddr, key, value);
    }

    function removePreAllocatedLeaf(address storageAddr, bytes32 key) external onlyOwner {
        bridge.removePreAllocatedLeaf(storageAddr, key);
    }

    function setupTonTransferPreAllocatedLeaf(address tonContractAddress) external onlyOwner {
        bridge.setPreAllocatedLeaf(tonContractAddress, bytes32(uint256(0x07)), 18);
    }

    function getPreAllocatedLeaf(address storageAddr, bytes32 key) external view returns (uint256 value, bool exists) {
        return bridge.getPreAllocatedLeaf(storageAddr, key);
    }

    function getTargetContractData(address storageAddr) external view returns (IBridgeCore.TargetContract memory) {
        return bridge.getTargetContractData(storageAddr);
    }

    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    uint256[48] private __gap;
}
