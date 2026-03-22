// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BridgeStructs} from "../src/BridgeStructs.sol";
import {BridgeAdminManager} from "../src/BridgeAdminManager.sol";
import {DAppManager} from "../src/DAppManager.sol";
import {BridgeCore} from "../src/BridgeCore.sol";
import {ChannelManager} from "../src/ChannelManager.sol";
import {L1TokenVault} from "../src/L1TokenVault.sol";
import {MockGrothVerifier} from "../src/mocks/MockGrothVerifier.sol";
import {MockTokamakVerifier} from "../src/mocks/MockTokamakVerifier.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract BridgeFlowTest is Test {
    bytes4 internal constant APP_SIG = bytes4(keccak256("trade(uint256)"));

    BridgeAdminManager internal adminManager;
    DAppManager internal dAppManager;
    BridgeCore internal bridgeCore;
    MockGrothVerifier internal grothVerifier;
    MockTokamakVerifier internal tokamakVerifier;
    MockERC20 internal asset;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal leader = address(0x1EAD);
    address internal appContract = address(0xCAFE);

    uint256 internal channelId = 1;
    uint256 internal secondChannelId = 2;

    ChannelManager internal channelManager;
    L1TokenVault internal tokenVault;

    function setUp() public {
        adminManager = new BridgeAdminManager(address(this));
        adminManager.setMerkleTreeLevels(4);
        adminManager.setTokamakPublicInputsLength(16);

        address[] memory storageAddrs = new address[](1);
        storageAddrs[0] = address(0x1234);
        adminManager.registerStorageMetadata(storageAddrs[0], _bytes32Array(bytes32(uint256(1))), _uint8Array(0));
        adminManager.registerFunction(APP_SIG, storageAddrs, bytes32("INSTANCE"), bytes32("PREPROCESS"));

        dAppManager = new DAppManager(address(this), adminManager);
        dAppManager.registerDApp(1, keccak256("private-app"));

        BridgeStructs.FunctionReference[] memory refs = new BridgeStructs.FunctionReference[](1);
        refs[0] = BridgeStructs.FunctionReference({entryContract: appContract, functionSig: APP_SIG});
        dAppManager.registerDAppFunctions(1, refs);

        grothVerifier = new MockGrothVerifier();
        tokamakVerifier = new MockTokamakVerifier();
        bridgeCore = new BridgeCore(address(this), adminManager, dAppManager, grothVerifier, tokamakVerifier);

        asset = new MockERC20("Mock Asset", "MA");
        asset.mint(alice, 1_000 ether);
        asset.mint(bob, 1_000 ether);

        (address manager, address vault) = bridgeCore.createChannel(
            channelId,
            1,
            leader,
            asset,
            bytes32("CHANNEL_INSTANCE"),
            _rootVector(bytes32(uint256(11)), bytes32(uint256(22))),
            0,
            refs
        );

        channelManager = ChannelManager(manager);
        tokenVault = L1TokenVault(vault);

        vm.prank(alice);
        asset.approve(address(tokenVault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(tokenVault), type(uint256).max);
    }

    function testRegisterAndFundStoresDerivedLeafIndex() public {
        bytes32 key = bytes32(uint256(5));

        vm.prank(alice);
        tokenVault.registerAndFund(key, 100 ether);

        L1TokenVault.VaultRegistration memory registration = tokenVault.getRegistration(alice);
        assertTrue(registration.exists);
        assertEq(registration.l2TokenVaultKey, key);
        assertEq(registration.leafIndex, 5);
        assertEq(registration.availableBalance, 100 ether);
        assertEq(registration.totalCustodyBalance, 100 ether);
        assertEq(asset.balanceOf(address(tokenVault)), 100 ether);
    }

    function testRejectsPerChannelLeafCollision() public {
        vm.prank(alice);
        tokenVault.registerAndFund(bytes32(uint256(1)), 10 ether);

        vm.expectRevert(abi.encodeWithSelector(BridgeCore.ChannelLeafIndexCollision.selector, channelId, 1));
        vm.prank(bob);
        tokenVault.registerAndFund(bytes32(uint256(17)), 10 ether);
    }

    function testRejectsGlobalKeyReuseAcrossChannels() public {
        bytes32 reusedKey = bytes32(uint256(8));

        vm.prank(alice);
        tokenVault.registerAndFund(reusedKey, 10 ether);

        BridgeStructs.FunctionReference[] memory refs = new BridgeStructs.FunctionReference[](1);
        refs[0] = BridgeStructs.FunctionReference({entryContract: appContract, functionSig: APP_SIG});

        (, address secondVaultAddress) = bridgeCore.createChannel(
            secondChannelId,
            1,
            leader,
            asset,
            bytes32("CHANNEL_INSTANCE_2"),
            _rootVector(bytes32(uint256(101)), bytes32(uint256(202))),
            0,
            refs
        );

        L1TokenVault secondVault = L1TokenVault(secondVaultAddress);
        vm.prank(bob);
        asset.approve(address(secondVault), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(BridgeCore.GlobalVaultKeyAlreadyRegistered.selector, reusedKey));
        vm.prank(bob);
        secondVault.registerAndFund(reusedKey, 10 ether);
    }

    function testGrothDepositUpdatesVaultStateAndRootVector() public {
        bytes32 key = bytes32(uint256(9));
        vm.prank(alice);
        tokenVault.registerAndFund(key, 100 ether);

        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRoot: bytes32(uint256(11)),
            updatedRoot: bytes32(uint256(111)),
            currentUserKey: bytes32(0),
            currentUserValue: 0,
            updatedUserKey: key,
            updatedUserValue: 40 ether
        });

        vm.prank(alice);
        tokenVault.deposit(hex"1234", update);

        L1TokenVault.VaultRegistration memory registration = tokenVault.getRegistration(alice);
        assertEq(registration.availableBalance, 60 ether);
        assertEq(registration.l2AccountingBalance, 40 ether);

        bytes32[] memory currentRoots = channelManager.getCurrentRootVector();
        assertEq(currentRoots[0], bytes32(uint256(111)));
        assertEq(
            channelManager.getLatestTokenVaultLeaf(registration.leafIndex),
            tokenVault.mockTokenVaultLeaf(key, 40 ether)
        );
    }

    function testGrothWithdrawAndClaimToWallet() public {
        bytes32 key = bytes32(uint256(9));
        vm.prank(alice);
        tokenVault.registerAndFund(key, 100 ether);

        BridgeStructs.GrothUpdate memory depositUpdate = BridgeStructs.GrothUpdate({
            currentRoot: bytes32(uint256(11)),
            updatedRoot: bytes32(uint256(111)),
            currentUserKey: bytes32(0),
            currentUserValue: 0,
            updatedUserKey: key,
            updatedUserValue: 40 ether
        });
        vm.prank(alice);
        tokenVault.deposit(hex"1111", depositUpdate);

        BridgeStructs.GrothUpdate memory withdrawUpdate = BridgeStructs.GrothUpdate({
            currentRoot: bytes32(uint256(111)),
            updatedRoot: bytes32(uint256(222)),
            currentUserKey: key,
            currentUserValue: 40 ether,
            updatedUserKey: key,
            updatedUserValue: 10 ether
        });
        vm.prank(alice);
        tokenVault.withdraw(hex"2222", withdrawUpdate);

        L1TokenVault.VaultRegistration memory registration = tokenVault.getRegistration(alice);
        assertEq(registration.availableBalance, 90 ether);
        assertEq(registration.l2AccountingBalance, 10 ether);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        vm.prank(alice);
        tokenVault.claimToWallet(50 ether);
        assertEq(asset.balanceOf(alice), aliceBalanceBefore + 50 ether);
    }

    function testTokamakVerificationRejectsUnsupportedFunction() public {
        BridgeStructs.TokamakTransactionInstance memory instance = BridgeStructs.TokamakTransactionInstance({
            currentRootVector: _rootVector(bytes32(uint256(11)), bytes32(uint256(22))),
            updatedRootVector: _rootVector(bytes32(uint256(12)), bytes32(uint256(23))),
            entryContract: address(0xBEEF),
            functionSig: APP_SIG
        });

        vm.expectRevert(
            abi.encodeWithSelector(ChannelManager.UnsupportedChannelFunction.selector, address(0xBEEF), APP_SIG)
        );
        channelManager.submitTokamakProof(hex"01", instance);
    }

    function testTokamakVerificationUpdatesRootVector() public {
        BridgeStructs.TokamakTransactionInstance memory instance = BridgeStructs.TokamakTransactionInstance({
            currentRootVector: _rootVector(bytes32(uint256(11)), bytes32(uint256(22))),
            updatedRootVector: _rootVector(bytes32(uint256(33)), bytes32(uint256(44))),
            entryContract: appContract,
            functionSig: APP_SIG
        });

        channelManager.submitTokamakProof(hex"abcd", instance);

        bytes32[] memory currentRoots = channelManager.getCurrentRootVector();
        assertEq(currentRoots[0], bytes32(uint256(33)));
        assertEq(currentRoots[1], bytes32(uint256(44)));
    }

    function _rootVector(bytes32 left, bytes32 right) internal pure returns (bytes32[] memory roots) {
        roots = new bytes32[](2);
        roots[0] = left;
        roots[1] = right;
    }

    function _bytes32Array(bytes32 value) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](1);
        out[0] = value;
    }

    function _uint8Array(uint8 value) internal pure returns (uint8[] memory out) {
        out = new uint8[](1);
        out[0] = value;
    }
}
