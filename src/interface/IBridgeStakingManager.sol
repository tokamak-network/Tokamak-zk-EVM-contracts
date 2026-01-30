// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title IBridgeStakingManager
 * @notice Interface for the staking manager that handles TON staking, slashing, and rewards
 * @dev Part of the Q2 2026 upgrade implementing the objection/slash/reward architecture
 */
interface IBridgeStakingManager {
    // ========== STRUCTS ==========

    struct StakeInfo {
        uint256 amount;           // Amount of TON staked
        uint256 lockedUntil;      // Timestamp until stake is locked
        uint256 pendingRewards;   // Accumulated rewards not yet claimed
        bool isActive;            // Whether the stake is active
    }

    struct SlashRecord {
        address staker;           // Address that was slashed
        uint256 amount;           // Amount slashed
        bytes32 reason;           // Reason for slashing
        uint256 timestamp;        // When the slash occurred
    }

    // ========== EVENTS ==========

    event Staked(bytes32 indexed channelId, address indexed staker, uint256 amount);
    event Unstaked(bytes32 indexed channelId, address indexed staker, uint256 amount);
    event UnstakeRequested(bytes32 indexed channelId, address indexed staker, uint256 cooldownEnds);
    event Slashed(bytes32 indexed channelId, address indexed staker, uint256 amount, bytes32 reason);
    event RewardDistributed(bytes32 indexed channelId, address indexed recipient, uint256 amount);
    event RewardsClaimed(address indexed claimer, uint256 amount);
    event StakingParametersUpdated(uint256 minStake, uint256 lockPeriod, uint256 cooldown);

    // ========== STAKING FUNCTIONS ==========

    /**
     * @notice Stake TON tokens for a specific channel
     * @param channelId The channel to stake for
     * @param amount Amount of TON to stake
     */
    function stakeForChannel(bytes32 channelId, uint256 amount) external;

    /**
     * @notice Request to unstake tokens (starts cooldown period)
     * @param channelId The channel to unstake from
     */
    function requestUnstake(bytes32 channelId) external;

    /**
     * @notice Complete unstaking after cooldown period
     * @param channelId The channel to complete unstake from
     */
    function unstake(bytes32 channelId) external;

    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external;

    // ========== SLASHING FUNCTIONS ==========

    /**
     * @notice Slash a staker for dishonest behavior
     * @dev Only callable by authorized managers (objection manager)
     * @param channelId The channel where violation occurred
     * @param staker Address of the staker to slash
     * @param percentage Percentage of stake to slash (0-100)
     * @param reason Reason identifier for the slash
     */
    function slash(bytes32 channelId, address staker, uint256 percentage, bytes32 reason) external;

    /**
     * @notice Distribute reward to an honest actor
     * @dev Only callable by authorized managers
     * @param channelId The channel where reward was earned
     * @param recipient Address to receive the reward
     * @param amount Amount to reward
     */
    function distributeReward(bytes32 channelId, address recipient, uint256 amount) external;

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Check if a staker has the minimum required stake for a channel
     * @param channelId The channel to check
     * @param staker The staker address to check
     * @return hasStake Whether the staker meets minimum stake requirements
     */
    function hasMinimumStake(bytes32 channelId, address staker) external view returns (bool hasStake);

    /**
     * @notice Get stake info for a staker in a channel
     * @param channelId The channel to query
     * @param staker The staker address
     * @return info The stake information
     */
    function getStakeInfo(bytes32 channelId, address staker) external view returns (StakeInfo memory info);

    /**
     * @notice Get pending rewards for an address
     * @param account The account to query
     * @return rewards Pending reward amount
     */
    function getPendingRewards(address account) external view returns (uint256 rewards);

    /**
     * @notice Get the total reward pool balance
     * @return balance Total rewards available for distribution
     */
    function getRewardPoolBalance() external view returns (uint256 balance);

    /**
     * @notice Get the TON token address used for staking
     * @return token The TON token contract address
     */
    function getTonToken() external view returns (address token);

    // ========== PARAMETER GETTERS ==========

    /**
     * @notice Get the minimum stake amount
     * @return amount Minimum TON required to stake
     */
    function getMinimumStake() external view returns (uint256 amount);

    /**
     * @notice Get the stake lock period
     * @return period Lock period in seconds
     */
    function getStakeLockPeriod() external view returns (uint256 period);

    /**
     * @notice Get the unstake cooldown period
     * @return period Cooldown period in seconds
     */
    function getUnstakeCooldown() external view returns (uint256 period);

    /**
     * @notice Get the slash percentage for invalid proofs
     * @return percentage Slash percentage (0-100)
     */
    function getInvalidProofSlashPercentage() external view returns (uint256 percentage);

    /**
     * @notice Get the slash percentage for false objections
     * @return percentage Slash percentage (0-100)
     */
    function getFalseObjectionSlashPercentage() external view returns (uint256 percentage);
}
