// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interface/IBridgeCore.sol";
import "./BridgeDepositManager.sol";

contract BridgeWithdrawManager is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant PROOF_SUBMISSION_DEADLINE = 7 days;
    uint256 public constant NATIVE_TOKEN_TRANSFER_GAS_LIMIT = 1_000_000;

    IBridgeCore public bridge;

    event ChannelClosed(uint256 indexed channelId);
    event EmergencyWithdrawalsEnabled(uint256 indexed channelId);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);

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

    function withdraw(uint256 channelId) external nonReentrant {
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Closed, "Not closed");
        require(bridge.isChannelParticipant(channelId, msg.sender), "Not a participant");

        address targetContract = bridge.getChannelTargetContract(channelId);
        require(targetContract != address(0), "Invalid target contract");

        uint256 withdrawAmount = bridge.getWithdrawableAmount(channelId, msg.sender);
        require(withdrawAmount > 0, "No withdrawable amount");

        // Clear the withdrawable amount
        bridge.clearWithdrawableAmount(channelId, msg.sender);

        // Transfer the token from deposit manager (where tokens are held)
        BridgeDepositManager(bridge.depositManager()).transferForWithdrawal(targetContract, msg.sender, withdrawAmount);

        emit Withdrawn(channelId, msg.sender, targetContract, withdrawAmount);
    }

    function updateBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        bridge = IBridgeCore(_newBridge);
    }

    receive() external payable {}

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

    uint256[45] private __gap;
}
