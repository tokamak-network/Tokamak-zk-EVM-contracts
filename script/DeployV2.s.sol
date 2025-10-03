// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/RollupBridge.sol";
import "../src/verifier/Verifier.sol";
import "../src/library/ZecFrost.sol";

contract DeployV2Script is Script {
    // Implementation addresses
    address public rollupBridgeImpl;

    // Proxy addresses (main contracts)
    address public rollupBridge;

    // Environment variables
    address public zkVerifier;
    address public zecFrost;
    address public deployer;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load environment variables
        deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        shouldVerify = vm.envOr("VERIFY_CONTRACTS", false);
        etherscanApiKey = vm.envOr("ETHERSCAN_API_KEY", string(""));
        chainId = vm.envOr("CHAIN_ID", string("31337"));

        // ZK Verifier can be provided or we deploy a new one
        try vm.envAddress("ZK_VERIFIER_ADDRESS") returns (address verifier) {
            zkVerifier = verifier;
        } catch {
            console.log("No ZK_VERIFIER_ADDRESS provided, will deploy new Verifier");
        }

        // ZecFrost can be provided or we deploy a new one
        try vm.envAddress("ZEC_FROST_ADDRESS") returns (address frost) {
            zecFrost = frost;
        } catch {
            console.log("No ZEC_FROST_ADDRESS provided, will deploy new ZecFrost");
        }
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployer = vm.addr(deployerPrivateKey);
        console.log("Deploying with account:", deployer);
        console.log("Account balance:", deployer.balance);

        // Deploy ZK Verifier if not provided
        if (zkVerifier == address(0)) {
            console.log("Deploying Verifier...");
            Verifier verifierContract = new Verifier();
            zkVerifier = address(verifierContract);
            console.log("Verifier deployed at:", zkVerifier);
        } else {
            console.log("Using existing Verifier at:", zkVerifier);
        }

        // Deploy ZecFrost if not provided
        if (zecFrost == address(0)) {
            console.log("Deploying ZecFrost...");
            ZecFrost zecFrostContract = new ZecFrost();
            zecFrost = address(zecFrostContract);
            console.log("ZecFrost deployed at:", zecFrost);
        } else {
            console.log("Using existing ZecFrost at:", zecFrost);
        }

        // Deploy RollupBridge implementation
        console.log("Deploying RollupBridge implementation...");
        RollupBridge rollupBridgeImplementation = new RollupBridge();
        rollupBridgeImpl = address(rollupBridgeImplementation);
        console.log("RollupBridge implementation deployed at:", rollupBridgeImpl);

        // Deploy RollupBridge proxy
        console.log("Deploying RollupBridge proxy...");
        bytes memory rollupBridgeInitData = abi.encodeCall(
            RollupBridge.initialize,
            (zkVerifier, zecFrost, deployer) // Include ZecFrost contract
        );

        ERC1967Proxy rollupBridgeProxy = new ERC1967Proxy(rollupBridgeImpl, rollupBridgeInitData);
        rollupBridge = address(rollupBridgeProxy);
        console.log("RollupBridge proxy deployed at:", rollupBridge);

        // Authorize the deployer as a channel creator
        RollupBridge(rollupBridge).authorizeCreator(deployer);
        console.log("Authorized deployer as channel creator");

        // Configure WTON target contract
        console.log("Configuring WTON target contract...");
        _configureWTONContract(rollupBridge);

        // Configure USDT target contract
        console.log("Configuring USDT target contract...");
        _configureUSDTContract(rollupBridge);

        vm.stopBroadcast();

        // Log final addresses
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("ZK Verifier:", zkVerifier);
        console.log("ZecFrost:", zecFrost);
        console.log("RollupBridge Implementation:", rollupBridgeImpl);
        console.log("RollupBridge Proxy:", rollupBridge);
        console.log("Deployer (Owner):", deployer);

        // Verify contracts if requested
        if (shouldVerify && bytes(etherscanApiKey).length > 0) {
            verifyContracts();
        }
    }

    function verifyContracts() internal {
        console.log("\n=== VERIFYING CONTRACTS ===");

        try vm.parseAddress(vm.envString("ZK_VERIFIER_ADDRESS")) {
            console.log("Skipping Verifier verification (pre-existing)");
        } catch {
            // Verify Verifier
            console.log("Verifying Verifier...");
            string[] memory verifierCmd = new string[](6);
            verifierCmd[0] = "forge";
            verifierCmd[1] = "verify-contract";
            verifierCmd[2] = vm.toString(zkVerifier);
            verifierCmd[3] = "src/verifier/Verifier.sol:Verifier";
            verifierCmd[4] = "--etherscan-api-key";
            verifierCmd[5] = etherscanApiKey;
            vm.ffi(verifierCmd);
        }

        try vm.parseAddress(vm.envString("ZEC_FROST_ADDRESS")) {
            console.log("Skipping ZecFrost verification (pre-existing)");
        } catch {
            // Verify ZecFrost
            console.log("Verifying ZecFrost...");
            string[] memory zecFrostCmd = new string[](6);
            zecFrostCmd[0] = "forge";
            zecFrostCmd[1] = "verify-contract";
            zecFrostCmd[2] = vm.toString(zecFrost);
            zecFrostCmd[3] = "src/library/ZecFrost.sol:ZecFrost";
            zecFrostCmd[4] = "--etherscan-api-key";
            zecFrostCmd[5] = etherscanApiKey;
            vm.ffi(zecFrostCmd);
        }

        // Verify RollupBridge Implementation
        console.log("Verifying RollupBridge Implementation...");
        string[] memory rollupCmd = new string[](6);
        rollupCmd[0] = "forge";
        rollupCmd[1] = "verify-contract";
        rollupCmd[2] = vm.toString(rollupBridgeImpl);
        rollupCmd[3] = "src/RollupBridge.sol:RollupBridge";
        rollupCmd[4] = "--etherscan-api-key";
        rollupCmd[5] = etherscanApiKey;
        vm.ffi(rollupCmd);

        console.log("Contract verification complete!");
    }

    function _configureWTONContract(address bridgeAddress) internal {
        // WTON contract address
        address wtonAddress = 0x79E0d92670106c85E9067b56B8F674340dCa0Bbd;

        // WTON preprocess data from WTON_preprocess.json
        uint128[] memory wtonPreprocessedPart1 = new uint128[](4);
        wtonPreprocessedPart1[0] = 0x1186b2f2b6871713b10bc24ef04a9a39;
        wtonPreprocessedPart1[1] = 0x02b36b71d4948be739d14bb0e8f4a887;
        wtonPreprocessedPart1[2] = 0x18e54aba379045c9f5c18d8aefeaa8cc;
        wtonPreprocessedPart1[3] = 0x08df3e052d4b1c0840d73edcea3f85e7;

        uint256[] memory wtonPreprocessedPart2 = new uint256[](4);
        wtonPreprocessedPart2[0] = 0x7e084b3358f7f1404f0a4ee1acc6d254997032f77fd77593fab7c896b7cfce1e;
        wtonPreprocessedPart2[1] = 0xe2dfa30cd1fca5558bfe26343dc755a0a52ef6115b9aef97d71b047ed5d830c8;
        wtonPreprocessedPart2[2] = 0xf68408df0b8dda3f529522a67be22f2934970885243a9d2cf17d140f2ac1bb10;
        wtonPreprocessedPart2[3] = 0x4b0d9a6ffeb25101ff57e35d7e527f2080c460edc122f2480f8313555a71d3ac;

        RollupBridge(bridgeAddress).setAllowedTargetContract(
            wtonAddress, wtonPreprocessedPart1, wtonPreprocessedPart2, true
        );

        console.log("WTON target contract configured:", wtonAddress);
    }

    function _configureUSDTContract(address bridgeAddress) internal {
        // USDT contract address
        address usdtAddress = 0x42d3b260c761cD5da022dB56Fe2F89c4A909b04A;

        // USDT preprocess data from USDT_preprocess.json
        uint128[] memory usdtPreprocessedPart1 = new uint128[](4);
        usdtPreprocessedPart1[0] = 0x1186b2f2b6871713b10bc24ef04a9a39;
        usdtPreprocessedPart1[1] = 0x02b36b71d4948be739d14bb0e8f4a887;
        usdtPreprocessedPart1[2] = 0x18e54aba379045c9f5c18d8aefeaa8cc;
        usdtPreprocessedPart1[3] = 0x08df3e052d4b1c0840d73edcea3f85e7;

        uint256[] memory usdtPreprocessedPart2 = new uint256[](4);
        usdtPreprocessedPart2[0] = 0x7e084b3358f7f1404f0a4ee1acc6d254997032f77fd77593fab7c896b7cfce1e;
        usdtPreprocessedPart2[1] = 0xe2dfa30cd1fca5558bfe26343dc755a0a52ef6115b9aef97d71b047ed5d830c8;
        usdtPreprocessedPart2[2] = 0xf68408df0b8dda3f529522a67be22f2934970885243a9d2cf17d140f2ac1bb10;
        usdtPreprocessedPart2[3] = 0x4b0d9a6ffeb25101ff57e35d7e527f2080c460edc122f2480f8313555a71d3ac;

        RollupBridge(bridgeAddress).setAllowedTargetContract(
            usdtAddress, usdtPreprocessedPart1, usdtPreprocessedPart2, true
        );

        console.log("USDT target contract configured:", usdtAddress);
    }
}
