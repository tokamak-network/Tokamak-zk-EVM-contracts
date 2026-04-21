#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Contract, JsonRpcProvider, Wallet } from "ethers";
import {
  buildDAppDefinitions,
  buildFunctionDefinition,
  copyDir,
  copyFile,
  ensureDir,
  isCapacityError,
  loadExampleManifest,
  readJson,
  slugify,
  writeJson,
} from "../../scripts/zk/lib/tokamak-artifacts.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const tokamakSubmoduleRoot = path.join(repoRoot, "submodules", "Tokamak-zk-EVM");
const synthesizerRoot = path.join(tokamakSubmoduleRoot, "packages", "frontend", "synthesizer");
const tokamakCliPath = path.join(tokamakSubmoduleRoot, "tokamak-cli");
const defaultArtifactsRoot = path.join(repoRoot, "bridge", "deployments", "dapp-registration-artifacts");
const syncAppGrothArtifactsScriptPath = path.join(
  repoRoot,
  "apps",
  "private-state",
  "scripts",
  "deploy",
  "sync-groth16-update-tree-artifacts.sh",
);

function usage() {
  console.log(`Usage:
  node bridge/scripts/admin-add-dapp.mjs --group <example-group> [--group <example-group> ...] --dapp-id <uint> [options]

Options:
  --deployment-path <path>          Bridge deployment JSON path; defaults to bridge/deployments/bridge.<chain-id>.json
  --abi-manifest <path>             ABI manifest path; defaults to bridge/deployments/bridge-abi-manifest.<chain-id>.json
  --dapp-manager <address>          Override DAppManager address; defaults from deployment JSON
  --dapp-label <name>               Logical DApp label used to merge multiple example groups
  --app-network <name>              App deployment network whose manifests should be used; defaults to APPS_NETWORK, BRIDGE_NETWORK, or the bridge chain name
  --app-deployment-path <path>      App deployment manifest; defaults to private-state latest for the app chain
  --storage-layout-path <path>      App storage-layout manifest; defaults to private-state latest for the app chain
  --rpc-url <url>                   JSON-RPC URL; defaults from bridge env variables
  --private-key <hex>               Broadcaster key; defaults from BRIDGE_DEPLOYER_PRIVATE_KEY
  --manifest-out <path>             Output manifest path; defaults to bridge/deployments/dapp-registration.<chain-id>.json
  --artifacts-out <path>            Directory for archived synthesizer/preprocess outputs

Example groups are resolved relative to:
  submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/examples/privateState/<group>/cli-launch-manifest.json
`);
}

function parseArgs(argv) {
  const options = {
    groups: [],
    dappId: null,
    deploymentPath: null,
    abiManifestPath: null,
    dAppManager: null,
    dappLabel: null,
    appNetwork: null,
    appDeploymentPath: null,
    storageLayoutPath: null,
    rpcUrl: null,
    privateKey: process.env.BRIDGE_DEPLOYER_PRIVATE_KEY ?? null,
    manifestOut: null,
    artifactsOut: defaultArtifactsRoot,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    const next = argv[i + 1];

    const take = (name) => {
      if (!next || next.startsWith("--")) {
        throw new Error(`Missing value for ${name}.`);
      }
      i += 1;
      return next;
    };

    switch (current) {
      case "--group":
        options.groups.push(take(current));
        break;
      case "--dapp-id":
        options.dappId = Number.parseInt(take(current), 10);
        break;
      case "--deployment-path":
        options.deploymentPath = path.resolve(process.cwd(), take(current));
        break;
      case "--abi-manifest":
        options.abiManifestPath = path.resolve(process.cwd(), take(current));
        break;
      case "--dapp-manager":
        options.dAppManager = take(current);
        break;
      case "--dapp-label":
        options.dappLabel = take(current);
        break;
      case "--app-network":
        options.appNetwork = take(current);
        break;
      case "--app-deployment-path":
        options.appDeploymentPath = path.resolve(process.cwd(), take(current));
        break;
      case "--storage-layout-path":
        options.storageLayoutPath = path.resolve(process.cwd(), take(current));
        break;
      case "--rpc-url":
        options.rpcUrl = take(current);
        break;
      case "--private-key":
        options.privateKey = take(current);
        break;
      case "--manifest-out":
        options.manifestOut = path.resolve(process.cwd(), take(current));
        break;
      case "--artifacts-out":
        options.artifactsOut = path.resolve(process.cwd(), take(current));
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        throw new Error(`Unknown option: ${current}`);
    }
  }

  if (options.groups.length === 0) {
    throw new Error("--group is required at least once.");
  }
  if (!Number.isInteger(options.dappId) || options.dappId < 0) {
    throw new Error("--dapp-id must be a non-negative integer.");
  }

  return options;
}

