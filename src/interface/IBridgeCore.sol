// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IBridgeCore {
    enum ChannelState {
        None,           // 0 - Channel doesn't exist
        Initialized,    // 1 - Awaiting deposits
        Open,           // 2 - Active, accepting proofs
        Disputing,      // 3 - Objection raised, awaiting resolution
        Closing         // 4 - Awaiting finalization
    }

    struct ConfirmedState {
        bytes32 stateRoot;      // The confirmed state root m_i
        uint256 confirmedAt;    // Timestamp when confirmed
        uint256 proofIndex;     // Last proof index included in this state
        uint256 blockNumber;    // Block number when confirmed
    }

    struct PreAllocatedLeaf {
        uint256 value;
        bytes32 key;
        bool isActive;
    }

    struct UserStorageSlot {
        uint8 slotOffset;
        bytes32 getterFunctionSignature;
        bool isLoadedOnChain; // false = value from deposits (balance), true = fetch via staticcall
    }

    struct TargetContract {
        PreAllocatedLeaf[] preAllocatedLeaves;
        RegisteredFunction[] registeredFunctions;
        UserStorageSlot[] userStorageSlots;
    }

    struct RegisteredFunction {
        bytes32 functionSignature;
        bytes32 instancesHash;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    // View functions - Manager addresses
    function depositManager() external view returns (address);
    function withdrawManager() external view returns (address);
    function stakingManager() external view returns (address);
    function objectionManager() external view returns (address);
    function getChannelState(bytes32 channelId) external view returns (ChannelState);
    function getChannelTargetContract(bytes32 channelId) external view returns (address);
    function getChannelLeader(bytes32 channelId) external view returns (address);
    function getChannelParticipants(bytes32 channelId) external view returns (address[] memory);
    function isChannelWhitelisted(bytes32 channelId, address addr) external view returns (bool);
    function getChannelTreeSize(bytes32 channelId) external view returns (uint256);
    function getL2MptKey(bytes32 channelId, address participant, uint8 slotIndex) external view returns (uint256);
    function getChannelPublicKey(bytes32 channelId) external view returns (uint256 pkx, uint256 pky);
    function isChannelPublicKeySet(bytes32 channelId) external view returns (bool);
    function getChannelSignerAddr(bytes32 channelId) external view returns (address);
    function getChannelFinalStateRoot(bytes32 channelId) external view returns (bytes32);
    function getChannelInitialStateRoot(bytes32 channelId) external view returns (bytes32);
    function isAllowedTargetContract(address targetContract) external view returns (bool);
    function getTargetContractData(address targetContract) external view returns (TargetContract memory);
    function getChannelInfo(bytes32 channelId)
        external
        view
        returns (address targetContract, ChannelState state, uint256 participantCount, bytes32 initialRoot);
    function getValidatedUserSlotValue(bytes32 channelId, address participant, uint8 slotIndex)
        external
        view
        returns (uint256);
    function getValidatedUserTargetContract(bytes32 channelId, address participant)
        external
        view
        returns (address);
    function hasUserWithdrawn(bytes32 channelId, address participant, address targetContract)
        external
        view
        returns (bool);
    function getBalanceSlotIndex(address targetContract) external view returns (uint8);
    function isSignatureVerified(bytes32 channelId) external view returns (bool);
    function getChannelBlockInfosHash(bytes32 channelId) external view returns (bytes32);
    function isFrostSignatureEnabled(bytes32 channelId) external view returns (bool);
    function isChannelTimedOut(bytes32 channelId) external view returns (bool);

    // Setter functions (only callable by managers)
    function updateChannelUserDeposits(bytes32 channelId, address participant, uint8 slotIndex, uint256 amount)
        external;
    function setChannelL2MptKeys(bytes32 channelId, address participant, uint256[] calldata mptKeys) external;
    function setChannelInitialStateRoot(bytes32 channelId, bytes32 stateRoot) external;
    function setChannelFinalStateRoot(bytes32 channelId, bytes32 stateRoot) external;
    function setChannelState(bytes32 channelId, ChannelState state) external;
    function setChannelCloseTimestamp(bytes32 channelId, uint256 timestamp) external;
    function setChannelValidatedUserStorage(bytes32 channelId, address[] memory participants, uint256[][] memory slotValues)
        external;
    function setChannelSignatureVerified(bytes32 channelId, bool verified) external;
    function setAllowedTargetContract(
        address targetContract,
        PreAllocatedLeaf[] memory leaves,
        UserStorageSlot[] memory userStorageSlots,
        bool allowed
    ) external;
    function registerFunction(
        address targetContract,
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bytes32 instancesHash
    ) external;
    function unregisterFunction(address targetContract, bytes32 functionSignature) external;
    function clearValidatedUserStorage(bytes32 channelId, address participant, address targetContract) external;
    function setChannelBlockInfosHash(bytes32 channelId, bytes32 blockInfosHash) external;
    function addParticipantOnDeposit(bytes32 channelId, address user) external;
    function cleanupChannel(bytes32 channelId) external;

    // === PRE-ALLOCATED LEAVES FUNCTIONS ===
    function setPreAllocatedLeaf(address targetContract, bytes32 mptKey, uint256 value) external;
    function removePreAllocatedLeaf(address targetContract, bytes32 mptKey) external;
    function getPreAllocatedLeaf(address targetContract, bytes32 mptKey)
        external
        view
        returns (uint256 value, bool exists);
    function getPreAllocatedKeys(address targetContract) external view returns (bytes32[] memory keys);
    function getPreAllocatedLeavesCount(address targetContract) external view returns (uint256 count);
    function getChannelPreAllocatedLeavesCount(bytes32 channelId) external view returns (uint256 count);

    function generateChannelId(address leader, bytes32 salt) external pure returns (bytes32 channelId);

    // === CONFIRMED STATE FUNCTIONS ===
    function addConfirmedState(bytes32 channelId, bytes32 stateRoot, uint256 proofIndex) external;
    function getLatestConfirmedState(bytes32 channelId) external view returns (bytes32 stateRoot, uint256 proofIndex);
    function getConfirmedStates(bytes32 channelId) external view returns (ConfirmedState[] memory);
    function getConfirmedStateCount(bytes32 channelId) external view returns (uint256);
    function getConfirmedStateAt(bytes32 channelId, uint256 index) external view returns (ConfirmedState memory);
}
