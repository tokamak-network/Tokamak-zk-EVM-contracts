#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  HDNodeWallet,
  JsonRpcProvider,
  Wallet,
  ethers,
  getAddress,
} from "ethers";
import {
  createAddressFromString,
} from "@ethereumjs/util";
import {
  buildTokamakCliInvocation,
  resolveTokamakBlockInputConfig,
  resolveTokamakCliResourceDir,
  resolveTokamakCliSetupOutputDir,
} from "@tokamak-private-dapps/common-library/tokamak-runtime-paths";
import {
  deriveNoteReceiveKeyMaterial,
} from "../../cli/lib/private-state-note-delivery.mjs";
import {
  buildEncryptedMintOutput,
  buildEncryptedTransferOutput,
  buildMintInterface,
  buildRedeemInterface,
  buildStateManager,
  buildTokamakTxSnapshot,
  buildTransferInterface,
  currentStorageBigInt,
  deriveChannelTokenVaultLeafIndex,
  deriveLiquidBalanceStorageKey,
  fetchContractCodes,
  getFixedBlockInfo,
  initializePrivateStateSnapshot,
  normalizeBytes32Hex,
  putStorageValue,
} from "../lib/private-state-registration-fixtures.mjs";
import {
  deriveChannelIdFromName,
  deriveParticipantIdentityFromSigner,
  slugifyPathComponent,
  walletDirForName as walletDirForNameInRoot,
  walletNameForChannelAndAddress,
  workspaceDirForName,
  workspaceWalletsDir,
} from "../../cli/lib/private-state-cli-shared.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..", "..");
const appRoot = path.resolve(repoRoot, "packages", "apps", "private-state");
const bridgeRoot = path.resolve(repoRoot, "bridge");
const commonPackageRoot = path.resolve(repoRoot, "packages", "common");
const groth16PackageRoot = path.resolve(repoRoot, "packages", "groth16");
const cliPackageRoot = path.resolve(appRoot, "cli");
const cliPackageManifestPath = path.resolve(appRoot, "cli", "package.json");
const cliPackageManifest = JSON.parse(fs.readFileSync(cliPackageManifestPath, "utf8"));
const cliPackageSpecs = resolveCliPackageSpecs();
const cliPackageSpecLabel = cliPackageSpecs.join(" ");
const outputRoot = path.resolve(appRoot, "scripts", "e2e", "output", "private-state-bridge-cli");
const cliInstallRoot = path.resolve(outputRoot, "npm-cli-install");
const cliBinPath = path.join(
  cliInstallRoot,
  "node_modules",
  ".bin",
  process.platform === "win32" ? "private-state-cli.cmd" : "private-state-cli",
);
const bridgeDeployHelperPath = path.resolve(bridgeRoot, "scripts", "deploy-bridge.mjs");
const adminAddDAppPath = path.resolve(bridgeRoot, "scripts", "admin-add-dapp.mjs");
const privateStateDeployScriptPath = path.resolve(
  appRoot,
  "scripts",
  "deploy",
  "DeployPrivateState.s.sol:DeployPrivateStateScript",
);
const privateStateArtifactWriterPath = path.resolve(appRoot, "scripts", "deploy", "write-deploy-artifacts.mjs");
const systemMonitorRoot = path.resolve(outputRoot, "system-monitor");
const bridgeEnvPath = path.resolve(outputRoot, "bridge.anvil.env");
const summaryPath = path.resolve(outputRoot, "summary.json");
const failureDiagnosticsPath = path.resolve(outputRoot, "failure-diagnostics.json");
const dappMetadataRoot = path.resolve(outputRoot, "dapp-metadata");
const providerUrl = process.env.ANVIL_RPC_URL?.trim() || "http://127.0.0.1:8545";
const workspaceNetworkName = "anvil";
const anvilMnemonic = process.env.APPS_ANVIL_MNEMONIC?.trim() || "test test test test test test test test test test test junk";
const anvilDeployerPrivateKey =
  process.env.APPS_ANVIL_DEPLOYER_PRIVATE_KEY?.trim()
    || "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const txSubmitterAccount = "channel-creator";
const txSubmitterAddress = getAddress(new Wallet(anvilDeployerPrivateKey).address);
const channelName = "private-state-cli-e2e";
const dappId = "1";
const dappLabel = "private-state";
const joinTollTokens = "1";
const depositAmountTokens = "3";
const claimAmountTokens = "9";
const amountUnit = 10n ** 18n;
const joinTollBaseUnits = 1n * amountUnit;
const depositAmountBaseUnits = 3n * amountUnit;
const claimAmountBaseUnits = 9n * amountUnit;
const {
  aPubBlockLength: tokamakAPubBlockLength,
} = resolveTokamakBlockInputConfig();
const requiredTokamakSetupArtifacts = [
  "combined_sigma.rkyv",
  "sigma_preprocess.rkyv",
  "sigma_verify.json",
];
const tokamakCliInvocation = buildTokamakCliInvocation();
const tokamakStepArtifactDirectories = [
  path.join("synthesizer", "output"),
  path.join("preprocess", "output"),
];
const workspaceRoot = path.resolve(os.homedir(), "tokamak-private-channels", "workspace");
const secretRoot = path.resolve(os.homedir(), "tokamak-private-channels", "secrets");
const registrationLaunchInputsRoot = path.resolve(outputRoot, "generated-launch-inputs");
const localRegistrationExamples = [
  "mintNotes1",
  "mintNotes2",
  "transferNotes1To1",
  "transferNotes1To2",
  "transferNotes2To1",
  "redeemNotes1",
];
const timestampLabelPattern = /^\d{8}T\d{6}Z$/;

function usage() {
  console.log(`Usage:
  node packages/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs [options]

Options:
  --skip-install                      Skip Tokamak runtime and private-state artifact install steps
  --skip-groth-setup                  Skip bridge Groth16 refresh during local redeploy
  --keep-anvil                         Leave anvil running after success
  --help                               Show this help

Notes:
  - The participant scenario is executed through a private-state-cli binary installed into a temporary npm workspace.
  - Set PRIVATE_STATE_CLI_E2E_PACKAGE_SPEC to override the package spec. Default: ${cliPackageSpecLabel}
  - Set PRIVATE_STATE_CLI_E2E_PACKAGE_SPECS to install multiple package specs before running the binary.
  - Bridge deployment, DApp registration, and canonical-asset minting still use existing command-line helpers because
    the current private-state CLI does not expose those administrative setup flows.
`);
}

function resolveCliPackageSpecs() {
  const multiValue = process.env.PRIVATE_STATE_CLI_E2E_PACKAGE_SPECS?.trim();
  if (multiValue) {
    return parsePackageSpecs(multiValue, "PRIVATE_STATE_CLI_E2E_PACKAGE_SPECS");
  }

  const singleValue = process.env.PRIVATE_STATE_CLI_E2E_PACKAGE_SPEC?.trim();
  if (singleValue) {
    return [singleValue];
  }

  return [commonPackageRoot, groth16PackageRoot, cliPackageRoot];
}

function parsePackageSpecs(value, envName) {
  if (value.startsWith("[")) {
    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed) || parsed.some((entry) => typeof entry !== "string" || entry.trim() === "")) {
      throw new Error(`${envName} JSON value must be an array of non-empty strings.`);
    }
    return parsed.map((entry) => entry.trim());
  }

  const specs = value
    .split(/[\r\n,]+/u)
    .map((entry) => entry.trim())
    .filter(Boolean);
  if (specs.length === 0) {
    throw new Error(`${envName} did not contain any npm package specs.`);
  }
  return specs;
}

function parseArgs(argv) {
  const options = {
    runInstall: true,
    runGrothSetup: true,
    keepAnvil: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    switch (current) {
      case "--skip-install":
        options.runInstall = false;
        break;
      case "--skip-groth-setup":
        options.runGrothSetup = false;
        break;
      case "--keep-anvil":
        options.keepAnvil = true;
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        throw new Error(`Unknown option: ${current}`);
    }
  }

  return options;
}

