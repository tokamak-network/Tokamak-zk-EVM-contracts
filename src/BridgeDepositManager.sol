// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interface/IBridgeCore.sol";

contract BridgeDepositManager is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public constant ETH_TOKEN_ADDRESS = address(1);

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

    function depositToken(uint256 _channelId, address _token, uint256 _amount, bytes32 _mptKey) external nonReentrant {
        require(
            bridge.getChannelState(_channelId) == IBridgeCore.ChannelState.Initialized,
            "Invalid channel state"
        );
        require(bridge.isChannelParticipant(_channelId, msg.sender), "Not a participant");
        require(_token != ETH_TOKEN_ADDRESS, "Use depositETH for ETH deposits");
        require(bridge.isTokenAllowedInChannel(_channelId, _token), "Token not allowed in this channel");
        require(_mptKey != bytes32(0), "Invalid MPT key");
        require(_amount != 0, "amount must be greater than 0");

        uint256 userBalance = IERC20Upgradeable(_token).balanceOf(msg.sender);
        require(
            userBalance >= _amount,
            string(abi.encodePacked("Insufficient token balance: ", toString(userBalance), " < ", toString(_amount)))
        );

        uint256 userAllowance = IERC20Upgradeable(_token).allowance(msg.sender, address(this));
        require(
            userAllowance >= _amount,
            string(
                abi.encodePacked("Insufficient token allowance: ", toString(userAllowance), " < ", toString(_amount))
            )
        );

        uint256 balanceBefore = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balanceAfter = IERC20Upgradeable(_token).balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;
        require(actualAmount > 0, "No tokens transferred");

        bridge.setChannelL2MptKey(_channelId, msg.sender, _token, uint256(_mptKey));
        bridge.updateChannelTokenDeposits(_channelId, _token, msg.sender, actualAmount);
        bridge.updateChannelTotalDeposits(_channelId, _token, actualAmount);

        emit Deposited(_channelId, msg.sender, _token, actualAmount);
    }

    function updateBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        bridge = IBridgeCore(_newBridge);
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
