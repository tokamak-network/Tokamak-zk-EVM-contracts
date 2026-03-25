#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  AbiCoder,
  Contract,
  HDNodeWallet,
  Interface,
  JsonRpcProvider,
  Wallet,
  ethers,
  getAddress,
} from "ethers";
import {
  createTokamakL2Common,
  createTokamakL2StateManagerFromStateSnapshot,
  createTokamakL2Tx,
  poseidon,
} from "tokamak-l2js";
import {
  addHexPrefix,
  bytesToHex,
  createAddressFromString,
  hexToBytes,
} from "@ethereumjs/util";
import {
  buildDAppDefinitions,
  buildFunctionDefinition,
} from "../../../../script/zk/lib/tokamak-artifacts.mjs";
import {
  deriveChannelIdFromName,
  deriveParticipantIdentityFromSigner,
  walletDirForName as sharedWalletDirForName,
  walletInboxPathForDir as sharedWalletInboxPathForDir,
  walletNameForChannelAndAddress as sharedWalletNameForChannelAndAddress,
} from "../../cli/private-state-cli-shared.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
const appRoot = path.resolve(repoRoot, "apps", "private-state");
const bridgeRoot = path.resolve(repoRoot, "bridge");
const tokamakRoot = path.resolve(repoRoot, "submodules", "Tokamak-zk-EVM");
const cliPath = path.resolve(appRoot, "cli", "private-state-bridge-cli.mjs");
const bridgeDeployHelperPath = path.resolve(bridgeRoot, "script", "deploy-bridge.sh");
const bridgeDeploymentPath = path.resolve(bridgeRoot, "deployments", "bridge.31337.json");
const deploymentManifestPath = path.resolve(appRoot, "deploy", "deployment.31337.latest.json");
const storageLayoutManifestPath = path.resolve(appRoot, "deploy", "storage-layout.31337.latest.json");
const controllerAbiPath = path.resolve(appRoot, "deploy", "PrivateStateController.callable-abi.json");
const outputRoot = path.resolve(appRoot, "script", "e2e", "output", "private-state-bridge-cli");
const bridgeEnvPath = path.resolve(outputRoot, "bridge.anvil.env");
const summaryPath = path.resolve(outputRoot, "summary.json");
const dappMetadataRoot = path.resolve(outputRoot, "dapp-metadata");
const providerUrl = process.env.ANVIL_RPC_URL?.trim() || "http://127.0.0.1:8545";
const anvilMnemonic = process.env.APPS_ANVIL_MNEMONIC?.trim() || "test test test test test test test test test test test junk";
const anvilDeployerPrivateKey =
  process.env.APPS_ANVIL_DEPLOYER_PRIVATE_KEY?.trim()
    || "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const channelName = "private-state-cli-e2e";
const dappId = "1";
const dappLabel = "private-state";
const depositAmountTokens = "3";
const claimAmountTokens = "9";
const amountUnit = 10n ** 18n;
const depositAmountBaseUnits = 3n * amountUnit;
const claimAmountBaseUnits = 9n * amountUnit;
const rootZero = "0x0ce3a78a0131c84050bbe2205642f9e176ffe98488dbddb19336b987420f3bde";
const tokamakAPubBlockLength = 68;
const tokamakPrevBlockHashCount = 4;
const requiredTokamakSetupArtifacts = [
  "combined_sigma.rkyv",
  "sigma_preprocess.rkyv",
  "sigma_verify.rkyv",
];
const tokamakCliPath = path.resolve(tokamakRoot, "tokamak-cli");
const tokamakSetupSourceDir = path.resolve(tokamakRoot, "packages", "backend", "setup", "trusted-setup", "output");
const tokamakSetupDistDir = path.resolve(tokamakRoot, "dist", "resource", "setup", "output");
const walletsRoot = path.resolve(appRoot, "cli", "wallets");
const workspacesRoot = path.resolve(appRoot, "cli", "workspaces");
const abiCoder = AbiCoder.defaultAbiCoder();
const dAppManagerAbi = [
  "function registerDApp(uint256 dappId, bytes32 labelHash, tuple(address storageAddr, bytes32[] preAllocatedKeys, uint8[] userStorageSlots, bool isChannelTokenVaultStorage)[] storages, tuple(address entryContract, bytes4 functionSig, bytes32 preprocessInputHash, tuple(uint8 entryContractOffsetWords, uint8 functionSigOffsetWords, uint8 currentRootVectorOffsetWords, uint8 updatedRootVectorOffsetWords, tuple(uint8 aPubOffsetWords, uint8 storageAddrIndex)[] storageWrites) instanceLayout)[] functions) external",
];

function usage() {
  console.log(`Usage:
  node apps/private-state/script/e2e/run-bridge-private-state-cli-e2e.mjs [options]

Options:
  --keep-anvil                         Leave anvil running after success
  --help                               Show this help

Notes:
  - The participant scenario is executed through the private-state CLI only.
  - Bridge deployment, DApp registration, and canonical-asset minting still use existing command-line helpers because
    the current private-state CLI does not expose those administrative setup flows.
`);
}