function expect(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

let currentCliE2EOptions = {
  runGrothSetup: true,
};

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function cleanDir(dirPath) {
  fs.rmSync(dirPath, { recursive: true, force: true });
  fs.mkdirSync(dirPath, { recursive: true });
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function latestBridgeDeploymentPath() {
  const latestDir = requireLatestTimestampDir(
    path.join(repoRoot, "deployment", "chain-id-31337", "bridge"),
    "bridge deployment snapshot for chain 31337",
  );
  return path.join(latestDir, "bridge.31337.json");
}

function latestPrivateStateArtifactDir() {
  return requireLatestTimestampDir(
    path.join(repoRoot, "deployment", "chain-id-31337", "dapps", "private-state"),
    "private-state DApp deployment snapshot for chain 31337",
  );
}

function requireLatestTimestampDir(rootDir, description) {
  if (!fs.existsSync(rootDir)) {
    throw new Error(`Missing ${description} root: ${rootDir}`);
  }

  const labels = fs.readdirSync(rootDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && timestampLabelPattern.test(entry.name))
    .map((entry) => entry.name)
    .sort();
  const latestLabel = labels.at(-1);
  if (!latestLabel) {
    throw new Error(`No timestamped ${description} exists under ${rootDir}.`);
  }
  return path.join(rootDir, latestLabel);
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(
    filePath,
    `${JSON.stringify(value, (_key, current) => (
      typeof current === "bigint" ? current.toString() : current
    ), 2)}\n`,
  );
}

function writeSecretFile(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true, mode: 0o700 });
  fs.writeFileSync(filePath, `${String(value).trim()}\n`, { mode: 0o600 });
  fs.chmodSync(filePath, 0o600);
}

function readJsonIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return readJson(filePath);
}

const currentCommandPath = path.join(systemMonitorRoot, "current-command.json");
const lastCommandPath = path.join(systemMonitorRoot, "last-command.json");
const commandHistoryPath = path.join(systemMonitorRoot, "command-history.ndjson");

function appendCommandHistory(entry) {
  ensureDir(systemMonitorRoot);
  fs.appendFileSync(
    commandHistoryPath,
    `${JSON.stringify(entry, (_key, current) => (
      typeof current === "bigint" ? current.toString() : current
    ))}\n`,
  );
}

function updateCurrentCommand(entry) {
  writeJson(currentCommandPath, entry);
}

function clearCurrentCommand() {
  fs.rmSync(currentCommandPath, { force: true });
}

function run(command, args, {
  cwd = repoRoot,
  env = process.env,
  captureStdout = false,
  quiet = false,
  label = null,
} = {}) {
  const printable = [command, ...args].join(" ");
  const commandLabel = label ?? printable;
  const startedAtMs = Date.now();
  const startedAt = new Date(startedAtMs).toISOString();
  updateCurrentCommand({
    label: commandLabel,
    command,
    args,
    cwd,
    captureStdout,
    quiet,
    startedAt,
  });
  appendCommandHistory({
    event: "start",
    label: commandLabel,
    command,
    args,
    cwd,
    captureStdout,
    quiet,
    startedAt,
  });
  console.log(`E2E CLI: ${printable}`);
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: captureStdout
      ? ["ignore", "pipe", quiet ? "pipe" : "inherit"]
      : (quiet ? ["ignore", "ignore", "pipe"] : "inherit"),
  });
  const finishedAtMs = Date.now();
  const finishedAt = new Date(finishedAtMs).toISOString();
  const completedEntry = {
    label: commandLabel,
    command,
    args,
    cwd,
    captureStdout,
    quiet,
    startedAt,
    finishedAt,
    durationMs: finishedAtMs - startedAtMs,
    exitCode: result.status,
    signal: result.signal ?? null,
    stdoutLength: (result.stdout ?? "").length,
    stderrLength: (result.stderr ?? "").length,
  };
  writeJson(lastCommandPath, completedEntry);
  appendCommandHistory({
    event: result.status === 0 ? "success" : "failure",
    ...completedEntry,
  });
  clearCurrentCommand();

  if (result.status !== 0) {
    throw new Error(
      [
        `${printable} failed with exit code ${result.status ?? "unknown"}.`,
        captureStdout && (result.stdout ?? "").trim().length > 0 ? `stdout:\n${result.stdout}` : null,
        quiet && (result.stderr ?? "").trim().length > 0 ? `stderr:\n${result.stderr}` : null,
      ].filter(Boolean).join("\n"),
    );
  }

  return captureStdout ? (result.stdout ?? "") : "";
}

function runJsonCommand(command, args, options = {}) {
  const stdout = run(command, [...args, "--json"], {
    ...options,
    captureStdout: true,
    quiet: options.quiet ?? true,
  });
  const trimmedStdout = stdout.trim();
  try {
    return JSON.parse(trimmedStdout);
  } catch (error) {
    throw new Error(
      [
        `Expected JSON output from ${command} ${args.join(" ")}.`,
        `stdout:\n${trimmedStdout}`,
      ].join("\n"),
    );
  }
}

function installPrivateStateCliPackageForE2E() {
  cleanDir(cliInstallRoot);
  writeJson(path.join(cliInstallRoot, "package.json"), {
    private: true,
    type: "module",
    description: "Temporary private-state CLI E2E install root.",
  });
  run("npm", ["install", "--package-lock=false", "--no-audit", "--no-fund", ...cliPackageSpecs], {
    cwd: cliInstallRoot,
    quiet: true,
    label: "private-state-cli:npm-install",
  });
  expect(
    fs.existsSync(cliBinPath),
    `npm install completed but private-state-cli binary is missing: ${cliBinPath}`,
  );
  run(cliBinPath, ["--help"], {
    cwd: cliInstallRoot,
    quiet: true,
    label: "private-state-cli:npm-smoke-help",
  });
  return {
    packageSpecs: cliPackageSpecs,
    installRoot: cliInstallRoot,
    binPath: cliBinPath,
  };
}

function loadLiquidBalancesSlot() {
  const storageLayout = readJson(path.join(latestPrivateStateArtifactDir(), "storage-layout.31337.latest.json"));
  return ethers.toBigInt(
    storageLayout.contracts.L2AccountingVault.storageLayout.storage.find((entry) => entry.label === "liquidBalances").slot,
  );
}

async function buildGrothTransition(stepName, stateManager, vaultAddress, keyHex, nextValue) {
  const vaultAddressObj = createAddressFromString(vaultAddress);
  const keyBigInt = ethers.toBigInt(keyHex);
  const proof = stateManager.merkleTrees.getProof(vaultAddressObj, keyBigInt);
  const currentValue = await currentStorageBigInt(stateManager, vaultAddress, keyHex);

  await putStorageValue(stateManager, vaultAddress, keyHex, nextValue);

  return {
    stepName,
    proof,
    currentValue,
    nextSnapshot: await stateManager.captureStateSnapshot(),
  };
}

function writeRegistrationLaunchBundle(exampleName, snapshot, transaction, blockInfo, contractCodes, { register = true } = {}) {
  const bundleDir = register
    ? path.join(registrationLaunchInputsRoot, dappLabel, exampleName)
    : path.join(dappMetadataRoot, "_internal-inputs", exampleName);
  cleanDir(bundleDir);
  writeJson(path.join(bundleDir, "previous_state_snapshot.json"), snapshot);
  writeJson(path.join(bundleDir, "transaction.json"), transaction);
  writeJson(path.join(bundleDir, "block_info.json"), blockInfo);
  writeJson(path.join(bundleDir, "contract_codes.json"), contractCodes);
  return bundleDir;
}

function registrationParticipantAt(participants, index) {
  const participant = participants[index];
  expect(participant?.registration, `Missing resolved registration context for participant index ${index}.`);
  return participant;
}

function assertTokamakSetupArtifactsInstalled() {
  const tokamakSetupDistDir = resolveTokamakCliSetupOutputDir();
  const missingInDist = requiredTokamakSetupArtifacts.filter(
    (fileName) => !fs.existsSync(path.join(tokamakSetupDistDir, fileName)),
  );
  if (missingInDist.length === 0) {
    return;
  }
  throw new Error(
    [
      `Missing Tokamak setup artifacts in ${tokamakSetupDistDir}: ${missingInDist.join(", ")}.`,
      "Run tokamak-cli --install or rerun this script without --skip-install.",
    ].join(" "),
  );
}

