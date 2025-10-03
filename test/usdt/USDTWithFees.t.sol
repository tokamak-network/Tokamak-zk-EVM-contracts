// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/RollupBridge.sol";
import "../../src/interface/IRollupBridge.sol";
import "../../src/interface/IVerifier.sol";
import "../../src/interface/IZecFrost.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// USDT mock with fees enabled to test fee-on-transfer behavior
contract USDTWithFeesMock {
    string public name = "Tether USD (With Fees)";
    string public symbol = "USDT";
    uint8 public decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowed;
    mapping(address => bool) public isBlackListed;

    address public owner;
    bool public paused = false;

    // Fee parameters - SET TO NON-ZERO VALUES TO SIMULATE FEES
    uint256 public basisPointsRate = 10; // 0.1% fee (10 basis points)
    uint256 public maximumFee = 1000000; // 1 USDT max fee (1,000,000 units with 6 decimals)

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function balanceOf(address who) public view returns (uint256) {
        return balances[who];
    }

    function allowance(address _owner, address spender) public view returns (uint256) {
        return allowed[_owner][spender];
    }

    function approve(address spender, uint256 value) public {
        // USDT has approval race condition protection
        require(!(value != 0 && allowed[msg.sender][spender] != 0), "Must approve 0 first");

        allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
    }

    // Enable fees for testing
    function setParams(uint256 newBasisPoints, uint256 newMaxFee) public {
        require(msg.sender == owner, "Only owner");
        basisPointsRate = newBasisPoints;
        maximumFee = newMaxFee;
    }

    // USDT's transfer function with fee logic - NO RETURN VALUE
    function transfer(address to, uint256 value) public {
        require(!paused, "Contract paused");
        require(!isBlackListed[msg.sender], "Sender blacklisted");

        uint256 fee = (value * basisPointsRate) / 10000;
        if (fee > maximumFee) {
            fee = maximumFee;
        }

        uint256 sendAmount = value - fee;

        require(balances[msg.sender] >= value, "Insufficient balance");
        balances[msg.sender] -= value;
        balances[to] += sendAmount;

        if (fee > 0) {
            balances[owner] += fee;
            emit Transfer(msg.sender, owner, fee);
        }

        emit Transfer(msg.sender, to, sendAmount);
        // NOTE: NO RETURN VALUE
    }

    // USDT's transferFrom function with fee logic - NO RETURN VALUE
    function transferFrom(address from, address to, uint256 value) public {
        require(!paused, "Contract paused");
        require(!isBlackListed[from], "From address blacklisted");

        uint256 _allowance = allowed[from][msg.sender];
        require(_allowance >= value, "Insufficient allowance");

        uint256 fee = (value * basisPointsRate) / 10000;
        if (fee > maximumFee) {
            fee = maximumFee;
        }

        uint256 sendAmount = value - fee;

        require(balances[from] >= value, "Insufficient balance");

        // Update allowance (USDT uses MAX_UINT pattern)
        uint256 MAX_UINT = type(uint256).max;
        if (_allowance < MAX_UINT) {
            allowed[from][msg.sender] = _allowance - value;
        }

        balances[from] -= value;
        balances[to] += sendAmount;

        if (fee > 0) {
            balances[owner] += fee;
            emit Transfer(from, owner, fee);
        }

        emit Transfer(from, to, sendAmount);
        // NOTE: NO RETURN VALUE
    }
}

contract MockVerifier is IVerifier {
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

contract MockZecFrost is IZecFrost {
    function verify(bytes32, uint256 pkx, uint256 pky, uint256, uint256, uint256)
        external
        pure
        returns (address recovered)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(pkx, pky)))));
    }
}

