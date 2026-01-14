// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeDepositManager.sol";
import "../../src/BridgeProofManager.sol";
import "../../src/BridgeWithdrawManager.sol";
import "../../src/BridgeAdminManager.sol";
import "../../src/verifier/TokamakVerifier.sol";
import "../../src/verifier/Groth16Verifier16Leaves.sol";
import "../../src/verifier/Groth16Verifier32Leaves.sol";
import "../../src/verifier/Groth16Verifier64Leaves.sol";
import "../../src/verifier/Groth16Verifier64LeavesIC.sol";
import "../../src/verifier/Groth16Verifier128Leaves.sol";
import "../../src/verifier/Groth16Verifier128LeavesIC1.sol";
import "../../src/verifier/Groth16Verifier128LeavesIC2.sol";
import "../../src/library/ZecFrost.sol";

contract DeployV2Script is Script {
    // Implementation addresses
    address public rollupBridgeImpl;
    address public depositManagerImpl;
    address public proofManagerImpl;
    address public withdrawManagerImpl;
    address public adminManagerImpl;

    // Proxy addresses (main contracts)
    address public rollupBridge;
    address public depositManager;
    address public proofManager;
    address public withdrawManager;
    address public adminManager;

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

        // Always deploy a new TokamakVerifier
        console.log("Will deploy new TokamakVerifier (forced deployment)");

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

        // Always deploy a new TokamakVerifier
        console.log("Deploying new TokamakVerifier...");
        TokamakVerifier verifierContract = new TokamakVerifier();
        zkVerifier = address(verifierContract);
        console.log("TokamakVerifier deployed at:", zkVerifier);

        // Deploy Groth16 Verifiers
        console.log("Deploying Groth16Verifier16Leaves...");
        Groth16Verifier16Leaves groth16VerifierContract16 = new Groth16Verifier16Leaves();
        address groth16Verifier16 = address(groth16VerifierContract16);
        console.log("Groth16Verifier16Leaves deployed at:", groth16Verifier16);

        console.log("Deploying Groth16Verifier32Leaves...");
        Groth16Verifier32Leaves groth16VerifierContract32 = new Groth16Verifier32Leaves();
        address groth16Verifier32 = address(groth16VerifierContract32);
        console.log("Groth16Verifier32Leaves deployed at:", groth16Verifier32);

        console.log("Deploying Groth16Verifier64LeavesIC...");
        Groth16Verifier64LeavesIC groth16Verifier64IC = new Groth16Verifier64LeavesIC();
        console.log("Groth16Verifier64LeavesIC deployed at:", address(groth16Verifier64IC));

        console.log("Deploying Groth16Verifier64Leaves...");
        Groth16Verifier64Leaves groth16VerifierContract64 = new Groth16Verifier64Leaves(address(groth16Verifier64IC));
        address groth16Verifier64 = address(groth16VerifierContract64);
        console.log("Groth16Verifier64Leaves deployed at:", groth16Verifier64);

        console.log("Deploying Groth16Verifier128LeavesIC1...");
        Groth16Verifier128LeavesIC1 groth16Verifier128IC1 = new Groth16Verifier128LeavesIC1();
        console.log("Groth16Verifier128LeavesIC1 deployed at:", address(groth16Verifier128IC1));

        console.log("Deploying Groth16Verifier128LeavesIC2...");
        Groth16Verifier128LeavesIC2 groth16Verifier128IC2 = new Groth16Verifier128LeavesIC2();
        console.log("Groth16Verifier128LeavesIC2 deployed at:", address(groth16Verifier128IC2));

        console.log("Deploying Groth16Verifier128Leaves...");
        Groth16Verifier128Leaves groth16VerifierContract128 =
            new Groth16Verifier128Leaves(address(groth16Verifier128IC1), address(groth16Verifier128IC2));
        address groth16Verifier128 = address(groth16VerifierContract128);
        console.log("Groth16Verifier128Leaves deployed at:", groth16Verifier128);

        // Deploy ZecFrost if not provided
        if (zecFrost == address(0)) {
            console.log("Deploying ZecFrost...");
            ZecFrost zecFrostContract = new ZecFrost();
            zecFrost = address(zecFrostContract);
            console.log("ZecFrost deployed at:", zecFrost);
        } else {
            console.log("Using existing ZecFrost at:", zecFrost);
        }

        // Deploy Bridge implementation
        console.log("Deploying Bridge implementation...");
        BridgeCore rollupBridgeImplementation = new BridgeCore();
        rollupBridgeImpl = address(rollupBridgeImplementation);
        console.log("Bridge implementation deployed at:", rollupBridgeImpl);

        // Deploy manager implementations
        console.log("Deploying BridgeDepositManager implementation...");
        BridgeDepositManager depositManagerImplementation = new BridgeDepositManager();
        depositManagerImpl = address(depositManagerImplementation);
        console.log("BridgeDepositManager implementation deployed at:", depositManagerImpl);

        console.log("Deploying BridgeProofManager implementation...");
        BridgeProofManager proofManagerImplementation = new BridgeProofManager();
        proofManagerImpl = address(proofManagerImplementation);
        console.log("BridgeProofManager implementation deployed at:", proofManagerImpl);

        console.log("Deploying BridgeWithdrawManager implementation...");
        BridgeWithdrawManager withdrawManagerImplementation = new BridgeWithdrawManager();
        withdrawManagerImpl = address(withdrawManagerImplementation);
        console.log("BridgeWithdrawManager implementation deployed at:", withdrawManagerImpl);

        console.log("Deploying BridgeAdminManager implementation...");
        BridgeAdminManager adminManagerImplementation = new BridgeAdminManager();
        adminManagerImpl = address(adminManagerImplementation);
        console.log("BridgeAdminManager implementation deployed at:", adminManagerImpl);

        // Deploy Bridge proxy with temporary zero addresses
        console.log("Deploying Bridge proxy...");
        bytes memory rollupBridgeInitData =
            abi.encodeCall(BridgeCore.initialize, (address(0), address(0), address(0), address(0), deployer));

        ERC1967Proxy rollupBridgeProxy = new ERC1967Proxy(rollupBridgeImpl, rollupBridgeInitData);
        rollupBridge = address(rollupBridgeProxy);
        console.log("Bridge proxy deployed at:", rollupBridge);

        // Deploy manager proxies and initialize
        console.log("Deploying manager proxies...");

        // Deploy DepositManager proxy
        bytes memory depositManagerInitData = abi.encodeCall(BridgeDepositManager.initialize, (rollupBridge, deployer));
        ERC1967Proxy depositManagerProxy = new ERC1967Proxy(depositManagerImpl, depositManagerInitData);
        depositManager = address(depositManagerProxy);
        console.log("BridgeDepositManager proxy deployed at:", depositManager);

        // Deploy ProofManager proxy
        address[4] memory groth16Verifiers =
            [groth16Verifier16, groth16Verifier32, groth16Verifier64, groth16Verifier128];
        bytes memory proofManagerInitData = abi.encodeCall(
            BridgeProofManager.initialize, (rollupBridge, zkVerifier, zecFrost, groth16Verifiers, deployer)
        );
        ERC1967Proxy proofManagerProxy = new ERC1967Proxy(proofManagerImpl, proofManagerInitData);
        proofManager = address(proofManagerProxy);
        console.log("BridgeProofManager proxy deployed at:", proofManager);

        // Deploy WithdrawManager proxy
        bytes memory withdrawManagerInitData =
            abi.encodeCall(BridgeWithdrawManager.initialize, (rollupBridge, deployer));
        ERC1967Proxy withdrawManagerProxy = new ERC1967Proxy(withdrawManagerImpl, withdrawManagerInitData);
        withdrawManager = address(withdrawManagerProxy);
        console.log("BridgeWithdrawManager proxy deployed at:", withdrawManager);

        // Deploy AdminManager proxy
        bytes memory adminManagerInitData = abi.encodeCall(BridgeAdminManager.initialize, (rollupBridge, deployer));
        ERC1967Proxy adminManagerProxy = new ERC1967Proxy(adminManagerImpl, adminManagerInitData);
        adminManager = address(adminManagerProxy);
        console.log("BridgeAdminManager proxy deployed at:", adminManager);

        // Update bridge with correct manager addresses
        console.log("Updating bridge with manager addresses...");
        BridgeCore(rollupBridge).updateManagerAddresses(depositManager, proofManager, withdrawManager, adminManager);

        // Configure TON target contract
        console.log("Configuring TON target contract...");
        _configureTONContract(adminManager);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("All contracts deployed successfully!");

        // Log final addresses
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Tokamak Verifier:", zkVerifier);
        console.log("Groth16 Verifier16:", groth16Verifier16);
        console.log("Groth16 Verifier32:", groth16Verifier32);
        console.log("Groth16 Verifier64:", groth16Verifier64);
        console.log("Groth16 Verifier128:", groth16Verifier128);
        console.log("ZecFrost:", zecFrost);
        console.log("\n=== IMPLEMENTATIONS ===");
        console.log("Bridge Implementation:", rollupBridgeImpl);
        console.log("Deposit Manager Implementation:", depositManagerImpl);
        console.log("Proof Manager Implementation:", proofManagerImpl);
        console.log("Withdraw Manager Implementation:", withdrawManagerImpl);
        console.log("Admin Manager Implementation:", adminManagerImpl);
        console.log("\n=== PROXIES ===");
        console.log("Bridge Proxy:", rollupBridge);
        console.log("Deposit Manager Proxy:", depositManager);
        console.log("Proof Manager Proxy:", proofManager);
        console.log("Withdraw Manager Proxy:", withdrawManager);
        console.log("Admin Manager Proxy:", adminManager);
        console.log("\nDeployer (Owner):", deployer);

        // Post-deployment verification
        if (shouldVerify && bytes(etherscanApiKey).length > 0) {
            console.log("\n=== STARTING CONTRACT VERIFICATION ===");
            console.log("Note: Verification happens AFTER all contracts are deployed");
            console.log("Waiting 30 seconds before verification to allow Etherscan indexing...");
            vm.sleep(30000); // Wait 30 seconds
            verifyContracts();
        } else {
            console.log("\n=== SKIPPING CONTRACT VERIFICATION ===");
            if (!shouldVerify) {
                console.log("Reason: VERIFY_CONTRACTS=false");
            }
            if (bytes(etherscanApiKey).length == 0) {
                console.log("Reason: No ETHERSCAN_API_KEY provided");
            }
        }
    }

    function verifyContracts() internal {
        console.log("\n=== VERIFYING CONTRACTS ===");
        console.log("IMPORTANT: All contracts have been deployed. Now starting verification process.");

        // Ensure all required contracts are deployed before verification
        require(rollupBridgeImpl != address(0), "Bridge implementation not deployed");
        require(depositManagerImpl != address(0), "Deposit manager implementation not deployed");
        require(proofManagerImpl != address(0), "Proof manager implementation not deployed");
        require(withdrawManagerImpl != address(0), "Withdraw manager implementation not deployed");
        require(adminManagerImpl != address(0), "Admin manager implementation not deployed");
        require(rollupBridge != address(0), "Bridge proxy not deployed");
        require(depositManager != address(0), "Deposit manager proxy not deployed");
        require(proofManager != address(0), "Proof manager proxy not deployed");
        require(withdrawManager != address(0), "Withdraw manager proxy not deployed");
        require(adminManager != address(0), "Admin manager proxy not deployed");

        // Always verify TokamakVerifier since we always deploy a new one
        console.log("Verifying TokamakVerifier...");
        string[] memory verifierCmd = new string[](6);
        verifierCmd[0] = "forge";
        verifierCmd[1] = "verify-contract";
        verifierCmd[2] = vm.toString(zkVerifier);
        verifierCmd[3] = "src/verifier/TokamakVerifier.sol:TokamakVerifier";
        verifierCmd[4] = "--etherscan-api-key";
        verifierCmd[5] = etherscanApiKey;
        _verifyWithRetry(verifierCmd, "TokamakVerifier");

        // Only verify if we deployed a new ZecFrost (not using existing)
        bool deployedNewZecFrost = false;
        try vm.parseAddress(vm.envString("ZEC_FROST_ADDRESS")) {
            console.log("Skipping ZecFrost verification (pre-existing)");
        } catch {
            deployedNewZecFrost = true;
            console.log("Verifying ZecFrost...");
            string[] memory zecFrostCmd = new string[](6);
            zecFrostCmd[0] = "forge";
            zecFrostCmd[1] = "verify-contract";
            zecFrostCmd[2] = vm.toString(zecFrost);
            zecFrostCmd[3] = "src/library/ZecFrost.sol:ZecFrost";
            zecFrostCmd[4] = "--etherscan-api-key";
            zecFrostCmd[5] = etherscanApiKey;
            _verifyWithRetry(zecFrostCmd, "ZecFrost");
        }

        // Verify Bridge Implementation
        console.log("Verifying Bridge Implementation...");
        string[] memory rollupCmd = new string[](6);
        rollupCmd[0] = "forge";
        rollupCmd[1] = "verify-contract";
        rollupCmd[2] = vm.toString(rollupBridgeImpl);
        rollupCmd[3] = "src/BridgeCore.sol:BridgeCore";
        rollupCmd[4] = "--etherscan-api-key";
        rollupCmd[5] = etherscanApiKey;
        _verifyWithRetry(rollupCmd, "BridgeCore");

        // Verify Manager contracts
        console.log("Verifying BridgeDepositManager implementation...");
        string[] memory depositCmd = new string[](6);
        depositCmd[0] = "forge";
        depositCmd[1] = "verify-contract";
        depositCmd[2] = vm.toString(depositManagerImpl);
        depositCmd[3] = "src/BridgeDepositManager.sol:BridgeDepositManager";
        depositCmd[4] = "--etherscan-api-key";
        depositCmd[5] = etherscanApiKey;
        _verifyWithRetry(depositCmd, "BridgeDepositManager");

        console.log("Verifying BridgeProofManager implementation...");
        string[] memory proofCmd = new string[](6);
        proofCmd[0] = "forge";
        proofCmd[1] = "verify-contract";
        proofCmd[2] = vm.toString(proofManagerImpl);
        proofCmd[3] = "src/BridgeProofManager.sol:BridgeProofManager";
        proofCmd[4] = "--etherscan-api-key";
        proofCmd[5] = etherscanApiKey;
        _verifyWithRetry(proofCmd, "BridgeProofManager");

        console.log("Verifying BridgeWithdrawManager implementation...");
        string[] memory withdrawCmd = new string[](6);
        withdrawCmd[0] = "forge";
        withdrawCmd[1] = "verify-contract";
        withdrawCmd[2] = vm.toString(withdrawManagerImpl);
        withdrawCmd[3] = "src/BridgeWithdrawManager.sol:BridgeWithdrawManager";
        withdrawCmd[4] = "--etherscan-api-key";
        withdrawCmd[5] = etherscanApiKey;
        _verifyWithRetry(withdrawCmd, "BridgeWithdrawManager");

        console.log("Verifying BridgeAdminManager implementation...");
        string[] memory adminCmd = new string[](6);
        adminCmd[0] = "forge";
        adminCmd[1] = "verify-contract";
        adminCmd[2] = vm.toString(adminManagerImpl);
        adminCmd[3] = "src/BridgeAdminManager.sol:BridgeAdminManager";
        adminCmd[4] = "--etherscan-api-key";
        adminCmd[5] = etherscanApiKey;
        _verifyWithRetry(adminCmd, "BridgeAdminManager");

        console.log("Contract verification complete!");
    }

    function _verifyWithRetry(string[] memory cmd, string memory contractName) internal {
        uint256 maxRetries = 3;
        uint256 retryDelay = 15000; // 15 seconds

        for (uint256 i = 0; i < maxRetries; i++) {
            try vm.ffi(cmd) {
                console.log(string.concat(contractName, " verified successfully"));
                return;
            } catch {
                if (i < maxRetries - 1) {
                    console.log(string.concat("Verification failed for ", contractName, ", retrying in 15 seconds..."));
                    vm.sleep(retryDelay);
                } else {
                    console.log(
                        string.concat(
                            "Verification failed for ", contractName, " after ", vm.toString(maxRetries), " attempts"
                        )
                    );
                }
            }
        }
    }

    function _configureTONContract(address adminManagerAddress) internal {
        // TON contract address
        address tonAddress = 0xa30fe40285B8f5c0457DbC3B7C8A280373c40044;

        // TON preprocess data from WTON_preprocess.json
        uint128[] memory tonPreprocessedPart1 = new uint128[](4);
        tonPreprocessedPart1[0] = 0x11b01d3b7756a1e2c84462f2a011f8cf;
        tonPreprocessedPart1[1] = 0x110f0dbdfee1e30c55061363fd147c5f;
        tonPreprocessedPart1[2] = 0x02e86220169ffc66feac2bca980de255;
        tonPreprocessedPart1[3] = 0x12d32a9d10236151ea94eddd2de15df4;

        uint256[] memory tonPreprocessedPart2 = new uint256[](4);
        tonPreprocessedPart2[0] = 0xe2285fde54386faf68544ac49ac3f620c84265d1e76dffbbb780329a35c798f2;
        tonPreprocessedPart2[1] = 0x85767f719652f5fcde0bc847a1af46c16c3ffab6bded47addd0f8215588f1684;
        tonPreprocessedPart2[2] = 0xd775a85c51e4d33eaccca66cd04346c2d291b2c777daa08b093d91a9475e1623;
        tonPreprocessedPart2[3] = 0x3e984d129c3dab74f9d13ab9ab66d5d826fca5e1f6270242aaa5dedeedf2fe58;

        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        BridgeAdminManager(adminManagerAddress).setAllowedTargetContract(tonAddress, emptySlots, true);

        // Setup TON pre-allocated leaf for decimals (slot 0x07 with value 18)
        BridgeAdminManager(adminManagerAddress).setupTonTransferPreAllocatedLeaf(tonAddress);

        // Register TON transfer function
        bytes32 tonTransferSig = 0xa9059cbb00000000000000000000000000000000000000000000000000000000;
        bytes32 instanceHash = 0xd157cb883adb9cb0e27d9dc419e2a4be817d856281b994583b5bae64be94d35a;
        BridgeAdminManager(adminManagerAddress).registerFunction(
            tonAddress, tonTransferSig, tonPreprocessedPart1, tonPreprocessedPart2, instanceHash
        );

        console.log("TON target contract configured:", tonAddress);
        console.log("TON pre-allocated leaf (0x07 decimals) configured for:", tonAddress);
    }
}
