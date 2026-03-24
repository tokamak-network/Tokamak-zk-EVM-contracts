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
} from "../../script/zk/lib/tokamak-artifacts.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const tokamakSubmoduleRoot = path.join(repoRoot, "submodules", "Tokamak-zk-EVM");
const synthesizerRoot = path.join(tokamakSubmoduleRoot, "packages", "frontend", "synthesizer");
const tokamakCliPath = path.join(tokamakSubmoduleRoot, "tokamak-cli");
const defaultDeploymentPath = path.join(repoRoot, "bridge", "deployments", "bridge-latest.json");
const defaultArtifactsRoot = path.join(repoRoot, "bridge", "deployments", "dapp-registration-artifacts");
const defaultManifestPath = path.join(repoRoot, "bridge", "deployments", "dapp-registration.latest.json");

function usage() {
  console.log(`Usage:
  node bridge/script/admin-add-dapp.mjs --group <example-group> --dapp-id <uint> [options]

Options:
  --deployment-path <path>          Bridge deployment JSON path
  --abi-manifest <path>             ABI manifest path; defaults from deployment JSON
  --dapp-manager <address>          Override DAppManager address; defaults from deployment JSON
  --rpc-url <url>                   JSON-RPC URL; defaults from bridge env variables
  --private-key <hex>               Broadcaster key; defaults from BRIDGE_DEPLOYER_PRIVATE_KEY
  --install-arg <value>             tokamak-cli --install argument; defaults to resolved RPC URL
  --manifest-out <path>             Output manifest path
  --artifacts-out <path>            Directory for archived synthesizer/preprocess outputs
  --skip-submodule-update           Skip updating submodules/Tokamak-zk-EVM to origin/dev
  --skip-install                    Skip tokamak-cli --install
`);
}

function parseArgs(argv) {
  const options = {
    group: null,
    dappId: null,
    deploymentPath: defaultDeploymentPath,
    abiManifestPath: null,
    dAppManager: null,
    rpcUrl: null,
    privateKey: process.env.BRIDGE_DEPLOYER_PRIVATE_KEY ?? null,
    installArg: null,
    manifestOut: defaultManifestPath,
    artifactsOut: defaultArtifactsRoot,
    skipSubmoduleUpdate: false,
    skipInstall: false,
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
        options.group = take(current);
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
      case "--rpc-url":
        options.rpcUrl = take(current);
        break;
      case "--private-key":
        options.privateKey = take(current);
        break;
      case "--install-arg":
        options.installArg = take(current);
        break;
      case "--manifest-out":
        options.manifestOut = path.resolve(process.cwd(), take(current));
        break;
      case "--artifacts-out":
        options.artifactsOut = path.resolve(process.cwd(), take(current));
        break;
      case "--skip-submodule-update":
        options.skipSubmoduleUpdate = true;
        break;
      case "--skip-install":
        options.skipInstall = true;
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        throw new Error(`Unknown option: ${current}`);
    }
  }

  if (!options.group) {
    throw new Error("--group is required.");
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

function resolveAbiManifestPath(options, deployment) {
  if (options.abiManifestPath) {
    return options.abiManifestPath;
  }
  if (typeof deployment.abiManifestPath === "string" && deployment.abiManifestPath.length > 0) {
    return path.resolve(path.dirname(options.deploymentPath), deployment.abiManifestPath);
  }
  return path.join(repoRoot, "bridge", "deployments", "bridge-abi-manifest.latest.json");
}

function loadDAppManagerAbi(abiManifestPath) {
  const manifest = readJson(abiManifestPath);
  const abi = manifest.contracts?.dAppManager?.abi;
  if (!Array.isArray(abi)) {
    throw new Error(`ABI manifest does not include dAppManager ABI: ${abiManifestPath}`);
  }
  return abi;
}

function run(command, args, { cwd = repoRoot, streamOutput = true } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
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

async function runTokamakInstall(installArg) {
  await run(tokamakCliPath, ["--install", installArg], { cwd: tokamakSubmoduleRoot });
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

async function processDAppGroup(groupName, archiveRoot) {
  const groupRoot = path.join(synthesizerRoot, "examples", groupName);
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
        groupName,
        exampleName,
        transactionJsonPath: path.join(synthesizerRoot, entry.files.transaction),
        snapshotJsonPath: path.join(synthesizerRoot, entry.files.previousState),
        preprocessJsonPath: path.join(exampleOutputRoot, "preprocess.json"),
        instanceJsonPath: path.join(exampleOutputRoot, "synthesizer-output", "instance.json"),
        instanceDescriptionJsonPath: path.join(exampleOutputRoot, "synthesizer-output", "instance_description.json"),
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
  const deployment = readJson(options.deploymentPath);
  const abiManifestPath = resolveAbiManifestPath(options, deployment);
  const dAppManagerAddress = options.dAppManager ?? deployment.dAppManager;
  if (!dAppManagerAddress) {
    throw new Error("Unable to resolve DAppManager address from arguments or deployment artifact.");
  }

  const rpcUrl = resolveRpcUrl(options);
  const installArg = options.installArg ?? rpcUrl;
  const privateKey = normalizePrivateKey(options.privateKey);
  const artifactsRoot = path.join(options.artifactsOut, options.group);
  ensureDir(artifactsRoot);

  if (!options.skipSubmoduleUpdate) {
    await updateTokamakSubmodule();
  }
  if (!options.skipInstall) {
    await runTokamakInstall(installArg);
  }

  const processedGroup = await processDAppGroup(options.group, artifactsRoot);
  const dapps = buildDAppDefinitions(processedGroup.processed);
  if (dapps.length !== 1) {
    throw new Error(`Expected exactly one DApp definition for ${options.group}, received ${dapps.length}.`);
  }
  const dapp = dapps[0];

  const provider = new JsonRpcProvider(rpcUrl);
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
      isTokenVaultStorage: storage.isTokenVaultStorage,
    })),
    dapp.functions.map((fn) => ({
      entryContract: fn.entryContract,
      functionSig: fn.functionSig,
      preprocessInputHash: fn.preprocessInputHash,
      entryContractOffsetWords: fn.entryContractOffsetWords,
      functionSigOffsetWords: fn.functionSigOffsetWords,
      currentRootVectorOffsetWords: fn.currentRootVectorOffsetWords,
      updatedRootVectorOffsetWords: fn.updatedRootVectorOffsetWords,
      storageWrites: fn.storageWrites,
    }))
  );
  const receipt = await tx.wait();

  const manifest = {
    generatedAt: new Date().toISOString(),
    deploymentPath: options.deploymentPath,
    abiManifestPath,
    groupName: options.group,
    dappId: options.dappId,
    dAppManager: dAppManagerAddress,
    rpcUrl,
    artifactsRoot,
    processedExamples: processedGroup.processed.map((entry) => ({
      groupName: entry.groupName,
      exampleName: entry.exampleName,
      entryContract: entry.entryContract,
      functionSig: entry.functionSig,
    })),
    skippedExamples: processedGroup.skipped,
    registration: {
      txHash: tx.hash,
      blockNumber: receipt?.blockNumber ?? null,
      labelHash: dapp.labelHash,
      storageCount: dapp.storageMetadata.length,
      functionCount: dapp.functions.length,
    },
  };

  writeJson(options.manifestOut, manifest);
  console.log(`Registered DApp ${options.dappId} for group ${options.group}.`);
  console.log(`Wrote manifest: ${options.manifestOut}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
