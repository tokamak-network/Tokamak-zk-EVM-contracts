// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IBridgeCore} from "./interface/IBridgeCore.sol";

interface IBridgeDepositManager {
    function transferForWithdrawal(address targetContract, address to, uint256 amount) external;
}

contract BridgeWithdrawManager is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    IBridgeCore public bridge;

    event BridgeUpdated(address indexed newBridge);
    event Withdrawn(bytes32 indexed channelId, address indexed user, address indexed targetContract, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address bridgeCore, address owner_) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

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

    function withdraw(bytes32 channelId, address targetContract) external nonReentrant {
        IBridgeCore.ChannelState state = bridge.getChannelState(channelId);
        require(
            state == IBridgeCore.ChannelState.Closing || bridge.isChannelTimedOut(channelId),
            "Channel not withdrawable"
        );

        address channelTarget = bridge.getChannelTargetContract(channelId);
        address token = targetContract == address(0) ? channelTarget : targetContract;
        require(token == channelTarget, "Target mismatch");

        uint8 balanceSlot = bridge.getBalanceSlotIndex(token);
        uint256 amount = bridge.getValidatedUserSlotValue(channelId, msg.sender, balanceSlot);
        require(amount > 0, "No withdrawable balance");

        bridge.clearValidatedUserStorage(channelId, msg.sender, token);
        IBridgeDepositManager(bridge.depositManager()).transferForWithdrawal(token, msg.sender, amount);

        emit Withdrawn(channelId, msg.sender, token, amount);
    }

    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    uint256[48] private __gap;
}
