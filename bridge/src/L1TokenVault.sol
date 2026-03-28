// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {BridgeStructs} from "./BridgeStructs.sol";
import {ChannelManager} from "./ChannelManager.sol";
import {IGrothVerifier} from "./interfaces/IGrothVerifier.sol";
import {IChannelRegistry} from "./interfaces/IChannelRegistry.sol";

contract L1TokenVault is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    uint256 internal constant BLS12_381_SCALAR_FIELD_MODULUS =
        0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    error InvalidAmount();
    error KeyMismatch();
    error InsufficientAvailableBalance();
    error L2ValueOutOfRange(uint256 value);
    error GrothProofRejected();
    error InvalidAsset();
    error InvalidGrothVerifier();
    error InvalidChannelRegistry();
    error UnknownChannel(uint256 channelId);
    error UnsupportedAssetTransferBehavior(uint256 expectedDelta, uint256 actualDelta);
    error NotRegisteredInChannel(address user, uint256 channelId);

    struct ChannelVaultUpdateContext {
        ChannelManager channelManager;
        BridgeStructs.ChannelTokenVaultRegistration registration;
        bytes32 currentRoot;
    }

    IERC20 public asset;
    IGrothVerifier public grothVerifier;
    IChannelRegistry public channelRegistry;

    mapping(address => uint256) private _availableBalances;

    event AssetsFunded(address indexed user, uint256 amount);
    event StorageWriteObserved(address indexed storageAddr, uint256 storageKey, uint256 value);
    event AssetsClaimed(address indexed user, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        IERC20 asset_,
        IGrothVerifier grothVerifier_,
        IChannelRegistry channelRegistry_
    ) external initializer {
        if (address(asset_) == address(0)) revert InvalidAsset();
        if (address(grothVerifier_) == address(0)) revert InvalidGrothVerifier();
        if (address(channelRegistry_) == address(0)) revert InvalidChannelRegistry();

        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        if (initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }

        asset = asset_;
        grothVerifier = grothVerifier_;
        channelRegistry = channelRegistry_;
    }

    function fund(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        _availableBalances[msg.sender] += amount;
        uint256 vaultBalanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        uint256 vaultBalanceDelta = asset.balanceOf(address(this)) - vaultBalanceBefore;
        if (vaultBalanceDelta != amount) {
            revert UnsupportedAssetTransferBehavior(amount, vaultBalanceDelta);
        }

        emit AssetsFunded(msg.sender, amount);
    }

    function deposit(uint256 channelId, BridgeStructs.GrothProof calldata proof, BridgeStructs.GrothUpdate calldata update)
        external
        nonReentrant
        returns (bool)
    {
        ChannelVaultUpdateContext memory context = _prepareChannelVaultUpdate(channelId, msg.sender, update);
        if (update.updatedUserValue <= update.currentUserValue) revert InvalidAmount();

        uint256 amount = update.updatedUserValue - update.currentUserValue;
        if (_availableBalances[msg.sender] < amount) revert InsufficientAvailableBalance();

        _availableBalances[msg.sender] -= amount;
        _verifyAndApplyChannelVaultUpdate(context, proof, update);
        return true;
    }

    function withdraw(
        uint256 channelId,
        BridgeStructs.GrothProof calldata proof,
        BridgeStructs.GrothUpdate calldata update
    ) external nonReentrant returns (bool) {
        ChannelVaultUpdateContext memory context = _prepareChannelVaultUpdate(channelId, msg.sender, update);
        if (update.currentUserValue <= update.updatedUserValue) revert InvalidAmount();

        uint256 amount = update.currentUserValue - update.updatedUserValue;
        _availableBalances[msg.sender] += amount;
        _verifyAndApplyChannelVaultUpdate(context, proof, update);
        return true;
    }

    function claimToWallet(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (_availableBalances[msg.sender] < amount) revert InsufficientAvailableBalance();

        _availableBalances[msg.sender] -= amount;

        uint256 vaultBalanceBefore = asset.balanceOf(address(this));
        uint256 recipientBalanceBefore = asset.balanceOf(msg.sender);
        asset.safeTransfer(msg.sender, amount);
        uint256 vaultBalanceDelta = vaultBalanceBefore - asset.balanceOf(address(this));
        if (vaultBalanceDelta != amount) {
            revert UnsupportedAssetTransferBehavior(amount, vaultBalanceDelta);
        }
        uint256 recipientBalanceDelta = asset.balanceOf(msg.sender) - recipientBalanceBefore;
        if (recipientBalanceDelta != amount) {
            revert UnsupportedAssetTransferBehavior(amount, recipientBalanceDelta);
        }
        emit AssetsClaimed(msg.sender, amount);
    }

    function availableBalanceOf(address user) external view returns (uint256) {
        return _availableBalances[user];
    }

    function _requireL2ValueInField(uint256 value) private pure {
        if (value >= BLS12_381_SCALAR_FIELD_MODULUS) {
            revert L2ValueOutOfRange(value);
        }
    }

    function _prepareChannelVaultUpdate(uint256 channelId, address user, BridgeStructs.GrothUpdate calldata update)
        private
        view
        returns (ChannelVaultUpdateContext memory context)
    {
        address channelManagerAddress = channelRegistry.getChannelManager(channelId);
        if (channelManagerAddress == address(0)) revert UnknownChannel(channelId);
        context.channelManager = ChannelManager(channelManagerAddress);
        context.registration = context.channelManager.getChannelTokenVaultRegistration(user);
        if (!context.registration.exists) revert NotRegisteredInChannel(user, channelId);
        context.currentRoot = update.currentRootVector[context.channelManager.channelTokenVaultTreeIndex()];

        _requireL2ValueInField(update.currentUserValue);
        _requireL2ValueInField(update.updatedUserValue);
        if (update.currentUserKey != context.registration.channelTokenVaultKey) revert KeyMismatch();
        if (update.updatedUserKey != context.registration.channelTokenVaultKey) revert KeyMismatch();
    }

    function _verifyAndApplyChannelVaultUpdate(
        ChannelVaultUpdateContext memory context,
        BridgeStructs.GrothProof calldata proof,
        BridgeStructs.GrothUpdate calldata update
    ) private {
        uint256[5] memory publicSignals;
        publicSignals[0] = uint256(context.currentRoot);
        publicSignals[1] = uint256(update.updatedRoot);
        publicSignals[2] = uint256(update.updatedUserKey);
        publicSignals[3] = update.currentUserValue;
        publicSignals[4] = update.updatedUserValue;

        bool ok = grothVerifier.verifyProof(proof.pA, proof.pB, proof.pC, publicSignals);
        if (!ok) revert GrothProofRejected();

        context.channelManager.applyVaultUpdate(
            update.currentRootVector,
            update.updatedRoot,
            context.registration.leafIndex,
            bytes32(update.updatedUserValue)
        );

        emit StorageWriteObserved(
            context.channelManager.channelTokenVaultStorageAddress(),
            uint256(context.registration.channelTokenVaultKey),
            update.updatedUserValue
        );
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
