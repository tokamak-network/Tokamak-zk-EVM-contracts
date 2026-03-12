// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {PrivateNoteRegistry} from "../../apps/private-state/src/PrivateNoteRegistry.sol";
import {PrivateStateController} from "../../apps/private-state/src/PrivateStateController.sol";
import {TokenVault} from "../../apps/private-state/src/TokenVault.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

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
    PrivateNoteRegistry private noteRegistry;
    PrivateStateController private controller;

    function setUp() public {
        token = new MockToken();
        tokenVault = new TokenVault(owner);
        noteRegistry = new PrivateNoteRegistry(owner);
        controller = new PrivateStateController(noteRegistry, tokenVault);

        vm.startPrank(owner);
        tokenVault.setController(address(controller));
        noteRegistry.setController(address(controller));
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
        controller.depositToken(address(token), 100 ether);

        assertEq(tokenVault.liquidBalances(alice, address(token)), 100 ether);
        assertEq(token.balanceOf(address(tokenVault)), 100 ether);

        vm.prank(alice);
        (uint256 noteId,) = controller.mintNote(address(token), 60 ether, alice, bytes32("alice-note-1"), 11);

        assertEq(tokenVault.liquidBalances(alice, address(token)), 40 ether);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](2);
        outputs[0] = PrivateStateController.OutputNote({
            owner: bob, value: 35 ether, salt: bytes32("bob-note-1"), nullifierNonce: 21
        });
        outputs[1] = PrivateStateController.OutputNote({
            owner: alice, value: 25 ether, salt: bytes32("alice-change-1"), nullifierNonce: 22
        });

        uint256[] memory inputNoteIds = new uint256[](1);
        inputNoteIds[0] = noteId;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        vm.prank(alice);
        (bytes32[] memory nullifiers, uint256[] memory outputIds,) =
            controller.transferNotes(inputNoteIds, authorizations, outputs);

        assertEq(nullifiers.length, 1);
        assertTrue(noteRegistry.nullifierUsed(nullifiers[0]));
        assertTrue(noteRegistry.getNote(noteId).spent);
        assertEq(outputIds.length, 2);
        assertEq(noteRegistry.getNote(outputIds[0]).owner, bob);
        assertEq(noteRegistry.getNote(outputIds[0]).value, 35 ether);
        assertEq(noteRegistry.getNote(outputIds[1]).owner, alice);
        assertEq(noteRegistry.getNote(outputIds[1]).value, 25 ether);

        uint256[] memory bobNoteIds = new uint256[](1);
        bobNoteIds[0] = outputIds[0];
        authorizations = new PrivateStateController.SpendAuthorization[](1);

        vm.prank(bob);
        controller.redeemNotes(bobNoteIds, authorizations, bob);

        assertEq(tokenVault.liquidBalances(bob, address(token)), 35 ether);

        uint256 bobBalanceBefore = token.balanceOf(bob);

        vm.prank(bob);
        controller.withdrawToken(address(token), 35 ether, bob);

        assertEq(tokenVault.liquidBalances(bob, address(token)), 0);
        assertEq(token.balanceOf(bob), bobBalanceBefore + 35 ether);
        assertEq(token.balanceOf(address(tokenVault)), 65 ether);
    }

    function testRelayerCanTransferWithOwnerSignature() public {
        vm.prank(alice);
        controller.depositToken(address(token), 50 ether);

        vm.prank(alice);
        (uint256 noteId,) = controller.mintNote(address(token), 50 ether, alice, bytes32("alice-note-2"), 31);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = PrivateStateController.OutputNote({
            owner: bob, value: 50 ether, salt: bytes32("bob-note-2"), nullifierNonce: 41
        });

        bytes32 outputsHash = controller.hashTransferOutputs(address(token), outputs);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = controller.getTransferAuthorizationHash(noteId, outputsHash, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);

        uint256[] memory inputNoteIds = new uint256[](1);
        inputNoteIds[0] = noteId;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);
        authorizations[0] =
            PrivateStateController.SpendAuthorization({deadline: deadline, signature: abi.encodePacked(r, s, v)});

        vm.prank(relayer);
        (, uint256[] memory outputIds,) = controller.transferNotes(inputNoteIds, authorizations, outputs);

        assertEq(noteRegistry.getNote(outputIds[0]).owner, bob);
        assertEq(noteRegistry.getNote(outputIds[0]).value, 50 ether);
    }

    function testCannotTransferWithoutOwnerAuthorization() public {
        vm.prank(alice);
        controller.depositToken(address(token), 10 ether);

        vm.prank(alice);
        (uint256 noteId,) = controller.mintNote(address(token), 10 ether, alice, bytes32("alice-note-3"), 51);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = PrivateStateController.OutputNote({
            owner: bob, value: 10 ether, salt: bytes32("bob-note-3"), nullifierNonce: 61
        });

        uint256[] memory inputNoteIds = new uint256[](1);
        inputNoteIds[0] = noteId;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.MissingAuthorization.selector, noteId));
        vm.prank(relayer);
        controller.transferNotes(inputNoteIds, authorizations, outputs);
    }

    function testCannotReplaySpentNote() public {
        vm.prank(alice);
        controller.depositToken(address(token), 15 ether);

        vm.prank(alice);
        (uint256 noteId,) = controller.mintNote(address(token), 15 ether, alice, bytes32("alice-note-4"), 71);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = PrivateStateController.OutputNote({
            owner: alice, value: 15 ether, salt: bytes32("alice-note-4b"), nullifierNonce: 72
        });

        uint256[] memory inputNoteIds = new uint256[](1);
        inputNoteIds[0] = noteId;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        vm.prank(alice);
        controller.transferNotes(inputNoteIds, authorizations, outputs);

        vm.expectRevert(abi.encodeWithSelector(PrivateNoteRegistry.NoteAlreadySpent.selector, noteId));
        vm.prank(alice);
        controller.transferNotes(inputNoteIds, authorizations, outputs);
    }

    function testRejectsTransferValueMismatch() public {
        vm.prank(alice);
        controller.depositToken(address(token), 20 ether);

        vm.prank(alice);
        (uint256 noteId,) = controller.mintNote(address(token), 20 ether, alice, bytes32("alice-note-5"), 81);

        PrivateStateController.OutputNote[] memory outputs = new PrivateStateController.OutputNote[](1);
        outputs[0] = PrivateStateController.OutputNote({
            owner: bob, value: 19 ether, salt: bytes32("bob-note-5"), nullifierNonce: 91
        });

        uint256[] memory inputNoteIds = new uint256[](1);
        inputNoteIds[0] = noteId;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.InputOutputValueMismatch.selector, 20 ether, 19 ether)
        );
        vm.prank(alice);
        controller.transferNotes(inputNoteIds, authorizations, outputs);
    }

    function testRelayerCanRedeemWithOwnerSignature() public {
        vm.prank(alice);
        controller.depositToken(address(token), 25 ether);

        vm.prank(alice);
        (uint256 noteId,) = controller.mintNote(address(token), 25 ether, alice, bytes32("alice-note-6"), 101);

        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = controller.getRedeemAuthorizationHash(noteId, bob, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);

        uint256[] memory inputNoteIds = new uint256[](1);
        inputNoteIds[0] = noteId;
        PrivateStateController.SpendAuthorization[] memory authorizations =
            new PrivateStateController.SpendAuthorization[](1);
        authorizations[0] =
            PrivateStateController.SpendAuthorization({deadline: deadline, signature: abi.encodePacked(r, s, v)});

        vm.prank(relayer);
        controller.redeemNotes(inputNoteIds, authorizations, bob);

        assertEq(tokenVault.liquidBalances(bob, address(token)), 25 ether);
        assertTrue(noteRegistry.getNote(noteId).spent);
    }

    function testCannotWithdrawMoreThanLiquidBalance() public {
        vm.prank(alice);
        controller.depositToken(address(token), 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                TokenVault.InsufficientLiquidBalance.selector, alice, address(token), 10 ether, 11 ether
            )
        );
        vm.prank(alice);
        controller.withdrawToken(address(token), 11 ether, alice);
    }
}
