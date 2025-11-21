// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/RollupBridgeCore.sol";
import "../../src/RollupBridgeProofManager.sol";
import "../../src/RollupBridgeDepositManager.sol";
import "../../src/RollupBridgeWithdrawManager.sol";
import "../../src/RollupBridgeAdminManager.sol";
import "../../src/interface/ITokamakVerifier.sol";
import "../../src/interface/IZecFrost.sol";
import "../../src/interface/IGroth16Verifier16Leaves.sol";
import {ZecFrost} from "../../src/library/ZecFrost.sol";
import {TokamakVerifier} from "../../src/verifier/TokamakVerifier.sol";
import {Groth16Verifier16Leaves} from "../../src/verifier/Groth16Verifier16Leaves.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

// Mock Contracts
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

    constructor() {
        mockSigner = address(this);
    }

    function verify(bytes32, uint256, uint256, uint256, uint256, uint256) external view override returns (address) {
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
        returns (bool)
    {
        return shouldVerify;
    }
}

contract TestERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        _setupDecimals(_decimals);
    }

    function _setupDecimals(uint8 _decimals) internal {
        // Note: This is a simplified mock. In production, you'd use OpenZeppelin's approach
        // For testing purposes, we'll just mint tokens to test addresses
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return super.decimals();
    }
}

