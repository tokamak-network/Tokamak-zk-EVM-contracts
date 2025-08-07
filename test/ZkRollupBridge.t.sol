// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/ZKRollupBridge.sol";
import "../src/MerklePatriciaTrie.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";
import {Verifier} from "../src/Verifier.sol";

contract ZKRollupBridgeTest is Test {
    ZKRollupBridge public bridge;
    Verifier public verifier;
    ERC20Mock public token;
    
    address public owner = address(0x1);
    address public channelCreator = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);
    address public charlie = address(0x5);
    
    // L2 public keys for participants
    address public aliceL2 = address(0x13);
    address public bobL2 = address(0x14);
    address public charlieL2 = address(0x15);
    
    uint256 constant TIMEOUT = 1 days;

    // ZKP variables
    uint128[] public serializedProofPart1;
    uint256[] public serializedProofPart2;
    uint128[] public preprocessedPart1;
    uint256[] public preprocessedPart2;
    uint256[] public publicInputs;
    uint256 public smax;
    
    event ChannelOpened(uint256 indexed channelId, address indexed targetContract);
    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event StateInitialized(uint256 indexed channelId, bytes32 stateRoot);
    event ChannelClosed(uint256 indexed channelId);
    event Withdrawn(uint256 indexed channelId, address indexed participant, address indexed token, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy contracts
        verifier = new Verifier();
        bridge = new ZKRollupBridge(address(verifier));
        token = new ERC20Mock("Tokamak Network", "TON");
        
        // Authorize channel creator
        bridge.authorizeCreator(channelCreator);
        
        // Distribute tokens
        token.mint(owner, 1000 * 10**18);
        token.mint(channelCreator, 1000 * 10**18);
        token.mint(alice, 1000 * 10**18);
        token.mint(bob, 1000 * 10**18);
        token.mint(charlie, 1000 * 10**18);

        _initializeValidProofData();
        
        vm.stopPrank();
    }

    // ========== OpenChannel Tests ==========

    function test_OpenChannel_Success() public {
        vm.startPrank(channelCreator);
        
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        l2PublicKeys[2] = charlieL2;
        
        uint256[] memory contractSlots = new uint256[](2);
        contractSlots[0] = 0;
        contractSlots[1] = 1;
        
        vm.expectEmit(true, true, false, true);
        emit ChannelOpened(0, address(token));
        
        uint256 channelId = bridge.openChannel(
            address(token),
            keccak256("TON TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            TIMEOUT
        );
        
        assertEq(channelId, 0);
        
        // Verify channel state
        (address targetContract, IZKRollupBridge.ChannelState state, uint256 participantCount,) = bridge.getChannelInfo(channelId);
        assertEq(targetContract, address(token));
        assertEq(uint8(state), uint8(IZKRollupBridge.ChannelState.Initialized));
        assertEq(participantCount, 3);
        
        vm.stopPrank();
    }

    function test_OpenChannel_NotAuthorized() public {
        vm.startPrank(alice); // Alice is not authorized
        
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        l2PublicKeys[2] = charlieL2;
        
        uint256[] memory contractSlots = new uint256[](0);
        
        vm.expectRevert("Not authorized");
        bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            TIMEOUT
        );
        
        vm.stopPrank();
    }

    function test_OpenChannel_InvalidParticipantCount() public {
        vm.startPrank(channelCreator);
        
        // Test with too few participants (less than MIN_PARTICIPANTS)
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;
        
        address[] memory l2PublicKeys = new address[](2);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        
        uint256[] memory contractSlots = new uint256[](0);
        
        vm.expectRevert("Invalid participant number");
        bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            TIMEOUT
        );
        
        vm.stopPrank();
    }

    function test_OpenChannel_MismatchedArrays() public {
        vm.startPrank(channelCreator);
        
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        
        // L2 public keys array with different length
        address[] memory l2PublicKeys = new address[](2);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        
        uint256[] memory contractSlots = new uint256[](0);
        
        vm.expectRevert("Mismatched arrays");
        bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            TIMEOUT
        );
        
        vm.stopPrank();
    }

    function test_OpenChannel_InvalidTimeout() public {
        vm.startPrank(channelCreator);
        
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        l2PublicKeys[2] = charlieL2;
        
        uint256[] memory contractSlots = new uint256[](0);
        
        // Test with timeout too short
        vm.expectRevert("Invalid timeout");
        bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            30 minutes // Less than 1 hour
        );
        
        // Test with timeout too long
        vm.expectRevert("Invalid timeout");
        bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            8 days // More than 7 days
        );
        
        vm.stopPrank();
    }

    function test_OpenChannel_DuplicateParticipant() public {
        vm.startPrank(channelCreator);
        
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = alice; // Duplicate
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        l2PublicKeys[2] = aliceL2;
        
        uint256[] memory contractSlots = new uint256[](0);
        
        vm.expectRevert("Duplicate participant");
        bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            TIMEOUT
        );
        
        vm.stopPrank();
    }

    function test_OpenChannel_ChannelLimitReached() public {
        vm.startPrank(channelCreator);
        
        // Open first channel successfully
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        l2PublicKeys[2] = charlieL2;
        
        uint256[] memory contractSlots = new uint256[](0);
        
        bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            TIMEOUT
        );
        
        // Try to open second channel - should fail
        vm.expectRevert("Channel limit reached");
        bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            TIMEOUT
        );
        
        vm.stopPrank();
    }

    // ========== Deposit Tests ==========

    function test_DepositToken_Success() public {
        // First open a channel
        uint256 channelId = _openTestChannel();
        
        // Alice deposits tokens
        vm.startPrank(alice);
        uint256 depositAmount = 100 * 10**18;
        token.approve(address(bridge), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposited(channelId, alice, address(token), depositAmount);
        
        bridge.depositToken(channelId, address(token), depositAmount);
        
        vm.stopPrank();
    }

    function test_DepositETH_Success() public {
        // Open a channel for ETH
        vm.startPrank(channelCreator);
        
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        l2PublicKeys[2] = charlieL2;
        
        uint256 channelId = bridge.openChannel(
            bridge.ETH_TOKEN_ADDRESS(),
            keccak256("ETH TRANSFER"),
            participants,
            l2PublicKeys,
            new uint256[](0),
            new uint128[](0),
            new uint256[](0),
            TIMEOUT
        );
        
        vm.stopPrank();
        
        // Alice deposits ETH
        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        
        uint256 depositAmount = 1 ether;
        
        vm.expectEmit(true, true, true, true);
        emit Deposited(channelId, alice, bridge.ETH_TOKEN_ADDRESS(), depositAmount);
        
        bridge.depositETH{value: depositAmount}(channelId);
        
        vm.stopPrank();
    }

    // ========== Initialize State ==========

    
    function test_InitializeChannelState_WithGasLimit() public {
        // Set a high gas limit for this test
        vm.txGasPrice(1);
        
        // Step 1: Open channel
        vm.startPrank(channelCreator);
        
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        l2PublicKeys[2] = charlieL2;
        
        uint256 channelId = bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            new uint256[](0),
            new uint128[](0),
            new uint256[](0),
            TIMEOUT
        );
        
        vm.stopPrank();
        
        // Step 2: Make deposits
        vm.startPrank(alice);
        token.approve(address(bridge), 100 * 10**18);
        bridge.depositToken(channelId, address(token), 100 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(bob);
        token.approve(address(bridge), 200 * 10**18);
        bridge.depositToken(channelId, address(token), 200 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        token.approve(address(bridge), 150 * 10**18);
        bridge.depositToken(channelId, address(token), 150 * 10**18);
        vm.stopPrank();
        
        // Step 3: Initialize with high gas limit
        vm.startPrank(channelCreator);
        
        // Increase gas limit for the initialization call
        uint256 gasStart = gasleft();
        
        vm.expectEmit(true, false, false, false);
        emit StateInitialized(channelId, bytes32(0));
        
        // Call with explicit gas limit
        (bool success,) = address(bridge).call{gas: 50_000_000}(
            abi.encodeWithSignature("initializeChannelState(uint256)", channelId)
        );
        
        require(success, "Initialize failed");
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for initialization:", gasUsed);
        
        // Verify state changed
        (, IZKRollupBridge.ChannelState state,,) = bridge.getChannelInfo(channelId);
        assertEq(uint8(state), uint8(IZKRollupBridge.ChannelState.Open));
        
        vm.stopPrank();
    }


    // ========== Helper Functions ==========

    function _openTestChannel() internal returns (uint256) {
        vm.startPrank(channelCreator);
        
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        
        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = aliceL2;
        l2PublicKeys[1] = bobL2;
        l2PublicKeys[2] = charlieL2;
        
        uint256[] memory contractSlots = new uint256[](0);
        
        uint256 channelId = bridge.openChannel(
            address(token),
            keccak256("TRANSFER"),
            participants,
            l2PublicKeys,
            contractSlots,
            preprocessedPart1,
            preprocessedPart2,
            TIMEOUT
        );
        
        vm.stopPrank();
        
        return channelId;
    }

    function _initializeValidProofData() internal {
        // serializedProofPart1: First 16 bytes (32 hex chars) of each coordinate
        // serializedProofPart2: Last 32 bytes (64 hex chars) of each coordinate
        // preprocessedPart1: First 16 bytes (32 hex chars) of each preprocessed committment coordinate
        // preprocessedPart2: last 32 bytes (64 hex chars) of each preprocessed committment coordinate


        // PREPROCESSED PART 1 (First 16 bytes - 32 hex chars)
        preprocessedPart1.push(0x042df2d7ba82218503dbadeaa9e87792);
        preprocessedPart1.push(0x0801f08b0423c3bb6cc7640b59e2ad81);
        preprocessedPart1.push(0x14d6acdf7112c181e4b618ae54cf2dbb);
        preprocessedPart1.push(0x0620aa348ac912429c4397e4083ba707);

        // PREPROCESSED PART 2 (Last 32 bytes - 64 hex chars)
        preprocessedPart2.push(0xebcab00c3413baa3b039e936e26e87f30a8ed8e4260497bfd1dc2227674f0d02);
        preprocessedPart2.push(0xb3cb4d475bbb5b22058c8ce67c59d218277dbdb6ae79e1e083cc74bc2197b283);
        preprocessedPart2.push(0x9fde9d8a778d5c673020961f56a2976b4cde817a6b617b2dd830da65787a21cd);
        preprocessedPart2.push(0x8c800ff423029764962680ccc47ad3244a8669361f84ad5922f8659e5b8a678e);

        // SERIALIZED PROOF PART 1 (First 16 bytes - 32 hex chars)
        serializedProofPart1.push(0x0c24fdec12d53a11da4d980c17d4e1a0);
        serializedProofPart1.push(0x17a05805dfe64737462cc7905747825b);
        serializedProofPart1.push(0x0896a633d5adf4b47c13d51806d66a35);
        serializedProofPart1.push(0x0a083a0932bebfbe2075aaf972cc5af7);
        serializedProofPart1.push(0x0a28401cd04c6e2e0bf2677b09d43a4c);
        serializedProofPart1.push(0x182ee1ed2f42610a39b255b4a0e84ee5);
        serializedProofPart1.push(0x0bd00d0783c76029e7d10c85d8b7a054);
        serializedProofPart1.push(0x087cbceebc924fadbff19a7059e44a68);
        serializedProofPart1.push(0x0ab348bc443f0fae8b8cf657e1c970ce);
        serializedProofPart1.push(0x1445acc8d6f02dddd0e17eaafd98d200);
        serializedProofPart1.push(0x001708378a5785dc70d0e217112197b9);
        serializedProofPart1.push(0x0783caf01311feb7b0896a179ad220d2);
        serializedProofPart1.push(0x0c5479dab696569b5943662da9194b3b);
        serializedProofPart1.push(0x0cabc8d2b5e630fd8b5698e2d4ce9370);
        serializedProofPart1.push(0x11d4bbafa0da1fc302112e38300bd9a1);
        serializedProofPart1.push(0x0a3c0cc511d40fa513a97ab0fae9da99);
        serializedProofPart1.push(0x03dbeb7f79d515638ed23e5ce018f592);
        serializedProofPart1.push(0x0d1c6c26b1f7d69bb0441eb8fde52aa4);
        serializedProofPart1.push(0x04be84681792a0a5afabba29ed3fcfb8);
        serializedProofPart1.push(0x05fb88f7324750e43d173a23aee8181e);
        serializedProofPart1.push(0x170f46f976ef61677cbebcdefb74feeb);
        serializedProofPart1.push(0x0b17a6a12b6fb13eca79be94abc8582b);
        serializedProofPart1.push(0x064aac9536b7b2ce667f9ba6a28cb1d3);
        serializedProofPart1.push(0x15f89d14f23e7cd275787c22e59b7cfb);
        serializedProofPart1.push(0x1768019026542d286a58258435158b31);
        serializedProofPart1.push(0x0a61414b5c2ccfe907df78c2b39bcd2e);
        serializedProofPart1.push(0x04f4c3891678a4e32c90b78e11a6ade1);
        serializedProofPart1.push(0x1982759528c860a8757bc2afc9f7fda4);
        serializedProofPart1.push(0x158ca44f01aac0407705fe5cc4d44f5c);
        serializedProofPart1.push(0x0a03d544f26007212ab4d53d3a8fcb87);
        serializedProofPart1.push(0x086ece3d5d70f8815d8b1c3659ca8a8a);
        serializedProofPart1.push(0x10b90670319cd41cf4af3e0b474be4ca);
        serializedProofPart1.push(0x158ca44f01aac0407705fe5cc4d44f5c);
        serializedProofPart1.push(0x0a03d544f26007212ab4d53d3a8fcb87);
        serializedProofPart1.push(0x126cbc300279a36e774d9e1c1953e9dc);
        serializedProofPart1.push(0x0ee0a0e6d60e1f8527d56093560223f5);
        serializedProofPart1.push(0x18ab22994ea4cb2eb9ebea8af602f8dd);
        serializedProofPart1.push(0x129eab9c15fcd487d09de770171b6912);

        // SERIALIZED PROOF PART 2 (Last 32 bytes - 64 hex chars)
        serializedProofPart2.push(0x29afb6b437675cf15e0324fe3bad032c88bd9addc36ff22855acb73a5c3f4cef);
        serializedProofPart2.push(0xdd670e5cdb1a14f5842e418357b752ee2200d5eab40a3990615224f2467c985a);
        serializedProofPart2.push(0xa379b716417a5870cc2f334e28cd91a388c5e3f18012f24700a103ea0c2aacb2);
        serializedProofPart2.push(0xffaac16f6dc2f74a0e7e18fba4e5585b4e5d642ded1156a1f58f48853e59aa42);
        serializedProofPart2.push(0xa23bfdfdfca0f91636ecc5527ac26058e20d58bac954eb642bae8bd626ef7010);
        serializedProofPart2.push(0x6f9598e15cdb8c85c5ac7ac0a78e1385446815324b91f17efacada8c544d2196);
        serializedProofPart2.push(0xba1b4b3bc86fb24b15799faa6c863b93de799bcb6a7aa6b000dff5e3dab2471f);
        serializedProofPart2.push(0xec6e41cb9cf3cc5910993ea9f08f40bd100ddf83f93f04e6bdd316797ef0beb0);
        serializedProofPart2.push(0xe9df3c6debe8c19110bc1d660e4deb5a52301ac37ecc90879bd68ecc8d97bdd2);
        serializedProofPart2.push(0x00fc98c6635577ff28950f2143aa83508c93095237abd83d69e2b24886dea95a);
        serializedProofPart2.push(0x63914eaba1999e91128214fdc6658ecfbc495062ceef8457ca7a1ec6c0d0e0eb);
        serializedProofPart2.push(0xd5bbef14f885ccbe203d48b0014ffdb943845363b278c4ab5be13674a2378134);
        serializedProofPart2.push(0x3d07b6d0abc0874227371ff6317cac98105f2f6fc1181cd1d66a4e4ec946cc65);
        serializedProofPart2.push(0x3f31b28005195499d4af392ca85edb0cee55452f39d4237641476955548e12af);
        serializedProofPart2.push(0xa66c27ac6a19f296259e0979530c4fcd90cb9e74249871c0c6489485404d9063);
        serializedProofPart2.push(0xd72bca363ba9ae574db315d4336478d0042b3e0e61270a4792a28368185a3194);
        serializedProofPart2.push(0xed8921adcbf1cf3805b293511a1b11363907a3aac8f481d8fd94374c040e5d6b);
        serializedProofPart2.push(0xd434523ed473b876e8ec1d784d149db6f706deac4d472677587a1fce0a161b3b);
        serializedProofPart2.push(0x6ea759852f22461d6206b877123aa7b5e0c8c2f252bcfd67e7db9e270f4f89f0);
        serializedProofPart2.push(0x58673a8bd4ce54d417f3f4611f1a17babe9ae036c26dbd1c090b5aa21b103e7e);
        serializedProofPart2.push(0x795bb282127eb89f0f74f3ac4225110c7f6ba1d28ee3585c5d2f9fd87407a076);
        serializedProofPart2.push(0x1c5f55837e396d3133e3327a1d55181c43e70a40175eec9830f504196143addc);
        serializedProofPart2.push(0xd6f85a33ffc841e63ffb0f7397933fbc479255bc76350181f60e8a674ce4a511);
        serializedProofPart2.push(0x042e8d8894ad3c74b0a4e53b6d4ed6ef593d6c289192c995573db09388ff6d11);
        serializedProofPart2.push(0x1569d3423b1b51e0bc46ba0eb5cc6a5d85d824a38380712cc45cf82afaf207a5);
        serializedProofPart2.push(0x1ab0450608bd2e5ba51dc73326511bf150fc5641615ae710a50b693b243642c7);
        serializedProofPart2.push(0x08daa13bff0ada0a5bc43ed4d7cea70dd8f326ceb3b4e45c371dd2700ef6f0c6);
        serializedProofPart2.push(0x4b3655e123391a00b8d3071defdab3c8b8417c0f5a547d6b589dcd20ecd33e7e);
        serializedProofPart2.push(0xc6e1ae5fca24804ade878f6ef38651c10c05a135e3f97bfd2d904fda94c7a9b1);
        serializedProofPart2.push(0x7a4e463b9e70b0b696dfbdf889158587a97fef29a5ccec0e9280623518965f4d);
        serializedProofPart2.push(0xcc5b7968dccd9e745adadb83015cd9e23c93952cb531f2f4288da589c0069574);
        serializedProofPart2.push(0xe7f91b230e048be6e77b32dc40b244236168ca832273465751c4f2ccc01cbf64);
        serializedProofPart2.push(0xc6e1ae5fca24804ade878f6ef38651c10c05a135e3f97bfd2d904fda94c7a9b1);
        serializedProofPart2.push(0x7a4e463b9e70b0b696dfbdf889158587a97fef29a5ccec0e9280623518965f4d);
        serializedProofPart2.push(0xbaea13ee7c8871272649ac7715c915a9a56ed50a8dea0571e2eff309d40f58ab);
        serializedProofPart2.push(0x82225a228142d0995337f879f93baf9f33e98586d1fc033a7dacbef88a99fe20);
        serializedProofPart2.push(0x4f776b37f90ad57ce6ea738d9aa08ab70f7b59b4f3936d07b1232bb77dc23b49);
        serializedProofPart2.push(0x9186c52b1e29b407b2ced700d98969bd27ef020d51bedc925a12759bc01b277d);
        serializedProofPart2.push(0x5cbd85f2d305fe00912332e05075b9f0de9c10f44ec7ab91b1f62084281f248c);
        serializedProofPart2.push(0x72369709049708f987668022c05c3ff71329e24dbda58f5107687c2c1c019bc3);
        serializedProofPart2.push(0x54bf083810754a2f2e0ea1a9c2cc1cd0dff97d8fd62a463be309018d5e482d10);
        serializedProofPart2.push(0x4f95625e828ae72498ff9d6e15029b414cd6cc9a8ba6d8f1dc1366f2879c76a8);

        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        ///////////////////////////////////             PUBLIC INPUTS             ////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

        publicInputs.push(0x00000000000000000000000000000000ad92adf90254df20eb73f68015e9a000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000001e371b2);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x00000000000000000000000000000000ad92adf90254df20eb73f68015e9a000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000001e371b2);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x00000000000000000000000000000000bcbd36a06b28bf1d5459edbe7dea2c85);
        publicInputs.push(0x00000000000000000000000000000000000000000000000000000000fc284778);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x00000000000000000000000000000000bcbd36a06b28bf1d5459edbe7dea2c85);
        publicInputs.push(0x00000000000000000000000000000000000000000000000000000000fc284778);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x000000000000000000000000000000004c9920779783843241d6b450935960df);
        publicInputs.push(0x00000000000000000000000000000000e69a44d2db21957ed88948127ec06b10);
        publicInputs.push(0x000000000000000000000000000000004c9920779783843241d6b450935960df);
        publicInputs.push(0x00000000000000000000000000000000e69a44d2db21957ed88948127ec06b10);
        publicInputs.push(0x000000000000000000000000000000004cba917fb9796a16f3ca5bc38b943d00);
        publicInputs.push(0x0000000000000000000000000000000099377efdd5f7e86f7648b87c1eccd6a8);
        publicInputs.push(0x000000000000000000000000000000004cba917fb9796a16f3ca5bc38b943d00);
        publicInputs.push(0x0000000000000000000000000000000099377efdd5f7e86f7648b87c1eccd6a8);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs.push(0x0000000000000000000000000000000000000000000000000000000000000000);

        smax = 512;
    }
}