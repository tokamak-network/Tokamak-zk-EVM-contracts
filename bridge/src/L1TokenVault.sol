// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {BridgeStructs} from "./BridgeStructs.sol";
import {ChannelManager} from "./ChannelManager.sol";
import {IGrothVerifier} from "./interfaces/IGrothVerifier.sol";

interface IVaultKeyRegistry {
    function reserveVaultKey(uint256 channelId, address user, bytes32 key) external returns (uint256);
}

contract L1TokenVault is ReentrancyGuard {
    error AlreadyRegistered(address user);
    error NotRegistered(address user);
    error InvalidAmount();
    error KeyMismatch();
    error UnexpectedCurrentL2Balance();
    error InsufficientAvailableBalance();
    error GrothProofRejected();

    struct VaultRegistration {
        bool exists;
        bytes32 l2TokenVaultKey;
        uint256 leafIndex;
        uint256 availableBalance;
        uint256 totalCustodyBalance;
        uint256 l2AccountingBalance;
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
    event DepositAccepted(address indexed user, uint256 amount, uint256 leafIndex);
    event WithdrawalAccepted(address indexed user, uint256 amount, uint256 leafIndex);
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
            availableBalance: amount,
            totalCustodyBalance: amount,
            l2AccountingBalance: 0
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
        registration.totalCustodyBalance += amount;

        _pullAsset(msg.sender, amount);
        emit AssetsFunded(msg.sender, amount);
    }

    function deposit(BridgeStructs.GrothProof calldata proof, BridgeStructs.GrothUpdate calldata update)
        external
        nonReentrant
        returns (bool)
    {
        VaultRegistration storage registration = _requireRegistration(msg.sender);

        if (update.updatedUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.currentUserValue != registration.l2AccountingBalance) {
            revert UnexpectedCurrentL2Balance();
        }
        if (update.updatedUserValue <= update.currentUserValue) revert InvalidAmount();

        uint256 amount = update.updatedUserValue - update.currentUserValue;
        if (registration.availableBalance < amount) revert InsufficientAvailableBalance();

        bool ok = grothVerifier.verifyProof(proof.pA, proof.pB, proof.pC, _toPublicSignals(update));
        if (!ok) revert GrothProofRejected();

        registration.availableBalance -= amount;
        registration.l2AccountingBalance = update.updatedUserValue;

        channelManager.applyVaultUpdate(
            update.currentRoot,
            update.updatedRoot,
            registration.leafIndex,
            _mockTokenVaultLeaf(update.updatedUserKey, update.updatedUserValue)
        );

        emit DepositAccepted(msg.sender, amount, registration.leafIndex);
        return true;
    }

    function withdraw(BridgeStructs.GrothProof calldata proof, BridgeStructs.GrothUpdate calldata update)
        external
        nonReentrant
        returns (bool)
    {
        VaultRegistration storage registration = _requireRegistration(msg.sender);

        if (update.currentUserKey != registration.l2TokenVaultKey) revert KeyMismatch();
        if (update.currentUserValue != registration.l2AccountingBalance) {
            revert UnexpectedCurrentL2Balance();
        }
        if (update.currentUserValue <= update.updatedUserValue) revert InvalidAmount();

        uint256 amount = update.currentUserValue - update.updatedUserValue;

        bool ok = grothVerifier.verifyProof(proof.pA, proof.pB, proof.pC, _toPublicSignals(update));
        if (!ok) revert GrothProofRejected();

        registration.availableBalance += amount;
        registration.l2AccountingBalance = update.updatedUserValue;

        channelManager.applyVaultUpdate(
            update.currentRoot,
            update.updatedRoot,
            registration.leafIndex,
            _mockTokenVaultLeaf(update.updatedUserKey, update.updatedUserValue)
        );

        emit WithdrawalAccepted(msg.sender, amount, registration.leafIndex);
        return true;
    }

    function claimToWallet(uint256 amount) external nonReentrant {
        VaultRegistration storage registration = _requireRegistration(msg.sender);
        if (amount == 0) revert InvalidAmount();
        if (registration.availableBalance < amount) revert InsufficientAvailableBalance();

        registration.availableBalance -= amount;
        registration.totalCustodyBalance -= amount;

        require(asset.transfer(msg.sender, amount), "TRANSFER_FAILED");
        emit AssetsClaimed(msg.sender, amount);
    }

    function getRegistration(address user) external view returns (VaultRegistration memory) {
        return _registrations[user];
    }

    function mockTokenVaultLeaf(bytes32 userKey, uint256 userValue) external pure returns (bytes32) {
        return _mockTokenVaultLeaf(userKey, userValue);
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
        require(asset.transferFrom(from, address(this), amount), "TRANSFER_FROM_FAILED");
    }

    function _toPublicSignals(BridgeStructs.GrothUpdate calldata update)
        private
        pure
        returns (uint256[6] memory pubSignals)
    {
        pubSignals[0] = uint256(update.currentRoot);
        pubSignals[1] = uint256(update.updatedRoot);
        pubSignals[2] = uint256(update.currentUserKey);
        pubSignals[3] = update.currentUserValue;
        pubSignals[4] = uint256(update.updatedUserKey);
        pubSignals[5] = update.updatedUserValue;
    }

    // The documents specify Poseidon hashing for the leaf shape but do not provide
    // the production integration details here. This helper is intentionally mocked.
    function _mockTokenVaultLeaf(bytes32 userKey, uint256 userValue) private pure returns (bytes32) {
        return keccak256(abi.encode(userKey, userValue));
    }
}
