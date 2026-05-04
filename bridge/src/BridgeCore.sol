// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Initializable } from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";
import { BridgeStructs } from "./BridgeStructs.sol";
import { DAppManager } from "./DAppManager.sol";
import { ChannelManager } from "./ChannelManager.sol";
import { ChannelDeployer } from "./ChannelDeployer.sol";
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
    error TooManyManagedStorages(uint256 actualCount, uint256 maxSupported);
    error InvalidDAppManager();
    error InvalidChannelDeployer();
    error InvalidChannelManager(address manager);
    error InvalidGrothVerifier();
    error InvalidTokamakVerifier();
    error InvalidBridgeTokenVault();
    error BridgeTokenVaultAlreadySet();
    error UnsupportedCanonicalAssetChain(uint256 chainId);
    error InvalidJoinTollRefundSchedule();
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

    DAppManager public dAppManager;
    ChannelDeployer public channelDeployer;
    IGrothVerifier public grothVerifier;
    ITokamakVerifier public tokamakVerifier;
    address public bridgeTokenVault;
    uint64 public defaultJoinTollRefundCutoff1;
    uint64 public defaultJoinTollRefundCutoff2;
    uint64 public defaultJoinTollRefundCutoff3;
    uint16 public defaultJoinTollRefundBps1;
    uint16 public defaultJoinTollRefundBps2;
    uint16 public defaultJoinTollRefundBps3;
    uint16 public defaultJoinTollRefundBps4;

    mapping(uint256 => ChannelDeployment) private _channels;

    event ChannelCreated(
        uint256 indexed channelId, uint256 indexed dappId, address manager, address bridgeTokenVault
    );
    event BridgeTokenVaultBound(address indexed bridgeTokenVault);
    event ChannelDeployerUpdated(address indexed channelDeployer);
    event GrothVerifierUpdated(address indexed grothVerifier);
    event TokamakVerifierUpdated(address indexed tokamakVerifier);
    event JoinTollRefundScheduleUpdated(
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
        DAppManager dAppManager_,
        ChannelDeployer channelDeployer_,
        IGrothVerifier grothVerifier_,
        ITokamakVerifier tokamakVerifier_
    ) external initializer {
        if (address(dAppManager_) == address(0)) {
            revert InvalidDAppManager();
        }
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

        dAppManager = dAppManager_;
        channelDeployer = channelDeployer_;
        grothVerifier = grothVerifier_;
        tokamakVerifier = tokamakVerifier_;
        _setJoinTollRefundSchedule(6 hours, 7_500, 24 hours, 5_000, 3 days, 2_500, 0);
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

    function setJoinTollRefundSchedule(
        uint64 cutoff1,
        uint16 bps1,
        uint64 cutoff2,
        uint16 bps2,
        uint64 cutoff3,
        uint16 bps3,
        uint16 bps4
    ) external onlyOwner {
        _setJoinTollRefundSchedule(cutoff1, bps1, cutoff2, bps2, cutoff3, bps3, bps4);
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
        uint256 initialJoinToll,
        bytes32 expectedDAppMetadataDigest
    ) external returns (address manager, address boundBridgeTokenVault) {
        address leader = msg.sender;
        IERC20 asset = IERC20(canonicalAsset());
        if (_channels[channelId].exists) revert ChannelAlreadyExists(channelId);
        if (bridgeTokenVault == address(0)) revert InvalidBridgeTokenVault();
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
            dAppInfo.functionRoot,
            initialJoinToll,
            defaultJoinTollRefundCutoff1,
            defaultJoinTollRefundBps1,
            defaultJoinTollRefundCutoff2,
            defaultJoinTollRefundBps2,
            defaultJoinTollRefundCutoff3,
            defaultJoinTollRefundBps3,
            defaultJoinTollRefundBps4,
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
            dAppInfo.functionRoot,
            initialJoinToll
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
        bytes32 functionRoot,
        uint256 initialJoinToll
    ) private view {
        address manager = address(channelManager);
        if (
            manager.code.length == 0 || channelManager.bridgeCore() != address(this)
                || channelManager.channelId() != channelId || channelManager.dappId() != dappId
                || channelManager.leader() != leader
                || channelManager.channelTokenVaultTreeIndex() != channelTokenVaultTreeIndex
                || channelManager.dappMetadataDigestSchema() != dappMetadataDigestSchema
                || channelManager.dappMetadataDigest() != dappMetadataDigest
                || channelManager.functionRoot() != functionRoot
                || address(channelManager.grothVerifier()) != verifierSnapshot.grothVerifier
                || keccak256(bytes(channelManager.grothVerifierCompatibleBackendVersion()))
                    != keccak256(bytes(verifierSnapshot.grothVerifierCompatibleBackendVersion))
                || address(channelManager.tokamakVerifier()) != verifierSnapshot.tokamakVerifier
                || keccak256(bytes(channelManager.tokamakVerifierCompatibleBackendVersion()))
                    != keccak256(bytes(verifierSnapshot.tokamakVerifierCompatibleBackendVersion))
                || channelManager.joinToll() != initialJoinToll
                || channelManager.joinTollRefundCutoff1() != defaultJoinTollRefundCutoff1
                || channelManager.joinTollRefundBps1() != defaultJoinTollRefundBps1
                || channelManager.joinTollRefundCutoff2() != defaultJoinTollRefundCutoff2
                || channelManager.joinTollRefundBps2() != defaultJoinTollRefundBps2
                || channelManager.joinTollRefundCutoff3() != defaultJoinTollRefundCutoff3
                || channelManager.joinTollRefundBps3() != defaultJoinTollRefundBps3
                || channelManager.joinTollRefundBps4() != defaultJoinTollRefundBps4
        ) {
            revert InvalidChannelManager(manager);
        }
    }

    function _setJoinTollRefundSchedule(
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
            revert InvalidJoinTollRefundSchedule();
        }

        defaultJoinTollRefundCutoff1 = cutoff1;
        defaultJoinTollRefundCutoff2 = cutoff2;
        defaultJoinTollRefundCutoff3 = cutoff3;
        defaultJoinTollRefundBps1 = bps1;
        defaultJoinTollRefundBps2 = bps2;
        defaultJoinTollRefundBps3 = bps3;
        defaultJoinTollRefundBps4 = bps4;

        emit JoinTollRefundScheduleUpdated(cutoff1, bps1, cutoff2, bps2, cutoff3, bps3, bps4);
    }
}
