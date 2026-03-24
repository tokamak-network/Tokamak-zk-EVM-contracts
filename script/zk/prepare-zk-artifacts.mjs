#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  Contract,
  JsonRpcProvider,
  Wallet,
} from "ethers";
import {
  assertExists,
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
} from "./lib/tokamak-artifacts.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const tokamakSubmoduleRoot = path.join(repoRoot, "submodules", "Tokamak-zk-EVM");
const synthesizerRoot = path.join(tokamakSubmoduleRoot, "packages", "frontend", "synthesizer");
const tokamakCliPath = path.join(tokamakSubmoduleRoot, "tokamak-cli");
const sigmaVerifyRkyvPath = path.join(
  tokamakSubmoduleRoot,
  "dist",
  "resource",
  "setup",
  "output",
  "sigma_verify.rkyv",
);
const setupParamsPath = path.join(
  tokamakSubmoduleRoot,
  "dist",
  "resource",
  "qap-compiler",
  "library",
  "setupParams.json",
);
const sigmaVerifyJsonPath = path.join(
  repoRoot,
  "tokamak-zkp",
  "TokamakVerifierKey",
  "sigma_verify.json",
);
const tokamakVerifierGeneratedPath = path.join(
  repoRoot,
  "tokamak-zkp",
  "TokamakVerifierKey",
  "TokamakVerifierKey.generated.sol",
);
const tokamakVerifierSourcePath = path.join(repoRoot, "tokamak-zkp", "TokamakVerifier.sol");
const grothVerificationKeyPath = path.join(
  repoRoot,
  "groth16",
  "trusted-setup",
  "updateTree",
  "verification_key.json",
);
const grothVerifierOutputPath = path.join(
  repoRoot,
  "groth16",
  "verifier",
  "src",
  "Groth16Verifier.sol",
);
const outputRoot = path.join(repoRoot, "script", "output", "zk-artifacts");
const defaultManifestPath = path.join(outputRoot, "manifest.json");
const dAppManagerAbi = [
  "function registerDApp(uint256 dappId, bytes32 labelHash, tuple(address storageAddr, bytes32[] preAllocatedKeys, uint8[] userStorageSlots, bool isTokenVaultStorage)[] storages, tuple(address entryContract, bytes4 functionSig, address[] storageAddrs, bytes32 preprocessInputHash, uint16 updatedRootVectorOffsetWords)[] functions) external",
];
const bridgeCoreAbi = [
  "function createChannel(uint256 channelId, uint256 dappId, address leader, address asset, bytes32 aPubBlockHash) external returns (address manager, address vault)",
];

const privateStateGroups = [
  "privateStateMint",
  "privateStateTransfer",
  "privateStateRedeem",
];

function usage() {
  console.log(`Usage:
  node script/zk/prepare-zk-artifacts.mjs --install-arg <ALCHEMY_API_KEY|ALCHEMY_RPC_URL> [options]

Options:
  --dapp-manager <address>           Register derived DApp metadata on the bridge
  --bridge-core <address>            Create channels after DApp registration
  --leader <address>                 Channel leader used when creating channels
  --asset <address>                  L1 token address used when creating channels
  --dapp-id-base <uint>              Starting DApp ID for uploaded groups (default: 1)
  --channel-id-base <uint>           Starting channel ID for created example channels (default: 1)
  --rpc-url <url>                    JSON-RPC URL for bridge registration
  --private-key <hex>                Broadcaster key for bridge registration
  --manifest-out <path>              Output manifest path
  --create-channels                  Create one channel per processed example after DApp registration
  --skip-submodule-update            Skip updating submodules/Tokamak-zk-EVM to origin/dev
  --skip-install                     Skip tokamak-cli --install
  --skip-private-state               Skip private-state example synthesis/preprocess
  --skip-bridge-upload               Do not register artifacts on the bridge
  --skip-groth                       Skip Groth16 trusted-setup/verifier regeneration
  --skip-tokamak-verifier            Skip Tokamak sigma conversion and generated-key refresh
`);
}

