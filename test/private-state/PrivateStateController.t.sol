// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {PrivateNullifierRegistry} from "../../apps/private-state/src/PrivateNullifierRegistry.sol";
import {PrivateNoteRegistry} from "../../apps/private-state/src/PrivateNoteRegistry.sol";
import {PrivateStateController} from "../../apps/private-state/src/PrivateStateController.sol";
import {TokenVault} from "../../apps/private-state/src/TokenVault.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Tokamak Network Token", "TNT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PrivateStateControllerTest is Test {
    uint256 private constant ALICE_KEY = 0xA11CE;
    uint256 private constant BOB_KEY = 0xB0B;
    uint256 private constant RELAYER_KEY = 0xCAFE;

    address private owner = makeAddr("owner");
    address private alice = vm.addr(ALICE_KEY);
    address private bob = vm.addr(BOB_KEY);
    address private relayer = vm.addr(RELAYER_KEY);

    MockToken private token;
    TokenVault private tokenVault;
    PrivateNullifierRegistry private nullifierStore;
    PrivateNoteRegistry private noteRegistry;
    PrivateStateController private controller;

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

        vm.prank(alice);
        bytes32 aliceCommitment = controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt);

        assertEq(tokenVault.liquidBalances(alice), 40 ether);
        assertEq(aliceCommitment, _commitmentOf(aliceNote));
        assertTrue(noteRegistry.commitmentExists(aliceCommitment));

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](2);
        outputs[0] = _outputNote(bob, 35 ether, bytes32("bob-note-1"));
        outputs[1] = _outputNote(alice, 25 ether, bytes32("alice-change-1"));

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        vm.prank(alice);
        (bytes32[] memory nullifiers, bytes32[] memory outputCommitments) =
            controller.transferNotes(inputNotes, authorizations, outputs);

        assertEq(nullifiers.length, 1);
        assertTrue(nullifierStore.nullifierUsed(nullifiers[0]));
        assertEq(outputCommitments.length, 2);
        assertTrue(noteRegistry.commitmentExists(outputCommitments[0]));
        assertTrue(noteRegistry.commitmentExists(outputCommitments[1]));

        PrivateStateController.InputNote[] memory bobNotes = new PrivateStateController.InputNote[](1);
        bobNotes[0] = _inputNote(35 ether, bob, bytes32("bob-note-1"));
        authorizations = new PrivateStateController.SpendAuthorization[](1);

        vm.prank(bob);
        controller.redeemNotes(bobNotes, authorizations, bob);

        assertEq(tokenVault.liquidBalances(bob), 35 ether);

        uint256 bobBalanceBefore = token.balanceOf(bob);

        vm.prank(bob);
        controller.withdrawToken(35 ether, bob);

        assertEq(tokenVault.liquidBalances(bob), 0);
        assertEq(token.balanceOf(bob), bobBalanceBefore + 35 ether);
        assertEq(token.balanceOf(address(tokenVault)), 65 ether);
    }

    function testRelayerCanTransferWithOwnerSignature() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(50 ether, alice, bytes32("alice-note-2"));

        vm.prank(alice);
        controller.depositToken(50 ether);

        vm.prank(alice);
        bytes32 aliceCommitment = controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(bob, 50 ether, bytes32("bob-note-2"));

        bytes32 outputsHash = controller.hashTransferOutputs(outputs);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = controller.getTransferAuthorizationHash(aliceCommitment, outputsHash, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);
        authorizations[0] =
            PrivateStateController.SpendAuthorization({deadline: deadline, signature: abi.encodePacked(r, s, v)});

        vm.prank(relayer);
        (, bytes32[] memory outputCommitments) = controller.transferNotes(inputNotes, authorizations, outputs);

        assertTrue(noteRegistry.commitmentExists(outputCommitments[0]));
        assertEq(outputCommitments[0], _commitmentOf(_inputNote(50 ether, bob, bytes32("bob-note-2"))));
    }

    function testCannotTransferWithoutOwnerAuthorization() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(10 ether, alice, bytes32("alice-note-3"));

        vm.prank(alice);
        controller.depositToken(10 ether);

        vm.prank(alice);
        bytes32 aliceCommitment = controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(bob, 10 ether, bytes32("bob-note-3"));

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.MissingAuthorization.selector, aliceCommitment));
        vm.prank(relayer);
        controller.transferNotes(inputNotes, authorizations, outputs);
    }

    function testCannotReplaySpentNote() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(15 ether, alice, bytes32("alice-note-4"));

        vm.prank(alice);
        controller.depositToken(15 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(alice, 15 ether, bytes32("alice-note-4b"));

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        vm.prank(alice);
        controller.transferNotes(inputNotes, authorizations, outputs);

        vm.expectRevert(
            abi.encodeWithSelector(PrivateNullifierRegistry.NullifierAlreadyUsed.selector, _nullifierOf(aliceNote))
        );
        vm.prank(alice);
        controller.transferNotes(inputNotes, authorizations, outputs);
    }

    function testRejectsTransferValueMismatch() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(20 ether, alice, bytes32("alice-note-5"));

        vm.prank(alice);
        controller.depositToken(20 ether);

        vm.prank(alice);
        controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(bob, 19 ether, bytes32("bob-note-5"));

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.InputOutputValueMismatch.selector, 20 ether, 19 ether)
        );
        vm.prank(alice);
        controller.transferNotes(inputNotes, authorizations, outputs);
    }

    function testRelayerCanRedeemWithOwnerSignature() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(25 ether, alice, bytes32("alice-note-6"));

        vm.prank(alice);
        controller.depositToken(25 ether);

        vm.prank(alice);
        bytes32 aliceCommitment = controller.mintNote(aliceNote.value, aliceNote.owner, aliceNote.salt);

        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = controller.getRedeemAuthorizationHash(aliceCommitment, bob, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);

        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = aliceNote;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);
        authorizations[0] =
            PrivateStateController.SpendAuthorization({deadline: deadline, signature: abi.encodePacked(r, s, v)});

        vm.prank(relayer);
        controller.redeemNotes(inputNotes, authorizations, bob);

        assertEq(tokenVault.liquidBalances(bob), 25 ether);
        assertTrue(nullifierStore.nullifierUsed(_nullifierOf(aliceNote)));
    }

    function testUnknownCommitmentCannotBeSpent() public {
        PrivateStateController.InputNote[] memory inputNotes = new PrivateStateController.InputNote[](1);
        inputNotes[0] = _inputNote(5 ether, alice, bytes32("unknown-note"));
        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = _outputNote(bob, 5 ether, bytes32("unknown-out"));
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        bytes32 unknownCommitment = _commitmentOf(inputNotes[0]);

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnknownCommitment.selector, unknownCommitment));
        vm.prank(alice);
        controller.transferNotes(inputNotes, authorizations, outputs);
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
        tokenVault.bindController(relayer);

        vm.expectRevert(PrivateNoteRegistry.ControllerAlreadyBound.selector);
        vm.prank(owner);
        noteRegistry.bindController(relayer);

        vm.expectRevert(PrivateNullifierRegistry.ControllerAlreadyBound.selector);
        vm.prank(owner);
        nullifierStore.bindController(relayer);
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
