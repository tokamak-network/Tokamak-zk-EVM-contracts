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

    error AlreadyRegistered(address user);
    error NotRegistered(address user);
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

    IERC20 public asset;
    IGrothVerifier public grothVerifier;
    IChannelRegistry public channelRegistry;

    mapping(address => BridgeStructs.BridgeBalanceAccount) private _accounts;

    event BridgeAccountRegistered(address indexed user);
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

    function registerAndFund(uint256 amount) external nonReentrant {
        if (_accounts[msg.sender].exists) revert AlreadyRegistered(msg.sender);
        if (amount == 0) revert InvalidAmount();

        _accounts[msg.sender] = BridgeStructs.BridgeBalanceAccount({exists: true, availableBalance: amount});

        _pullAsset(msg.sender, amount);

        emit BridgeAccountRegistered(msg.sender);
        emit AssetsFunded(msg.sender, amount);
    }

    function fund(uint256 amount) external nonReentrant {
        BridgeStructs.BridgeBalanceAccount storage account = _requireAccount(msg.sender);
        if (amount == 0) revert InvalidAmount();

        account.availableBalance += amount;

        _pullAsset(msg.sender, amount);
        emit AssetsFunded(msg.sender, amount);
    }

    function deposit(uint256 channelId, BridgeStructs.GrothProof calldata proof, BridgeStructs.GrothUpdate calldata update)
        external
        nonReentrant
        returns (bool)
    {
        BridgeStructs.BridgeBalanceAccount storage account = _requireAccount(msg.sender);
        ChannelManager channelManager = _requireChannelManager(channelId);
        BridgeStructs.TokenVaultRegistration memory registration =
            _requireChannelRegistration(channelManager, msg.sender, channelId);
        bytes32 currentRoot = _currentTokenVaultRoot(channelManager, update);

        _requireL2ValueInField(update.currentUserValue);
        _requireL2ValueInField(update.updatedUserValue);
        if (update.currentUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.updatedUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.updatedUserValue <= update.currentUserValue) revert InvalidAmount();

        uint256 amount = update.updatedUserValue - update.currentUserValue;
        if (account.availableBalance < amount) revert InsufficientAvailableBalance();

        bool ok = grothVerifier.verifyProof(proof.pA, proof.pB, proof.pC, _toPublicSignals(currentRoot, update));
        if (!ok) revert GrothProofRejected();

        account.availableBalance -= amount;

        channelManager.applyVaultUpdate(
            update.currentRootVector,
            update.updatedRoot,
            registration.leafIndex,
            _encodeTokenVaultLeaf(update.updatedUserValue)
        );

        emit StorageWriteObserved(
            channelManager.tokenVaultStorageAddress(), uint256(registration.l2TokenVaultKey), update.updatedUserValue
        );
        return true;
    }

    function withdraw(
        uint256 channelId,
        BridgeStructs.GrothProof calldata proof,
        BridgeStructs.GrothUpdate calldata update
    ) external nonReentrant returns (bool) {
        BridgeStructs.BridgeBalanceAccount storage account = _requireAccount(msg.sender);
        ChannelManager channelManager = _requireChannelManager(channelId);
        BridgeStructs.TokenVaultRegistration memory registration =
            _requireChannelRegistration(channelManager, msg.sender, channelId);
        bytes32 currentRoot = _currentTokenVaultRoot(channelManager, update);

        _requireL2ValueInField(update.currentUserValue);
        _requireL2ValueInField(update.updatedUserValue);
        if (update.currentUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.updatedUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.currentUserValue <= update.updatedUserValue) revert InvalidAmount();

        uint256 amount = update.currentUserValue - update.updatedUserValue;

        bool ok = grothVerifier.verifyProof(proof.pA, proof.pB, proof.pC, _toPublicSignals(currentRoot, update));
        if (!ok) revert GrothProofRejected();

        account.availableBalance += amount;

        channelManager.applyVaultUpdate(
            update.currentRootVector,
            update.updatedRoot,
            registration.leafIndex,
            _encodeTokenVaultLeaf(update.updatedUserValue)
        );

        emit StorageWriteObserved(
            channelManager.tokenVaultStorageAddress(), uint256(registration.l2TokenVaultKey), update.updatedUserValue
        );
        return true;
    }

    function claimToWallet(uint256 amount) external nonReentrant {
        BridgeStructs.BridgeBalanceAccount storage account = _requireAccount(msg.sender);
        if (amount == 0) revert InvalidAmount();
        if (account.availableBalance < amount) revert InsufficientAvailableBalance();

        account.availableBalance -= amount;

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

    function getAccount(address user) external view returns (BridgeStructs.BridgeBalanceAccount memory) {
        return _accounts[user];
    }

    function encodeTokenVaultLeaf(bytes32, uint256 userValue) external pure returns (bytes32) {
        return _encodeTokenVaultLeaf(userValue);
    }

    function _requireAccount(address user)
        private
        view
        returns (BridgeStructs.BridgeBalanceAccount storage account)
    {
        account = _accounts[user];
        if (!account.exists) revert NotRegistered(user);
    }

    function _requireChannelManager(uint256 channelId) private view returns (ChannelManager channelManager) {
        address channelManagerAddress = channelRegistry.getChannelManager(channelId);
        if (channelManagerAddress == address(0)) revert UnknownChannel(channelId);
        channelManager = ChannelManager(channelManagerAddress);
    }

    function _requireChannelRegistration(ChannelManager channelManager, address user, uint256 channelId)
        private
        view
        returns (BridgeStructs.TokenVaultRegistration memory registration)
    {
        registration = channelManager.getTokenVaultRegistration(user);
        if (!registration.exists) revert NotRegisteredInChannel(user, channelId);
    }

    function _pullAsset(address from, uint256 amount) private {
        uint256 vaultBalanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(from, address(this), amount);
        uint256 vaultBalanceDelta = asset.balanceOf(address(this)) - vaultBalanceBefore;
        if (vaultBalanceDelta != amount) {
            revert UnsupportedAssetTransferBehavior(amount, vaultBalanceDelta);
        }
    }

    function _requireL2ValueInField(uint256 value) private pure {
        if (value >= BLS12_381_SCALAR_FIELD_MODULUS) {
            revert L2ValueOutOfRange(value);
        }
    }

    function _currentTokenVaultRoot(ChannelManager channelManager, BridgeStructs.GrothUpdate calldata update)
        private
        view
        returns (bytes32)
    {
        return update.currentRootVector[channelManager.tokenVaultTreeIndex()];
    }

    function _toPublicSignals(bytes32 currentRoot, BridgeStructs.GrothUpdate calldata update)
        private
        pure
        returns (uint256[5] memory pubSignals)
    {
        pubSignals[0] = uint256(currentRoot);
        pubSignals[1] = uint256(update.updatedRoot);
        pubSignals[2] = uint256(update.updatedUserKey);
        pubSignals[3] = update.currentUserValue;
        pubSignals[4] = update.updatedUserValue;
    }

    function _encodeTokenVaultLeaf(uint256 userValue) private pure returns (bytes32) {
        return bytes32(userValue);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