contract USDTWithFeesTest is Test {
    RollupBridge public bridge;
    USDTWithFeesMock public usdt;
    MockVerifier public verifier;
    MockZecFrost public zecFrost;

    address public owner = makeAddr("owner");
    address public leader = makeAddr("leader");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    address constant ETH_TOKEN_ADDRESS = address(1);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        verifier = new MockVerifier();
        zecFrost = new MockZecFrost();
        usdt = new USDTWithFeesMock();

        // Deploy RollupBridge with proxy
        RollupBridge implementation = new RollupBridge();
        bytes memory initData = abi.encodeCall(RollupBridge.initialize, (address(verifier), address(zecFrost), owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        bridge = RollupBridge(address(proxy));

        // Setup permissions
        bridge.authorizeCreator(leader);
        bridge.setAllowedTargetContract(address(usdt), new uint128[](0), new uint256[](0), true);

        // Mint USDT tokens (extra for high fee test)
        usdt.mint(user1, 3000e6); // 3000 USDT to support large deposit test
        usdt.mint(user2, 1000e6);
        usdt.mint(user3, 1000e6);

        vm.stopPrank();

        // Fund accounts with ETH
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    function testUSDTDepositWithFees() public {
        console.log("Testing USDT deposit with fees enabled");
        console.log("Fee rate:", usdt.basisPointsRate(), "basis points");
        console.log("Max fee:", usdt.maximumFee(), "units");

        // Create a channel with USDT as target contract
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = makeAddr("l2user1");
        l2PublicKeys[1] = makeAddr("l2user2");
        l2PublicKeys[2] = makeAddr("l2user3");

        uint128[] memory preprocessedPart1 = new uint128[](1);
        preprocessedPart1[0] = 1;

        uint256[] memory preprocessedPart2 = new uint256[](1);
        preprocessedPart2[0] = 1;

        IRollupBridge.ChannelParams memory params = IRollupBridge.ChannelParams({
            targetContract: address(usdt),
            participants: participants,
            l2PublicKeys: l2PublicKeys,
            timeout: 1 hours,
            pkx: 0x4F6340CFDD930A6F54E730188E3071D150877FA664945FB6F120C18B56CE1C09,
            pky: 0x802A5E67C00A70D85B9A088EAC7CF5B9FB46AC5C0B2BD7D1E189FAC210F6B7EF
        });

        uint256 channelId = bridge.openChannel(params);
        vm.stopPrank();

        // Test USDT deposit with fees
        uint256 depositAmount = 100e6; // 100 USDT

        // Calculate expected fee
        uint256 expectedFee = (depositAmount * usdt.basisPointsRate()) / 10000;
        if (expectedFee > usdt.maximumFee()) {
            expectedFee = usdt.maximumFee();
        }
        uint256 expectedReceived = depositAmount - expectedFee;

        console.log("Deposit amount:", depositAmount);
        console.log("Expected fee:", expectedFee);
        console.log("Expected received by bridge:", expectedReceived);

        vm.startPrank(user1);

        // Approve bridge to spend USDT (need to approve 0 first due to USDT's protection)
        if (usdt.allowance(user1, address(bridge)) > 0) {
            usdt.approve(address(bridge), 0);
        }
        usdt.approve(address(bridge), depositAmount);

        // Check balances before deposit
        uint256 userBalanceBefore = usdt.balanceOf(user1);
        uint256 bridgeBalanceBefore = usdt.balanceOf(address(bridge));
        uint256 ownerBalanceBefore = usdt.balanceOf(owner);

        console.log("User balance before:", userBalanceBefore);
        console.log("Bridge balance before:", bridgeBalanceBefore);
        console.log("Owner balance before:", ownerBalanceBefore);

        // Deposit USDT
        bridge.depositToken(channelId, address(usdt), depositAmount);

        // Check balances after deposit
        uint256 userBalanceAfter = usdt.balanceOf(user1);
        uint256 bridgeBalanceAfter = usdt.balanceOf(address(bridge));
        uint256 ownerBalanceAfter = usdt.balanceOf(owner);

        console.log("User balance after:", userBalanceAfter);
        console.log("Bridge balance after:", bridgeBalanceAfter);
        console.log("Owner balance after:", ownerBalanceAfter);

        uint256 actualFeeCollected = ownerBalanceAfter - ownerBalanceBefore;
        uint256 actualReceived = bridgeBalanceAfter - bridgeBalanceBefore;

        console.log("Actual fee collected:", actualFeeCollected);
        console.log("Actual received by bridge:", actualReceived);

        vm.stopPrank();

        // Verify fee-on-transfer behavior
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "User should lose full deposit amount");
        assertEq(actualFeeCollected, expectedFee, "Owner should receive expected fee");
        assertEq(actualReceived, expectedReceived, "Bridge should receive amount minus fee");

        // Verify the contract recorded the actual transferred amount (not the requested amount)
        uint256 recordedDeposit = bridge.getParticipantDeposit(channelId, user1);
        console.log("Recorded deposit in contract:", recordedDeposit);
        assertEq(recordedDeposit, actualReceived, "Contract should record actual received amount");
    }

    function testUSDTDepositWithHighFees() public {
        console.log("Testing USDT deposit with high fees");

        // Set higher fees for this test
        vm.prank(owner);
        usdt.setParams(500, 50e6); // 5% fee, max 50 USDT

        console.log("New fee rate:", usdt.basisPointsRate(), "basis points");
        console.log("New max fee:", usdt.maximumFee(), "units");

        // Create channel
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        address[] memory l2PublicKeys = new address[](3);
        l2PublicKeys[0] = makeAddr("l2user1");
        l2PublicKeys[1] = makeAddr("l2user2");
        l2PublicKeys[2] = makeAddr("l2user3");

        IRollupBridge.ChannelParams memory params = IRollupBridge.ChannelParams({
            targetContract: address(usdt),
            participants: participants,
            l2PublicKeys: l2PublicKeys,
            timeout: 1 hours,
            pkx: 0x4F6340CFDD930A6F54E730188E3071D150877FA664945FB6F120C18B56CE1C09,
            pky: 0x802A5E67C00A70D85B9A088EAC7CF5B9FB46AC5C0B2BD7D1E189FAC210F6B7EF
        });

        uint256 channelId = bridge.openChannel(params);
        vm.stopPrank();

        // Test with large deposit that hits max fee
        uint256 depositAmount = 2000e6; // 2000 USDT

        // Calculate expected fee (should hit max fee)
        uint256 calculatedFee = (depositAmount * usdt.basisPointsRate()) / 10000; // 5% of 2000 = 100 USDT
        uint256 expectedFee = calculatedFee > usdt.maximumFee() ? usdt.maximumFee() : calculatedFee;
        uint256 expectedReceived = depositAmount - expectedFee;

        console.log("Large deposit amount:", depositAmount);
        console.log("Calculated fee (5%):", calculatedFee);
        console.log("Expected fee (capped at max):", expectedFee);
        console.log("Expected received by bridge:", expectedReceived);

        vm.startPrank(user1);

        // Approve and deposit
        if (usdt.allowance(user1, address(bridge)) > 0) {
            usdt.approve(address(bridge), 0);
        }
        usdt.approve(address(bridge), depositAmount);

        uint256 bridgeBalanceBefore = usdt.balanceOf(address(bridge));
        uint256 ownerBalanceBefore = usdt.balanceOf(owner);

        bridge.depositToken(channelId, address(usdt), depositAmount);

        uint256 actualFeeCollected = usdt.balanceOf(owner) - ownerBalanceBefore;
        uint256 actualReceived = usdt.balanceOf(address(bridge)) - bridgeBalanceBefore;

        console.log("Actual fee collected:", actualFeeCollected);
        console.log("Actual received by bridge:", actualReceived);

        vm.stopPrank();

        // Verify max fee was applied
        assertEq(actualFeeCollected, expectedFee, "Should collect capped fee amount");
        assertEq(actualReceived, expectedReceived, "Bridge should receive correct amount after max fee");

        // Verify recorded deposit
        uint256 recordedDeposit = bridge.getParticipantDeposit(channelId, user1);
        assertEq(recordedDeposit, actualReceived, "Contract should record actual received amount");
    }
}
