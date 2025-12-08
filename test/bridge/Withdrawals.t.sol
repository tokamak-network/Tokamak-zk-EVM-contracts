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
    BridgeCore public bridge;
    BridgeDepositManager public depositManager;
    BridgeProofManager public proofManager;
    BridgeWithdrawManager public withdrawManager;
    BridgeAdminManager public adminManager;

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
        BridgeCore bridgeImpl = new BridgeCore();
        BridgeDepositManager depositManagerImpl = new BridgeDepositManager();
        BridgeAdminManager adminManagerImpl = new BridgeAdminManager();
        BridgeProofManager proofManagerImpl = new BridgeProofManager();
        BridgeWithdrawManager withdrawManagerImpl = new BridgeWithdrawManager();

        address[4] memory groth16Verifiers = [
            address(mockGroth16Verifier),
            address(mockGroth16Verifier),
            address(mockGroth16Verifier),
            address(mockGroth16Verifier)
        ];

        // Deploy bridge with proxy pattern first
        bytes memory bridgeInitData = abi.encodeCall(
            BridgeCore.initialize,
            (address(0), address(0), address(0), address(0), owner) // Temporary addresses
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(bridgeImpl), bridgeInitData);
        bridge = BridgeCore(payable(address(bridgeProxy)));

        // Deploy manager contracts as proxies
        bytes memory depositInitData = abi.encodeCall(BridgeDepositManager.initialize, (address(bridge), owner));
        ERC1967Proxy depositProxy = new ERC1967Proxy(address(depositManagerImpl), depositInitData);
        depositManager = BridgeDepositManager(address(depositProxy));

        bytes memory adminInitData = abi.encodeCall(BridgeAdminManager.initialize, (address(bridge), owner));
        ERC1967Proxy adminProxy = new ERC1967Proxy(address(adminManagerImpl), adminInitData);
        adminManager = BridgeAdminManager(address(adminProxy));

        bytes memory proofInitData = abi.encodeCall(
            BridgeProofManager.initialize,
            (address(bridge), address(mockVerifier), address(mockZecFrost), groth16Verifiers, owner)
        );
        ERC1967Proxy proofProxy = new ERC1967Proxy(address(proofManagerImpl), proofInitData);
        proofManager = BridgeProofManager(address(proofProxy));

        bytes memory withdrawInitData = abi.encodeCall(BridgeWithdrawManager.initialize, (address(bridge), owner));
        ERC1967Proxy withdrawProxy = new ERC1967Proxy(address(withdrawManagerImpl), withdrawInitData);
        withdrawManager = BridgeWithdrawManager(payable(address(withdrawProxy)));

        // Update bridge with manager addresses
        bridge.updateManagerAddresses(
            address(depositManager), address(proofManager), address(withdrawManager), address(adminManager)
        );

        // Register the test token and its transfer function
        uint128[] memory preprocessedPart1 = new uint128[](4);
        uint256[] memory preprocessedPart2 = new uint256[](4);
        bytes32 transferSig = bytes32(bytes4(keccak256("transfer(address,uint256)")));

        adminManager.setAllowedTargetContract(address(token), bytes1(0x00), true);
        adminManager.registerFunction(transferSig, preprocessedPart1, preprocessedPart2, keccak256("test_instance_hash"));

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


        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});

        console.log("About to open channel");
        console.log("Leader balance:", leader.balance);

        channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

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
        // User1 deposits tokens
        token.mint(user1, 1000e18);
        console.log("User1 minted tokens");
        vm.startPrank(user1);
        token.approve(address(depositManager), 2e18);
        console.log("User1 approved tokens");
        depositManager.depositToken(channelId, 2e18, bytes32(uint256(10)));
        console.log("User1 deposited tokens");
        vm.stopPrank();

        // User2 deposits tokens
        token.mint(user2, 1000e18);
        console.log("User2 minted tokens");
        vm.startPrank(user2);
        token.approve(address(depositManager), 500e18);
        console.log("User2 approved tokens");
        depositManager.depositToken(channelId, 500e18, bytes32(uint256(20)));
        console.log("User2 deposited tokens");
        vm.stopPrank();
    }

    function _initializeChannelState() internal {
        console.log("Initializing channel state");
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        BridgeProofManager.ChannelInitializationProof memory mockProof = BridgeProofManager
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
        // Register the function first
        console.log("Registering function");
        bytes32 transferSig = bytes32(bytes4(keccak256("transfer(address,uint256)")));
        vm.prank(owner);
        adminManager.registerFunction(
            transferSig, new uint128[](4), new uint256[](4), keccak256("test_instance_hash")
        );
        console.log("Function registered");

        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 102e18; // token balance for user1 (2e18 deposited + 100e18 from scenario)
        finalBalances[1] = 400e18; // token balance for user2 (500e18 - 100e18 transferred to user1)
        finalBalances[2] = 0; // token balance for leader

        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot")); // Set non-zero final state root
        _setWithdrawalsTestStateRoots(publicInputs);
        
        BridgeProofManager.ProofData memory proofData = BridgeProofManager.ProofData({
            proofPart1: new uint128[](4),
            proofPart2: new uint256[](4),
            publicInputs: publicInputs,
            smax: 100
        });

        // Set up signature verification
        address expectedSigner = bridge.getChannelSignerAddr(channelId);
        console.log("Expected signer:", expectedSigner);
        mockZecFrost.setMockSigner(expectedSigner);

        bytes32 commitmentHash = keccak256(abi.encodePacked(channelId, bytes32(uint256(keccak256("finalStateRoot")))));
        BridgeProofManager.Signature memory signature =
            BridgeProofManager.Signature({message: commitmentHash, rx: 1, ry: 2, z: 3});

        // Advance time to pass the timeout
        vm.warp(block.timestamp + 1 days + 1);
        console.log("Time advanced past timeout");

        // Submit proof
        console.log("Submitting proof and signature");
        vm.prank(leader);
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofData), signature);
        console.log("Proof submitted");

        // Verify final balances to close channel
        console.log("Verifying final balances");
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });
        proofManager.verifyFinalBalancesGroth16(channelId, finalBalances, finalizationProof);

        console.log("Channel closed");
    }

    function testWithdrawTokenSuccess() public {
        uint256 expectedWithdrawAmount = 102e18;

        // Debug: Check if user1 is a participant and has withdrawable amount
        console.log("Is user1 participant:", bridge.isChannelParticipant(channelId, user1));
        console.log("User1 withdrawable tokens:", bridge.getWithdrawableAmount(channelId, user1));
        console.log("Channel participants count:", bridge.getChannelParticipants(channelId).length);

        // Give withdraw manager tokens for testing
        token.mint(address(withdrawManager), 1000e18);

        // Test the actual withdraw function
        uint256 initialTokenBalance = token.balanceOf(user1);
        vm.prank(user1);
        withdrawManager.withdraw(channelId);

        // User1 should receive tokens
        assertEq(
            token.balanceOf(user1), initialTokenBalance + expectedWithdrawAmount, "Token withdrawal amount incorrect"
        );
        assertEq(
            bridge.getWithdrawableAmount(channelId, user1), 0, "Token withdrawable amount not cleared"
        );
    }

    function testWithdrawTokenUser2Success() public {
        uint256 initialTokenBalance = token.balanceOf(user2);
        uint256 expectedTokenWithdrawAmount = 400e18;

        // Give tokens to withdraw manager for testing
        token.mint(address(withdrawManager), 1000e18);

        vm.prank(user2);
        withdrawManager.withdraw(channelId);

        // User2 should receive tokens
        assertEq(
            token.balanceOf(user2),
            initialTokenBalance + expectedTokenWithdrawAmount,
            "Token withdrawal amount incorrect"
        );
        assertEq(
            bridge.getWithdrawableAmount(channelId, user2), 0, "Token withdrawable amount not cleared"
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

        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});

        uint256 openChannelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            openChannelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("Not closed");
        withdrawManager.withdraw(openChannelId);
    }

    function testWithdrawFailsNoWithdrawableAmountForToken() public {
        // Fund withdraw manager for both ETH and token transfers
        vm.deal(address(withdrawManager), 10 ether);
        token.mint(address(withdrawManager), 1000e18);

        // First successful withdrawal
        vm.prank(user1);
        withdrawManager.withdraw(channelId);

        // Second attempt should fail - no more tokens to withdraw
        vm.prank(user1);
        vm.expectRevert("No withdrawable amount for this token");
        withdrawManager.withdraw(channelId);
    }

    function testWithdrawFailsNotParticipant() public {
        address nonParticipant = address(0x999);
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

        // User1 should be able to withdraw allowed tokens
        uint256 user1InitialTokens = token.balanceOf(user1);

        vm.prank(user1);
        withdrawManager.withdraw(channelId);

        // Verify user1 received tokens
        assertEq(token.balanceOf(user1), user1InitialTokens + 102e18, "User1 token withdrawal failed");
    }

    function testWithdrawFailsNoWithdrawableAmount() public {
        // Create a scenario where user has 0 withdrawable amount
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = leader;

        vm.startPrank(leader);
        vm.deal(leader, 10 ether);

        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});

        uint256 testChannelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            testChannelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );
        vm.stopPrank();

        // Initialize and close without any final balances
        _setupEmptyChannel(testChannelId);

        vm.prank(user1);
        vm.expectRevert("No withdrawable amount for this token");
        withdrawManager.withdraw(testChannelId);
    }

    function _setupEmptyChannel(uint256 testChannelId) internal {
        // Initialize channel state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        BridgeProofManager.ChannelInitializationProof memory mockProof = BridgeProofManager
            .ChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });

        vm.prank(leader);
        proofManager.initializeChannelState(testChannelId, mockProof);

        // Submit proof with empty balances

        uint256[] memory emptyBalances = new uint256[](3);
        emptyBalances[0] = 0; // No withdrawable amount
        emptyBalances[1] = 0; // No withdrawable amount
        emptyBalances[2] = 0; // No withdrawable amount

        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot")); // Set non-zero final state root
        _setWithdrawalsTestStateRoots(publicInputs);
        
        BridgeProofManager.ProofData memory proofData = BridgeProofManager.ProofData({
            proofPart1: new uint128[](4),
            proofPart2: new uint256[](4),
            publicInputs: publicInputs,
            smax: 100
        });

        mockZecFrost.setMockSigner(bridge.getChannelSignerAddr(testChannelId));

        bytes32 commitmentHash = keccak256(abi.encodePacked(testChannelId, bytes32(uint256(keccak256("finalStateRoot")))));
        BridgeProofManager.Signature memory signature =
            BridgeProofManager.Signature({message: commitmentHash, rx: 1, ry: 2, z: 3});

        // Advance time to pass the timeout
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);
        proofManager.submitProofAndSignature(testChannelId, _wrapProofInArray(proofData), signature);

        // Verify final balances to close channel
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });
        proofManager.verifyFinalBalancesGroth16(testChannelId, emptyBalances, finalizationProof);
    }

    function testWithdrawTokenFailsOnTransferFailure() public {
        // Create a contract that will reject token transfers (insufficient balance)
        RejectingContract rejector = new RejectingContract();

        // Set up a channel where the rejector is a participant
        vm.startPrank(leader);
        vm.deal(leader, 10 ether);

        address[] memory participants = new address[](3);
        participants[0] = address(rejector);
        participants[1] = user1;
        participants[2] = leader;

        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});

        uint256 rejectChannelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            rejectChannelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );
        vm.stopPrank();

        // Setup channel with rejector having withdrawable tokens
        _setupChannelWithRejector(rejectChannelId);

        // Attempt withdrawal should fail
        vm.prank(address(rejector));
        vm.expectRevert(); // ERC20InsufficientBalance error will be thrown
        withdrawManager.withdraw(rejectChannelId);
    }

    function _setupChannelWithRejector(uint256 testChannelId) internal {
        // First, we need to make deposits that match the channel setup
        // The rejector channel only has token as allowed token, so make token deposits
        address[] memory participants = bridge.getChannelParticipants(testChannelId);
        address rejectorAddr = participants[0];

        // Deposit tokens for the rejector
        token.mint(rejectorAddr, 1000e18);
        vm.startPrank(rejectorAddr);
        token.approve(address(depositManager), 1e18);
        depositManager.depositToken(testChannelId, 1e18, bytes32(uint256(30)));
        vm.stopPrank();

        // Fund withdraw manager for the transfer
        vm.deal(address(withdrawManager), 2 ether);

        // Initialize channel state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        BridgeProofManager.ChannelInitializationProof memory mockProof = BridgeProofManager
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
        adminManager.registerFunction(bytes32(bytes4(keccak256("transfer(address,uint256)"))), new uint128[](4), new uint256[](4), keccak256("test_instance_hash"));

        // Submit proof with balance for rejector

        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether; // Rejector has 1 ETH to withdraw
        balances[1] = 0; // user1 has 0 ETH
        balances[2] = 0; // leader has 0 ETH

        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot")); // Set non-zero final state root
        _setWithdrawalsTestStateRoots(publicInputs);
        
        BridgeProofManager.ProofData memory proofData = BridgeProofManager.ProofData({
            proofPart1: new uint128[](4),
            proofPart2: new uint256[](4),
            publicInputs: publicInputs,
            smax: 100
        });

        mockZecFrost.setMockSigner(bridge.getChannelSignerAddr(testChannelId));

        bytes32 commitmentHash = keccak256(abi.encodePacked(testChannelId, bytes32(uint256(keccak256("finalStateRoot")))));
        BridgeProofManager.Signature memory signature =
            BridgeProofManager.Signature({message: commitmentHash, rx: 1, ry: 2, z: 3});

        // Advance time to pass the timeout
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);
        proofManager.submitProofAndSignature(testChannelId, _wrapProofInArray(proofData), signature);

        // Verify final balances to close channel
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });
        proofManager.verifyFinalBalancesGroth16(testChannelId, balances, finalizationProof);
    }

    function testMultipleUsersWithdrawDifferentTokens() public {
        // Fund withdraw manager for transfers
        vm.deal(address(withdrawManager), 10 ether);
        token.mint(address(withdrawManager), 1000e18);

        // User1 withdraws all tokens
        uint256 user1InitialTokens = token.balanceOf(user1);
        vm.prank(user1);
        withdrawManager.withdraw(channelId);
        assertEq(token.balanceOf(user1), user1InitialTokens + 102e18, "User1 token withdrawal failed");

        // User2 withdraws all tokens
        uint256 user2InitialTokens = token.balanceOf(user2);
        vm.prank(user2);
        withdrawManager.withdraw(channelId);
        assertEq(token.balanceOf(user2), user2InitialTokens + 400e18, "User2 token withdrawal failed");

        // Both users should have no more withdrawable tokens
        assertEq(
            bridge.getWithdrawableAmount(channelId, user1), 0, "User1 withdrawable amount not cleared"
        );
        assertEq(
            bridge.getWithdrawableAmount(channelId, user2), 0, "User2 withdrawable amount not cleared"
        );
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

        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});

        uint256 zeroChannelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            zeroChannelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );
        vm.stopPrank();

        _setupEmptyChannel(zeroChannelId);

        vm.prank(zeroUser);
        vm.expectRevert("No withdrawable amount for this token");
        withdrawManager.withdraw(zeroChannelId);
    }

    function _wrapProofInArray(BridgeProofManager.ProofData memory proof)
        internal
        pure
        returns (BridgeProofManager.ProofData[] memory)
    {
        BridgeProofManager.ProofData[] memory proofs = new BridgeProofManager.ProofData[](1);
        proofs[0] = proof;
        return proofs;
    }

    function _setWithdrawalsTestStateRoots(uint256[] memory publicInputs) internal pure {
        if (publicInputs.length >= 12) {
            // Use the same mock root that's used in channel initialization for input
            bytes32 mockRoot = keccak256(abi.encodePacked("mockRoot"));
            uint256 inputRootHigh = uint256(mockRoot) >> 128;
            uint256 inputRootLow = uint256(mockRoot) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            
            // Use the finalStateRoot (which is set in publicInputs[0]) for output
            bytes32 finalStateRoot = bytes32(publicInputs[0]);
            uint256 outputRootHigh = uint256(finalStateRoot) >> 128;
            uint256 outputRootLow = uint256(finalStateRoot) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            
            publicInputs[8] = inputRootHigh;   // input state root high
            publicInputs[9] = inputRootLow;    // input state root low
            publicInputs[10] = outputRootHigh; // output state root high (matches publicInputs[0])
            publicInputs[11] = outputRootLow;  // output state root low
        }
        
        // Set function signature at index 18 (transfer function selector: 0xa9059cbb)
        if (publicInputs.length >= 19) {
            publicInputs[18] = 0xa9059cbb; // transfer(address,uint256) function selector
        }
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
