#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { parse as parseDotenv } from "dotenv";
import { ethers } from "ethers";
import { resolveAppNetwork } from "@tokamak-private-dapps/common-library/network-config";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "..", "..");
const bridgeRoot = path.join(projectRoot, "bridge");
const envFile = process.env.BRIDGE_ENV_FILE || path.join(projectRoot, ".env");
const ETHERSCAN_V2_API_URL = "https://api.etherscan.io/v2/api";
const CHANNEL_CREATED_EVENT =
  "event ChannelCreated(uint256 indexed channelId,uint256 indexed dappId,address manager,address bridgeTokenVault)";
const CHANNEL_MANAGER_CONTRACT = "src/ChannelManager.sol:ChannelManager";
const CHANNEL_MANAGER_ARTIFACT_PATH = path.join(
  bridgeRoot,
  "out",
  "ChannelManager.sol",
  "ChannelManager.json",
);
const DEFAULT_CONFIRMATIONS = 12;
const DEFAULT_LOOKBACK_BLOCKS = 64;
const DEFAULT_CHUNK_SIZE = 20_000;
const DEFAULT_LOG_SOURCE = "etherscan";
const DEFAULT_ETHERSCAN_LOG_PAGE_SIZE = 1_000;
const DEFAULT_LOG_RETRIES = 6;
const DEFAULT_LOG_RETRY_DELAY_MS = 2_000;
const DEFAULT_REQUEST_DELAY_MS = 0;

function fail(message) {
  throw new Error(message);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function run(command, args, { cwd = projectRoot, env = process.env } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: "inherit",
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    fail(`${command} ${args.join(" ")} exited with status ${result.status ?? "unknown"}`);
  }
}

function usage() {
  console.log(`Usage:
  node bridge/scripts/verify-channel-managers.mjs --network <mainnet|sepolia> [options]

Options:
  --network <name>      Network to scan. Supported values: mainnet, sepolia
  --deployment-path <path>
                        Bridge deployment artifact. Defaults to the latest bridge deployment artifact.
  --state-path <path>   Verification checkpoint path. Defaults to deployment/chain-id-*/bridge state.
  --from-block <block>  Override scan start block
  --to-block <block>    Override scan end block. Defaults to latest finalized by --confirmations
  --confirmations <n>   Blocks to lag from latest when --to-block is omitted. Default: ${DEFAULT_CONFIRMATIONS}
  --lookback-blocks <n> Re-scan this many blocks before the previous checkpoint. Default: ${DEFAULT_LOOKBACK_BLOCKS}
  --log-source <source> ChannelCreated log source. Supported values: etherscan, rpc. Default: ${DEFAULT_LOG_SOURCE}
  --chunk-size <n>      RPC log scan chunk size. Default: ${DEFAULT_CHUNK_SIZE}
  --request-delay-ms <n>
                        Delay between log scan requests. Default: ${DEFAULT_REQUEST_DELAY_MS}
  --log-retries <n>     Retry count for transient log scan failures. Default: ${DEFAULT_LOG_RETRIES}
  --log-retry-delay-ms <n>
                        Initial retry delay for log scan failures. Default: ${DEFAULT_LOG_RETRY_DELAY_MS}
  --dry-run             Scan and report without submitting Etherscan verification or writing state
  --refresh             Re-check managers already recorded in the local verification state
  --skip-build          Do not run forge build before extracting constructor args
  --help, -h            Show this help message`);
}

