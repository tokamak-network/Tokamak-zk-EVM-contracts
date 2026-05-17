#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import { Contract, Interface, JsonRpcProvider, ethers } from "ethers";
import {
  createDriveClient,
  findChildFileMetadata,
  findChildFolderId,
  listChildFolders,
  resolveDriveUploadConfigWithFolderId,
} from "../drive/lib/google-drive-upload.mjs";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, "../..");
const DEFAULT_INTERNAL_OUTPUT_DIR = path.join(SCRIPT_DIR, "output");
const PUBLIC_OUTPUT_DIR = path.join(REPO_ROOT, "docs/audit/monitoring/data");
const DEFAULT_CHAIN_ID = 1;
const DEFAULT_DAPP = "private-state";
const DEFAULT_CHANNEL = "the-great-first-channel";
const ETHERSCAN_BASE_URL = "https://etherscan.io";
const ETHERSCAN_V2_API_URL = "https://api.etherscan.io/v2/api";
const ETHERSCAN_RETRY_COUNT = 3;
const ETHERSCAN_RETRY_DELAY_MS = 750;
const EIP1967_IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
const EIP1967_ADMIN_SLOT =
  "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";

const PRIVATE_STATE_EVENT_ABIS = {
  privateStateController: [
    "event NoteValueEncrypted(bytes32[3] encryptedNoteValue)",
    "event StorageKeyObserved(bytes32 storageKey)",
  ],
  l2AccountingVault: [
    "event LiquidBalanceStorageWriteObserved(address l2Address, bytes32 value)",
  ],
};
const CURRENT_ROOT_VECTOR_OBSERVED_ABI = [
  "event CurrentRootVectorObserved(bytes32 indexed rootVectorHash, bytes32[] rootVector)",
];
const DEFAULT_RPC_LOG_CHUNK_SIZE = 10;

function printHelp() {
  console.log(`Usage: node scripts/monitoring-packet/generate.mjs [options]

Generates the data-backed Monitoring Packet files.

Public packet output:
  docs/audit/monitoring/data/

Internal validation output:
  scripts/monitoring-packet/output/*.json

Options:
  --chain-id <id>              Ethereum chain ID. Default: 1.
  --dapp <label>               DApp deployment label. Default: private-state.
  --channel <name>             Channel name. Default: the-great-first-channel.
  --rpc-url <url>              Mainnet RPC URL. Defaults to RPC_URL, MAINNET_RPC_URL, ETHEREUM_RPC_URL, or Alchemy env keys.
  --drive-folder-id <id>       Google Drive root folder ID. Defaults to TOKAMAK_MPC_DRIVE_FOLDER_ID.
  --output <dir>               Internal validation output directory. Default: scripts/monitoring-packet/output.
  --skip-drive                 Skip Google Drive artifact metadata reads.
  --allow-missing-drive        Continue with a warning if Drive metadata cannot be read.
  --skip-etherscan             Skip source verification status reads.
  --allow-missing-etherscan    Continue with a warning if Etherscan status cannot be classified.
  --help                       Show this help.
`);
}

