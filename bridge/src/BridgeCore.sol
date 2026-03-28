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
import {IGrothVerifier} from "./interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "./interfaces/ITokamakVerifier.sol";
import {IChannelRegistry} from "./interfaces/IChannelRegistry.sol";

contract BridgeCore is Initializable, OwnableUpgradeable, UUPSUpgradeable, IChannelRegistry {
    uint8 internal constant SUPPORTED_MT_LEVELS = 12;
    uint256 internal constant MAX_MANAGED_STORAGES = 11;
    address internal constant TOKAMAK_NETWORK_TOKEN_MAINNET = 0x2be5e8c109e2197D077D13A82dAead6a9b3433C5;
    address internal constant TOKAMAK_NETWORK_TOKEN_SEPOLIA = 0xa30fe40285B8f5c0457DbC3B7C8A280373c40044;
    bytes32 internal constant ZERO_FILLED_TREE_ROOT =
        bytes32(uint256(5829984778942235508054786484586420582947187778500268001993713384889194068958));

    error UnknownChannel(uint256 channelId);
    error ChannelAlreadyExists(uint256 channelId);
    error InvalidMerkleTreeConfiguration();
    error UnsupportedMerkleTreeLevels(uint8 actualLevels, uint8 expectedLevels);
    error InvalidLeader();
    error TooManyManagedStorages(uint256 actualCount, uint256 maxSupported);
    error InvalidAdminManager();
    error InvalidDAppManager();
    error InvalidGrothVerifier();
    error InvalidTokamakVerifier();
    error InvalidBridgeTokenVault();
    error BridgeTokenVaultAlreadySet();
    error UnsupportedCanonicalAssetChain(uint256 chainId);

    struct ChannelDeployment {
        bool exists;
        uint256 dappId;
        address leader;
        address asset;
        address manager;
        address bridgeTokenVault;
        bytes32 aPubBlockHash;
    }

    BridgeAdminManager public adminManager;
    DAppManager public dAppManager;
    IGrothVerifier public grothVerifier;
    ITokamakVerifier public tokamakVerifier;
    address public bridgeTokenVault;

    mapping(uint256 => ChannelDeployment) private _channels;

    event ChannelCreated(
        uint256 indexed channelId,
        uint256 indexed dappId,
        address manager,
        address bridgeTokenVault
    );
    event BridgeTokenVaultBound(address indexed bridgeTokenVault);
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

    function bindBridgeTokenVault(address bridgeTokenVault_) external onlyOwner {
        if (bridgeTokenVault_ == address(0)) revert InvalidBridgeTokenVault();
        if (bridgeTokenVault != address(0)) revert BridgeTokenVaultAlreadySet();
        bridgeTokenVault = bridgeTokenVault_;
        emit BridgeTokenVaultBound(bridgeTokenVault_);
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
    ) external onlyOwner returns (address manager, address boundBridgeTokenVault) {
        IERC20 asset = IERC20(canonicalAsset());
        if (_channels[channelId].exists) revert ChannelAlreadyExists(channelId);
        if (bridgeTokenVault == address(0)) revert InvalidBridgeTokenVault();
        if (leader == address(0)) revert InvalidLeader();
        if (adminManager.nMerkleTreeLevels() == 0) revert InvalidMerkleTreeConfiguration();
        if (adminManager.nMerkleTreeLevels() != SUPPORTED_MT_LEVELS) {
            revert UnsupportedMerkleTreeLevels(adminManager.nMerkleTreeLevels(), SUPPORTED_MT_LEVELS);
        }
        address[] memory managedStorageAddresses = dAppManager.getManagedStorageAddresses(dappId);
        if (managedStorageAddresses.length > MAX_MANAGED_STORAGES) {
            revert TooManyManagedStorages(managedStorageAddresses.length, MAX_MANAGED_STORAGES);
        }
        uint256 channelTokenVaultTreeIndex = dAppManager.getChannelTokenVaultTreeIndex(dappId);
        BridgeStructs.FunctionReference[] memory registeredFunctions = dAppManager.getRegisteredFunctions(dappId);

        bytes32[] memory initialRootVector = new bytes32[](managedStorageAddresses.length);
        for (uint256 i = 0; i < managedStorageAddresses.length; i++) {
            initialRootVector[i] = ZERO_FILLED_TREE_ROOT;
        }

        ChannelManager channelManager = new ChannelManager(
            channelId,
            dappId,
            leader,
            channelTokenVaultTreeIndex,
            initialRootVector,
            managedStorageAddresses,
            registeredFunctions,
            address(this),
            dAppManager,
            tokamakVerifier
        );

        channelManager.bindBridgeTokenVault(bridgeTokenVault);

        bytes32 channelAPubBlockHash = channelManager.aPubBlockHash();
        _channels[channelId] = ChannelDeployment({
            exists: true,
            dappId: dappId,
            leader: leader,
            asset: address(asset),
            manager: address(channelManager),
            bridgeTokenVault: bridgeTokenVault,
            aPubBlockHash: channelAPubBlockHash
        });

        emit ChannelCreated(channelId, dappId, address(channelManager), bridgeTokenVault);
        return (address(channelManager), bridgeTokenVault);
    }

    function getChannel(uint256 channelId) external view returns (ChannelDeployment memory) {
        if (!_channels[channelId].exists) revert UnknownChannel(channelId);
        return _channels[channelId];
    }

    function getChannelManager(uint256 channelId) external view override returns (address) {
        if (!_channels[channelId].exists) revert UnknownChannel(channelId);
        return _channels[channelId].manager;
    }

    function getChannelTokenVaultRegistration(uint256 channelId, address l1Address)
        external
        view
        returns (BridgeStructs.ChannelTokenVaultRegistration memory)
    {
        if (!_channels[channelId].exists) revert UnknownChannel(channelId);
        return ChannelManager(_channels[channelId].manager).getChannelTokenVaultRegistration(l1Address);
    }

    function getChannelTokenVaultRegistrationByL2Address(uint256 channelId, address l2Address)
        external
        view
        returns (BridgeStructs.ChannelTokenVaultRegistration memory)
    {
        if (!_channels[channelId].exists) revert UnknownChannel(channelId);
        return ChannelManager(_channels[channelId].manager).getChannelTokenVaultRegistrationByL2Address(l2Address);
    }

    function getNoteReceivePubKeyByL2Address(uint256 channelId, address l2Address)
        external
        view
        returns (BridgeStructs.NoteReceivePubKey memory)
    {
        if (!_channels[channelId].exists) revert UnknownChannel(channelId);
        return ChannelManager(_channels[channelId].manager).getNoteReceivePubKeyByL2Address(l2Address);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