function parseArgs(argv) {
  const options = {
    networkName: null,
    deploymentPath: null,
    statePath: null,
    fromBlock: null,
    toBlock: null,
    confirmations: DEFAULT_CONFIRMATIONS,
    lookbackBlocks: DEFAULT_LOOKBACK_BLOCKS,
    logSource: DEFAULT_LOG_SOURCE,
    chunkSize: DEFAULT_CHUNK_SIZE,
    requestDelayMs: DEFAULT_REQUEST_DELAY_MS,
    logRetries: DEFAULT_LOG_RETRIES,
    logRetryDelayMs: DEFAULT_LOG_RETRY_DELAY_MS,
    dryRun: false,
    refresh: false,
    skipBuild: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    const next = argv[index + 1];
    switch (current) {
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      case "--network":
        options.networkName = requireOptionValue(current, next);
        index += 1;
        break;
      case "--deployment-path":
        options.deploymentPath = requireOptionValue(current, next);
        index += 1;
        break;
      case "--state-path":
        options.statePath = requireOptionValue(current, next);
        index += 1;
        break;
      case "--from-block":
        options.fromBlock = parseBlockNumber(requireOptionValue(current, next), current);
        index += 1;
        break;
      case "--to-block":
        options.toBlock = parseBlockNumber(requireOptionValue(current, next), current);
        index += 1;
        break;
      case "--confirmations":
        options.confirmations = parseNonNegativeInteger(requireOptionValue(current, next), current);
        index += 1;
        break;
      case "--lookback-blocks":
        options.lookbackBlocks = parseNonNegativeInteger(requireOptionValue(current, next), current);
        index += 1;
        break;
      case "--log-source":
        options.logSource = requireOptionValue(current, next);
        if (!["etherscan", "rpc"].includes(options.logSource)) {
          fail(`Unsupported --log-source=${options.logSource}\nSupported values: etherscan, rpc`);
        }
        index += 1;
        break;
      case "--chunk-size":
        options.chunkSize = parsePositiveInteger(requireOptionValue(current, next), current);
        index += 1;
        break;
      case "--request-delay-ms":
        options.requestDelayMs = parseNonNegativeInteger(requireOptionValue(current, next), current);
        index += 1;
        break;
      case "--log-retries":
        options.logRetries = parseNonNegativeInteger(requireOptionValue(current, next), current);
        index += 1;
        break;
      case "--log-retry-delay-ms":
        options.logRetryDelayMs = parseNonNegativeInteger(requireOptionValue(current, next), current);
        index += 1;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--refresh":
        options.refresh = true;
        break;
      case "--skip-build":
        options.skipBuild = true;
        break;
      default:
        fail(`Unknown option: ${current}`);
    }
  }

  if (!options.networkName) {
    fail("Missing required argument: --network <mainnet|sepolia>");
  }
  if (!["mainnet", "sepolia"].includes(options.networkName)) {
    fail(`Unsupported --network=${options.networkName}\nSupported values: mainnet, sepolia`);
  }

  return options;
}

function requireOptionValue(optionName, value) {
  if (!value || value.startsWith("--")) {
    fail(`Missing value for ${optionName}`);
  }
  return value;
}

function parseBlockNumber(value, label) {
  const parsed = parseNonNegativeInteger(value, label);
  if (!Number.isSafeInteger(parsed)) {
    fail(`${label} is too large for a JavaScript-safe block number: ${value}`);
  }
  return parsed;
}

function parseNonNegativeInteger(value, label) {
  if (!/^\d+$/.test(value)) {
    fail(`${label} must be a non-negative integer: ${value}`);
  }
  return Number(value);
}

