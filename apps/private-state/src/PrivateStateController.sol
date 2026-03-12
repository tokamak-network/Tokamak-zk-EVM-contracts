// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/utils/cryptography/MessageHashUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {PrivateNullifierRegistry} from "./PrivateNullifierRegistry.sol";
import {PrivateNoteRegistry} from "./PrivateNoteRegistry.sol";
import {TokenVault} from "./TokenVault.sol";

/// @title PrivateStateController
/// @notice User-facing application logic for the non-private zk-note DApp.
contract PrivateStateController is ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error EmptyArray();
    error ArrayLengthMismatch(uint256 expected, uint256 actual);
    error ZeroAddress();
    error ZeroAmount();
    error MixedNoteTokens(address expected, address actual);
    error InputOutputValueMismatch(uint256 inputValue, uint256 outputValue);
    error AuthorizationExpired(uint256 deadline);
    error MissingAuthorization(uint256 noteId);
    error InvalidAuthorization(uint256 noteId, address recoveredSigner, address expectedSigner);

    bytes32 private constant TRANSFER_NOTE_TYPEHASH = keccak256(
        "TransferNote(uint256 chainId,address controller,uint256 noteId,bytes32 outputsHash,uint256 deadline)"
    );
    bytes32 private constant REDEEM_NOTE_TYPEHASH =
        keccak256("RedeemNote(uint256 chainId,address controller,uint256 noteId,address receiver,uint256 deadline)");

    struct OutputNote {
        address owner;
        uint256 value;
        bytes32 salt;
        uint256 nullifierNonce;
    }

    struct SpendAuthorization {
        uint256 deadline;
        bytes signature;
    }

    event TokenDeposited(address indexed payer, address indexed beneficiary, address indexed token, uint256 amount);
    event NoteMinted(
        address indexed liquidBalanceOwner,
        uint256 indexed noteId,
        address indexed noteOwner,
        address token,
        uint256 amount,
        bytes32 commitment
    );
    event NotesTransferred(address indexed operator, address indexed token, uint256 inputCount, uint256 outputCount);
    event NotesRedeemed(address indexed operator, address indexed receiver, uint256 inputCount);
    event TokenWithdrawn(address indexed account, address indexed receiver, address indexed token, uint256 amount);

    PrivateNullifierRegistry public immutable nullifierStore;
    PrivateNoteRegistry public immutable noteRegistry;
    TokenVault public immutable tokenVault;

    constructor(PrivateNoteRegistry noteRegistry_, PrivateNullifierRegistry nullifierStore_, TokenVault tokenVault_) {
        if (
            address(noteRegistry_) == address(0) || address(nullifierStore_) == address(0)
                || address(tokenVault_) == address(0)
        ) {
            revert ZeroAddress();
        }

        nullifierStore = nullifierStore_;
        noteRegistry = noteRegistry_;
        tokenVault = tokenVault_;
    }

    function depositToken(address token, uint256 amount) external {
        depositTokenFor(token, amount, msg.sender);
    }

    function depositTokenFor(address token, uint256 amount, address beneficiary) public nonReentrant {
        tokenVault.deposit(token, msg.sender, beneficiary, amount);
        emit TokenDeposited(msg.sender, beneficiary, token, amount);
    }

    function mintNote(address token, uint256 amount, address noteOwner, bytes32 salt, uint256 nullifierNonce)
        external
        nonReentrant
        returns (uint256 noteId, bytes32 commitment)
    {
        if (noteOwner == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        tokenVault.debitLiquidBalance(msg.sender, token, amount);
        (noteId, commitment) = noteRegistry.createNote(token, amount, noteOwner, salt, nullifierNonce);

        emit NoteMinted(msg.sender, noteId, noteOwner, token, amount, commitment);
    }

    function transferNotes(
        uint256[] calldata inputNoteIds,
        SpendAuthorization[] calldata authorizations,
        OutputNote[] calldata outputs
    )
        external
        nonReentrant
        returns (bytes32[] memory nullifiers, uint256[] memory outputNoteIds, bytes32[] memory commitments)
    {
        if (inputNoteIds.length == 0 || outputs.length == 0) {
            revert EmptyArray();
        }
        if (inputNoteIds.length != authorizations.length) {
            revert ArrayLengthMismatch(inputNoteIds.length, authorizations.length);
        }

        PrivateNoteRegistry.Note memory firstNote = noteRegistry.getNote(inputNoteIds[0]);
        address token = firstNote.token;
        bytes32 outputsHash = hashTransferOutputs(token, outputs);

        uint256 totalOutputValue;
        for (uint256 i = 0; i < outputs.length; ++i) {
            if (outputs[i].owner == address(0)) {
                revert ZeroAddress();
            }
            if (outputs[i].value == 0) {
                revert ZeroAmount();
            }

            totalOutputValue += outputs[i].value;
        }

        uint256 totalInputValue;
        nullifiers = new bytes32[](inputNoteIds.length);
        for (uint256 i = 0; i < inputNoteIds.length; ++i) {
            PrivateNoteRegistry.Note memory note = noteRegistry.getNote(inputNoteIds[i]);
            if (note.token != token) {
                revert MixedNoteTokens(token, note.token);
            }

            _verifyTransferAuthorization(inputNoteIds[i], note.owner, outputsHash, authorizations[i]);
            totalInputValue += note.value;
            nullifiers[i] =
                noteRegistry.computeNullifier(inputNoteIds[i], note.commitment, note.owner, note.nullifierNonce);
            nullifierStore.useNullifier(nullifiers[i], inputNoteIds[i], msg.sender);
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        outputNoteIds = new uint256[](outputs.length);
        commitments = new bytes32[](outputs.length);
        for (uint256 i = 0; i < outputs.length; ++i) {
            (outputNoteIds[i], commitments[i]) = noteRegistry.createNote(
                token, outputs[i].value, outputs[i].owner, outputs[i].salt, outputs[i].nullifierNonce
            );
        }

        emit NotesTransferred(msg.sender, token, inputNoteIds.length, outputs.length);
    }

    function redeemNotes(
        uint256[] calldata inputNoteIds,
        SpendAuthorization[] calldata authorizations,
        address receiver
    ) external nonReentrant returns (bytes32[] memory nullifiers) {
        if (inputNoteIds.length == 0) {
            revert EmptyArray();
        }
        if (inputNoteIds.length != authorizations.length) {
            revert ArrayLengthMismatch(inputNoteIds.length, authorizations.length);
        }
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        nullifiers = new bytes32[](inputNoteIds.length);
        for (uint256 i = 0; i < inputNoteIds.length; ++i) {
            PrivateNoteRegistry.Note memory note = noteRegistry.getNote(inputNoteIds[i]);
            _verifyRedeemAuthorization(inputNoteIds[i], note.owner, receiver, authorizations[i]);

            nullifiers[i] =
                noteRegistry.computeNullifier(inputNoteIds[i], note.commitment, note.owner, note.nullifierNonce);
            nullifierStore.useNullifier(nullifiers[i], inputNoteIds[i], msg.sender);
            tokenVault.creditLiquidBalance(receiver, note.token, note.value);
        }

        emit NotesRedeemed(msg.sender, receiver, inputNoteIds.length);
    }

    function withdrawToken(address token, uint256 amount, address receiver) external nonReentrant {
        tokenVault.withdraw(token, msg.sender, receiver, amount);
        emit TokenWithdrawn(msg.sender, receiver, token, amount);
    }

    function hashTransferOutputs(address token, OutputNote[] calldata outputs) public pure returns (bytes32) {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (outputs.length == 0) {
            revert EmptyArray();
        }

        bytes32 rollingHash = keccak256(abi.encodePacked(token, outputs.length));
        for (uint256 i = 0; i < outputs.length; ++i) {
            rollingHash = keccak256(
                abi.encodePacked(
                    rollingHash, outputs[i].owner, outputs[i].value, outputs[i].salt, outputs[i].nullifierNonce
                )
            );
        }

        return rollingHash;
    }

    function getTransferAuthorizationHash(uint256 noteId, bytes32 outputsHash, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        return keccak256(
                abi.encode(TRANSFER_NOTE_TYPEHASH, block.chainid, address(this), noteId, outputsHash, deadline)
            ).toEthSignedMessageHash();
    }

    function getRedeemAuthorizationHash(uint256 noteId, address receiver, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        return keccak256(abi.encode(REDEEM_NOTE_TYPEHASH, block.chainid, address(this), noteId, receiver, deadline))
            .toEthSignedMessageHash();
    }

    function _verifyTransferAuthorization(
        uint256 noteId,
        address owner,
        bytes32 outputsHash,
        SpendAuthorization calldata authorization
    ) internal view {
        if (msg.sender == owner) {
            return;
        }

        if (authorization.signature.length == 0) {
            revert MissingAuthorization(noteId);
        }
        if (authorization.deadline < block.timestamp) {
            revert AuthorizationExpired(authorization.deadline);
        }

        address recoveredSigner =
            getTransferAuthorizationHash(noteId, outputsHash, authorization.deadline).recover(authorization.signature);
        if (recoveredSigner != owner) {
            revert InvalidAuthorization(noteId, recoveredSigner, owner);
        }
    }

    function _verifyRedeemAuthorization(
        uint256 noteId,
        address owner,
        address receiver,
        SpendAuthorization calldata authorization
    ) internal view {
        if (msg.sender == owner) {
            return;
        }

        if (authorization.signature.length == 0) {
            revert MissingAuthorization(noteId);
        }
        if (authorization.deadline < block.timestamp) {
            revert AuthorizationExpired(authorization.deadline);
        }

        address recoveredSigner =
            getRedeemAuthorizationHash(noteId, receiver, authorization.deadline).recover(authorization.signature);
        if (recoveredSigner != owner) {
            revert InvalidAuthorization(noteId, recoveredSigner, owner);
        }
    }
}