function copyTokamakArtifacts(stepDir) {
  const resourceRoot = path.join(stepDir, "resource");
  fs.rmSync(resourceRoot, { recursive: true, force: true });
  for (const relativeDirectory of tokamakStepArtifactDirectories) {
    const sourceDir = resolveTokamakCliResourceDir(relativeDirectory);
    if (!fs.existsSync(sourceDir)) {
      continue;
    }

    const targetDir = path.join(resourceRoot, relativeDirectory);
    fs.mkdirSync(path.dirname(targetDir), { recursive: true });
    fs.cpSync(sourceDir, targetDir, { recursive: true });
  }
}

async function runTokamakMetadataStep(exampleName, bundleSourceDir) {
  const stepDir = path.join(dappMetadataRoot, exampleName);
  cleanDir(stepDir);
  const canonicalInputs = [
    "previous_state_snapshot.json",
    "transaction.json",
    "block_info.json",
    "contract_codes.json",
  ];
  for (const fileName of canonicalInputs) {
    fs.copyFileSync(path.join(bundleSourceDir, fileName), path.join(stepDir, fileName));
  }

  run(tokamakCliInvocation.command, [...tokamakCliInvocation.args, "--synthesize", stepDir], {
    cwd: repoRoot,
    quiet: true,
    label: `metadata:${exampleName}:synthesize`,
  });
  assertTokamakSetupArtifactsInstalled();
  run(tokamakCliInvocation.command, [...tokamakCliInvocation.args, "--preprocess"], {
    cwd: repoRoot,
    quiet: true,
    label: `metadata:${exampleName}:preprocess`,
  });
  copyTokamakArtifacts(stepDir);

  // Some Tokamak CLI paths mutate or prune step-local inputs while materializing outputs.
  // Rewrite the canonical inputs after artifact copy so downstream metadata derivation is stable.
  for (const fileName of canonicalInputs) {
    fs.copyFileSync(path.join(bundleSourceDir, fileName), path.join(stepDir, fileName));
  }

  const nextSnapshot = readJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.json"));
  if (Array.isArray(nextSnapshot.storageAddresses)) {
    nextSnapshot.storageAddresses = nextSnapshot.storageAddresses
      .map((address) => createAddressFromString(address).toString());
  }
  writeJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"), nextSnapshot);

  return {
    nextSnapshot,
  };
}

async function materializeRegistrationLaunchBundles(provider, participants) {
  const privateStateArtifactDir = latestPrivateStateArtifactDir();
  const appDeployment = readJson(path.join(privateStateArtifactDir, "deployment.31337.latest.json"));
  const controllerAddress = getAddress(appDeployment.contracts.controller);
  const vaultAddress = getAddress(appDeployment.contracts.l2AccountingVault);
  const liquidBalancesSlot = loadLiquidBalancesSlot();
  const blockInfo = await getFixedBlockInfo(provider);
  const contractCodes = await fetchContractCodes(provider, [controllerAddress, vaultAddress]);
  const chainId = 31337;
  const channelId = deriveChannelIdFromName(channelName);

  const participantA = registrationParticipantAt(participants, 0);
  const participantB = registrationParticipantAt(participants, 1);
  const participantC = registrationParticipantAt(participants, 2);
  const participantVaultKeys = new Map();
  for (const participant of participants) {
    participantVaultKeys.set(
      participant.alias,
      deriveLiquidBalanceStorageKey(participant.registration.l2Identity.l2Address, liquidBalancesSlot),
    );
  }

  const initialSnapshot = await initializePrivateStateSnapshot({ controllerAddress, vaultAddress, channelId });
  const depositStateManager = await buildStateManager(initialSnapshot, contractCodes);

  for (const participant of participants) {
    participant.noteReceive = participant.registration.noteReceive;
  }

  let postDepositSnapshot = initialSnapshot;
  for (const participant of participants) {
    const transition = await buildGrothTransition(
      `registration-deposit-${participant.alias}`,
      depositStateManager,
      vaultAddress,
      participantVaultKeys.get(participant.alias),
      depositAmountBaseUnits,
    );
    postDepositSnapshot = transition.nextSnapshot;
  }
  if (Array.isArray(postDepositSnapshot.storageAddresses)) {
    postDepositSnapshot.storageAddresses = postDepositSnapshot.storageAddresses
      .map((address) => createAddressFromString(address).toString());
  }

  const encryptedMints = {
    aMint: buildEncryptedMintOutput({
      owner: participantA.registration.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantA.noteReceive.noteReceivePubKey,
      value: depositAmountBaseUnits,
      label: "cli-e2e:a-mint",
      chainId,
      channelId,
    }),
    bMint: buildEncryptedMintOutput({
      owner: participantB.registration.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantB.noteReceive.noteReceivePubKey,
      value: depositAmountBaseUnits,
      label: "cli-e2e:b-mint",
      chainId,
      channelId,
    }),
    cMint: buildEncryptedMintOutput({
      owner: participantC.registration.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantC.noteReceive.noteReceivePubKey,
      value: depositAmountBaseUnits,
      label: "cli-e2e:c-mint",
      chainId,
      channelId,
    }),
    aMintSplit1: buildEncryptedMintOutput({
      owner: participantA.registration.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantA.noteReceive.noteReceivePubKey,
      value: 1n * amountUnit,
      label: "cli-e2e:a-mint-split-1",
      chainId,
      channelId,
    }),
    aMintSplit2: buildEncryptedMintOutput({
      owner: participantA.registration.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantA.noteReceive.noteReceivePubKey,
      value: 2n * amountUnit,
      label: "cli-e2e:a-mint-split-2",
      chainId,
      channelId,
    }),
  };

  const encryptedTransfers = {
    aToBOne: buildEncryptedTransferOutput({
      owner: participantB.registration.l2Identity.l2Address,
      value: 1n * amountUnit,
      label: "cli-e2e:a-to-b-1",
      recipientNoteReceivePubKey: participantB.noteReceive.noteReceivePubKey,
      chainId,
      channelId,
    }),
    aToBThree: buildEncryptedTransferOutput({
      owner: participantB.registration.l2Identity.l2Address,
      value: 3n * amountUnit,
      label: "cli-e2e:a-to-b-3",
      recipientNoteReceivePubKey: participantB.noteReceive.noteReceivePubKey,
      chainId,
      channelId,
    }),
    aToC: buildEncryptedTransferOutput({
      owner: participantC.registration.l2Identity.l2Address,
      value: 2n * amountUnit,
      label: "cli-e2e:a-to-c",
      recipientNoteReceivePubKey: participantC.noteReceive.noteReceivePubKey,
      chainId,
      channelId,
    }),
    bToC: buildEncryptedTransferOutput({
      owner: participantC.registration.l2Identity.l2Address,
      value: 4n * amountUnit,
      label: "cli-e2e:b-to-c",
      recipientNoteReceivePubKey: participantC.noteReceive.noteReceivePubKey,
      chainId,
      channelId,
    }),
  };

  const notes = {
    aMint: encryptedMints.aMint.note,
    bMint: encryptedMints.bMint.note,
    cMint: encryptedMints.cMint.note,
    aToBOne: encryptedTransfers.aToBOne.note,
    aToC: encryptedTransfers.aToC.note,
    bToC: encryptedTransfers.bToC.note,
  };

  async function materializeExample({
    exampleName,
    previousSnapshot,
    sender,
    calldata,
    nonce = 0,
    register = true,
  }) {
    const transaction = buildTokamakTxSnapshot({
      signerPrivateKey: sender.registration.l2Identity.l2PrivateKey,
      senderPubKey: sender.registration.l2Identity.l2PublicKey,
      to: controllerAddress,
      data: calldata,
      nonce,
    });
    const bundleDir = writeRegistrationLaunchBundle(
      exampleName,
      previousSnapshot,
      transaction,
      blockInfo,
      contractCodes,
      { register },
    );
    return runTokamakMetadataStep(exampleName, bundleDir);
  }

  const mintNotes1 = await materializeExample({
    exampleName: "mintNotes1",
    previousSnapshot: postDepositSnapshot,
    sender: participantA,
    calldata: buildMintInterface(1).encodeFunctionData("mintNotes1", [[[
      encryptedMints.aMint.output.value,
      encryptedMints.aMint.output.encryptedNoteValue,
    ]]]),
  });

  const mintNotes2 = await materializeExample({
    exampleName: "mintNotes2",
    previousSnapshot: postDepositSnapshot,
    sender: participantA,
    calldata: buildMintInterface(2).encodeFunctionData("mintNotes2", [[
      [encryptedMints.aMintSplit1.output.value, encryptedMints.aMintSplit1.output.encryptedNoteValue],
      [encryptedMints.aMintSplit2.output.value, encryptedMints.aMintSplit2.output.encryptedNoteValue],
    ]]),
  });

  const transferNotes1To1 = await materializeExample({
    exampleName: "transferNotes1To1",
    previousSnapshot: mintNotes1.nextSnapshot,
    sender: participantA,
    calldata: buildTransferInterface(1, 1).encodeFunctionData("transferNotes1To1", [[
      [
        encryptedTransfers.aToBThree.output.owner,
        encryptedTransfers.aToBThree.output.value,
        encryptedTransfers.aToBThree.output.encryptedNoteValue,
      ],
    ], [[
      notes.aMint.owner,
      notes.aMint.value,
      notes.aMint.salt,
    ]]]),
  });

  const internalMintB = await materializeExample({
    exampleName: "_internal-mint-b",
    previousSnapshot: mintNotes1.nextSnapshot,
    sender: participantB,
    calldata: buildMintInterface(1).encodeFunctionData("mintNotes1", [[[
      encryptedMints.bMint.output.value,
      encryptedMints.bMint.output.encryptedNoteValue,
    ]]]),
    register: false,
  });

  const internalMintC = await materializeExample({
    exampleName: "_internal-mint-c",
    previousSnapshot: internalMintB.nextSnapshot,
    sender: participantC,
    calldata: buildMintInterface(1).encodeFunctionData("mintNotes1", [[[
      encryptedMints.cMint.output.value,
      encryptedMints.cMint.output.encryptedNoteValue,
    ]]]),
    register: false,
  });

  const transferNotes1To2 = await materializeExample({
    exampleName: "transferNotes1To2",
    previousSnapshot: internalMintC.nextSnapshot,
    sender: participantA,
    calldata: buildTransferInterface(1, 2).encodeFunctionData("transferNotes1To2", [[
      [
        encryptedTransfers.aToBOne.output.owner,
        encryptedTransfers.aToBOne.output.value,
        encryptedTransfers.aToBOne.output.encryptedNoteValue,
      ],
      [
        encryptedTransfers.aToC.output.owner,
        encryptedTransfers.aToC.output.value,
        encryptedTransfers.aToC.output.encryptedNoteValue,
      ],
    ], [[
      notes.aMint.owner,
      notes.aMint.value,
      notes.aMint.salt,
    ]]]),
  });

  const transferNotes2To1 = await materializeExample({
    exampleName: "transferNotes2To1",
    previousSnapshot: transferNotes1To2.nextSnapshot,
    sender: participantB,
    calldata: buildTransferInterface(2, 1).encodeFunctionData("transferNotes2To1", [[
      [
        encryptedTransfers.bToC.output.owner,
        encryptedTransfers.bToC.output.value,
        encryptedTransfers.bToC.output.encryptedNoteValue,
      ],
    ], [
      [
        notes.bMint.owner,
        notes.bMint.value,
        notes.bMint.salt,
      ],
      [
        notes.aToBOne.owner,
        notes.aToBOne.value,
        notes.aToBOne.salt,
      ],
    ]]),
  });

  await materializeExample({
    exampleName: "redeemNotes1",
    previousSnapshot: transferNotes2To1.nextSnapshot,
    sender: participantC,
    calldata: buildRedeemInterface(1).encodeFunctionData("redeemNotes1", [[[
      notes.aToC.owner,
      notes.aToC.value,
      notes.aToC.salt,
    ]], participantC.registration.l2Identity.l2Address]),
  });
  return localRegistrationExamples;
}