function parsePositiveInteger(value, label) {
  const parsed = parseNonNegativeInteger(value, label);
  if (parsed <= 0) {
    fail(`${label} must be greater than zero: ${value}`);
  }
  return parsed;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function resolveProjectPath(inputPath) {
  return path.isAbsolute(inputPath) ? inputPath : path.resolve(projectRoot, inputPath);
}

function loadEnvFile() {
  if (!fs.existsSync(envFile)) {
    fail(`Missing ${envFile}\nCreate it from ${path.join(projectRoot, ".env.example")}`);
  }
  const parsed = parseDotenv(fs.readFileSync(envFile));
  for (const [key, value] of Object.entries(parsed)) {
    process.env[key] = value;
  }
}

function readOptionalEnvTrimmed(name) {
  const value = process.env[name]?.trim();
  return value && value.length > 0 ? value : null;
}

function requireEnv(names) {
  for (const name of names) {
    if (!readOptionalEnvTrimmed(name)) {
      fail(`Missing required environment variable: ${name}`);
    }
  }
}

function latestCompleteBridgeDir(rootDir, chainId) {
  if (!fs.existsSync(rootDir)) {
    return "";
  }
  const timestampPattern = /^20\d{6}T\d{6}Z$/;
  return fs.readdirSync(rootDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && timestampPattern.test(entry.name))
    .map((entry) => path.join(rootDir, entry.name))
    .filter((candidateDir) => fs.existsSync(path.join(candidateDir, `bridge.${chainId}.json`)))
    .sort()
    .at(-1) ?? "";
}

function resolveDefaultDeploymentPath(chainId) {
  const bridgeDir = latestCompleteBridgeDir(
    path.join(projectRoot, "deployment", `chain-id-${chainId}`, "bridge"),
    chainId,
  );
  if (!bridgeDir) {
    fail(`No bridge deployment artifact found for chain ID ${chainId}`);
  }
  return path.join(bridgeDir, `bridge.${chainId}.json`);
}

function resolveDefaultStatePath(chainId) {
  return path.join(
    projectRoot,
    "deployment",
    `chain-id-${chainId}`,
    "bridge",
    "channel-manager-verification-state.json",
  );
}

function resolveRpcUrl(networkName, bridgeNetwork) {
  if (process.env.BRIDGE_RPC_URL_OVERRIDE) {
    return process.env.BRIDGE_RPC_URL_OVERRIDE;
  }
  if (networkName === "anvil" && bridgeNetwork.defaultRpcUrl) {
    return bridgeNetwork.defaultRpcUrl;
  }
  requireEnv(["BRIDGE_ALCHEMY_API_KEY"]);
  return `https://${bridgeNetwork.alchemyNetwork}.g.alchemy.com/v2/${process.env.BRIDGE_ALCHEMY_API_KEY}`;
}

function resolveEtherscanApiKey() {
  const apiKey = readOptionalEnvTrimmed("BRIDGE_ETHERSCAN_API_KEY")
    || readOptionalEnvTrimmed("ETHERSCAN_API_KEY");
  if (!apiKey) {
    fail("BRIDGE_ETHERSCAN_API_KEY or ETHERSCAN_API_KEY is required.");
  }
  return apiKey;
}

async function fetchEtherscanJson(
  params,
  { method = "GET", retries = DEFAULT_LOG_RETRIES, retryDelayMs = DEFAULT_LOG_RETRY_DELAY_MS } = {},
) {
  const urlParams = new URLSearchParams(params);
  let lastStatus = null;
  let lastJson = null;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const response = method === "GET"
      ? await fetch(`${ETHERSCAN_V2_API_URL}?${urlParams.toString()}`, { method })
      : await fetch(ETHERSCAN_V2_API_URL, { method, body: urlParams });
    const text = await response.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch {
      fail(`Etherscan returned non-JSON response: ${text}`);
    }
    if (response.ok && !etherscanRetryable(json)) {
      return json;
    }

    lastStatus = response.status;
    lastJson = json;
    if (attempt >= retries) {
      break;
    }

    const delay = retryDelayMs * 2 ** attempt;
    console.log(`Etherscan request throttled; retrying in ${delay}ms (${attempt + 1}/${retries})`);
    await sleep(delay);
  }
  if (lastStatus && lastStatus !== 200) {
    fail(`Etherscan request failed with HTTP ${lastStatus}: ${JSON.stringify(lastJson)}`);
  }
  fail(`Etherscan request failed: ${JSON.stringify(lastJson)}`);
}

async function getContractCreation(address, { chainId, etherscanApiKey }) {
  const json = await fetchEtherscanJson({
    apikey: etherscanApiKey,
    chainid: String(chainId),
    module: "contract",
    action: "getcontractcreation",
    contractaddresses: address,
  });
  const [creation] = Array.isArray(json.result) ? json.result : [];
  if (!creation) {
    fail(`Etherscan did not return creation metadata for ${address}: ${JSON.stringify(json)}`);
  }
  return creation;
}

