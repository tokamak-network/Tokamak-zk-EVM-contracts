// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeProofManager.sol";
import "../../src/BridgeDepositManager.sol";
import "../../src/BridgeWithdrawManager.sol";
import "../../src/BridgeAdminManager.sol";
import "../../src/interface/ITokamakVerifier.sol";
import "../../src/interface/IZecFrost.sol";
import "../../src/interface/IGroth16Verifier16Leaves.sol";
import {ZecFrost} from "../../src/library/ZecFrost.sol";
import {TokamakVerifier} from "../../src/verifier/TokamakVerifier.sol";
import {Groth16Verifier16Leaves} from "../../src/verifier/Groth16Verifier16Leaves.sol";
import {Groth16Verifier32Leaves} from "../../src/verifier/Groth16Verifier32Leaves.sol";
import {Groth16Verifier64Leaves} from "../../src/verifier/Groth16Verifier64Leaves.sol";
import {Groth16Verifier128Leaves} from "../../src/verifier/Groth16Verifier128Leaves.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockTokamakVerifier is ITokamakVerifier {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verify(
        uint128[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external view override returns (bool) {
        return shouldVerify;
    }
}

contract MockZecFrost is IZecFrost {
    address public mockSigner;
    
    // Mapping of signature vectors to their recovered addresses
    mapping(bytes32 => address) private signatureVectorToSigner;

    constructor() {
        mockSigner = address(this);
        
        // Vector 1 signature (valid) - recovers to user1 (0xd96b35D012879d89cfBA6fE215F1015863a6f6d0)
        bytes32 vector1Key = keccak256(abi.encodePacked(
            uint256(0x1fb4c0436e9054ae0b237cde3d7a478ce82405b43fdbb5bf1d63c9f8d912dd5d),
            uint256(0x3a7784df441925a8859b9f3baf8d570d488493506437db3ccf230a4b43b27c1e),
            uint256(0xc7fdcb364dd8577e47dd479185ca659adbfcd1b8675e5cbb36e5f93ca4e15b25)
        ));
        signatureVectorToSigner[vector1Key] = 0xd96b35D012879d89cfBA6fE215F1015863a6f6d0;
        
        // Vector 2 signature (invalid) - recovers to user2 (0x012C2171f631e27C4bA9f7f8262af2a48956939A)
        bytes32 vector2Key = keccak256(abi.encodePacked(
            uint256(0xc303bb5de5a5962d9af9b45f5e0bdc919de2aac9153b8c353960f50aa3cb950c),
            uint256(0x6df25261f523a8ea346f49dad49b3b36786e653a129cff327a0fea5839e712a2),
            uint256(0x27c26d628367261edb63b64eefc48a192a8130e9cd608b75820775684af010b0)
        ));
        signatureVectorToSigner[vector2Key] = 0x012C2171f631e27C4bA9f7f8262af2a48956939A;
    }

    function verify(bytes32, uint256, uint256, uint256 rx, uint256 ry, uint256 z) external view override returns (address) {
        // Check if this is one of our known signature vectors
        bytes32 vectorKey = keccak256(abi.encodePacked(rx, ry, z));
        address vectorSigner = signatureVectorToSigner[vectorKey];
        
        if (vectorSigner != address(0)) {
            return vectorSigner;
        }
        
        // Fall back to mock signer for unknown vectors
        return mockSigner;
    }

    function setMockSigner(address _signer) external {
        mockSigner = _signer;
    }
}

contract MockGroth16Verifier is IGroth16Verifier16Leaves {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[33] calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}

contract MockGroth16Verifier32 is IGroth16Verifier32Leaves {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[65] calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}

contract MockGroth16Verifier64 is IGroth16Verifier64Leaves {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[129] calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}

