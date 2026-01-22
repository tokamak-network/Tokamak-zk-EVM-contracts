// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeDepositManager.sol";
import "../../src/BridgeProofManager.sol";
import "../../src/BridgeWithdrawManager.sol";
import "../../src/BridgeAdminManager.sol";
import "../../src/interface/ITokamakVerifier.sol";
import "../../src/interface/IZecFrost.sol";
import "../../src/interface/IGroth16Verifier16Leaves.sol";
import "../../src/interface/IGroth16Verifier32Leaves.sol";
import "../../src/interface/IGroth16Verifier64Leaves.sol";
import "../../src/interface/IGroth16Verifier128Leaves.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock Contracts
contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockZecFrost is IZecFrost {
    function verify(bytes32 message, uint256 pkx, uint256 pky, uint256 rx, uint256 ry, uint256 z)
        external
        pure
        returns (address)
    {
        // Always return a fixed address for testing
        return address(0x1234567890123456789012345678901234567890);
    }
}

contract MockTokamakVerifier is ITokamakVerifier {
    function verify(
        uint128[] calldata proofPart1,
        uint256[] calldata proofPart2,
        uint128[] calldata preprocessedPart1,
        uint256[] calldata preprocessedPart2,
        uint256[] calldata publicInputs,
        uint256 smax
    ) external pure returns (bool) {
        return true;
    }
}

