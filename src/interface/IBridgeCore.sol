// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IBridgeCore {
    enum ChannelState {
        None,
        Initialized,
        Open,
        Closing,
        Closed
    }

    struct TargetContract {
        address contractAddress;
        bytes1 storageSlot;
    }

    struct RegisteredFunction {
        bytes32 functionSignature;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    // View functions
    function getChannelState(uint256 channelId) external view returns (ChannelState);
    function isChannelParticipant(uint256 channelId, address participant) external view returns (bool);
    function isTokenAllowedInChannel(uint256 channelId, address token) external view returns (bool);
    function getChannelLeader(uint256 channelId) external view returns (address);
    function getChannelParticipants(uint256 channelId) external view returns (address[] memory);
    function getChannelAllowedTokens(uint256 channelId) external view returns (address[] memory);
    function getChannelTreeSize(uint256 channelId) external view returns (uint256);
    function getParticipantTokenDeposit(uint256 channelId, address participant, address token)
        external
        view
        returns (uint256);
    function getL2MptKey(uint256 channelId, address participant, address token) external view returns (uint256);
    function getChannelTotalDeposits(uint256 channelId, address token) external view returns (uint256);
    function getChannelPublicKey(uint256 channelId) external view returns (uint256 pkx, uint256 pky);
    function getChannelSignerAddr(uint256 channelId) external view returns (address);
    function getChannelFinalStateRoot(uint256 channelId) external view returns (bytes32);
    function getChannelInitialStateRoot(uint256 channelId) external view returns (bytes32);
    function getRegisteredFunction(bytes32 functionSignature) external view returns (RegisteredFunction memory);
    function isAllowedTargetContract(address targetContract) external view returns (bool);
    function getTargetContractData(address targetContract) external view returns (TargetContract memory);
    function getChannelTimeout(uint256 channelId) external view returns (uint256 openTimestamp, uint256 timeout);
    function getWithdrawableAmount(uint256 channelId, address participant, address token)
        external
        view
        returns (uint256);
    function hasUserWithdrawn(uint256 channelId, address participant) external view returns (bool);
    function isSignatureVerified(uint256 channelId) external view returns (bool);
    function getTreasuryAddress() external view returns (address);

    // Setter functions (only callable by managers)
    function updateChannelTokenDeposits(uint256 channelId, address token, address participant, uint256 amount)
        external;
    function updateChannelTotalDeposits(uint256 channelId, address token, uint256 amount) external;
    function setChannelL2MptKey(uint256 channelId, address participant, address token, uint256 mptKey) external;
    function setChannelInitialStateRoot(uint256 channelId, bytes32 stateRoot) external;
    function setChannelFinalStateRoot(uint256 channelId, bytes32 stateRoot) external;
    function setChannelState(uint256 channelId, ChannelState state) external;
    function setChannelCloseTimestamp(uint256 channelId, uint256 timestamp) external;
    function setChannelWithdrawAmounts(
        uint256 channelId,
        address[] memory participants,
        address[] memory tokens,
        uint256[][] memory amounts
    ) external;
    function setChannelSignatureVerified(uint256 channelId, bool verified) external;
    function setAllowedTargetContract(address targetContract, bytes1 storageSlot, bool allowed) external;
    function registerFunction(
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2
    ) external;
    function unregisterFunction(bytes32 functionSignature) external;
    function setTreasuryAddress(address treasury) external;
    function enableEmergencyWithdrawals(uint256 channelId) external;
    function markUserWithdrawn(uint256 channelId, address participant) external;
    function clearWithdrawableAmount(uint256 channelId, address participant, address token) external;

    // === DASHBOARD FUNCTIONS ===
    function getTotalChannels() external view returns (uint256);
    function getChannelStats()
        external
        view
        returns (uint256 openChannels, uint256 activeChannels, uint256 closingChannels, uint256 closedChannels);
    function getUserTotalBalance(address user)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances);
    function batchGetChannelStates(uint256[] calldata channelIds)
        external
        view
        returns (ChannelState[] memory states);

    // === MEDIUM PRIORITY UX FUNCTIONS ===
    function getUserAnalytics(address user)
        external
        view
        returns (
            uint256 totalChannelsJoined,
            uint256 activeChannelsCount,
            uint256 totalTokenTypes,
            uint256 channelsAsLeader
        );
    function getChannelHistory(address user)
        external
        view
        returns (
            uint256[] memory channelIds,
            ChannelState[] memory states,
            uint256[] memory joinTimestamps,
            bool[] memory isLeaderFlags
        );
    function canUserDeposit(address user, uint256 channelId, address token, uint256 amount)
        external
        view
        returns (bool canDeposit, string memory reason);
    function canUserWithdraw(address user, uint256 channelId)
        external
        view
        returns (bool canWithdraw, string memory reason);

    // === LOW PRIORITY ADVANCED FUNCTIONS ===
    function getSystemAnalytics()
        external
        view
        returns (
            uint256 totalChannelsCreated,
            uint256 totalValueLocked,
            uint256 totalUniqueUsers,
            uint256 averageChannelSize
        );
    function getChannelLiveMetrics(uint256 channelId)
        external
        view
        returns (
            uint256 activeParticipants,
            uint256 totalDeposits,
            uint256 averageDepositSize,
            uint256 timeActive,
            uint256 lastActivityTime
        );
    function searchChannelsByParticipant(address participant, ChannelState state, uint256 limit, uint256 offset)
        external
        view
        returns (uint256[] memory channelIds, uint256 totalMatches);
    function searchChannelsByToken(address token, uint256 minTotalDeposits, uint256 limit, uint256 offset)
        external
        view
        returns (uint256[] memory channelIds, uint256[] memory totalDeposits, uint256 totalMatches);
}