function parseArgs(argv) {
  const args = {
    chainId: DEFAULT_CHAIN_ID,
    dapp: DEFAULT_DAPP,
    channel: DEFAULT_CHANNEL,
    output: DEFAULT_INTERNAL_OUTPUT_DIR,
    skipDrive: false,
    allowMissingDrive: false,
    skipEtherscan: false,
    allowMissingEtherscan: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const value = () => {
      const next = argv[i + 1];
      if (!next || next.startsWith("--")) throw new Error(`Missing value for ${arg}.`);
      i += 1;
      return next;
    };
    if (arg === "--help") args.help = true;
    else if (arg === "--chain-id") args.chainId = Number(value());
    else if (arg === "--dapp") args.dapp = value();
    else if (arg === "--channel") args.channel = value();
    else if (arg === "--rpc-url") args.rpcUrl = value();
    else if (arg === "--drive-folder-id") args.driveFolderId = value();
    else if (arg === "--output") args.output = path.resolve(value());
    else if (arg === "--skip-drive") args.skipDrive = true;
    else if (arg === "--allow-missing-drive") args.allowMissingDrive = true;
    else if (arg === "--skip-etherscan") args.skipEtherscan = true;
    else if (arg === "--allow-missing-etherscan") args.allowMissingEtherscan = true;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (!Number.isInteger(args.chainId) || args.chainId <= 0) {
    throw new Error(`Invalid --chain-id: ${args.chainId}`);
  }
  return args;
}

function loadEnv() {
  for (const envPath of [path.join(REPO_ROOT, ".env"), path.join(REPO_ROOT, "packages/apps/.env")]) {
    if (fs.existsSync(envPath)) dotenv.config({ path: envPath, override: false });
  }
}

function resolveRpcUrl(args) {
  const direct = args.rpcUrl
    ?? process.env.RPC_URL
    ?? process.env.MAINNET_RPC_URL
    ?? process.env.ETHEREUM_RPC_URL
    ?? process.env.BRIDGE_RPC_URL
    ?? null;
  if (direct) return direct;
  const alchemyKey = process.env.ALCHEMY_API_KEY
    ?? process.env.APPS_ALCHEMY_API_KEY
    ?? process.env.BRIDGE_ALCHEMY_API_KEY
    ?? null;
  if (alchemyKey) return `https://eth-mainnet.g.alchemy.com/v2/${alchemyKey}`;
  throw new Error("Missing RPC URL. Set RPC_URL, MAINNET_RPC_URL, ETHEREUM_RPC_URL, BRIDGE_RPC_URL, or pass --rpc-url.");
}

function resolveEtherscanApiKey() {
  return process.env.ETHERSCAN_API_KEY
    ?? process.env.BRIDGE_ETHERSCAN_API_KEY
    ?? process.env.APPS_ETHERSCAN_API_KEY
    ?? null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readOptionalJson(filePath) {
  return fs.existsSync(filePath) ? readJson(filePath) : null;
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(toPlain(value), null, 2)}\n`);
}

function writeText(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, value.endsWith("\n") ? value : `${value}\n`);
}

function fileKeccak256(filePath) {
  return ethers.keccak256(fs.readFileSync(filePath));
}

function toPlain(value) {
  if (typeof value === "bigint") return value.toString();
  if (Array.isArray(value)) return value.map((entry) => toPlain(entry));
  if (value && typeof value === "object") {
    if (typeof value.toObject === "function") return toPlain(value.toObject());
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !/^\d+$/.test(key))
        .map(([key, entry]) => [key, toPlain(entry)]),
    );
  }
  return value;
}

function findLatestDir(parentDir, requiredFileName) {
  const names = fs.readdirSync(parentDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
  for (const name of [...names].reverse()) {
    const candidate = path.join(parentDir, name);
    if (fs.existsSync(path.join(candidate, requiredFileName))) return candidate;
  }
  throw new Error(`No deployment directory with ${requiredFileName}: ${parentDir}`);
}

function requireFile(filePath) {
  if (!fs.existsSync(filePath)) throw new Error(`Missing required file: ${filePath}`);
  return filePath;
}

function loadLocalArtifacts({ chainId, dapp }) {
  const bridgeRoot = path.join(REPO_ROOT, "deployment", `chain-id-${chainId}`, "bridge");
  const dappRoot = path.join(REPO_ROOT, "deployment", `chain-id-${chainId}`, "dapps", dapp);
  const bridgeDir = findLatestDir(bridgeRoot, `bridge.${chainId}.json`);
  const dappDir = findLatestDir(dappRoot, `deployment.${chainId}.latest.json`);
  const bridgeDeploymentPath = requireFile(path.join(bridgeDir, `bridge.${chainId}.json`));
  const bridgeAbiManifestPath = requireFile(path.join(bridgeDir, `bridge-abi-manifest.${chainId}.json`));
  const dappDeploymentPath = requireFile(path.join(dappDir, `deployment.${chainId}.latest.json`));
  const dappRegistrationPath = requireFile(path.join(dappDir, `dapp-registration.${chainId}.json`));
  const dappStorageLayoutPath = requireFile(path.join(dappDir, `storage-layout.${chainId}.latest.json`));
  return {
    paths: {
      bridgeDir,
      dappDir,
      bridgeDeploymentPath,
      bridgeAbiManifestPath,
      dappDeploymentPath,
      dappRegistrationPath,
      dappStorageLayoutPath,
    },
    bridge: readJson(bridgeDeploymentPath),
    bridgeAbiManifest: readJson(bridgeAbiManifestPath),
    dappDeployment: readJson(dappDeploymentPath),
    dappRegistration: readJson(dappRegistrationPath),
    dappStorageLayout: readJson(dappStorageLayoutPath),
  };
}

function getBridgeAbis(artifacts) {
  const manifest = artifacts.bridgeAbiManifest;
  if (manifest.abis) return manifest.abis;
  if (manifest.contracts) {
    return Object.fromEntries(Object.entries(manifest.contracts).map(([name, entry]) => [name, entry.abi]));
  }
  throw new Error("Unsupported bridge ABI manifest format.");
}

function readArtifactAbi(filePath) {
  const artifact = readOptionalJson(filePath);
  if (!artifact) return null;
  return Array.isArray(artifact) ? artifact : artifact.abi ?? null;
}

function readPrivateStateContractAbi(contractName, fallback) {
  return readArtifactAbi(path.join(
    REPO_ROOT,
    "packages/apps/private-state/out",
    `${contractName}.sol`,
    `${contractName}.json`,
  )) ?? fallback;
}

function deriveChannelIdFromName(channelName) {
  return ethers.toBigInt(ethers.keccak256(ethers.toUtf8Bytes(channelName)));
}

function slugify(value) {
  return String(value)
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}

function addressFromSlot(value) {
  if (!value || ethers.toBigInt(value) === 0n) return null;
  return ethers.getAddress(`0x${value.slice(-40)}`);
}

async function proxyState(provider, address) {
  const [implementationSlot, adminSlot, code] = await Promise.all([
    provider.getStorage(address, EIP1967_IMPLEMENTATION_SLOT),
    provider.getStorage(address, EIP1967_ADMIN_SLOT),
    provider.getCode(address),
  ]);
  return {
    address: ethers.getAddress(address),
    implementation: addressFromSlot(implementationSlot),
    admin: addressFromSlot(adminSlot),
    proxyKind: "uups",
    adminStatus: addressFromSlot(adminSlot) ? "admin-slot-set" : "empty-admin-slot",
    bytecodeHash: code === "0x" ? null : ethers.keccak256(code),
    explorerUrl: `${ETHERSCAN_BASE_URL}/address/${ethers.getAddress(address)}`,
  };
}

async function codeHash(provider, address) {
  const code = await provider.getCode(address);
  return code === "0x" ? null : ethers.keccak256(code);
}

async function safeCall(label, fn) {
  try {
    return { ok: true, value: await fn() };
  } catch (error) {
    return { ok: false, error: `${label}: ${error.message}` };
  }
}

async function queryFirstFilterInChunks(contract, filter, fromBlock, toBlock, chunkSize = DEFAULT_RPC_LOG_CHUNK_SIZE) {
  for (let start = Number(fromBlock); start <= Number(toBlock); start += chunkSize) {
    const end = Math.min(start + chunkSize - 1, Number(toBlock));
    const logs = await contract.queryFilter(filter, start, end);
    if (logs.length > 0) return logs[0];
  }
  return null;
}

async function queryLatestFilterInChunks(contract, filter, fromBlock, toBlock, chunkSize = DEFAULT_RPC_LOG_CHUNK_SIZE) {
  for (let end = Number(toBlock); end >= Number(fromBlock); end -= chunkSize) {
    const start = Math.max(Number(fromBlock), end - chunkSize + 1);
    const logs = await contract.queryFilter(filter, start, end);
    if (logs.length > 0) return logs[logs.length - 1];
  }
  return null;
}

function numberFromHex(value) {
  if (value === null || value === undefined) return null;
  return Number(ethers.toBigInt(value));
}

function formatAcceptedTransitionLog(log) {
  if (!log) return null;
  const rootVectorHash = log.args?.rootVectorHash ?? log.args?.[0] ?? null;
  const rootVector = log.args?.rootVector ?? log.args?.[1] ?? [];
  return {
    eventName: "CurrentRootVectorObserved",
    transactionHash: log.transactionHash,
    blockNumber: log.blockNumber,
    blockHash: log.blockHash,
    logIndex: log.index ?? log.logIndex ?? null,
    rootVectorHash,
    rootVector: Array.from(rootVector).map((entry) => String(entry)),
    explorerUrl: log.transactionHash ? `${ETHERSCAN_BASE_URL}/tx/${log.transactionHash}#eventlog` : null,
  };
}

function formatEtherscanAcceptedTransitionLog(log) {
  if (!log) return null;
  const iface = new Interface(CURRENT_ROOT_VECTOR_OBSERVED_ABI);
  const parsed = iface.parseLog({ topics: log.topics, data: log.data });
  const rootVectorHash = parsed.args.rootVectorHash ?? parsed.args[0];
  const rootVector = parsed.args.rootVector ?? parsed.args[1] ?? [];
  const transactionHash = log.transactionHash ?? null;
  return {
    eventName: "CurrentRootVectorObserved",
    transactionHash,
    blockNumber: numberFromHex(log.blockNumber),
    blockHash: log.blockHash ?? null,
    logIndex: numberFromHex(log.logIndex),
    transactionIndex: numberFromHex(log.transactionIndex),
    timestamp: numberFromHex(log.timeStamp),
    rootVectorHash,
    rootVector: Array.from(rootVector).map((entry) => String(entry)),
    explorerUrl: transactionHash ? `${ETHERSCAN_BASE_URL}/tx/${transactionHash}#eventlog` : null,
    checkedVia: "etherscan-api",
  };
}

async function fetchEtherscanCurrentRootLogs({
  address,
  rootVectorHash,
  fromBlock,
  toBlock,
  chainId,
  apiKey,
}) {
  const params = new URLSearchParams({
    chainid: String(chainId),
    module: "logs",
    action: "getLogs",
    fromBlock: String(fromBlock),
    toBlock: String(toBlock),
    address,
    topic0: ethers.id("CurrentRootVectorObserved(bytes32,bytes32[])"),
    topic0_1_opr: "and",
    topic1: rootVectorHash,
    page: "1",
    offset: "1000",
    apikey: apiKey,
  });
  const response = await fetch(`${ETHERSCAN_V2_API_URL}?${params.toString()}`);
  const json = await response.json();
  if (!response.ok) {
    throw new Error(`Etherscan getLogs failed: ${response.status}`);
  }
  if (json.status === "0") {
    const message = String(json.result ?? json.message ?? "");
    if (/No records found/i.test(message)) return [];
    throw new Error(`Etherscan getLogs failed: ${json.message ?? "status 0"}: ${message}`);
  }
  if (!Array.isArray(json.result)) {
    throw new Error("Etherscan getLogs returned a non-array result.");
  }
  return json.result;
}