function parseArgs(argv) {
  const options = {
    keepAnvil: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    switch (current) {
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

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(
    filePath,
    `${JSON.stringify(value, (_key, current) => (
      typeof current === "bigint" ? current.toString() : current
    ), 2)}\n`,
  );
}

function run(command, args, {
  cwd = repoRoot,
  env = process.env,
  captureStdout = false,
  quiet = false,
} = {}) {
  const printable = [command, ...args].join(" ");
  console.log(`E2E CLI: ${printable}`);
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: captureStdout
      ? ["ignore", "pipe", quiet ? "ignore" : "inherit"]
      : (quiet ? ["ignore", "ignore", "ignore"] : "inherit"),
  });

  if (result.status !== 0) {
    throw new Error(
      [
        `${printable} failed with exit code ${result.status ?? "unknown"}.`,
        captureStdout && (result.stdout ?? "").trim().length > 0 ? `stdout:\n${result.stdout}` : null,
      ].filter(Boolean).join("\n"),
    );
  }

  return captureStdout ? (result.stdout ?? "") : "";
}

function runJsonCommand(command, args, options = {}) {
  const jsonOutputPath = path.resolve(outputRoot, ".tmp", `${Date.now()}-${Math.random().toString(16).slice(2)}.json`);
  run(command, args, {
    ...options,
    env: {
      ...process.env,
      ...(options.env ?? {}),
      PRIVATE_STATE_CLI_JSON_OUTPUT: jsonOutputPath,
    },
  });
  const stdout = fs.readFileSync(jsonOutputPath, "utf8").trim();
  try {
    return JSON.parse(stdout);
  } catch (error) {
    const trailingJson = extractTrailingJsonObject(stdout);
    if (trailingJson !== null) {
      return trailingJson;
    }
    throw new Error(
      [
        `Expected JSON output from ${command} ${args.join(" ")}.`,
        `stdout:\n${stdout}`,
      ].join("\n"),
    );
  } finally {
    fs.rmSync(jsonOutputPath, { force: true });
  }
}

function extractTrailingJsonObject(stdout) {
  for (let index = stdout.lastIndexOf("{"); index >= 0; index = stdout.lastIndexOf("{", index - 1)) {
    const candidate = stdout.slice(index).trim();
    try {
      return JSON.parse(candidate);
    } catch {
      continue;
    }
  }
  return null;
}

function bytes32FromHex(hexValue) {
  return ethers.zeroPadValue(ethers.toBeHex(BigInt(hexValue)), 32);
}

function normalizeBytes32Hex(hexValue) {
  return bytes32FromHex(hexValue).toLowerCase();
}

async function deriveParticipantIdentity(participant, provider) {
  const signer = new Wallet(participant.l1PrivateKey, provider);
  return deriveParticipantIdentityFromSigner({
    channelName,
    password: participant.password,
    signer,
  });
}

async function rpcCall(provider, method, params) {
  return provider.send(method, params);
}

async function getFixedBlockInfo(provider) {
  const latestNumberHex = await rpcCall(provider, "eth_blockNumber", []);
  const latestNumber = Number(BigInt(latestNumberHex));
  const blockNumber = Math.max(latestNumber, tokamakPrevBlockHashCount);
  return getBlockInfoAt(provider, blockNumber);
}

async function getBlockInfoAt(provider, blockNumber) {
  const blockTag = ethers.toQuantity(blockNumber);
  const block = await rpcCall(provider, "eth_getBlockByNumber", [blockTag, false]);
  const prevBlockHashes = [];
  for (let offset = 1; offset <= tokamakPrevBlockHashCount; offset += 1) {
    if (blockNumber <= offset) {
      prevBlockHashes.push("0x0");
      continue;
    }
    const previousBlock = await rpcCall(provider, "eth_getBlockByNumber", [ethers.toQuantity(blockNumber - offset), false]);
    prevBlockHashes.push(previousBlock.hash);
  }
  const chainId = await rpcCall(provider, "eth_chainId", []);
  return {
    coinBase: block.miner,
    timeStamp: block.timestamp,
    blockNumber: block.number,
    prevRanDao: block.prevRandao ?? block.mixHash ?? block.difficulty ?? "0x0",
    gasLimit: block.gasLimit,
    chainId,
    selfBalance: "0x0",
    baseFee: block.baseFeePerGas ?? "0x0",
    prevBlockHashes,
  };
}

async function fetchContractCodes(provider, addresses) {
  const codes = [];
  for (const address of addresses) {
    codes.push({
      address: getAddress(address),
      code: await provider.getCode(address),
    });
  }
  return codes;
}

function buildGenesisSnapshot(controllerAddress, vaultAddress) {
  return {
    channelId: deriveChannelIdFromName(channelName).toString(),
    stateRoots: [rootZero, rootZero],
    storageAddresses: [getAddress(controllerAddress), getAddress(vaultAddress)],
    storageEntries: [[], []],
  };
}