contract MockGroth16Verifier128 is IGroth16Verifier128Leaves {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[257] calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ProofSubmissionTest is Test {
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant INITIAL_TOKEN_BALANCE = 1000 * 10 ** 18;
    
    BridgeCore public bridge;
    BridgeProofManager public proofManager;
    BridgeDepositManager public depositManager;
    BridgeWithdrawManager public withdrawManager;
    BridgeAdminManager public adminManager;
    MockTokamakVerifier public tokamakVerifier;
    MockZecFrost public mockZecFrost;
    MockGroth16Verifier public groth16Verifier16;
    MockGroth16Verifier32 public groth16Verifier32;
    MockGroth16Verifier64 public groth16Verifier64;
    MockGroth16Verifier128 public groth16Verifier128;
    MockERC20 public token;

    address public owner = address(1);
    address public user1 = 0xF9Fa94D45C49e879E46Ea783fc133F41709f3bc7; 
    address public user2 = 0x322acfaA747F3CE5b5899611034FB4433f0Edf34;
    address public user3 = 0x31Fbd690BF62cd8C60A93F3aD8E96A6085Dc5647;

    uint256 public User1l2MPTKey = 0x5846aca7f69c5df6171620f9fe93a0b0071057dbeaea943382e36283d98d3164;
    uint256 public User2l2MPTKey = 0x30cb74383499705597743f7ebc89ac8514034e4525cc903fb79eb32ace584be7;
    uint256 public User3l2MPTKey = 0x2cba90f17ac312557f5d3eb10891ce57e40bf513a8ae0dbbf153ef6fafd5d9eb;

    uint256 public user1DepositValue = 1000000000000000000;
    uint256 public user2DepositValue = 1000000000000000000;
    uint256 public user3DepositValue = 1000000000000000000;

    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);

        tokamakVerifier = new MockTokamakVerifier();
        mockZecFrost = new MockZecFrost();
        groth16Verifier16 = new MockGroth16Verifier();
        groth16Verifier32 = new MockGroth16Verifier32();
        groth16Verifier64 = new MockGroth16Verifier64();
        groth16Verifier128 = new MockGroth16Verifier128();
        token = new MockERC20();

        // Deploy manager implementations
        BridgeDepositManager depositManagerImpl = new BridgeDepositManager();
        BridgeWithdrawManager withdrawManagerImpl = new BridgeWithdrawManager();
        BridgeAdminManager adminManagerImpl = new BridgeAdminManager();
        BridgeProofManager proofManagerImpl = new BridgeProofManager();

        // Deploy core contract with proxy first
        BridgeCore implementation = new BridgeCore();
        bytes memory bridgeInitData = abi.encodeCall(
            BridgeCore.initialize,
            (address(0), address(0), address(0), address(0), owner) // Temporary addresses
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(implementation), bridgeInitData);
        bridge = BridgeCore(address(bridgeProxy));

        // Deploy manager proxies with bridge address
        bytes memory depositInitData = abi.encodeCall(BridgeDepositManager.initialize, (address(bridge), owner));
        ERC1967Proxy depositProxy = new ERC1967Proxy(address(depositManagerImpl), depositInitData);
        depositManager = BridgeDepositManager(address(depositProxy));

        bytes memory withdrawInitData = abi.encodeCall(BridgeWithdrawManager.initialize, (address(bridge), owner));
        ERC1967Proxy withdrawProxy = new ERC1967Proxy(address(withdrawManagerImpl), withdrawInitData);
        withdrawManager = BridgeWithdrawManager(payable(address(withdrawProxy)));

        bytes memory adminInitData = abi.encodeCall(BridgeAdminManager.initialize, (address(bridge), owner));
        ERC1967Proxy adminProxy = new ERC1967Proxy(address(adminManagerImpl), adminInitData);
        adminManager = BridgeAdminManager(address(adminProxy));

        address[4] memory groth16Verifiers = [
            address(groth16Verifier16),
            address(groth16Verifier32),
            address(groth16Verifier64),
            address(groth16Verifier128)
        ];
        bytes memory proofInitData = abi.encodeCall(
            BridgeProofManager.initialize,
            (address(bridge), address(tokamakVerifier), address(mockZecFrost), groth16Verifiers, owner)
        );
        ERC1967Proxy proofProxy = new ERC1967Proxy(address(proofManagerImpl), proofInitData);
        proofManager = BridgeProofManager(address(proofProxy));

        // Update bridge with manager addresses
        bridge.updateManagerAddresses(
            address(depositManager), address(proofManager), address(withdrawManager), address(adminManager)
        );

        // Configure mock ZecFrost - we'll set the actual expected signer later in tests

        // Fund test accounts
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(user3, INITIAL_BALANCE);

        token.mint(user1, INITIAL_TOKEN_BALANCE);
        token.mint(user2, INITIAL_TOKEN_BALANCE);
        token.mint(user3, INITIAL_TOKEN_BALANCE);

        // correct preprocess for ton transfer function
        uint128[] memory preprocessedPart1 = new uint128[](4);
        preprocessedPart1[0] = 0x0009bbc7b057876cfc754a192e990683;
        preprocessedPart1[1] = 0x1508f2445c632c43eb3f9df4fc2f1894;
        preprocessedPart1[2] = 0x155cb5eeafb6e4cf7147420e1ce64b17;
        preprocessedPart1[3] = 0x150e9343bcaa1cac0acb160871c5c886;
        uint256[] memory preprocessedPart2 = new uint256[](4);
        preprocessedPart2[0] = 0x2516192ae1c6b963f3f8e0a1a88b9d669ddbb70cce11452260f4a7c0e71bdbd7;
        preprocessedPart2[1] = 0x60754cda6595f02b2696e5fad29df24e0c9343af6ef16804484b7253261564da;
        preprocessedPart2[2] = 0x6637521519a48e13f11e77f2f3b61bd40ea0a7c2d8d6455b908cd0d943fefa65;
        preprocessedPart2[3] = 0x5bab1505911b91f98e0a7515340ca6bf507c7b7286aff2c079d64acc3a9a26f8;

        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        adminManager.setAllowedTargetContract(address(token), emptySlots, true);

        // Set pre-allocated leaf with key 0x07 and value 18 (for decimals)
        adminManager.setPreAllocatedLeaf(address(token), bytes32(uint256(0x07)), 18);

        // Register transfer function using 4-byte selector (standard format)
        bytes32 transferSig = bytes32(bytes4(keccak256("transfer(address,uint256)")));
        adminManager.registerFunction(address(token), transferSig, preprocessedPart1, preprocessedPart2, keccak256("test_instance_hash"));

        vm.stopPrank();
    }

    // Helper function to set up a channel with 3 participants and deposits
    function setupChannelWithDeposits() internal returns (uint256 channelId) {
        // Open channel with user1 as leader
        vm.startPrank(user1);
        
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;
        
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            participants: participants,
            timeout: 7 days
        });
        
        channelId = bridge.openChannel(params);
        
        // Set channel public key (required before deposits)
        uint256 pkx = 0x1234567890123456789012345678901234567890123456789012345678901234;
        uint256 pky = 0x9876543210987654321098765432109876543210987654321098765432109876;
        bridge.setChannelPublicKey(channelId, pkx, pky);
        
        // User1 deposits
        token.approve(address(depositManager), user1DepositValue);
        depositManager.depositToken(channelId, user1DepositValue, bytes32(User1l2MPTKey));
        vm.stopPrank();
        
        // User2 deposits
        vm.startPrank(user2);
        token.approve(address(depositManager), user2DepositValue);
        depositManager.depositToken(channelId, user2DepositValue, bytes32(User2l2MPTKey));
        vm.stopPrank();
        
        // User3 deposits
        vm.startPrank(user3);
        token.approve(address(depositManager), user3DepositValue);
        depositManager.depositToken(channelId, user3DepositValue, bytes32(User3l2MPTKey));
        vm.stopPrank();
        
        // Initialize channel state (as leader)
        vm.startPrank(user1);
        
        // Create initialization proof
        BridgeProofManager.ChannelInitializationProof memory initProof;
        
        // Set mock proof values for groth16 proof
        initProof.pA[0] = 1;
        initProof.pA[1] = 2;
        initProof.pA[2] = 3;
        initProof.pA[3] = 4;
        
        for (uint256 i = 0; i < 8; i++) {
            initProof.pB[i] = i + 1;
        }
        
        for (uint256 i = 0; i < 4; i++) {
            initProof.pC[i] = i + 1;
        }
        
        // Set initial state root
        initProof.merkleRoot = 0x7380218991c8a0feb79bb9715fd26e2a697f6a98de69bdc71426efe52f459cfc;
        
        // Initialize channel state
        proofManager.initializeChannelState(channelId, initProof);
        
        vm.stopPrank();
        
        return channelId;
    }
    
    // Test function to verify the helper works correctly
    function testSetupChannelWithDeposits() public {
        uint256 channelId = setupChannelWithDeposits();
        
        // Verify channel is set up correctly
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(IBridgeCore.ChannelState.Open));
        assertEq(bridge.getChannelLeader(channelId), user1);
        
        // Verify participants
        address[] memory participants = bridge.getChannelParticipants(channelId);
        assertEq(participants.length, 3);
        assertEq(participants[0], user1);
        assertEq(participants[1], user2);
        assertEq(participants[2], user3);
        
        // Verify deposits
        assertEq(bridge.getParticipantDeposit(channelId, user1), user1DepositValue);
        assertEq(bridge.getParticipantDeposit(channelId, user2), user2DepositValue);
        assertEq(bridge.getParticipantDeposit(channelId, user3), user3DepositValue);
        
        // Verify L2 MPT keys
        assertEq(bridge.getL2MptKey(channelId, user1), User1l2MPTKey);
        assertEq(bridge.getL2MptKey(channelId, user2), User2l2MPTKey);
        assertEq(bridge.getL2MptKey(channelId, user3), User3l2MPTKey);
        
        // Verify pre-allocated leaf was set
        (uint256 value, bool exists) = adminManager.getPreAllocatedLeaf(address(token), bytes32(uint256(0x07)));
        assertTrue(exists, "Pre-allocated leaf should exist");
        assertEq(value, 18, "Pre-allocated leaf value should be 18");
    }
}