async function resolveLatestAcceptedTransition({
  args,
  channelManager,
  channelCreatedBlock,
  latestBlock,
  currentRootVectorHash,
}) {
  if (!currentRootVectorHash) return null;
  const fromBlock = Number(channelCreatedBlock);
  const toBlock = Number(latestBlock);
  const apiKey = args.skipEtherscan ? null : resolveEtherscanApiKey();
  if (apiKey) {
    const logs = await fetchEtherscanCurrentRootLogs({
      address: await channelManager.getAddress(),
      rootVectorHash: currentRootVectorHash,
      fromBlock,
      toBlock,
      chainId: args.chainId,
      apiKey,
    });
    const latestLog = logs
      .map(formatEtherscanAcceptedTransitionLog)
      .sort((a, b) => (a.blockNumber - b.blockNumber) || ((a.logIndex ?? 0) - (b.logIndex ?? 0)))
      .at(-1);
    if (latestLog) return latestLog;
  }
  const filter = channelManager.filters.CurrentRootVectorObserved(currentRootVectorHash);
  return formatAcceptedTransitionLog(await queryLatestFilterInChunks(channelManager, filter, fromBlock, toBlock));
}

function privateStateControllerAddress(artifacts) {
  return artifacts.dappDeployment.contracts?.privateStateController
    ?? artifacts.dappDeployment.contracts?.controller
    ?? null;
}

async function buildOnchainSnapshot({ args, artifacts, rpcUrl }) {
  const provider = new JsonRpcProvider(rpcUrl, args.chainId);
  const network = await provider.getNetwork();
  if (Number(network.chainId) !== args.chainId) {
    throw new Error(`RPC chain ID mismatch: expected ${args.chainId}, got ${network.chainId.toString()}.`);
  }
  const abis = getBridgeAbis(artifacts);
  const bridgeCore = new Contract(artifacts.bridge.bridgeCore, abis.bridgeCore, provider);
  const dAppManager = new Contract(artifacts.bridge.dAppManager, abis.dAppManager, provider);
  const bridgeTokenVault = new Contract(artifacts.bridge.bridgeTokenVault, abis.bridgeTokenVault, provider);
  const channelId = deriveChannelIdFromName(args.channel);
  const [latestBlock, channelInfo, mirrorUrl, canonicalAsset] = await Promise.all([
    provider.getBlockNumber(),
    bridgeCore.getChannel(channelId),
    bridgeCore.getChannelWorkspaceMirror(channelId),
    safeCall("BridgeCore.canonicalAsset", () => bridgeCore.canonicalAsset()),
  ]);
  const channelManagerAddress = ethers.getAddress(channelInfo.manager);
  const channelManager = new Contract(channelManagerAddress, abis.channelManager, provider);
  const dappId = Number(channelInfo.dappId);
  const channelCreatedResult = await safeCall("ChannelCreated log scan", () => queryFirstFilterInChunks(
    bridgeCore,
    bridgeCore.filters.ChannelCreated(channelId),
    Number(artifacts.dappRegistration.registration?.blockNumber ?? 0),
    latestBlock,
  ));
  const channelCreated = channelCreatedResult.ok ? channelCreatedResult.value : null;

  const [
    currentRootVectorHash,
    managedStorageAddresses,
    joinToll,
    bridgeOwner,
    dappManagerOwner,
    vaultOwner,
    dappInfo,
    verifierSnapshot,
    bridgeCoreProxy,
    dAppManagerProxy,
    bridgeTokenVaultProxy,
  ] = await Promise.all([
    safeCall("ChannelManager.currentRootVectorHash", () => channelManager.currentRootVectorHash()),
    safeCall("ChannelManager.getManagedStorageAddresses", () => channelManager.getManagedStorageAddresses()),
    safeCall("ChannelManager.joinToll", () => channelManager.joinToll()),
    safeCall("BridgeCore.owner", () => bridgeCore.owner()),
    safeCall("DAppManager.owner", () => dAppManager.owner()),
    safeCall("L1TokenVault.owner", () => bridgeTokenVault.owner()),
    safeCall("DAppManager.getDAppInfo", () => dAppManager.getDAppInfo(dappId)),
    safeCall("DAppManager.getDAppVerifierSnapshot", () => dAppManager.getDAppVerifierSnapshot(dappId)),
    proxyState(provider, artifacts.bridge.bridgeCore),
    proxyState(provider, artifacts.bridge.dAppManager),
    proxyState(provider, artifacts.bridge.bridgeTokenVault),
  ]);
  const latestAcceptedTransition = await safeCall(
    "ChannelManager.CurrentRootVectorObserved latest log scan",
    () => resolveLatestAcceptedTransition({
      args,
      channelManager,
      channelCreatedBlock: channelCreated?.blockNumber ?? artifacts.dappRegistration.registration?.blockNumber ?? 0,
      latestBlock,
      currentRootVectorHash: currentRootVectorHash.ok ? currentRootVectorHash.value : null,
    }),
  );

  const monitoredAddresses = [
    artifacts.bridge.bridgeCore,
    artifacts.bridge.bridgeCoreImplementation,
    artifacts.bridge.dAppManager,
    artifacts.bridge.dAppManagerImplementation,
    artifacts.bridge.bridgeTokenVault,
    artifacts.bridge.bridgeTokenVaultImplementation,
    artifacts.bridge.channelDeployer,
    artifacts.bridge.grothVerifier,
    artifacts.bridge.tokamakVerifier,
    channelManagerAddress,
    channelInfo.bridgeTokenVault,
    privateStateControllerAddress(artifacts),
    artifacts.dappDeployment.contracts?.l2AccountingVault,
  ].filter(Boolean).map((address) => ethers.getAddress(address));

  const bytecodeHashes = Object.fromEntries(await Promise.all(
    [...new Set(monitoredAddresses)].map(async (address) => [address, await codeHash(provider, address)]),
  ));

  return {
    rpc: { chainId: args.chainId, currentBlock: latestBlock },
    channel: {
      name: args.channel,
      id: channelId.toString(),
      createdTxHash: channelCreated?.transactionHash ?? null,
      createdBlockNumber: channelCreated?.blockNumber ?? null,
      manager: channelManagerAddress,
      bridgeTokenVault: ethers.getAddress(channelInfo.bridgeTokenVault),
      leader: ethers.getAddress(channelInfo.leader),
      operator: ethers.getAddress(channelInfo.leader),
      asset: ethers.getAddress(channelInfo.asset),
      dappId,
      aPubBlockHash: channelInfo.aPubBlockHash,
      dappMetadataDigestSchema: channelInfo.dappMetadataDigestSchema,
      dappMetadataDigest: channelInfo.dappMetadataDigest,
      workspaceMirrorUrl: String(mirrorUrl ?? ""),
      currentRootVectorHash: currentRootVectorHash.ok ? currentRootVectorHash.value : null,
      latestAcceptedTransition: latestAcceptedTransition.ok ? latestAcceptedTransition.value : null,
      managedStorageAddresses: managedStorageAddresses.ok
        ? managedStorageAddresses.value.map((address) => ethers.getAddress(address))
        : [],
      joinToll: joinToll.ok ? joinToll.value.toString() : null,
    },
    bridge: {
      canonicalAsset: canonicalAsset.ok ? ethers.getAddress(canonicalAsset.value) : null,
      grothVerifier: ethers.getAddress(artifacts.bridge.grothVerifier),
      tokamakVerifier: ethers.getAddress(artifacts.bridge.tokamakVerifier),
      proxyState: {
        bridgeCore: bridgeCoreProxy,
        dAppManager: dAppManagerProxy,
        bridgeTokenVault: bridgeTokenVaultProxy,
      },
      owners: {
        bridgeCore: bridgeOwner.ok ? ethers.getAddress(bridgeOwner.value) : null,
        dAppManager: dappManagerOwner.ok ? ethers.getAddress(dappManagerOwner.value) : null,
        bridgeTokenVault: vaultOwner.ok ? ethers.getAddress(vaultOwner.value) : null,
      },
    },
    dapp: {
      label: args.dapp,
      id: dappId,
      registrationTxHash: artifacts.dappRegistration.registration?.txHash ?? null,
      registrationBlockNumber: artifacts.dappRegistration.registration?.blockNumber ?? null,
      metadataDigest: artifacts.dappRegistration.registration?.metadataDigest ?? channelInfo.dappMetadataDigest,
      functionRoot: artifacts.dappRegistration.registration?.functionRoot ?? null,
      info: dappInfo.ok ? dappInfo.value : null,
      verifierSnapshot: verifierSnapshot.ok ? verifierSnapshot.value : null,
      contracts: {
        ...(artifacts.dappDeployment.contracts ?? {}),
        privateStateController: privateStateControllerAddress(artifacts),
      },
    },
    bytecodeHashes,
    warnings: [
      canonicalAsset,
      currentRootVectorHash,
      managedStorageAddresses,
      joinToll,
      bridgeOwner,
      dappManagerOwner,
      vaultOwner,
      dappInfo,
      verifierSnapshot,
      channelCreatedResult,
      latestAcceptedTransition,
    ].filter((entry) => !entry.ok).map((entry) => entry.error),
  };
}