function resolveRpcUrl(options) {
  if (options.rpcUrl) {
    return options.rpcUrl;
  }

  if (process.env.BRIDGE_RPC_URL_OVERRIDE) {
    return process.env.BRIDGE_RPC_URL_OVERRIDE;
  }

  const network = process.env.BRIDGE_NETWORK;
  if (!network) {
    throw new Error("Missing --rpc-url and BRIDGE_NETWORK is not set.");
  }
  if (network === "anvil") {
    return "http://127.0.0.1:8545";
  }

  const apiKey = process.env.BRIDGE_ALCHEMY_API_KEY;
  if (!apiKey) {
    throw new Error("Missing --rpc-url and BRIDGE_ALCHEMY_API_KEY is not set.");
  }

  switch (network) {
    case "sepolia":
      return `https://eth-sepolia.g.alchemy.com/v2/${apiKey}`;
    case "mainnet":
      return `https://eth-mainnet.g.alchemy.com/v2/${apiKey}`;
    default:
      throw new Error(`Unsupported BRIDGE_NETWORK=${network}`);
  }
}

function normalizePrivateKey(privateKey) {
  if (!privateKey) {
    throw new Error("Missing --private-key and BRIDGE_DEPLOYER_PRIVATE_KEY is not set.");
  }
  return privateKey.startsWith("0x") ? privateKey : `0x${privateKey}`;
}

function resolveAbiManifestPath(options, deployment, deploymentPath) {
  if (options.abiManifestPath) {
    return options.abiManifestPath;
  }
  if (typeof deployment.abiManifestPath === "string" && deployment.abiManifestPath.length > 0) {
    const deploymentRelativePath = path.resolve(path.dirname(deploymentPath), deployment.abiManifestPath);
    if (fs.existsSync(deploymentRelativePath)) {
      return deploymentRelativePath;
    }
    const bridgeRelativePath = path.resolve(repoRoot, "bridge", deployment.abiManifestPath);
    if (fs.existsSync(bridgeRelativePath)) {
      return bridgeRelativePath;
    }
  }
  const chainId = Number.parseInt(String(deployment.chainId ?? 0), 10);
  return resolveBridgeAbiManifestPath(chainId);
}

function loadDAppManagerAbi(abiManifestPath) {
  const manifest = readJson(abiManifestPath);
  const abi = manifest.contracts?.dAppManager?.abi;
  if (!Array.isArray(abi)) {
    throw new Error(`ABI manifest does not include dAppManager ABI: ${abiManifestPath}`);
  }
  return abi;
}

function resolvePrivateStateManifestPath(rootDir, chainId, kind) {
  return path.join(repoRoot, "apps", "private-state", "deploy", `${kind}.${chainId}.latest.json`);
}

const APP_NETWORK_CHAIN_IDS = new Map([
  ["sepolia", 11155111],
  ["mainnet", 1],
  ["base-sepolia", 84532],
  ["base-mainnet", 8453],
  ["arb-sepolia", 421614],
  ["arb-mainnet", 42161],
  ["op-mainnet", 10],
  ["op-sepolia", 11155420],
  ["anvil", 31337],
]);

const CHAIN_ID_TO_APP_NETWORK = new Map(
  Array.from(APP_NETWORK_CHAIN_IDS.entries()).map(([network, chainId]) => [chainId, network]),
);

function resolveBridgeDeploymentPath(chainId) {
  return path.join(repoRoot, "bridge", "deployments", `bridge.${chainId}.json`);
}

function resolveBridgeAbiManifestPath(chainId) {
  return path.join(repoRoot, "bridge", "deployments", `bridge-abi-manifest.${chainId}.json`);
}

