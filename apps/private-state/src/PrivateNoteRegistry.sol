// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/access/Ownable.sol";

/// @title PrivateNoteRegistry
/// @notice Stores note commitments and nullifiers for the non-private zk-note DApp.
contract PrivateNoteRegistry is Ownable {
    error ZeroAddress();
    error ZeroAmount();
    error UnauthorizedController(address caller);
    error NoteNotFound(uint256 noteId);
    error NoteAlreadySpent(uint256 noteId);
    error NullifierAlreadyUsed(bytes32 nullifier);

    struct Note {
        address token;
        uint256 value;
        address owner;
        bytes32 salt;
        uint256 nullifierNonce;
        bytes32 commitment;
        bool spent;
    }

    event ControllerUpdated(address indexed controller);
    event NoteCreated(
        uint256 indexed noteId,
        address indexed token,
        address indexed owner,
        uint256 value,
        bytes32 commitment,
        bytes32 salt,
        uint256 nullifierNonce
    );
    event NoteSpent(uint256 indexed noteId, bytes32 indexed nullifier, address indexed operator);

    mapping(uint256 noteId => Note note) private notes;
    mapping(bytes32 nullifier => bool used) public nullifierUsed;

    uint256 public nextNoteId = 1;
    address public controller;

    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier onlyController() {
        if (msg.sender != controller) {
            revert UnauthorizedController(msg.sender);
        }
        _;
    }

    function setController(address newController) external onlyOwner {
        if (newController == address(0)) {
            revert ZeroAddress();
        }

        controller = newController;
        emit ControllerUpdated(newController);
    }

    function noteExists(uint256 noteId) public view returns (bool) {
        return notes[noteId].owner != address(0);
    }

    function getNote(uint256 noteId) external view returns (Note memory) {
        if (!noteExists(noteId)) {
            revert NoteNotFound(noteId);
        }

        return notes[noteId];
    }

    function previewNullifier(uint256 noteId) public view returns (bytes32) {
        Note storage note = _requireNote(noteId);
        return computeNullifier(noteId, note.commitment, note.owner, note.nullifierNonce);
    }

    function createNote(address token, uint256 value, address owner, bytes32 salt, uint256 nullifierNonce)
        external
        onlyController
        returns (uint256 noteId, bytes32 commitment)
    {
        if (token == address(0) || owner == address(0)) {
            revert ZeroAddress();
        }
        if (value == 0) {
            revert ZeroAmount();
        }

        noteId = nextNoteId++;
        commitment = computeCommitment(token, value, owner, salt, nullifierNonce);
        notes[noteId] = Note({
            token: token,
            value: value,
            owner: owner,
            salt: salt,
            nullifierNonce: nullifierNonce,
            commitment: commitment,
            spent: false
        });

        emit NoteCreated(noteId, token, owner, value, commitment, salt, nullifierNonce);
    }

    function consumeNote(uint256 noteId, address operator) external onlyController returns (bytes32 nullifier) {
        Note storage note = _requireNote(noteId);
        if (note.spent) {
            revert NoteAlreadySpent(noteId);
        }

        nullifier = computeNullifier(noteId, note.commitment, note.owner, note.nullifierNonce);
        if (nullifierUsed[nullifier]) {
            revert NullifierAlreadyUsed(nullifier);
        }

        note.spent = true;
        nullifierUsed[nullifier] = true;

        emit NoteSpent(noteId, nullifier, operator);
    }

    function computeCommitment(address token, uint256 value, address owner, bytes32 salt, uint256 nullifierNonce)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(token, value, owner, salt, nullifierNonce));
    }

    function computeNullifier(uint256 noteId, bytes32 commitment, address owner, uint256 nullifierNonce)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(noteId, commitment, owner, nullifierNonce));
    }

    function _requireNote(uint256 noteId) internal view returns (Note storage note) {
        note = notes[noteId];
        if (note.owner == address(0)) {
            revert NoteNotFound(noteId);
        }
    }
}