function runPrivateStateCli(args, options = {}) {
  expect(
    fs.existsSync(cliBinPath),
    `Missing npm-installed private-state-cli binary: ${cliBinPath}`,
  );
  return runJsonCommand(cliBinPath, args, {
    ...options,
    cwd: options.cwd ?? cliInstallRoot,
    label: options.label ?? `private-state-cli:${args[0] ?? "unknown"}`,
    quiet: options.quiet ?? true,
  });
}

function installPrivateStateCliRuntimeForE2E() {
  return run(cliBinPath, ["install", "--include-local-artifacts"], {
    // Local anvil artifacts are generated under the repository deployment/ tree during bootstrap.
    cwd: repoRoot,
    label: "private-state-cli:install",
    quiet: true,
  });
}

function deriveParticipant(index, alias) {
  const wallet = HDNodeWallet.fromPhrase(anvilMnemonic, undefined, `m/44'/60'/0'/0/${index}`);
  return {
    alias,
    walletSecret: alias,
    walletSecretSeed: alias,
    l1Address: getAddress(wallet.address),
    l1PrivateKey: wallet.privateKey,
    walletName: null,
    walletSecretPath: null,
    l2Address: null,
    registration: null,
  };
}

async function deriveRegistrationCandidate({ participant, provider, walletSecret, liquidBalancesSlot }) {
  const signer = new Wallet(participant.l1PrivateKey, provider);
  const l2Identity = await deriveParticipantIdentityFromSigner({
    channelName,
    walletSecret,
    signer,
  });
  const noteReceive = await deriveNoteReceiveKeyMaterial({
    signer,
    chainId: 31337,
    channelId: deriveChannelIdFromName(channelName),
    channelName,
    account: participant.l1Address,
  });
  const storageKey = normalizeBytes32Hex(deriveLiquidBalanceStorageKey(l2Identity.l2Address, liquidBalancesSlot));
  const leafIndex = deriveChannelTokenVaultLeafIndex(storageKey);
  return {
    walletSecret,
    l2Identity,
    noteReceive,
    storageKey,
    leafIndex,
  };
}

async function resolveParticipantRegistrations(provider, participants) {
  const liquidBalancesSlot = loadLiquidBalancesSlot();
  const usedL2Addresses = new Set();
  const usedStorageKeys = new Set();
  const usedLeafIndices = new Set();

  for (const participant of participants) {
    let resolved = null;
    for (let attempt = 0; attempt < 64; attempt += 1) {
      const walletSecret = attempt === 0
        ? participant.walletSecretSeed
        : `${participant.walletSecretSeed}-retry-${attempt}`;
      const candidate = await deriveRegistrationCandidate({
        participant,
        provider,
        walletSecret,
        liquidBalancesSlot,
      });
      const l2AddressKey = getAddress(candidate.l2Identity.l2Address).toLowerCase();
      const storageKey = normalizeBytes32Hex(candidate.storageKey);
      const leafIndexKey = candidate.leafIndex.toString();
      if (usedL2Addresses.has(l2AddressKey) || usedStorageKeys.has(storageKey) || usedLeafIndices.has(leafIndexKey)) {
        continue;
      }
      usedL2Addresses.add(l2AddressKey);
      usedStorageKeys.add(storageKey);
      usedLeafIndices.add(leafIndexKey);
      resolved = {
        ...candidate,
        attempts: attempt + 1,
      };
      break;
    }
    expect(
      resolved !== null,
      `Failed to resolve a collision-free join-channel wallet secret for ${participant.alias} within 64 attempts.`,
    );
    participant.walletSecret = resolved.walletSecret;
    participant.registration = resolved;
  }
}

function walletDirForName(walletName) {
  const workspaceDir = workspaceDirForName(workspaceRoot, workspaceNetworkName, channelName);
  const walletsRoot = workspaceWalletsDir(workspaceDir);
  return walletDirForNameInRoot(walletsRoot, walletName);
}

function privateKeyInputPath(accountName) {
  return path.join(outputRoot, "secret-inputs", `${slugifyPathComponent(accountName)}.private-key`);
}

function walletSecretInputPath(walletName) {
  return path.join(outputRoot, "secret-inputs", `${slugifyPathComponent(walletName)}.wallet-secret`);
}