function isZeroLikeStorageValue(value) {
  if (typeof value !== "string") {
    return false;
  }
  const normalized = value.trim().toLowerCase();
  return normalized === "0x" || normalized === "0x0" || normalized === "0x00";
}

function normalizeStateSnapshot(snapshot) {
  return {
    ...snapshot,
    stateRoots: snapshot.stateRoots.map((value) => normalizeBytes32Hex(value)),
    storageEntries: snapshot.storageEntries.map((entries) => entries
      .filter((entry) => !isZeroLikeStorageValue(entry.value))
      .map((entry) => ({
        key: entry.key.toLowerCase(),
        value: entry.value.toLowerCase(),
      }))),
  };
}

async function buildStateManager(snapshot, contractCodes) {
  return createTokamakL2StateManagerFromStateSnapshot(snapshot, {
    contractCodes: contractCodes.map((entry) => ({
      address: createAddressFromString(entry.address),
      code: addHexPrefix(entry.code),
    })),
  });
}

function mappingKeyHex(address, slot) {
  const encoded = abiCoder.encode(["address", "uint256"], [address, BigInt(slot)]);
  return bytesToHex(poseidon(hexToBytes(encoded)));
}

function serializeBigInts(value) {
  return JSON.parse(JSON.stringify(value, (_key, current) => (
    typeof current === "bigint" ? current.toString() : current
  )));
}

function buildTokamakTxSnapshot({ signerPrivateKey, senderPubKey, to, data, nonce }) {
  const tx = createTokamakL2Tx(
    {
      nonce: BigInt(nonce),
      to: createAddressFromString(to),
      data: hexToBytes(data),
      senderPubKey,
    },
    { common: createTokamakL2Common() },
  ).sign(signerPrivateKey);
  return serializeBigInts(tx.captureTxSnapshot());
}

function note(owner, value, saltLabel) {
  const raw = BigInt(ethers.id(saltLabel));
  const normalized = (raw % ((1n << 255n) - 1n)) + 1n;
  return {
    owner: getAddress(owner),
    value,
    salt: bytes32FromHex(ethers.toBeHex(normalized)),
  };
}

function ensureTokamakSetupArtifacts() {
  const missingInDist = requiredTokamakSetupArtifacts.filter(
    (fileName) => !fs.existsSync(path.join(tokamakSetupDistDir, fileName)),
  );
  if (missingInDist.length === 0) {
    return;
  }

  const missingInSource = requiredTokamakSetupArtifacts.filter(
    (fileName) => !fs.existsSync(path.join(tokamakSetupSourceDir, fileName)),
  );
  expect(
    missingInSource.length === 0,
    `Missing Tokamak setup artifacts in trusted setup output: ${missingInSource.join(", ")}`,
  );

  ensureDir(tokamakSetupDistDir);
  for (const fileName of requiredTokamakSetupArtifacts) {
    fs.copyFileSync(path.join(tokamakSetupSourceDir, fileName), path.join(tokamakSetupDistDir, fileName));
  }
}

function copyTokamakArtifacts(stepDir) {
  const resourceRoot = path.join(stepDir, "resource");
  fs.rmSync(resourceRoot, { recursive: true, force: true });
  fs.cpSync(path.join(tokamakRoot, "dist", "resource"), resourceRoot, { recursive: true });
}

async function applyDepositSnapshot(stateManager, vaultAddress, keyHex, nextValue) {
  await stateManager.putStorage(
    createAddressFromString(vaultAddress),
    hexToBytes(keyHex),
    hexToBytes(bytes32FromHex(ethers.toBeHex(nextValue))),
  );
  return normalizeStateSnapshot(await stateManager.captureStateSnapshot());
}

async function runTokamakMetadataStep(step, previousSnapshot, blockInfo, contractCodes) {
  const stepDir = path.join(dappMetadataRoot, step.name);
  cleanDir(stepDir);

  const transactionSnapshot = buildTokamakTxSnapshot({
    signerPrivateKey: step.sender.l2PrivateKey,
    senderPubKey: step.sender.l2PublicKey,
    to: step.controllerAddress,
    data: step.calldata,
    nonce: step.nonce,
  });

  writeJson(path.join(stepDir, "previous_state_snapshot.json"), previousSnapshot);
  writeJson(path.join(stepDir, "transaction.json"), transactionSnapshot);
  writeJson(path.join(stepDir, "block_info.json"), blockInfo);
  writeJson(path.join(stepDir, "contract_codes.json"), contractCodes);

  run(tokamakCliPath, ["--synthesize", "--tokamak-ch-tx", stepDir], { cwd: tokamakRoot, quiet: true });
  ensureTokamakSetupArtifacts();
  run(tokamakCliPath, ["--preprocess"], { cwd: tokamakRoot, quiet: true });
  copyTokamakArtifacts(stepDir);

  const nextSnapshot = normalizeStateSnapshot(
    readJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.json")),
  );
  writeJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"), nextSnapshot);

  const metadataRecord = buildFunctionDefinition({
    groupName: dappLabel,
    exampleName: step.name,
    transactionJsonPath: path.join(stepDir, "transaction.json"),
    snapshotJsonPath: path.join(stepDir, "previous_state_snapshot.json"),
    preprocessJsonPath: path.join(stepDir, "resource", "preprocess", "output", "preprocess.json"),
    instanceJsonPath: path.join(stepDir, "resource", "synthesizer", "output", "instance.json"),
    instanceDescriptionJsonPath: path.join(stepDir, "resource", "synthesizer", "output", "instance_description.json"),
  });

  return {
    metadataRecord,
    nextSnapshot,
  };
}