contract WithdrawalsTest is Test {
    RollupBridgeCore public bridge;
    RollupBridgeDepositManager public depositManager;
    RollupBridgeProofManager public proofManager;
    RollupBridgeWithdrawManager public withdrawManager;
    RollupBridgeAdminManager public adminManager;

    MockTokamakVerifier public mockVerifier;
    MockZecFrost public mockZecFrost;
    MockGroth16Verifier public mockGroth16Verifier;

    TestERC20 public token;

    address public leader = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public owner = address(0x4);

    uint256 public channelId;

    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        mockVerifier = new MockTokamakVerifier();
        mockZecFrost = new MockZecFrost();
        mockGroth16Verifier = new MockGroth16Verifier();

        // Deploy test token
        token = new TestERC20("TestToken", "TT", 18);

        // Deploy implementation contracts
        RollupBridgeCore bridgeImpl = new RollupBridgeCore();
        RollupBridgeDepositManager depositManagerImpl = new RollupBridgeDepositManager();
        RollupBridgeAdminManager adminManagerImpl = new RollupBridgeAdminManager();
        RollupBridgeProofManager proofManagerImpl = new RollupBridgeProofManager();
        RollupBridgeWithdrawManager withdrawManagerImpl = new RollupBridgeWithdrawManager();

        address[4] memory groth16Verifiers = [
            address(mockGroth16Verifier),
            address(mockGroth16Verifier),
            address(mockGroth16Verifier),
            address(mockGroth16Verifier)
        ];

        // Deploy bridge with proxy pattern first
        bytes memory bridgeInitData = abi.encodeCall(
            RollupBridgeCore.initialize,
            (address(0), address(0), address(0), address(0), owner) // Temporary addresses
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(bridgeImpl), bridgeInitData);
        bridge = RollupBridgeCore(payable(address(bridgeProxy)));

        // Deploy manager contracts as proxies
        bytes memory depositInitData = abi.encodeCall(
            RollupBridgeDepositManager.initialize, (address(bridge), owner)
        );
        ERC1967Proxy depositProxy = new ERC1967Proxy(address(depositManagerImpl), depositInitData);
        depositManager = RollupBridgeDepositManager(address(depositProxy));

        bytes memory adminInitData = abi.encodeCall(
            RollupBridgeAdminManager.initialize, (address(bridge), owner)
        );
        ERC1967Proxy adminProxy = new ERC1967Proxy(address(adminManagerImpl), adminInitData);
        adminManager = RollupBridgeAdminManager(address(adminProxy));

        bytes memory proofInitData = abi.encodeCall(
            RollupBridgeProofManager.initialize, (address(bridge), address(mockVerifier), address(mockZecFrost), groth16Verifiers, owner)
        );
        ERC1967Proxy proofProxy = new ERC1967Proxy(address(proofManagerImpl), proofInitData);
        proofManager = RollupBridgeProofManager(address(proofProxy));

        bytes memory withdrawInitData = abi.encodeCall(
            RollupBridgeWithdrawManager.initialize, (address(bridge), owner)
        );
        ERC1967Proxy withdrawProxy = new ERC1967Proxy(address(withdrawManagerImpl), withdrawInitData);
        withdrawManager = RollupBridgeWithdrawManager(payable(address(withdrawProxy)));

        // Update bridge with manager addresses
        bridge.updateManagerAddresses(address(depositManager), address(proofManager), address(withdrawManager), address(adminManager));

        // Register the test token and its transfer function
        uint128[] memory preprocessedPart1 = new uint128[](4);
        uint256[] memory preprocessedPart2 = new uint256[](4);
        bytes32 transferSig = keccak256("transfer(address,uint256)");

        adminManager.setAllowedTargetContract(address(token), bytes1(0x00), true);
        adminManager.registerFunction(transferSig, preprocessedPart1, preprocessedPart2);

        vm.stopPrank();

        console.log("Setup completed, starting channel setup");

        // Setup channel for testing
        _setupChannelForWithdrawals();
    }

    function _setupChannelForWithdrawals() internal {
        console.log("Starting channel setup");
        vm.startPrank(leader);
        vm.deal(leader, 10 ether);
        console.log("Leader funded with ETH");

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = leader;

        address[] memory allowedTokens = new address[](2);
        allowedTokens[0] = bridge.ETH_TOKEN_ADDRESS();
        allowedTokens[1] = address(token);

        RollupBridgeCore.ChannelParams memory params = RollupBridgeCore.ChannelParams({
            allowedTokens: allowedTokens,
            participants: participants,
            timeout: 1 days,
            pkx: 0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            pky: 0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        });

        console.log("About to open channel");
        console.log("Required bond:", bridge.LEADER_BOND_REQUIRED());
        console.log("Leader balance:", leader.balance);

        channelId = bridge.openChannel{value: bridge.LEADER_BOND_REQUIRED()}(params);

        console.log("Channel opened with ID:", channelId);
        vm.stopPrank();

        // Make deposits
        _makeDeposits();

        // Initialize channel state
        _initializeChannelState();

        // Submit proof and close channel
        _submitProofAndCloseChannel();
    }

    function _makeDeposits() internal {
        console.log("Making deposits");
        // User1 deposits ETH
        vm.deal(user1, 5 ether);
        console.log("User1 funded with ETH");
        vm.prank(user1);
        depositManager.depositETH{value: 2 ether}(channelId, bytes32(uint256(10)));
        console.log("User1 deposited ETH");

        // User2 deposits tokens
        token.mint(user2, 1000e18);
        console.log("User2 minted tokens");
        vm.startPrank(user2);
        token.approve(address(depositManager), 500e18);
        console.log("User2 approved tokens");
        depositManager.depositToken(channelId, address(token), 500e18, bytes32(uint256(20)));
        console.log("User2 deposited tokens");
        vm.stopPrank();
    }

    function _initializeChannelState() internal {
        console.log("Initializing channel state");
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        RollupBridgeProofManager.ChannelInitializationProof memory mockProof = RollupBridgeProofManager
            .ChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });

        console.log("About to initialize channel state");
        vm.prank(leader);
        proofManager.initializeChannelState(channelId, mockProof);
        console.log("Channel state initialized");
    }

    function _submitProofAndCloseChannel() internal {
        console.log("Submitting proof and closing channel");
        // Prepare proof data
        IRollupBridgeCore.RegisteredFunction[] memory functions = new IRollupBridgeCore.RegisteredFunction[](1);
        functions[0] = IRollupBridgeCore.RegisteredFunction({
            functionSignature: keccak256("transfer(address,uint256)"),
            preprocessedPart1: new uint128[](4),
            preprocessedPart2: new uint256[](4)
        });

        // Register the function first
        console.log("Registering function");
        vm.prank(owner);
        adminManager.registerFunction(
            functions[0].functionSignature, functions[0].preprocessedPart1, functions[0].preprocessedPart2
        );
        console.log("Function registered");

        uint256[][] memory finalBalances = new uint256[][](3);
        finalBalances[0] = new uint256[](2); // user1: [ETH_amount, token_amount]
        finalBalances[0][0] = 1.5 ether; // ETH balance for user1
        finalBalances[0][1] = 100e18; // token balance for user1
        finalBalances[1] = new uint256[](2); // user2: [ETH_amount, token_amount]
        finalBalances[1][0] = 0.5 ether; // ETH balance for user2
        finalBalances[1][1] = 400e18; // token balance for user2
        finalBalances[2] = new uint256[](2); // leader: [ETH_amount, token_amount]
        finalBalances[2][0] = 0; // ETH balance for leader
        finalBalances[2][1] = 0; // token balance for leader

        RollupBridgeProofManager.ProofData memory proofData = RollupBridgeProofManager.ProofData({
            proofPart1: new uint128[](4),
            proofPart2: new uint256[](4),
            publicInputs: new uint256[](4),
            smax: 100,
            functions: functions,
            finalBalances: finalBalances
        });

        // Set up signature verification
        address expectedSigner = bridge.getChannelSignerAddr(channelId);
        console.log("Expected signer:", expectedSigner);
        mockZecFrost.setMockSigner(expectedSigner);

        RollupBridgeProofManager.Signature memory signature =
            RollupBridgeProofManager.Signature({message: keccak256("message"), rx: 1, ry: 2, z: 3});

        // Submit proof
        console.log("Submitting proof and signature");
        vm.prank(leader);
        proofManager.submitProofAndSignature(channelId, proofData, signature);
        console.log("Proof submitted");

        // Close and finalize channel
        console.log("Closing and finalizing channel");
        console.log("Channel state:", uint8(bridge.getChannelState(channelId)));
        console.log("Signature verified:", bridge.isSignatureVerified(channelId));
        console.log("Leader:", leader);
        console.log("Channel leader:", bridge.getChannelLeader(channelId));
        vm.prank(leader);
        withdrawManager.closeAndFinalizeChannel(channelId);
        console.log("Channel closed");
    }

    function testWithdrawETHSuccess() public {
        uint256 initialBalance = user1.balance;
        uint256 expectedWithdrawAmount = 1.5 ether;

        // Debug: Check if user1 is a participant and has withdrawable amount
        console.log("Is user1 participant:", bridge.isChannelParticipant(channelId, user1));
        address ethToken = bridge.ETH_TOKEN_ADDRESS();
        console.log("User1 withdrawable ETH:", bridge.getWithdrawableAmount(channelId, user1, ethToken));
        console.log("Channel participants count:", bridge.getChannelParticipants(channelId).length);

        // Give withdraw manager some ETH and tokens for testing
        vm.deal(address(withdrawManager), 10 ether);
        token.mint(address(withdrawManager), 1000e18);

        // Test the actual withdraw function (withdraws all tokens)
        uint256 initialTokenBalance = token.balanceOf(user1);
        vm.prank(user1);
        withdrawManager.withdraw(channelId);

        // User1 should receive both ETH and tokens
        assertEq(user1.balance, initialBalance + expectedWithdrawAmount, "ETH withdrawal amount incorrect");
        assertEq(token.balanceOf(user1), initialTokenBalance + 100e18, "Token withdrawal amount incorrect");
        assertTrue(bridge.hasUserWithdrawn(channelId, user1), "User withdrawal status not updated");
        assertEq(bridge.getWithdrawableAmount(channelId, user1, ethToken), 0, "ETH withdrawable amount not cleared");
        assertEq(
            bridge.getWithdrawableAmount(channelId, user1, address(token)), 0, "Token withdrawable amount not cleared"
        );
    }

    function testWithdrawTokenSuccess() public {
        uint256 initialTokenBalance = token.balanceOf(user2);
        uint256 initialEthBalance = user2.balance;
        uint256 expectedTokenWithdrawAmount = 400e18;
        uint256 expectedEthWithdrawAmount = 0.5 ether;

        // Give both tokens and ETH to withdraw manager for testing
        token.mint(address(withdrawManager), 1000e18);
        vm.deal(address(withdrawManager), 10 ether);

        vm.prank(user2);
        withdrawManager.withdraw(channelId);

        // User2 should receive both tokens and ETH
        assertEq(
            token.balanceOf(user2),
            initialTokenBalance + expectedTokenWithdrawAmount,
            "Token withdrawal amount incorrect"
        );
        assertEq(user2.balance, initialEthBalance + expectedEthWithdrawAmount, "ETH withdrawal amount incorrect");
        assertTrue(bridge.hasUserWithdrawn(channelId, user2), "User withdrawal status not updated");
        assertEq(
            bridge.getWithdrawableAmount(channelId, user2, address(token)), 0, "Token withdrawable amount not cleared"
        );
        assertEq(
            bridge.getWithdrawableAmount(channelId, user2, bridge.ETH_TOKEN_ADDRESS()),
            0,
            "ETH withdrawable amount not cleared"
        );
    }

    function testWithdrawFailsChannelNotClosed() public {
        // Create new channel that's still open
        vm.startPrank(leader);
        vm.deal(leader, 10 ether);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = leader;
        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = bridge.ETH_TOKEN_ADDRESS();

        RollupBridgeCore.ChannelParams memory params = RollupBridgeCore.ChannelParams({
            allowedTokens: allowedTokens,
            participants: participants,
            timeout: 1 days,
            pkx: 0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            pky: 0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        });

        uint256 openChannelId = bridge.openChannel{value: bridge.LEADER_BOND_REQUIRED()}(params);
        vm.stopPrank();

        address ethToken = bridge.ETH_TOKEN_ADDRESS();
        vm.prank(user1);
        vm.expectRevert("Not closed");
        withdrawManager.withdraw(openChannelId);
    }

    function testWithdrawFailsAlreadyWithdrawn() public {
        // Fund withdraw manager for both ETH and token transfers
        vm.deal(address(withdrawManager), 10 ether);
        token.mint(address(withdrawManager), 1000e18);

        // First successful withdrawal
        vm.prank(user1);
        withdrawManager.withdraw(channelId);

        // Second attempt should fail
        vm.prank(user1);
        vm.expectRevert("Already withdrawn");
        withdrawManager.withdraw(channelId);
    }

    function testWithdrawFailsNotParticipant() public {
        address nonParticipant = address(0x999);
        address ethToken = bridge.ETH_TOKEN_ADDRESS();

        vm.prank(nonParticipant);
        vm.expectRevert("Not a participant");
        withdrawManager.withdraw(channelId);
    }

    function testWithdrawOnlyAllowedTokens() public {
        // This test verifies that the withdraw function only processes tokens
        // that are in the channel's allowed tokens list
        // Fund withdraw manager for transfers
        vm.deal(address(withdrawManager), 10 ether);
        token.mint(address(withdrawManager), 1000e18);

        // User1 should be able to withdraw both ETH and allowed tokens
        uint256 user1InitialETH = user1.balance;
        uint256 user1InitialTokens = token.balanceOf(user1);

        vm.prank(user1);
        withdrawManager.withdraw(channelId);

        // Verify user1 received both ETH and tokens
        assertEq(user1.balance, user1InitialETH + 1.5 ether, "User1 ETH withdrawal failed");
        assertEq(token.balanceOf(user1), user1InitialTokens + 100e18, "User1 token withdrawal failed");
        assertTrue(bridge.hasUserWithdrawn(channelId, user1), "User1 not marked as withdrawn");
    }

    function testWithdrawFailsNoWithdrawableAmount() public {
        // Create a scenario where user has 0 withdrawable amount
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = leader;
        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = address(token);

        vm.startPrank(leader);
        vm.deal(leader, 10 ether);

        RollupBridgeCore.ChannelParams memory params = RollupBridgeCore.ChannelParams({
            allowedTokens: allowedTokens,
            participants: participants,
            timeout: 1 days,
            pkx: 0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            pky: 0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        });

        uint256 testChannelId = bridge.openChannel{value: bridge.LEADER_BOND_REQUIRED()}(params);
        vm.stopPrank();

        // Initialize and close without any final balances
        _setupEmptyChannel(testChannelId);

        vm.prank(user1);
        vm.expectRevert("No withdrawable amount");
        withdrawManager.withdraw(testChannelId);
    }

    function _setupEmptyChannel(uint256 testChannelId) internal {
        // Initialize channel state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        RollupBridgeProofManager.ChannelInitializationProof memory mockProof = RollupBridgeProofManager
            .ChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });

        vm.prank(leader);
        proofManager.initializeChannelState(testChannelId, mockProof);

        // Submit proof with empty balances
        IRollupBridgeCore.RegisteredFunction[] memory functions = new IRollupBridgeCore.RegisteredFunction[](1);
        functions[0] = IRollupBridgeCore.RegisteredFunction({
            functionSignature: keccak256("transfer(address,uint256)"),
            preprocessedPart1: new uint128[](4),
            preprocessedPart2: new uint256[](4)
        });

        uint256[][] memory emptyBalances = new uint256[][](3);
        emptyBalances[0] = new uint256[](1);
        emptyBalances[0][0] = 0; // No withdrawable amount
        emptyBalances[1] = new uint256[](1);
        emptyBalances[1][0] = 0; // No withdrawable amount
        emptyBalances[2] = new uint256[](1);
        emptyBalances[2][0] = 0; // No withdrawable amount

        RollupBridgeProofManager.ProofData memory proofData = RollupBridgeProofManager.ProofData({
            proofPart1: new uint128[](4),
            proofPart2: new uint256[](4),
            publicInputs: new uint256[](4),
            smax: 100,
            functions: functions,
            finalBalances: emptyBalances
        });

        mockZecFrost.setMockSigner(bridge.getChannelSignerAddr(testChannelId));

        RollupBridgeProofManager.Signature memory signature =
            RollupBridgeProofManager.Signature({message: keccak256("message"), rx: 1, ry: 2, z: 3});

        vm.prank(leader);
        proofManager.submitProofAndSignature(testChannelId, proofData, signature);

        vm.prank(leader);
        withdrawManager.closeAndFinalizeChannel(testChannelId);
    }

    function testWithdrawETHFailsOnTransferFailure() public {
        // Create a contract that will reject ETH transfers
        RejectingContract rejector = new RejectingContract();

        // Set up a channel where the rejector is a participant
        vm.startPrank(leader);
        vm.deal(leader, 10 ether);

        address[] memory participants = new address[](3);
        participants[0] = address(rejector);
        participants[1] = user1;
        participants[2] = leader;
        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = bridge.ETH_TOKEN_ADDRESS();

        RollupBridgeCore.ChannelParams memory params = RollupBridgeCore.ChannelParams({
            allowedTokens: allowedTokens,
            participants: participants,
            timeout: 1 days,
            pkx: 0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            pky: 0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        });

        uint256 rejectChannelId = bridge.openChannel{value: bridge.LEADER_BOND_REQUIRED()}(params);
        vm.stopPrank();

        // Setup channel with rejector having withdrawable ETH
        _setupChannelWithRejector(rejectChannelId);

        // Attempt withdrawal should fail
        address ethTokenAddr = bridge.ETH_TOKEN_ADDRESS();
        vm.prank(address(rejector));
        vm.expectRevert("ETH transfer failed");
        withdrawManager.withdraw(rejectChannelId);
    }

    function _setupChannelWithRejector(uint256 testChannelId) internal {
        // First, we need to make deposits that match the channel setup
        // The rejector channel only has ETH as allowed token, so make ETH deposits
        address[] memory participants = bridge.getChannelParticipants(testChannelId);
        address rejectorAddr = participants[0];

        // Deposit 1 ETH for the rejector
        vm.deal(rejectorAddr, 2 ether);
        vm.prank(rejectorAddr);
        depositManager.depositETH{value: 1 ether}(testChannelId, bytes32(uint256(30)));

        // Fund withdraw manager for the transfer
        vm.deal(address(withdrawManager), 2 ether);

        // Initialize channel state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        RollupBridgeProofManager.ChannelInitializationProof memory mockProof = RollupBridgeProofManager
            .ChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });

        vm.prank(leader);
        proofManager.initializeChannelState(testChannelId, mockProof);

        // Register the function first
        vm.prank(owner);
        adminManager.registerFunction(keccak256("transfer(address,uint256)"), new uint128[](4), new uint256[](4));

        // Submit proof with balance for rejector
        IRollupBridgeCore.RegisteredFunction[] memory functions = new IRollupBridgeCore.RegisteredFunction[](1);
        functions[0] = IRollupBridgeCore.RegisteredFunction({
            functionSignature: keccak256("transfer(address,uint256)"),
            preprocessedPart1: new uint128[](4),
            preprocessedPart2: new uint256[](4)
        });

        uint256[][] memory balances = new uint256[][](3);
        balances[0] = new uint256[](1);
        balances[0][0] = 1 ether; // Rejector has 1 ETH to withdraw
        balances[1] = new uint256[](1);
        balances[1][0] = 0; // user1 has 0 ETH
        balances[2] = new uint256[](1);
        balances[2][0] = 0; // leader has 0 ETH

        RollupBridgeProofManager.ProofData memory proofData = RollupBridgeProofManager.ProofData({
            proofPart1: new uint128[](4),
            proofPart2: new uint256[](4),
            publicInputs: new uint256[](4),
            smax: 100,
            functions: functions,
            finalBalances: balances
        });

        mockZecFrost.setMockSigner(bridge.getChannelSignerAddr(testChannelId));

        RollupBridgeProofManager.Signature memory signature =
            RollupBridgeProofManager.Signature({message: keccak256("message"), rx: 1, ry: 2, z: 3});

        vm.prank(leader);
        proofManager.submitProofAndSignature(testChannelId, proofData, signature);

        vm.prank(leader);
        withdrawManager.closeAndFinalizeChannel(testChannelId);
    }

    function testMultipleUsersWithdrawDifferentTokens() public {
        // Fund withdraw manager for transfers
        vm.deal(address(withdrawManager), 10 ether);
        token.mint(address(withdrawManager), 1000e18);

        // User1 withdraws all tokens (both ETH and ERC20)
        uint256 user1InitialETH = user1.balance;
        uint256 user1InitialTokens = token.balanceOf(user1);
        vm.prank(user1);
        withdrawManager.withdraw(channelId);
        assertEq(user1.balance, user1InitialETH + 1.5 ether, "User1 ETH withdrawal failed");
        assertEq(token.balanceOf(user1), user1InitialTokens + 100e18, "User1 token withdrawal failed");

        // User2 withdraws all tokens (both ETH and ERC20)
        uint256 user2InitialETH = user2.balance;
        uint256 user2InitialTokens = token.balanceOf(user2);
        vm.prank(user2);
        withdrawManager.withdraw(channelId);
        assertEq(user2.balance, user2InitialETH + 0.5 ether, "User2 ETH withdrawal failed");
        assertEq(token.balanceOf(user2), user2InitialTokens + 400e18, "User2 token withdrawal failed");

        // Both users should be marked as withdrawn
        assertTrue(bridge.hasUserWithdrawn(channelId, user1), "User1 not marked as withdrawn");
        assertTrue(bridge.hasUserWithdrawn(channelId, user2), "User2 not marked as withdrawn");
    }

    function testWithdrawZeroAmountFails() public {
        // Manually set withdrawable amount to 0 for user1 ETH
        // This would require either admin functionality or a separate test setup
        // For now, we test the revert message when amount is 0

        // Create a new test scenario where user has 0 balance
        address zeroUser = address(0x888);
        vm.startPrank(leader);
        vm.deal(leader, 10 ether);

        address[] memory participants = new address[](3);
        participants[0] = zeroUser;
        participants[1] = user1;
        participants[2] = leader;
        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = bridge.ETH_TOKEN_ADDRESS();

        RollupBridgeCore.ChannelParams memory params = RollupBridgeCore.ChannelParams({
            allowedTokens: allowedTokens,
            participants: participants,
            timeout: 1 days,
            pkx: 0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            pky: 0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        });

        uint256 zeroChannelId = bridge.openChannel{value: bridge.LEADER_BOND_REQUIRED()}(params);
        vm.stopPrank();

        _setupEmptyChannel(zeroChannelId);

        address ethTokenAddr = bridge.ETH_TOKEN_ADDRESS();
        vm.prank(zeroUser);
        vm.expectRevert("No withdrawable amount");
        withdrawManager.withdraw(zeroChannelId);
    }
}

// Contract that rejects ETH transfers
contract RejectingContract {
    // This contract will reject any ETH sent to it
    receive() external payable {
        revert("ETH rejected");
    }

    fallback() external payable {
        revert("ETH rejected");
    }
}