function resolveDefaultAppNetwork(chainId) {
  if (process.env.APPS_NETWORK) {
    return process.env.APPS_NETWORK;
  }
  if (process.env.BRIDGE_NETWORK) {
    return process.env.BRIDGE_NETWORK;
  }
  const network = CHAIN_ID_TO_APP_NETWORK.get(chainId);
  if (!network) {
    throw new Error(
      `Unable to infer an app deployment network for chain ID ${chainId}. Pass --app-network explicitly.`,
    );
  }
  return network;
}

function resolveAppChainId(appNetwork) {
  const chainId = APP_NETWORK_CHAIN_IDS.get(appNetwork);
  if (!chainId) {
    throw new Error(`Unsupported --app-network=${appNetwork}`);
  }
  return chainId;
}

function loadPrivateStateAppContext({ appDeploymentPath, storageLayoutPath }) {
  const deployment = readJson(appDeploymentPath);
  const storageLayout = readJson(storageLayoutPath);

  const controller = deployment.contracts?.controller;
  const l2AccountingVault = deployment.contracts?.l2AccountingVault;
  if (!controller || !l2AccountingVault) {
    throw new Error(`App deployment manifest is missing controller/L2AccountingVault: ${appDeploymentPath}`);
  }

  const liquidBalanceSlot = storageLayout.contracts?.L2AccountingVault?.storageLayout?.storage?.find(
    (entry) => entry.label === "liquidBalances",
  )?.slot;

  if (liquidBalanceSlot === undefined) {
    throw new Error(`Unable to locate L2AccountingVault.liquidBalances in ${storageLayoutPath}`);
  }

  const liquidBalanceSlotNumber = Number.parseInt(String(liquidBalanceSlot), 10);
  if (!Number.isInteger(liquidBalanceSlotNumber) || liquidBalanceSlotNumber < 0 || liquidBalanceSlotNumber > 0xff) {
    throw new Error(`L2AccountingVault.liquidBalances slot is out of uint8 range: ${liquidBalanceSlot}`);
  }

  return {
    entryContract: controller,
    storageMetadata: [
      {
        storageAddress: controller,
        preAllocKeys: [],
        userSlots: [],
        isChannelTokenVaultStorage: false,
      },
      {
        storageAddress: l2AccountingVault,
        preAllocKeys: [],
        userSlots: [liquidBalanceSlotNumber],
        isChannelTokenVaultStorage: true,
      },
    ],
  };
}

function run(command, args, { cwd = repoRoot, streamOutput = true, env = process.env } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let combined = "";

    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      combined += text;
      if (streamOutput) {
        process.stdout.write(text);
      }
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      combined += text;
      if (streamOutput) {
        process.stderr.write(text);
      }
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve(combined);
      } else {
        const error = new Error(`${command} ${args.join(" ")} exited with code ${code ?? "unknown"}.`);
        error.output = combined;
        reject(error);
      }
    });
  });
}

async function updateTokamakSubmodule() {
  await run("git", ["fetch", "origin", "dev"], { cwd: tokamakSubmoduleRoot });
  await run("git", ["checkout", "-B", "dev", "origin/dev"], { cwd: tokamakSubmoduleRoot });
  await run("git", ["pull", "--ff-only", "origin", "dev"], { cwd: tokamakSubmoduleRoot });
}

async function runTokamakInstall() {
  await run(tokamakCliPath, ["--install"], { cwd: tokamakSubmoduleRoot });
}

function buildTokamakCliArgs(files) {
  return [
    "--synthesize",
    "--tokamak-ch-tx",
    "--previous-state",
    path.join(synthesizerRoot, files.previousState),
    "--transaction",
    path.join(synthesizerRoot, files.transaction),
    "--block-info",
    path.join(synthesizerRoot, files.blockInfo),
    "--contract-code",
    path.join(synthesizerRoot, files.contractCode),
  ];
}

function distDir() {
  return path.join(tokamakSubmoduleRoot, "dist");
}

function synthOutputDir() {
  return path.join(distDir(), "resource", "synthesizer", "output");
}

function preprocessOutputPath() {
  return path.join(distDir(), "resource", "preprocess", "output", "preprocess.json");
}

function collectInstanceDescriptionErrors(instanceDescriptionPath) {
  if (!fs.existsSync(instanceDescriptionPath)) {
    return [];
  }
  const contents = fs.readFileSync(instanceDescriptionPath, "utf8");
  return contents
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter((line) => /error:/iu.test(line));
}