async function materializeCurrentDAppDefinition(provider, participants) {
  const appDeployment = readJson(deploymentManifestPath);
  const storageLayout = readJson(storageLayoutManifestPath);
  const controllerAbi = readJson(controllerAbiPath);
  const controller = getAddress(appDeployment.contracts.controller);
  const vault = getAddress(appDeployment.contracts.l2AccountingVault);
  const controllerInterface = new Interface(controllerAbi);
  const liquidBalancesSlot = BigInt(
    storageLayout.contracts.L2AccountingVault.storageLayout.storage.find((entry) => entry.label === "liquidBalances").slot,
  );

  for (const participant of participants) {
    participant.metadataIdentity = await deriveParticipantIdentity(participant, provider);
  }

  const contractCodes = await fetchContractCodes(provider, [controller, vault]);
  const bootstrapBlockInfo = await getFixedBlockInfo(provider);
  const initialSnapshot = buildGenesisSnapshot(controller, vault);
  const depositStateManager = await buildStateManager(initialSnapshot, contractCodes);

  const participantKeys = new Map();
  for (const participant of participants) {
    participantKeys.set(
      participant.alias,
      mappingKeyHex(participant.metadataIdentity.l2Address, liquidBalancesSlot),
    );
  }

  let currentSnapshot = initialSnapshot;
  for (const participant of participants) {
    currentSnapshot = await applyDepositSnapshot(
      depositStateManager,
      vault,
      participantKeys.get(participant.alias),
      depositAmountBaseUnits,
    );
  }

  const notes = {
    aMint: note(participants[0].metadataIdentity.l2Address, depositAmountBaseUnits, `${channelName}:a-mint`),
    bMint: note(participants[1].metadataIdentity.l2Address, depositAmountBaseUnits, `${channelName}:b-mint`),
    cMint: note(participants[2].metadataIdentity.l2Address, depositAmountBaseUnits, `${channelName}:c-mint`),
    aToB: note(participants[1].metadataIdentity.l2Address, 1n * amountUnit, `${channelName}:a-to-b`),
    aToC: note(participants[2].metadataIdentity.l2Address, 2n * amountUnit, `${channelName}:a-to-c`),
    bToC: note(participants[2].metadataIdentity.l2Address, 4n * amountUnit, `${channelName}:b-to-c`),
  };

  const scenarios = [
    {
      name: "mint-notes-1",
      sender: participants[0].metadataIdentity,
      nonce: 0,
      controllerAddress: controller,
      calldata: controllerInterface.encodeFunctionData("mintNotes1", [[[notes.aMint.owner, notes.aMint.value, notes.aMint.salt]]]),
    },
    {
      name: "transfer-notes-1-to-2",
      sender: participants[0].metadataIdentity,
      nonce: 0,
      controllerAddress: controller,
      calldata: controllerInterface.encodeFunctionData(
        "transferNotes1To2",
        [
          [[notes.aMint.owner, notes.aMint.value, notes.aMint.salt]],
          [
            [notes.aToB.owner, notes.aToB.value, notes.aToB.salt],
            [notes.aToC.owner, notes.aToC.value, notes.aToC.salt],
          ],
        ],
      ),
    },
    {
      name: "mint-notes-2",
      sender: participants[1].metadataIdentity,
      nonce: 0,
      controllerAddress: controller,
      calldata: controllerInterface.encodeFunctionData("mintNotes1", [[[notes.bMint.owner, notes.bMint.value, notes.bMint.salt]]]),
    },
    {
      name: "transfer-notes-2-to-1",
      sender: participants[1].metadataIdentity,
      nonce: 0,
      controllerAddress: controller,
      calldata: controllerInterface.encodeFunctionData(
        "transferNotes2To1",
        [
          [
            [notes.bMint.owner, notes.bMint.value, notes.bMint.salt],
            [notes.aToB.owner, notes.aToB.value, notes.aToB.salt],
          ],
          [[notes.bToC.owner, notes.bToC.value, notes.bToC.salt]],
        ],
      ),
    },
    {
      name: "mint-notes-3",
      sender: participants[2].metadataIdentity,
      nonce: 0,
      controllerAddress: controller,
      calldata: controllerInterface.encodeFunctionData("mintNotes1", [[[notes.cMint.owner, notes.cMint.value, notes.cMint.salt]]]),
    },
    {
      name: "redeem-notes-1",
      sender: participants[2].metadataIdentity,
      nonce: 0,
      controllerAddress: controller,
      calldata: controllerInterface.encodeFunctionData(
        "redeemNotes1",
        [
          [[notes.aToC.owner, notes.aToC.value, notes.aToC.salt]],
          participants[2].metadataIdentity.l2Address,
        ],
      ),
    },
  ];

  const records = [];
  for (const scenario of scenarios) {
    const result = await runTokamakMetadataStep(scenario, currentSnapshot, bootstrapBlockInfo, contractCodes);
    records.push(result.metadataRecord);
    currentSnapshot = result.nextSnapshot;
  }

  const dapps = buildDAppDefinitions(records);
  expect(dapps.length === 1, `Expected one derived DApp definition, found ${dapps.length}.`);
  return {
    definition: dapps[0],
    records,
  };
}