async function fetchEtherscanApiSource(address, { chainId, apiKey }) {
  const params = new URLSearchParams({
    chainid: String(chainId),
    module: "contract",
    action: "getsourcecode",
    address,
    apikey: apiKey,
  });
  const url = `${ETHERSCAN_V2_API_URL}?${params.toString()}`;
  let lastError = null;
  for (let attempt = 1; attempt <= ETHERSCAN_RETRY_COUNT; attempt += 1) {
    try {
      const response = await fetch(url);
      const json = await response.json();
      if (!response.ok || json.status === "0") {
        const message = json.result
          ? `${json.message ?? response.status}: ${json.result}`
          : `${json.message ?? response.status}`;
        lastError = new Error(`Etherscan getsourcecode failed: ${message}`);
        if (message.includes("Missing/Invalid API Key")) break;
      } else {
        const result = Array.isArray(json.result) ? json.result[0] : null;
        return {
          address,
          contractName: result?.ContractName ?? null,
          compilerVersion: result?.CompilerVersion ?? null,
          proxy: result?.Proxy ?? null,
          implementation: result?.Implementation ?? null,
          verified: Boolean(result?.SourceCode && String(result.SourceCode).trim().length > 0),
          explorerUrl: `${ETHERSCAN_BASE_URL}/address/${address}#code`,
          checkedVia: "etherscan-api",
        };
      }
    } catch (error) {
      lastError = error;
    }
    if (attempt < ETHERSCAN_RETRY_COUNT) {
      await sleep(ETHERSCAN_RETRY_DELAY_MS * attempt);
    }
  }
  throw lastError ?? new Error("Etherscan getsourcecode failed");
}

async function fetchEtherscanHtmlVerification(address, { chainId }) {
  if (chainId !== 1) {
    throw new Error(`Etherscan HTML fallback is only configured for Ethereum mainnet, got chain ID ${chainId}.`);
  }
  const explorerUrl = `${ETHERSCAN_BASE_URL}/address/${address}#code`;
  const response = await fetch(explorerUrl);
  const html = await response.text();
  if (!response.ok) {
    throw new Error(`Etherscan HTML fallback failed: ${response.status}`);
  }
  const verified = /Contract:\s*Verified/i.test(html) || /Source Code Verified/i.test(html);
  const unverified = /Contract:\s*Unverified/i.test(html) || /Verify and Publish/i.test(html);
  if (!verified && !unverified) {
    throw new Error("Etherscan HTML fallback could not classify source verification status.");
  }
  return {
    address,
    contractName: null,
    compilerVersion: null,
    proxy: null,
    implementation: null,
    verified,
    explorerUrl,
    checkedVia: "etherscan-html",
    verificationStatusSource: verified ? "html-verified" : "html-unverified",
  };
}

async function buildSourceVerification({ args, artifacts, onchain }) {
  if (args.skipEtherscan) {
    return { status: "skipped", warning: "Etherscan source verification checks skipped." };
  }
  const apiKey = resolveEtherscanApiKey();
  const warnings = [];
  if (!apiKey) {
    warnings.push("Missing Etherscan API key; falling back to Etherscan HTML source status pages.");
  }
  const addresses = {
    bridgeCore: artifacts.bridge.bridgeCore,
    bridgeCoreImplementation: artifacts.bridge.bridgeCoreImplementation,
    dAppManager: artifacts.bridge.dAppManager,
    dAppManagerImplementation: artifacts.bridge.dAppManagerImplementation,
    bridgeTokenVault: artifacts.bridge.bridgeTokenVault,
    bridgeTokenVaultImplementation: artifacts.bridge.bridgeTokenVaultImplementation,
    channelManager: onchain.channel.manager,
    channelBridgeTokenVault: onchain.channel.bridgeTokenVault,
    privateStateController: onchain.dapp.contracts.privateStateController,
    l2AccountingVault: onchain.dapp.contracts.l2AccountingVault,
    grothVerifier: artifacts.bridge.grothVerifier,
    tokamakVerifier: artifacts.bridge.tokamakVerifier,
  };
  const entriesByAddress = new Map();
  async function fetchSourceStatus(address) {
    const normalized = ethers.getAddress(address);
    const cacheKey = normalized.toLowerCase();
    if (!entriesByAddress.has(cacheKey)) {
      entriesByAddress.set(cacheKey, (async () => {
        if (apiKey) {
          try {
            return await fetchEtherscanApiSource(normalized, {
              chainId: args.chainId,
              apiKey,
            });
          } catch (error) {
            warnings.push(`${normalized}: ${error.message}; falling back to Etherscan HTML source status page.`);
          }
        }
        try {
          return await fetchEtherscanHtmlVerification(normalized, { chainId: args.chainId });
        } catch (error) {
          return {
            address: normalized,
            verified: null,
            error: error.message,
            explorerUrl: `${ETHERSCAN_BASE_URL}/address/${normalized}#code`,
          };
        }
      })());
    }
    return entriesByAddress.get(cacheKey);
  }
  const entries = {};
  for (const [name, address] of Object.entries(addresses)) {
    if (!address) continue;
    entries[name] = await fetchSourceStatus(address);
  }
  const uncheckedOrFailedAddresses = Object.values(entries).filter((entry) => entry.verified !== true);
  return {
    status: uncheckedOrFailedAddresses.length === 0 ? "ok" : "partial",
    entries,
    allCheckedAddressesVerified: uncheckedOrFailedAddresses.length === 0,
    uncheckedOrFailedAddresses,
    warnings,
    warning: warnings.length > 0 ? warnings.join(" ") : undefined,
  };
}

async function readDriveJson(drive, fileId) {
  const response = await drive.files.get({ fileId, alt: "media" }, { responseType: "text" });
  return typeof response.data === "string" ? JSON.parse(response.data) : response.data;
}

async function readDriveFileMetadata(drive, folderId, name) {
  const file = await findChildFileMetadata(drive, folderId, name);
  if (!file) return null;
  const metadata = await drive.files.get({
    fileId: file.id,
    fields: "id,name,mimeType,size,md5Checksum,modifiedTime,webViewLink",
  });
  return metadata.data;
}

