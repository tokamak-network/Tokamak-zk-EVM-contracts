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

contract ProofSubmissionTest is Test {
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

    uint128[] public proofPart1;
    uint256[] public proofPart2;
    uint256[] public publicInputs;

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

        // Use the actual registered function instance hash from the deployed contract
        bytes32 functionInstanceHash = 0xd157cb883adb9cb0e27d9dc419e2a4be817d856281b994583b5bae64be94d35a;

        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        adminManager.setAllowedTargetContract(address(token), emptySlots, true);
        adminManager.registerFunction(
            address(token), transferSig, preprocessedPart1, preprocessedPart2, functionInstanceHash
        );

        vm.stopPrank();
    }

    function setupChannelWithDeposits() public returns (uint256 channelId) {
        vm.startPrank(leader);
        vm.deal(leader, 10 ether);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = leader;

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });

        channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );
        vm.stopPrank();

        // Make deposits to become participants
        token.mint(user1, 1000e18);
        vm.startPrank(user1);
        token.approve(address(depositManager), 2e18);
        depositManager.depositToken(channelId, 2e18, bytes32(uint256(10)));
        vm.stopPrank();

        token.mint(user2, 1000e18);
        vm.startPrank(user2);
        token.approve(address(depositManager), 500e18);
        depositManager.depositToken(channelId, 500e18, bytes32(uint256(20)));
        vm.stopPrank();

        token.mint(leader, 1000e18);
        vm.startPrank(leader);
        token.approve(address(depositManager), 1e18);
        depositManager.depositToken(channelId, 1e18, bytes32(uint256(30)));
        vm.stopPrank();
    }

    function computeCorrectFunctionInstanceHash() public pure returns (bytes32) {
        uint256[] memory correctData = new uint256[](446);

        // Set specific known values that should hash to the correct instance hash
        correctData[0] = 0x01;
        correctData[1] = 0xffffffffffffffffffffffffffffffff;
        correctData[2] = 0xffffffff;

        return keccak256(abi.encodePacked(correctData));
    }

    function testcheckInstanceHash() public {
        bytes32 expectedHash = computeCorrectFunctionInstanceHash();
        console.logBytes32(expectedHash);
    }
}
