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
    function getChannelState(bytes32 channelId) external view returns (ChannelState);
    function isChannelParticipant(bytes32 channelId, address participant) external view returns (bool);
    function getChannelTargetContract(bytes32 channelId) external view returns (address);
    function getChannelLeader(bytes32 channelId) external view returns (address);
    function getChannelParticipants(bytes32 channelId) external view returns (address[] memory);
    // function getChannelWhitelisted(bytes32 channelId) external view returns (address[] memory);
    function isChannelWhitelisted(bytes32 channelId, address addr) external view returns (bool);
    function getChannelTreeSize(bytes32 channelId) external view returns (uint256);
    function getParticipantDeposit(bytes32 channelId, address participant) external view returns (uint256);
    function getL2MptKey(bytes32 channelId, address participant) external view returns (uint256);
    function getChannelTotalDeposits(bytes32 channelId) external view returns (uint256);
    function getChannelPublicKey(bytes32 channelId) external view returns (uint256 pkx, uint256 pky);
    function isChannelPublicKeySet(bytes32 channelId) external view returns (bool);
    function getChannelSignerAddr(bytes32 channelId) external view returns (address);
    function getChannelFinalStateRoot(bytes32 channelId) external view returns (bytes32);
    function getChannelInitialStateRoot(bytes32 channelId) external view returns (bytes32);
    function isAllowedTargetContract(address targetContract) external view returns (bool);
    function getTargetContractData(address targetContract) external view returns (TargetContract memory);
    function getChannelInfo(bytes32 channelId) external view returns (address targetContract, ChannelState state, uint256 participantCount, bytes32 initialRoot);
    function getWithdrawableAmount(bytes32 channelId, address participant) external view returns (uint256);
    function hasUserWithdrawn(bytes32 channelId, address participant) external view returns (bool);
    function isSignatureVerified(bytes32 channelId) external view returns (bool);
    function getChannelBlockInfosHash(bytes32 channelId) external view returns (bytes32);
    function isFrostSignatureEnabled(bytes32 channelId) external view returns (bool);

    // Setter functions (only callable by managers)
    function updateChannelUserDeposits(bytes32 channelId, address participant, uint256 amount) external;
    function updateChannelTotalDeposits(bytes32 channelId, uint256 amount) external;
    function setChannelL2MptKey(bytes32 channelId, address participant, uint256 mptKey) external;
    function setChannelInitialStateRoot(bytes32 channelId, bytes32 stateRoot) external;
    function setChannelFinalStateRoot(bytes32 channelId, bytes32 stateRoot) external;
    function setChannelState(bytes32 channelId, ChannelState state) external;
    function setChannelCloseTimestamp(bytes32 channelId, uint256 timestamp) external;
    function setChannelWithdrawAmounts(bytes32 channelId, address[] memory participants, uint256[] memory amounts)
        external;
    function setChannelSignatureVerified(bytes32 channelId, bool verified) external;
    function setAllowedTargetContract(address targetContract, PreAllocatedLeaf[] memory storageSlots, bool allowed)
        external;
    function registerFunction(
        address targetContract,
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bytes32 instancesHash
    ) external;
    function cleanupClosedChannel(bytes32 channelId) external;
    function unregisterFunction(address targetContract, bytes32 functionSignature) external;
    function clearWithdrawableAmount(bytes32 channelId, address participant) external;
    function batchCleanupClosedChannels(bytes32[] calldata channelIds) external;
    function setChannelBlockInfosHash(bytes32 channelId, bytes32 blockInfosHash) external;
    function addParticipantOnDeposit(bytes32 channelId, address user) external;

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
    function getChannelPreAllocatedLeavesCount(bytes32 channelId) external view returns (uint256 count);

    function generateChannelId(address leader, bytes32 salt) external pure returns (bytes32 channelId);
}
