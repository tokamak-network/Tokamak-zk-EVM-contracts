// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ITokamakVerifier} from "./interface/ITokamakVerifier.sol";
import "./interface/IGroth16Verifier16Leaves.sol";
import "./interface/IRollupBridgeCore.sol";

contract RollupBridgeAdminManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    IRollupBridgeCore public rollupBridge;

    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event TargetContractAllowed(address indexed targetContract, bool allowed);
    event FunctionRegistered(
        bytes32 indexed functionSignature, uint256 preprocessedPart1Length, uint256 preprocessedPart2Length
    );
    event FunctionUnregistered(bytes32 indexed functionSignature);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);

    modifier onlyBridge() {
        require(msg.sender == address(rollupBridge), "Only bridge can call");
        _;
    }

    function initialize(address _rollupBridge, address _owner) public initializer {
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);

        require(_rollupBridge != address(0), "Invalid bridge address");
        rollupBridge = IRollupBridgeCore(_rollupBridge);
    }

    function setAllowedTargetContract(address targetContract, bytes1 _storageSlot, bool allowed) external onlyOwner {
        require(targetContract != address(0), "Invalid target contract address");

        rollupBridge.setAllowedTargetContract(targetContract, _storageSlot, allowed);
        emit TargetContractAllowed(targetContract, allowed);
    }

    function registerFunction(
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2
    ) external onlyOwner {
        require(functionSignature != bytes32(0), "Invalid function signature");
        require(preprocessedPart1.length > 0, "preprocessedPart1 cannot be empty");
        require(preprocessedPart2.length > 0, "preprocessedPart2 cannot be empty");

        rollupBridge.registerFunction(functionSignature, preprocessedPart1, preprocessedPart2);
        emit FunctionRegistered(functionSignature, preprocessedPart1.length, preprocessedPart2.length);
    }

    function unregisterFunction(bytes32 functionSignature) external onlyOwner {
        require(functionSignature != bytes32(0), "Invalid function signature");

        IRollupBridgeCore.RegisteredFunction memory registeredFunc =
            rollupBridge.getRegisteredFunction(functionSignature);
        require(registeredFunc.functionSignature != bytes32(0), "Function not registered");

        rollupBridge.unregisterFunction(functionSignature);
        emit FunctionUnregistered(functionSignature);
    }

    function setTreasuryAddress(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Treasury cannot be zero address");

        // Get current treasury address for event
        // This would need to be implemented to get the old treasury address
        address oldTreasury = address(0); // Placeholder

        rollupBridge.setTreasuryAddress(_treasury);
        emit TreasuryAddressUpdated(oldTreasury, _treasury);
    }

    function getRegisteredFunction(bytes32 functionSignature)
        external
        view
        returns (IRollupBridgeCore.RegisteredFunction memory)
    {
        return rollupBridge.getRegisteredFunction(functionSignature);
    }

    function isAllowedTargetContract(address targetContract) external view returns (bool) {
        return rollupBridge.isAllowedTargetContract(targetContract);
    }

    function getTargetContractData(address targetContract)
        external
        view
        returns (IRollupBridgeCore.TargetContract memory)
    {
        return rollupBridge.getTargetContractData(targetContract);
    }

    function updateRollupBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        rollupBridge = IRollupBridgeCore(_newBridge);
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
