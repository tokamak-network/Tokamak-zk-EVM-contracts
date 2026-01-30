// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interface/IBridgeCore.sol";
import "./interface/IBridgeStakingManager.sol";

/**
 * @title BridgeStakingManager
 * @notice Manages TON staking, slashing, and reward distribution for the bridge
 * @dev Part of the Q2 2026 upgrade implementing the objection/slash/reward architecture
 */
contract BridgeStakingManager is
    IBridgeStakingManager,
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ========== CONSTANTS ==========

    uint256 public constant MINIMUM_STAKE = 100 ether;        // 100 TON minimum
    uint256 public constant STAKE_LOCK_PERIOD = 7 days;       // 7 day lock period
    uint256 public constant UNSTAKE_COOLDOWN = 2 days;        // 2 day cooldown after request
    uint256 public constant INVALID_PROOF_SLASH = 50;         // 50% slash for invalid proof
    uint256 public constant FALSE_OBJECTION_SLASH = 25;       // 25% slash for false objection
    uint256 public constant PERCENTAGE_BASE = 100;

    // ========== STORAGE ==========

    /// @custom:storage-location erc7201:tokamak.storage.BridgeStakingManager
    struct BridgeStakingManagerStorage {
        IBridgeCore bridge;
        address tonToken;
        address objectionManager;
        // channelId => staker => StakeInfo
        mapping(bytes32 => mapping(address => StakeInfo)) stakes;
        // channelId => staker => unstake request timestamp
        mapping(bytes32 => mapping(address => uint256)) unstakeRequests;
        // address => pending rewards
        mapping(address => uint256) pendingRewards;
        // Total reward pool from slashing
        uint256 rewardPool;
        // Slash records for auditing
        SlashRecord[] slashRecords;
    }

    bytes32 private constant BridgeStakingManagerStorageLocation =
        0x2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a01;

    // ========== EVENTS ==========

    event ObjectionManagerUpdated(address indexed oldManager, address indexed newManager);

    // ========== MODIFIERS ==========

    modifier onlyObjectionManager() {
        BridgeStakingManagerStorage storage $ = _getStorage();
        require(msg.sender == $.objectionManager, "Only objection manager");
        _;
    }

    modifier onlyAuthorizedManager() {
        BridgeStakingManagerStorage storage $ = _getStorage();
        require(
            msg.sender == $.objectionManager || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ========== INITIALIZATION ==========

    function initialize(
        address _bridgeCore,
        address _tonToken,
        address _owner
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);

        require(_bridgeCore != address(0), "Invalid bridge address");
        require(_tonToken != address(0), "Invalid TON token address");

        BridgeStakingManagerStorage storage $ = _getStorage();
        $.bridge = IBridgeCore(_bridgeCore);
        $.tonToken = _tonToken;
    }

    // ========== STAKING FUNCTIONS ==========

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function stakeForChannel(bytes32 channelId, uint256 amount) external nonReentrant {
        require(amount >= MINIMUM_STAKE, "Below minimum stake");

        BridgeStakingManagerStorage storage $ = _getStorage();

        // Verify channel exists and is in valid state
        IBridgeCore.ChannelState state = $.bridge.getChannelState(channelId);
        require(
            state == IBridgeCore.ChannelState.Initialized ||
            state == IBridgeCore.ChannelState.Open ||
            state == IBridgeCore.ChannelState.Disputing,
            "Invalid channel state for staking"
        );

        // Verify staker is a participant
        require($.bridge.isChannelWhitelisted(channelId, msg.sender), "Not a channel participant");

        StakeInfo storage stake = $.stakes[channelId][msg.sender];

        // Transfer TON tokens
        IERC20Upgradeable($.tonToken).safeTransferFrom(msg.sender, address(this), amount);

        // Update stake info
        stake.amount += amount;
        stake.lockedUntil = block.timestamp + STAKE_LOCK_PERIOD;
        stake.isActive = true;

        emit Staked(channelId, msg.sender, amount);
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function requestUnstake(bytes32 channelId) external nonReentrant {
        BridgeStakingManagerStorage storage $ = _getStorage();
        StakeInfo storage stake = $.stakes[channelId][msg.sender];

        require(stake.isActive, "No active stake");
        require(stake.amount > 0, "No stake to unstake");
        require(block.timestamp >= stake.lockedUntil, "Stake still locked");

        // Verify channel is closed or timed out
        IBridgeCore.ChannelState state = $.bridge.getChannelState(channelId);
        require(
            state == IBridgeCore.ChannelState.Closing ||
            state == IBridgeCore.ChannelState.None ||
            $.bridge.isChannelTimedOut(channelId),
            "Channel still active"
        );

        // Set cooldown
        $.unstakeRequests[channelId][msg.sender] = block.timestamp + UNSTAKE_COOLDOWN;

        emit UnstakeRequested(channelId, msg.sender, block.timestamp + UNSTAKE_COOLDOWN);
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function unstake(bytes32 channelId) external nonReentrant {
        BridgeStakingManagerStorage storage $ = _getStorage();

        uint256 cooldownEnd = $.unstakeRequests[channelId][msg.sender];
        require(cooldownEnd > 0, "No unstake request");
        require(block.timestamp >= cooldownEnd, "Cooldown not finished");

        StakeInfo storage stake = $.stakes[channelId][msg.sender];
        require(stake.isActive, "No active stake");

        uint256 amount = stake.amount;
        require(amount > 0, "Nothing to unstake");

        // Clear stake
        stake.amount = 0;
        stake.isActive = false;
        delete $.unstakeRequests[channelId][msg.sender];

        // Transfer tokens back
        IERC20Upgradeable($.tonToken).safeTransfer(msg.sender, amount);

        emit Unstaked(channelId, msg.sender, amount);
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function claimRewards() external nonReentrant {
        BridgeStakingManagerStorage storage $ = _getStorage();

        uint256 rewards = $.pendingRewards[msg.sender];
        require(rewards > 0, "No rewards to claim");
        require($.rewardPool >= rewards, "Insufficient reward pool");

        $.pendingRewards[msg.sender] = 0;
        $.rewardPool -= rewards;

        IERC20Upgradeable($.tonToken).safeTransfer(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    // ========== SLASHING FUNCTIONS ==========

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function slash(
        bytes32 channelId,
        address staker,
        uint256 percentage,
        bytes32 reason
    ) external onlyAuthorizedManager nonReentrant {
        require(percentage > 0 && percentage <= PERCENTAGE_BASE, "Invalid percentage");

        BridgeStakingManagerStorage storage $ = _getStorage();
        StakeInfo storage stake = $.stakes[channelId][staker];

        require(stake.isActive && stake.amount > 0, "No stake to slash");

        uint256 slashAmount = (stake.amount * percentage) / PERCENTAGE_BASE;
        stake.amount -= slashAmount;

        // Add to reward pool
        $.rewardPool += slashAmount;

        // Record slash
        $.slashRecords.push(SlashRecord({
            staker: staker,
            amount: slashAmount,
            reason: reason,
            timestamp: block.timestamp
        }));

        // Deactivate if fully slashed
        if (stake.amount == 0) {
            stake.isActive = false;
        }

        emit Slashed(channelId, staker, slashAmount, reason);
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function distributeReward(
        bytes32 channelId,
        address recipient,
        uint256 amount
    ) external onlyAuthorizedManager nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        BridgeStakingManagerStorage storage $ = _getStorage();
        require($.rewardPool >= amount, "Insufficient reward pool");

        $.pendingRewards[recipient] += amount;

        emit RewardDistributed(channelId, recipient, amount);
    }

    // ========== ADMIN FUNCTIONS ==========

    function setObjectionManager(address _objectionManager) external onlyOwner {
        require(_objectionManager != address(0), "Invalid address");
        BridgeStakingManagerStorage storage $ = _getStorage();
        address oldManager = $.objectionManager;
        $.objectionManager = _objectionManager;
        emit ObjectionManagerUpdated(oldManager, _objectionManager);
    }

    function updateBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        BridgeStakingManagerStorage storage $ = _getStorage();
        $.bridge = IBridgeCore(_newBridge);
    }

    function updateTonToken(address _tonToken) external onlyOwner {
        require(_tonToken != address(0), "Invalid token address");
        BridgeStakingManagerStorage storage $ = _getStorage();
        $.tonToken = _tonToken;
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function hasMinimumStake(bytes32 channelId, address staker) external view returns (bool) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        StakeInfo storage stake = $.stakes[channelId][staker];
        return stake.isActive && stake.amount >= MINIMUM_STAKE;
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getStakeInfo(bytes32 channelId, address staker) external view returns (StakeInfo memory) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        return $.stakes[channelId][staker];
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getPendingRewards(address account) external view returns (uint256) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        return $.pendingRewards[account];
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getRewardPoolBalance() external view returns (uint256) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        return $.rewardPool;
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getTonToken() external view returns (address) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        return $.tonToken;
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getMinimumStake() external pure returns (uint256) {
        return MINIMUM_STAKE;
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getStakeLockPeriod() external pure returns (uint256) {
        return STAKE_LOCK_PERIOD;
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getUnstakeCooldown() external pure returns (uint256) {
        return UNSTAKE_COOLDOWN;
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getInvalidProofSlashPercentage() external pure returns (uint256) {
        return INVALID_PROOF_SLASH;
    }

    /**
     * @inheritdoc IBridgeStakingManager
     */
    function getFalseObjectionSlashPercentage() external pure returns (uint256) {
        return FALSE_OBJECTION_SLASH;
    }

    function getObjectionManager() external view returns (address) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        return $.objectionManager;
    }

    function getBridge() external view returns (address) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        return address($.bridge);
    }

    function getSlashRecordsCount() external view returns (uint256) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        return $.slashRecords.length;
    }

    function getSlashRecord(uint256 index) external view returns (SlashRecord memory) {
        BridgeStakingManagerStorage storage $ = _getStorage();
        require(index < $.slashRecords.length, "Index out of bounds");
        return $.slashRecords[index];
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _getStorage() internal pure returns (BridgeStakingManagerStorage storage $) {
        assembly {
            $.slot := BridgeStakingManagerStorageLocation
        }
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

    uint256[45] private __gap;
}