contract MockGroth16Verifier is IGroth16Verifier16Leaves, IGroth16Verifier32Leaves, IGroth16Verifier64Leaves, IGroth16Verifier128Leaves {
    function verifyProof(uint256[4] calldata pA, uint256[8] calldata pB, uint256[4] calldata pC, uint256[33] calldata publicSignals)
        external
        pure
        returns (bool)
    {
        return true;
    }

    function verifyProof(uint256[4] calldata pA, uint256[8] calldata pB, uint256[4] calldata pC, uint256[65] calldata publicSignals)
        external
        pure
        returns (bool)
    {
        return true;
    }

    function verifyProof(uint256[4] calldata pA, uint256[8] calldata pB, uint256[4] calldata pC, uint256[129] calldata publicSignals)
        external
        pure
        returns (bool)
    {
        return true;
    }

    function verifyProof(uint256[4] calldata pA, uint256[8] calldata pB, uint256[4] calldata pC, uint256[257] calldata publicSignals)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

contract TimeoutWithdrawalTest is Test {
    BridgeCore public bridge;
    BridgeDepositManager public depositManager;
    BridgeProofManager public proofManager;
    BridgeWithdrawManager public withdrawManager;
    BridgeAdminManager public adminManager;
    MockToken public token;
    MockTokamakVerifier public zkVerifier;
    MockZecFrost public zecFrost;
    MockGroth16Verifier public groth16Verifier16;
    MockGroth16Verifier public groth16Verifier32;
    MockGroth16Verifier public groth16Verifier64;
    MockGroth16Verifier public groth16Verifier128;

    address public owner = address(this);
    address public leader = makeAddr("leader");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    bytes32 public channelId;
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;

    event Withdrawn(bytes32 indexed channelId, address indexed user, address token, uint256 amount);

    function setUp() public {
        // Set proper block number to avoid underflow in blockhash calculations
        vm.roll(10);
        
        // Deploy mock contracts
        token = new MockToken("TestToken", "TT", 18);
        zkVerifier = new MockTokamakVerifier();
        zecFrost = new MockZecFrost();
        groth16Verifier16 = new MockGroth16Verifier();
        groth16Verifier32 = new MockGroth16Verifier();
        groth16Verifier64 = new MockGroth16Verifier();
        groth16Verifier128 = new MockGroth16Verifier();

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
        withdrawManager = BridgeWithdrawManager(address(withdrawProxy));

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
            (address(bridge), address(zkVerifier), address(zecFrost), groth16Verifiers, owner)
        );
        ERC1967Proxy proofProxy = new ERC1967Proxy(address(proofManagerImpl), proofInitData);
        proofManager = BridgeProofManager(address(proofProxy));

        // Update managers to point to the correct bridge and update bridge with manager addresses
        vm.startPrank(owner);
        
        // Create a new bridge with the correct manager addresses
        BridgeCore newImplementation = new BridgeCore();
        bytes memory correctBridgeInitData = abi.encodeCall(
            BridgeCore.initialize,
            (address(depositManager), address(proofManager), address(withdrawManager), address(adminManager), owner)
        );
        ERC1967Proxy newBridgeProxy = new ERC1967Proxy(address(newImplementation), correctBridgeInitData);
        bridge = BridgeCore(address(newBridgeProxy));

        // Update all managers to point to the new bridge
        depositManager.updateBridge(address(bridge));
        withdrawManager.updateBridge(address(bridge));
        proofManager.updateBridge(address(bridge));
        adminManager.updateBridge(address(bridge));
        
        vm.stopPrank();

        // Set up allowed target contract with balance slot
        vm.startPrank(owner);
        IBridgeCore.PreAllocatedLeaf[] memory emptyLeaves = new IBridgeCore.PreAllocatedLeaf[](0);
        IBridgeCore.UserStorageSlot[] memory balanceSlot = new IBridgeCore.UserStorageSlot[](1);
        balanceSlot[0] = IBridgeCore.UserStorageSlot({
            slotOffset: 0,
            getterFunctionSignature: bytes32(0),
            isLoadedOnChain: false
        });
        adminManager.setAllowedTargetContract(address(token), emptyLeaves, balanceSlot, true);
        vm.stopPrank();

        // Mint tokens to participants
        token.mint(user1, 10 ether);
        token.mint(user2, 10 ether);
        token.mint(user3, 10 ether);

        // Setup channel
        _setupChannel();
    }

    function _setupChannel() internal {
        vm.startPrank(leader);
        
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        channelId = keccak256(abi.encode(leader, block.timestamp, "timeout_test"));
        
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: false
        });

        bridge.openChannel(params);
        vm.stopPrank();

        // Make deposits
        _makeDeposits();
    }

    function _makeDeposits() internal {
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        for (uint256 i = 0; i < participants.length; i++) {
            vm.startPrank(participants[i]);
            token.approve(address(depositManager), DEPOSIT_AMOUNT);
            bytes32[] memory mptKeys = new bytes32[](1);
            mptKeys[0] = bytes32(uint256(i + 1));
            depositManager.depositToken(channelId, DEPOSIT_AMOUNT, mptKeys);
            vm.stopPrank();
        }
    }

    function _initializeChannel() internal {
        vm.startPrank(leader);
        
        BridgeProofManager.ChannelInitializationProof memory mockProof = BridgeProofManager.ChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: keccak256(abi.encodePacked("mockRoot"))
        });
        
        proofManager.initializeChannelState(channelId, mockProof);
        vm.stopPrank();
    }

    function testWithdrawOnTimeoutSuccess() public {
        _initializeChannel();

        // Fast forward past timeout
        vm.warp(block.timestamp + bridge.CHANNEL_TIMEOUT() + 1);

        uint256 initialTokenBalance = token.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(channelId, user1, address(token), DEPOSIT_AMOUNT);

        vm.prank(user1);
        withdrawManager.withdraw(channelId, address(token));

        // Check user received their deposit back
        assertEq(token.balanceOf(user1), initialTokenBalance + DEPOSIT_AMOUNT);

        // Verify user's validatedUserStorage is cleared after withdrawal
        assertEq(bridge.getValidatedUserBalance(channelId, user1), 0);
    }

    function testWithdrawOnTimeoutBeforeTimeout() public {
        _initializeChannel();

        vm.expectRevert("Channel must be deleted or timed out");
        vm.prank(user1);
        withdrawManager.withdraw(channelId, address(token));
    }

    function testWithdrawOnTimeoutAlreadyWithdrawn() public {
        _initializeChannel();

        // Fast forward past timeout
        vm.warp(block.timestamp + bridge.CHANNEL_TIMEOUT() + 1);

        // First withdrawal
        vm.prank(user1);
        withdrawManager.withdraw(channelId, address(token));

        // Try to withdraw again
        vm.expectRevert("No withdrawable amount");
        vm.prank(user1);
        withdrawManager.withdraw(channelId, address(token));
    }

    function testWithdrawOnTimeoutNotParticipant() public {
        _initializeChannel();

        // Fast forward past timeout
        vm.warp(block.timestamp + bridge.CHANNEL_TIMEOUT() + 1);

        address nonParticipant = makeAddr("nonParticipant");

        vm.expectRevert("No withdrawable amount");
        vm.prank(nonParticipant);
        withdrawManager.withdraw(channelId, address(token));
    }



    function testMultipleUsersCanWithdrawOnTimeout() public {
        _initializeChannel();

        // Fast forward past timeout
        vm.warp(block.timestamp + bridge.CHANNEL_TIMEOUT() + 1);

        uint256 user1InitialBalance = token.balanceOf(user1);
        uint256 user2InitialBalance = token.balanceOf(user2);

        // User1 withdraws
        vm.prank(user1);
        withdrawManager.withdraw(channelId, address(token));

        // User2 withdraws
        vm.prank(user2);
        withdrawManager.withdraw(channelId, address(token));

        // Both should have received their deposits back
        assertEq(token.balanceOf(user1), user1InitialBalance + DEPOSIT_AMOUNT);
        assertEq(token.balanceOf(user2), user2InitialBalance + DEPOSIT_AMOUNT);

        // Verify both users' validatedUserStorage is cleared after withdrawal
        assertEq(bridge.getValidatedUserBalance(channelId, user1), 0);
        assertEq(bridge.getValidatedUserBalance(channelId, user2), 0);
    }

    function _submitMockProof() internal {
        BridgeProofManager.ProofData[] memory proofs = new BridgeProofManager.ProofData[](1);
        uint256[] memory publicInputs = new uint256[](64);
        
        // Get the initial state root from the channel
        bytes32 initialStateRoot = bridge.getChannelInitialStateRoot(channelId);
        bytes32 finalStateRoot = keccak256(abi.encodePacked("finalRoot"));
        
        // Set required public inputs for state root validation
        publicInputs[0] = uint256(finalStateRoot) >> 128; // final state root part 1
        publicInputs[1] = uint256(finalStateRoot) & ((1 << 128) - 1); // final state root part 2
        publicInputs[8] = uint256(initialStateRoot) >> 128; // initial state root part 1
        publicInputs[9] = uint256(initialStateRoot) & ((1 << 128) - 1); // initial state root part 2
        
        // Set block info data to match the stored blockInfosHash
        bytes32 storedBlockInfoHash = bridge.getChannelBlockInfosHash(channelId);
        // For mock purposes, we'll just set some basic block info that should work
        for (uint256 i = 40; i < 64; i += 2) {
            publicInputs[i] = 0; // mock block info data - simplified for testing
            publicInputs[i + 1] = 0;
        }
        
        proofs[0] = BridgeProofManager.ProofData({
            proofPart1: new uint128[](8),
            proofPart2: new uint256[](8), 
            publicInputs: publicInputs,
            smax: 1000
        });

        BridgeProofManager.Signature memory signature = BridgeProofManager.Signature({
            message: bytes32(0),
            rx: 0,
            ry: 0,
            z: 0
        });

        proofManager.submitProofAndSignature(channelId, proofs, signature);
    }
}