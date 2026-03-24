// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {BridgeStructs} from "./BridgeStructs.sol";
import {ChannelManager} from "./ChannelManager.sol";
import {IGrothVerifier} from "./interfaces/IGrothVerifier.sol";

interface IVaultKeyRegistry {
    function reserveVaultKey(uint256 channelId, address user, bytes32 key) external returns (uint256);
}

contract L1TokenVault is ReentrancyGuard {
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
    error UnsupportedAssetTransferBehavior(uint256 expectedDelta, uint256 actualDelta);

    struct VaultRegistration {
        bool exists;
        bytes32 l2TokenVaultKey;
        uint256 leafIndex;
        uint256 availableBalance;
    }

    uint256 public immutable channelId;
    IERC20 public immutable asset;
    ChannelManager public immutable channelManager;
    IGrothVerifier public immutable grothVerifier;
    IVaultKeyRegistry public immutable keyRegistry;

    mapping(address => VaultRegistration) private _registrations;
    mapping(uint256 => address) public registeredUserAtLeafIndex;

    event UserRegistered(address indexed user, bytes32 indexed key, uint256 leafIndex);
    event AssetsFunded(address indexed user, uint256 amount);
    event StorageWriteObserved(address indexed storageAddr, uint256 storageKey, uint256 value);
    event AssetsClaimed(address indexed user, uint256 amount);

    constructor(
        uint256 channelId_,
        IERC20 asset_,
        ChannelManager channelManager_,
        IGrothVerifier grothVerifier_,
        IVaultKeyRegistry keyRegistry_
    ) {
        channelId = channelId_;
        asset = asset_;
        channelManager = channelManager_;
        grothVerifier = grothVerifier_;
        keyRegistry = keyRegistry_;
    }

    function registerAndFund(bytes32 l2TokenVaultKey, uint256 amount) external nonReentrant {
        if (_registrations[msg.sender].exists) revert AlreadyRegistered(msg.sender);
        if (amount == 0) revert InvalidAmount();

        uint256 leafIndex = keyRegistry.reserveVaultKey(channelId, msg.sender, l2TokenVaultKey);

        _registrations[msg.sender] = VaultRegistration({
            exists: true,
            l2TokenVaultKey: l2TokenVaultKey,
            leafIndex: leafIndex,
            availableBalance: amount
        });
        registeredUserAtLeafIndex[leafIndex] = msg.sender;

        _pullAsset(msg.sender, amount);

        emit UserRegistered(msg.sender, l2TokenVaultKey, leafIndex);
        emit AssetsFunded(msg.sender, amount);
    }

    function fund(uint256 amount) external nonReentrant {
        VaultRegistration storage registration = _requireRegistration(msg.sender);
        if (amount == 0) revert InvalidAmount();

        registration.availableBalance += amount;

        _pullAsset(msg.sender, amount);
        emit AssetsFunded(msg.sender, amount);
    }

    function deposit(BridgeStructs.GrothProof calldata proof, BridgeStructs.GrothUpdate calldata update)
        external
        nonReentrant
        returns (bool)
    {
        VaultRegistration storage registration = _requireRegistration(msg.sender);
        bytes32 currentRoot = _currentTokenVaultRoot(update);

        _requireL2ValueInField(update.currentUserValue);
        _requireL2ValueInField(update.updatedUserValue);
        if (update.currentUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.updatedUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.updatedUserValue <= update.currentUserValue) revert InvalidAmount();

        uint256 amount = update.updatedUserValue - update.currentUserValue;
        if (registration.availableBalance < amount) revert InsufficientAvailableBalance();

        bool ok = grothVerifier.verifyProof(proof.pA, proof.pB, proof.pC, _toPublicSignals(currentRoot, update));
        if (!ok) revert GrothProofRejected();

        registration.availableBalance -= amount;

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

    function withdraw(BridgeStructs.GrothProof calldata proof, BridgeStructs.GrothUpdate calldata update)
        external
        nonReentrant
        returns (bool)
    {
        VaultRegistration storage registration = _requireRegistration(msg.sender);
        bytes32 currentRoot = _currentTokenVaultRoot(update);

        _requireL2ValueInField(update.currentUserValue);
        _requireL2ValueInField(update.updatedUserValue);
        if (update.currentUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.updatedUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.currentUserValue <= update.updatedUserValue) revert InvalidAmount();

        uint256 amount = update.currentUserValue - update.updatedUserValue;

        bool ok = grothVerifier.verifyProof(proof.pA, proof.pB, proof.pC, _toPublicSignals(currentRoot, update));
        if (!ok) revert GrothProofRejected();

        registration.availableBalance += amount;

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
        VaultRegistration storage registration = _requireRegistration(msg.sender);
        if (amount == 0) revert InvalidAmount();
        if (registration.availableBalance < amount) revert InsufficientAvailableBalance();

        registration.availableBalance -= amount;

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

    function getRegistration(address user) external view returns (VaultRegistration memory) {
        return _registrations[user];
    }

    function encodeTokenVaultLeaf(bytes32, uint256 userValue) external pure returns (bytes32) {
        return _encodeTokenVaultLeaf(userValue);
    }

    function _requireRegistration(address user)
        private
        view
        returns (VaultRegistration storage registration)
    {
        registration = _registrations[user];
        if (!registration.exists) revert NotRegistered(user);
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

    function _currentTokenVaultRoot(BridgeStructs.GrothUpdate calldata update) private view returns (bytes32) {
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

    // The current circuit model treats each token-vault leaf as the raw stored value.
    function _encodeTokenVaultLeaf(uint256 userValue) private pure returns (bytes32) {
        return bytes32(userValue);
    }
}