function removeAnvilAccountSecret(accountName) {
  fs.rmSync(path.join(
    secretRoot,
    workspaceNetworkName,
    "accounts",
    slugifyPathComponent(accountName),
  ), { recursive: true, force: true });
}

function removeAnvilWalletSecret(walletName) {
  fs.rmSync(path.join(
    secretRoot,
    workspaceNetworkName,
    "wallets",
    slugifyPathComponent(walletName),
  ), { recursive: true, force: true });
}

function prepareAccountSecret(accountName, privateKey) {
  removeAnvilAccountSecret(accountName);
  const inputPath = privateKeyInputPath(accountName);
  writeSecretFile(inputPath, privateKey);
  return runAnvilCliCommand("account", [
    "import",
    "--account", accountName,
    "--private-key-file", inputPath,
  ]);
}

function prepareWalletSecretSource(participant) {
  expect(participant.walletName, `${participant.alias} walletName is not available.`);
  participant.walletSecretPath = walletSecretInputPath(participant.walletName);
  writeSecretFile(participant.walletSecretPath, participant.walletSecret);
}

function prepareCliSecrets(participants) {
  prepareAccountSecret(txSubmitterAccount, anvilDeployerPrivateKey);
  for (const participant of participants) {
    participant.walletName = walletNameForChannelAndAddress(channelName, participant.l1Address);
    removeAnvilWalletSecret(participant.walletName);
    prepareAccountSecret(participant.alias, participant.l1PrivateKey);
    prepareWalletSecretSource(participant);
  }
}

function assertBigIntEq(actual, expected, label) {
  expect(
    ethers.toBigInt(actual) === ethers.toBigInt(expected),
    `${label} mismatch. Expected ${expected.toString()}, got ${actual.toString()}.`,
  );
}

function removeCliRunState() {
  cleanDir(outputRoot);
  fs.rmSync(workspaceDirForName(workspaceRoot, workspaceNetworkName, channelName), { recursive: true, force: true });
}

function pruneCliRunOutput() {
  if (!fs.existsSync(outputRoot)) {
    return;
  }
  for (const entry of fs.readdirSync(outputRoot, { withFileTypes: true })) {
    if (entry.name === path.basename(summaryPath)) {
      continue;
    }
    fs.rmSync(path.join(outputRoot, entry.name), { recursive: true, force: true });
  }
}

function collectOperationDiagnostics(operationsRoot) {
  if (!fs.existsSync(operationsRoot)) {
    return [];
  }

  return fs.readdirSync(operationsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const operationDir = path.join(operationsRoot, entry.name);
      const stats = fs.statSync(operationDir);
      const tokamakLogsDir = path.join(operationDir, "tokamak-cli-logs");
      const tokamakLogs = fs.existsSync(tokamakLogsDir)
        ? fs.readdirSync(tokamakLogsDir, { withFileTypes: true })
          .filter((logEntry) => logEntry.isFile())
          .map((logEntry) => path.join(tokamakLogsDir, logEntry.name))
          .sort()
        : [];
      return {
        operationDir,
        modifiedAt: stats.mtime.toISOString(),
        transactionPath: fs.existsSync(path.join(operationDir, "transaction.json"))
          ? path.join(operationDir, "transaction.json")
          : null,
        previousStateSnapshotPath: fs.existsSync(path.join(operationDir, "previous_state_snapshot.json"))
          ? path.join(operationDir, "previous_state_snapshot.json")
          : null,
        tokamakLogs,
      };
    })
    .sort((left, right) => right.modifiedAt.localeCompare(left.modifiedAt));
}

function extractReferencedPaths(text) {
  const matches = String(text ?? "").match(/\/[^\s:]+(?:\.[A-Za-z0-9_-]+)?/g) ?? [];
  return [...new Set(matches)].filter((candidate) => fs.existsSync(candidate));
}

function writeFailureDiagnostics(error) {
  const workspaceDir = workspaceDirForName(workspaceRoot, workspaceNetworkName, channelName);
  const channelOperationsRoot = path.join(workspaceDir, "channel", "operations");
  const walletsRoot = path.join(workspaceDir, "wallets");
  const walletDiagnostics = fs.existsSync(walletsRoot)
    ? fs.readdirSync(walletsRoot, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => ({
        walletDir: path.join(walletsRoot, entry.name),
        operations: collectOperationDiagnostics(path.join(walletsRoot, entry.name, "operations")),
      }))
    : [];

  const stack = error instanceof Error ? error.stack ?? error.message : String(error);
  const referencedPaths = extractReferencedPaths(stack);
  const referencedFiles = referencedPaths.map((filePath) => ({
    path: filePath,
    exists: true,
    preview: fs.statSync(filePath).isFile()
      ? fs.readFileSync(filePath, "utf8").slice(0, 4000)
      : null,
  }));

  writeJson(failureDiagnosticsPath, {
    channelName,
    workspaceDir,
    outputRoot,
    errorMessage: error instanceof Error ? error.message : String(error),
    stack,
    summaryPresent: fs.existsSync(summaryPath),
    summary: readJsonIfExists(summaryPath),
    channelOperations: collectOperationDiagnostics(channelOperationsRoot),
    wallets: walletDiagnostics,
    referencedFiles,
  });
  console.error(`E2E CLI failure diagnostics written to ${failureDiagnosticsPath}`);
}

function bootstrapAnvil() {
  run("make", ["-C", appRoot, "anvil-stop"], { quiet: true, label: "anvil:stop" });
  run("make", ["-C", appRoot, "anvil-start"], { quiet: true, label: "anvil:start" });
  deployPrivateStateForCliE2E();
}

function deployPrivateStateForCliE2E() {
  run(
    "forge",
    [
      "script",
      privateStateDeployScriptPath,
      "--rpc-url", providerUrl,
      "--broadcast",
    ],
    {
      cwd: repoRoot,
      quiet: true,
      label: "private-state:forge-deploy",
      env: {
        ...process.env,
        APPS_DEPLOYER_PRIVATE_KEY: anvilDeployerPrivateKey,
      },
    },
  );
  run("node", [privateStateArtifactWriterPath, "31337"], {
    cwd: repoRoot,
    quiet: true,
    label: "private-state:write-deploy-artifacts",
  });
}

function deployBridgeStack() {
  writeJsonLikeEnv(bridgeEnvPath, {
    BRIDGE_DEPLOYER_PRIVATE_KEY: anvilDeployerPrivateKey,
    BRIDGE_RPC_URL_OVERRIDE: providerUrl,
  });

  const env = {
    ...process.env,
    BRIDGE_ENV_FILE: bridgeEnvPath,
    BRIDGE_SKIP_TOKAMAK_INSTALL: "1",
    BRIDGE_DEPLOY_MOCK_ASSET: "true",
  };

  if (!currentCliE2EOptions.runGrothSetup) {
    env.BRIDGE_SKIP_GROTH_REFRESH = "1";
  }

  run(
    "node",
    [
      bridgeDeployHelperPath,
      "--network",
      "anvil",
      "--mode",
      "redeploy-proxy",
    ],
    { env, quiet: true, label: "bridge:redeploy-proxy" },
  );

  return readJson(latestBridgeDeploymentPath());
}

