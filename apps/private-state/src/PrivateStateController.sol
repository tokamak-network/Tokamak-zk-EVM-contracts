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
    error UnknownCommitment(bytes32 commitment);
    error InputOutputValueMismatch(uint256 inputValue, uint256 outputValue);
    error AuthorizationExpired(uint256 deadline);
    error MissingAuthorization(bytes32 commitment);
    error InvalidAuthorization(bytes32 commitment, address recoveredSigner, address expectedSigner);

    bytes32 private constant TRANSFER_NOTE_TYPEHASH = keccak256(
        "TransferNote(uint256 chainId,address controller,bytes32 inputCommitment,bytes32 outputsHash,uint256 deadline)"
    );
    bytes32 private constant REDEEM_NOTE_TYPEHASH = keccak256(
        "RedeemNote(uint256 chainId,address controller,bytes32 inputCommitment,address receiver,uint256 deadline)"
    );

    struct InputNote {
        uint256 value;
        address owner;
        bytes32 salt;
    }

    struct OutputNote {
        address owner;
        uint256 value;
        bytes32 salt;
    }

    struct SpendAuthorization {
        uint256 deadline;
        bytes signature;
    }

    event TokenDeposited(address indexed payer, address indexed beneficiary, address indexed token, uint256 amount);
    event NoteMinted(
        address indexed liquidBalanceOwner, bytes32 indexed commitment, address indexed noteOwner, uint256 amount
    );
    event NotesTransferred(address indexed operator, uint256 inputCount, uint256 outputCount);
    event NotesRedeemed(address indexed operator, address indexed receiver, uint256 inputCount);
    event TokenWithdrawn(address indexed account, address indexed receiver, uint256 amount);

    PrivateNullifierRegistry public immutable nullifierStore;
    PrivateNoteRegistry public immutable noteRegistry;
    TokenVault public immutable tokenVault;
    address public immutable tokamakNetworkToken;

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
        tokamakNetworkToken = address(tokenVault_.tokamakNetworkToken());
    }

    function depositToken(uint256 amount) external {
        depositTokenFor(amount, msg.sender);
    }

    function depositTokenFor(uint256 amount, address beneficiary) public nonReentrant {
        tokenVault.deposit(msg.sender, beneficiary, amount);
        emit TokenDeposited(msg.sender, beneficiary, tokamakNetworkToken, amount);
    }

    function mintNote(uint256 amount, address noteOwner, bytes32 salt)
        external
        nonReentrant
        returns (bytes32 commitment)
    {
        _validateNoteFields(amount, noteOwner);

        tokenVault.debitLiquidBalance(msg.sender, amount);
        commitment = computeNoteCommitment(amount, noteOwner, salt);
        noteRegistry.registerCommitment(commitment);

        emit NoteMinted(msg.sender, commitment, noteOwner, amount);
    }

    function transferNotes(
        InputNote[] calldata inputNotes,
        SpendAuthorization[] calldata authorizations,
        OutputNote[] calldata outputs
    ) external nonReentrant returns (bytes32[] memory nullifiers, bytes32[] memory outputCommitments) {
        if (inputNotes.length == 0 || outputs.length == 0) {
            revert EmptyArray();
        }
        if (inputNotes.length != authorizations.length) {
            revert ArrayLengthMismatch(inputNotes.length, authorizations.length);
        }

        _validateNoteFields(inputNotes[0].value, inputNotes[0].owner);

        bytes32 outputsHash = hashTransferOutputs(outputs);
        uint256 totalOutputValue;
        for (uint256 i = 0; i < outputs.length; ++i) {
            _validateOutputNote(outputs[i]);
            totalOutputValue += outputs[i].value;
        }

        uint256 totalInputValue;
        bytes32[] memory inputCommitments = new bytes32[](inputNotes.length);
        nullifiers = new bytes32[](inputNotes.length);
        for (uint256 i = 0; i < inputNotes.length; ++i) {
            InputNote calldata note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 commitment = computeNoteCommitment(note.value, note.owner, note.salt);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _verifyTransferAuthorization(commitment, note.owner, outputsHash, authorizations[i]);
            inputCommitments[i] = commitment;
            nullifiers[i] = computeNullifier(note.value, note.owner, note.salt);
            totalInputValue += note.value;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < inputCommitments.length; ++i) {
            nullifierStore.useNullifier(nullifiers[i], inputCommitments[i], msg.sender);
        }

        outputCommitments = new bytes32[](outputs.length);
        for (uint256 i = 0; i < outputs.length; ++i) {
            outputCommitments[i] = computeNoteCommitment(outputs[i].value, outputs[i].owner, outputs[i].salt);
            noteRegistry.registerCommitment(outputCommitments[i]);
        }

        emit NotesTransferred(msg.sender, inputNotes.length, outputs.length);
    }

    function redeemNotes(
        InputNote[] calldata inputNotes,
        SpendAuthorization[] calldata authorizations,
        address receiver
    ) external nonReentrant returns (bytes32[] memory nullifiers) {
        if (inputNotes.length == 0) {
            revert EmptyArray();
        }
        if (inputNotes.length != authorizations.length) {
            revert ArrayLengthMismatch(inputNotes.length, authorizations.length);
        }
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        bytes32[] memory inputCommitments = new bytes32[](inputNotes.length);
        nullifiers = new bytes32[](inputNotes.length);
        for (uint256 i = 0; i < inputNotes.length; ++i) {
            InputNote calldata note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 commitment = computeNoteCommitment(note.value, note.owner, note.salt);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _verifyRedeemAuthorization(commitment, note.owner, receiver, authorizations[i]);
            inputCommitments[i] = commitment;
            nullifiers[i] = computeNullifier(note.value, note.owner, note.salt);
        }

        for (uint256 i = 0; i < inputNotes.length; ++i) {
            nullifierStore.useNullifier(nullifiers[i], inputCommitments[i], msg.sender);
            tokenVault.creditLiquidBalance(receiver, inputNotes[i].value);
        }

        emit NotesRedeemed(msg.sender, receiver, inputNotes.length);
    }

    function withdrawToken(uint256 amount, address receiver) external nonReentrant {
        tokenVault.withdraw(msg.sender, receiver, amount);
        emit TokenWithdrawn(msg.sender, receiver, amount);
    }

    function hashTransferOutputs(OutputNote[] calldata outputs) public pure returns (bytes32) {
        if (outputs.length == 0) {
            revert EmptyArray();
        }

        bytes32 rollingHash = keccak256(abi.encodePacked(outputs.length));
        for (uint256 i = 0; i < outputs.length; ++i) {
            rollingHash = keccak256(abi.encodePacked(rollingHash, outputs[i].owner, outputs[i].value, outputs[i].salt));
        }

        return rollingHash;
    }

    function computeNoteCommitment(uint256 value, address owner, bytes32 salt) public view returns (bytes32) {
        _validateNoteFields(value, owner);
        return keccak256(abi.encode(block.chainid, address(noteRegistry), tokamakNetworkToken, value, owner, salt));
    }

    function computeNullifier(uint256 value, address owner, bytes32 salt) public view returns (bytes32) {
        _validateNoteFields(value, owner);
        return keccak256(abi.encode(block.chainid, address(nullifierStore), tokamakNetworkToken, value, owner, salt));
    }

    function getTransferAuthorizationHash(bytes32 inputCommitment, bytes32 outputsHash, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        return keccak256(
                abi.encode(TRANSFER_NOTE_TYPEHASH, block.chainid, address(this), inputCommitment, outputsHash, deadline)
            ).toEthSignedMessageHash();
    }

    function getRedeemAuthorizationHash(bytes32 inputCommitment, address receiver, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        return keccak256(
                abi.encode(REDEEM_NOTE_TYPEHASH, block.chainid, address(this), inputCommitment, receiver, deadline)
            ).toEthSignedMessageHash();
    }

    function _verifyTransferAuthorization(
        bytes32 inputCommitment,
        address owner,
        bytes32 outputsHash,
        SpendAuthorization calldata authorization
    ) internal view {
        if (msg.sender == owner) {
            return;
        }

        if (authorization.signature.length == 0) {
            revert MissingAuthorization(inputCommitment);
        }
        if (authorization.deadline < block.timestamp) {
            revert AuthorizationExpired(authorization.deadline);
        }

        address recoveredSigner = getTransferAuthorizationHash(inputCommitment, outputsHash, authorization.deadline)
            .recover(authorization.signature);
        if (recoveredSigner != owner) {
            revert InvalidAuthorization(inputCommitment, recoveredSigner, owner);
        }
    }

    function _verifyRedeemAuthorization(
        bytes32 inputCommitment,
        address owner,
        address receiver,
        SpendAuthorization calldata authorization
    ) internal view {
        if (msg.sender == owner) {
            return;
        }

        if (authorization.signature.length == 0) {
            revert MissingAuthorization(inputCommitment);
        }
        if (authorization.deadline < block.timestamp) {
            revert AuthorizationExpired(authorization.deadline);
        }

        address recoveredSigner = getRedeemAuthorizationHash(inputCommitment, receiver, authorization.deadline)
            .recover(authorization.signature);
        if (recoveredSigner != owner) {
            revert InvalidAuthorization(inputCommitment, recoveredSigner, owner);
        }
    }

    function _validateNoteFields(uint256 value, address owner) internal pure {
        if (owner == address(0)) {
            revert ZeroAddress();
        }
        if (value == 0) {
            revert ZeroAmount();
        }
    }

    function _validateOutputNote(OutputNote calldata output) internal pure {
        if (output.owner == address(0)) {
            revert ZeroAddress();
        }
        if (output.value == 0) {
            revert ZeroAmount();
        }
    }
}