function runPrivateStateCli(args, options = {}) {
  return runJsonCommand("node", [cliPath, ...args], {
    ...options,
    quiet: options.quiet ?? true,
  });
}

function deriveParticipant(index, alias) {
  const wallet = HDNodeWallet.fromPhrase(anvilMnemonic, undefined, `m/44'/60'/0'/0/${index}`);
  return {
    alias,
    password: alias,
    l1Address: getAddress(wallet.address),
    l1PrivateKey: wallet.privateKey,
    walletName: null,
    l2Address: null,
  };
}

function walletDirForName(walletName) {
  return sharedWalletDirForName(walletsRoot, walletName);
}

function walletInboxPathForName(walletName) {
  return sharedWalletInboxPathForDir(walletDirForName(walletName));
}

function readWalletInbox(walletName) {
  const inboxPath = walletInboxPathForName(walletName);
  if (!fs.existsSync(inboxPath)) {
    return [];
  }
  return readJson(inboxPath);
}

function assertWalletInboxCount(walletName, expectedCount, label) {
  const inbox = readWalletInbox(walletName);
  expect(
    inbox.length === expectedCount,
    `${label} inbox count mismatch. Expected ${expectedCount}, got ${inbox.length}.`,
  );
  return inbox;
}

function assertWalletInboxCleared(walletName, label) {
  expect(
    readWalletInbox(walletName).length === 0,
    `${label} inbox should be empty.`,
  );
}

function pickDeliveredRecipient(deliveries, participant) {
  const delivery = (deliveries ?? []).find((entry) => entry.wallet === participant.walletName);
  expect(delivery, `Missing delivered recipient entry for ${participant.alias}.`);
  return delivery;
}

function assertBigIntEq(actual, expected, label) {
  expect(
    BigInt(actual) === BigInt(expected),
    `${label} mismatch. Expected ${expected.toString()}, got ${actual.toString()}.`,
  );
}

function removeCliRunState() {
  cleanDir(outputRoot);

  fs.rmSync(path.join(workspacesRoot, channelName), { recursive: true, force: true });

  if (!fs.existsSync(walletsRoot)) {
    return;
  }

  for (const entry of fs.readdirSync(walletsRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) {
      continue;
    }
    if (!entry.name.startsWith(`${channelName}-`)) {
      continue;
    }
    fs.rmSync(path.join(walletsRoot, entry.name), { recursive: true, force: true });
  }
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

function bootstrapAnvil() {
  run("make", ["-C", appRoot, "anvil-stop"], { quiet: true });
  run("make", ["-C", appRoot, "anvil-start"], { quiet: true });
  run("make", ["-C", appRoot, "anvil-bootstrap"], { quiet: true });
}

function deployBridgeStack() {
  writeJsonLikeEnv(bridgeEnvPath, {
    BRIDGE_NETWORK: "anvil",
    BRIDGE_DEPLOYER_PRIVATE_KEY: anvilDeployerPrivateKey,
    BRIDGE_RPC_URL_OVERRIDE: providerUrl,
  });

  const env = {
    ...process.env,
    BRIDGE_ENV_FILE: bridgeEnvPath,
    BRIDGE_OUTPUT_PATH: bridgeDeploymentPath,
    BRIDGE_SKIP_SUBMODULE_UPDATE: "1",
    BRIDGE_SKIP_TOKAMAK_INSTALL: "1",
    BRIDGE_SKIP_TOKAMAK_VERIFIER_REFRESH: "1",
    BRIDGE_SKIP_GROTH_REFRESH: "1",
    BRIDGE_DEPLOY_MOCK_ASSET: "true",
  };

  run(
    "bash",
    [
      bridgeDeployHelperPath,
      "--mode",
      "redeploy-proxy",
    ],
    { env, quiet: true },
  );

  return readJson(bridgeDeploymentPath);
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
    { captureStdout: true },
  ).trim();
}