async function getBridgeDeploymentBlock(bridgeCore, { chainId, etherscanApiKey }) {
  const creation = await getContractCreation(bridgeCore, { chainId, etherscanApiKey });
  return parseBlockNumber(String(creation.blockNumber), `bridgeCore creation block for ${bridgeCore}`);
}

async function getSourceCodeStatus(address, { chainId, etherscanApiKey }) {
  const json = await fetchEtherscanJson({
    apikey: etherscanApiKey,
    chainid: String(chainId),
    module: "contract",
    action: "getsourcecode",
    address,
  });
  const [source] = Array.isArray(json.result) ? json.result : [];
  if (!source) {
    fail(`Etherscan did not return source metadata for ${address}: ${JSON.stringify(json)}`);
  }
  return {
    contractName: source.ContractName ?? "",
    isVerified: source.ABI !== "Contract source code not verified",
  };
}

function readState(statePath) {
  if (!fs.existsSync(statePath)) {
    return {
      lastScannedBlock: null,
      verifiedManagers: {},
    };
  }
  const state = readJson(statePath);
  return {
    ...state,
    verifiedManagers: state.verifiedManagers && typeof state.verifiedManagers === "object"
      ? state.verifiedManagers
      : {},
  };
}

function normalizeStateForWrite(state, { chainId, bridgeCore, deploymentPath }) {
  return {
    chainId,
    bridgeCore,
    deploymentPath: path.relative(projectRoot, deploymentPath),
    updatedAtUtc: new Date().toISOString(),
    lastScannedBlock: state.lastScannedBlock,
    verifiedManagers: state.verifiedManagers,
  };
}

function isRetryableLogError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("429")
    || message.includes("exceeded")
    || message.includes("rate limit")
    || message.includes("timeout")
    || message.includes("temporarily")
    || message.includes("SERVER_ERROR")
    || message.includes("UNKNOWN_ERROR");
}

async function getLogsWithRetry(provider, filter, { retries, retryDelayMs }) {
  let lastError = null;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      return await provider.getLogs(filter);
    } catch (error) {
      lastError = error;
      if (attempt >= retries || !isRetryableLogError(error)) {
        throw error;
      }
      const delay = retryDelayMs * 2 ** attempt;
      console.log(`Log scan failed; retrying in ${delay}ms (${attempt + 1}/${retries})`);
      await sleep(delay);
    }
  }
  throw lastError;
}

function parseLogNumber(value, label) {
  const parsed = typeof value === "number" ? value : Number(BigInt(value));
  if (!Number.isSafeInteger(parsed)) {
    fail(`${label} is too large for a JavaScript-safe integer: ${String(value)}`);
  }
  return parsed;
}

function parseChannelCreatedLogs(logs) {
  const iface = new ethers.Interface([CHANNEL_CREATED_EVENT]);
  const events = [];
  for (const log of logs) {
    const parsed = iface.parseLog({ topics: log.topics, data: log.data });
    events.push({
      channelId: parsed.args.channelId.toString(),
      dappId: parsed.args.dappId.toString(),
      manager: ethers.getAddress(parsed.args.manager),
      bridgeTokenVault: ethers.getAddress(parsed.args.bridgeTokenVault),
      transactionHash: log.transactionHash,
      blockNumber: parseLogNumber(log.blockNumber, "log blockNumber"),
      logIndex: parseLogNumber(log.logIndex ?? log.index ?? 0, "log index"),
    });
  }
  events.sort((left, right) => left.blockNumber - right.blockNumber || left.logIndex - right.logIndex);
  return events;
}