async function buildDriveArtifacts({ args, artifacts }) {
  if (args.skipDrive) {
    return { status: "skipped", warning: "Google Drive artifact metadata read skipped." };
  }
  const folderId = args.driveFolderId ?? process.env.TOKAMAK_MPC_DRIVE_FOLDER_ID;
  if (!folderId) throw new Error("Missing Google Drive folder ID. Set TOKAMAK_MPC_DRIVE_FOLDER_ID or pass --drive-folder-id.");
  const config = resolveDriveUploadConfigWithFolderId(folderId);
  const drive = await createDriveClient(config);
  const artifactIndexFile = await findChildFileMetadata(drive, folderId, "artifact-index.json");
  const artifactIndex = artifactIndexFile ? await readDriveJson(drive, artifactIndexFile.id) : null;
  const chainFolderId = await findChildFolderId(drive, folderId, `chain-id-${args.chainId}`);
  const bridgeRootId = chainFolderId ? await findChildFolderId(drive, chainFolderId, "bridge") : null;
  const dappsRootId = chainFolderId ? await findChildFolderId(drive, chainFolderId, "dapps") : null;
  const dappRootId = dappsRootId ? await findChildFolderId(drive, dappsRootId, args.dapp) : null;
  const bridgeFolderName = path.basename(artifacts.paths.bridgeDir);
  const dappFolderName = path.basename(artifacts.paths.dappDir);
  const bridgeFolderId = bridgeRootId ? await findChildFolderId(drive, bridgeRootId, bridgeFolderName) : null;
  const dappFolderId = dappRootId ? await findChildFolderId(drive, dappRootId, dappFolderName) : null;
  const bridgeFiles = bridgeFolderId
    ? await Promise.all([
      `bridge.${args.chainId}.json`,
      `bridge-abi-manifest.${args.chainId}.json`,
    ].map((name) => readDriveFileMetadata(drive, bridgeFolderId, name)))
    : [];
  const dappFiles = dappFolderId
    ? await Promise.all([
      `deployment.${args.chainId}.latest.json`,
      `dapp-registration.${args.chainId}.json`,
      `storage-layout.${args.chainId}.latest.json`,
      "PrivateStateController.callable-abi.json",
      "L2AccountingVault.callable-abi.json",
    ].map((name) => readDriveFileMetadata(drive, dappFolderId, name)))
    : [];
  return {
    status: "ok",
    rootFolderId: folderId,
    rootFolderUrl: config.folderUrl,
    artifactIndex,
    chainFolderId,
    bridgeFolder: { name: bridgeFolderName, id: bridgeFolderId, files: bridgeFiles.filter(Boolean) },
    dappFolder: { name: dappFolderName, id: dappFolderId, files: dappFiles.filter(Boolean) },
    siblingBridgeFolders: bridgeRootId ? await listChildFolders(drive, bridgeRootId) : [],
    siblingDappFolders: dappRootId ? await listChildFolders(drive, dappRootId) : [],
  };
}

function ifaceEvents(abi) {
  const iface = new Interface(abi);
  return Object.values(iface.fragments)
    .filter((fragment) => fragment.type === "event")
    .map((fragment) => ({
      name: fragment.name,
      signature: fragment.format(),
      topic0: ethers.id(fragment.format()),
      indexedFields: fragment.inputs.filter((input) => input.indexed).map((input) => ({ name: input.name, type: input.type })),
      nonIndexedFields: fragment.inputs.filter((input) => !input.indexed).map((input) => ({ name: input.name, type: input.type })),
    }));
}

function eventByName(abi, name) {
  return ifaceEvents(abi).find((event) => event.name === name) ?? null;
}

function eventEntry({
  checklistItem,
  observableAs,
  artifactName,
  contractAddress,
  abi,
  eventName,
  monitoringMeaning,
  knownFromEvent,
  notKnownFromEvent,
}) {
  const event = eventName ? eventByName(abi, eventName) : null;
  return {
    checklistItem,
    observableAs,
    artifactName,
    contractAddress,
    eventName: eventName ?? null,
    availability: event ? "event-present" : "no-dedicated-event",
    signature: event?.signature ?? null,
    topic0: event?.topic0 ?? null,
    indexedFields: event?.indexedFields ?? [],
    nonIndexedFields: event?.nonIndexedFields ?? [],
    explorerQueryExample: contractAddress ? `${ETHERSCAN_BASE_URL}/address/${contractAddress}#events` : null,
    knownFromEvent,
    notKnownFromEvent,
    monitoringMeaning,
  };
}

