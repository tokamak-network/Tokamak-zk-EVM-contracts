// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IBridgeCore {
    enum ChannelState {
        None,
        Initialized,
        Open,
        Closing
    }

    struct PreAllocatedLeaf {
        uint256 value;
        bytes32 key;
        bool isActive;
    }

    struct UserStorageSlot {
        uint8 slotOffset;
        bytes32 getterFunctionSignature;
        bool isLoadedOnChain;
    }

    struct RegisteredFunction {
        bytes32 functionSignature;
        bytes32 instancesHash;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    struct TargetContract {
        PreAllocatedLeaf[] preAllocatedLeaves;
        RegisteredFunction[] registeredFunctions;
        UserStorageSlot[] userStorageSlots;
    }

    struct ChannelParams {
        bytes32 channelId;
        address targetContract;
        address[] whitelisted;
        bool enableFrostSignature;
    }

    function depositManager() external view returns (address);
    function withdrawManager() external view returns (address);
    function nTokamakPublicInputs() external view returns (uint16);
    function nMerkleTreeLevels() external view returns (uint8);

    function openChannel(ChannelParams calldata params) external returns (bytes32 channelId);
    function generateChannelId(address leader, bytes32 salt) external pure returns (bytes32 channelId);

    function updateManagerAddresses(
        address _depositManager,
        address _proofManager,
        address _withdrawManager,
        address _adminManager
    ) external;

    function getChannelState(bytes32 channelId) external view returns (ChannelState);
    function getChannelTargetContract(bytes32 channelId) external view returns (address);
    function getChannelLeader(bytes32 channelId) external view returns (address);
    function getChannelParticipants(bytes32 channelId) external view returns (address[] memory);
    function getChannelUsers(bytes32 channelId) external view returns (address[] memory);
    function isChannelWhitelisted(bytes32 channelId, address addr) external view returns (bool);
    function getChannelTreeSize(bytes32 channelId) external view returns (uint256);
    function getChannelMerkleTreeLevels(bytes32 channelId) external view returns (uint8);
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
    function getValidatedUserTargetContract(bytes32 channelId, address participant) external view returns (address);
    function hasUserWithdrawn(bytes32 channelId, address participant, address targetContract)
        external
        view
        returns (bool);
    function getBalanceSlotIndex(address targetContract) external view returns (uint8);
    function getBalanceSlotOffset(address targetContract) external view returns (uint8);
    function isSignatureVerified(bytes32 channelId) external view returns (bool);
    function getChannelBlockInfosHash(bytes32 channelId) external view returns (bytes32);
    function isFrostSignatureEnabled(bytes32 channelId) external view returns (bool);
    function isChannelTimedOut(bytes32 channelId) external view returns (bool);

    function getFcnStorages(bytes32 functionSignature) external view returns (address[] memory);
    function getPreAllocKeys(address storageAddr) external view returns (bytes32[] memory);
    function getUserSlots(address storageAddr) external view returns (uint8[] memory);
    function getFcnCfg(bytes32 functionSignature) external view returns (bytes32 instancesHash, bytes32 preprocessHash);

    function getAppFcnStorages(bytes32 channelId, bytes32 functionSignature) external view returns (address[] memory);
    function getAppPreAllocKeys(bytes32 channelId, address appStorageAddr) external view returns (bytes32[] memory);
    function getAppUserSlots(bytes32 channelId, address appStorageAddr) external view returns (uint8[] memory);
    function getAppFcnCfg(bytes32 channelId, bytes32 functionSignature)
        external
        view
        returns (bytes32 instancesHash, bytes32 preprocessHash);
    function getAppUserStorageKey(bytes32 channelId, address user, address appStorageAddr)
        external
        view
        returns (uint256);
    function getAppValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 appUserStorageKey)
        external
        view
        returns (uint256);
    function getAppPreAllocValue(bytes32 channelId, address appStorageAddr, bytes32 preAllocKey)
        external
        view
        returns (uint256);
    function getVerifiedStateRoot(bytes32 channelId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32);
    function getProposedStateRoot(bytes32 channelId, uint8 forkId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32);
    function getProposedStateFork(bytes32 channelId, uint8 forkId)
        external
        view
        returns (uint16[] memory stateIndices, bytes32[] memory roots);

    function getChannelFcnStorages(bytes32 channelId, bytes32 functionSignature)
        external
        view
        returns (address[] memory);
    function getChannelPreAllocKeys(bytes32 channelId, address appStorageAddr) external view returns (bytes32[] memory);
    function getChannelUserSlots(bytes32 channelId, address appStorageAddr) external view returns (uint8[] memory);
    function getChannelFcnCfg(bytes32 channelId, bytes32 functionSignature)
        external
        view
        returns (bytes32 instancesHash, bytes32 preprocessHash);
    function getChannelUserStorageKey(bytes32 channelId, address user, address appStorageAddr)
        external
        view
        returns (uint256);
    function getChannelValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 appUserStorageKey)
        external
        view
        returns (uint256);
    function getChannelPreAllocValue(bytes32 channelId, address appStorageAddr, bytes32 preAllocKey)
        external
        view
        returns (uint256);
    function getChannelVerifiedStateRoot(bytes32 channelId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32);
    function getChannelProposedStateRoot(bytes32 channelId, uint8 forkId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32);
    function getChannelProposedStateFork(bytes32 channelId, uint8 forkId)
        external
        view
        returns (uint16[] memory stateIndices, bytes32[] memory roots);

    function updateChannelUserDeposits(bytes32 channelId, address participant, uint8 slotIndex, uint256 amount) external;
    function setChannelL2MptKeys(bytes32 channelId, address participant, uint256[] calldata mptKeys) external;
    function setChannelUserStorageKey(bytes32 channelId, address participant, address appStorageAddr, uint256 key) external;
    function setChannelValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 storageKey, uint256 value)
        external;
    function increaseChannelValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 storageKey, uint256 amount)
        external;

    function setChannelInitialStateRoot(bytes32 channelId, bytes32 stateRoot) external;
    function setChannelFinalStateRoot(bytes32 channelId, bytes32 stateRoot) external;
    function updateSingleStateLeaf(
        bytes32 channelId,
        address appStorageAddr,
        uint256 userChannelStorageKey,
        uint256 updatedStorageValue,
        bytes32 updatedRoot,
        uint256[16] calldata proofGroth16,
        uint256[5] calldata publicInputGroth16
    ) external returns (bool);
    function verifyProposedStateRoots(
        bytes32 channelId,
        uint8 forkId,
        uint16 proposedStateIndex,
        address[] calldata appStorageAddrs,
        uint256[][] calldata storageKeys,
        uint256[][] calldata updatedStorageValues,
        bytes32[] calldata updatedRoots,
        uint256[42] calldata proofTokamak,
        uint256[4] calldata preprocessTokamak,
        uint256[] calldata publicInputTokamak
    ) external returns (bool);

    function setChannelState(bytes32 channelId, ChannelState state) external;
    function setChannelCloseTimestamp(bytes32 channelId, uint256 timestamp) external;
    function setChannelValidatedUserStorage(
        bytes32 channelId,
        address[] memory participants,
        uint256[][] memory slotValues
    ) external;
    function setChannelSignatureVerified(bytes32 channelId, bool verified) external;
    function setChannelBlockInfosHash(bytes32 channelId, bytes32 blockInfosHash) external;
    function addParticipantOnDeposit(bytes32 channelId, address user) external;
    function cleanupChannel(bytes32 channelId) external;

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

    function setPreAllocatedLeaf(address targetContract, bytes32 mptKey, uint256 value) external;
    function removePreAllocatedLeaf(address targetContract, bytes32 mptKey) external;
    function getPreAllocatedLeaf(address targetContract, bytes32 mptKey)
        external
        view
        returns (uint256 value, bool exists);
    function getPreAllocatedKeys(address targetContract) external view returns (bytes32[] memory keys);
    function getPreAllocatedLeavesCount(address targetContract) external view returns (uint256 count);
    function getChannelPreAllocatedLeavesCount(bytes32 channelId) external view returns (uint256 count);

    function setChannelPublicKey(bytes32 channelId, uint256 pkx, uint256 pky) external;
    function getImplementation() external view returns (address implementation);
}