async function scanChannelCreatedEventsFromRpc({
  provider,
  bridgeCore,
  fromBlock,
  toBlock,
  chunkSize,
  requestDelayMs,
  logRetries,
  logRetryDelayMs,
}) {
  const iface = new ethers.Interface([CHANNEL_CREATED_EVENT]);
  const topic = iface.getEvent("ChannelCreated").topicHash;
  const logs = [];
  for (let start = fromBlock; start <= toBlock; start += chunkSize) {
    const end = Math.min(start + chunkSize - 1, toBlock);
    console.log(`Scanning ChannelCreated logs: ${start}..${end}`);
    const chunkLogs = await getLogsWithRetry(provider, {
      address: bridgeCore,
      topics: [topic],
      fromBlock: start,
      toBlock: end,
    }, {
      retries: logRetries,
      retryDelayMs: logRetryDelayMs,
    });
    logs.push(...chunkLogs);
    if (requestDelayMs > 0 && end < toBlock) {
      await sleep(requestDelayMs);
    }
  }
  return parseChannelCreatedLogs(logs);
}

function etherscanNoRecords(json) {
  const message = `${json.message ?? ""} ${json.result ?? ""}`;
  return json.status === "0" && /no records found/i.test(message);
}

function etherscanRetryable(json) {
  const message = `${json.message ?? ""} ${json.result ?? ""}`;
  return /rate limit|timeout|temporarily|busy/i.test(message);
}

async function fetchEtherscanLogsPage(params, { retries, retryDelayMs }) {
  let lastJson = null;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const json = await fetchEtherscanJson(params);
    if (etherscanNoRecords(json)) {
      return [];
    }
    if (json.status === "1" && Array.isArray(json.result)) {
      return json.result;
    }
    lastJson = json;
    if (attempt >= retries || !etherscanRetryable(json)) {
      fail(`Etherscan log scan failed: ${JSON.stringify(json)}`);
    }
    const delay = retryDelayMs * 2 ** attempt;
    console.log(`Etherscan log scan failed; retrying in ${delay}ms (${attempt + 1}/${retries})`);
    await sleep(delay);
  }
  fail(`Etherscan log scan failed: ${JSON.stringify(lastJson)}`);
}

async function scanChannelCreatedEventsFromEtherscan({
  bridgeCore,
  fromBlock,
  toBlock,
  chainId,
  etherscanApiKey,
  requestDelayMs,
  logRetries,
  logRetryDelayMs,
}) {
  const iface = new ethers.Interface([CHANNEL_CREATED_EVENT]);
  const topic = iface.getEvent("ChannelCreated").topicHash;
  const logs = [];
  for (let page = 1; ; page += 1) {
    console.log(`Scanning ChannelCreated logs from Etherscan: ${fromBlock}..${toBlock} page ${page}`);
    const pageLogs = await fetchEtherscanLogsPage({
      apikey: etherscanApiKey,
      chainid: String(chainId),
      module: "logs",
      action: "getLogs",
      address: bridgeCore,
      fromBlock: String(fromBlock),
      toBlock: String(toBlock),
      topic0: topic,
      page: String(page),
      offset: String(DEFAULT_ETHERSCAN_LOG_PAGE_SIZE),
    }, {
      retries: logRetries,
      retryDelayMs: logRetryDelayMs,
    });
    logs.push(...pageLogs);
    if (pageLogs.length < DEFAULT_ETHERSCAN_LOG_PAGE_SIZE) {
      break;
    }
    if (requestDelayMs > 0) {
      await sleep(requestDelayMs);
    }
  }
  return parseChannelCreatedLogs(logs);
}

async function scanChannelCreatedEvents({
  logSource,
  provider,
  bridgeCore,
  fromBlock,
  toBlock,
  chainId,
  etherscanApiKey,
  chunkSize,
  requestDelayMs,
  logRetries,
  logRetryDelayMs,
}) {
  if (logSource === "etherscan") {
    return scanChannelCreatedEventsFromEtherscan({
      bridgeCore,
      fromBlock,
      toBlock,
      chainId,
      etherscanApiKey,
      requestDelayMs,
      logRetries,
      logRetryDelayMs,
    });
  }
  return scanChannelCreatedEventsFromRpc({
    provider,
    bridgeCore,
    fromBlock,
    toBlock,
    chunkSize,
    requestDelayMs,
    logRetries,
    logRetryDelayMs,
  });
}

function uniqueEventsByManager(events) {
  const seen = new Set();
  const unique = [];
  for (const event of events) {
    const key = event.manager.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    unique.push(event);
  }
  return unique;
}

