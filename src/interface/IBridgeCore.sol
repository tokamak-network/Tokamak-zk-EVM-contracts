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

    struct PreAllocatedLeaf {
        uint256 value;
        bytes32 key;
        bool isActive;
    }

    struct TargetContract {
        // contractAddress removed - redundant with mapping key
        PreAllocatedLeaf[] storageSlot;
        RegisteredFunction[] registeredFunctions;
    }

    struct RegisteredFunction {
        bytes32 functionSignature;
        bytes32 instancesHash;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    // View functions
    function depositManager() external view returns (address);
    function withdrawManager() external view returns (address);
    function getChannelState(uint256 channelId) external view returns (ChannelState);
    function isChannelParticipant(uint256 channelId, address participant) external view returns (bool);
    function getChannelTargetContract(uint256 channelId) external view returns (address);
    function getChannelLeader(uint256 channelId) external view returns (address);
    function getChannelParticipants(uint256 channelId) external view returns (address[] memory);
    // function getChannelWhitelisted(uint256 channelId) external view returns (address[] memory);
    function isChannelWhitelisted(uint256 channelId, address addr) external view returns (bool);
    function getChannelTreeSize(uint256 channelId) external view returns (uint256);
    function getParticipantDeposit(uint256 channelId, address participant) external view returns (uint256);
    function getL2MptKey(uint256 channelId, address participant) external view returns (uint256);
    function getChannelTotalDeposits(uint256 channelId) external view returns (uint256);
    function getChannelPublicKey(uint256 channelId) external view returns (uint256 pkx, uint256 pky);
    function isChannelPublicKeySet(uint256 channelId) external view returns (bool);
    function getChannelSignerAddr(uint256 channelId) external view returns (address);
    function getChannelFinalStateRoot(uint256 channelId) external view returns (bytes32);
    function getChannelInitialStateRoot(uint256 channelId) external view returns (bytes32);
    function isAllowedTargetContract(address targetContract) external view returns (bool);
    function getTargetContractData(address targetContract) external view returns (TargetContract memory);
    function getChannelInfo(uint256 channelId) external view returns (address targetContract, ChannelState state, uint256 participantCount, bytes32 initialRoot);
    function getWithdrawableAmount(uint256 channelId, address participant) external view returns (uint256);
    function hasUserWithdrawn(uint256 channelId, address participant) external view returns (bool);
    function isSignatureVerified(uint256 channelId) external view returns (bool);
    function getChannelBlockInfosHash(uint256 channelId) external view returns (bytes32);
    function isFrostSignatureEnabled(uint256 channelId) external view returns (bool);

    // Setter functions (only callable by managers)
    function updateChannelUserDeposits(uint256 channelId, address participant, uint256 amount) external;
    function updateChannelTotalDeposits(uint256 channelId, uint256 amount) external;
    function setChannelL2MptKey(uint256 channelId, address participant, uint256 mptKey) external;
    function setChannelInitialStateRoot(uint256 channelId, bytes32 stateRoot) external;
    function setChannelFinalStateRoot(uint256 channelId, bytes32 stateRoot) external;
    function setChannelState(uint256 channelId, ChannelState state) external;
    function setChannelCloseTimestamp(uint256 channelId, uint256 timestamp) external;
    function setChannelWithdrawAmounts(uint256 channelId, address[] memory participants, uint256[] memory amounts)
        external;
    function setChannelSignatureVerified(uint256 channelId, bool verified) external;
    function setAllowedTargetContract(address targetContract, PreAllocatedLeaf[] memory storageSlots, bool allowed)
        external;
    function registerFunction(
        address targetContract,
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bytes32 instancesHash
    ) external;
    function cleanupClosedChannel(uint256 channelId) external;
    function unregisterFunction(address targetContract, bytes32 functionSignature) external;
    function clearWithdrawableAmount(uint256 channelId, address participant) external;
    function batchCleanupClosedChannels(uint256[] calldata channelIds) external;
    function setChannelBlockInfosHash(uint256 channelId, bytes32 blockInfosHash) external;
    function addParticipantOnDeposit(uint256 channelId, address user) external;

    // === PRE-ALLOCATED LEAVES FUNCTIONS ===
    function setPreAllocatedLeaf(address targetContract, bytes32 mptKey, uint256 value) external;
    function removePreAllocatedLeaf(address targetContract, bytes32 mptKey) external;
    function getPreAllocatedLeaf(address targetContract, bytes32 mptKey)
        external
        view
        returns (uint256 value, bool exists);
    function getPreAllocatedKeys(address targetContract) external view returns (bytes32[] memory keys);
    function getPreAllocatedLeavesCount(address targetContract) external view returns (uint256 count);
    function getMaxAllowedParticipants(address targetContract) external view returns (uint256 maxParticipants);
    function getChannelPreAllocatedLeavesCount(uint256 channelId) external view returns (uint256 count);

    function getTotalChannels() external view returns (uint256);
}
