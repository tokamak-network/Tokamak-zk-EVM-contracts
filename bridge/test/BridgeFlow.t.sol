// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ERC1967Proxy} from "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {BridgeStructs} from "../src/BridgeStructs.sol";
import {BridgeAdminManager} from "../src/BridgeAdminManager.sol";
import {DAppManager} from "../src/DAppManager.sol";
import {BridgeCore} from "../src/BridgeCore.sol";
import {ChannelManager} from "../src/ChannelManager.sol";
import {L1TokenVault} from "../src/L1TokenVault.sol";
import {IChannelRegistry} from "../src/interfaces/IChannelRegistry.sol";
import {IGrothVerifier} from "../src/interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "../src/interfaces/ITokamakVerifier.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {FeeOnTransferMockERC20} from "../src/mocks/FeeOnTransferMockERC20.sol";
import {DepositGrothProofFixture, WithdrawGrothProofFixture} from "./GrothProofFixtures.sol";
import {Groth16Verifier} from "groth16-verifier/src/Groth16Verifier.sol";
import {TokamakVerifier} from "tokamak-zkp/TokamakVerifier.sol";

contract BridgeFlowTest is Test {
    using stdJson for string;

    bytes4 internal constant APP_SIG = bytes4(keccak256("trade(uint256)"));
    bytes4 internal constant APP_SIG_2 = bytes4(keccak256("rebalance(uint256)"));
    uint256 internal constant BLS12_381_SCALAR_FIELD_MODULUS =
        0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 internal constant TOKEN_VAULT_MT_LEAF_COUNT = uint256(1) << 12;
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant INITIAL_ZERO_ROOT =
        bytes32(uint256(5829984778942235508054786484586420582947187778500268001993713384889194068958));
    string internal constant TOKAMAK_FIXTURE_PATH = "test/fixtures/tokamak-proof-fixture.json";
    string internal constant REAL_TOKAMAK_PROOF_PATH =
        "../tokamak-zkp/test/fixtures/mintNotes1-proof/resource/prove/fixture/proof.json";
    string internal constant REAL_TOKAMAK_PREPROCESS_PATH =
        "../tokamak-zkp/test/fixtures/mintNotes1-proof/resource/preprocess/fixture/preprocess.json";
    string internal constant REAL_TOKAMAK_INSTANCE_PATH =
        "../tokamak-zkp/test/fixtures/mintNotes1-proof/resource/synthesizer/fixture/instance.json";
    address internal constant REAL_TOKAMAK_APP_STORAGE = 0x8b64A4D3DF1771d7dFC93b374f545563B680b420;

    BridgeAdminManager internal adminManager;
    DAppManager internal dAppManager;
    BridgeCore internal bridgeCore;
    Groth16Verifier internal grothVerifier;
    TokamakVerifier internal tokamakVerifier;
    MockERC20 internal asset;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal leader = address(0x1EAD);
    address internal appContract = address(0xCAFE);
    address internal appContract2 = address(0xD00D);

    string internal channelName = "bridge-flow-primary";
    string internal secondChannelName = "bridge-flow-secondary";
    uint256 internal channelId;
    uint256 internal secondChannelId;
    bytes32 internal defaultPreprocessInputHash;

    ChannelManager internal channelManager;
    L1TokenVault internal bridgeTokenVault;

    function setUp() public {
        BridgeStructs.TokamakProofPayload memory tokamakFixture = _loadTokamakProofPayload();
        defaultPreprocessInputHash =
            _computePointEncodingHash(tokamakFixture.functionPreprocessPart1, tokamakFixture.functionPreprocessPart2);

        adminManager = _deployAdminManagerProxy(address(this), 12);

        tokamakVerifier = new TokamakVerifier();

        address vaultStorageAddr = address(0xF00D);
        address appStorageAddr = address(0x1234);
        address secondaryVaultStorageAddr = address(0xF00E);
        dAppManager = _deployDAppManagerProxy(address(this));
        dAppManager.registerDApp(
            1,
            keccak256("private-app"),
            _defaultStorageLayouts(vaultStorageAddr, appStorageAddr),
            _defaultDAppFunctions(defaultPreprocessInputHash)
        );
        dAppManager.registerDApp(
            2,
            keccak256("alt-private-app"),
            _singleVaultStorageLayout(secondaryVaultStorageAddr),
            _singleVaultDAppFunction()
        );

        grothVerifier = new Groth16Verifier();
        bridgeCore = _deployBridgeCoreProxy(
            address(this),
            adminManager,
            dAppManager,
            IGrothVerifier(address(grothVerifier)),
            ITokamakVerifier(address(tokamakVerifier))
        );
        dAppManager.bindBridgeCore(address(bridgeCore));
        channelId = _deriveChannelId(channelName);
        secondChannelId = _deriveChannelId(secondChannelName);
        bridgeTokenVault = _deployTokenVaultProxy(address(this), bridgeCore);
        bridgeCore.bindBridgeTokenVault(address(bridgeTokenVault));

        MockERC20 assetImplementation = new MockERC20("Mock Asset", "MA");
        asset = MockERC20(bridgeCore.canonicalAsset());
        vm.etch(address(asset), address(assetImplementation).code);
        asset.mint(alice, 1_000 ether);
        asset.mint(bob, 1_000 ether);

        (address manager, address vault) = bridgeCore.createChannel(channelId, 1, leader);

        channelManager = ChannelManager(manager);
        assertEq(vault, address(bridgeTokenVault));

        vm.prank(alice);
        asset.approve(address(bridgeTokenVault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(bridgeTokenVault), type(uint256).max);
    }

    function testFundStoresSharedBridgeBalance() public {
        vm.prank(alice);
        bridgeTokenVault.fund(100 ether);

        assertEq(bridgeTokenVault.availableBalanceOf(alice), 100 ether);
        assertEq(asset.balanceOf(address(bridgeTokenVault)), 100 ether);
    }

    function testAdminManagerReturnsMaxMerkleTreeLeaves() public view {
        assertEq(adminManager.getMaxMerkleTreeLeaves(), uint256(1) << 12);
    }

    function testRejectsUnsupportedMerkleTreeLevels() public {
        vm.expectRevert(
            abi.encodeWithSelector(BridgeAdminManager.UnsupportedMerkleTreeLevels.selector, uint8(13), uint8(12))
        );
        adminManager.setMerkleTreeLevels(13);
    }

    function testDAppManagerExposesRegisteredMetadata() public view {
        DAppManager.DAppInfo memory info = dAppManager.getDAppInfo(1);
        assertTrue(info.exists);
        assertEq(info.labelHash, keccak256("private-app"));
        assertEq(info.channelTokenVaultTreeIndex, 0);

        address[] memory managedStorageAddresses = dAppManager.getManagedStorageAddresses(1);
        assertEq(managedStorageAddresses.length, 2);
        assertEq(managedStorageAddresses[0], address(0xF00D));
        assertEq(managedStorageAddresses[1], address(0x1234));

        BridgeStructs.FunctionConfig memory functionConfig = dAppManager.getFunctionMetadata(1, appContract, APP_SIG);
        assertTrue(functionConfig.exists);
        assertEq(functionConfig.preprocessInputHash, defaultPreprocessInputHash);
        assertEq(functionConfig.entryContractOffsetWords, 22);
        assertEq(functionConfig.functionSigOffsetWords, 24);
        assertEq(functionConfig.currentRootVectorOffsetWords, 26);
        assertEq(functionConfig.updatedRootVectorOffsetWords, 0);

        BridgeStructs.StorageWriteMetadata[] memory storageWrites =
            dAppManager.getFunctionStorageWrites(1, appContract, APP_SIG);
        assertEq(storageWrites.length, 0);
        assertTrue(dAppManager.isSupportedFunction(1, appContract, APP_SIG));
        assertEq(dAppManager.getChannelTokenVaultTreeIndex(1), 0);

        bytes32[] memory preAllocKeys = dAppManager.getPreAllocKeys(1, address(0xF00D));
        assertEq(preAllocKeys.length, 1);
        assertEq(preAllocKeys[0], bytes32(uint256(0)));

        uint8[] memory userSlots = dAppManager.getUserSlots(1, address(0xF00D));
        assertEq(userSlots.length, 1);
        assertEq(userSlots[0], 0);
        assertTrue(dAppManager.isChannelTokenVaultStorageAddress(1, address(0xF00D)));
        assertFalse(dAppManager.isChannelTokenVaultStorageAddress(1, address(0x1234)));
    }

    function testDAppManagerTracksBoundBridgeCoreAndActiveChannels() public view {
        assertEq(dAppManager.bridgeCore(), address(bridgeCore));
        assertEq(dAppManager.getActiveChannelCount(1), 1);
        assertEq(dAppManager.getActiveChannelCount(2), 0);
    }

    function testOwnerCanDeleteUnboundDAppWhileDeletionIsEnabled() public {
        dAppManager.deleteDApp(2);

        vm.expectRevert(abi.encodeWithSelector(DAppManager.UnknownDApp.selector, 2));
        dAppManager.getDAppInfo(2);
    }

    function testDeletedDAppIdCanBeRegisteredAgain() public {
        dAppManager.deleteDApp(2);

        dAppManager.registerDApp(
            2,
            keccak256("alt-private-app-reloaded"),
            _singleVaultStorageLayout(address(0xF11D)),
            _singleVaultDAppFunction()
        );

        DAppManager.DAppInfo memory info = dAppManager.getDAppInfo(2);
        assertTrue(info.exists);
        assertEq(info.labelHash, keccak256("alt-private-app-reloaded"));
    }

    function testRejectsDeletingDAppWithActiveChannels() public {
        vm.expectRevert(abi.encodeWithSelector(DAppManager.ActiveChannelsExist.selector, 1, 1));
        dAppManager.deleteDApp(1);
    }

    function testRejectsDeletingDAppAfterDeletionIsDisabledForever() public {
        dAppManager.disableDAppDeletionForever();

        vm.expectRevert(DAppManager.DAppDeletionDisabled.selector);
        dAppManager.deleteDApp(2);
    }

    function testOwnerCanReEnableDeletionBeforePermanentLock() public {
        dAppManager.disableDAppDeletionForever();

        vm.expectRevert(DAppManager.DAppDeletionLockedForever.selector);
        dAppManager.enableDAppDeletion();
    }

    function testChannelStoresManagedStorageAddressVector() public view {
        address[] memory managedStorageAddresses = channelManager.getManagedStorageAddresses();
        assertEq(managedStorageAddresses.length, 2);
        assertEq(managedStorageAddresses[0], address(0xF00D));
        assertEq(managedStorageAddresses[1], address(0x1234));

        bytes32[] memory currentRoots = _rootVector(INITIAL_ZERO_ROOT, INITIAL_ZERO_ROOT);
        assertEq(currentRoots.length, managedStorageAddresses.length);
        assertEq(channelManager.currentRootVectorHash(), _hashRootVector(currentRoots));
    }

    function testChannelStoresGenesisBlockNumber() public view {
        assertEq(channelManager.genesisBlockNumber(), block.number);
    }

    function testRejectsPerChannelLeafCollision() public {
        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, bytes32(uint256(1)), 1, _defaultNoteReceivePubKey());

        vm.expectRevert(abi.encodeWithSelector(ChannelManager.ChannelTokenVaultLeafIndexAlreadyRegistered.selector, 1));
        vm.prank(bob);
        channelManager.registerChannelTokenVaultIdentity(bob, bytes32(uint256(4097)), 1, _defaultNoteReceivePubKey());
    }

    function testAllowsKeyReuseAcrossDifferentChannels() public {
        bytes32 reusedKey = bytes32(uint256(8));

        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, reusedKey, 8, _defaultNoteReceivePubKey());

        (address secondManagerAddress, address secondVaultAddress) =
            bridgeCore.createChannel(secondChannelId, 1, leader);
        ChannelManager secondChannelManager = ChannelManager(secondManagerAddress);
        vm.prank(bob);
        secondChannelManager.registerChannelTokenVaultIdentity(bob, reusedKey, 8, _defaultNoteReceivePubKey());

        assertEq(secondVaultAddress, address(bridgeTokenVault));
        BridgeStructs.ChannelTokenVaultRegistration memory secondRegistration =
            secondChannelManager.getChannelTokenVaultRegistration(bob);
        assertTrue(secondRegistration.exists);
        assertEq(secondRegistration.channelTokenVaultKey, reusedKey);
        assertEq(secondRegistration.leafIndex, 8);
    }

    function testChannelReturnsRegisteredTokenVaultIdentityForUser() public {
        bytes32 key = bytes32(uint256(17));

        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, key, 17, _defaultNoteReceivePubKey());

        BridgeStructs.ChannelTokenVaultRegistration memory registration =
            bridgeCore.getChannelTokenVaultRegistration(channelId, alice);
        assertTrue(registration.exists);
        assertEq(registration.l2Address, alice);
        assertEq(registration.channelTokenVaultKey, key);
        assertEq(registration.leafIndex, 17);
    }

    function testRejectsDAppRegistrationWithMultipleTokenVaultStorages() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DAppManager.MultipleChannelTokenVaultStorageAddresses.selector, 3, address(0xF00D), address(0xF00E)
            )
        );
        dAppManager.registerDApp(
            3,
            keccak256("invalid-private-app"),
            _threeStorageLayouts(address(0xF00D), address(0x1234), address(0xF00E)),
            _conflictingDAppFunctions()
        );
    }

    function testRejectsDAppRegistrationWithoutPreprocessHash() public {
        BridgeStructs.DAppFunctionMetadata[] memory functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            preprocessInputHash: bytes32(0),
            instanceLayout: _instanceLayout(22, 24, 26, 0, _emptyStorageWrites())
        });

        vm.expectRevert(
            abi.encodeWithSelector(DAppManager.MissingPreprocessInputHash.selector, uint256(3), appContract, APP_SIG)
        );
        dAppManager.registerDApp(
            3, keccak256("missing-preprocess-hash"), _defaultStorageLayouts(address(0xF00D), address(0x1234)), functions
        );
    }

    function testRejectsDAppRegistrationWithDuplicatePreprocessHash() public {
        bytes32 duplicateHash = bytes32("DUPLICATE_PREPROCESS_HASH");
        BridgeStructs.DAppFunctionMetadata[] memory functions = new BridgeStructs.DAppFunctionMetadata[](2);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            preprocessInputHash: duplicateHash,
            instanceLayout: _instanceLayout(22, 24, 26, 0, _emptyStorageWrites())
        });
        functions[1] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract2,
            functionSig: APP_SIG_2,
            preprocessInputHash: duplicateHash,
            instanceLayout: _instanceLayout(22, 24, 26, 0, _emptyStorageWrites())
        });

        vm.expectRevert(
            abi.encodeWithSelector(DAppManager.DuplicatePreprocessInputHash.selector, uint256(3), duplicateHash)
        );
        dAppManager.registerDApp(
            3,
            keccak256("duplicate-preprocess-hash"),
            _defaultStorageLayouts(address(0xF00D), address(0x1234)),
            functions
        );
    }

    function testChannelDerivesAPubBlockHashOnCreation() public view {
        BridgeCore.ChannelDeployment memory deployment = bridgeCore.getChannel(channelId);
        assertEq(deployment.aPubBlockHash, channelManager.aPubBlockHash());
    }

    function testBridgeCoreExposesChannelManagerAddress() public view {
        assertEq(bridgeCore.getChannelManager(channelId), address(channelManager));
    }

    function testRejectsBridgeTokenVaultRebinding() public {
        vm.expectRevert(BridgeCore.BridgeTokenVaultAlreadySet.selector);
        bridgeCore.bindBridgeTokenVault(address(0xBEEF));
    }

    function testRejectsChannelCreationWithTooManyManagedStorages() public {
        BridgeStructs.StorageMetadata[] memory storages = new BridgeStructs.StorageMetadata[](12);
        for (uint256 i = 0; i < storages.length; i++) {
            storages[i] = BridgeStructs.StorageMetadata({
                storageAddr: address(uint160(0x1000 + i)),
                preAllocatedKeys: new bytes32[](0),
                userStorageSlots: new uint8[](0),
                isChannelTokenVaultStorage: i == 0
            });
        }

        BridgeStructs.DAppFunctionMetadata[] memory functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            preprocessInputHash: bytes32("PREPROCESS_INPUT"),
            instanceLayout: _instanceLayout(22, 24, 26, 0, _emptyStorageWrites())
        });

        dAppManager.registerDApp(3, keccak256("oversized-dapp"), storages, functions);

        vm.expectRevert(abi.encodeWithSelector(BridgeCore.TooManyManagedStorages.selector, uint256(12), uint256(11)));
        bridgeCore.createChannel(_deriveChannelId("missing-block-context-channel"), 3, leader);
    }

    function testGrothDepositUpdatesVaultStateAndRootVector() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        bridgeTokenVault.fund(100 ether);
        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, key, 111, _defaultNoteReceivePubKey());
        _mockGrothVerifierAcceptsAllProofs();

        uint256[5] memory pubSignals = _depositPublicSignals();
        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(pubSignals[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(pubSignals[1]),
            currentUserKey: key,
            currentUserValue: pubSignals[3],
            updatedUserKey: key,
            updatedUserValue: pubSignals[4]
        });

        vm.recordLogs();
        vm.prank(alice);
        bridgeTokenVault.deposit(channelId, _depositProof(), update);

        BridgeStructs.ChannelTokenVaultRegistration memory registration =
            channelManager.getChannelTokenVaultRegistration(alice);
        assertEq(bridgeTokenVault.availableBalanceOf(alice), 100 ether - 10);

        bytes32[] memory currentRoots = _rootVector(bytes32(pubSignals[1]), INITIAL_ZERO_ROOT);
        assertEq(channelManager.currentRootVectorHash(), _hashRootVector(currentRoots));
        assertEq(channelManager.getLatestChannelTokenVaultLeaf(registration.leafIndex), bytes32(uint256(10)));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 storageWriteTopic = keccak256("StorageWriteObserved(address,uint256,uint256)");
        bytes32 rootVectorObservedTopic = keccak256("CurrentRootVectorObserved(bytes32,bytes32[])");
        uint256 storageWriteCount;
        uint256 rootVectorObservedCount;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(bridgeTokenVault) && logs[i].topics[0] == storageWriteTopic) {
                storageWriteCount += 1;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), channelManager.channelTokenVaultStorageAddress());
                (uint256 storageKey, uint256 value) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(storageKey, uint256(registration.channelTokenVaultKey));
                assertEq(value, update.updatedUserValue);
            } else if (logs[i].emitter == address(channelManager) && logs[i].topics[0] == rootVectorObservedTopic) {
                rootVectorObservedCount += 1;
                bytes32 emittedRootVectorHash = bytes32(logs[i].topics[1]);
                bytes32[] memory emittedRootVector = abi.decode(logs[i].data, (bytes32[]));
                bytes32[] memory expectedRootVector = _rootVector(bytes32(pubSignals[1]), INITIAL_ZERO_ROOT);
                assertEq(emittedRootVectorHash, _hashRootVector(expectedRootVector));
                assertEq(emittedRootVector.length, expectedRootVector.length);
                for (uint256 j = 0; j < emittedRootVector.length; j++) {
                    assertEq(emittedRootVector[j], expectedRootVector[j]);
                }
            }
        }
        assertEq(storageWriteCount, 1);
        assertEq(rootVectorObservedCount, 1);
    }

    function testGrothWithdrawAndClaimToWallet() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        bridgeTokenVault.fund(100 ether);
        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, key, 111, _defaultNoteReceivePubKey());
        _mockGrothVerifierAcceptsAllProofs();

        uint256[5] memory depositSignals = _depositPublicSignals();
        BridgeStructs.GrothUpdate memory depositUpdate = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(depositSignals[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(depositSignals[1]),
            currentUserKey: key,
            currentUserValue: depositSignals[3],
            updatedUserKey: key,
            updatedUserValue: depositSignals[4]
        });
        vm.prank(alice);
        bridgeTokenVault.deposit(channelId, _depositProof(), depositUpdate);

        uint256[5] memory withdrawSignals = _withdrawPublicSignals();
        BridgeStructs.GrothUpdate memory withdrawUpdate = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(withdrawSignals[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(withdrawSignals[1]),
            currentUserKey: key,
            currentUserValue: withdrawSignals[3],
            updatedUserKey: key,
            updatedUserValue: withdrawSignals[4]
        });
        vm.recordLogs();
        vm.prank(alice);
        bridgeTokenVault.withdraw(channelId, _withdrawProof(), withdrawUpdate);

        bytes32[] memory currentRoots = _rootVector(bytes32(withdrawSignals[1]), INITIAL_ZERO_ROOT);
        assertEq(channelManager.currentRootVectorHash(), _hashRootVector(currentRoots));

        BridgeStructs.ChannelTokenVaultRegistration memory registration =
            channelManager.getChannelTokenVaultRegistration(alice);
        assertEq(bridgeTokenVault.availableBalanceOf(alice), 100 ether - 4);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        vm.prank(alice);
        bridgeTokenVault.claimToWallet(50 ether);
        assertEq(asset.balanceOf(alice), aliceBalanceBefore + 50 ether);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 storageWriteTopic = keccak256("StorageWriteObserved(address,uint256,uint256)");
        bytes32 rootVectorObservedTopic = keccak256("CurrentRootVectorObserved(bytes32,bytes32[])");
        uint256 storageWriteCount;
        uint256 rootVectorObservedCount;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(bridgeTokenVault) && logs[i].topics[0] == storageWriteTopic) {
                storageWriteCount += 1;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), channelManager.channelTokenVaultStorageAddress());
                (uint256 storageKey, uint256 value) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(storageKey, uint256(registration.channelTokenVaultKey));
                assertEq(value, withdrawUpdate.updatedUserValue);
            } else if (logs[i].emitter == address(channelManager) && logs[i].topics[0] == rootVectorObservedTopic) {
                rootVectorObservedCount += 1;
                bytes32 emittedRootVectorHash = bytes32(logs[i].topics[1]);
                bytes32[] memory emittedRootVector = abi.decode(logs[i].data, (bytes32[]));
                bytes32[] memory expectedRootVector = _rootVector(bytes32(withdrawSignals[1]), INITIAL_ZERO_ROOT);
                assertEq(emittedRootVectorHash, _hashRootVector(expectedRootVector));
                assertEq(emittedRootVector.length, expectedRootVector.length);
                for (uint256 j = 0; j < emittedRootVector.length; j++) {
                    assertEq(emittedRootVector[j], expectedRootVector[j]);
                }
            }
        }
        assertEq(storageWriteCount, 1);
        assertEq(rootVectorObservedCount, 1);
    }

    function testRejectsFeeOnTransferAssetDuringRegistration() public {
        FeeOnTransferMockERC20 feeAssetImplementation =
            new FeeOnTransferMockERC20("Fee Asset", "FEE", 100, address(0xFEE));
        FeeOnTransferMockERC20 feeAsset = FeeOnTransferMockERC20(address(asset));
        vm.etch(address(feeAsset), address(feeAssetImplementation).code);
        feeAsset.mint(alice, 100 ether);

        (address manager, address vault) =
            bridgeCore.createChannel(_deriveChannelId("fee-on-transfer-channel"), 1, leader);

        manager;
        L1TokenVault feeVault = L1TokenVault(vault);
        vm.prank(alice);
        feeAsset.approve(address(feeVault), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(L1TokenVault.UnsupportedAssetTransferBehavior.selector, 100 ether, 99 ether)
        );
        vm.prank(alice);
        feeVault.fund(100 ether);
    }

    function testDepositRejectsUnregisteredUser() public {
        vm.prank(alice);
        bridgeTokenVault.fund(10 ether);

        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(_depositPublicSignals()[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(_depositPublicSignals()[1]),
            currentUserKey: bytes32(uint256(111)),
            currentUserValue: 0,
            updatedUserKey: bytes32(uint256(111)),
            updatedUserValue: 10
        });

        vm.expectRevert(abi.encodeWithSelector(L1TokenVault.NotRegisteredInChannel.selector, alice, channelId));
        vm.prank(alice);
        bridgeTokenVault.deposit(channelId, _depositProof(), update);
    }

    function testDepositRejectsL2ValueAtScalarFieldModulus() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        bridgeTokenVault.fund(100 ether);
        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, key, 111, _defaultNoteReceivePubKey());

        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(_depositPublicSignals()[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(_depositPublicSignals()[1]),
            currentUserKey: key,
            currentUserValue: 0,
            updatedUserKey: key,
            updatedUserValue: BLS12_381_SCALAR_FIELD_MODULUS
        });

        vm.expectRevert(abi.encodeWithSelector(L1TokenVault.L2ValueOutOfRange.selector, BLS12_381_SCALAR_FIELD_MODULUS));
        vm.prank(alice);
        bridgeTokenVault.deposit(channelId, _depositProof(), update);
    }

    function testWithdrawRejectsCurrentL2ValueAtScalarFieldModulus() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        bridgeTokenVault.fund(100 ether);
        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, key, 111, _defaultNoteReceivePubKey());

        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(_withdrawPublicSignals()[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(_withdrawPublicSignals()[1]),
            currentUserKey: key,
            currentUserValue: BLS12_381_SCALAR_FIELD_MODULUS,
            updatedUserKey: key,
            updatedUserValue: 0
        });

        vm.expectRevert(abi.encodeWithSelector(L1TokenVault.L2ValueOutOfRange.selector, BLS12_381_SCALAR_FIELD_MODULUS));
        vm.prank(alice);
        bridgeTokenVault.withdraw(channelId, _withdrawProof(), update);
    }

    function testDepositEmitsCurrentRootVectorObserved() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        bridgeTokenVault.fund(100 ether);
        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, key, 111, _defaultNoteReceivePubKey());

        uint256[5] memory pubSignals = _depositPublicSignals();
        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(pubSignals[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(pubSignals[1]),
            currentUserKey: key,
            currentUserValue: pubSignals[3],
            updatedUserKey: key,
            updatedUserValue: pubSignals[4]
        });

        _mockGrothVerifierAcceptsAllProofs();

        vm.recordLogs();
        vm.prank(alice);
        bridgeTokenVault.deposit(channelId, _depositProof(), update);

        _assertSingleCurrentRootVectorObserved(
            vm.getRecordedLogs(), _rootVector(bytes32(pubSignals[1]), INITIAL_ZERO_ROOT)
        );
    }

    function testWithdrawEmitsCurrentRootVectorObserved() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        bridgeTokenVault.fund(100 ether);
        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, key, 111, _defaultNoteReceivePubKey());

        _mockGrothVerifierAcceptsAllProofs();

        uint256[5] memory depositSignals = _depositPublicSignals();
        BridgeStructs.GrothUpdate memory depositUpdate = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(depositSignals[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(depositSignals[1]),
            currentUserKey: key,
            currentUserValue: depositSignals[3],
            updatedUserKey: key,
            updatedUserValue: depositSignals[4]
        });
        vm.prank(alice);
        bridgeTokenVault.deposit(channelId, _depositProof(), depositUpdate);

        uint256[5] memory withdrawSignals = _withdrawPublicSignals();
        BridgeStructs.GrothUpdate memory withdrawUpdate = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(withdrawSignals[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(withdrawSignals[1]),
            currentUserKey: key,
            currentUserValue: withdrawSignals[3],
            updatedUserKey: key,
            updatedUserValue: withdrawSignals[4]
        });

        vm.recordLogs();
        vm.prank(alice);
        bridgeTokenVault.withdraw(channelId, _withdrawProof(), withdrawUpdate);

        _assertSingleCurrentRootVectorObserved(
            vm.getRecordedLogs(), _rootVector(bytes32(withdrawSignals[1]), INITIAL_ZERO_ROOT)
        );
    }

    function testTokamakVerificationRejectsUnsupportedFunction() public {
        BridgeStructs.TokamakProofPayload memory proofPayload = _loadTokamakProofPayload();
        proofPayload.aPubUser[22] = uint160(address(0xBEEF));
        proofPayload.aPubUser[24] = uint32(APP_SIG);
        _writeSplitWord(proofPayload.aPubUser, 26, uint256(INITIAL_ZERO_ROOT));
        _writeSplitWord(proofPayload.aPubUser, 28, uint256(INITIAL_ZERO_ROOT));

        vm.expectRevert(
            abi.encodeWithSelector(ChannelManager.UnsupportedChannelFunction.selector, address(0xBEEF), APP_SIG)
        );
        channelManager.executeChannelTransaction(proofPayload);
    }

    function testTokamakVerificationRejectsShortAPubUser() public {
        BridgeStructs.TokamakProofPayload memory proofPayload = _loadTokamakProofPayload();
        uint256[] memory shortened = _slice(proofPayload.aPubUser, 0, 29);
        proofPayload.aPubUser = shortened;

        vm.expectRevert(
            abi.encodeWithSelector(ChannelManager.APubUserTooShort.selector, uint256(30), uint256(shortened.length))
        );
        channelManager.executeChannelTransaction(proofPayload);
    }

    function testChannelUsesRealTokamakVerifier() public view {
        assertEq(address(bridgeCore.tokamakVerifier()), address(tokamakVerifier));
    }

    function testOwnerCanUpdateVerifierAddresses() public {
        IGrothVerifier newGrothVerifier = IGrothVerifier(address(0xBEEF));
        ITokamakVerifier newTokamakVerifier = ITokamakVerifier(address(0xCAFE));

        bridgeCore.setGrothVerifier(newGrothVerifier);
        bridgeCore.setTokamakVerifier(newTokamakVerifier);

        assertEq(address(bridgeCore.grothVerifier()), address(newGrothVerifier));
        assertEq(address(bridgeCore.tokamakVerifier()), address(newTokamakVerifier));
    }

    function testDepositUsesGrothVerifierFromBridgeCore() public {
        bytes32 key = bytes32(uint256(111));
        IGrothVerifier rotatedGrothVerifier = IGrothVerifier(address(0xBEEF));

        bridgeCore.setGrothVerifier(rotatedGrothVerifier);
        assertEq(address(bridgeTokenVault.grothVerifier()), address(rotatedGrothVerifier));
        vm.mockCall(
            address(rotatedGrothVerifier), abi.encodeWithSelector(IGrothVerifier.verifyProof.selector), abi.encode(true)
        );

        vm.prank(alice);
        bridgeTokenVault.fund(100 ether);
        vm.prank(alice);
        channelManager.registerChannelTokenVaultIdentity(alice, key, 111, _defaultNoteReceivePubKey());

        uint256[5] memory pubSignals = _depositPublicSignals();
        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRootVector: _rootVector(bytes32(pubSignals[0]), INITIAL_ZERO_ROOT),
            updatedRoot: bytes32(pubSignals[1]),
            currentUserKey: key,
            currentUserValue: pubSignals[3],
            updatedUserKey: key,
            updatedUserValue: pubSignals[4]
        });

        vm.prank(alice);
        bool accepted = bridgeTokenVault.deposit(channelId, _depositProof(), update);
        assertTrue(accepted);
    }

    function testChannelExecutionUsesTokamakVerifierFromBridgeCore() public {
        ITokamakVerifier rotatedTokamakVerifier = ITokamakVerifier(address(0xCAFE));
        bridgeCore.setTokamakVerifier(rotatedTokamakVerifier);
        vm.mockCall(
            address(rotatedTokamakVerifier), abi.encodeWithSelector(ITokamakVerifier.verify.selector), abi.encode(true)
        );

        ChannelManager localChannelManager = _createExecutionChannel(3, "tokamak-rotated-verifier");
        bytes32[] memory currentRoots = _rootVector(INITIAL_ZERO_ROOT, INITIAL_ZERO_ROOT);
        bytes32[] memory updatedRoots = _rootVector(bytes32(uint256(555)), bytes32(uint256(777)));
        BridgeStructs.TokamakProofPayload memory proofPayload =
            _buildExecutableTokamakProofPayload(appContract, APP_SIG, currentRoots, updatedRoots, 11, 22, 33, 44);

        bool accepted = localChannelManager.executeChannelTransaction(proofPayload);
        assertTrue(accepted);
        assertEq(localChannelManager.currentRootVectorHash(), _hashRootVector(updatedRoots));
    }

    function testRootProxyAddressesStayStableAcrossUpgrade() public {
        address adminProxyAddress = address(adminManager);
        address dAppProxyAddress = address(dAppManager);
        address bridgeProxyAddress = address(bridgeCore);
        address bridgeTokenVaultProxyAddress = address(bridgeTokenVault);

        address previousAdminImplementation = _implementationOf(adminProxyAddress);
        address previousDAppImplementation = _implementationOf(dAppProxyAddress);
        address previousBridgeImplementation = _implementationOf(bridgeProxyAddress);
        address previousTokenVaultImplementation = _implementationOf(bridgeTokenVaultProxyAddress);

        BridgeAdminManager newAdminImplementation = new BridgeAdminManager();
        DAppManager newDAppImplementation = new DAppManager();
        BridgeCore newBridgeImplementation = new BridgeCore();
        L1TokenVault newTokenVaultImplementation = new L1TokenVault();

        adminManager.upgradeTo(address(newAdminImplementation));
        dAppManager.upgradeTo(address(newDAppImplementation));
        bridgeCore.upgradeTo(address(newBridgeImplementation));
        bridgeTokenVault.upgradeTo(address(newTokenVaultImplementation));

        assertEq(address(adminManager), adminProxyAddress);
        assertEq(address(dAppManager), dAppProxyAddress);
        assertEq(address(bridgeCore), bridgeProxyAddress);
        assertEq(address(bridgeTokenVault), bridgeTokenVaultProxyAddress);
        assertEq(adminManager.owner(), address(this));
        assertEq(dAppManager.owner(), address(this));
        assertEq(bridgeCore.owner(), address(this));
        assertEq(bridgeTokenVault.owner(), address(this));

        assertTrue(_implementationOf(adminProxyAddress) != previousAdminImplementation);
        assertTrue(_implementationOf(dAppProxyAddress) != previousDAppImplementation);
        assertTrue(_implementationOf(bridgeProxyAddress) != previousBridgeImplementation);
        assertTrue(_implementationOf(bridgeTokenVaultProxyAddress) != previousTokenVaultImplementation);
        assertEq(dAppManager.bridgeCore(), address(bridgeCore));
    }

    function testTokamakVerificationRejectsProofForUnexpectedCurrentState() public {
        ChannelManager localChannelManager = _createExecutionChannel(3, "tokamak-unexpected-current-root");
        BridgeStructs.TokamakProofPayload memory proofPayload = _buildExecutableTokamakProofPayload(
            appContract,
            APP_SIG,
            _rootVector(bytes32(uint256(111)), bytes32(uint256(222))),
            _rootVector(bytes32(uint256(333)), bytes32(uint256(444))),
            uint256(11),
            uint256(22),
            uint256(33),
            uint256(44)
        );

        vm.expectRevert(ChannelManager.UnexpectedCurrentRootVector.selector);
        localChannelManager.executeChannelTransaction(proofPayload);
    }

    function testTokamakVerificationRejectsTokenVaultRootChangeWithoutStorageWrite() public {
        BridgeStructs.TokamakProofPayload memory proofPayload = _loadTokamakProofPayload();

        _writeSplitWord(proofPayload.aPubUser, 22, uint256(uint160(appContract)));
        _writeSplitWord(proofPayload.aPubUser, 24, uint32(APP_SIG));
        _writeSplitWord(proofPayload.aPubUser, 26, uint256(INITIAL_ZERO_ROOT));
        _writeSplitWord(proofPayload.aPubUser, 28, uint256(INITIAL_ZERO_ROOT));
        _writeSplitWord(proofPayload.aPubUser, 0, 123);
        _writeSplitWord(proofPayload.aPubUser, 2, uint256(INITIAL_ZERO_ROOT));

        vm.expectRevert(ChannelManager.ChannelTokenVaultRootUpdateWithoutStorageWrite.selector);
        channelManager.executeChannelTransaction(proofPayload);
    }

    function testTokamakVerificationRejectsAPubBlockLengthMismatch() public {
        ChannelManager localChannelManager = _createExecutionChannel(3, "tokamak-short-apub-block");
        BridgeStructs.TokamakProofPayload memory proofPayload = _buildExecutableTokamakProofPayload(
            appContract,
            APP_SIG,
            _rootVector(INITIAL_ZERO_ROOT, INITIAL_ZERO_ROOT),
            _rootVector(bytes32(uint256(111)), bytes32(uint256(222))),
            uint256(11),
            uint256(22),
            uint256(33),
            uint256(44)
        );

        uint256[] memory shortened = new uint256[](67);
        for (uint256 i = 0; i < shortened.length; i++) {
            shortened[i] = proofPayload.aPubBlock[i];
        }
        proofPayload.aPubBlock = shortened;

        vm.expectRevert(
            abi.encodeWithSelector(ChannelManager.APubBlockLengthMismatch.selector, uint256(68), uint256(67))
        );
        localChannelManager.executeChannelTransaction(proofPayload);
    }

    function testTokamakVerificationUpdatesRootsAndObservedWritesOnAcceptedProof() public {
        ChannelManager localChannelManager = _createExecutionChannel(3, "tokamak-success");
        bytes32[] memory currentRoots = _rootVector(INITIAL_ZERO_ROOT, INITIAL_ZERO_ROOT);
        bytes32[] memory updatedRoots = _rootVector(bytes32(uint256(555)), bytes32(uint256(777)));
        uint256 expectedTokenVaultStorageKey = 11;
        uint256 expectedTokenVaultLeafIndex = _deriveLeafIndex(expectedTokenVaultStorageKey);
        uint256 expectedTokenVaultValue = 22;
        uint256 expectedAppStorageKey = 33;
        uint256 expectedAppValue = 44;
        BridgeStructs.TokamakProofPayload memory proofPayload = _buildExecutableTokamakProofPayload(
            appContract,
            APP_SIG,
            currentRoots,
            updatedRoots,
            expectedTokenVaultStorageKey,
            expectedTokenVaultValue,
            expectedAppStorageKey,
            expectedAppValue
        );

        vm.mockCall(
            address(tokamakVerifier), abi.encodeWithSelector(ITokamakVerifier.verify.selector), abi.encode(true)
        );
        vm.recordLogs();
        bool accepted = localChannelManager.executeChannelTransaction(proofPayload);
        assertTrue(accepted);

        assertEq(localChannelManager.currentRootVectorHash(), _hashRootVector(updatedRoots));
        assertEq(
            localChannelManager.getLatestChannelTokenVaultLeaf(expectedTokenVaultLeafIndex),
            bytes32(expectedTokenVaultValue)
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 storageWriteTopic = keccak256("StorageWriteObserved(address,uint256,uint256)");
        bytes32 rootVectorObservedTopic = keccak256("CurrentRootVectorObserved(bytes32,bytes32[])");
        uint256 storageWriteCount;
        uint256 rootVectorObservedCount;
        bool sawTokenVaultWrite;
        bool sawAppStorageWrite;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == storageWriteTopic) {
                storageWriteCount += 1;
                address storageAddr = address(uint160(uint256(logs[i].topics[1])));
                (uint256 storageKey, uint256 value) = abi.decode(logs[i].data, (uint256, uint256));
                if (storageAddr == address(0xF00D)) {
                    sawTokenVaultWrite = true;
                    assertEq(storageKey, expectedTokenVaultStorageKey);
                    assertEq(value, expectedTokenVaultValue);
                } else if (storageAddr == address(0x1234)) {
                    sawAppStorageWrite = true;
                    assertEq(storageKey, expectedAppStorageKey);
                    assertEq(value, expectedAppValue);
                }
            } else if (logs[i].topics[0] == rootVectorObservedTopic) {
                rootVectorObservedCount += 1;
            }
        }

        assertEq(storageWriteCount, 2);
        assertEq(rootVectorObservedCount, 1);
        assertTrue(sawTokenVaultWrite);
        assertTrue(sawAppStorageWrite);
    }

    function _loadTokamakProofPayload() internal view returns (BridgeStructs.TokamakProofPayload memory payload) {
        string memory json = vm.readFile(TOKAMAK_FIXTURE_PATH);

        payload.proofPart1 = _toUint128Array(json.readUintArray(".proofPart1"));
        payload.proofPart2 = json.readUintArray(".proofPart2");
        payload.functionPreprocessPart1 = _toUint128Array(json.readUintArray(".functionPreprocessPart1"));
        payload.functionPreprocessPart2 = json.readUintArray(".functionPreprocessPart2");
        uint256[] memory publicInputs = json.readUintArray(".publicInputs");
        payload.aPubUser = _slice(publicInputs, 0, 50);
        payload.aPubBlock = _currentBlockAPubBlock();
    }

    function _loadRealTokamakProofPayload() internal view returns (BridgeStructs.TokamakProofPayload memory payload) {
        string memory proofJson = vm.readFile(REAL_TOKAMAK_PROOF_PATH);
        string memory preprocessJson = vm.readFile(REAL_TOKAMAK_PREPROCESS_PATH);
        string memory instanceJson = vm.readFile(REAL_TOKAMAK_INSTANCE_PATH);

        payload.proofPart1 = _toUint128Array(proofJson.readUintArray(".proof_entries_part1"));
        payload.proofPart2 = proofJson.readUintArray(".proof_entries_part2");
        payload.functionPreprocessPart1 = _toUint128Array(preprocessJson.readUintArray(".preprocess_entries_part1"));
        payload.functionPreprocessPart2 = preprocessJson.readUintArray(".preprocess_entries_part2");
        payload.aPubUser = instanceJson.readUintArray(".a_pub_user");
        payload.aPubBlock = _normalizeAPubBlock(instanceJson.readUintArray(".a_pub_block"));
    }

    function _rootVector(bytes32 left, bytes32 right) internal pure returns (bytes32[] memory roots) {
        roots = new bytes32[](2);
        roots[0] = left;
        roots[1] = right;
    }

    function _deployAdminManagerProxy(address owner, uint8 levels) internal returns (BridgeAdminManager) {
        BridgeAdminManager implementation = new BridgeAdminManager();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(implementation), abi.encodeCall(BridgeAdminManager.initialize, (owner, levels)));
        return BridgeAdminManager(address(proxy));
    }

    function _deployDAppManagerProxy(address owner) internal returns (DAppManager) {
        DAppManager implementation = new DAppManager();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(DAppManager.initialize, (owner)));
        return DAppManager(address(proxy));
    }

    function _deployBridgeCoreProxy(
        address owner,
        BridgeAdminManager localAdminManager,
        DAppManager localDAppManager,
        IGrothVerifier localGrothVerifier,
        ITokamakVerifier localTokamakVerifier
    ) internal returns (BridgeCore) {
        BridgeCore implementation = new BridgeCore();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                BridgeCore.initialize,
                (owner, localAdminManager, localDAppManager, localGrothVerifier, localTokamakVerifier)
            )
        );
        return BridgeCore(address(proxy));
    }

    function _deployTokenVaultProxy(address owner, BridgeCore localBridgeCore) internal returns (L1TokenVault) {
        L1TokenVault implementation = new L1TokenVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                L1TokenVault.initialize,
                (
                    owner,
                    IERC20(localBridgeCore.canonicalAsset()),
                    IChannelRegistry(address(localBridgeCore))
                )
            )
        );
        return L1TokenVault(address(proxy));
    }

    function _updatedRootsFromAPubUser(uint256[] memory aPubUser, uint256 offset)
        internal
        pure
        returns (bytes32[] memory roots)
    {
        roots = new bytes32[](2);
        roots[0] = _decodeBytes32FromSplitWords(aPubUser, offset);
        roots[1] = _decodeBytes32FromSplitWords(aPubUser, offset + 2);
    }

    function _currentRootsFromAPubUser(uint256[] memory aPubUser, uint256 offset)
        internal
        pure
        returns (bytes32[] memory roots)
    {
        roots = new bytes32[](2);
        roots[0] = _decodeBytes32FromSplitWords(aPubUser, offset);
        roots[1] = _decodeBytes32FromSplitWords(aPubUser, offset + 2);
    }

    function _entryContractFromAPubUser(uint256[] memory aPubUser, uint256 offset) internal pure returns (address) {
        return address(uint160(_decodeUint256FromSplitWords(aPubUser, offset)));
    }

    function _functionSigFromAPubUser(uint256[] memory aPubUser, uint256 offset) internal pure returns (bytes4) {
        return bytes4(uint32(_decodeUint256FromSplitWords(aPubUser, offset)));
    }

    function _defaultStorageLayouts(address tokenVaultStorage, address appStorage)
        internal
        pure
        returns (BridgeStructs.StorageMetadata[] memory storageLayouts)
    {
        storageLayouts = new BridgeStructs.StorageMetadata[](2);
        storageLayouts[0] = BridgeStructs.StorageMetadata({
            storageAddr: tokenVaultStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(0))),
            userStorageSlots: _uint8Array(0),
            isChannelTokenVaultStorage: true
        });
        storageLayouts[1] = BridgeStructs.StorageMetadata({
            storageAddr: appStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(1))),
            userStorageSlots: _uint8Array(0),
            isChannelTokenVaultStorage: false
        });
    }

    function _realTokamakStorageLayouts(address entryContract, address appStorage)
        internal
        pure
        returns (BridgeStructs.StorageMetadata[] memory storageLayouts)
    {
        storageLayouts = new BridgeStructs.StorageMetadata[](2);
        storageLayouts[0] = BridgeStructs.StorageMetadata({
            storageAddr: entryContract,
            preAllocatedKeys: new bytes32[](0),
            userStorageSlots: new uint8[](0),
            isChannelTokenVaultStorage: false
        });
        storageLayouts[1] = BridgeStructs.StorageMetadata({
            storageAddr: appStorage,
            preAllocatedKeys: new bytes32[](0),
            userStorageSlots: new uint8[](0),
            isChannelTokenVaultStorage: true
        });
    }

    function _singleVaultStorageLayout(address tokenVaultStorage)
        internal
        pure
        returns (BridgeStructs.StorageMetadata[] memory storageLayouts)
    {
        storageLayouts = new BridgeStructs.StorageMetadata[](1);
        storageLayouts[0] = BridgeStructs.StorageMetadata({
            storageAddr: tokenVaultStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(2))),
            userStorageSlots: _uint8Array(0),
            isChannelTokenVaultStorage: true
        });
    }

    function _threeStorageLayouts(address firstVaultStorage, address appStorage, address secondVaultStorage)
        internal
        pure
        returns (BridgeStructs.StorageMetadata[] memory storageLayouts)
    {
        storageLayouts = new BridgeStructs.StorageMetadata[](3);
        storageLayouts[0] = BridgeStructs.StorageMetadata({
            storageAddr: firstVaultStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(0))),
            userStorageSlots: _uint8Array(0),
            isChannelTokenVaultStorage: true
        });
        storageLayouts[1] = BridgeStructs.StorageMetadata({
            storageAddr: appStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(1))),
            userStorageSlots: _uint8Array(0),
            isChannelTokenVaultStorage: false
        });
        storageLayouts[2] = BridgeStructs.StorageMetadata({
            storageAddr: secondVaultStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(2))),
            userStorageSlots: _uint8Array(0),
            isChannelTokenVaultStorage: true
        });
    }

    function _defaultDAppFunctions(bytes32 preprocessInputHash)
        internal
        view
        returns (BridgeStructs.DAppFunctionMetadata[] memory functions)
    {
        functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            preprocessInputHash: preprocessInputHash,
            instanceLayout: _instanceLayout(22, 24, 26, 0, _emptyStorageWrites())
        });
    }

    function _singleVaultDAppFunction() internal view returns (BridgeStructs.DAppFunctionMetadata[] memory functions) {
        functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract2,
            functionSig: APP_SIG_2,
            preprocessInputHash: bytes32("PREPROCESS_INPUT_2"),
            instanceLayout: _instanceLayout(22, 24, 26, 0, _emptyStorageWrites())
        });
    }

    function _executionDAppFunctions() internal view returns (BridgeStructs.DAppFunctionMetadata[] memory functions) {
        functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            preprocessInputHash: _executionPreprocessInputHash(),
            instanceLayout: _instanceLayout(22, 24, 26, 30, _executionStorageWrites())
        });
    }

    function _realTokamakFunctionMetadata(bytes32 preprocessInputHash)
        internal
        pure
        returns (BridgeStructs.DAppFunctionMetadata memory functionMetadata)
    {
        functionMetadata = BridgeStructs.DAppFunctionMetadata({
            entryContract: 0xB9Dca06940a5dC5cB98BE0fD9E2eD24eBDF05F84,
            functionSig: 0x0df1a4ac,
            preprocessInputHash: preprocessInputHash,
            instanceLayout: _instanceLayout(22, 24, 26, 8, _realTokamakStorageWrites())
        });
    }

    function _singleFunctionArray(BridgeStructs.DAppFunctionMetadata memory functionMetadata)
        internal
        pure
        returns (BridgeStructs.DAppFunctionMetadata[] memory functions)
    {
        functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = functionMetadata;
    }

    function _conflictingDAppFunctions() internal view returns (BridgeStructs.DAppFunctionMetadata[] memory functions) {
        functions = new BridgeStructs.DAppFunctionMetadata[](2);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            preprocessInputHash: bytes32("PREPROCESS_INPUT"),
            instanceLayout: _instanceLayout(22, 24, 26, 0, _emptyStorageWrites())
        });
        functions[1] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract2,
            functionSig: APP_SIG_2,
            preprocessInputHash: bytes32("PREPROCESS_INPUT_2"),
            instanceLayout: _instanceLayout(22, 24, 26, 0, _emptyStorageWrites())
        });
    }

    function _realTokamakStorageWrites()
        internal
        pure
        returns (BridgeStructs.StorageWriteMetadata[] memory storageWrites)
    {
        storageWrites = new BridgeStructs.StorageWriteMetadata[](2);
        storageWrites[0] = BridgeStructs.StorageWriteMetadata({aPubOffsetWords: 0, storageAddrIndex: 1});
        storageWrites[1] = BridgeStructs.StorageWriteMetadata({aPubOffsetWords: 4, storageAddrIndex: 0});
    }

    function _executionStorageWrites()
        internal
        pure
        returns (BridgeStructs.StorageWriteMetadata[] memory storageWrites)
    {
        storageWrites = new BridgeStructs.StorageWriteMetadata[](2);
        storageWrites[0] = BridgeStructs.StorageWriteMetadata({aPubOffsetWords: 0, storageAddrIndex: 0});
        storageWrites[1] = BridgeStructs.StorageWriteMetadata({aPubOffsetWords: 4, storageAddrIndex: 1});
    }

    function _emptyStorageWrites() internal pure returns (BridgeStructs.StorageWriteMetadata[] memory storageWrites) {
        storageWrites = new BridgeStructs.StorageWriteMetadata[](0);
    }

    function _emptyEventLogs() internal pure returns (BridgeStructs.EventLogMetadata[] memory eventLogs) {
        eventLogs = new BridgeStructs.EventLogMetadata[](0);
    }

    function _defaultNoteReceivePubKey()
        internal
        pure
        returns (BridgeStructs.NoteReceivePubKey memory noteReceivePubKey)
    {
        noteReceivePubKey = BridgeStructs.NoteReceivePubKey({x: bytes32(uint256(0x1234)), yParity: 1});
    }

    function _instanceLayout(
        uint8 entryContractOffsetWords,
        uint8 functionSigOffsetWords,
        uint8 currentRootVectorOffsetWords,
        uint8 updatedRootVectorOffsetWords,
        BridgeStructs.StorageWriteMetadata[] memory storageWrites
    ) internal pure returns (BridgeStructs.InstanceLayout memory layout) {
        layout = BridgeStructs.InstanceLayout({
            entryContractOffsetWords: entryContractOffsetWords,
            functionSigOffsetWords: functionSigOffsetWords,
            currentRootVectorOffsetWords: currentRootVectorOffsetWords,
            updatedRootVectorOffsetWords: updatedRootVectorOffsetWords,
            storageWrites: storageWrites,
            eventLogs: _emptyEventLogs()
        });
    }

    function _blankTokamakProofPayload() internal pure returns (BridgeStructs.TokamakProofPayload memory payload) {
        payload.proofPart1 = new uint128[](0);
        payload.proofPart2 = new uint256[](0);
        payload.functionPreprocessPart1 = new uint128[](0);
        payload.functionPreprocessPart2 = new uint256[](0);
        payload.aPubUser = new uint256[](50);
        payload.aPubBlock = new uint256[](68);
    }

    function _buildExecutableTokamakProofPayload(
        address entryContract,
        bytes4 functionSig,
        bytes32[] memory currentRoots,
        bytes32[] memory updatedRoots,
        uint256 tokenVaultStorageKey,
        uint256 tokenVaultValue,
        uint256 appStorageKey,
        uint256 appStorageValue
    ) internal view returns (BridgeStructs.TokamakProofPayload memory payload) {
        payload = _blankTokamakProofPayload();
        payload.functionPreprocessPart1 = _executionFunctionPreprocessPart1();
        payload.functionPreprocessPart2 = _executionFunctionPreprocessPart2();
        payload.aPubUser = new uint256[](34);
        payload.aPubBlock = _currentBlockAPubBlock();

        _writeSplitWord(payload.aPubUser, 0, tokenVaultStorageKey);
        _writeSplitWord(payload.aPubUser, 2, tokenVaultValue);
        _writeSplitWord(payload.aPubUser, 4, appStorageKey);
        _writeSplitWord(payload.aPubUser, 6, appStorageValue);
        _writeSplitWord(payload.aPubUser, 22, uint256(uint160(entryContract)));
        _writeSplitWord(payload.aPubUser, 24, uint32(functionSig));
        _writeSplitWord(payload.aPubUser, 26, uint256(currentRoots[0]));
        _writeSplitWord(payload.aPubUser, 28, uint256(currentRoots[1]));
        _writeSplitWord(payload.aPubUser, 30, uint256(updatedRoots[0]));
        _writeSplitWord(payload.aPubUser, 32, uint256(updatedRoots[1]));
    }

    function _createExecutionChannel(uint256 dappId, string memory channelLabel) internal returns (ChannelManager) {
        dAppManager.registerDApp(
            dappId,
            keccak256(bytes(channelLabel)),
            _defaultStorageLayouts(address(0xF00D), address(0x1234)),
            _executionDAppFunctions()
        );
        (address manager,) = bridgeCore.createChannel(_deriveChannelId(channelLabel), dappId, leader);
        return ChannelManager(manager);
    }

    function _normalizeAPubBlock(uint256[] memory aPubBlock) internal pure returns (uint256[] memory normalized) {
        uint256 normalizedLength = aPubBlock.length;
        if (normalizedLength > 68) {
            for (uint256 i = 68; i < normalizedLength; i++) {
                if (aPubBlock[i] != 0) {
                    revert("a_pub_block too long");
                }
            }
            normalizedLength = 68;
        }

        normalized = new uint256[](68);
        for (uint256 i = 0; i < normalizedLength; i++) {
            normalized[i] = aPubBlock[i];
        }
    }

    function _decodeBytes32FromSplitWords(uint256[] memory words, uint256 offset) internal pure returns (bytes32) {
        return bytes32(_decodeUint256FromSplitWords(words, offset));
    }

    function _decodeUint256FromSplitWords(uint256[] memory words, uint256 offset) internal pure returns (uint256) {
        return words[offset] | (words[offset + 1] << 128);
    }

    function _writeSplitWord(uint256[] memory words, uint256 offset, uint256 value) internal pure {
        words[offset] = uint128(value);
        words[offset + 1] = uint128(value >> 128);
    }

    function _currentBlockAPubBlock() internal view returns (uint256[] memory words) {
        words = new uint256[](68);
        _writeSplitWord(words, 0, uint256(uint160(address(block.coinbase))));
        _writeSplitWord(words, 2, block.timestamp);
        _writeSplitWord(words, 4, block.number);
        _writeSplitWord(words, 6, uint256(block.prevrandao));
        _writeSplitWord(words, 8, block.gaslimit);
        _writeSplitWord(words, 10, block.chainid);
        _writeSplitWord(words, 12, 0);
        _writeSplitWord(words, 14, block.basefee);
        for (uint256 i = 0; i < 4; i++) {
            uint256 blockHashNumber = block.number > (i + 1) ? block.number - (i + 1) : 0;
            _writeSplitWord(words, 16 + i * 2, uint256(blockhash(blockHashNumber)));
        }
    }

    function _setBlockContextFromAPubBlock(uint256[] memory aPubBlock) internal {
        vm.coinbase(address(uint160(_decodeUint256FromSplitWords(aPubBlock, 0))));
        vm.warp(_decodeUint256FromSplitWords(aPubBlock, 2));
        vm.roll(_decodeUint256FromSplitWords(aPubBlock, 4));
        vm.prevrandao(bytes32(_decodeUint256FromSplitWords(aPubBlock, 6)));
        vm.fee(_decodeUint256FromSplitWords(aPubBlock, 14));
        vm.chainId(_decodeUint256FromSplitWords(aPubBlock, 10));

        uint256 currentBlockNumber = block.number;
        for (uint256 i = 0; i < 4; i++) {
            vm.setBlockhash(currentBlockNumber - (i + 1), bytes32(_decodeUint256FromSplitWords(aPubBlock, 16 + i * 2)));
        }
    }

    function _depositProof() private pure returns (BridgeStructs.GrothProof memory proof) {
        proof = BridgeStructs.GrothProof({
            pA: DepositGrothProofFixture.pA(), pB: DepositGrothProofFixture.pB(), pC: DepositGrothProofFixture.pC()
        });
    }

    function _withdrawProof() private pure returns (BridgeStructs.GrothProof memory proof) {
        proof = BridgeStructs.GrothProof({
            pA: WithdrawGrothProofFixture.pA(), pB: WithdrawGrothProofFixture.pB(), pC: WithdrawGrothProofFixture.pC()
        });
    }

    function _depositPublicSignals() private pure returns (uint256[5] memory values) {
        values = [
            uint256(5829984778942235508054786484586420582947187778500268001993713384889194068958),
            uint256(12649971214846735256928973055327082315338775527920953067671803034981096374020),
            uint256(111),
            uint256(0),
            uint256(10)
        ];
    }

    function _withdrawPublicSignals() private pure returns (uint256[5] memory values) {
        values = [
            uint256(12649971214846735256928973055327082315338775527920953067671803034981096374020),
            uint256(6561881689766049952519769904166055391395720462224322729436837786896958711256),
            uint256(111),
            uint256(10),
            uint256(4)
        ];
    }

    function _mockGrothVerifierAcceptsAllProofs() private {
        vm.mockCall(
            address(grothVerifier), abi.encodeWithSelector(IGrothVerifier.verifyProof.selector), abi.encode(true)
        );
    }

    function _assertSingleCurrentRootVectorObserved(Vm.Log[] memory logs, bytes32[] memory expectedRootVector)
        private
        view
    {
        bytes32 rootVectorObservedTopic = keccak256("CurrentRootVectorObserved(bytes32,bytes32[])");
        uint256 rootVectorObservedCount;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(channelManager) && logs[i].topics[0] == rootVectorObservedTopic) {
                rootVectorObservedCount += 1;
                bytes32 emittedRootVectorHash = bytes32(logs[i].topics[1]);
                bytes32[] memory emittedRootVector = abi.decode(logs[i].data, (bytes32[]));
                assertEq(emittedRootVectorHash, _hashRootVector(expectedRootVector));
                assertEq(emittedRootVector.length, expectedRootVector.length);
                for (uint256 j = 0; j < emittedRootVector.length; j++) {
                    assertEq(emittedRootVector[j], expectedRootVector[j]);
                }
            }
        }

        assertEq(rootVectorObservedCount, 1);
    }

    function _bytes32Array(bytes32 value) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](1);
        out[0] = value;
    }

    function _uint8Array(uint8 value) internal pure returns (uint8[] memory out) {
        out = new uint8[](1);
        out[0] = value;
    }

    function _toUint128Array(uint256[] memory values) internal pure returns (uint128[] memory out) {
        out = new uint128[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            out[i] = uint128(values[i]);
        }
    }

    function _slice(uint256[] memory values, uint256 start, uint256 length)
        internal
        pure
        returns (uint256[] memory out)
    {
        out = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = values[start + i];
        }
    }

    function _computePointEncodingHash(uint128[] memory part1, uint256[] memory part2) internal pure returns (bytes32) {
        return keccak256(abi.encode(part1, part2));
    }

    function _executionPreprocessInputHash() internal pure returns (bytes32) {
        return _computePointEncodingHash(_executionFunctionPreprocessPart1(), _executionFunctionPreprocessPart2());
    }

    function _executionFunctionPreprocessPart1() internal pure returns (uint128[] memory values) {
        values = new uint128[](4);
        values[0] = 1;
        values[1] = 2;
        values[2] = 3;
        values[3] = 4;
    }

    function _executionFunctionPreprocessPart2() internal pure returns (uint256[] memory values) {
        values = new uint256[](4);
        values[0] = 5;
        values[1] = 6;
        values[2] = 7;
        values[3] = 8;
    }

    function _hashRootVector(bytes32[] memory rootVector) internal pure returns (bytes32) {
        return keccak256(abi.encode(rootVector));
    }

    function _deriveChannelId(string memory name) internal pure returns (uint256) {
        return uint256(keccak256(bytes(name)));
    }

    function _deriveLeafIndex(uint256 storageKey) internal pure returns (uint256) {
        return storageKey % TOKEN_VAULT_MT_LEAF_COUNT;
    }

    function _seedChannelCurrentRoots(ChannelManager targetChannelManager, bytes32[] memory currentRoots) internal {
        // ChannelManager layout keeps `genesisBlockNumber` at slot 0, `bridgeTokenVault` at slot 1,
        // and `currentRootVectorHash` at slot 2.
        vm.store(address(targetChannelManager), bytes32(uint256(2)), _hashRootVector(currentRoots));
    }

    function _implementationOf(address proxyAddress) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxyAddress, ERC1967_IMPLEMENTATION_SLOT))));
    }
}