function parseArgs(argv) {
  const options = {
    installArg: null,
    dAppManager: null,
    bridgeCore: null,
    leader: null,
    asset: null,
    dappIdBase: 1,
    channelIdBase: 1,
    createChannels: false,
    rpcUrl: null,
    privateKey: null,
    manifestOut: defaultManifestPath,
    skipSubmoduleUpdate: false,
    skipInstall: false,
    skipPrivateState: false,
    skipBridgeUpload: false,
    skipGroth: false,
    skipTokamakVerifier: false,
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
      case "--install-arg":
        options.installArg = take(current);
        break;
      case "--dapp-manager":
        options.dAppManager = take(current);
        break;
      case "--bridge-core":
        options.bridgeCore = take(current);
        break;
      case "--leader":
        options.leader = take(current);
        break;
      case "--asset":
        options.asset = take(current);
        break;
      case "--dapp-id-base":
        options.dappIdBase = Number.parseInt(take(current), 10);
        break;
      case "--channel-id-base":
        options.channelIdBase = Number.parseInt(take(current), 10);
        break;
      case "--create-channels":
        options.createChannels = true;
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
      case "--skip-submodule-update":
        options.skipSubmoduleUpdate = true;
        break;
      case "--skip-install":
        options.skipInstall = true;
        break;
      case "--skip-private-state":
        options.skipPrivateState = true;
        break;
      case "--skip-bridge-upload":
        options.skipBridgeUpload = true;
        break;
      case "--skip-groth":
        options.skipGroth = true;
        break;
      case "--skip-tokamak-verifier":
        options.skipTokamakVerifier = true;
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        throw new Error(`Unknown option: ${current}`);
    }
  }

  if (!options.skipInstall && !options.installArg) {
    throw new Error("--install-arg is required unless --skip-install is used.");
  }

  if (!options.skipBridgeUpload) {
    const missing = [];
    if (!options.dAppManager) missing.push("--dapp-manager");
    if (!options.rpcUrl) missing.push("--rpc-url");
    if (!options.privateKey) missing.push("--private-key");
    if (missing.length > 0) {
      throw new Error(
        `Bridge upload requires ${missing.join(", ")}. Use --skip-bridge-upload to omit on-chain registration.`,
      );
    }
  }

  if (options.createChannels) {
    if (options.skipBridgeUpload) {
      throw new Error("--create-channels requires bridge upload. Remove --skip-bridge-upload.");
    }
    const missing = [];
    if (!options.bridgeCore) missing.push("--bridge-core");
    if (!options.leader) missing.push("--leader");
    if (!options.asset) missing.push("--asset");
    if (missing.length > 0) {
      throw new Error(`Channel creation requires ${missing.join(", ")}.`);
    }
  }

  return options;
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

async function regenerateTokamakVerifierKey() {
  assertExists(sigmaVerifyRkyvPath, "Tokamak sigma_verify.rkyv");
  assertExists(setupParamsPath, "Tokamak setupParams.json");

  await run(
    "cargo",
    [
      "run",
      "--manifest-path",
      path.join("script", "zk", "rkyv-to-json", "Cargo.toml"),
      "--",
      sigmaVerifyRkyvPath,
      sigmaVerifyJsonPath,
    ],
    { cwd: repoRoot },
  );

  await run("node", [path.join("script", "generate-tokamak-verifier-key.js")], { cwd: repoRoot });
  await run("node", [path.join("script", "generate-tokamak-verifier-params.js")], { cwd: repoRoot });

  assertExists(sigmaVerifyJsonPath, "Tokamak sigma_verify.json");
  assertExists(tokamakVerifierGeneratedPath, "Tokamak generated verification key");
  assertExists(tokamakVerifierSourcePath, "Tokamak verifier source");
}

async function regenerateGrothArtifacts() {
  await run("node", [path.join("groth16", "trusted-setup", "scripts", "generate_update_tree_setup.mjs")], {
    cwd: repoRoot,
  });
  await run(
    "python3",
    [
      path.join("groth16", "verifier", "scripts", "generate_update_tree_verifier.py"),
      grothVerificationKeyPath,
      grothVerifierOutputPath,
    ],
    { cwd: repoRoot },
  );
}

