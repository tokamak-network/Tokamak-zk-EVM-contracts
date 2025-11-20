// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "./library/RollupBridgeLib.sol";
import "./interface/IRollupBridgeCore.sol";

contract RollupBridgeDepositManager is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public constant ETH_TOKEN_ADDRESS = address(1);

    IRollupBridgeCore public rollupBridge;

    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);

    modifier onlyBridge() {
        require(msg.sender == address(rollupBridge), "Only bridge can call");
        _;
    }

    function initialize(address _rollupBridge, address _owner) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        _transferOwnership(_owner);

        require(_rollupBridge != address(0), "Invalid bridge address");
        rollupBridge = IRollupBridgeCore(_rollupBridge);
    }

    function depositETH(uint256 _channelId, bytes32 _mptKey) external payable nonReentrant {
        require(
            rollupBridge.getChannelState(_channelId) == IRollupBridgeCore.ChannelState.Initialized,
            "Invalid channel state"
        );
        require(rollupBridge.isChannelParticipant(_channelId, msg.sender), "Not a participant");
        require(msg.value > 0, "Deposit must be greater than 0");
        require(rollupBridge.isTokenAllowedInChannel(_channelId, ETH_TOKEN_ADDRESS), "ETH not allowed in this channel");
        require(_mptKey != bytes32(0), "Invalid MPT key");

        rollupBridge.setChannelL2MptKey(_channelId, msg.sender, ETH_TOKEN_ADDRESS, uint256(_mptKey));
        rollupBridge.updateChannelTokenDeposits(_channelId, ETH_TOKEN_ADDRESS, msg.sender, msg.value);
        rollupBridge.updateChannelTotalDeposits(_channelId, ETH_TOKEN_ADDRESS, msg.value);

        emit Deposited(_channelId, msg.sender, ETH_TOKEN_ADDRESS, msg.value);
    }

    function depositToken(uint256 _channelId, address _token, uint256 _amount, bytes32 _mptKey) external nonReentrant {
        require(
            rollupBridge.getChannelState(_channelId) == IRollupBridgeCore.ChannelState.Initialized,
            "Invalid channel state"
        );
        require(rollupBridge.isChannelParticipant(_channelId, msg.sender), "Not a participant");
        require(_token != ETH_TOKEN_ADDRESS, "Use depositETH for ETH deposits");
        require(rollupBridge.isTokenAllowedInChannel(_channelId, _token), "Token not allowed in this channel");
        require(_mptKey != bytes32(0), "Invalid MPT key");
        require(_amount != 0, "amount must be greater than 0");

        uint256 actualAmount = RollupBridgeLib.depositToken(msg.sender, IERC20Upgradeable(_token), _amount);

        rollupBridge.setChannelL2MptKey(_channelId, msg.sender, _token, uint256(_mptKey));
        rollupBridge.updateChannelTokenDeposits(_channelId, _token, msg.sender, actualAmount);
        rollupBridge.updateChannelTotalDeposits(_channelId, _token, actualAmount);

        emit Deposited(_channelId, msg.sender, _token, actualAmount);
    }

    function updateRollupBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        rollupBridge = IRollupBridgeCore(_newBridge);
    }

    uint256[48] private __gap;
}
