// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract BridgeCore is ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using ECDSAUpgradeable for bytes32;

    enum ChannelState {
        None,
        Initialized,
        Open,
        Closing
    }

    struct ChannelParams {
        bytes32 channelId;
        address targetContract;
        address[] whitelisted;
        bool enableFrostSignature;
    }

    struct TargetContract {
        PreAllocatedLeaf[] preAllocatedLeaves;
        RegisteredFunction[] registeredFunctions;
        UserStorageSlot[] userStorageSlots;
    }

    struct UserStorageSlot {
        uint8 slotOffset;
        bytes32 getterFunctionSignature;
        bool isLoadedOnChain; // false = value from deposits (balance), true = fetch via staticcall
    }

    struct ValidatedUserStorage {
        address targetContract;
        mapping(uint8 => uint256) value; // Usage: value[SLOT_NUMBER]
        bool isLocked;
    }

    struct PreAllocatedLeaf {
        uint256 value;
        bytes32 key;
        bool isActive;
    }

    struct RegisteredFunction {
        bytes32 functionSignature;
        bytes32 instancesHash;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    struct Channel {
        // Slot 0
        bytes32 id;
        // Slot 1-2: pack addresses and small values (20 + 20 + 1 + 1 + 1 + 1 = 44 bytes)
        address targetContract; // 20 bytes
        address leader; // 20 bytes
        ChannelState state; // 1 byte
        bool sigVerified; // 1 byte
        bool frostSignatureEnabled; // 1 byte

        // Slot 3: signer and counts (20 + 8 + 4 bytes = 32 bytes)
        address signerAddr; // 20 bytes
        uint64 requiredTreeSize; // 8 bytes (enough for tree size)
        uint32 preAllocatedLeavesCount; // 4 bytes (max 4.2B leaves)
        // Slot 4-5: timestamps (each 128 bits is enough until year 10^38)
        uint128 openTimestamp; // 16 bytes
        uint128 closeTimestamp; // 16 bytes
        uint128 _reserved; // 16 bytes for future use
        // Slots 6-7: state roots
        bytes32 initialStateRoot;
        bytes32 finalStateRoot;
        // Slot 8: block info
        bytes32 blockInfosHash;
        // Slots 9-10: public key
        uint256 pkx;
        uint256 pky;
        // Dynamic storage (mappings and arrays)
        mapping(address => bool) isWhiteListed;
        address[] participants;
        mapping(address => mapping(uint8 => uint256)) l2MptKey; // l2MptKey[participant][slotIndex]
    }

    uint256 public constant MIN_PARTICIPANTS = 1;
    uint256 public constant MAX_PARTICIPANTS = 128;
    uint256 public constant CHANNEL_TIMEOUT = 7 days;
    uint16 public constant nTokamakPublicInputs = 64;
    uint8 public constant nMerkleTreeLevels = 7;
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    /// @custom:storage-location erc7201:tokamak.storage.BridgeCore
    struct BridgeCoreStorage {
        mapping(bytes32 => Channel) channels;
        mapping(address => TargetContract) allowedTargetContracts;
        address depositManager;
        address proofManager;
        address withdrawManager;
        address adminManager;
        mapping(address => mapping(bytes32 => PreAllocatedLeaf)) preAllocatedLeaves;
        mapping(address => bytes32[]) targetContractPreAllocatedKeys;
        // Usage: validatedUserStorage[USER_ADDRESS][CHANNEL_ID]
        mapping(address => mapping(bytes32 => ValidatedUserStorage[])) validatedUserStorage;
        // Spec-aligned manager relations
        mapping(bytes32 => address[]) functionStorages;
        mapping(bytes32 => mapping(address => bool)) functionStorageExists;
        mapping(bytes32 => bytes32) functionInstancesHash;
        mapping(bytes32 => bytes32) functionPreprocessHash;
        mapping(bytes32 => bool) functionCfgExists;
        // Spec-aligned channel/root relations
        mapping(bytes32 => mapping(uint16 => bytes32)) verifiedStateRoots;
        mapping(bytes32 => uint16[]) verifiedStateIndices;
        mapping(bytes32 => mapping(uint16 => bool)) verifiedStateIndexExists;
        mapping(bytes32 => mapping(uint8 => mapping(uint16 => bytes32))) proposedStateRoots;
        mapping(bytes32 => uint8[]) proposedForkIds;
        mapping(bytes32 => mapping(uint8 => bool)) proposedForkExists;
        mapping(bytes32 => mapping(uint8 => uint16[])) proposedStateIndices;
        mapping(bytes32 => mapping(uint8 => mapping(uint16 => bool))) proposedStateIndexExists;
    }

    bytes32 private constant BridgeCoreStorageLocation =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;

    event ChannelOpened(bytes32 indexed channelId, address targetContract);
    event ChannelPublicKeySet(bytes32 indexed channelId, uint256 pkx, uint256 pky, address signerAddr);
    event PreAllocatedLeafSet(address indexed targetContract, bytes32 indexed mptKey, uint256 value);
    event PreAllocatedLeafRemoved(address indexed targetContract, bytes32 indexed mptKey);
    event ChannelDeleted(bytes32 indexed channelId, uint256 cleanupTime);

    modifier onlyManager() {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require(
            msg.sender == $.depositManager || msg.sender == $.proofManager || msg.sender == $.withdrawManager
                || msg.sender == $.adminManager,
            "Only managers can call"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _depositManager,
        address _proofManager,
        address _withdrawManager,
        address _adminManager,
        address _owner
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        _transferOwnership(_owner);
        __UUPSUpgradeable_init();

        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.depositManager = _depositManager;
        $.proofManager = _proofManager;
        $.withdrawManager = _withdrawManager;
        $.adminManager = _adminManager;
    }

    // ========== EXTERNAL FUNCTIONS ==========

    function openChannel(ChannelParams calldata params) external returns (bytes32 channelId) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        require(params.channelId != bytes32(0), "Channel ID cannot be zero");
        require(params.targetContract != address(0), "Target contract cannot be zero address");
        require(_isTargetContractAllowed(params.targetContract), "Target contract not allowed");
        require($.channels[params.channelId].leader == address(0), "Channel ID already exists");

        channelId = params.channelId;

        // Get number of active pre-allocated leaves for this target contract
        uint256 preAllocatedCount = _getActivePreAllocatedCount(params.targetContract);
        uint256 numberOfUserStorageSlot = $.allowedTargetContracts[params.targetContract].userStorageSlots.length;

        // Calculate maximum allowed participants considering pre-allocated leaves and leader
        // Formula: (availableLeaves / slotsPerParticipant) - (1 * numberOfUserStorageSlot) for leader
        // Example: tree=16, preAlloc=4, slots=2 => ((16-4)/2)-1 = 5 whitelisted (6 total with leader)
        uint256 maxAllowedParticipants =
            ((MAX_PARTICIPANTS - preAllocatedCount) / numberOfUserStorageSlot) - (1 * numberOfUserStorageSlot);

        require(
            params.whitelisted.length >= MIN_PARTICIPANTS && params.whitelisted.length <= maxAllowedParticipants,
            "Invalid whitelisted count considering pre-allocated leaves"
        );

        // Include leader in tree size calculation (+1 for leader)
        uint256 requiredTreeSize = determineTreeSize(params.whitelisted.length + 1 + preAllocatedCount, 1);

        Channel storage channel = $.channels[channelId];

        channel.id = channelId;
        channel.targetContract = params.targetContract;
        channel.leader = msg.sender;
        channel.openTimestamp = uint128(block.timestamp);
        channel.state = ChannelState.Initialized;
        channel.requiredTreeSize = uint64(requiredTreeSize);
        channel.preAllocatedLeavesCount = uint32(preAllocatedCount);
        channel.frostSignatureEnabled = params.enableFrostSignature;

        // Automatically whitelist the channel leader
        channel.isWhiteListed[msg.sender] = true;

        uint256 whitelistedLength = params.whitelisted.length;
        for (uint256 i = 0; i < whitelistedLength;) {
            address whitelistedUser = params.whitelisted[i];

            channel.isWhiteListed[whitelistedUser] = true;
            unchecked {
                ++i;
            }
        }

        emit ChannelOpened(channelId, params.targetContract);
    }

    function setChannelPublicKey(bytes32 channelId, uint256 pkx, uint256 pky) external {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        require(channel.leader != address(0), "Channel does not exist");
        require(msg.sender == channel.leader, "Only channel leader can set public key");
        require(channel.frostSignatureEnabled, "frost is disabled");

        require(channel.state == ChannelState.Initialized, "Can only set public key for initialized channel");
        require(channel.pkx == 0 && channel.pky == 0, "Public key already set");

        channel.pkx = pkx;
        channel.pky = pky;
        address signerAddr = deriveAddressFromPubkey(pkx, pky);
        channel.signerAddr = signerAddr;

        emit ChannelPublicKeySet(channelId, pkx, pky, signerAddr);
    }

    // Manager setter functions
    function updateChannelUserDeposits(bytes32 channelId, address participant, uint8 slotIndex, uint256 amount)
        external
        onlyManager
    {
        require(amount < R_MOD, "Amount exceeds R_MOD");

        // Validate slotIndex has isLoadedOnChain == false (i.e., it's a balance slot)
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        address targetContract = $.channels[channelId].targetContract;
        require(slotIndex < $.allowedTargetContracts[targetContract].userStorageSlots.length, "Invalid slot index");
        require(
            !$.allowedTargetContracts[targetContract].userStorageSlots[slotIndex].isLoadedOnChain,
            "Slot must be off-chain"
        );

        ValidatedUserStorage storage entry = _getOrCreateValidatedUserStorage(participant, channelId);
        entry.value[slotIndex] += amount;
    }

    function setChannelL2MptKeys(bytes32 channelId, address participant, uint256[] calldata mptKeys)
        external
        onlyManager
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        // Get expected number of slots from userStorageSlots
        uint256 expectedSlots = $.allowedTargetContracts[channel.targetContract].userStorageSlots.length;
        require(mptKeys.length == expectedSlots, "MPT keys count mismatch");

        // Validate and store each mptKey by slot index
        bytes32[] storage preAllocKeys = $.targetContractPreAllocatedKeys[channel.targetContract];
        for (uint8 i = 0; i < mptKeys.length; i++) {
            require(mptKeys[i] < R_MOD, "MPT key exceeds R_MOD");
            for (uint256 preAllocIdx = 0; preAllocIdx < preAllocKeys.length; preAllocIdx++) {
                require(mptKeys[i] != uint256(preAllocKeys[preAllocIdx]), "MPT key collides with pre-alloc key");
            }
            for (uint256 participantIdx = 0; participantIdx < channel.participants.length; participantIdx++) {
                address existingParticipant = channel.participants[participantIdx];
                if (existingParticipant != participant && channel.l2MptKey[existingParticipant][i] == mptKeys[i]) {
                    revert("Duplicate MPT key");
                }
            }
            channel.l2MptKey[participant][i] = mptKeys[i];
        }
    }

    function setChannelInitialStateRoot(bytes32 channelId, bytes32 stateRoot) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].initialStateRoot = stateRoot;
        _upsertVerifiedStateRoot(channelId, 0, stateRoot);
        _upsertProposedStateRoot(channelId, 0, 0, stateRoot);
    }

    function setChannelFinalStateRoot(bytes32 channelId, bytes32 stateRoot) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].finalStateRoot = stateRoot;
        uint16 nextIndex = 0;
        if ($.verifiedStateIndices[channelId].length > 0) {
            nextIndex = $.verifiedStateIndices[channelId][$.verifiedStateIndices[channelId].length - 1] + 1;
        }
        _upsertVerifiedStateRoot(channelId, nextIndex, stateRoot);
        _upsertProposedStateRoot(channelId, 0, nextIndex, stateRoot);
    }

    function setChannelState(bytes32 channelId, ChannelState state) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].state = state;
    }

    function setChannelValidatedUserStorage(
        bytes32 channelId,
        address[] memory participants,
        uint256[][] memory slotValues
    ) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        address targetContract = $.channels[channelId].targetContract;
        uint256 numSlots = $.allowedTargetContracts[targetContract].userStorageSlots.length;

        for (uint256 participantIdx = 0; participantIdx < participants.length; participantIdx++) {
            address participant = participants[participantIdx];
            require(slotValues[participantIdx].length == numSlots, "Slot values count mismatch");

            ValidatedUserStorage storage entry = _getOrCreateValidatedUserStorage(participant, channelId);
            for (uint8 slotIdx = 0; slotIdx < numSlots; slotIdx++) {
                entry.value[slotIdx] = slotValues[participantIdx][slotIdx];
            }
            entry.isLocked = false;
        }
    }

    function setChannelSignatureVerified(bytes32 channelId, bool verified) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].sigVerified = verified;
    }

    function setAllowedTargetContract(
        address targetContract,
        PreAllocatedLeaf[] memory leaves,
        UserStorageSlot[] memory userStorageSlots,
        bool allowed
    ) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        if (allowed) {
            // Clear existing pre-allocated leaves from both storages
            bytes32[] storage existingKeys = $.targetContractPreAllocatedKeys[targetContract];
            for (uint256 i = 0; i < existingKeys.length; i++) {
                delete $.preAllocatedLeaves[targetContract][existingKeys[i]];
            }
            delete $.targetContractPreAllocatedKeys[targetContract];
            delete $.allowedTargetContracts[targetContract].preAllocatedLeaves;

            // Add new pre-allocated leaves to both storages
            for (uint256 i = 0; i < leaves.length; i++) {
                PreAllocatedLeaf memory leaf = leaves[i];
                $.allowedTargetContracts[targetContract].preAllocatedLeaves.push(leaf);

                // Also update the preAllocatedLeaves mapping and keys array if leaf is active
                if (leaf.isActive) {
                    $.preAllocatedLeaves[targetContract][leaf.key] = leaf;
                    $.targetContractPreAllocatedKeys[targetContract].push(leaf.key);
                }
            }

            // Clear existing user storage slots
            delete $.allowedTargetContracts[targetContract].userStorageSlots;

            // Add new user storage slots
            for (uint256 i = 0; i < userStorageSlots.length; i++) {
                $.allowedTargetContracts[targetContract].userStorageSlots.push(userStorageSlots[i]);
            }

            // If no pre-allocated leaves provided and no functions registered, add a dummy entry
            // to mark the contract as allowed
            if (leaves.length == 0 && $.allowedTargetContracts[targetContract].registeredFunctions.length == 0) {
                // Push a dummy inactive leaf to mark as allowed
                $.allowedTargetContracts[targetContract].preAllocatedLeaves
                    .push(PreAllocatedLeaf({value: 0, key: bytes32(0), isActive: false}));
            }
        } else {
            TargetContract storage target = $.allowedTargetContracts[targetContract];
            for (uint256 i = 0; i < target.registeredFunctions.length; i++) {
                _removeFunctionStorageRelation(target.registeredFunctions[i].functionSignature, targetContract);
            }

            // Clear pre-allocated leaves from mapping and keys array
            bytes32[] storage existingKeys = $.targetContractPreAllocatedKeys[targetContract];
            for (uint256 i = 0; i < existingKeys.length; i++) {
                delete $.preAllocatedLeaves[targetContract][existingKeys[i]];
            }
            delete $.targetContractPreAllocatedKeys[targetContract];
            delete $.allowedTargetContracts[targetContract];
        }
    }

    function registerFunction(
        address targetContract,
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bytes32 instancesHash
    ) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");
        require(functionSignature != bytes32(0), "Invalid function signature");

        bytes32 preprocessHash = _computePreprocessHash(preprocessedPart1, preprocessedPart2);
        if ($.functionCfgExists[functionSignature]) {
            require($.functionInstancesHash[functionSignature] == instancesHash, "Function instances hash conflict");
            require($.functionPreprocessHash[functionSignature] == preprocessHash, "Function preprocess hash conflict");
        } else {
            $.functionCfgExists[functionSignature] = true;
            $.functionInstancesHash[functionSignature] = instancesHash;
            $.functionPreprocessHash[functionSignature] = preprocessHash;
        }

        // Also add to target contract's registered functions
        TargetContract storage target = $.allowedTargetContracts[targetContract];

        // Check if function already exists for this target
        bool functionExists = false;
        for (uint256 i = 0; i < target.registeredFunctions.length; i++) {
            if (target.registeredFunctions[i].functionSignature == functionSignature) {
                // Update existing function
                target.registeredFunctions[i] = RegisteredFunction({
                    functionSignature: functionSignature,
                    instancesHash: instancesHash,
                    preprocessedPart1: preprocessedPart1,
                    preprocessedPart2: preprocessedPart2
                });
                functionExists = true;
                break;
            }
        }

        // If function doesn't exist, add it
        if (!functionExists) {
            target.registeredFunctions
                .push(
                    RegisteredFunction({
                        functionSignature: functionSignature,
                        instancesHash: instancesHash,
                        preprocessedPart1: preprocessedPart1,
                        preprocessedPart2: preprocessedPart2
                    })
                );
        }

        if (!$.functionStorageExists[functionSignature][targetContract]) {
            $.functionStorageExists[functionSignature][targetContract] = true;
            $.functionStorages[functionSignature].push(targetContract);
        }
    }

    function unregisterFunction(address targetContract, bytes32 functionSignature) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");

        // Remove from target contract's registered functions
        TargetContract storage target = $.allowedTargetContracts[targetContract];
        uint256 functionsLength = target.registeredFunctions.length;

        for (uint256 i = 0; i < functionsLength; i++) {
            if (target.registeredFunctions[i].functionSignature == functionSignature) {
                // Move the last element to this position and pop
                if (i != functionsLength - 1) {
                    target.registeredFunctions[i] = target.registeredFunctions[functionsLength - 1];
                }
                target.registeredFunctions.pop();
                _removeFunctionStorageRelation(functionSignature, targetContract);
                break;
            }
        }
    }

    function clearValidatedUserStorage(bytes32 channelId, address participant, address targetContract)
        external
        onlyManager
    {
        if (!_hasValidatedUserStorage(participant, channelId)) {
            return; // Nothing to clear
        }
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        uint256 numSlots = $.allowedTargetContracts[targetContract].userStorageSlots.length;

        ValidatedUserStorage storage entry = _getValidatedUserStorage(participant, channelId);
        for (uint8 slotIdx = 0; slotIdx < numSlots; slotIdx++) {
            entry.value[slotIdx] = 0;
        }
        entry.isLocked = false;
    }

    function setChannelCloseTimestamp(bytes32 channelId, uint256 timestamp) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].closeTimestamp = uint128(timestamp);
    }

    function setChannelBlockInfosHash(bytes32 channelId, bytes32 blockInfosHash) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].blockInfosHash = blockInfosHash;
    }

    function addParticipantOnDeposit(bytes32 channelId, address user) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        require(channel.isWhiteListed[user], "User not whitelisted");

        // Check if user is already in participants array
        for (uint256 i = 0; i < channel.participants.length; i++) {
            if (channel.participants[i] == user) {
                return; // User already in participants
            }
        }

        // Add user to participants array
        channel.participants.push(user);
    }

    function cleanupChannel(bytes32 channelId) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        require(channel.leader != address(0), "Channel does not exist");

        // Get participants and target contract before cleanup
        address[] memory participants = channel.participants;
        address targetContract = channel.targetContract;

        // Get number of user storage slots for this target contract (now includes balance)
        uint256 numSlots = $.allowedTargetContracts[targetContract].userStorageSlots.length;

        // Clean up mappings inside the channel struct
        // Note: Arrays are cleared by delete, but mappings must be manually cleared
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            delete channel.isWhiteListed[participant];
            // Clear each slot index in the nested mapping
            for (uint8 j = 0; j < numSlots; j++) {
                delete channel.l2MptKey[participant][j];
            }
        }

        _clearChannelStateRelations(channelId);

        // Now delete the channel struct
        delete $.channels[channelId];

        emit ChannelDeleted(channelId, block.timestamp);
    }

    // ========== PRE-ALLOCATED LEAVES MANAGEMENT ==========

    /**
     * @notice Set a pre-allocated leaf value for a target contract
     * @dev Only managers can call this function
     * @param targetContract The target contract address
     * @param key The MPT key for the pre-allocated leaf
     * @param value The value for the pre-allocated leaf
     */
    function setPreAllocatedLeaf(address targetContract, bytes32 key, uint256 value) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");

        PreAllocatedLeaf storage leaf = $.preAllocatedLeaves[targetContract][key];
        bool isNewLeaf = !leaf.isActive;

        // If this is a new pre-allocated leaf, add it to the keys array
        if (isNewLeaf) {
            $.targetContractPreAllocatedKeys[targetContract].push(key);
        }

        leaf.key = key;
        leaf.value = value;
        leaf.isActive = true;

        // Update the allowedTargetContracts preAllocatedLeaves array
        TargetContract storage targetContractData = $.allowedTargetContracts[targetContract];

        if (isNewLeaf) {
            // Add new leaf to preAllocatedLeaves array
            targetContractData.preAllocatedLeaves.push(PreAllocatedLeaf({key: key, value: value, isActive: true}));
        } else {
            // Update existing leaf in preAllocatedLeaves array
            for (uint256 i = 0; i < targetContractData.preAllocatedLeaves.length; i++) {
                if (targetContractData.preAllocatedLeaves[i].key == key) {
                    targetContractData.preAllocatedLeaves[i].value = value;
                    targetContractData.preAllocatedLeaves[i].isActive = true;
                    break;
                }
            }
        }

        emit PreAllocatedLeafSet(targetContract, key, value);
    }

    /**
     * @notice Remove a pre-allocated leaf for a target contract
     * @dev Only managers can call this function
     * @param targetContract The target contract address
     * @param key The MPT key to remove
     */
    function removePreAllocatedLeaf(address targetContract, bytes32 key) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        PreAllocatedLeaf storage leaf = $.preAllocatedLeaves[targetContract][key];
        require(leaf.isActive, "Pre-allocated leaf does not exist");

        // Remove from the keys array
        bytes32[] storage keys = $.targetContractPreAllocatedKeys[targetContract];
        for (uint256 i = 0; i < keys.length; i++) {
            if (keys[i] == key) {
                keys[i] = keys[keys.length - 1];
                keys.pop();
                break;
            }
        }

        // Remove from the allowedTargetContracts preAllocatedLeaves array
        TargetContract storage targetContractData = $.allowedTargetContracts[targetContract];
        for (uint256 i = 0; i < targetContractData.preAllocatedLeaves.length; i++) {
            if (targetContractData.preAllocatedLeaves[i].key == key) {
                // Move the last element to this position and pop
                if (i != targetContractData.preAllocatedLeaves.length - 1) {
                    targetContractData.preAllocatedLeaves[i] =
                        targetContractData.preAllocatedLeaves[targetContractData.preAllocatedLeaves.length - 1];
                }
                targetContractData.preAllocatedLeaves.pop();
                break;
            }
        }

        // Remove the leaf
        delete $.preAllocatedLeaves[targetContract][key];

        emit PreAllocatedLeafRemoved(targetContract, key);
    }

    /**
     * @notice Get a pre-allocated leaf value
     * @param targetContract The target contract address
     * @param key The MPT key
     * @return value The value of the pre-allocated leaf
     * @return exists Whether the leaf exists
     */
    function getPreAllocatedLeaf(address targetContract, bytes32 key)
        external
        view
        returns (uint256 value, bool exists)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        PreAllocatedLeaf storage leaf = $.preAllocatedLeaves[targetContract][key];
        return (leaf.value, leaf.isActive);
    }

    /**
     * @notice Get all pre-allocated leaves for a target contract
     * @param targetContract The target contract address
     * @return keys Array of pre-allocated keys
     */
    function getPreAllocatedKeys(address targetContract) external view returns (bytes32[] memory keys) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.targetContractPreAllocatedKeys[targetContract];
    }

    /**
     * @notice Get the number of pre-allocated leaves for a target contract
     * @param targetContract The target contract address
     * @return count Number of pre-allocated leaves
     */
    function getPreAllocatedLeavesCount(address targetContract) external view returns (uint256 count) {
        return _getActivePreAllocatedCount(targetContract);
    }

    /**
     * @notice Get the number of pre-allocated leaves for a specific channel
     * @param channelId The channel ID
     * @return count Number of pre-allocated leaves in the channel
     */
    function getChannelPreAllocatedLeavesCount(bytes32 channelId) external view returns (uint256 count) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].preAllocatedLeavesCount;
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _getBridgeCoreStorage() internal pure returns (BridgeCoreStorage storage $) {
        assembly {
            $.slot := BridgeCoreStorageLocation
        }
    }

    function _isTargetContractAllowed(address targetContract) internal view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        TargetContract storage target = $.allowedTargetContracts[targetContract];
        // A target contract is allowed if it has pre-allocated leaves or registered functions
        // (including dummy inactive entries used just to mark as allowed)
        return target.preAllocatedLeaves.length > 0 || target.registeredFunctions.length > 0;
    }

    function _getActivePreAllocatedCount(address targetContract) internal view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        uint256 count = 0;
        bytes32[] memory keys = $.targetContractPreAllocatedKeys[targetContract];
        for (uint256 i = 0; i < keys.length; i++) {
            if ($.preAllocatedLeaves[targetContract][keys[i]].isActive) {
                count++;
            }
        }
        return count;
    }

    /**
     * @dev Get or create ValidatedUserStorage entry for a channel
     * @param participant The user address
     * @param channelId The channel ID
     * @return storage pointer to the ValidatedUserStorage entry
     */
    function _getOrCreateValidatedUserStorage(address participant, bytes32 channelId)
        internal
        returns (ValidatedUserStorage storage)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        ValidatedUserStorage[] storage entries = $.validatedUserStorage[participant][channelId];

        // Return existing entry if exists
        if (entries.length > 0) {
            return entries[0];
        }

        // Create new entry with channel's targetContract
        address targetContract = $.channels[channelId].targetContract;
        entries.push();
        ValidatedUserStorage storage newEntry = entries[0];
        newEntry.targetContract = targetContract;
        return newEntry;
    }

    /**
     * @dev Get ValidatedUserStorage entry for a channel (read-only)
     * @param participant The user address
     * @param channelId The channel ID
     * @return storage pointer to the ValidatedUserStorage entry (reverts if not found)
     */
    function _getValidatedUserStorage(address participant, bytes32 channelId)
        internal
        view
        returns (ValidatedUserStorage storage)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        ValidatedUserStorage[] storage entries = $.validatedUserStorage[participant][channelId];

        require(entries.length > 0, "ValidatedUserStorage not found");
        return entries[0];
    }

    /**
     * @dev Check if ValidatedUserStorage entry exists for a channel
     */
    function _hasValidatedUserStorage(address participant, bytes32 channelId) internal view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.validatedUserStorage[participant][channelId].length > 0;
    }

    /**
     * @dev Get the balance slot index for a target contract (the one with isLoadedOnChain == false)
     */
    function _getBalanceSlotIndex(address targetContract) internal view returns (uint8) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        UserStorageSlot[] storage slots = $.allowedTargetContracts[targetContract].userStorageSlots;
        for (uint8 i = 0; i < slots.length; i++) {
            if (!slots[i].isLoadedOnChain) {
                return i;
            }
        }
        revert("No balance slot found");
    }

    function _getBalanceSlotOffset(address targetContract) internal view returns (uint8) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        UserStorageSlot[] storage slots = $.allowedTargetContracts[targetContract].userStorageSlots;
        for (uint8 i = 0; i < slots.length; i++) {
            if (!slots[i].isLoadedOnChain) {
                return slots[i].slotOffset;
            }
        }
        revert("No balance slot found");
    }

    function _computePreprocessHash(uint128[] memory preprocessedPart1, uint256[] memory preprocessedPart2)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(preprocessedPart1, preprocessedPart2));
    }

    function _removeFunctionStorageRelation(bytes32 functionSignature, address targetContract) internal {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        if (!$.functionStorageExists[functionSignature][targetContract]) {
            return;
        }

        $.functionStorageExists[functionSignature][targetContract] = false;
        address[] storage storages = $.functionStorages[functionSignature];

        for (uint256 i = 0; i < storages.length; i++) {
            if (storages[i] == targetContract) {
                storages[i] = storages[storages.length - 1];
                storages.pop();
                break;
            }
        }

        if (storages.length == 0) {
            delete $.functionCfgExists[functionSignature];
            delete $.functionInstancesHash[functionSignature];
            delete $.functionPreprocessHash[functionSignature];
        }
    }

    function _upsertVerifiedStateRoot(bytes32 channelId, uint16 stateIndex, bytes32 root) internal {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        if (!$.verifiedStateIndexExists[channelId][stateIndex]) {
            $.verifiedStateIndexExists[channelId][stateIndex] = true;
            $.verifiedStateIndices[channelId].push(stateIndex);
        }
        $.verifiedStateRoots[channelId][stateIndex] = root;
    }

    function _upsertProposedStateRoot(bytes32 channelId, uint8 forkId, uint16 stateIndex, bytes32 root) internal {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        if (!$.proposedForkExists[channelId][forkId]) {
            $.proposedForkExists[channelId][forkId] = true;
            $.proposedForkIds[channelId].push(forkId);
        }
        if (!$.proposedStateIndexExists[channelId][forkId][stateIndex]) {
            $.proposedStateIndexExists[channelId][forkId][stateIndex] = true;
            $.proposedStateIndices[channelId][forkId].push(stateIndex);
        }
        $.proposedStateRoots[channelId][forkId][stateIndex] = root;
    }

    function _clearChannelStateRelations(bytes32 channelId) internal {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        uint16[] storage verifiedIndices = $.verifiedStateIndices[channelId];
        for (uint256 i = 0; i < verifiedIndices.length; i++) {
            uint16 stateIndex = verifiedIndices[i];
            delete $.verifiedStateRoots[channelId][stateIndex];
            delete $.verifiedStateIndexExists[channelId][stateIndex];
        }
        delete $.verifiedStateIndices[channelId];

        uint8[] storage forkIds = $.proposedForkIds[channelId];
        for (uint256 i = 0; i < forkIds.length; i++) {
            uint8 forkId = forkIds[i];
            uint16[] storage stateIndices = $.proposedStateIndices[channelId][forkId];
            for (uint256 j = 0; j < stateIndices.length; j++) {
                uint16 stateIndex = stateIndices[j];
                delete $.proposedStateRoots[channelId][forkId][stateIndex];
                delete $.proposedStateIndexExists[channelId][forkId][stateIndex];
            }
            delete $.proposedStateIndices[channelId][forkId];
            delete $.proposedForkExists[channelId][forkId];
        }
        delete $.proposedForkIds[channelId];
    }

    function _isChannelParticipant(bytes32 channelId, address user) internal view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        address[] storage participants = $.channels[channelId].participants;
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == user) {
                return true;
            }
        }
        return false;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function deriveAddressFromPubkey(uint256 pkx, uint256 pky) internal pure returns (address) {
        bytes32 h = keccak256(abi.encodePacked(pkx, pky));
        return address(uint160(uint256(h)));
    }

    function determineTreeSize(uint256 participantCount, uint256 contractCount) internal pure returns (uint256) {
        uint256 totalLeaves = participantCount * contractCount;

        if (totalLeaves <= 16) {
            return 16;
        } else if (totalLeaves <= 32) {
            return 32;
        } else if (totalLeaves <= 64) {
            return 64;
        } else if (totalLeaves <= 128) {
            return 128;
        } else {
            revert("Too many participant-contract combinations");
        }
    }

    // ========== OWNER FUNCTIONS ==========

    function updateManagerAddresses(
        address _depositManager,
        address _proofManager,
        address _withdrawManager,
        address _adminManager
    ) external onlyOwner {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        if (_depositManager != address(0)) $.depositManager = _depositManager;
        if (_proofManager != address(0)) $.proofManager = _proofManager;
        if (_withdrawManager != address(0)) $.withdrawManager = _withdrawManager;
        if (_adminManager != address(0)) $.adminManager = _adminManager;
    }

    // ========== GETTER FUNCTIONS ==========

    function depositManager() external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.depositManager;
    }

    function withdrawManager() external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.withdrawManager;
    }

    function getChannelState(bytes32 channelId) external view returns (ChannelState) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].state;
    }

    function getChannelTargetContract(bytes32 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].targetContract;
    }

    function getChannelLeader(bytes32 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].leader;
    }

    function getChannelParticipants(bytes32 channelId) external view returns (address[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].participants;
    }

    function getChannelUsers(bytes32 channelId) external view returns (address[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].participants;
    }

    function isChannelWhitelisted(bytes32 channelId, address addr) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].isWhiteListed[addr];
    }

    function getChannelTreeSize(bytes32 channelId) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].requiredTreeSize;
    }

    function getChannelMerkleTreeLevels(bytes32 channelId) external view returns (uint8) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        uint64 treeSize = $.channels[channelId].requiredTreeSize;

        if (treeSize == 16) return 4;
        if (treeSize == 32) return 5;
        if (treeSize == 64) return 6;
        if (treeSize == 128) return 7;

        revert("Invalid tree size");
    }

    function getL2MptKey(bytes32 channelId, address participant, uint8 slotIndex) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].l2MptKey[participant][slotIndex];
    }

    function getChannelPublicKey(bytes32 channelId) external view returns (uint256 pkx, uint256 pky) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.pkx, channel.pky);
    }

    function isChannelPublicKeySet(bytes32 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return channel.pkx != 0 && channel.pky != 0;
    }

    function getChannelSignerAddr(bytes32 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].signerAddr;
    }

    function getChannelFinalStateRoot(bytes32 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].finalStateRoot;
    }

    function getChannelInitialStateRoot(bytes32 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].initialStateRoot;
    }

    function isAllowedTargetContract(address targetContract) external view returns (bool) {
        return _isTargetContractAllowed(targetContract);
    }

    function getTargetContractData(address targetContract) external view returns (TargetContract memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");
        return $.allowedTargetContracts[targetContract];
    }

    function getChannelInfo(bytes32 channelId)
        external
        view
        returns (address targetContract, ChannelState state, uint256 participantCount, bytes32 initialRoot)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.targetContract, channel.state, channel.participants.length, channel.initialStateRoot);
    }

    function getFcnStorages(bytes32 functionSignature) external view returns (address[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.functionStorages[functionSignature];
    }

    function getPreAllocKeys(address storageAddr) external view returns (bytes32[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.targetContractPreAllocatedKeys[storageAddr];
    }

    function getUserSlots(address storageAddr) external view returns (uint8[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        UserStorageSlot[] storage userStorageSlots = $.allowedTargetContracts[storageAddr].userStorageSlots;
        uint8[] memory slotOffsets = new uint8[](userStorageSlots.length);
        for (uint256 i = 0; i < userStorageSlots.length; i++) {
            slotOffsets[i] = userStorageSlots[i].slotOffset;
        }
        return slotOffsets;
    }

    function getFcnCfg(bytes32 functionSignature)
        external
        view
        returns (bytes32 instancesHash, bytes32 preprocessHash)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require($.functionCfgExists[functionSignature], "Function config not found");
        return ($.functionInstancesHash[functionSignature], $.functionPreprocessHash[functionSignature]);
    }

    function getAppFcnStorages(bytes32 channelId, bytes32 functionSignature) external view returns (address[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        address targetContract = $.channels[channelId].targetContract;
        if ($.functionStorageExists[functionSignature][targetContract]) {
            address[] memory appStorages = new address[](1);
            appStorages[0] = targetContract;
            return appStorages;
        }
        return new address[](0);
    }

    function getAppPreAllocKeys(bytes32 channelId, address appStorageAddr) external view returns (bytes32[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        if ($.channels[channelId].targetContract != appStorageAddr) {
            return new bytes32[](0);
        }
        return $.targetContractPreAllocatedKeys[appStorageAddr];
    }

    function getAppUserSlots(bytes32 channelId, address appStorageAddr) external view returns (uint8[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        if ($.channels[channelId].targetContract != appStorageAddr) {
            return new uint8[](0);
        }

        UserStorageSlot[] storage userStorageSlots = $.allowedTargetContracts[appStorageAddr].userStorageSlots;
        uint8[] memory slotOffsets = new uint8[](userStorageSlots.length);
        for (uint256 i = 0; i < userStorageSlots.length; i++) {
            slotOffsets[i] = userStorageSlots[i].slotOffset;
        }
        return slotOffsets;
    }

    function getAppFcnCfg(bytes32 channelId, bytes32 functionSignature)
        external
        view
        returns (bytes32 instancesHash, bytes32 preprocessHash)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        address targetContract = $.channels[channelId].targetContract;
        require($.functionStorageExists[functionSignature][targetContract], "Function not in channel");
        require($.functionCfgExists[functionSignature], "Function config not found");
        return ($.functionInstancesHash[functionSignature], $.functionPreprocessHash[functionSignature]);
    }

    function getAppUserStorageKey(bytes32 channelId, address user, address appStorageAddr)
        external
        view
        returns (uint256)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.targetContract == appStorageAddr, "Invalid app storage");
        require(_isChannelParticipant(channelId, user), "User not in channel");

        uint8 balanceSlotIndex = _getBalanceSlotIndex(appStorageAddr);
        return channel.l2MptKey[user][balanceSlotIndex];
    }

    function getAppValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 appUserStorageKey)
        external
        view
        returns (uint256)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.targetContract == appStorageAddr, "Invalid app storage");

        uint256 slotCount = $.allowedTargetContracts[appStorageAddr].userStorageSlots.length;
        for (uint256 participantIdx = 0; participantIdx < channel.participants.length; participantIdx++) {
            address participant = channel.participants[participantIdx];
            for (uint8 slotIdx = 0; slotIdx < slotCount; slotIdx++) {
                if (channel.l2MptKey[participant][slotIdx] == appUserStorageKey) {
                    if (!_hasValidatedUserStorage(participant, channelId)) {
                        return 0;
                    }
                    ValidatedUserStorage storage entry = _getValidatedUserStorage(participant, channelId);
                    return entry.value[slotIdx];
                }
            }
        }

        revert("Storage key not found");
    }

    function getAppPreAllocValue(bytes32 channelId, address appStorageAddr, bytes32 preAllocKey)
        external
        view
        returns (uint256)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require($.channels[channelId].targetContract == appStorageAddr, "Invalid app storage");

        PreAllocatedLeaf storage leaf = $.preAllocatedLeaves[appStorageAddr][preAllocKey];
        require(leaf.isActive, "Pre-allocated leaf not found");
        return leaf.value;
    }

    function getVerifiedStateRoot(bytes32 channelId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require($.channels[channelId].targetContract == appStorageAddr, "Invalid app storage");
        return $.verifiedStateRoots[channelId][stateIndex];
    }

    function getProposedStateRoot(bytes32 channelId, uint8 forkId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require($.channels[channelId].targetContract == appStorageAddr, "Invalid app storage");
        return $.proposedStateRoots[channelId][forkId][stateIndex];
    }

    function getProposedStateFork(bytes32 channelId, uint8 forkId)
        external
        view
        returns (uint16[] memory stateIndices, bytes32[] memory roots)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        uint16[] storage storedStateIndices = $.proposedStateIndices[channelId][forkId];

        stateIndices = new uint16[](storedStateIndices.length);
        roots = new bytes32[](storedStateIndices.length);

        for (uint256 i = 0; i < storedStateIndices.length; i++) {
            uint16 stateIndex = storedStateIndices[i];
            stateIndices[i] = stateIndex;
            roots[i] = $.proposedStateRoots[channelId][forkId][stateIndex];
        }
    }

    function getChannelFcnStorages(bytes32 channelId, bytes32 functionSignature)
        external
        view
        returns (address[] memory)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        address targetContract = $.channels[channelId].targetContract;
        if ($.functionStorageExists[functionSignature][targetContract]) {
            address[] memory storages = new address[](1);
            storages[0] = targetContract;
            return storages;
        }
        return new address[](0);
    }

    function getChannelPreAllocKeys(bytes32 channelId, address appStorageAddr)
        external
        view
        returns (bytes32[] memory)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        if ($.channels[channelId].targetContract != appStorageAddr) {
            return new bytes32[](0);
        }
        return $.targetContractPreAllocatedKeys[appStorageAddr];
    }

    function getChannelUserSlots(bytes32 channelId, address appStorageAddr) external view returns (uint8[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        if ($.channels[channelId].targetContract != appStorageAddr) {
            return new uint8[](0);
        }

        UserStorageSlot[] storage userStorageSlots = $.allowedTargetContracts[appStorageAddr].userStorageSlots;
        uint8[] memory slotOffsets = new uint8[](userStorageSlots.length);
        for (uint256 i = 0; i < userStorageSlots.length; i++) {
            slotOffsets[i] = userStorageSlots[i].slotOffset;
        }
        return slotOffsets;
    }

    function getChannelFcnCfg(bytes32 channelId, bytes32 functionSignature)
        external
        view
        returns (bytes32 instancesHash, bytes32 preprocessHash)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        address targetContract = $.channels[channelId].targetContract;
        require($.functionStorageExists[functionSignature][targetContract], "Function not in channel");
        require($.functionCfgExists[functionSignature], "Function config not found");
        return ($.functionInstancesHash[functionSignature], $.functionPreprocessHash[functionSignature]);
    }

    function getChannelUserStorageKey(bytes32 channelId, address user, address appStorageAddr)
        external
        view
        returns (uint256)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.targetContract == appStorageAddr, "Invalid app storage");
        require(_isChannelParticipant(channelId, user), "User not in channel");

        uint8 balanceSlotIndex = _getBalanceSlotIndex(appStorageAddr);
        return channel.l2MptKey[user][balanceSlotIndex];
    }

    function getChannelValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 appUserStorageKey)
        external
        view
        returns (uint256)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.targetContract == appStorageAddr, "Invalid app storage");

        uint256 slotCount = $.allowedTargetContracts[appStorageAddr].userStorageSlots.length;
        for (uint256 participantIdx = 0; participantIdx < channel.participants.length; participantIdx++) {
            address participant = channel.participants[participantIdx];
            for (uint8 slotIdx = 0; slotIdx < slotCount; slotIdx++) {
                if (channel.l2MptKey[participant][slotIdx] == appUserStorageKey) {
                    if (!_hasValidatedUserStorage(participant, channelId)) {
                        return 0;
                    }
                    ValidatedUserStorage storage entry = _getValidatedUserStorage(participant, channelId);
                    return entry.value[slotIdx];
                }
            }
        }

        revert("Storage key not found");
    }

    function getChannelPreAllocValue(bytes32 channelId, address appStorageAddr, bytes32 preAllocKey)
        external
        view
        returns (uint256)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require($.channels[channelId].targetContract == appStorageAddr, "Invalid app storage");

        PreAllocatedLeaf storage leaf = $.preAllocatedLeaves[appStorageAddr][preAllocKey];
        require(leaf.isActive, "Pre-allocated leaf not found");
        return leaf.value;
    }

    function getChannelVerifiedStateRoot(bytes32 channelId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require($.channels[channelId].targetContract == appStorageAddr, "Invalid app storage");
        return $.verifiedStateRoots[channelId][stateIndex];
    }

    function getChannelProposedStateRoot(bytes32 channelId, uint8 forkId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require($.channels[channelId].targetContract == appStorageAddr, "Invalid app storage");
        return $.proposedStateRoots[channelId][forkId][stateIndex];
    }

    function getChannelProposedStateFork(bytes32 channelId, uint8 forkId)
        external
        view
        returns (uint16[] memory stateIndices, bytes32[] memory roots)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        uint16[] storage storedStateIndices = $.proposedStateIndices[channelId][forkId];

        stateIndices = new uint16[](storedStateIndices.length);
        roots = new bytes32[](storedStateIndices.length);

        for (uint256 i = 0; i < storedStateIndices.length; i++) {
            uint16 stateIndex = storedStateIndices[i];
            stateIndices[i] = stateIndex;
            roots[i] = $.proposedStateRoots[channelId][forkId][stateIndex];
        }
    }

    function isSignatureVerified(bytes32 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].sigVerified;
    }

    function getValidatedUserSlotValue(bytes32 channelId, address participant, uint8 slotIndex)
        external
        view
        returns (uint256)
    {
        if (!_hasValidatedUserStorage(participant, channelId)) {
            return 0;
        }
        ValidatedUserStorage storage entry = _getValidatedUserStorage(participant, channelId);
        return entry.value[slotIndex];
    }

    function getValidatedUserTargetContract(bytes32 channelId, address participant) external view returns (address) {
        if (!_hasValidatedUserStorage(participant, channelId)) {
            return address(0);
        }
        ValidatedUserStorage storage entry = _getValidatedUserStorage(participant, channelId);
        return entry.targetContract;
    }

    function hasUserWithdrawn(bytes32 channelId, address participant, address targetContract)
        external
        view
        returns (bool)
    {
        if (!_hasValidatedUserStorage(participant, channelId)) {
            return true; // No entry means nothing to withdraw
        }
        uint8 balanceSlotIndex = _getBalanceSlotIndex(targetContract);

        ValidatedUserStorage storage entry = _getValidatedUserStorage(participant, channelId);
        return entry.value[balanceSlotIndex] == 0;
    }

    function getBalanceSlotIndex(address targetContract) external view returns (uint8) {
        return _getBalanceSlotIndex(targetContract);
    }

    function getBalanceSlotOffset(address targetContract) external view returns (uint8) {
        return _getBalanceSlotOffset(targetContract);
    }

    function getChannelBlockInfosHash(bytes32 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].blockInfosHash;
    }

    function isMarkedChannelLeader(address addr, bytes32 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].leader == addr;
    }

    function isFrostSignatureEnabled(bytes32 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].frostSignatureEnabled;
    }

    function isChannelTimedOut(bytes32 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        require(channel.leader != address(0), "Channel does not exist");
        return block.timestamp > channel.openTimestamp + CHANNEL_TIMEOUT;
    }

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

    /**
     * @notice Generate a channel ID hash from leader address and salt
     * @dev This is a pure function that can be called off-chain to generate channel IDs
     * @param leader The channel leader address
     * @param salt Any salt value to ensure uniqueness
     * @return channelId The generated channel ID
     */
    function generateChannelId(address leader, bytes32 salt) external pure returns (bytes32 channelId) {
        return keccak256(abi.encodePacked(leader, salt));
    }

    uint256[42] private __gap;
}