function prepareCanonicalAsset(bridgeDeployment, participants) {
  const canonicalAsset = getCanonicalAssetAddress(bridgeDeployment.bridgeCore);
  const mockAssetCode = run(
    "cast",
    ["code", bridgeDeployment.mockAsset, "--rpc-url", providerUrl],
    { captureStdout: true },
  ).trim();

  run("cast", ["rpc", "anvil_setCode", canonicalAsset, mockAssetCode, "--rpc-url", providerUrl], { quiet: true });

  for (const participant of participants) {
    run(
      "cast",
      [
        "send",
        canonicalAsset,
        "mint(address,uint256)",
        participant.l1Address,
        depositAmountBaseUnits.toString(),
        "--private-key",
        anvilDeployerPrivateKey,
        "--rpc-url",
        providerUrl,
      ],
      { quiet: true },
    );
  }

  return canonicalAsset;
}

async function registerPrivateStateDApp(provider, bridgeDeployment, participants) {
  const derived = await materializeCurrentDAppDefinition(provider, participants);
  const deployer = new Wallet(anvilDeployerPrivateKey, provider);
  const dAppManager = new Contract(bridgeDeployment.dAppManager, dAppManagerAbi, deployer);
  const tx = await dAppManager.registerDApp(
    BigInt(dappId),
    derived.definition.labelHash,
    derived.definition.storageMetadata.map((storage) => ({
      storageAddr: storage.storageAddress,
      preAllocatedKeys: storage.preAllocKeys,
      userStorageSlots: storage.userSlots,
      isChannelTokenVaultStorage: storage.isChannelTokenVaultStorage,
    })),
    derived.definition.functions.map((fn) => ({
      entryContract: fn.entryContract,
      functionSig: fn.functionSig,
      preprocessInputHash: fn.preprocessInputHash,
      instanceLayout: {
        entryContractOffsetWords: fn.entryContractOffsetWords,
        functionSigOffsetWords: fn.functionSigOffsetWords,
        currentRootVectorOffsetWords: fn.currentRootVectorOffsetWords,
        updatedRootVectorOffsetWords: fn.updatedRootVectorOffsetWords,
        storageWrites: fn.storageWrites,
      },
    })),
  );
  const receipt = await tx.wait();
  const result = {
    txHash: tx.hash,
    blockNumber: receipt?.blockNumber ?? null,
    storageCount: derived.definition.storageMetadata.length,
    functionCount: derived.definition.functions.length,
    artifactsRoot: dappMetadataRoot,
  };
  writeJson(path.join(outputRoot, "dapp-registration.json"), {
    dappId,
    dappLabel,
    result,
    definition: derived.definition,
    records: derived.records,
  });
  return result;
}

function readErc20Balance(assetAddress, ownerAddress) {
  const output = run(
    "cast",
    ["call", assetAddress, "balanceOf(address)(uint256)", ownerAddress, "--rpc-url", providerUrl],
    { captureStdout: true },
  ).trim();
  const normalized = output.split(/\s+/)[0];
  return BigInt(normalized);
}

function createChannel() {
  return runPrivateStateCli([
    "create-channel",
    "--channel-name", channelName,
    "--dapp-label", dappLabel,
    "--private-key", anvilDeployerPrivateKey,
    "--create-workspace",
    "--network", "anvil",
  ]);
}

function depositBridge(participant) {
  return runPrivateStateCli([
    "deposit-bridge",
    "--network", "anvil",
    "--private-key", participant.l1PrivateKey,
    "--amount", depositAmountTokens,
  ]);
}

function registerChannel(participant) {
  const result = runPrivateStateCli([
    "register-channel",
    "--channel-name", channelName,
    "--network", "anvil",
    "--private-key", participant.l1PrivateKey,
    "--password", participant.password,
  ]);
  participant.walletName = result.wallet;
  participant.l2Address = result.l2Address;
  expect(
    result.wallet === sharedWalletNameForChannelAndAddress(channelName, result.l2Address),
    `register-channel returned unexpected wallet name ${result.wallet}.`,
  );
  return result;
}

function getWalletAddress(participant) {
  return runPrivateStateCli([
    "get-wallet-address",
    "--wallet", participant.walletName,
    "--password", participant.password,
  ]);
}

function isChannelRegistered(participant) {
  return runPrivateStateCli([
    "is-channel-registered",
    "--wallet", participant.walletName,
    "--password", participant.password,
  ]);
}

function getBridgeDeposit(participant) {
  return runPrivateStateCli([
    "get-bridge-deposit",
    "--wallet", participant.walletName,
    "--password", participant.password,
  ]);
}

function depositChannel(participant) {
  return runPrivateStateCli([
    "deposit-channel",
    "--wallet", participant.walletName,
    "--password", participant.password,
    "--amount", depositAmountTokens,
  ]);
}

function getChannelDeposit(participant) {
  return runPrivateStateCli([
    "get-channel-deposit",
    "--wallet", participant.walletName,
    "--password", participant.password,
  ]);
}

function recoverWorkspace() {
  return runPrivateStateCli([
    "recover-workspace",
    "--channel-name", channelName,
    "--network", "anvil",
    "--force",
  ]);
}

