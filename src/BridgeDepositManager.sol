// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IBridgeCore} from "./interface/IBridgeCore.sol";

contract BridgeDepositManager is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IBridgeCore public bridge;

    event BridgeUpdated(address indexed newBridge);
    event Deposited(bytes32 indexed channelId, address indexed user, address indexed token, uint256 amount);

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

    function depositToken(bytes32 channelId, uint256 amount, bytes32[] calldata mptKeys) external nonReentrant {
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Initialized, "Invalid channel state");
        require(bridge.isChannelWhitelisted(channelId, msg.sender), "Not whitelisted");

        address token = bridge.getChannelTargetContract(channelId);
        require(token != address(0), "Invalid target contract");

        if (amount > 0) {
            IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        bridge.addParticipantOnDeposit(channelId, msg.sender);

        if (mptKeys.length > 0) {
            uint256[] memory keys = new uint256[](mptKeys.length);
            for (uint256 i = 0; i < mptKeys.length; i++) {
                keys[i] = uint256(mptKeys[i]);
            }
            bridge.setChannelL2MptKeys(channelId, msg.sender, keys);
        }

        if (amount > 0) {
            uint8 balanceSlotIndex = bridge.getBalanceSlotIndex(token);
            bridge.updateChannelUserDeposits(channelId, msg.sender, balanceSlotIndex, amount);
        }

        emit Deposited(channelId, msg.sender, token, amount);
    }

    function transferForWithdrawal(address targetContract, address to, uint256 amount) external {
        require(msg.sender == bridge.withdrawManager(), "Only withdraw manager");
        require(targetContract != address(0), "Invalid target contract");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        IERC20Upgradeable(targetContract).safeTransfer(to, amount);
    }

    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    uint256[48] private __gap;
}