function buildEventCoverage({ artifacts, onchain }) {
  const bridgeAbis = getBridgeAbis(artifacts);
  const dappControllerAbi = readPrivateStateContractAbi(
    "PrivateStateController",
    PRIVATE_STATE_EVENT_ABIS.privateStateController,
  );
  const l2AccountingAbi = readPrivateStateContractAbi(
    "L2AccountingVault",
    PRIVATE_STATE_EVENT_ABIS.l2AccountingVault,
  );
  const addresses = {
    bridgeCore: artifacts.bridge.bridgeCore,
    dAppManager: artifacts.bridge.dAppManager,
    bridgeTokenVault: artifacts.bridge.bridgeTokenVault,
    channelManager: onchain.channel.manager,
    privateStateController: onchain.dapp.contracts.privateStateController,
    l2AccountingVault: onchain.dapp.contracts.l2AccountingVault,
  };
  return [
    eventEntry({
      checklistItem: "bridge deposit event",
      observableAs: "AssetsFunded",
      artifactName: "bridgeTokenVault",
      contractAddress: addresses.bridgeTokenVault,
      abi: bridgeAbis.bridgeTokenVault,
      eventName: "AssetsFunded",
      knownFromEvent: "L1 funder and funded amount.",
      notKnownFromEvent: "Later private note ownership or private transfer path.",
      monitoringMeaning: "Detects value entering bridge custody.",
    }),
    eventEntry({
      checklistItem: "bridge withdraw event",
      observableAs: "AssetsClaimed",
      artifactName: "bridgeTokenVault",
      contractAddress: addresses.bridgeTokenVault,
      abi: bridgeAbis.bridgeTokenVault,
      eventName: "AssetsClaimed",
      knownFromEvent: "L1 claimant and claimed amount.",
      notKnownFromEvent: "Complete private-state path that led to the claim.",
      monitoringMeaning: "Detects value leaving bridge custody.",
    }),
    eventEntry({
      checklistItem: "channel created event",
      observableAs: "ChannelCreated",
      artifactName: "bridgeCore",
      contractAddress: addresses.bridgeCore,
      abi: bridgeAbis.bridgeCore,
      eventName: "ChannelCreated",
      knownFromEvent: "Channel ID, DApp ID, channel manager, and vault address.",
      notKnownFromEvent: "Future user activity inside the channel.",
      monitoringMeaning: "Identifies canonical channel deployment.",
    }),
    eventEntry({
      checklistItem: "channel joined event",
      observableAs: "ChannelTokenVaultIdentityRegistered and ChannelJoinTollPaid",
      artifactName: "channelManager",
      contractAddress: addresses.channelManager,
      abi: bridgeAbis.channelManager,
      eventName: "ChannelTokenVaultIdentityRegistered",
      knownFromEvent: "L1 address, channel-local L2 address, leaf index, join toll, and note-receive public key material.",
      notKnownFromEvent: "Wallet secret, spending key, note-receive private key, or private note history.",
      monitoringMeaning: "Detects channel participation and identity registration.",
    }),
    eventEntry({
      checklistItem: "L1/L2 identity registration event",
      observableAs: "ChannelTokenVaultIdentityRegistered",
      artifactName: "channelManager",
      contractAddress: addresses.channelManager,
      abi: bridgeAbis.channelManager,
      eventName: "ChannelTokenVaultIdentityRegistered",
      knownFromEvent: "Public L1-to-channel-L2 binding.",
      notKnownFromEvent: "Private key material or all private-state actions by that identity.",
      monitoringMeaning: "Provides the public registration anchor for channel-vault accounting.",
    }),
    eventEntry({
      checklistItem: "note-receive public key registration event",
      observableAs: "ChannelTokenVaultIdentityRegistered",
      artifactName: "channelManager",
      contractAddress: addresses.channelManager,
      abi: bridgeAbis.channelManager,
      eventName: "ChannelTokenVaultIdentityRegistered",
      knownFromEvent: "Public note-receive key coordinates included at registration.",
      notKnownFromEvent: "Note-receive private key or decrypted note contents.",
      monitoringMeaning: "Documents the public delivery key surface without creating a viewing backdoor.",
    }),
    eventEntry({
      checklistItem: "deposit-channel event",
      observableAs: "StorageWriteObserved and CurrentRootVectorObserved",
      artifactName: "bridgeTokenVault",
      contractAddress: addresses.bridgeTokenVault,
      abi: bridgeAbis.bridgeTokenVault,
      eventName: "StorageWriteObserved",
      knownFromEvent: "Vault storage address, storage key, and new value emitted by an accepted update.",
      notKnownFromEvent: "Full private-state context outside the vault accounting domain.",
      monitoringMeaning: "Detects accepted channel-vault storage movement.",
    }),
    eventEntry({
      checklistItem: "withdraw-channel event",
      observableAs: "StorageWriteObserved, ChannelExitRefunded, AssetsClaimed",
      artifactName: "bridgeTokenVault",
      contractAddress: addresses.bridgeTokenVault,
      abi: bridgeAbis.bridgeTokenVault,
      eventName: "ChannelExitRefunded",
      knownFromEvent: "L1 address, channel ID, refunded amount, and refund basis points.",
      notKnownFromEvent: "Complete private note path before redeeming into liquid balance.",
      monitoringMeaning: "Detects exit-accounting and refund events around channel withdrawal paths.",
    }),
    eventEntry({
      checklistItem: "note commitment created event",
      observableAs: "CurrentRootVectorObserved and StorageKeyObserved",
      artifactName: "channelManager",
      contractAddress: addresses.channelManager,
      abi: bridgeAbis.channelManager,
      eventName: "CurrentRootVectorObserved",
      knownFromEvent: "Accepted root movement for managed storage domains.",
      notKnownFromEvent: "Plain note value, owner, recipient, or salt.",
      monitoringMeaning: "Detects accepted commitment-domain changes without exposing note plaintext.",
    }),
    eventEntry({
      checklistItem: "nullifier used event",
      observableAs: "CurrentRootVectorObserved and StorageKeyObserved",
      artifactName: "privateStateController",
      contractAddress: addresses.privateStateController,
      abi: dappControllerAbi,
      eventName: "StorageKeyObserved",
      knownFromEvent: "Bridge-visible storage key observation emitted by the DApp.",
      notKnownFromEvent: "Plain linkage from nullifier to note owner without selective disclosure.",
      monitoringMeaning: "Detects public storage-key surface for private-state transitions.",
    }),
    eventEntry({
      checklistItem: "encrypted note-delivery event",
      observableAs: "NoteValueEncrypted",
      artifactName: "privateStateController",
      contractAddress: addresses.privateStateController,
      abi: dappControllerAbi,
      eventName: "NoteValueEncrypted",
      knownFromEvent: "Encrypted note payload tuple.",
      notKnownFromEvent: "Plain note value or recipient semantics without recipient-side secrets.",
      monitoringMeaning: "Detects encrypted delivery publication for wallet-local recovery.",
    }),
    eventEntry({
      checklistItem: "proof accepted event",
      observableAs: "CurrentRootVectorObserved",
      artifactName: "channelManager",
      contractAddress: addresses.channelManager,
      abi: bridgeAbis.channelManager,
      eventName: "CurrentRootVectorObserved",
      knownFromEvent: "Accepted root-vector hash and root vector.",
      notKnownFromEvent: "Full witness or private execution trace.",
      monitoringMeaning: "Detects successful proof-backed state acceptance.",
    }),
    eventEntry({
      checklistItem: "storage root / commitment root update event",
      observableAs: "CurrentRootVectorObserved",
      artifactName: "channelManager",
      contractAddress: addresses.channelManager,
      abi: bridgeAbis.channelManager,
      eventName: "CurrentRootVectorObserved",
      knownFromEvent: "New accepted commitment head.",
      notKnownFromEvent: "Plain semantic interpretation of every changed leaf.",
      monitoringMeaning: "Tracks canonical channel state movement.",
    }),
    eventEntry({
      checklistItem: "policy snapshot event",
      observableAs: "ChannelCreated plus channel getter state",
      artifactName: "bridgeCore",
      contractAddress: addresses.bridgeCore,
      abi: bridgeAbis.bridgeCore,
      eventName: "ChannelCreated",
      knownFromEvent: "Channel creation anchor; full snapshot is read from channel and artifact state.",
      notKnownFromEvent: "Off-chain review conclusions.",
      monitoringMeaning: "Anchors the channel policy snapshot used in the generated policy file.",
    }),
    eventEntry({
      checklistItem: "verifier or metadata update event",
      observableAs: "GrothVerifierUpdated, TokamakVerifierUpdated, DAppMetadataUpdated, DAppMetadataDigestUpdated",
      artifactName: "dAppManager",
      contractAddress: addresses.dAppManager,
      abi: bridgeAbis.dAppManager,
      eventName: "DAppMetadataUpdated",
      knownFromEvent: "DApp ID and metadata-shape update.",
      notKnownFromEvent: "Full source-review rationale.",
      monitoringMeaning: "Detects future-channel DApp policy changes.",
    }),
    eventEntry({
      checklistItem: "proxy upgrade event",
      observableAs: "Upgraded",
      artifactName: "bridgeCore",
      contractAddress: addresses.bridgeCore,
      abi: bridgeAbis.bridgeCore,
      eventName: "Upgraded",
      knownFromEvent: "New implementation address.",
      notKnownFromEvent: "Human review result unless published separately.",
      monitoringMeaning: "Detects shared bridge control-plane implementation changes.",
    }),
    {
      checklistItem: "emergency pause or migration event, if exists",
      observableAs: "No current event",
      artifactName: null,
      contractAddress: null,
      eventName: null,
      availability: "not-present-in-current-abi",
      signature: null,
      topic0: null,
      indexedFields: [],
      nonIndexedFields: [],
      explorerQueryExample: null,
      knownFromEvent: "No current emergency pause or migration event exists in the monitored ABI set.",
      notKnownFromEvent: "Not applicable.",
      monitoringMeaning: "If introduced later, this item must be updated with the new event surface.",
    },
  ];
}