async function processDAppGroup(groupName, archiveRoot, appContext, dappLabel) {
  const groupRoot = path.join(synthesizerRoot, "examples", "privateState", groupName);
  const manifestPath = path.join(groupRoot, "cli-launch-manifest.json");
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`Unknown DApp example group: ${groupName}`);
  }

  ensureDir(archiveRoot);
  const entries = loadExampleManifest(manifestPath);
  const processed = [];
  const skipped = [];

  for (const entry of entries) {
    const exampleName = entry.files.previousState.split("/").slice(-2, -1)[0];
    const exampleOutputRoot = path.join(archiveRoot, slugify(exampleName));

    try {
      await run(tokamakCliPath, buildTokamakCliArgs(entry.files), { cwd: tokamakSubmoduleRoot });
    } catch (error) {
      const output = error.output ?? String(error);
      if (isCapacityError(output)) {
        skipped.push({
          groupName,
          exampleName,
          reason: "qap-compiler capacity exceeded",
        });
        continue;
      }
      throw new Error(`Synthesize failed for ${groupName}/${exampleName}: ${output}`);
    }

    const instanceDescriptionPath = path.join(synthOutputDir(), "instance_description.json");
    const errorLines = collectInstanceDescriptionErrors(instanceDescriptionPath);
    if (errorLines.length > 0) {
      const combined = errorLines.join("\n");
      if (isCapacityError(combined)) {
        skipped.push({
          groupName,
          exampleName,
          reason: "qap-compiler capacity exceeded",
        });
        continue;
      }
      throw new Error(`Synthesizer emitted errors for ${groupName}/${exampleName}:\n${combined}`);
    }

    copyDir(synthOutputDir(), path.join(exampleOutputRoot, "synthesizer-output"));

    await run(tokamakCliPath, ["--preprocess"], { cwd: tokamakSubmoduleRoot });
    copyFile(preprocessOutputPath(), path.join(exampleOutputRoot, "preprocess.json"));

    processed.push(
      buildFunctionDefinition({
        groupName: dappLabel,
        exampleName: `${groupName}/${exampleName}`,
        transactionJsonPath: path.join(synthesizerRoot, entry.files.transaction),
        snapshotJsonPath: path.join(synthesizerRoot, entry.files.previousState),
        preprocessJsonPath: path.join(exampleOutputRoot, "preprocess.json"),
        instanceJsonPath: path.join(exampleOutputRoot, "synthesizer-output", "instance.json"),
        instanceDescriptionJsonPath: path.join(exampleOutputRoot, "synthesizer-output", "instance_description.json"),
        entryContractOverride: appContext.entryContract,
        storageMetadataOverride: appContext.storageMetadata,
      })
    );
  }

  if (processed.length === 0) {
    throw new Error(`No processable examples remained for ${groupName}.`);
  }

  return { processed, skipped };
}

