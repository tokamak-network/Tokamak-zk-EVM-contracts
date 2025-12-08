// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ITokamakVerifier} from "./interface/ITokamakVerifier.sol";
import "./interface/IGroth16Verifier16Leaves.sol";
import "./interface/IBridgeCore.sol";

contract BridgeAdminManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    IBridgeCore public bridge;

    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event TargetContractAllowed(address indexed targetContract, bool allowed);
    event FunctionRegistered(
        bytes32 indexed functionSignature, uint256 preprocessedPart1Length, uint256 preprocessedPart2Length, bytes32 instancesHash
    );
    event FunctionUnregistered(bytes32 indexed functionSignature);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);

    modifier onlyBridge() {
        require(msg.sender == address(bridge), "Only bridge can call");
        _;
    }

    function initialize(address _bridgeCore, address _owner) public initializer {
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);

        require(_bridgeCore != address(0), "Invalid bridge address");
        bridge = IBridgeCore(_bridgeCore);
    }

    function setAllowedTargetContract(address targetContract, bytes1 _storageSlot, bool allowed) external onlyOwner {
        require(targetContract != address(0), "Invalid target contract address");

        bridge.setAllowedTargetContract(targetContract, _storageSlot, allowed);
        emit TargetContractAllowed(targetContract, allowed);
    }

    function registerFunction(
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bytes32 instancesHash
    ) external onlyOwner {
        require(functionSignature != bytes32(0), "Invalid function signature");
        require(preprocessedPart1.length > 0, "preprocessedPart1 cannot be empty");
        require(preprocessedPart2.length > 0, "preprocessedPart2 cannot be empty");

        bridge.registerFunction(functionSignature, preprocessedPart1, preprocessedPart2, instancesHash);
        emit FunctionRegistered(functionSignature, preprocessedPart1.length, preprocessedPart2.length, instancesHash);
    }

    function unregisterFunction(bytes32 functionSignature) external onlyOwner {
        require(functionSignature != bytes32(0), "Invalid function signature");

        IBridgeCore.RegisteredFunction memory registeredFunc =
            bridge.getRegisteredFunction(functionSignature);
        require(registeredFunc.functionSignature != bytes32(0), "Function not registered");

        bridge.unregisterFunction(functionSignature);
        emit FunctionUnregistered(functionSignature);
    }

    function getRegisteredFunction(bytes32 functionSignature)
        external
        view
        returns (IBridgeCore.RegisteredFunction memory)
    {
        return bridge.getRegisteredFunction(functionSignature);
    }

    function isAllowedTargetContract(address targetContract) external view returns (bool) {
        return bridge.isAllowedTargetContract(targetContract);
    }

    function getTargetContractData(address targetContract)
        external
        view
        returns (IBridgeCore.TargetContract memory)
    {
        return bridge.getTargetContractData(targetContract);
    }

    function updateBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        bridge = IBridgeCore(_newBridge);
    }

    // ========== PRE-ALLOCATED LEAVES MANAGEMENT ==========

    /**
     * @notice Set a pre-allocated leaf for a target contract
     * @param targetContract The target contract address
     * @param key The MPT key for the pre-allocated leaf
     * @param value The value for the pre-allocated leaf
     */
    function setPreAllocatedLeaf(address targetContract, bytes32 key, uint256 value) external onlyOwner {
        bridge.setPreAllocatedLeaf(targetContract, key, value);
    }

    /**
     * @notice Remove a pre-allocated leaf for a target contract
     * @param targetContract The target contract address
     * @param key The MPT key to remove
     */
    function removePreAllocatedLeaf(address targetContract, bytes32 key) external onlyOwner {
        bridge.removePreAllocatedLeaf(targetContract, key);
    }

    /**
     * @notice Setup TON transfer pre-allocated leaf (convenience function)
     * @dev Sets up the standard 0x07 slot with decimals value 18 for TON transfers
     * @param tonContractAddress The TON contract address
     */
    function setupTonTransferPreAllocatedLeaf(address tonContractAddress) external onlyOwner {
        // TON transfer uses slot 0x07 with decimals value 18
        bytes32 tonDecimalsSlot = bytes32(uint256(0x07));
        uint256 tonDecimalsValue = 18;
        
        bridge.setPreAllocatedLeaf(tonContractAddress, tonDecimalsSlot, tonDecimalsValue);
    }

    /**
     * @notice Get pre-allocated leaf information
     * @param targetContract The target contract address
     * @param key The key
     * @return value The value of the pre-allocated leaf
     * @return exists Whether the leaf exists
     */
    function getPreAllocatedLeaf(address targetContract, bytes32 key) 
        external 
        view 
        returns (uint256 value, bool exists) 
    {
        return bridge.getPreAllocatedLeaf(targetContract, key);
    }

    /**
     * @notice Get all pre-allocated MPT keys for a target contract
     * @param targetContract The target contract address
     * @return keys Array of MPT keys
     */
    function getPreAllocatedKeys(address targetContract) external view returns (bytes32[] memory keys) {
        return bridge.getPreAllocatedKeys(targetContract);
    }

    /**
     * @notice Get the maximum allowed participants for a target contract
     * @param targetContract The target contract address
     * @return maxParticipants Maximum number of participants allowed
     */
    function getMaxAllowedParticipants(address targetContract) external view returns (uint256 maxParticipants) {
        return bridge.getMaxAllowedParticipants(targetContract);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Returns the address of the current implementation contract
     * @dev Uses EIP-1967 standard storage slot for implementation address
     * @return implementation The address of the implementation contract
     */
    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    uint256[47] private __gap;
}