function mintNotes(participant, amounts) {
  return runPrivateStateCli([
    "mint-notes",
    "--wallet", participant.walletName,
    "--password", participant.password,
    "--amounts", JSON.stringify(amounts),
  ]);
}

function getMyNotes(participant) {
  return runPrivateStateCli([
    "get-my-notes",
    "--wallet", participant.walletName,
    "--password", participant.password,
  ]);
}

function transferNotes(participant, noteIds, recipients, amounts) {
  return runPrivateStateCli([
    "transfer-notes",
    "--wallet", participant.walletName,
    "--password", participant.password,
    "--note-ids", JSON.stringify(noteIds),
    "--recipients", JSON.stringify(recipients),
    "--amounts", JSON.stringify(amounts),
  ]);
}

function redeemNote(participant, noteId) {
  return runPrivateStateCli([
    "redeem-notes",
    "--wallet", participant.walletName,
    "--password", participant.password,
    "--note-id", noteId,
  ]);
}

function withdrawChannel(participant, amount) {
  return runPrivateStateCli([
    "withdraw-channel",
    "--wallet", participant.walletName,
    "--password", participant.password,
    "--amount", amount,
  ]);
}

function withdrawBridge(participant, amount) {
  return runPrivateStateCli([
    "withdraw-bridge",
    "--wallet", participant.walletName,
    "--password", participant.password,
    "--amount", amount,
  ]);
}