function buildTokamakCliArgs(exampleRoot, files) {
  return [
    "--synthesize",
    "--tokamak-ch-tx",
    "--previous-state",
    path.join(exampleRoot, files.previousState),
    "--transaction",
    path.join(exampleRoot, files.transaction),
    "--block-info",
    path.join(exampleRoot, files.blockInfo),
    "--contract-code",
    path.join(exampleRoot, files.contractCode),
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

async function processPrivateStateExamples() {
  const examplesRoot = path.join(synthesizerRoot, "examples");
  const archiveRoot = path.join(outputRoot, "private-state");
  ensureDir(archiveRoot);

  const processed = [];
  const skipped = [];

  for (const groupName of privateStateGroups) {
    const groupRoot = path.join(examplesRoot, groupName);
    const manifestPath = path.join(groupRoot, "cli-launch-manifest.json");
    const entries = loadExampleManifest(manifestPath);

    for (const entry of entries) {
      const exampleName = entry.files.previousState.split("/").slice(-2, -1)[0];
      const exampleId = `${groupName}/${exampleName}`;
      const exampleOutputRoot = path.join(archiveRoot, groupName, slugify(exampleName));

      try {
        await run(tokamakCliPath, buildTokamakCliArgs(synthesizerRoot, entry.files), {
          cwd: tokamakSubmoduleRoot,
        });
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
        throw new Error(`Synthesize failed for ${exampleId}: ${output}`);
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
        throw new Error(`Synthesizer emitted errors for ${exampleId}:\n${combined}`);
      }

      copyDir(synthOutputDir(), path.join(exampleOutputRoot, "synthesizer-output"));

      try {
        await run(tokamakCliPath, ["--preprocess"], { cwd: tokamakSubmoduleRoot });
      } catch (error) {
        throw new Error(`Preprocess failed for ${exampleId}: ${error.output ?? String(error)}`);
      }

      copyFile(preprocessOutputPath(), path.join(exampleOutputRoot, "preprocess.json"));

      processed.push(
        buildFunctionDefinition({
          groupName,
          exampleName,
          transactionJsonPath: path.join(synthesizerRoot, entry.files.transaction),
          snapshotJsonPath: path.join(synthesizerRoot, entry.files.previousState),
          preprocessJsonPath: path.join(exampleOutputRoot, "preprocess.json"),
          instanceJsonPath: path.join(exampleOutputRoot, "synthesizer-output", "instance.json"),
          instanceDescriptionJsonPath: path.join(
            exampleOutputRoot,
            "synthesizer-output",
            "instance_description.json"
          ),
        }),
      );
    }
  }

  return { processed, skipped };
}

async function uploadBridgeArtifacts(options, manifest) {
  const provider = new JsonRpcProvider(options.rpcUrl);
  const wallet = new Wallet(options.privateKey, provider);
  const dAppManager = new Contract(options.dAppManager, dAppManagerAbi, wallet);
  const bridgeCore = options.createChannels
    ? new Contract(options.bridgeCore, bridgeCoreAbi, wallet)
    : null;
  const upload = { dapps: [], channels: [] };

  for (let dappIndex = 0; dappIndex < manifest.bridge.dapps.length; dappIndex += 1) {
    const dapp = manifest.bridge.dapps[dappIndex];
    const dappId = options.dappIdBase + dappIndex;
    const tx = await dAppManager.registerDApp(
      dappId,
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
        storageAddrs: fn.storageAddresses,
        preprocessInputHash: fn.preprocessInputHash,
        updatedRootVectorOffsetWords: fn.updatedRootVectorOffsetWords,
      })),
    );
    await tx.wait();
    upload.dapps.push({
      dappId,
      groupName: dapp.groupName,
      txHash: tx.hash,
    });

    if (!options.createChannels) {
      continue;
    }

    for (let exampleIndex = 0; exampleIndex < dapp.examples.length; exampleIndex += 1) {
      const example = dapp.examples[exampleIndex];
      const channelId = options.channelIdBase + upload.channels.length;
      const staticResult = await bridgeCore.createChannel.staticCall(
        channelId,
        dappId,
        options.leader,
        options.asset,
        example.aPubBlockHash,
      );
      const channelTx = await bridgeCore.createChannel(
        channelId,
        dappId,
        options.leader,
        options.asset,
        example.aPubBlockHash,
      );
      await channelTx.wait();
      upload.channels.push({
        channelId,
        dappId,
        groupName: dapp.groupName,
        exampleName: example.exampleName,
        aPubBlockHash: example.aPubBlockHash,
        manager: staticResult[0],
        vault: staticResult[1],
        txHash: channelTx.hash,
      });
    }
  }

  return upload;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  ensureDir(outputRoot);

  if (!options.skipSubmoduleUpdate) {
    await updateTokamakSubmodule();
  }

  if (!options.skipInstall) {
    await runTokamakInstall(options.installArg);
  }

  if (!options.skipTokamakVerifier) {
    await regenerateTokamakVerifierKey();
  }

  if (!options.skipGroth) {
    await regenerateGrothArtifacts();
  }

  let privateStateResult = { processed: [], skipped: [] };
  if (!options.skipPrivateState) {
    privateStateResult = await processPrivateStateExamples();
  }

  const manifest = {
    generatedAt: new Date().toISOString(),
    tokamak: {
      submodulePath: tokamakSubmoduleRoot,
      sigmaVerifyRkyvPath,
      sigmaVerifyJsonPath,
      generatedVerifierKeyPath: tokamakVerifierGeneratedPath,
    },
    groth16: {
      verificationKeyPath: grothVerificationKeyPath,
      verifierPath: grothVerifierOutputPath,
      metadata: readJson(path.join(repoRoot, "groth16", "trusted-setup", "updateTree", "metadata.json")),
    },
    privateStateExamples: {
      processed: privateStateResult.processed,
      skipped: privateStateResult.skipped,
    },
    bridge: {
      hashEncoding: {
        preprocessInputHash: "keccak256(abi.encode(uint128[], uint256[]))",
        aPubBlockHash: "keccak256(abi.encode(uint256[]))",
      },
      dapps: buildDAppDefinitions(privateStateResult.processed),
      upload: null,
    },
  };

  if (!options.skipBridgeUpload) {
    manifest.bridge.upload = await uploadBridgeArtifacts(options, manifest);
  }

  writeJson(options.manifestOut, manifest);
  console.log(`Wrote manifest: ${options.manifestOut}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
