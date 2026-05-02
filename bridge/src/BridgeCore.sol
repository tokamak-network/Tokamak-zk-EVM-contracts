// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Initializable } from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";
import { BridgeStructs } from "./BridgeStructs.sol";
import { BridgeAdminManager } from "./BridgeAdminManager.sol";
import { DAppManager } from "./DAppManager.sol";
import { ChannelManager } from "./ChannelManager.sol";
import { ChannelDeployer } from "./ChannelDeployer.sol";
import { TokamakEnvironment } from "./generated/TokamakEnvironment.sol";
import { IGrothVerifier } from "./interfaces/IGrothVerifier.sol";
import { ITokamakVerifier } from "./interfaces/ITokamakVerifier.sol";
import { IChannelRegistry } from "./interfaces/IChannelRegistry.sol";

contract BridgeCore is Initializable, OwnableUpgradeable, UUPSUpgradeable, IChannelRegistry {
    uint256 internal constant MAX_MANAGED_STORAGES = 11;
    uint16 internal constant BPS_DENOMINATOR = 10_000;
    address internal constant TOKAMAK_NETWORK_TOKEN_MAINNET =
        0x2be5e8c109e2197D077D13A82dAead6a9b3433C5;
    address internal constant TOKAMAK_NETWORK_TOKEN_SEPOLIA =
        0xa30fe40285B8f5c0457DbC3B7C8A280373c40044;

    error UnknownChannel(uint256 channelId);
    error ChannelAlreadyExists(uint256 channelId);
    error InvalidMerkleTreeConfiguration();
    error UnsupportedMerkleTreeLevels(uint8 actualLevels, uint8 expectedLevels);
    error InvalidLeader();
    error TooManyManagedStorages(uint256 actualCount, uint256 maxSupported);
    error InvalidAdminManager();
    error InvalidDAppManager();
    error InvalidChannelDeployer();
    error InvalidChannelManager(address manager);
    error InvalidGrothVerifier();
    error InvalidTokamakVerifier();
    error InvalidBridgeTokenVault();
    error BridgeTokenVaultAlreadySet();
    error UnsupportedCanonicalAssetChain(uint256 chainId);
    error InvalidJoinFeeRefundSchedule();
    error DAppMetadataDigestMismatch(uint256 dappId, bytes32 expectedDigest, bytes32 actualDigest);

    struct ChannelDeployment {
        bool exists;
        uint256 dappId;
        address leader;
        address asset;
        address manager;
        address bridgeTokenVault;
        bytes32 aPubBlockHash;
        bytes32 dappMetadataDigestSchema;
        bytes32 dappMetadataDigest;
    }

    BridgeAdminManager public adminManager;
    DAppManager public dAppManager;
    ChannelDeployer public channelDeployer;
    IGrothVerifier public grothVerifier;
    ITokamakVerifier public tokamakVerifier;
    address public bridgeTokenVault;
    uint64 public defaultJoinFeeRefundCutoff1;
    uint64 public defaultJoinFeeRefundCutoff2;
    uint64 public defaultJoinFeeRefundCutoff3;
    uint16 public defaultJoinFeeRefundBps1;
    uint16 public defaultJoinFeeRefundBps2;
    uint16 public defaultJoinFeeRefundBps3;
    uint16 public defaultJoinFeeRefundBps4;

    mapping(uint256 => ChannelDeployment) private _channels;

    event ChannelCreated(
        uint256 indexed channelId, uint256 indexed dappId, address manager, address bridgeTokenVault
    );
    event BridgeTokenVaultBound(address indexed bridgeTokenVault);
    event ChannelDeployerUpdated(address indexed channelDeployer);
    event GrothVerifierUpdated(address indexed grothVerifier);
    event TokamakVerifierUpdated(address indexed tokamakVerifier);
    event JoinFeeRefundScheduleUpdated(
        uint64 cutoff1,
        uint16 bps1,
        uint64 cutoff2,
        uint16 bps2,
        uint64 cutoff3,
        uint16 bps3,
        uint16 bps4
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        BridgeAdminManager adminManager_,
        DAppManager dAppManager_,
        ChannelDeployer channelDeployer_,
        IGrothVerifier grothVerifier_,
        ITokamakVerifier tokamakVerifier_
    ) external initializer {
        if (address(adminManager_) == address(0)) {
            revert InvalidAdminManager();
        }
        if (address(dAppManager_) == address(0)) revert InvalidDAppManager();
        if (address(channelDeployer_) == address(0) || address(channelDeployer_).code.length == 0) {
            revert InvalidChannelDeployer();
        }
        if (address(grothVerifier_) == address(0)) revert InvalidGrothVerifier();
        if (address(tokamakVerifier_) == address(0)) revert InvalidTokamakVerifier();

        __Ownable_init();
        __UUPSUpgradeable_init();
        if (initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }

        adminManager = adminManager_;
        dAppManager = dAppManager_;
        channelDeployer = channelDeployer_;
        grothVerifier = grothVerifier_;
        tokamakVerifier = tokamakVerifier_;
        _setJoinFeeRefundSchedule(6 hours, 7_500, 24 hours, 5_000, 3 days, 2_500, 0);
    }

    function setChannelDeployer(ChannelDeployer channelDeployer_) external onlyOwner {
        if (address(channelDeployer_) == address(0) || address(channelDeployer_).code.length == 0) {
            revert InvalidChannelDeployer();
        }
        channelDeployer = channelDeployer_;
        emit ChannelDeployerUpdated(address(channelDeployer_));
    }

    function setGrothVerifier(IGrothVerifier grothVerifier_) external onlyOwner {
        if (address(grothVerifier_) == address(0)) revert InvalidGrothVerifier();
        grothVerifier = grothVerifier_;
        emit GrothVerifierUpdated(address(grothVerifier_));
    }

    function setTokamakVerifier(ITokamakVerifier tokamakVerifier_) external onlyOwner {
        if (address(tokamakVerifier_) == address(0)) revert InvalidTokamakVerifier();
        tokamakVerifier = tokamakVerifier_;
        emit TokamakVerifierUpdated(address(tokamakVerifier_));
    }

    function bindBridgeTokenVault(address bridgeTokenVault_) external onlyOwner {
        if (bridgeTokenVault_ == address(0)) revert InvalidBridgeTokenVault();
        if (bridgeTokenVault != address(0)) revert BridgeTokenVaultAlreadySet();
        bridgeTokenVault = bridgeTokenVault_;
        emit BridgeTokenVaultBound(bridgeTokenVault_);
    }

    function setJoinFeeRefundSchedule(
        uint64 cutoff1,
        uint16 bps1,
        uint64 cutoff2,
        uint16 bps2,
        uint64 cutoff3,
        uint16 bps3,
        uint16 bps4
    ) external onlyOwner {
        _setJoinFeeRefundSchedule(cutoff1, bps1, cutoff2, bps2, cutoff3, bps3, bps4);
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
        address leader,
        uint256 initialJoinFee,
        bytes32 expectedDAppMetadataDigest
    ) external onlyOwner returns (address manager, address boundBridgeTokenVault) {
        IERC20 asset = IERC20(canonicalAsset());
        if (_channels[channelId].exists) revert ChannelAlreadyExists(channelId);
        if (bridgeTokenVault == address(0)) revert InvalidBridgeTokenVault();
        if (leader == address(0)) revert InvalidLeader();
        if (adminManager.nMerkleTreeLevels() == 0) revert InvalidMerkleTreeConfiguration();
        if (adminManager.nMerkleTreeLevels() != TokamakEnvironment.MT_DEPTH) {
            revert UnsupportedMerkleTreeLevels(
                adminManager.nMerkleTreeLevels(), TokamakEnvironment.MT_DEPTH
            );
        }
        uint256 managedStorageCount = dAppManager.getManagedStorageCount(dappId);
        if (managedStorageCount > MAX_MANAGED_STORAGES) {
            revert TooManyManagedStorages(managedStorageCount, MAX_MANAGED_STORAGES);
        }
        DAppManager.DAppInfo memory dAppInfo = dAppManager.getDAppInfo(dappId);
        if (dAppInfo.metadataDigest != expectedDAppMetadataDigest) {
            revert DAppMetadataDigestMismatch(
                dappId, expectedDAppMetadataDigest, dAppInfo.metadataDigest
            );
        }
        uint256 channelTokenVaultTreeIndex = dAppInfo.channelTokenVaultTreeIndex;
        BridgeStructs.DAppVerifierSnapshot memory verifierSnapshot =
            dAppManager.getDAppVerifierSnapshot(dappId);

        address channelManagerAddress = channelDeployer.deployChannelManager(
            channelId,
            dappId,
            leader,
            channelTokenVaultTreeIndex,
            address(this),
            verifierSnapshot,
            dAppInfo.metadataDigestSchema,
            dAppInfo.metadataDigest,
            initialJoinFee,
            defaultJoinFeeRefundCutoff1,
            defaultJoinFeeRefundBps1,
            defaultJoinFeeRefundCutoff2,
            defaultJoinFeeRefundBps2,
            defaultJoinFeeRefundCutoff3,
            defaultJoinFeeRefundBps3,
            defaultJoinFeeRefundBps4,
            dAppManager,
            managedStorageCount
        );
        ChannelManager channelManager = ChannelManager(channelManagerAddress);

        _validateChannelManager(
            channelManager,
            channelId,
            dappId,
            leader,
            channelTokenVaultTreeIndex,
            verifierSnapshot,
            dAppInfo.metadataDigestSchema,
            dAppInfo.metadataDigest,
            initialJoinFee
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
            aPubBlockHash: channelAPubBlockHash,
            dappMetadataDigestSchema: dAppInfo.metadataDigestSchema,
            dappMetadataDigest: dAppInfo.metadataDigest
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

    function _authorizeUpgrade(address) internal override onlyOwner { }

    function _validateChannelManager(
        ChannelManager channelManager,
        uint256 channelId,
        uint256 dappId,
        address leader,
        uint256 channelTokenVaultTreeIndex,
        BridgeStructs.DAppVerifierSnapshot memory verifierSnapshot,
        bytes32 dappMetadataDigestSchema,
        bytes32 dappMetadataDigest,
        uint256 initialJoinFee
    ) private view {
        address manager = address(channelManager);
        if (
            manager.code.length == 0 || channelManager.bridgeCore() != address(this)
                || channelManager.channelId() != channelId || channelManager.dappId() != dappId
                || channelManager.leader() != leader
                || channelManager.channelTokenVaultTreeIndex() != channelTokenVaultTreeIndex
                || channelManager.dappMetadataDigestSchema() != dappMetadataDigestSchema
                || channelManager.dappMetadataDigest() != dappMetadataDigest
                || address(channelManager.grothVerifier()) != verifierSnapshot.grothVerifier
                || address(channelManager.tokamakVerifier()) != verifierSnapshot.tokamakVerifier
                || channelManager.joinFee() != initialJoinFee
                || channelManager.joinFeeRefundCutoff1() != defaultJoinFeeRefundCutoff1
                || channelManager.joinFeeRefundBps1() != defaultJoinFeeRefundBps1
                || channelManager.joinFeeRefundCutoff2() != defaultJoinFeeRefundCutoff2
                || channelManager.joinFeeRefundBps2() != defaultJoinFeeRefundBps2
                || channelManager.joinFeeRefundCutoff3() != defaultJoinFeeRefundCutoff3
                || channelManager.joinFeeRefundBps3() != defaultJoinFeeRefundBps3
                || channelManager.joinFeeRefundBps4() != defaultJoinFeeRefundBps4
        ) {
            revert InvalidChannelManager(manager);
        }
    }

    function _setJoinFeeRefundSchedule(
        uint64 cutoff1,
        uint16 bps1,
        uint64 cutoff2,
        uint16 bps2,
        uint64 cutoff3,
        uint16 bps3,
        uint16 bps4
    ) private {
        if (
            cutoff1 == 0 || cutoff1 >= cutoff2 || cutoff2 >= cutoff3 || bps1 > BPS_DENOMINATOR
                || bps2 > BPS_DENOMINATOR || bps3 > BPS_DENOMINATOR || bps4 > BPS_DENOMINATOR
                || bps1 < bps2 || bps2 < bps3 || bps3 < bps4
        ) {
            revert InvalidJoinFeeRefundSchedule();
        }

        defaultJoinFeeRefundCutoff1 = cutoff1;
        defaultJoinFeeRefundCutoff2 = cutoff2;
        defaultJoinFeeRefundCutoff3 = cutoff3;
        defaultJoinFeeRefundBps1 = bps1;
        defaultJoinFeeRefundBps2 = bps2;
        defaultJoinFeeRefundBps3 = bps3;
        defaultJoinFeeRefundBps4 = bps4;

        emit JoinFeeRefundScheduleUpdated(cutoff1, bps1, cutoff2, bps2, cutoff3, bps3, bps4);
    }
}
