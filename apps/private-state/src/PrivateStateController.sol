// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {PrivateNullifierRegistry} from "./PrivateNullifierRegistry.sol";
import {PrivateNoteRegistry} from "./PrivateNoteRegistry.sol";
import {TokenVault} from "./TokenVault.sol";

/// @title PrivateStateController
/// @notice User-facing application logic for the non-private zk-note DApp.
contract PrivateStateController is ReentrancyGuard {
    error EmptyArray();
    error ArrayLengthMismatch(uint256 expected, uint256 actual);
    error ZeroAddress();
    error ZeroAmount();
    error UnknownCommitment(bytes32 commitment);
    error InputOutputValueMismatch(uint256 inputValue, uint256 outputValue);
    error UnauthorizedNoteOwner(address caller, address expectedOwner);

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

    event TokenDeposited(address indexed payer, address indexed beneficiary, address indexed token, uint256 amount);
    event NoteMinted(
        address indexed liquidBalanceOwner, bytes32 indexed commitment, address indexed noteOwner, uint256 amount
    );
    event EncryptedNotePublished(bytes32 indexed commitment, address indexed noteOwner, bytes encryptedPayload);
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

    function mintNote(uint256 amount, address noteOwner, bytes32 salt, bytes calldata encryptedNotePayload)
        external
        nonReentrant
        returns (bytes32 commitment)
    {
        _validateNoteFields(amount, noteOwner);

        tokenVault.debitLiquidBalance(msg.sender, amount);
        commitment = computeNoteCommitment(amount, noteOwner, salt);
        noteRegistry.registerCommitment(commitment);

        emit NoteMinted(msg.sender, commitment, noteOwner, amount);
        emit EncryptedNotePublished(commitment, noteOwner, encryptedNotePayload);
    }

    function transferNotes(
        InputNote[] calldata inputNotes,
        OutputNote[] calldata outputs,
        bytes[] calldata encryptedOutputPayloads
    ) external nonReentrant returns (bytes32[] memory nullifiers, bytes32[] memory outputCommitments) {
        if (inputNotes.length == 0 || outputs.length == 0) {
            revert EmptyArray();
        }
        if (outputs.length != encryptedOutputPayloads.length) {
            revert ArrayLengthMismatch(outputs.length, encryptedOutputPayloads.length);
        }

        _validateNoteFields(inputNotes[0].value, inputNotes[0].owner);

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

            _requireNoteOwner(note.owner);
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
            emit EncryptedNotePublished(outputCommitments[i], outputs[i].owner, encryptedOutputPayloads[i]);
        }

        emit NotesTransferred(msg.sender, inputNotes.length, outputs.length);
    }

    function redeemNotes(InputNote[] calldata inputNotes, address receiver)
        external
        nonReentrant
        returns (bytes32[] memory nullifiers)
    {
        if (inputNotes.length == 0) {
            revert EmptyArray();
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

            _requireNoteOwner(note.owner);
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

    function computeNoteCommitment(uint256 value, address owner, bytes32 salt) public view returns (bytes32) {
        _validateNoteFields(value, owner);
        return keccak256(abi.encode(block.chainid, address(noteRegistry), tokamakNetworkToken, value, owner, salt));
    }

    function computeNullifier(uint256 value, address owner, bytes32 salt) public view returns (bytes32) {
        _validateNoteFields(value, owner);
        return keccak256(abi.encode(block.chainid, address(nullifierStore), tokamakNetworkToken, value, owner, salt));
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

    function _requireNoteOwner(address owner) internal view {
        if (msg.sender != owner) {
            revert UnauthorizedNoteOwner(msg.sender, owner);
        }
    }
}
