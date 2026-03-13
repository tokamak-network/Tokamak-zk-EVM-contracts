// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Script.sol";
import "../../src/MockTokamakNetworkToken.sol";

contract DeployMockTokamakNetworkTokenScript is Script {
    uint256 internal constant DEFAULT_INITIAL_SUPPLY = 1_000_000_000 ether;

    address public deployer;
    address public initialHolder;
    uint256 public initialSupply;
    address public token;

    function setUp() public {
        initialHolder = vm.envOr("PRIVATE_STATE_ANVIL_INITIAL_HOLDER", address(0));
        initialSupply = vm.envOr("PRIVATE_STATE_ANVIL_INITIAL_SUPPLY", DEFAULT_INITIAL_SUPPLY);
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("APPS_DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        initialHolder = vm.envOr("PRIVATE_STATE_ANVIL_INITIAL_HOLDER", deployer);
        initialSupply = vm.envOr("PRIVATE_STATE_ANVIL_INITIAL_SUPPLY", DEFAULT_INITIAL_SUPPLY);

        vm.startBroadcast(deployerPrivateKey);
        MockTokamakNetworkToken tokenContract = new MockTokamakNetworkToken(initialHolder, initialSupply);
        vm.stopBroadcast();

        token = address(tokenContract);

        console.log("DeployMockTokamakNetworkTokenScript complete");
        console.log("deployer", deployer);
        console.log("initialHolder", initialHolder);
        console.log("initialSupply", initialSupply);
        console.log("token", token);
    }
}