function readChannelManagerCreationBytecode() {
  if (!fs.existsSync(CHANNEL_MANAGER_ARTIFACT_PATH)) {
    fail(`Missing ChannelManager artifact: ${CHANNEL_MANAGER_ARTIFACT_PATH}`);
  }
  const artifact = readJson(CHANNEL_MANAGER_ARTIFACT_PATH);
  const bytecode = artifact.bytecode?.object ?? artifact.bytecode;
  if (typeof bytecode !== "string" || bytecode === "0x" || bytecode.length <= 2) {
    fail(`Invalid ChannelManager artifact bytecode: ${CHANNEL_MANAGER_ARTIFACT_PATH}`);
  }
  return bytecode;
}

function extractConstructorArgsFromCreationBytecode(creationBytecode, artifactBytecode, manager) {
  if (!creationBytecode.startsWith("0x")) {
    fail(`Etherscan creationBytecode for ${manager} is missing 0x prefix.`);
  }
  if (!creationBytecode.startsWith(artifactBytecode)) {
    fail([
      `Local ChannelManager creation bytecode does not match ${manager}.`,
      "This usually means the manager was deployed from a different source commit or compiler metadata path.",
      "Run this from the exact deployment source tree, or verify the manager manually with the matching artifact.",
    ].join("\n"));
  }
  const constructorArgs = `0x${creationBytecode.slice(artifactBytecode.length)}`;
  if (constructorArgs.length <= 2) {
    fail(`Could not extract constructor args for ${manager}.`);
  }
  return constructorArgs;
}

async function getChannelManagerConstructorArgs(manager, context) {
  const creation = await getContractCreation(manager, context);
  const artifactBytecode = readChannelManagerCreationBytecode();
  return extractConstructorArgsFromCreationBytecode(
    creation.creationBytecode ?? "",
    artifactBytecode,
    manager,
  );
}

async function tryGetChannelManagerConstructorArgs(manager, context) {
  try {
    return await getChannelManagerConstructorArgs(manager, context);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return null;
  }
}

