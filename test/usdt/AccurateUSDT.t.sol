// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/RollupBridge.sol";
import "../../src/interface/IRollupBridge.sol";
import "../../src/interface/IVerifier.sol";
import "../../src/interface/IZecFrost.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Accurate USDT mock that replicates the exact transfer behavior
contract AccurateUSDTMock {
    string public name = "Tether USD";
    string public symbol = "USDT";
    uint8 public decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowed;
    mapping(address => bool) public isBlackListed;

    address public owner;
    bool public paused = false;
    
    // Fee parameters (currently 0 in real USDT)
    uint256 public basisPointsRate = 0;
    uint256 public maximumFee = 0;

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

    // USDT's transfer function - NO RETURN VALUE (this is the key issue)
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
        // NOTE: NO RETURN VALUE - this is what makes USDT non-standard
    }

    // USDT's transferFrom function - NO RETURN VALUE (this is the key issue)
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
        // NOTE: NO RETURN VALUE - this is what makes USDT non-standard
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

contract AccurateUSDTTest is Test {
    RollupBridge public bridge;
    AccurateUSDTMock public usdt;
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
        usdt = new AccurateUSDTMock();

        // Deploy RollupBridge with proxy
        RollupBridge implementation = new RollupBridge();
        bytes memory initData = abi.encodeCall(RollupBridge.initialize, (address(verifier), address(zecFrost), owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        bridge = RollupBridge(address(proxy));

        // Setup permissions
        bridge.authorizeCreator(leader);
        bridge.setAllowedTargetContract(address(usdt), new uint128[](0), new uint256[](0), true);

        // Mint USDT tokens
        usdt.mint(user1, 1000e6); // 1000 USDT
        usdt.mint(user2, 1000e6);
        usdt.mint(user3, 1000e6);

        vm.stopPrank();

        // Fund accounts with ETH
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    function testAccurateUSDTDeposit() public {
        console.log("Testing with accurate USDT mock (no return values)");
        
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

        // Test USDT deposit
        uint256 depositAmount = 100e6; // 100 USDT
        
        vm.startPrank(user1);
        
        console.log("User1 balance before approval:", usdt.balanceOf(user1));
        
        // First approve the bridge to spend USDT (need to approve 0 first due to USDT's protection)
        if (usdt.allowance(user1, address(bridge)) > 0) {
            usdt.approve(address(bridge), 0);
        }
        usdt.approve(address(bridge), depositAmount);
        
        console.log("Allowance after approval:", usdt.allowance(user1, address(bridge)));
        
        // Check balances before deposit
        uint256 userBalanceBefore = usdt.balanceOf(user1);
        uint256 bridgeBalanceBefore = usdt.balanceOf(address(bridge));
        
        console.log("About to call depositToken...");
        
        // This should reveal where the failure occurs
        try bridge.depositToken(channelId, address(usdt), depositAmount) {
            console.log("Deposit successful!");
            
            // Check balances after deposit
            uint256 userBalanceAfter = usdt.balanceOf(user1);
            uint256 bridgeBalanceAfter = usdt.balanceOf(address(bridge));
            
            console.log("User balance before:", userBalanceBefore);
            console.log("User balance after:", userBalanceAfter);
            console.log("Bridge balance before:", bridgeBalanceBefore);
            console.log("Bridge balance after:", bridgeBalanceAfter);
            
            // Verify the deposit worked correctly
            assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "User balance should decrease by deposit amount");
            assertEq(bridgeBalanceAfter - bridgeBalanceBefore, depositAmount, "Bridge balance should increase by deposit amount");
            assertEq(bridge.getParticipantDeposit(channelId, user1), depositAmount, "Deposit should be recorded correctly");
        } catch Error(string memory reason) {
            console.log("Deposit failed with reason:", reason);
            revert(string(abi.encodePacked("Deposit failed: ", reason)));
        } catch (bytes memory) {
            console.log("Deposit failed with low-level error");
            revert("Deposit failed with low-level error");
        }
        
        vm.stopPrank();
    }

    function testDirectUSDTTransfer() public {
        console.log("Testing direct USDT transfer to verify mock works correctly");
        
        vm.startPrank(user1);
        
        uint256 transferAmount = 50e6;
        uint256 user1BalanceBefore = usdt.balanceOf(user1);
        uint256 user2BalanceBefore = usdt.balanceOf(user2);
        
        console.log("User1 balance before transfer:", user1BalanceBefore);
        console.log("User2 balance before transfer:", user2BalanceBefore);
        
        // Direct transfer should work
        usdt.transfer(user2, transferAmount);
        
        uint256 user1BalanceAfter = usdt.balanceOf(user1);
        uint256 user2BalanceAfter = usdt.balanceOf(user2);
        
        console.log("User1 balance after transfer:", user1BalanceAfter);
        console.log("User2 balance after transfer:", user2BalanceAfter);
        
        assertEq(user1BalanceBefore - user1BalanceAfter, transferAmount, "User1 balance should decrease");
        assertEq(user2BalanceAfter - user2BalanceBefore, transferAmount, "User2 balance should increase");
        
        vm.stopPrank();
    }

    function testDirectUSDTTransferFrom() public {
        console.log("Testing direct USDT transferFrom to verify mock works correctly");
        
        vm.startPrank(user1);
        
        // Approve user2 to spend user1's tokens
        if (usdt.allowance(user1, user2) > 0) {
            usdt.approve(user2, 0);
        }
        usdt.approve(user2, 50e6);
        
        vm.stopPrank();
        
        vm.startPrank(user2);
        
        uint256 transferAmount = 30e6;
        uint256 user1BalanceBefore = usdt.balanceOf(user1);
        uint256 user3BalanceBefore = usdt.balanceOf(user3);
        
        console.log("User1 balance before transferFrom:", user1BalanceBefore);
        console.log("User3 balance before transferFrom:", user3BalanceBefore);
        console.log("Allowance before transferFrom:", usdt.allowance(user1, user2));
        
        // transferFrom should work
        usdt.transferFrom(user1, user3, transferAmount);
        
        uint256 user1BalanceAfter = usdt.balanceOf(user1);
        uint256 user3BalanceAfter = usdt.balanceOf(user3);
        
        console.log("User1 balance after transferFrom:", user1BalanceAfter);
        console.log("User3 balance after transferFrom:", user3BalanceAfter);
        console.log("Allowance after transferFrom:", usdt.allowance(user1, user2));
        
        assertEq(user1BalanceBefore - user1BalanceAfter, transferAmount, "User1 balance should decrease");
        assertEq(user3BalanceAfter - user3BalanceBefore, transferAmount, "User3 balance should increase");
        
        vm.stopPrank();
    }
}