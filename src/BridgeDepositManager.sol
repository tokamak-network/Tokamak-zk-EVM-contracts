// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interface/IBridgeCore.sol";

contract BridgeDepositManager is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    using SafeERC20Upgradeable for IERC20Upgradeable;

    IBridgeCore public bridge;

    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);

    modifier onlyBridge() {
        require(msg.sender == address(bridge), "Only bridge can call");
        _;
    }

    function initialize(address _bridgeCore, address _owner) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);

        require(_bridgeCore != address(0), "Invalid bridge address");
        bridge = IBridgeCore(_bridgeCore);
    }

    function depositToken(uint256 _channelId, uint256 _amount, bytes32 _mptKey) external nonReentrant {
        require(bridge.getChannelState(_channelId) == IBridgeCore.ChannelState.Initialized, "Invalid channel state");
        // require(bridge.isChannelParticipant(_channelId, msg.sender), "Not a participant");
        require(bridge.isChannelWhitelisted(_channelId, msg.sender), "Not whitelisted");

        // Only require public key to be set if frost signature is enabled
        bool frostEnabled = bridge.isFrostSignatureEnabled(_channelId);
        if (frostEnabled) {
            require(bridge.isChannelPublicKeySet(_channelId), "Channel leader must set public key first");
        }

        require(_mptKey != bytes32(0), "Invalid MPT key");
        // we allow 0 TON transfers
        //require(_amount != 0, "amount must be greater than 0");

        address targetContract = bridge.getChannelTargetContract(_channelId);
        require(targetContract != address(0), "Invalid target contract");
        require(bridge.isAllowedTargetContract(targetContract), "Target contract not allowed");

        uint256 userBalance = IERC20Upgradeable(targetContract).balanceOf(msg.sender);
        require(
            userBalance >= _amount,
            string(abi.encodePacked("Insufficient token balance: ", toString(userBalance), " < ", toString(_amount)))
        );

        uint256 userAllowance = IERC20Upgradeable(targetContract).allowance(msg.sender, address(this));
        require(
            userAllowance >= _amount,
            string(
                abi.encodePacked("Insufficient token allowance: ", toString(userAllowance), " < ", toString(_amount))
            )
        );

        if (_amount > 0) {
            uint256 balanceBefore = IERC20Upgradeable(targetContract).balanceOf(address(this));
            IERC20Upgradeable(targetContract).safeTransferFrom(msg.sender, address(this), _amount);
            uint256 balanceAfter = IERC20Upgradeable(targetContract).balanceOf(address(this));
            uint256 actualAmount = balanceAfter - balanceBefore;
            require(actualAmount > 0, "No tokens transferred");
            bridge.updateChannelUserDeposits(_channelId, msg.sender, actualAmount);
            bridge.updateChannelTotalDeposits(_channelId, actualAmount);
        }

        // Add user to participants array when they make their first deposit
        bridge.addParticipantOnDeposit(_channelId, msg.sender);

        bridge.setChannelL2MptKey(_channelId, msg.sender, uint256(_mptKey));

        emit Deposited(_channelId, msg.sender, targetContract, _amount);
    }

    function updateBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        bridge = IBridgeCore(_newBridge);
    }

    function transferForWithdrawal(address targetContract, address to, uint256 amount) external {
        require(msg.sender == address(bridge.withdrawManager()), "Only withdraw manager can call");
        require(targetContract != address(0), "Invalid target contract");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        IERC20Upgradeable(targetContract).safeTransfer(to, amount);
    }

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
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