function verifyChannelManager(event, constructorArgs, { chainId, rpcUrl, etherscanApiKey }) {
  console.log(`Verifying ChannelManager ${event.manager} for channel ${event.channelId}`);
  run("forge", [
    "verify-contract",
    "--root",
    "bridge",
    "--chain",
    String(chainId),
    "--verifier",
    "etherscan",
    "--watch",
    "--constructor-args",
    constructorArgs,
    event.manager,
    CHANNEL_MANAGER_CONTRACT,
  ], {
    cwd: projectRoot,
    env: {
      ...process.env,
      ETHERSCAN_API_KEY: etherscanApiKey,
      ETH_RPC_URL: rpcUrl,
    },
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  loadEnvFile();

  const bridgeNetwork = resolveAppNetwork(options.networkName);
  const chainId = bridgeNetwork.chainId;
  const rpcUrl = resolveRpcUrl(options.networkName, bridgeNetwork);
  const etherscanApiKey = resolveEtherscanApiKey();
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const deploymentPath = options.deploymentPath
    ? resolveProjectPath(options.deploymentPath)
    : resolveDefaultDeploymentPath(chainId);
  const deployment = readJson(deploymentPath);
  const bridgeCore = ethers.getAddress(deployment.bridgeCore);
  const statePath = options.statePath
    ? resolveProjectPath(options.statePath)
    : resolveDefaultStatePath(chainId);
  const state = readState(statePath);
  const latestBlock = await provider.getBlockNumber();
  const toBlock = options.toBlock ?? Math.max(0, latestBlock - options.confirmations);
  if (toBlock > latestBlock) {
    fail(`--to-block ${toBlock} is greater than latest block ${latestBlock}`);
  }
  const deploymentBlock = await getBridgeDeploymentBlock(bridgeCore, { chainId, etherscanApiKey });
  const checkpointStart = typeof state.lastScannedBlock === "number"
    ? Math.max(deploymentBlock, state.lastScannedBlock - options.lookbackBlocks + 1)
    : deploymentBlock;
  const fromBlock = options.fromBlock ?? checkpointStart;
  if (fromBlock > toBlock) {
    console.log(`Nothing to scan: fromBlock ${fromBlock} is greater than toBlock ${toBlock}.`);
    return;
  }

  console.log(`BridgeCore: ${bridgeCore}`);
  console.log(`Deployment artifact: ${deploymentPath}`);
  console.log(`State path: ${statePath}`);
  console.log(`Log source: ${options.logSource}`);
  console.log(`Scan range: ${fromBlock}..${toBlock}`);

  const events = uniqueEventsByManager(await scanChannelCreatedEvents({
    logSource: options.logSource,
    provider,
    bridgeCore,
    fromBlock,
    toBlock,
    chainId,
    etherscanApiKey,
    chunkSize: options.chunkSize,
    requestDelayMs: options.requestDelayMs,
    logRetries: options.logRetries,
    logRetryDelayMs: options.logRetryDelayMs,
  }));
  console.log(`Discovered ${events.length} unique ChannelManager address(es) in scan range.`);

  const verificationQueue = [];
  for (const event of events) {
    const managerKey = event.manager.toLowerCase();
    const stateEntry = state.verifiedManagers[managerKey];
    if (!options.refresh && stateEntry?.verified) {
      console.log(`Known verified from state: ${event.manager}`);
      continue;
    }

    const sourceStatus = await getSourceCodeStatus(event.manager, { chainId, etherscanApiKey });
    if (sourceStatus.isVerified) {
      console.log(`Already verified: ${event.manager} (${sourceStatus.contractName || "unknown"})`);
      state.verifiedManagers[managerKey] = {
        channelId: event.channelId,
        dappId: event.dappId,
        manager: event.manager,
        bridgeTokenVault: event.bridgeTokenVault,
        creationTxHash: event.transactionHash,
        createdAtBlock: event.blockNumber,
        verified: true,
        verifiedAtUtc: state.verifiedManagers[managerKey]?.verifiedAtUtc ?? new Date().toISOString(),
      };
      continue;
    }

    console.log(`Not verified: ${event.manager} (channel ${event.channelId})`);
    verificationQueue.push(event);
  }

  if (verificationQueue.length === 0) {
    console.log("No unverified ChannelManager contracts found.");
  } else if (options.dryRun) {
    console.log(`Dry run found ${verificationQueue.length} unverified ChannelManager contract(s).`);
  } else {
    if (!options.skipBuild) {
      run("forge", ["build", "--root", "bridge"], { cwd: projectRoot });
    }

    for (const event of verificationQueue) {
      const managerKey = event.manager.toLowerCase();
      const constructorArgs = await tryGetChannelManagerConstructorArgs(event.manager, {
        chainId,
        etherscanApiKey,
      });
      if (!constructorArgs) {
        state.verifiedManagers[managerKey] = {
          channelId: event.channelId,
          dappId: event.dappId,
          manager: event.manager,
          bridgeTokenVault: event.bridgeTokenVault,
          creationTxHash: event.transactionHash,
          createdAtBlock: event.blockNumber,
          verified: false,
          error: "constructorArgsUnavailable",
          updatedAtUtc: new Date().toISOString(),
        };
        continue;
      }

      verifyChannelManager(event, constructorArgs, { chainId, rpcUrl, etherscanApiKey });
      state.verifiedManagers[managerKey] = {
        channelId: event.channelId,
        dappId: event.dappId,
        manager: event.manager,
        bridgeTokenVault: event.bridgeTokenVault,
        creationTxHash: event.transactionHash,
        createdAtBlock: event.blockNumber,
        verified: true,
        verifiedAtUtc: new Date().toISOString(),
      };
    }
  }

  state.lastScannedBlock = toBlock;
  if (options.dryRun) {
    console.log("Dry run complete; state was not written.");
  } else {
    writeJson(statePath, normalizeStateForWrite(state, { chainId, bridgeCore, deploymentPath }));
    console.log(`Updated verification state: ${statePath}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
