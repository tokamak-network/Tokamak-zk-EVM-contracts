// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeProofManager.sol";
import "../../src/BridgeDepositManager.sol";
import "../../src/BridgeAdminManager.sol";
import "../../src/interface/ITokamakVerifier.sol";
import "../../src/interface/IZecFrost.sol";
import "../../src/interface/IGroth16Verifier16Leaves.sol";
import "../../src/library/ZecFrost.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

// Mock USDT-like token with blacklist functionality
contract MockUSDT is ERC20 {
    mapping(address => bool) private _isBlackListed;

    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function addBlackList(address _evilUser) external {
        _isBlackListed[_evilUser] = true;
    }

    function removeBlackList(address _clearedUser) external {
        _isBlackListed[_clearedUser] = false;
    }

    function isBlackListed(address _maker) external view returns (bool) {
        return _isBlackListed[_maker];
    }

    // Override transfer to check blacklist
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(!_isBlackListed[msg.sender], "Sender is blacklisted");
        require(!_isBlackListed[to], "Recipient is blacklisted");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(!_isBlackListed[from], "Sender is blacklisted");
        require(!_isBlackListed[to], "Recipient is blacklisted");
        return super.transferFrom(from, to, amount);
    }
}

contract MockTokamakVerifier is ITokamakVerifier {
    function verify(
        uint128[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external pure returns (bool) {
        return true;
    }
}

contract MockGroth16Verifier is IGroth16Verifier16Leaves {
    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[33] calldata)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

/**
 * @title UserStorageSlotsTest
 * @notice Test initializeChannelState with additional user storage slots (like USDT's isBlackListed)
 */
contract UserStorageSlotsTest is Test {
    BridgeCore public bridge;
    BridgeProofManager public proofManager;
    BridgeDepositManager public depositManager;
    BridgeAdminManager public adminManager;

    MockTokamakVerifier public tokamakVerifier;
    MockGroth16Verifier public groth16Verifier;
    ZecFrost public zecFrost;
    MockUSDT public usdt;

    address public owner = makeAddr("owner");
    address public leader = makeAddr("leader");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    function setUp() public {
        // Set block number to avoid underflow in blockhash calculations
        vm.roll(100);

        vm.startPrank(owner);

        // Deploy mock contracts
        tokamakVerifier = new MockTokamakVerifier();
        groth16Verifier = new MockGroth16Verifier();
        zecFrost = new ZecFrost();
        usdt = new MockUSDT();

        // Deploy manager implementations
        BridgeDepositManager depositManagerImpl = new BridgeDepositManager();
        BridgeProofManager proofManagerImpl = new BridgeProofManager();
        BridgeAdminManager adminManagerImpl = new BridgeAdminManager();

        // Deploy core contract with proxy
        BridgeCore implementation = new BridgeCore();
        bytes memory bridgeInitData = abi.encodeCall(
            BridgeCore.initialize,
            (address(0), address(0), address(0), address(0), owner)
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(implementation), bridgeInitData);
        bridge = BridgeCore(address(bridgeProxy));

        // Deploy manager proxies
        bytes memory depositInitData = abi.encodeCall(BridgeDepositManager.initialize, (address(bridge), owner));
        ERC1967Proxy depositProxy = new ERC1967Proxy(address(depositManagerImpl), depositInitData);
        depositManager = BridgeDepositManager(address(depositProxy));

        address[4] memory groth16Verifiers =
            [address(groth16Verifier), address(groth16Verifier), address(groth16Verifier), address(groth16Verifier)];
        bytes memory proofInitData = abi.encodeCall(
            BridgeProofManager.initialize,
            (address(bridge), address(tokamakVerifier), address(zecFrost), groth16Verifiers, owner)
        );
        ERC1967Proxy proofProxy = new ERC1967Proxy(address(proofManagerImpl), proofInitData);
        proofManager = BridgeProofManager(address(proofProxy));

        bytes memory adminInitData = abi.encodeCall(BridgeAdminManager.initialize, (address(bridge), owner));
        ERC1967Proxy adminProxy = new ERC1967Proxy(address(adminManagerImpl), adminInitData);
        adminManager = BridgeAdminManager(address(adminProxy));

        // Update manager addresses
        bridge.updateManagerAddresses(
            address(depositManager), address(proofManager), address(0), address(adminManager)
        );
        depositManager.updateBridge(address(bridge));
        proofManager.updateBridge(address(bridge));
        adminManager.updateBridge(address(bridge));

        // Set up USDT as allowed target contract with balance + isBlackListed slots
        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        IBridgeCore.UserStorageSlot[] memory userStorageSlots = new IBridgeCore.UserStorageSlot[](2);

        // Slot 0: balance (not loaded from chain, comes from deposits)
        userStorageSlots[0] = IBridgeCore.UserStorageSlot({
            slotOffset: 2, // USDT balance slot offset
            getterFunctionSignature: bytes32(0),
            isLoadedOnChain: false
        });

        // Slot 1: isBlackListed (loaded from chain via staticcall)
        userStorageSlots[1] = IBridgeCore.UserStorageSlot({
            slotOffset: 6, // USDT isBlackListed slot offset
            getterFunctionSignature: bytes32(bytes4(keccak256("isBlackListed(address)"))),
            isLoadedOnChain: true
        });

        adminManager.setAllowedTargetContract(address(usdt), emptySlots, userStorageSlots, true);

        // Mint tokens to participants
        usdt.mint(leader, 100 ether);
        usdt.mint(user1, 100 ether);
        usdt.mint(user2, 100 ether);
        usdt.mint(user3, 100 ether);

        vm.stopPrank();
    }


    function testInitializeChannelStateWithoutBlacklist() public {
        // Create channel with simple ERC20 (no additional storage slots)
        MockUSDT simpleToken = new MockUSDT();

        vm.startPrank(owner);
        simpleToken.mint(leader, 100 ether);
        simpleToken.mint(user1, 100 ether);
        simpleToken.mint(user2, 100 ether);

        // Set up simple token with balance slot only
        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        IBridgeCore.UserStorageSlot[] memory balanceSlot = new IBridgeCore.UserStorageSlot[](1);
        balanceSlot[0] = IBridgeCore.UserStorageSlot({
            slotOffset: 0,
            getterFunctionSignature: bytes32(0),
            isLoadedOnChain: false
        });
        adminManager.setAllowedTargetContract(address(simpleToken), emptySlots, balanceSlot, true);
        vm.stopPrank();

        // Create channel
        vm.startPrank(leader);

        address[] memory participants = new address[](2);
        participants[0] = user1;
        participants[1] = user2;

        bytes32 channelId = keccak256(abi.encode(address(this), block.timestamp, "testSimple"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(simpleToken),
            whitelisted: participants,
            enableFrostSignature: false
        });

        bridge.openChannel(params);
        vm.stopPrank();

        // Deposit tokens (1 mptKey each: balance only for simple token)
        vm.startPrank(user1);
        simpleToken.approve(address(depositManager), 10 ether);
        bytes32[] memory mptKeys1 = new bytes32[](1);
        mptKeys1[0] = bytes32(uint256(1));
        depositManager.depositToken(channelId, 10 ether, mptKeys1);
        vm.stopPrank();

        vm.startPrank(user2);
        simpleToken.approve(address(depositManager), 20 ether);
        bytes32[] memory mptKeys2 = new bytes32[](1);
        mptKeys2[0] = bytes32(uint256(2));
        depositManager.depositToken(channelId, 20 ether, mptKeys2);
        vm.stopPrank();

        vm.startPrank(leader);
        simpleToken.approve(address(depositManager), 5 ether);
        bytes32[] memory mptKeys3 = new bytes32[](1);
        mptKeys3[0] = bytes32(uint256(3));
        depositManager.depositToken(channelId, 5 ether, mptKeys3);
        vm.stopPrank();

        // Initialize channel state with proof
        vm.startPrank(leader);

        uint256[4] memory pA;
        uint256[8] memory pB;
        uint256[4] memory pC;

        BridgeProofManager.ChannelInitializationProof memory proof = BridgeProofManager.ChannelInitializationProof({
            merkleRoot: bytes32(uint256(123456)),
            pA: pA,
            pB: pB,
            pC: pC
        });

        // This should work - only balance leaves (no additional storage slots)
        // Tree structure will be:
        // - 3 participants
        // - Each has 1 leaf: balance only
        // - Total: 3 user leaves
        // - Tree size should be 16 (minimum)
        proofManager.initializeChannelState(channelId, proof);

        vm.stopPrank();

        // Verify channel state changed to Open
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(IBridgeCore.ChannelState.Open));

        // Verify tree size (should be 16 for 3 participants with 1 slot each)
        assertEq(bridge.getChannelTreeSize(channelId), 16);
    }
}