function buildContractAddressPack({ args, artifacts, onchain, sourceVerification, eventCoverage }) {
  const bridge = artifacts.bridge;
  const storageLayoutHash = fileKeccak256(artifacts.paths.dappStorageLayoutPath);
  return {
    generatedAt: new Date().toISOString(),
    chainId: args.chainId,
    chain: args.chainId === 1 ? "ethereum-mainnet" : `chain-id-${args.chainId}`,
    canonicalTonContractAddress: onchain.bridge.canonicalAsset,
    bridgeCoreAddress: bridge.bridgeCore,
    l1TokenVaultAddress: bridge.bridgeTokenVault,
    channelManagerAddress: onchain.channel.manager,
    channel: {
      name: onchain.channel.name,
      id: onchain.channel.id,
      creationTxHash: onchain.channel.createdTxHash,
      creationBlockNumber: onchain.channel.createdBlockNumber,
      latestAcceptedTransition: onchain.channel.latestAcceptedTransition,
      latestPolicyVersion: "channel-creation-snapshot-v1",
      leader: onchain.channel.leader,
      operator: onchain.channel.operator,
    },
    dapp: {
      label: args.dapp,
      id: onchain.dapp.id,
      registrationTxHash: onchain.dapp.registrationTxHash,
      registrationBlockNumber: onchain.dapp.registrationBlockNumber,
      metadataDigest: onchain.dapp.metadataDigest,
      functionRoot: onchain.dapp.functionRoot,
      storageLayoutHash,
      storageLayoutHashAlgorithm: "keccak256(file bytes)",
    },
    verifierContractAddresses: {
      grothVerifier: bridge.grothVerifier,
      tokamakVerifier: bridge.tokamakVerifier,
    },
    proxyAddresses: {
      bridgeCore: bridge.bridgeCore,
      dAppManager: bridge.dAppManager,
      l1TokenVault: bridge.bridgeTokenVault,
    },
    implementationAddresses: {
      bridgeCore: bridge.bridgeCoreImplementation,
      dAppManager: bridge.dAppManagerImplementation,
      l1TokenVault: bridge.bridgeTokenVaultImplementation,
      channelManager: onchain.channel.manager,
      privateStateController: onchain.dapp.contracts.privateStateController,
      l2AccountingVault: onchain.dapp.contracts.l2AccountingVault,
    },
    proxyAdminAddresses: Object.fromEntries(
      Object.entries(onchain.bridge.proxyState).map(([key, state]) => [key, state.admin]),
    ),
    proxyAdminNotes: Object.fromEntries(
      Object.entries(onchain.bridge.proxyState).map(([key, state]) => [key, state.adminStatus]),
    ),
    ownerAdminMultisigTimelockAddresses: {
      owners: onchain.bridge.owners,
      deployer: bridge.deployer ?? null,
      configuredOwner: bridge.owner ?? null,
      multisig: null,
      timelock: null,
      note: "Current artifacts expose a single owner address. No multisig or timelock address is recorded in the deployment artifact.",
    },
    treasuryOrFeeRecipientAddresses: {
      channelJoinTollRecipient: onchain.channel.leader,
      bridgeTreasury: null,
      note: "The current channel join toll is channel-local. No separate treasury or fee-recipient address is recorded in the deployment artifact.",
    },
    deploymentBlocks: {
      dappRegistrationBlockNumber: onchain.dapp.registrationBlockNumber,
      channelCreationBlockNumber: onchain.channel.createdBlockNumber,
      bridgeProxyDeploymentBlockNumber: null,
      note: "Plain RPC does not expose contract creation block discovery without an indexer. Channel and DApp deployment anchors are included where available.",
    },
    deployedGitCommitHash: bridge.sourceCode?.repository?.commit ?? bridge.sourceCode?.commit ?? null,
    npmPackageVersions: {
      privateStateCliAtDappRegistration: artifacts.dappRegistration.artifactSources?.privateStateCli?.version ?? null,
      bridgePackageVersion: bridge.package?.version ?? null,
      grothVerifierCompatibleBackendVersion: bridge.grothVerifierCompatibleBackendVersion ?? null,
      tokamakVerifierCompatibleBackendVersion: bridge.tokamakVerifierCompatibleBackendVersion ?? null,
    },
    sourceVerificationStatus: sourceVerification,
    abiLinks: {
      bridgeAbiManifestLocalPath: path.relative(REPO_ROOT, artifacts.paths.bridgeAbiManifestPath),
      privateStateControllerCallableAbiLocalPath: path.relative(REPO_ROOT, path.join(artifacts.paths.dappDir, "PrivateStateController.callable-abi.json")),
      l2AccountingVaultCallableAbiLocalPath: path.relative(REPO_ROOT, path.join(artifacts.paths.dappDir, "L2AccountingVault.callable-abi.json")),
    },
    bytecodeHashes: onchain.bytecodeHashes,
    monitoredEventChecklist: eventCoverage.map((event) => ({
      checklistItem: event.checklistItem,
      observableAs: event.observableAs,
      contractAddress: event.contractAddress,
      eventName: event.eventName,
      availability: event.availability,
      topic0: event.topic0,
    })),
  };
}

function buildChannelPolicySnapshot({ args, artifacts, onchain }) {
  const storageLayoutHash = fileKeccak256(artifacts.paths.dappStorageLayoutPath);
  const latestPolicyVersion = {
    label: "channel-creation-snapshot-v1",
    version: 1,
    status: "immutable",
    sourceEvent: "ChannelCreated",
    transactionHash: onchain.channel.createdTxHash,
    blockNumber: onchain.channel.createdBlockNumber,
    dappMetadataDigestSchema: onchain.channel.dappMetadataDigestSchema,
    dappMetadataDigest: onchain.channel.dappMetadataDigest,
    dappFunctionRoot: onchain.dapp.functionRoot,
  };
  return {
    generatedAt: new Date().toISOString(),
    chainId: args.chainId,
    channelName: onchain.channel.name,
    channelId: onchain.channel.id,
    channelManager: onchain.channel.manager,
    bridgeTokenVault: onchain.channel.bridgeTokenVault,
    leader: onchain.channel.leader,
    operator: onchain.channel.operator,
    dappId: onchain.channel.dappId,
    asset: onchain.channel.asset,
    joinToll: onchain.channel.joinToll,
    currentRootVectorHash: onchain.channel.currentRootVectorHash,
    latestAcceptedTransition: onchain.channel.latestAcceptedTransition,
    managedStorageAddresses: onchain.channel.managedStorageAddresses,
    workspaceMirrorUrl: onchain.channel.workspaceMirrorUrl,
    aPubBlockHash: onchain.channel.aPubBlockHash,
    dappMetadataDigestSchema: onchain.channel.dappMetadataDigestSchema,
    dappMetadataDigest: onchain.channel.dappMetadataDigest,
    dappFunctionRoot: onchain.dapp.functionRoot,
    verifierSnapshot: onchain.dapp.verifierSnapshot,
    storageLayoutSource: path.relative(REPO_ROOT, artifacts.paths.dappStorageLayoutPath),
    storageLayoutHash,
    storageLayoutHashAlgorithm: "keccak256(file bytes)",
    latestPolicyVersion,
    policyExplanationSource: "bridge/docs/whitepaper.md#82-policy-surfaces",
  };
}

function markdownTable(headers, rows) {
  return [
    `| ${headers.join(" | ")} |`,
    `| ${headers.map(() => "---").join(" | ")} |`,
    ...rows.map((row) => `| ${row.map((cell) => String(cell ?? "").replaceAll("\n", "<br>")).join(" | ")} |`),
  ].join("\n");
}

function buildObservabilityMatrix(eventCoverage) {
  return `# Private-State Observability Matrix

This file maps the Monitoring Packet event checklist to the current public event surface. The policy
meaning of this matrix is described in \`bridge/docs/whitepaper.md\`; this file records
the current ABI-derived monitoring details.

${markdownTable([
    "Checklist item",
    "Observable as",
    "Contract",
    "Event",
    "Availability",
    "Indexed fields",
    "Non-indexed fields",
    "Explorer query",
    "Known from event",
    "Not known from event",
    "Monitoring meaning",
  ], eventCoverage.map((event) => [
    event.checklistItem,
    event.observableAs,
    event.artifactName ?? "N/A",
    event.eventName ?? "N/A",
    event.availability,
    event.indexedFields.map((field) => `${field.name}:${field.type}`).join(", ") || "None",
    event.nonIndexedFields.map((field) => `${field.name}:${field.type}`).join(", ") || "None",
    event.explorerQueryExample ?? "N/A",
    event.knownFromEvent,
    event.notKnownFromEvent,
    event.monitoringMeaning,
  ]))}
`;
}

function addressLink(address) {
  return address ? `[${address}](${ETHERSCAN_BASE_URL}/address/${address})` : "";
}

