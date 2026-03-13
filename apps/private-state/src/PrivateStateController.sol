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
    error ZeroAddress();
    error ZeroAmount();
    error UnknownCommitment(bytes32 commitment);
    error InputOutputValueMismatch(uint256 inputValue, uint256 outputValue);
    error UnauthorizedNoteOwner(address caller, address expectedOwner);

    struct Note {
        address owner;
        uint256 value;
        bytes32 salt;
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

    function depositToken(uint256 amount) external nonReentrant {
        tokenVault.deposit(msg.sender, msg.sender, amount);
        emit TokenDeposited(msg.sender, msg.sender, tokamakNetworkToken, amount);
    }

    function mintNotes1(Note[1] calldata outputs) external nonReentrant returns (bytes32[1] memory commitments) {
        Note[] memory dynamicOutputs = _copyNotes1(outputs);
        bytes32[] memory dynamicCommitments = _mintFixedNotes(dynamicOutputs);
        commitments[0] = dynamicCommitments[0];
    }

    function mintNotes2(Note[2] calldata outputs) external nonReentrant returns (bytes32[2] memory commitments) {
        Note[] memory dynamicOutputs = _copyNotes2(outputs);
        bytes32[] memory dynamicCommitments = _mintFixedNotes(dynamicOutputs);
        for (uint256 i = 0; i < 2; ++i) {
            commitments[i] = dynamicCommitments[i];
        }
    }

    function mintNotes3(Note[3] calldata outputs) external nonReentrant returns (bytes32[3] memory commitments) {
        Note[] memory dynamicOutputs = _copyNotes3(outputs);
        bytes32[] memory dynamicCommitments = _mintFixedNotes(dynamicOutputs);
        for (uint256 i = 0; i < 3; ++i) {
            commitments[i] = dynamicCommitments[i];
        }
    }

    function transferNotes4(Note[4] calldata inputNotes, Note[3] calldata outputs)
        external
        nonReentrant
        returns (bytes32[4] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        Note[] memory dynamicInputs = _copyNotes4(inputNotes);
        (bytes32[] memory dynamicNullifiers, bytes32[] memory dynamicOutputs) =
            _transferFixedNotes(dynamicInputs, outputs);

        for (uint256 i = 0; i < 4; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
        for (uint256 i = 0; i < 3; ++i) {
            outputCommitments[i] = dynamicOutputs[i];
        }
    }

    function transferNotes6(Note[6] calldata inputNotes, Note[3] calldata outputs)
        external
        nonReentrant
        returns (bytes32[6] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        Note[] memory dynamicInputs = _copyNotes6(inputNotes);
        (bytes32[] memory dynamicNullifiers, bytes32[] memory dynamicOutputs) =
            _transferFixedNotes(dynamicInputs, outputs);

        for (uint256 i = 0; i < 6; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
        for (uint256 i = 0; i < 3; ++i) {
            outputCommitments[i] = dynamicOutputs[i];
        }
    }

    function transferNotes8(Note[8] calldata inputNotes, Note[3] calldata outputs)
        external
        nonReentrant
        returns (bytes32[8] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        Note[] memory dynamicInputs = _copyNotes8(inputNotes);
        (bytes32[] memory dynamicNullifiers, bytes32[] memory dynamicOutputs) =
            _transferFixedNotes(dynamicInputs, outputs);

        for (uint256 i = 0; i < 8; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
        for (uint256 i = 0; i < 3; ++i) {
            outputCommitments[i] = dynamicOutputs[i];
        }
    }

    function redeemNotes4(Note[4] calldata inputNotes, address receiver)
        external
        nonReentrant
        returns (bytes32[4] memory nullifiers)
    {
        Note[] memory dynamicInputs = _copyNotes4(inputNotes);
        bytes32[] memory dynamicNullifiers = _redeemFixedNotes(dynamicInputs, receiver);
        for (uint256 i = 0; i < 4; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
    }

    function redeemNotes6(Note[6] calldata inputNotes, address receiver)
        external
        nonReentrant
        returns (bytes32[6] memory nullifiers)
    {
        Note[] memory dynamicInputs = _copyNotes6(inputNotes);
        bytes32[] memory dynamicNullifiers = _redeemFixedNotes(dynamicInputs, receiver);
        for (uint256 i = 0; i < 6; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
    }

    function redeemNotes8(Note[8] calldata inputNotes, address receiver)
        external
        nonReentrant
        returns (bytes32[8] memory nullifiers)
    {
        Note[] memory dynamicInputs = _copyNotes8(inputNotes);
        bytes32[] memory dynamicNullifiers = _redeemFixedNotes(dynamicInputs, receiver);
        for (uint256 i = 0; i < 8; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
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

    function _transferFixedNotes(Note[] memory inputNotes, Note[3] calldata outputs)
        internal
        returns (bytes32[] memory nullifiers, bytes32[] memory outputCommitments)
    {
        uint256 totalOutputValue;
        for (uint256 i = 0; i < 3; ++i) {
            _validateNoteFields(outputs[i].value, outputs[i].owner);
            totalOutputValue += outputs[i].value;
        }

        uint256 totalInputValue;
        bytes32[] memory inputCommitments = new bytes32[](inputNotes.length);
        nullifiers = new bytes32[](inputNotes.length);
        for (uint256 i = 0; i < inputNotes.length; ++i) {
            Note memory note = inputNotes[i];
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

        outputCommitments = new bytes32[](3);
        for (uint256 i = 0; i < 3; ++i) {
            outputCommitments[i] = computeNoteCommitment(outputs[i].value, outputs[i].owner, outputs[i].salt);
            noteRegistry.registerCommitment(outputCommitments[i]);
        }

        emit NotesTransferred(msg.sender, inputNotes.length, 3);
    }

    function _mintFixedNotes(Note[] memory outputs) internal returns (bytes32[] memory commitments) {
        uint256 totalValue;
        commitments = new bytes32[](outputs.length);
        for (uint256 i = 0; i < outputs.length; ++i) {
            _validateNoteFields(outputs[i].value, outputs[i].owner);
            totalValue += outputs[i].value;
        }

        tokenVault.debitLiquidBalance(msg.sender, totalValue);

        for (uint256 i = 0; i < outputs.length; ++i) {
            commitments[i] = computeNoteCommitment(outputs[i].value, outputs[i].owner, outputs[i].salt);
            noteRegistry.registerCommitment(commitments[i]);
            emit NoteMinted(msg.sender, commitments[i], outputs[i].owner, outputs[i].value);
        }
    }

    function _redeemFixedNotes(Note[] memory inputNotes, address receiver)
        internal
        returns (bytes32[] memory nullifiers)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        bytes32[] memory inputCommitments = new bytes32[](inputNotes.length);
        nullifiers = new bytes32[](inputNotes.length);
        for (uint256 i = 0; i < inputNotes.length; ++i) {
            Note memory note = inputNotes[i];
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

    function _validateNoteFields(uint256 value, address owner) internal pure {
        if (owner == address(0)) {
            revert ZeroAddress();
        }
        if (value == 0) {
            revert ZeroAmount();
        }
    }

    function _requireNoteOwner(address owner) internal view {
        if (msg.sender != owner) {
            revert UnauthorizedNoteOwner(msg.sender, owner);
        }
    }

    function _copyNotes4(Note[4] calldata inputNotes) internal pure returns (Note[] memory copied) {
        copied = new Note[](4);
        for (uint256 i = 0; i < 4; ++i) {
            copied[i] = inputNotes[i];
        }
    }

    function _copyNotes6(Note[6] calldata inputNotes) internal pure returns (Note[] memory copied) {
        copied = new Note[](6);
        for (uint256 i = 0; i < 6; ++i) {
            copied[i] = inputNotes[i];
        }
    }

    function _copyNotes8(Note[8] calldata inputNotes) internal pure returns (Note[] memory copied) {
        copied = new Note[](8);
        for (uint256 i = 0; i < 8; ++i) {
            copied[i] = inputNotes[i];
        }
    }

    function _copyNotes1(Note[1] calldata outputs) internal pure returns (Note[] memory copied) {
        copied = new Note[](1);
        copied[0] = outputs[0];
    }

    function _copyNotes2(Note[2] calldata outputs) internal pure returns (Note[] memory copied) {
        copied = new Note[](2);
        for (uint256 i = 0; i < 2; ++i) {
            copied[i] = outputs[i];
        }
    }

    function _copyNotes3(Note[3] calldata outputs) internal pure returns (Note[] memory copied) {
        copied = new Note[](3);
        for (uint256 i = 0; i < 3; ++i) {
            copied[i] = outputs[i];
        }
    }
}