function writeJsonLikeEnv(filePath, entries) {
  const lines = Object.entries(entries).map(([key, value]) => `${key}=${value}`);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${lines.join("\n")}\n`);
}

function getCanonicalAssetAddress(bridgeCoreAddress) {
  return run(
    "cast",
    ["call", bridgeCoreAddress, "canonicalAsset()(address)", "--rpc-url", providerUrl],
    { captureStdout: true, label: "bridge:read-canonical-asset" },
  ).trim();
}

function prepareCanonicalAsset(bridgeDeployment, participants) {
  const canonicalAsset = getCanonicalAssetAddress(bridgeDeployment.bridgeCore);
  const mockAssetCode = run(
    "cast",
    ["code", bridgeDeployment.mockAsset, "--rpc-url", providerUrl],
    { captureStdout: true, label: "bridge:read-mock-asset-code" },
  ).trim();

  run("cast", ["rpc", "anvil_setCode", canonicalAsset, mockAssetCode, "--rpc-url", providerUrl], {
    quiet: true,
    label: "bridge:install-canonical-asset-code",
  });

  for (const participant of participants) {
    run(
      "cast",
      [
        "send",
        canonicalAsset,
        "mint(address,uint256)",
        participant.l1Address,
        (depositAmountBaseUnits + joinTollBaseUnits).toString(),
        "--private-key",
        anvilDeployerPrivateKey,
        "--rpc-url",
        providerUrl,
      ],
      { quiet: true, label: `bridge:mint-canonical-asset:${participant.alias}` },
    );
  }

  return canonicalAsset;
}

async function registerPrivateStateDApp(provider, bridgeDeployment, participants) {
  await materializeRegistrationLaunchBundles(provider, participants);
  const privateStateArtifactDir = latestPrivateStateArtifactDir();
  const registrationManifestPath = path.join(privateStateArtifactDir, "dapp-registration.31337.json");

  run(
    "node",
    [
      adminAddDAppPath,
      "--group",
      dappLabel,
      "--dapp-id",
      dappId,
      "--network",
      "anvil",
      "--deployment-path",
      latestBridgeDeploymentPath(),
      "--dapp-manager",
      bridgeDeployment.dAppManager,
      "--app-network",
      "anvil",
      "--app-deployment-path",
      path.join(privateStateArtifactDir, "deployment.31337.latest.json"),
      "--storage-layout-path",
      path.join(privateStateArtifactDir, "storage-layout.31337.latest.json"),
      "--example-root",
      registrationLaunchInputsRoot,
      "--rpc-url",
      providerUrl,
      "--private-key",
      anvilDeployerPrivateKey,
      "--manifest-out",
      registrationManifestPath,
      "--artifacts-out",
      dappMetadataRoot,
      "--replace-existing",
    ],
    { quiet: true, label: "bridge:admin-add-dapp" },
  );

  const manifest = readJson(registrationManifestPath);
  writeJson(path.join(outputRoot, "dapp-registration.json"), manifest);
  const registration = manifest.registration ?? {};
  const result = {
    reusedExistingRegistration: false,
    txHash: registration.txHash,
    blockNumber: registration.blockNumber ?? null,
    storageCount: registration.storageCount,
    functionCount: registration.functionCount,
    artifactsRoot: dappMetadataRoot,
    registrationManifestPath,
  };
  return result;
}

function readErc20Balance(assetAddress, ownerAddress) {
  const output = run(
    "cast",
    ["call", assetAddress, "balanceOf(address)(uint256)", ownerAddress, "--rpc-url", providerUrl],
    { captureStdout: true, label: `erc20:balanceOf:${ownerAddress}` },
  ).trim();
  const normalized = output.split(/\s+/)[0];
  return ethers.toBigInt(normalized);
}

function runAnvilCliCommand(command, args = []) {
  return runPrivateStateCli([command, "--network", "anvil", ...args]);
}

function runAnvilBridgeCliCommand(command, args = []) {
  return runPrivateStateCli([command, "--network", "anvil", "--rpc-url", providerUrl, ...args]);
}

function walletCliArgs(participant) {
  return [
    "--wallet", participant.walletName,
  ];
}

function signerCliArgs(participant) {
  return [
    "--account", participant.alias,
  ];
}

function createChannel() {
  return runAnvilBridgeCliCommand("create-channel", [
    "--channel-name", channelName,
    "--join-toll", joinTollTokens,
    "--account", txSubmitterAccount,
  ]);
}

function depositBridge(participant) {
  return runAnvilBridgeCliCommand("deposit-bridge", [
    ...signerCliArgs(participant),
    "--amount", depositAmountTokens,
  ]);
}

function joinChannel(participant) {
  const result = runAnvilBridgeCliCommand("join-channel", [
    "--channel-name", channelName,
    ...signerCliArgs(participant),
    "--wallet-secret-path", participant.walletSecretPath,
  ]);
  participant.walletName = result.wallet;
  participant.l2Address = result.l2Address;
  if (participant.registration !== null) {
    assertResolvedWalletIdentity(result, participant, `${participant.alias} join-channel`);
  }
  expect(
    result.wallet === walletNameForChannelAndAddress(channelName, result.l1Address),
    `join-channel returned unexpected wallet name ${result.wallet}.`,
  );
  return result;
}

function recoverWallet(participant) {
  const result = runAnvilBridgeCliCommand("recover-wallet", [
    "--channel-name", channelName,
    ...signerCliArgs(participant),
  ]);
  participant.walletName = result.wallet;
  participant.l2Address = result.l2Address;
  return result;
}

function getMyWalletMeta(participant) {
  return runAnvilCliCommand("get-my-wallet-meta", walletCliArgs(participant));
}

function getMyL1Address(participant) {
  return runPrivateStateCli([
    "get-my-l1-address",
    "--network", workspaceNetworkName,
    ...signerCliArgs(participant),
  ]);
}

function listLocalWallets(args = []) {
  return runPrivateStateCli(["list-local-wallets", ...args]);
}

function getMyBridgeFund(participant) {
  return runAnvilBridgeCliCommand("get-my-bridge-fund", signerCliArgs(participant));
}

function depositChannel(participant) {
  return runAnvilCliCommand("deposit-channel", [
    ...walletCliArgs(participant),
    "--amount", depositAmountTokens,
  ]);
}

function getMyChannelFund(participant) {
  return runAnvilCliCommand("get-my-channel-fund", walletCliArgs(participant));
}

function recoverWorkspace() {
  return runAnvilBridgeCliCommand("recover-workspace", [
    "--channel-name", channelName,
  ]);
}

function deleteWalletDir(participant) {
  expect(participant.walletName, `${participant.alias} walletName is not available.`);
  fs.rmSync(walletDirForName(participant.walletName), { recursive: true, force: true });
}

function deleteWorkspaceDir() {
  fs.rmSync(workspaceDirForName(workspaceRoot, workspaceNetworkName, channelName), {
    recursive: true,
    force: true,
  });
}

function txSubmitterCliArgs(account) {
  return account ? ["--tx-submitter", account] : [];
}

function mintNotes(participant, amounts, { txSubmitter = null } = {}) {
  return runAnvilCliCommand("mint-notes", [
    ...walletCliArgs(participant),
    "--amounts", JSON.stringify(amounts),
    ...txSubmitterCliArgs(txSubmitter),
  ]);
}

function getMyNotes(participant) {
  return runAnvilCliCommand("get-my-notes", walletCliArgs(participant));
}

function transferNotes(participant, noteIds, recipients, amounts, { txSubmitter = null } = {}) {
  return runAnvilCliCommand("transfer-notes", [
    ...walletCliArgs(participant),
    "--note-ids", JSON.stringify(noteIds),
    "--recipients", JSON.stringify(recipients),
    "--amounts", JSON.stringify(amounts),
    ...txSubmitterCliArgs(txSubmitter),
  ]);
}

function redeemNotes(participant, noteIds, { txSubmitter = null } = {}) {
  return runAnvilCliCommand("redeem-notes", [
    ...walletCliArgs(participant),
    "--note-ids", JSON.stringify(noteIds),
    ...txSubmitterCliArgs(txSubmitter),
  ]);
}

function withdrawChannel(participant, amount) {
  return runAnvilCliCommand("withdraw-channel", [
    ...walletCliArgs(participant),
    "--amount", amount,
  ]);
}

function withdrawBridge(participant, amount) {
  return runAnvilBridgeCliCommand("withdraw-bridge", [
    ...signerCliArgs(participant),
    "--amount", amount,
  ]);
}

function exitChannel(participant) {
  return runAnvilCliCommand("exit-channel", walletCliArgs(participant));
}

function assertResolvedWalletIdentity(result, participant, label) {
  expect(
    ethers.toBigInt(getAddress(result.l2Address))
      === ethers.toBigInt(getAddress(participant.registration.l2Identity.l2Address)),
    `${label} returned an unexpected L2 address.`,
  );
  expect(
    ethers.toBigInt(normalizeBytes32Hex(result.l2StorageKey))
      === ethers.toBigInt(normalizeBytes32Hex(participant.registration.storageKey)),
    `${label} returned an unexpected storage key.`,
  );
  expect(
    ethers.toBigInt(result.leafIndex) === ethers.toBigInt(participant.registration.leafIndex),
    `${label} returned an unexpected leaf index.`,
  );
}

function pickOutputNoteByOwner(outputNotes, ownerAddress, expectedValue) {
  const owner = getAddress(ownerAddress);
  const expected = ethers.toBigInt(expectedValue).toString();
  const matches = outputNotes.filter((note) => (
    ethers.toBigInt(getAddress(note.owner)) === ethers.toBigInt(owner)
      && ethers.toBigInt(note.value) === ethers.toBigInt(expected)
  ));
  expect(
    matches.length === 1,
    `Expected exactly one output note for ${owner} with value ${expected}, found ${matches.length}.`,
  );
  return matches[0];
}

function assertWalletNoteSnapshot(noteSnapshot, { unusedCount, spentCount, unusedTotal, spentTotal }) {
  expect(noteSnapshot.unusedNotes.length === unusedCount, `Unexpected unused note count for ${noteSnapshot.wallet}.`);
  expect(noteSnapshot.spentNotes.length === spentCount, `Unexpected spent note count for ${noteSnapshot.wallet}.`);
  assertBigIntEq(noteSnapshot.unusedTotalBaseUnits, unusedTotal, `${noteSnapshot.wallet} unused total`);
  assertBigIntEq(noteSnapshot.spentTotalBaseUnits, spentTotal, `${noteSnapshot.wallet} spent total`);
  expect(
    Number(noteSnapshot.bridgeStatusMismatches) === 0,
    `${noteSnapshot.wallet} has bridgeStatusMismatches=${noteSnapshot.bridgeStatusMismatches}.`,
  );
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  currentCliE2EOptions = options;
  if (options.runInstall) {
    run(tokamakCliInvocation.command, [...tokamakCliInvocation.args, "--install"], {
      cwd: repoRoot,
      quiet: true,
      label: "tokamak:install",
    });
  }
  const provider = new JsonRpcProvider(providerUrl);
  const participants = [
    deriveParticipant(1, "participant-a"),
    deriveParticipant(2, "participant-b"),
    deriveParticipant(3, "participant-c"),
  ];

  removeCliRunState();

  let createChannelResult = null;
  let recoverWorkspaceResult = null;
  let bridgeDeployment = null;
  let canonicalAsset = null;
  let dappRegistrationResult = null;
  let cliPackageInstall = null;
  const commandResults = {
    participants: {},
  };

  try {
    cliPackageInstall = installPrivateStateCliPackageForE2E();
    console.log("E2E CLI: bootstrapping anvil and local deployments.");
    bootstrapAnvil();
    await resolveParticipantRegistrations(provider, participants);
    prepareCliSecrets(participants);
    bridgeDeployment = deployBridgeStack();
    canonicalAsset = prepareCanonicalAsset(bridgeDeployment, participants);
    dappRegistrationResult = await registerPrivateStateDApp(provider, bridgeDeployment, participants);
    if (options.runInstall) {
      installPrivateStateCliRuntimeForE2E();
    }

    createChannelResult = createChannel();

    for (const participant of participants) {
      const participantResults = {};
      participantResults.depositBridge = depositBridge(participant);
      participantResults.joinChannel = joinChannel(participant);
      if (participant.alias === "participant-a") {
        deleteWalletDir(participant);
        participantResults.recoverWallet = recoverWallet(participant);
        expect(
          participantResults.recoverWallet.status === "recovered",
          "recover-wallet must rebuild a deleted wallet directory.",
        );
        expect(
          participantResults.recoverWallet.wallet === participant.walletName,
          "recover-wallet returned an unexpected wallet name.",
        );
        assertResolvedWalletIdentity(participantResults.recoverWallet, participant, "recover-wallet");
        expect(
          Number(participantResults.recoverWallet.l2Nonce) === 0,
          "recover-wallet must reset l2Nonce to 0.",
        );

        participantResults.recoverWalletNoop = recoverWallet(participant);
        expect(
          participantResults.recoverWalletNoop.status === "already-recovered",
          "recover-wallet must stop when the existing wallet is already valid.",
        );
      }
      participantResults.getMyWalletMeta = getMyWalletMeta(participant);
      participantResults.getMyL1Address = getMyL1Address(participant);
      participantResults.depositChannel = depositChannel(participant);
      participantResults.getMyChannelFund = getMyChannelFund(participant);
      participantResults.getMyBridgeFund = getMyBridgeFund(participant);

      expect(
        String(participantResults.getMyWalletMeta.registeredL2Address).toLowerCase()
          === String(participantResults.joinChannel.l2Address).toLowerCase(),
        `${participant.alias} registered L2 address mismatch.`,
      );
      expect(
        participantResults.getMyWalletMeta.registrationExists === true
          && participantResults.getMyWalletMeta.matchesWallet === true,
        `${participant.alias} channel registration does not match the local wallet.`,
      );
      expect(
        participantResults.getMyWalletMeta.wallet === participant.walletName,
        `${participant.alias} wallet metadata returned an unexpected wallet name.`,
      );
      expect(
        getAddress(participantResults.getMyWalletMeta.l1Address) === getAddress(participant.l1Address),
        `${participant.alias} wallet metadata returned an unexpected L1 address.`,
      );
      expect(
        getAddress(participantResults.getMyWalletMeta.walletL2Address) === getAddress(participant.l2Address),
        `${participant.alias} wallet metadata returned an unexpected wallet L2 address.`,
      );
      expect(
        getAddress(participantResults.getMyL1Address.l1Address) === getAddress(participant.l1Address),
        `${participant.alias} get-my-l1-address returned an unexpected L1 address.`,
      );
      assertBigIntEq(
        participantResults.getMyChannelFund.channelDepositBaseUnits,
        depositAmountBaseUnits,
        `${participant.alias} channel deposit`,
      );
      assertBigIntEq(
        participantResults.getMyBridgeFund.availableBalanceBaseUnits,
        0n,
        `${participant.alias} bridge deposit after deposit-channel`,
      );

      commandResults.participants[participant.alias] = participantResults;
    }

    const localWalletList = listLocalWallets([
      "--network", workspaceNetworkName,
      "--channel-name", channelName,
    ]);
    const listedWallets = new Set(localWalletList.wallets.map((wallet) => wallet.wallet.toLowerCase()));
    for (const participant of participants) {
      expect(
        listedWallets.has(participant.walletName.toLowerCase()),
        `list-local-wallets did not include ${participant.walletName}.`,
      );
    }

    recoverWorkspaceResult = recoverWorkspace();

    const mintA = mintNotes(participants[0], [3], { txSubmitter: txSubmitterAccount });
    const mintB = mintNotes(participants[1], [3]);
    const mintC = mintNotes(participants[2], [3]);
    expect(
      getAddress(mintA.l1Submitter) === txSubmitterAddress,
      "mint-notes --tx-submitter must submit with the requested local account.",
    );
    expect(
      getAddress(mintA.l1WalletOwner) === getAddress(participants[0].l1Address),
      "mint-notes --tx-submitter must not change the wallet owner.",
    );

    const aMintNote = mintA.outputNotes[0];
    const bMintNote = mintB.outputNotes[0];
    const cMintNote = mintC.outputNotes[0];

    const notesAfterMintA = getMyNotes(participants[0]);
    const notesAfterMintB = getMyNotes(participants[1]);
    const notesAfterMintC = getMyNotes(participants[2]);
    for (const noteSnapshot of [notesAfterMintA, notesAfterMintB, notesAfterMintC]) {
      assertWalletNoteSnapshot(noteSnapshot, {
        unusedCount: 1,
        spentCount: 0,
        unusedTotal: depositAmountBaseUnits,
        spentTotal: 0n,
      });
    }

    const transferA = transferNotes(
      participants[0],
      [aMintNote.commitment],
      [participants[1].l2Address, participants[2].l2Address],
      [1, 2],
      { txSubmitter: txSubmitterAccount },
    );
    expect(
      getAddress(transferA.l1Submitter) === txSubmitterAddress,
      "transfer-notes --tx-submitter must submit with the requested local account.",
    );
    expect(
      getAddress(transferA.l1WalletOwner) === getAddress(participants[0].l1Address),
      "transfer-notes --tx-submitter must not change the wallet owner.",
    );
    const noteAToB = pickOutputNoteByOwner(transferA.outputNotes, participants[1].l2Address, 1n * amountUnit);
    const noteAToC = pickOutputNoteByOwner(transferA.outputNotes, participants[2].l2Address, 2n * amountUnit);
    expect(
      Array.isArray(transferA.deliveredRecipients) && transferA.deliveredRecipients.length === 0,
      "transfer-notes must not write recipient inbox sidecars anymore.",
    );
    const notesAfterTransferALogScanB = getMyNotes(participants[1]);
    const notesAfterTransferALogScanC = getMyNotes(participants[2]);
    assertWalletNoteSnapshot(notesAfterTransferALogScanB, { unusedCount: 2, spentCount: 0, unusedTotal: 4n * amountUnit, spentTotal: 0n });
    assertWalletNoteSnapshot(notesAfterTransferALogScanC, { unusedCount: 2, spentCount: 0, unusedTotal: 5n * amountUnit, spentTotal: 0n });

    const transferB = transferNotes(
      participants[1],
      [bMintNote.commitment, noteAToB.commitment],
      [participants[2].l2Address],
      [4],
    );
    const noteBToC = pickOutputNoteByOwner(transferB.outputNotes, participants[2].l2Address, 4n * amountUnit);
    expect(
      Array.isArray(transferB.deliveredRecipients) && transferB.deliveredRecipients.length === 0,
      "transfer-notes must not write recipient inbox sidecars anymore.",
    );

    const notesAfterTransferA = getMyNotes(participants[0]);
    const notesAfterTransferB = getMyNotes(participants[1]);
    const notesAfterTransferC = getMyNotes(participants[2]);
    assertWalletNoteSnapshot(notesAfterTransferA, { unusedCount: 0, spentCount: 1, unusedTotal: 0n, spentTotal: depositAmountBaseUnits });
    assertWalletNoteSnapshot(notesAfterTransferB, { unusedCount: 0, spentCount: 2, unusedTotal: 0n, spentTotal: 4n * amountUnit });
    assertWalletNoteSnapshot(notesAfterTransferC, { unusedCount: 3, spentCount: 0, unusedTotal: claimAmountBaseUnits, spentTotal: 0n });

    const redeemAToC = redeemNotes(participants[2], [noteAToC.commitment], { txSubmitter: txSubmitterAccount });
    const redeemBToC = redeemNotes(participants[2], [noteBToC.commitment]);
    const redeemCMint = redeemNotes(participants[2], [cMintNote.commitment]);
    expect(
      getAddress(redeemAToC.l1Submitter) === txSubmitterAddress,
      "redeem-notes --tx-submitter must submit with the requested local account.",
    );
    expect(
      getAddress(redeemAToC.l1WalletOwner) === getAddress(participants[2].l1Address),
      "redeem-notes --tx-submitter must not change the wallet owner.",
    );
    const notesAfterRedeemC = getMyNotes(participants[2]);
    assertWalletNoteSnapshot(notesAfterRedeemC, { unusedCount: 0, spentCount: 3, unusedTotal: 0n, spentTotal: claimAmountBaseUnits });

    deleteWorkspaceDir();
    const recoverWorkspaceAfterNotesResult = recoverWorkspace();
    expect(
      recoverWorkspaceAfterNotesResult.channelName === channelName,
      "recover-workspace must rebuild the deleted workspace after note activity.",
    );
    const recoverWalletAfterWorkspaceReset = recoverWallet(participants[2]);
    expect(
      recoverWalletAfterWorkspaceReset.wallet === participants[2].walletName,
      "recover-wallet must restore participant-c after workspace recovery.",
    );

    const channelDepositBeforeWithdraw = getMyChannelFund(participants[2]);
    assertBigIntEq(
      channelDepositBeforeWithdraw.channelDepositBaseUnits,
      claimAmountBaseUnits,
      "participant-c channel deposit before withdraw",
    );

    const l1BalanceBeforeClaim = readErc20Balance(canonicalAsset, participants[2].l1Address);
    const withdrawChannelResult = withdrawChannel(participants[2], claimAmountTokens);
    const bridgeDepositAfterWithdraw = getMyBridgeFund(participants[2]);
    const channelDepositAfterWithdraw = getMyChannelFund(participants[2]);
    assertBigIntEq(
      bridgeDepositAfterWithdraw.availableBalanceBaseUnits,
      claimAmountBaseUnits,
      "participant-c bridge deposit after withdraw-channel",
    );
    assertBigIntEq(
      channelDepositAfterWithdraw.channelDepositBaseUnits,
      0n,
      "participant-c channel deposit after withdraw-channel",
    );

    const exitChannelResult = exitChannel(participants[2]);
    assertBigIntEq(
      exitChannelResult.currentUserValue,
      0n,
      "participant-c currentUserValue at exit-channel",
    );
    assertBigIntEq(
      exitChannelResult.refundAmountBaseUnits,
      (joinTollBaseUnits * 75n) / 100n,
      "participant-c exit-channel refund amount",
    );
    expect(
      Number(exitChannelResult.refundBps) === 7500,
      `participant-c exit-channel refundBps mismatch: ${exitChannelResult.refundBps}.`,
    );

    const withdrawBridgeResult = withdrawBridge(participants[2], claimAmountTokens);
    const bridgeDepositAfterClaim = getMyBridgeFund(participants[2]);
    const l1BalanceAfterClaim = readErc20Balance(canonicalAsset, participants[2].l1Address);
    assertBigIntEq(
      bridgeDepositAfterClaim.availableBalanceBaseUnits,
      0n,
      "participant-c bridge deposit after withdraw-bridge",
    );
    assertBigIntEq(
      l1BalanceAfterClaim - l1BalanceBeforeClaim,
      claimAmountBaseUnits + ((joinTollBaseUnits * 75n) / 100n),
      "participant-c L1 ERC20 claim delta including exit refund",
    );
    for (const participant of participants.slice(0, 2)) {
      assertBigIntEq(
        getMyBridgeFund(participant).availableBalanceBaseUnits,
        0n,
        `${participant.alias} final bridge deposit`,
      );
    }
    commandResults.participants[participants[2].alias].exitChannel = exitChannelResult;

    const summary = {
      providerUrl,
      channelName,
      cliPackage: cliPackageInstall,
      bridgeDeployment,
      canonicalAsset,
      dappRegistration: dappRegistrationResult,
      createChannel: createChannelResult,
      recoverWorkspace: recoverWorkspaceResult,
      recoverWorkspaceAfterNotes: recoverWorkspaceAfterNotesResult,
      localWallets: localWalletList,
      participants: participants.map((participant) => ({
        alias: participant.alias,
        wallet: participant.walletName,
        l1Address: participant.l1Address,
        l2Address: participant.l2Address,
      })),
      flow: {
        mintA,
        mintB,
        mintC,
        transferA,
        transferB,
        redeemTransferredToC: redeemAToC,
        redeemCMint,
        withdrawChannelResult,
        withdrawBridgeResult,
      },
      snapshots: {
        notesAfterMintA,
        notesAfterMintB,
        notesAfterMintC,
        notesAfterTransferA,
        notesAfterTransferB,
        notesAfterTransferC,
        notesAfterRedeemC,
        channelDepositBeforeWithdraw,
        channelDepositAfterWithdraw,
        bridgeDepositAfterWithdraw,
        bridgeDepositAfterClaim,
      },
      commandResults,
      l1Claim: {
        before: l1BalanceBeforeClaim.toString(),
        after: l1BalanceAfterClaim.toString(),
        delta: (l1BalanceAfterClaim - l1BalanceBeforeClaim).toString(),
      },
    };
    writeJson(summaryPath, summary);
    pruneCliRunOutput();

    console.log("E2E CLI private-state bridge flow succeeded.");
    console.log(`Summary: ${summaryPath}`);
  } finally {
    if (typeof provider.destroy === "function") {
      provider.destroy();
    }
    if (!options.keepAnvil) {
      run("make", ["-C", appRoot, "anvil-stop"], { quiet: true, label: "anvil:stop:cleanup" });
    }
  }
}

main().catch((error) => {
  writeFailureDiagnostics(error);
  console.error(error instanceof Error ? error.stack ?? error.message : String(error));
  process.exit(1);
});
