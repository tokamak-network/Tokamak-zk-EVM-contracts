// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IRollupBridgeCore {
    enum ChannelState {
        None,
        Initialized,
        Open,
        Active,
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
    function getLeaderBond(uint256 channelId) external view returns (uint256 bond, bool slashed);
    function getTreasuryAddress() external view returns (address);
    function getTotalSlashedBonds() external view returns (uint256);

    // Setter functions (only callable by managers)
    function updateChannelTokenDeposits(uint256 channelId, address token, address participant, uint256 amount)
        external;
    function updateChannelTotalDeposits(uint256 channelId, address token, uint256 amount) external;
    function setChannelL2MptKey(uint256 channelId, address participant, address token, uint256 mptKey) external;
    function setChannelInitialStateRoot(uint256 channelId, bytes32 stateRoot) external;
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
    function slashLeaderBond(uint256 channelId, string memory reason) external;
    function enableEmergencyWithdrawals(uint256 channelId) external;
    function markUserWithdrawn(uint256 channelId, address participant) external;
    function clearWithdrawableAmount(uint256 channelId, address participant, address token) external;
    function reclaimLeaderBondInternal(uint256 channelId) external returns (uint256 bondAmount);
    function addSlashedBonds(uint256 amount) external;
}
