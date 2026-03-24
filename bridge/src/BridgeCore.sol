// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {BridgeStructs} from "./BridgeStructs.sol";
import {BridgeAdminManager} from "./BridgeAdminManager.sol";
import {DAppManager} from "./DAppManager.sol";
import {ChannelManager} from "./ChannelManager.sol";
import {L1TokenVault, IVaultKeyRegistry} from "./L1TokenVault.sol";
import {IGrothVerifier} from "./interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "./interfaces/ITokamakVerifier.sol";

contract BridgeCore is Initializable, OwnableUpgradeable, UUPSUpgradeable, IVaultKeyRegistry {
    uint8 internal constant SUPPORTED_MT_LEVELS = 12;
    uint256 internal constant SUPPORTED_MT_LEAVES = uint256(1) << uint256(SUPPORTED_MT_LEVELS);
    uint256 internal constant MAX_MANAGED_STORAGES = 11;
    address internal constant TOKAMAK_NETWORK_TOKEN_MAINNET = 0x2be5e8c109e2197D077D13A82dAead6a9b3433C5;
    address internal constant TOKAMAK_NETWORK_TOKEN_SEPOLIA = 0xa30fe40285B8f5c0457DbC3B7C8A280373c40044;
    bytes32 internal constant ZERO_FILLED_TREE_ROOT =
        bytes32(uint256(5829984778942235508054786484586420582947187778500268001993713384889194068958));

    error UnknownChannel(uint256 channelId);
    error ChannelAlreadyExists(uint256 channelId);
    error OnlyChannelVault();
    error InvalidMerkleTreeConfiguration();
    error UnsupportedMerkleTreeLevels(uint8 actualLevels, uint8 expectedLevels);
    error InvalidLeader();
    error GlobalVaultKeyAlreadyRegistered(bytes32 key);
    error ChannelLeafIndexCollision(uint256 channelId, uint256 leafIndex);
    error TooManyManagedStorages(uint256 actualCount, uint256 maxSupported);
    error InvalidAdminManager();
    error InvalidDAppManager();
    error InvalidGrothVerifier();
    error InvalidTokamakVerifier();
    error UnsupportedCanonicalAssetChain(uint256 chainId);

    struct ChannelDeployment {
        bool exists;
        uint256 dappId;
        address leader;
        address asset;
        address manager;
        address vault;
        bytes32 aPubBlockHash;
    }

    BridgeAdminManager public adminManager;
    DAppManager public dAppManager;
    IGrothVerifier public grothVerifier;
    ITokamakVerifier public tokamakVerifier;

    mapping(uint256 => ChannelDeployment) private _channels;
    mapping(address => uint256) public vaultToChannelId;
    mapping(bytes32 => bool) public globallyRegisteredVaultKeys;
    mapping(uint256 => mapping(uint256 => address)) public channelLeafIndexOwner;

    event ChannelCreated(
        uint256 indexed channelId,
        uint256 indexed dappId,
        address manager,
        address vault
    );
    event VaultKeyReserved(
        uint256 indexed channelId,
        address indexed user,
        bytes32 indexed key,
        uint256 leafIndex
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        BridgeAdminManager adminManager_,
        DAppManager dAppManager_,
        IGrothVerifier grothVerifier_,
        ITokamakVerifier tokamakVerifier_
    ) external initializer {
        if (address(adminManager_) == address(0)) revert InvalidAdminManager();
        if (address(dAppManager_) == address(0)) revert InvalidDAppManager();
        if (address(grothVerifier_) == address(0)) revert InvalidGrothVerifier();
        if (address(tokamakVerifier_) == address(0)) revert InvalidTokamakVerifier();

        __Ownable_init();
        __UUPSUpgradeable_init();
        if (initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }

        adminManager = adminManager_;
        dAppManager = dAppManager_;
        grothVerifier = grothVerifier_;
        tokamakVerifier = tokamakVerifier_;
    }

    function canonicalAsset() public view returns (address) {
        if (block.chainid == 1) {
            return TOKAMAK_NETWORK_TOKEN_MAINNET;
        }
        if (block.chainid == 11155111 || block.chainid == 31337) {
            return TOKAMAK_NETWORK_TOKEN_SEPOLIA;
        }
        revert UnsupportedCanonicalAssetChain(block.chainid);
    }

    function createChannel(
        uint256 channelId,
        uint256 dappId,
        address leader
    ) external onlyOwner returns (address manager, address vault) {
        IERC20 asset = IERC20(canonicalAsset());
        if (_channels[channelId].exists) revert ChannelAlreadyExists(channelId);
        if (leader == address(0)) revert InvalidLeader();
        if (adminManager.nMerkleTreeLevels() == 0) revert InvalidMerkleTreeConfiguration();
        if (adminManager.nMerkleTreeLevels() != SUPPORTED_MT_LEVELS) {
            revert UnsupportedMerkleTreeLevels(adminManager.nMerkleTreeLevels(), SUPPORTED_MT_LEVELS);
        }
        address[] memory managedStorageAddresses = dAppManager.getManagedStorageAddresses(dappId);
        if (managedStorageAddresses.length > MAX_MANAGED_STORAGES) {
            revert TooManyManagedStorages(managedStorageAddresses.length, MAX_MANAGED_STORAGES);
        }
        uint256 tokenVaultTreeIndex = dAppManager.getTokenVaultTreeIndex(dappId);
        BridgeStructs.FunctionReference[] memory registeredFunctions = dAppManager.getRegisteredFunctions(dappId);

        bytes32[] memory initialRootVector = _buildInitialRootVector(managedStorageAddresses.length);

        ChannelManager channelManager = new ChannelManager(
            channelId,
            dappId,
            leader,
            tokenVaultTreeIndex,
            initialRootVector,
            managedStorageAddresses,
            registeredFunctions,
            address(this),
            dAppManager,
            tokamakVerifier
        );

        L1TokenVault tokenVault =
            new L1TokenVault(channelId, asset, channelManager, grothVerifier, IVaultKeyRegistry(address(this)));

        channelManager.bindTokenVault(address(tokenVault));

        bytes32 channelAPubBlockHash = channelManager.aPubBlockHash();
        _channels[channelId] = ChannelDeployment({
            exists: true,
            dappId: dappId,
            leader: leader,
            asset: address(asset),
            manager: address(channelManager),
            vault: address(tokenVault),
            aPubBlockHash: channelAPubBlockHash
        });

        vaultToChannelId[address(tokenVault)] = channelId;

        emit ChannelCreated(channelId, dappId, address(channelManager), address(tokenVault));
        return (address(channelManager), address(tokenVault));
    }

    function reserveVaultKey(uint256 channelId, address user, bytes32 key)
        external
        override
        returns (uint256 leafIndex)
    {
        ChannelDeployment memory deployment = _channels[channelId];
        if (!deployment.exists) revert UnknownChannel(channelId);
        if (msg.sender != deployment.vault) revert OnlyChannelVault();
        if (globallyRegisteredVaultKeys[key]) revert GlobalVaultKeyAlreadyRegistered(key);

        leafIndex = deriveLeafIndex(key);
        if (channelLeafIndexOwner[channelId][leafIndex] != address(0)) {
            revert ChannelLeafIndexCollision(channelId, leafIndex);
        }

        globallyRegisteredVaultKeys[key] = true;
        channelLeafIndexOwner[channelId][leafIndex] = user;

        emit VaultKeyReserved(channelId, user, key, leafIndex);
    }

    function getChannel(uint256 channelId) external view returns (ChannelDeployment memory) {
        if (!_channels[channelId].exists) revert UnknownChannel(channelId);
        return _channels[channelId];
    }

    function deriveLeafIndex(bytes32 key) public pure returns (uint256) {
        return uint256(key) % SUPPORTED_MT_LEAVES;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _buildInitialRootVector(uint256 treeCount) private pure returns (bytes32[] memory initialRootVector) {
        initialRootVector = new bytes32[](treeCount);
        for (uint256 i = 0; i < treeCount; i++) {
            initialRootVector[i] = ZERO_FILLED_TREE_ROOT;
        }
    }
}