function buildAdminPolicy({ pack }) {
  const ownerRows = Object.entries(pack.ownerAdminMultisigTimelockAddresses.owners)
    .map(([name, owner]) => [name, addressLink(owner)]);
  const proxyRows = Object.entries(pack.proxyAddresses).map(([name, address]) => [
    name,
    addressLink(address),
    addressLink(pack.implementationAddresses[name === "l1TokenVault" ? "l1TokenVault" : name]),
    addressLink(pack.proxyAdminAddresses[name === "l1TokenVault" ? "bridgeTokenVault" : name]),
    pack.proxyAdminNotes[name === "l1TokenVault" ? "bridgeTokenVault" : name],
  ]);
  return `# Admin Wallets and Upgrade Policy

This file records the current on-chain owner and proxy-slot state for the monitored mainnet bridge
deployment. The external policy model for upgrades and per-channel immutability is described in
\`bridge/docs/whitepaper.md\`.

## Owners

${markdownTable(["Contract", "Owner"], ownerRows)}

## Proxies

${markdownTable(["Proxy", "Address", "Implementation", "EIP-1967 admin slot", "Admin slot status"], proxyRows)}

## Notes

- Current root bridge proxies use the UUPS proxy pattern.
- An empty EIP-1967 admin slot is expected for the current UUPS deployment.
- Existing channel policy snapshots are not rewritten by later DApp metadata or bridge verifier default changes.
`;
}

function buildCoverageReport({ pack, eventCoverage }) {
  const contractAddressItems = [
    ["chain ID", pack.chainId],
    ["canonical TON contract address", pack.canonicalTonContractAddress],
    ["bridge core address", pack.bridgeCoreAddress],
    ["L1 token vault address", pack.l1TokenVaultAddress],
    ["ChannelManager address", pack.channelManagerAddress],
    ["channel id/name", pack.channel?.id && pack.channel?.name],
    ["channel creation tx hash", pack.channel?.creationTxHash],
    ["private-state DApp id", pack.dapp?.id],
    ["private-state DApp registration tx hash", pack.dapp?.registrationTxHash],
    ["verifier contract addresses", pack.verifierContractAddresses?.grothVerifier && pack.verifierContractAddresses?.tokamakVerifier],
    ["proxy addresses", Object.values(pack.proxyAddresses ?? {}).every(Boolean)],
    ["implementation addresses", Object.values(pack.implementationAddresses ?? {}).some(Boolean)],
    ["proxy admin addresses", Object.prototype.hasOwnProperty.call(pack, "proxyAdminAddresses")],
    ["owner/admin/multisig/timelock addresses", pack.ownerAdminMultisigTimelockAddresses?.owners],
    ["treasury or fee recipient addresses", pack.treasuryOrFeeRecipientAddresses],
    ["channel leader/operator address", pack.channel?.leader],
    ["deployment block number", pack.deploymentBlocks?.dappRegistrationBlockNumber || pack.deploymentBlocks?.channelCreationBlockNumber],
    ["deployed Git commit hash", pack.deployedGitCommitHash],
    ["NPM package version used for deployment/proving/CLI", pack.npmPackageVersions],
    ["source verification status", pack.sourceVerificationStatus?.status === "ok"],
    ["ABI links", pack.abiLinks],
    ["bytecode hash", pack.bytecodeHashes],
  ];
  return {
    generatedAt: new Date().toISOString(),
    contractAddressPack: contractAddressItems.map(([item, value]) => ({
      item,
      status: value ? "covered" : "needs-review",
    })),
    eventAndMonitoringMap: eventCoverage.map((event) => ({
      item: event.checklistItem,
      status: event.availability === "not-present-in-current-abi" ? "not-present" : "covered",
      observableAs: event.observableAs,
    })),
  };
}

function buildSummary({ args, artifacts, onchain, driveArtifacts, sourceVerification, publicFiles, internalFiles }) {
  return {
    generatedAt: new Date().toISOString(),
    chainId: args.chainId,
    dapp: args.dapp,
    channel: args.channel,
    bridgeArtifactDirectory: path.relative(REPO_ROOT, artifacts.paths.bridgeDir),
    dappArtifactDirectory: path.relative(REPO_ROOT, artifacts.paths.dappDir),
    rpcCurrentBlock: onchain.rpc.currentBlock,
    driveStatus: driveArtifacts.status,
    sourceVerificationStatus: sourceVerification.status,
    warnings: [
      ...(onchain.warnings ?? []),
      ...(driveArtifacts.warning ? [driveArtifacts.warning] : []),
      ...(sourceVerification.warning ? [sourceVerification.warning] : []),
    ],
    publicFiles,
    internalFiles,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    printHelp();
    return;
  }
  loadEnv();
  const publicDir = PUBLIC_OUTPUT_DIR;
  const internalDir = args.output;
  fs.rmSync(internalDir, { recursive: true, force: true });
  fs.mkdirSync(publicDir, { recursive: true });
  fs.mkdirSync(internalDir, { recursive: true });

  const artifacts = loadLocalArtifacts(args);
  const onchain = await buildOnchainSnapshot({ args, artifacts, rpcUrl: resolveRpcUrl(args) });

  let driveArtifacts;
  try {
    driveArtifacts = await buildDriveArtifacts({ args, artifacts });
  } catch (error) {
    if (!args.allowMissingDrive) throw error;
    driveArtifacts = { status: "unavailable", warning: error.message };
  }

  let sourceVerification;
  try {
    sourceVerification = await buildSourceVerification({ args, artifacts, onchain });
  } catch (error) {
    if (!args.allowMissingEtherscan) throw error;
    sourceVerification = { status: "unavailable", warning: error.message };
  }

  const eventCoverage = buildEventCoverage({ artifacts, onchain });
  const pack = buildContractAddressPack({ args, artifacts, onchain, sourceVerification, eventCoverage });
  const channelPolicy = buildChannelPolicySnapshot({ args, artifacts, onchain });
  const coverageReport = buildCoverageReport({ pack, eventCoverage });

  const publicOutputs = {
    "TPAC-Contract-Addresses.json": pack,
    [`${slugify(args.channel)}-Policy-Snapshot.json`]: channelPolicy,
    "Private-State-Observability-Matrix.md": buildObservabilityMatrix(eventCoverage),
    "Admin-Wallets-and-Upgrade-Policy.md": buildAdminPolicy({ pack }),
  };
  const internalOutputs = {
    "event-monitoring-map.json": eventCoverage,
    "drive-artifacts.json": driveArtifacts,
    "coverage-report.json": coverageReport,
  };

  const publicFiles = [];
  for (const [fileName, content] of Object.entries(publicOutputs)) {
    const filePath = path.join(publicDir, fileName);
    fileName.endsWith(".json") ? writeJson(filePath, content) : writeText(filePath, content);
    publicFiles.push(path.relative(REPO_ROOT, filePath));
  }
  const internalFiles = [];
  for (const [fileName, content] of Object.entries(internalOutputs)) {
    const filePath = path.join(internalDir, fileName);
    writeJson(filePath, content);
    internalFiles.push(path.relative(REPO_ROOT, filePath));
  }
  const packetSummaryFile = path.relative(REPO_ROOT, path.join(internalDir, "packet-summary.json"));
  internalFiles.push(packetSummaryFile);
  const summary = buildSummary({ args, artifacts, onchain, driveArtifacts, sourceVerification, publicFiles, internalFiles });
  writeJson(path.join(internalDir, "packet-summary.json"), summary);

  console.log(`Wrote public monitoring packet files to ${path.relative(REPO_ROOT, publicDir)}`);
  for (const file of publicFiles) console.log(`- ${file}`);
  console.log(`Wrote internal validation files to ${path.relative(REPO_ROOT, internalDir)}`);
  for (const file of internalFiles) console.log(`- ${file}`);
}

main().catch((error) => {
  console.error(error.stack ?? error.message);
  process.exitCode = 1;
});