function pickOutputNoteByOwner(outputNotes, ownerAddress, expectedValue) {
  const owner = getAddress(ownerAddress);
  const expected = BigInt(expectedValue).toString();
  const matches = outputNotes.filter((note) => (
    getAddress(note.owner) === owner && BigInt(note.value) === BigInt(expected)
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
  const commandResults = {
    participants: {},
  };

  try {
    console.log("E2E CLI: bootstrapping anvil and local deployments.");
    bootstrapAnvil();
    bridgeDeployment = deployBridgeStack();
    canonicalAsset = prepareCanonicalAsset(bridgeDeployment, participants);
    dappRegistrationResult = await registerPrivateStateDApp(provider, bridgeDeployment, participants);

    createChannelResult = createChannel();
    recoverWorkspaceResult = recoverWorkspace();

    for (const participant of participants) {
      const participantResults = {};
      participantResults.depositBridge = depositBridge(participant);
      participantResults.registerChannel = registerChannel(participant);
      participantResults.getWalletAddress = getWalletAddress(participant);
      participantResults.isChannelRegistered = isChannelRegistered(participant);
      participantResults.depositChannel = depositChannel(participant);
      participantResults.getChannelDeposit = getChannelDeposit(participant);
      participantResults.getBridgeDeposit = getBridgeDeposit(participant);

      expect(
        String(participantResults.getWalletAddress.l2Address).toLowerCase()
          === String(participantResults.registerChannel.l2Address).toLowerCase(),
        `${participant.alias} registered L2 address mismatch.`,
      );
      expect(
        participantResults.isChannelRegistered.registrationExists === true
          && participantResults.isChannelRegistered.matchesWallet === true,
        `${participant.alias} channel registration does not match the local wallet.`,
      );
      assertBigIntEq(
        participantResults.getChannelDeposit.channelDepositBaseUnits,
        depositAmountBaseUnits,
        `${participant.alias} channel deposit`,
      );
      assertBigIntEq(
        participantResults.getBridgeDeposit.availableBalanceBaseUnits,
        0n,
        `${participant.alias} bridge deposit after deposit-channel`,
      );

      commandResults.participants[participant.alias] = participantResults;
    }

    recoverWorkspaceResult = recoverWorkspace();

    const mintA = mintNotes(participants[0], [3]);
    const mintB = mintNotes(participants[1], [3]);
    const mintC = mintNotes(participants[2], [3]);

    const aMintNote = mintA.outputNotes[0];
    const bMintNote = mintB.outputNotes[0];
    const cMintNote = mintC.outputNotes[0];

    const notesAfterMintA = getMyNotes(participants[0]);
    const notesAfterMintB = getMyNotes(participants[1]);
    const notesAfterMintC = getMyNotes(participants[2]);
    assertWalletNoteSnapshot(notesAfterMintA, { unusedCount: 1, spentCount: 0, unusedTotal: depositAmountBaseUnits, spentTotal: 0n });
    assertWalletNoteSnapshot(notesAfterMintB, { unusedCount: 1, spentCount: 0, unusedTotal: depositAmountBaseUnits, spentTotal: 0n });
    assertWalletNoteSnapshot(notesAfterMintC, { unusedCount: 1, spentCount: 0, unusedTotal: depositAmountBaseUnits, spentTotal: 0n });

    const transferA = transferNotes(
      participants[0],
      [aMintNote.commitment],
      [participants[1].l2Address, participants[2].l2Address],
      [1, 2],
    );
    const noteAToB = pickOutputNoteByOwner(transferA.outputNotes, participants[1].l2Address, 1n * amountUnit);
    const noteAToC = pickOutputNoteByOwner(transferA.outputNotes, participants[2].l2Address, 2n * amountUnit);
    const deliveredAToB = pickDeliveredRecipient(transferA.deliveredRecipients, participants[1]);
    const deliveredAToC = pickDeliveredRecipient(transferA.deliveredRecipients, participants[2]);
    assertBigIntEq(deliveredAToB.noteCount, 1n, "transfer A delivery count to B");
    assertBigIntEq(deliveredAToC.noteCount, 1n, "transfer A delivery count to C");
    assertWalletInboxCount(participants[1].walletName, 1, "participant-b after transfer A");
    assertWalletInboxCount(participants[2].walletName, 1, "participant-c after transfer A");

    const transferB = transferNotes(
      participants[1],
      [bMintNote.commitment, noteAToB.commitment],
      [participants[2].l2Address],
      [4],
    );
    const noteBToC = pickOutputNoteByOwner(transferB.outputNotes, participants[2].l2Address, 4n * amountUnit);
    const deliveredBToC = pickDeliveredRecipient(transferB.deliveredRecipients, participants[2]);
    assertBigIntEq(deliveredBToC.noteCount, 1n, "transfer B delivery count to C");
    assertWalletInboxCleared(participants[1].walletName, "participant-b after transfer B");
    assertWalletInboxCount(participants[2].walletName, 2, "participant-c after transfer B");

    const notesAfterTransferA = getMyNotes(participants[0]);
    const notesAfterTransferB = getMyNotes(participants[1]);
    const notesAfterTransferC = getMyNotes(participants[2]);
    assertWalletInboxCleared(participants[2].walletName, "participant-c after wallet sync");
    assertWalletNoteSnapshot(notesAfterTransferA, { unusedCount: 0, spentCount: 1, unusedTotal: 0n, spentTotal: depositAmountBaseUnits });
    assertWalletNoteSnapshot(notesAfterTransferB, { unusedCount: 0, spentCount: 2, unusedTotal: 0n, spentTotal: 4n * amountUnit });
    assertWalletNoteSnapshot(notesAfterTransferC, { unusedCount: 3, spentCount: 0, unusedTotal: claimAmountBaseUnits, spentTotal: 0n });

    const redeemAToC = redeemNote(participants[2], noteAToC.commitment);
    const redeemBToC = redeemNote(participants[2], noteBToC.commitment);
    const redeemCMint = redeemNote(participants[2], cMintNote.commitment);
    const notesAfterRedeemC = getMyNotes(participants[2]);
    assertWalletNoteSnapshot(notesAfterRedeemC, { unusedCount: 0, spentCount: 3, unusedTotal: 0n, spentTotal: claimAmountBaseUnits });

    const channelDepositBeforeWithdraw = getChannelDeposit(participants[2]);
    assertBigIntEq(
      channelDepositBeforeWithdraw.channelDepositBaseUnits,
      claimAmountBaseUnits,
      "participant-c channel deposit before withdraw",
    );

    const l1BalanceBeforeClaim = readErc20Balance(canonicalAsset, participants[2].l1Address);
    const withdrawChannelResult = withdrawChannel(participants[2], claimAmountTokens);
    const bridgeDepositAfterWithdraw = getBridgeDeposit(participants[2]);
    const channelDepositAfterWithdraw = getChannelDeposit(participants[2]);
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

    const withdrawBridgeResult = withdrawBridge(participants[2], claimAmountTokens);
    const bridgeDepositAfterClaim = getBridgeDeposit(participants[2]);
    const l1BalanceAfterClaim = readErc20Balance(canonicalAsset, participants[2].l1Address);
    assertBigIntEq(
      bridgeDepositAfterClaim.availableBalanceBaseUnits,
      0n,
      "participant-c bridge deposit after withdraw-bridge",
    );
    assertBigIntEq(
      l1BalanceAfterClaim - l1BalanceBeforeClaim,
      claimAmountBaseUnits,
      "participant-c L1 ERC20 claim delta",
    );
    assertBigIntEq(getBridgeDeposit(participants[0]).availableBalanceBaseUnits, 0n, "participant-a final bridge deposit");
    assertBigIntEq(getBridgeDeposit(participants[1]).availableBalanceBaseUnits, 0n, "participant-b final bridge deposit");

    const summary = {
      providerUrl,
      channelName,
      bridgeDeployment,
      canonicalAsset,
      dappRegistration: dappRegistrationResult,
      createChannel: createChannelResult,
      recoverWorkspace: recoverWorkspaceResult,
      participants: participants.map((participant) => ({
        alias: participant.alias,
        password: participant.password,
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
        redeemAToC,
        redeemBToC,
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
    if (!options.keepAnvil) {
      run("make", ["-C", appRoot, "anvil-stop"], { quiet: true });
    }
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack ?? error.message : String(error));
  process.exit(1);
});