async function assertDAppDoesNotExist(dAppManager, dappId) {
  try {
    await dAppManager.getDAppInfo(dappId);
    throw new Error(`DApp ${dappId} already exists. Modifying existing DApp metadata is not supported.`);
  } catch (error) {
    const revertName = error?.revert?.name ?? error?.info?.errorName ?? error?.errorName;
    const shortMessage = error?.shortMessage ?? error?.message ?? "";
    if (revertName === "UnknownDApp" || shortMessage.includes("UnknownDApp")) {
      return;
    }
    if (String(error?.message ?? "").includes("already exists")) {
      throw error;
    }
    throw error;
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const rpcUrl = resolveRpcUrl(options);
  const privateKey = normalizePrivateKey(options.privateKey);
  const provider = new JsonRpcProvider(rpcUrl);
  const chainId = Number((await provider.getNetwork()).chainId);
  const deploymentPath = options.deploymentPath ?? resolveBridgeDeploymentPath(chainId);
  const deployment = readJson(deploymentPath);
  const abiManifestPath = resolveAbiManifestPath(options, deployment, deploymentPath);
  const dAppManagerAddress = options.dAppManager ?? deployment.dAppManager;
  if (!dAppManagerAddress) {
    throw new Error("Unable to resolve DAppManager address from arguments or deployment artifact.");
  }
  const appNetwork = options.appNetwork ?? resolveDefaultAppNetwork(chainId);
  const appChainId = resolveAppChainId(appNetwork);
  await updateTokamakSubmodule();
  await runTokamakInstall();
  const appDeploymentPath =
    options.appDeploymentPath ?? resolvePrivateStateManifestPath(repoRoot, appChainId, "deployment");
  const storageLayoutPath =
    options.storageLayoutPath ?? resolvePrivateStateManifestPath(repoRoot, appChainId, "storage-layout");
  const manifestOut =
    options.manifestOut ?? path.join(repoRoot, "bridge", "deployments", `dapp-registration.${chainId}.json`);
  const dappLabel = options.dappLabel ?? "private-state";
  const artifactsRoot = path.join(options.artifactsOut, dappLabel);
  ensureDir(artifactsRoot);
  const appContext = loadPrivateStateAppContext({ appDeploymentPath, storageLayoutPath });

  const allProcessed = [];
  const allSkipped = [];
  for (const groupName of options.groups) {
    const processedGroup = await processDAppGroup(groupName, artifactsRoot, appContext, dappLabel);
    allProcessed.push(...processedGroup.processed);
    allSkipped.push(...processedGroup.skipped);
  }

  const dapps = buildDAppDefinitions(allProcessed);
  if (dapps.length !== 1) {
    throw new Error(`Expected exactly one DApp definition for ${dappLabel}, received ${dapps.length}.`);
  }
  const dapp = dapps[0];

  const wallet = new Wallet(privateKey, provider);
  const dAppManager = new Contract(dAppManagerAddress, loadDAppManagerAbi(abiManifestPath), wallet);

  await assertDAppDoesNotExist(dAppManager, options.dappId);

  const tx = await dAppManager.registerDApp(
    options.dappId,
    dapp.labelHash,
    dapp.storageMetadata.map((storage) => ({
      storageAddr: storage.storageAddress,
      preAllocatedKeys: storage.preAllocKeys,
      userStorageSlots: storage.userSlots,
      isChannelTokenVaultStorage: storage.isChannelTokenVaultStorage,
    })),
    dapp.functions.map((fn) => ({
      entryContract: fn.entryContract,
      functionSig: fn.functionSig,
      preprocessInputHash: fn.preprocessInputHash,
      instanceLayout: {
        entryContractOffsetWords: fn.entryContractOffsetWords,
        functionSigOffsetWords: fn.functionSigOffsetWords,
        currentRootVectorOffsetWords: fn.currentRootVectorOffsetWords,
        updatedRootVectorOffsetWords: fn.updatedRootVectorOffsetWords,
        eventLogs: fn.eventLogs,
      },
    }))
  );
  const receipt = await tx.wait();

  await run("bash", [syncAppGrothArtifactsScriptPath, String(appChainId)], {
    cwd: repoRoot,
  });

  const manifest = {
    generatedAt: new Date().toISOString(),
    deploymentPath,
    abiManifestPath,
    appNetwork,
    appChainId,
    appDeploymentPath,
    storageLayoutPath,
    appGrothManifestPath: path.join(repoRoot, "apps", "private-state", "deploy", `groth16-updateTree.${appChainId}.latest.json`),
    groupNames: options.groups,
    dappLabel,
    dappId: options.dappId,
    dAppManager: dAppManagerAddress,
    rpcUrl,
    artifactsRoot,
    processedExamples: allProcessed.map((entry) => ({
      groupName: entry.groupName,
      exampleName: entry.exampleName,
      entryContract: entry.entryContract,
      functionSig: entry.functionSig,
    })),
    skippedExamples: allSkipped,
    registration: {
      txHash: tx.hash,
      blockNumber: receipt?.blockNumber ?? null,
      labelHash: dapp.labelHash,
      storageCount: dapp.storageMetadata.length,
      functionCount: dapp.functions.length,
    },
  };

  writeJson(manifestOut, manifest);
  console.log(`Using app deployment manifest: ${appDeploymentPath}`);
  console.log(`Using app storage layout manifest: ${storageLayoutPath}`);
  console.log(`Registered DApp ${options.dappId} for groups ${options.groups.join(", ")} as ${dappLabel}.`);
  console.log(`Wrote manifest: ${manifestOut}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
