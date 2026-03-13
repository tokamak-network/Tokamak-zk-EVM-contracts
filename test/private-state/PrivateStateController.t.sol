// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {PrivateNullifierRegistry} from "../../apps/private-state/src/PrivateNullifierRegistry.sol";
import {PrivateNoteRegistry} from "../../apps/private-state/src/PrivateNoteRegistry.sol";
import {PrivateStateController} from "../../apps/private-state/src/PrivateStateController.sol";
import {TokenVault} from "../../apps/private-state/src/TokenVault.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Tokamak Network Token", "TON") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PrivateStateControllerTest is Test {
    address private owner = makeAddr("owner");
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private mallory = makeAddr("mallory");

    MockToken private token;
    TokenVault private tokenVault;
    PrivateNullifierRegistry private nullifierStore;
    PrivateNoteRegistry private noteRegistry;
    PrivateStateController private controller;

    event EncryptedNotePublished(bytes32 indexed commitment, address indexed noteOwner, bytes encryptedPayload);

    function setUp() public {
        token = new MockToken();
        tokenVault = new TokenVault(owner, address(token));
        nullifierStore = new PrivateNullifierRegistry(owner);
        noteRegistry = new PrivateNoteRegistry(owner);
        controller = new PrivateStateController(noteRegistry, nullifierStore, tokenVault);

        vm.startPrank(owner);
        tokenVault.bindController(address(controller));
        nullifierStore.bindController(address(controller));
        noteRegistry.bindController(address(controller));
        vm.stopPrank();

        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);

        vm.prank(alice);
        token.approve(address(tokenVault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(tokenVault), type(uint256).max);
    }

    function testDepositMintTransferRedeemAndWithdraw() public {
        vm.prank(alice);
        controller.depositToken(100 ether);

        assertEq(tokenVault.liquidBalances(alice), 100 ether);
        assertEq(token.balanceOf(address(tokenVault)), 100 ether);

        PrivateStateController.InputNote memory aliceNote = _inputNote(60 ether, alice, bytes32("alice-note-1"));
        bytes memory aliceEncryptedPayload = bytes("enc:alice-note-1");

        vm.prank(alice);
        bytes32 aliceCommitment =
            controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, aliceEncryptedPayload);

        assertEq(tokenVault.liquidBalances(alice), 40 ether);
        assertEq(aliceCommitment, _commitmentOf(aliceNote));
        assertTrue(noteRegistry.commitmentExists(aliceCommitment));

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](2);
        outputs[0] = _outputNote(bob, 35 ether, bytes32("bob-note-1"));
        outputs[1] = _outputNote(alice, 25 ether, bytes32("alice-change-1"));
        bytes[] memory encryptedOutputPayloads = new bytes[](2);
        encryptedOutputPayloads[0] = bytes("enc:bob-note-1");
        encryptedOutputPayloads[1] = bytes("enc:alice-change-1");

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;

        vm.prank(alice);
        (bytes32[] memory nullifiers, bytes32[] memory outputCommitments) =
            controller.transferNotes(inputNotes, outputs, encryptedOutputPayloads);

        assertEq(nullifiers.length, 1);
        assertTrue(nullifierStore.nullifierUsed(nullifiers[0]));
        assertEq(outputCommitments.length, 2);
        assertTrue(noteRegistry.commitmentExists(outputCommitments[0]));
        assertTrue(noteRegistry.commitmentExists(outputCommitments[1]));

        PrivateStateController.InputNote[] memory bobNotes = new PrivateStateController.InputNote[](1);
        bobNotes[0] = _inputNote(35 ether, bob, bytes32("bob-note-1"));

        vm.prank(bob);
        controller.redeemNotes(bobNotes, bob);

        assertEq(tokenVault.liquidBalances(bob), 35 ether);

        uint256 bobBalanceBefore = token.balanceOf(bob);

        vm.prank(bob);
        controller.withdrawToken(35 ether, bob);

        assertEq(tokenVault.liquidBalances(bob), 0);
        assertEq(token.balanceOf(bob), bobBalanceBefore + 35 ether);
        assertEq(token.balanceOf(address(tokenVault)), 65 ether);
    }

    function testNoteOwnerCanTransferDirectly() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(50 ether, alice, bytes32("alice-note-2"));
        bytes memory aliceEncryptedPayload = bytes("enc:alice-note-2");

        vm.prank(alice);
        controller.depositToken(50 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, aliceEncryptedPayload);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(bob, 50 ether, bytes32("bob-note-2"));
        bytes[] memory encryptedOutputPayloads = new bytes[](1);
        encryptedOutputPayloads[0] = bytes("enc:bob-note-2");

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;

        vm.prank(alice);
        (, bytes32[] memory outputCommitments) = controller.transferNotes(inputNotes, outputs, encryptedOutputPayloads);

        assertTrue(noteRegistry.commitmentExists(outputCommitments[0]));
        assertEq(outputCommitments[0], _commitmentOf(_inputNote(50 ether, bob, bytes32("bob-note-2"))));
    }

    function testCannotTransferAnotherOwnersNote() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(10 ether, alice, bytes32("alice-note-3"));

        vm.prank(alice);
        controller.depositToken(10 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, bytes("enc:alice-note-3"));

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(bob, 10 ether, bytes32("bob-note-3"));
        bytes[] memory encryptedOutputPayloads = new bytes[](1);
        encryptedOutputPayloads[0] = bytes("enc:bob-note-3");

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.transferNotes(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testCannotReplaySpentNote() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(15 ether, alice, bytes32("alice-note-4"));

        vm.prank(alice);
        controller.depositToken(15 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, bytes("enc:alice-note-4"));

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(alice, 15 ether, bytes32("alice-note-4b"));
        bytes[] memory encryptedOutputPayloads = new bytes[](1);
        encryptedOutputPayloads[0] = bytes("enc:alice-note-4b");

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;

        vm.prank(alice);
        controller.transferNotes(inputNotes, outputs, encryptedOutputPayloads);

        vm.expectRevert(
            abi.encodeWithSelector(PrivateNullifierRegistry.NullifierAlreadyUsed.selector, _nullifierOf(aliceNote))
        );
        vm.prank(alice);
        controller.transferNotes(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testRejectsTransferValueMismatch() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(20 ether, alice, bytes32("alice-note-5"));

        vm.prank(alice);
        controller.depositToken(20 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, bytes("enc:alice-note-5"));

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(bob, 19 ether, bytes32("bob-note-5"));
        bytes[] memory encryptedOutputPayloads = new bytes[](1);
        encryptedOutputPayloads[0] = bytes("enc:bob-note-5");

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.InputOutputValueMismatch.selector, 20 ether, 19 ether)
        );
        vm.prank(alice);
        controller.transferNotes(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testNoteOwnerCanRedeemDirectly() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(25 ether, alice, bytes32("alice-note-6"));

        vm.prank(alice);
        controller.depositToken(25 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, bytes("enc:alice-note-6"));

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;

        vm.prank(alice);
        controller.redeemNotes(inputNotes, bob);

        assertEq(tokenVault.liquidBalances(bob), 25 ether);
        assertTrue(nullifierStore.nullifierUsed(_nullifierOf(aliceNote)));
    }

    function testCannotRedeemAnotherOwnersNote() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(12 ether, alice, bytes32("alice-note-7"));

        vm.prank(alice);
        controller.depositToken(12 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, bytes("enc:alice-note-7"));

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.redeemNotes(inputNotes, mallory);
    }

    function testUnknownCommitmentCannotBeSpent() public {
        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = _inputNote(5 ether, alice, bytes32("unknown-note"));
        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(bob, 5 ether, bytes32("unknown-out"));
        bytes[] memory encryptedOutputPayloads = new bytes[](1);
        encryptedOutputPayloads[0] = bytes("enc:unknown-out");

        bytes32 unknownCommitment = _commitmentOf(inputNotes[0]);

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnknownCommitment.selector, unknownCommitment));
        vm.prank(alice);
        controller.transferNotes(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testTransferRejectsEncryptedPayloadLengthMismatch() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(30 ether, alice, bytes32("alice-note-8"));

        vm.prank(alice);
        controller.depositToken(30 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, bytes("enc:alice-note-8"));

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](2);
        outputs[0] = _outputNote(bob, 10 ether, bytes32("bob-note-8"));
        outputs[1] = _outputNote(alice, 20 ether, bytes32("alice-change-8"));

        bytes[] memory encryptedOutputPayloads = new bytes[](1);
        encryptedOutputPayloads[0] = bytes("enc:bob-note-8");

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.ArrayLengthMismatch.selector, 2, 1));
        vm.prank(alice);
        controller.transferNotes(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testMintEmitsEncryptedPayload() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(18 ether, alice, bytes32("alice-note-9"));
        bytes memory encryptedPayload = bytes("enc:alice-note-9");
        bytes32 expectedCommitment = _commitmentOf(aliceNote);

        vm.prank(alice);
        controller.depositToken(18 ether);

        vm.expectEmit(true, true, false, true);
        emit EncryptedNotePublished(expectedCommitment, alice, encryptedPayload);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt, encryptedPayload);
    }

    function testCannotWithdrawMoreThanLiquidBalance() public {
        vm.prank(alice);
        controller.depositToken(10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TokenVault.InsufficientLiquidBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(alice);
        controller.withdrawToken(11 ether, alice);
    }

    function testStoreControllerCannotBeRebound() public {
        vm.expectRevert(TokenVault.ControllerAlreadyBound.selector);
        vm.prank(owner);
        tokenVault.bindController(mallory);

        vm.expectRevert(PrivateNoteRegistry.ControllerAlreadyBound.selector);
        vm.prank(owner);
        noteRegistry.bindController(mallory);

        vm.expectRevert(PrivateNullifierRegistry.ControllerAlreadyBound.selector);
        vm.prank(owner);
        nullifierStore.bindController(mallory);
    }

    function _inputNote(uint256 value_, address owner_, bytes32 salt_)
        internal
        pure
        returns (PrivateStateController.InputNote memory)
    {
        return PrivateStateController.InputNote({value: value_, owner: owner_, salt: salt_});
    }

    function _outputNote(address owner_, uint256 value_, bytes32 salt_)
        internal
        pure
        returns (PrivateStateController.OutputNote memory)
    {
        return PrivateStateController.OutputNote({owner: owner_, value: value_, salt: salt_});
    }

    function _commitmentOf(PrivateStateController.InputNote memory note) internal view returns (bytes32) {
        return controller.computeNoteCommitment(note.value, note.owner, note.salt);
    }

    function _nullifierOf(PrivateStateController.InputNote memory note) internal view returns (bytes32) {
        return controller.computeNullifier(note.value, note.owner, note.salt);
    }
}
