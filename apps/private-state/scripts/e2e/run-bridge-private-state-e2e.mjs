#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import {
  AbiCoder,
  Contract,
  HDNodeWallet,
  Interface,
  JsonRpcProvider,
  Wallet,
  ethers,
  getAddress,
  keccak256,
} from "ethers";
import {
  MAX_MT_LEAVES,
  MT_DEPTH,
  TokamakL2StateManager,
  createTokamakL2Common,
  createTokamakL2StateManagerFromStateSnapshot,
  createTokamakL2Tx,
  deriveL2KeysFromSignature,
  fromEdwardsToAddress,
  poseidon,
} from "tokamak-l2js";
import {
  addHexPrefix,
  bytesToBigInt,
  bytesToHex,
  createAddressFromString,
  hexToBytes,
  setLengthLeft,
  utf8ToBytes,
} from "@ethereumjs/util";
import {
  buildDAppDefinitions,
  buildFunctionDefinition,
  ensureTokamakDistBackendBinaries,
  hashTokamakPublicInputs,
  writeJson,
} from "../../../../scripts/zk/lib/tokamak-artifacts.mjs";
import {
  computeEncryptedNoteSalt,
  deriveNoteReceiveKeyMaterial,
  encryptMintNoteValueForOwner,
  encryptedNoteValueTuple,
  encryptNoteValueForRecipient,
} from "./private-state-note-delivery.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
const appRoot = path.resolve(repoRoot, "apps", "private-state");
const bridgeRoot = path.resolve(repoRoot, "bridge");
const tokamakRoot = path.resolve(repoRoot, "submodules", "Tokamak-zk-EVM");
const tokamakCliPath = path.resolve(tokamakRoot, "tokamak-cli");
const tokamakSetupSourceDir = path.resolve(tokamakRoot, "packages", "backend", "setup", "trusted-setup", "output");
const tokamakSetupDistDir = path.resolve(tokamakRoot, "dist", "resource", "setup", "output");
const outputRoot = path.resolve(appRoot, "scripts", "e2e", "output", "private-state-bridge-genesis");
const deploymentManifestPath = path.resolve(appRoot, "deploy", "deployment.31337.latest.json");
const storageLayoutManifestPath = path.resolve(appRoot, "deploy", "storage-layout.31337.latest.json");
const controllerAbiPath = path.resolve(appRoot, "deploy", "PrivateStateController.callable-abi.json");
const bridgeDeploymentArtifactPath = path.resolve(bridgeRoot, "deployments", "bridge.31337.json");
const bridgeAbiManifestPath = path.resolve(bridgeRoot, "deployments", "bridge-abi-manifest.31337.json");
const bridgeDeploymentSummaryPath = path.resolve(outputRoot, "bridge-deployment.json");
const grothInputDir = path.resolve(outputRoot, "groth-inputs");
const tokamakStepsDir = path.resolve(outputRoot, "tokamak-steps");
const summaryPath = path.resolve(outputRoot, "summary.json");
const providerUrl = process.env.ANVIL_RPC_URL?.trim() || "http://127.0.0.1:8545";
const anvilMnemonic = process.env.APPS_ANVIL_MNEMONIC?.trim() || "test test test test test test test test test test test junk";
const anvilDeployerPrivateKey =
  process.env.APPS_ANVIL_DEPLOYER_PRIVATE_KEY?.trim()
    || "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const channelName = "private-state-bridge-genesis";
const channelId = deriveChannelIdFromName(channelName);
const dappId = 1;
const tokamakAPubBlockLength = 43;
const tokamakPrevBlockHashCount = 4;
const amountUnit = 10n ** 18n;
const joinFee = 1n * amountUnit;
const depositAmount = 3n * amountUnit;
const abiCoder = AbiCoder.defaultAbiCoder();
const deployerAddress = new Wallet(anvilDeployerPrivateKey).address;
const bridgeCoreAbi = [
  "function canonicalAsset() external view returns (address)",
  "function createChannel(uint256 channelId, uint256 dappId, address leader, uint256 initialJoinFee) external returns (address manager, address bridgeTokenVault)",
  "function getChannel(uint256 channelId) external view returns (tuple(bool exists,uint256 dappId,address leader,address asset,address manager,address bridgeTokenVault,bytes32 aPubBlockHash))",
];
const dAppManagerAbi = [
  "function registerDApp(uint256 dappId, bytes32 labelHash, tuple(address storageAddr, bytes32[] preAllocatedKeys, uint8[] userStorageSlots, bool isChannelTokenVaultStorage)[] storages, tuple(address entryContract, bytes4 functionSig, bytes32 preprocessInputHash, tuple(uint8 entryContractOffsetWords, uint8 functionSigOffsetWords, uint8 currentRootVectorOffsetWords, uint8 updatedRootVectorOffsetWords, tuple(uint16 startOffsetWords, uint8 topicCount)[] eventLogs) instanceLayout)[] functions) external",
];
const channelManagerAbi = [
  "function currentRootVectorHash() external view returns (bytes32)",
  "function genesisBlockNumber() external view returns (uint256)",
  "function getChannelTokenVaultRegistration(address user) external view returns (tuple(bool exists, address l2Address, bytes32 channelTokenVaultKey, uint256 leafIndex, uint256 joinFeePaid, uint64 joinedAt, (bytes32 x,uint8 yParity) noteReceivePubKey))",
  "function executeChannelTransaction((uint128[] proofPart1,uint256[] proofPart2,uint128[] functionPreprocessPart1,uint256[] functionPreprocessPart2,uint256[] aPubUser,uint256[] aPubBlock) payload) external returns (bool)",
];
const bridgeTokenVaultAbi = [
  "function fund(uint256 amount) external",
  "function joinChannel(uint256 channelId, address l2Address, bytes32 channelTokenVaultKey, uint256 leafIndex, (bytes32 x,uint8 yParity) noteReceivePubKey) external returns (bool)",
  "function deposit(uint256 channelId, (uint256[4] pA,uint256[8] pB,uint256[4] pC) proof, (bytes32[] currentRootVector,bytes32 updatedRoot,bytes32 currentUserKey,uint256 currentUserValue,bytes32 updatedUserKey,uint256 updatedUserValue) update) external returns (bool)",
  "function withdraw(uint256 channelId, (uint256[4] pA,uint256[8] pB,uint256[4] pC) proof, (bytes32[] currentRootVector,bytes32 updatedRoot,bytes32 currentUserKey,uint256 currentUserValue,bytes32 updatedUserKey,uint256 updatedUserValue) update) external returns (bool)",
  "function claimToWallet(uint256 amount) external",
  "function availableBalanceOf(address user) external view returns (uint256)",
];
const mockErc20Abi = [
  "function mint(address to, uint256 amount) external",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
];
const requiredTokamakSetupArtifacts = [
  "combined_sigma.rkyv",
  "sigma_preprocess.rkyv",
  "sigma_verify.rkyv",
];

function usage() {
  console.log(`Usage:
  node apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs [options]

Options:
  --skip-install                                  Skip tokamak-cli --install before the flow
  --reuse-generated-artifacts                     Reuse existing Tokamak step artifacts under the output directory
  --keep-anvil                                    Leave anvil running after success
  --help                                          Show this help
`);
}

function parseArgs(argv) {
  const options = {
    runInstall: true,
    reuseGeneratedArtifacts: false,
    keepAnvil: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    switch (current) {
      case "--skip-install":
        options.runInstall = false;
        break;
      case "--keep-anvil":
        options.keepAnvil = true;
        break;
      case "--reuse-generated-artifacts":
        options.reuseGeneratedArtifacts = true;
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

function run(command, args, { cwd = repoRoot, env = process.env } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}.`);
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function cleanDir(dirPath) {
  fs.rmSync(dirPath, { recursive: true, force: true });
  fs.mkdirSync(dirPath, { recursive: true });
}

function expect(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function bytes32FromHex(hexValue) {
  return ethers.zeroPadValue(ethers.toBeHex(BigInt(hexValue)), 32);
}

function normalizeBytes32Hex(hexValue) {
  return bytes32FromHex(hexValue).toLowerCase();
}

function deriveChannelIdFromName(name) {
  return BigInt(keccak256(ethers.toUtf8Bytes(name)));
}

function deriveLeafIndex(storageKey) {
  return BigInt(storageKey) % BigInt(MAX_MT_LEAVES);
}

function buildL1Wallet(index, provider) {
  const node = HDNodeWallet.fromPhrase(anvilMnemonic, undefined, `m/44'/60'/0'/0/${index}`);
  return node.connect(provider);
}

function buildParticipant(index) {
  const signature = poseidonHexFromBytes(ethers.toUtf8Bytes(`private-state participant ${index}`));
  const keySet = deriveL2KeysFromSignature(signature);
  const l2Address = fromEdwardsToAddress(keySet.publicKey).toString();
  return {
    index,
    l1: null,
    l2PrivateKey: keySet.privateKey,
    l2PublicKey: keySet.publicKey,
    l2Address: getAddress(l2Address),
  };
}

function buildParticipants(provider) {
  // Keep the deployer/leader separate from channel participants so account nonces
  // used by bridge deployment do not collide with participant transactions.
  const base = [1, 2, 3].map((index) => buildParticipant(index));
  return base.map((participant) => ({
    ...participant,
    l1: buildL1Wallet(participant.index, provider),
  }));
}

async function rpcCall(provider, method, params) {
  return provider.send(method, params);
}

async function getFixedBlockInfo(provider) {
  const latestNumberHex = await rpcCall(provider, "eth_blockNumber", []);
  const latestNumber = Number(BigInt(latestNumberHex));
  return getBlockInfoAt(provider, latestNumber);
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
    const previousBlock =
      await rpcCall(provider, "eth_getBlockByNumber", [ethers.toQuantity(blockNumber - offset), false]);
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

function encodeTokamakBlockInfo(blockInfo) {
  const values = new Array(tokamakAPubBlockLength).fill(0n);
  writeSplitWord(values, 0, BigInt(blockInfo.coinBase));
  writeSplitWord(values, 2, BigInt(blockInfo.timeStamp));
  writeSplitWord(values, 4, BigInt(blockInfo.blockNumber));
  writeSplitWord(values, 6, BigInt(blockInfo.prevRanDao));
  writeSplitWord(values, 8, BigInt(blockInfo.gasLimit));
  writeSplitWord(values, 10, BigInt(blockInfo.chainId));
  writeSplitWord(values, 12, BigInt(blockInfo.selfBalance));
  writeSplitWord(values, 14, BigInt(blockInfo.baseFee));
  for (let index = 0; index < tokamakPrevBlockHashCount; index += 1) {
    writeSplitWord(values, 16 + index * 2, BigInt(blockInfo.prevBlockHashes[index] ?? 0n));
  }
  return values;
}

function writeSplitWord(words, offset, value) {
  const normalized = BigInt(value);
  words[offset] = normalized & ((1n << 128n) - 1n);
  words[offset + 1] = normalized >> 128n;
}

async function fetchContractCodes(provider, addresses) {
  const codes = [];
  for (const address of addresses) {
    const code = await provider.getCode(address);
    codes.push({
      address: getAddress(address),
      code,
    });
  }
  return codes;
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
  const encoded = abiCoder.encode(["address", "uint256"], [address, slot]);
  return bytesToHex(poseidon(hexToBytes(encoded)));
}

function poseidonHexFromBytes(bytesLike) {
  return ethers.hexlify(poseidon(ethers.getBytes(bytesLike))).toLowerCase();
}

function bigintToHex32(value) {
  return ethers.zeroPadValue(ethers.toBeHex(value), 32);
}

function saltHex(label) {
  return bytes32FromHex(poseidonHexFromBytes(ethers.toUtf8Bytes(label)));
}

function note(owner, value, saltLabel) {
  return {
    owner: getAddress(owner),
    value,
    salt: saltHex(saltLabel),
  };
}

function buildEncryptedTransferOutput({
  owner,
  value,
  label,
  recipientNoteReceivePubKey,
  chainId,
  channelId,
}) {
  const deterministicNonce = ethers.dataSlice(
    poseidonHexFromBytes(ethers.toUtf8Bytes(`${label}:nonce`)),
    0,
    12,
  );
  const encryptedNoteValue = encryptNoteValueForRecipient({
    value,
    recipientNoteReceivePubKey,
    chainId,
    channelId,
    owner,
    nonce: deterministicNonce,
  });
  return {
    output: {
      owner: getAddress(owner),
      value,
      encryptedNoteValue,
    },
    note: {
      owner: getAddress(owner),
      value,
      salt: computeEncryptedNoteSalt(encryptedNoteValue),
    },
  };
}

function buildEncryptedMintOutput({
  owner,
  ownerNoteReceivePubKey,
  value,
  label,
  chainId,
  channelId,
}) {
  const deterministicNonce = ethers.dataSlice(
    poseidonHexFromBytes(ethers.toUtf8Bytes(`${label}:nonce`)),
    0,
    12,
  );
  const encryptedNoteValue = encryptMintNoteValueForOwner({
    value,
    ownerNoteReceivePubKey,
    chainId,
    channelId,
    owner,
    nonce: deterministicNonce,
  });
  return {
    output: {
      value,
      encryptedNoteValue,
    },
    note: {
      owner: getAddress(owner),
      value,
      salt: computeEncryptedNoteSalt(encryptedNoteValue),
    },
  };
}

function serializeBigInts(value) {
  return JSON.parse(JSON.stringify(value, (_key, current) => (
    typeof current === "bigint" ? current.toString() : current
  )));
}

async function writeStepInputs(stepDir, snapshot, transactionSnapshot, blockInfo, contractCodes) {
  ensureDir(stepDir);
  writeJson(path.join(stepDir, "previous_state_snapshot.json"), snapshot);
  writeJson(path.join(stepDir, "transaction.json"), transactionSnapshot);
  writeJson(path.join(stepDir, "block_info.json"), blockInfo);
  writeJson(path.join(stepDir, "contract_codes.json"), contractCodes);
}

function toTokamakSnapshot(tx) {
  return serializeBigInts(tx.captureTxSnapshot());
}

function buildTokamakTxSnapshot({ signerPrivateKey, senderPubKey, to, data, nonce }) {
  const tx = createTokamakL2Tx(
    {
      nonce: BigInt(nonce),
      to: createAddressFromString(to),
      data: hexToBytes(data),
      senderPubKey: senderPubKey,
    },
    { common: createTokamakL2Common() },
  ).sign(signerPrivateKey);

  return toTokamakSnapshot(tx);
}

function outputFile(relativePath) {
  return path.join(tokamakRoot, "dist", relativePath);
}

const tokamakStepArtifactDirectories = [
  path.join("synthesizer", "output"),
  path.join("preprocess", "output"),
  path.join("prove", "output"),
];

function consumeAccountNonce(accountNonces, address) {
  const normalizedAddress = getAddress(address);
  const nextNonce = accountNonces.get(normalizedAddress);
  if (nextNonce === undefined) {
    throw new Error(`Missing cached nonce for ${normalizedAddress}.`);
  }
  accountNonces.set(normalizedAddress, nextNonce + 1);
  return nextNonce;
}

function copyTokamakArtifacts(stepDir) {
  const resourceRoot = path.join(stepDir, "resource");
  cleanDir(resourceRoot);
  for (const relativeDirectory of tokamakStepArtifactDirectories) {
    const sourceDir = path.join(tokamakRoot, "dist", "resource", relativeDirectory);
    if (!fs.existsSync(sourceDir)) {
      continue;
    }

    const targetDir = path.join(resourceRoot, relativeDirectory);
    fs.mkdirSync(path.dirname(targetDir), { recursive: true });
    fs.cpSync(sourceDir, targetDir, { recursive: true });
  }
}

function ensureTokamakSetupArtifacts() {
  const missingInDist = requiredTokamakSetupArtifacts
    .filter((fileName) => !fs.existsSync(path.join(tokamakSetupDistDir, fileName)));
  if (missingInDist.length === 0) {
    return;
  }

  const missingInSource = requiredTokamakSetupArtifacts
    .filter((fileName) => !fs.existsSync(path.join(tokamakSetupSourceDir, fileName)));
  expect(
    missingInSource.length === 0,
    `Missing Tokamak setup artifacts in trusted setup output: ${missingInSource.join(", ")}`,
  );

  ensureDir(tokamakSetupDistDir);
  for (const fileName of requiredTokamakSetupArtifacts) {
    fs.copyFileSync(path.join(tokamakSetupSourceDir, fileName), path.join(tokamakSetupDistDir, fileName));
  }
}

function loadTokamakPayloadFromStep(stepDir) {
  const proofJson = readJson(path.join(stepDir, "resource", "prove", "output", "proof.json"));
  const preprocessJson = readJson(path.join(stepDir, "resource", "preprocess", "output", "preprocess.json"));
  const instanceJson = readJson(path.join(stepDir, "resource", "synthesizer", "output", "instance.json"));

  return {
    proofPart1: proofJson.proof_entries_part1.map((value) => BigInt(value)),
    proofPart2: proofJson.proof_entries_part2.map((value) => BigInt(value)),
    functionPreprocessPart1: preprocessJson.preprocess_entries_part1.map((value) => BigInt(value)),
    functionPreprocessPart2: preprocessJson.preprocess_entries_part2.map((value) => BigInt(value)),
    aPubUser: instanceJson.a_pub_user.map((value) => BigInt(value)),
    aPubBlock: normalizeTokamakAPubBlock(instanceJson.a_pub_block.map((value) => BigInt(value))),
  };
}

function functionSelectorHex(calldata) {
  return calldata.slice(0, 10);
}

function normalizedRootVector(roots) {
  return roots.map((value) => normalizeBytes32Hex(value));
}

function hashRootVector(roots) {
  return keccak256(abiCoder.encode(["bytes32[]"], [normalizedRootVector(roots)]));
}

function normalizeTokamakAPubBlock(values) {
  let normalizedValues = values.slice();
  if (normalizedValues.length > tokamakAPubBlockLength) {
    const trailingValues = normalizedValues.slice(tokamakAPubBlockLength);
    if (!trailingValues.every((value) => value === 0n)) {
      throw new Error(
        `a_pub_block length ${normalizedValues.length} exceeds the fixed Tokamak block input length ${tokamakAPubBlockLength}.`,
      );
    }
    normalizedValues = normalizedValues.slice(0, tokamakAPubBlockLength);
  }
  return normalizedValues.concat(new Array(tokamakAPubBlockLength - normalizedValues.length).fill(0n));
}

function requiredTokamakStepFiles(stepDir) {
  return [
    path.join(stepDir, "previous_state_snapshot.json"),
    path.join(stepDir, "transaction.json"),
    path.join(stepDir, "block_info.json"),
    path.join(stepDir, "contract_codes.json"),
    path.join(stepDir, "resource", "preprocess", "output", "preprocess.json"),
    path.join(stepDir, "resource", "prove", "output", "proof.json"),
    path.join(stepDir, "resource", "synthesizer", "output", "instance.json"),
    path.join(stepDir, "resource", "synthesizer", "output", "instance_description.json"),
    path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"),
  ];
}

function hasReusableTokamakArtifacts(stepDir) {
  return requiredTokamakStepFiles(stepDir).every((filePath) => fs.existsSync(filePath));
}

function assertStepArtifactsMatchCurrentContext(stepDir, expectedSnapshot, expectedTransactionSnapshot, expectedBlockInfo) {
  const savedSnapshot = readJson(path.join(stepDir, "previous_state_snapshot.json"));
  const savedTransaction = readJson(path.join(stepDir, "transaction.json"));
  const savedBlockInfo = readJson(path.join(stepDir, "block_info.json"));

  expect(
    JSON.stringify(savedSnapshot) === JSON.stringify(expectedSnapshot),
    `Saved Tokamak step snapshot does not match current context: ${stepDir}`,
  );
  expect(
    JSON.stringify(savedTransaction) === JSON.stringify(expectedTransactionSnapshot),
    `Saved Tokamak transaction snapshot does not match current context: ${stepDir}`,
  );
  expect(
    JSON.stringify(savedBlockInfo) === JSON.stringify(expectedBlockInfo),
    `Saved Tokamak block info does not match current context: ${stepDir}`,
  );
}

function loadExistingTokamakStep(step, currentSnapshot, blockInfo, contractCodes) {
  const stepDir = path.join(tokamakStepsDir, step.name);
  if (!hasReusableTokamakArtifacts(stepDir)) {
    throw new Error(`Missing reusable Tokamak artifacts for ${step.name}: ${stepDir}`);
  }

  const transactionSnapshot = buildTokamakTxSnapshot({
    signerPrivateKey: step.sender.l2PrivateKey,
    senderPubKey: step.sender.l2PublicKey,
    to: step.controllerAddress,
    data: step.calldata,
    nonce: step.nonce,
  });

  assertStepArtifactsMatchCurrentContext(stepDir, currentSnapshot, transactionSnapshot, blockInfo);

  const nextSnapshot = readJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"));
  const metadataRecord = buildFunctionDefinition({
    groupName: "private-state-e2e",
    exampleName: step.name,
    transactionJsonPath: path.join(stepDir, "transaction.json"),
    snapshotJsonPath: path.join(stepDir, "previous_state_snapshot.json"),
    preprocessJsonPath: path.join(stepDir, "resource", "preprocess", "output", "preprocess.json"),
    instanceJsonPath: path.join(stepDir, "resource", "synthesizer", "output", "instance.json"),
    instanceDescriptionJsonPath: path.join(stepDir, "resource", "synthesizer", "output", "instance_description.json"),
  });

  return {
    stepDir,
    transactionSnapshot,
    metadataRecord,
    payload: loadTokamakPayloadFromStep(stepDir),
    nextSnapshot,
  };
}

async function runTokamakStep(step, currentSnapshot, blockInfo, contractCodes) {
  const stepDir = path.join(tokamakStepsDir, step.name);
  cleanDir(stepDir);
  const transactionSnapshot = buildTokamakTxSnapshot({
    signerPrivateKey: step.sender.l2PrivateKey,
    senderPubKey: step.sender.l2PublicKey,
    to: step.controllerAddress,
    data: step.calldata,
    nonce: step.nonce,
  });

  await writeStepInputs(stepDir, currentSnapshot, transactionSnapshot, blockInfo, contractCodes);

  run(tokamakCliPath, ["--synthesize", "--tokamak-ch-tx", stepDir], { cwd: tokamakRoot });
  ensureTokamakSetupArtifacts();
  run(tokamakCliPath, ["--preprocess"], { cwd: tokamakRoot });
  ensureTokamakSetupArtifacts();
  run(tokamakCliPath, ["--prove"], { cwd: tokamakRoot });

  const bundlePath = path.join(stepDir, `${step.name}.zip`);
  run(tokamakCliPath, ["--extract-proof", bundlePath], { cwd: tokamakRoot });
  copyTokamakArtifacts(stepDir);
  run(tokamakCliPath, ["--verify", bundlePath], { cwd: tokamakRoot });

  const nextSnapshot = readJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.json"));
  if (Array.isArray(nextSnapshot.storageAddresses)) {
    nextSnapshot.storageAddresses = nextSnapshot.storageAddresses
      .map((address) => createAddressFromString(address).toString());
  }
  writeJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"), nextSnapshot);
  const metadataRecord = buildFunctionDefinition({
    groupName: "private-state-e2e",
    exampleName: step.name,
    transactionJsonPath: path.join(stepDir, "transaction.json"),
    snapshotJsonPath: path.join(stepDir, "previous_state_snapshot.json"),
    preprocessJsonPath: path.join(stepDir, "resource", "preprocess", "output", "preprocess.json"),
    instanceJsonPath: path.join(stepDir, "resource", "synthesizer", "output", "instance.json"),
    instanceDescriptionJsonPath: path.join(stepDir, "resource", "synthesizer", "output", "instance_description.json"),
  });

  return {
    stepDir,
    transactionSnapshot,
    metadataRecord,
    payload: loadTokamakPayloadFromStep(stepDir),
    nextSnapshot,
  };
}

async function materializeTokamakResults(tokamakScenarios, initialSnapshot, blockInfo, contractCodes, options) {
  let currentSnapshot = initialSnapshot;
  const tokamakResults = [];

  for (const scenario of tokamakScenarios) {
    let result;
    const stepDir = path.join(tokamakStepsDir, scenario.name);
    if (options.reuseGeneratedArtifacts && hasReusableTokamakArtifacts(stepDir)) {
      console.log(`E2E: reusing Tokamak artifacts for ${scenario.name}.`);
      try {
        result = loadExistingTokamakStep(scenario, currentSnapshot, blockInfo, contractCodes);
      } catch (error) {
        console.log(`E2E: cached Tokamak artifacts for ${scenario.name} do not match current context, regenerating.`);
        result = await runTokamakStep(scenario, currentSnapshot, blockInfo, contractCodes);
      }
    } else {
      console.log(`E2E: generating Tokamak artifacts for ${scenario.name}.`);
      result = await runTokamakStep(scenario, currentSnapshot, blockInfo, contractCodes);
    }

    tokamakResults.push({
      ...result,
      scenario,
      previousSnapshot: currentSnapshot,
    });
    currentSnapshot = result.nextSnapshot;
  }

  return {
    tokamakResults,
    finalSnapshot: currentSnapshot,
  };
}

async function currentStorageBigInt(stateManager, address, keyHex) {
  const valueBytes = await stateManager.getStorage(createAddressFromString(address), hexToBytes(keyHex));
  if (valueBytes.length === 0) {
    return 0n;
  }
  return bytesToBigInt(valueBytes);
}

async function buildGrothTransition(stepName, stateManager, vaultAddress, keyHex, nextValue) {
  const vaultAddressObj = createAddressFromString(vaultAddress);
  const keyBigInt = BigInt(keyHex);
  const proof = stateManager.merkleTrees.getProof(vaultAddressObj, keyBigInt);
  const currentRoot = stateManager.merkleTrees.getRoot(vaultAddressObj);
  const currentValue = await currentStorageBigInt(stateManager, vaultAddress, keyHex);
  const currentSnapshot = await stateManager.captureStateSnapshot();

  await stateManager.putStorage(vaultAddressObj, hexToBytes(keyHex), hexToBytes(bigintToHex32(nextValue)));
  const updatedRoot = stateManager.merkleTrees.getRoot(vaultAddressObj);
  const nextSnapshot = await stateManager.captureStateSnapshot();

  const input = {
    root_before: currentRoot.toString(),
    root_after: updatedRoot.toString(),
    leaf_index: BigInt(proof.leafIndex).toString(),
    storage_key: keyBigInt.toString(),
    storage_value_before: currentValue.toString(),
    storage_value_after: nextValue.toString(),
    proof: proof.siblings.map((siblings) => BigInt(siblings[0] ?? 0n).toString()),
  };

  const stepDir = path.join(grothInputDir, stepName);
  cleanDir(stepDir);
  const inputPath = path.join(stepDir, "input.json");
  writeJson(inputPath, input);

  run("node", ["scripts/groth16/prover/updateTree/generateProof.mjs", "--input", inputPath], { cwd: repoRoot });

  const proofJson = readJson(path.join(repoRoot, "groth16", "prover", "updateTree", "proof.json"));
  const publicSignals = readJson(path.join(repoRoot, "groth16", "prover", "updateTree", "public.json"));

  writeJson(path.join(stepDir, "proof.json"), proofJson);
  writeJson(path.join(stepDir, "public.json"), publicSignals);

  const solidityProof = toGrothSolidityProof(proofJson);
  const grothUpdate = {
    currentRootVector: currentSnapshot.stateRoots,
    updatedRoot: bytes32FromHex(ethers.toBeHex(updatedRoot)),
    currentUserKey: bytes32FromHex(keyHex),
    currentUserValue: currentValue,
    updatedUserKey: bytes32FromHex(keyHex),
    updatedUserValue: nextValue,
  };

  return {
    stepDir,
    input,
    proofJson,
    publicSignals,
    proof: solidityProof,
    update: grothUpdate,
    nextSnapshot,
  };
}

function splitFieldElement(value) {
  const hexValue = BigInt(value).toString(16).padStart(96, "0");
  return [
    BigInt(`0x${"0".repeat(32)}${hexValue.slice(0, 32)}`),
    BigInt(`0x${hexValue.slice(32)}`),
  ];
}

function toGrothSolidityProof(proof) {
  return {
    pA: [
      ...splitFieldElement(proof.pi_a[0]),
      ...splitFieldElement(proof.pi_a[1]),
    ],
    pB: [
      ...splitFieldElement(proof.pi_b[0][1]),
      ...splitFieldElement(proof.pi_b[0][0]),
      ...splitFieldElement(proof.pi_b[1][1]),
      ...splitFieldElement(proof.pi_b[1][0]),
    ],
    pC: [
      ...splitFieldElement(proof.pi_c[0]),
      ...splitFieldElement(proof.pi_c[1]),
    ],
  };
}

async function bootstrapAnvil() {
  run("make", ["-C", appRoot, "anvil-stop"], { cwd: repoRoot });
  run("make", ["-C", appRoot, "anvil-start"], { cwd: repoRoot });
  run("make", ["-C", appRoot, "anvil-bootstrap"], { cwd: repoRoot });
}

async function deployBridgeStack() {
  ensureDir(path.dirname(bridgeDeploymentArtifactPath));
  const env = {
    ...process.env,
    BRIDGE_DEPLOYER_PRIVATE_KEY: anvilDeployerPrivateKey,
    BRIDGE_MERKLE_TREE_LEVELS: String(MT_DEPTH),
    BRIDGE_OUTPUT_PATH: bridgeDeploymentArtifactPath,
    BRIDGE_DEPLOY_MOCK_ASSET: "true",
  };

  run(
    "forge",
    [
      "script",
      "scripts/DeployBridgeStack.s.sol:DeployBridgeStackScript",
      "--sig",
      "run()",
      "--rpc-url",
      providerUrl,
      "--broadcast",
    ],
    { cwd: bridgeRoot, env },
  );

  run(
    "node",
    [
      path.join(bridgeRoot, "scripts", "generate-bridge-abi-manifest.mjs"),
      "--output",
      bridgeAbiManifestPath,
      "--chain-id",
      "31337",
      "--deployment-path",
      bridgeDeploymentArtifactPath,
    ],
    { cwd: repoRoot },
  );

  const deployment = readJson(bridgeDeploymentArtifactPath);
  writeJson(bridgeDeploymentSummaryPath, deployment);
  return deployment;
}

function toStorageMetadata(entries) {
  return entries.map((entry) => ({
    storageAddr: entry.storageAddress,
    preAllocatedKeys: entry.preAllocKeys,
    userStorageSlots: entry.userSlots,
    isChannelTokenVaultStorage: entry.isChannelTokenVaultStorage,
  }));
}

function toFunctionMetadata(entries) {
  return entries.map((entry) => ({
    entryContract: entry.entryContract,
    functionSig: entry.functionSig,
    preprocessInputHash: entry.preprocessInputHash,
    instanceLayout: {
      entryContractOffsetWords: entry.entryContractOffsetWords,
      functionSigOffsetWords: entry.functionSigOffsetWords,
      currentRootVectorOffsetWords: entry.currentRootVectorOffsetWords,
      updatedRootVectorOffsetWords: entry.updatedRootVectorOffsetWords,
      eventLogs: entry.eventLogs,
    },
  }));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.reuseGeneratedArtifacts) {
    ensureDir(outputRoot);
  } else {
    cleanDir(outputRoot);
  }
  ensureDir(grothInputDir);
  ensureDir(tokamakStepsDir);

  console.log("E2E: bootstrapping local anvil and app deployment.");

  await bootstrapAnvil();

  ensureTokamakDistBackendBinaries(tokamakRoot);

  if (options.runInstall) {
    run(tokamakCliPath, ["--install"], { cwd: tokamakRoot });
  }

  const provider = new JsonRpcProvider(providerUrl);
  const deployer = new Wallet(anvilDeployerPrivateKey, provider);
  const participants = buildParticipants(provider);
  const leader = deployer.address;

  const appDeployment = readJson(deploymentManifestPath);
  const storageLayout = readJson(storageLayoutManifestPath);
  const controllerAddress = getAddress(appDeployment.contracts.controller);
  const vaultAddress = getAddress(appDeployment.contracts.l2AccountingVault);
  const controllerAbi = readJson(controllerAbiPath);
  const controllerInterface = new Interface(controllerAbi);

  const liquidBalancesSlot = BigInt(
    storageLayout.contracts.L2AccountingVault.storageLayout.storage.find((entry) => entry.label === "liquidBalances").slot,
  );

  const contractCodes = await fetchContractCodes(provider, [controllerAddress, vaultAddress]);
  const bootstrapBlockInfo = await getFixedBlockInfo(provider);

  const initialStateManager = new TokamakL2StateManager({ common: createTokamakL2Common() });
  const initialAddresses = [getAddress(controllerAddress), getAddress(vaultAddress)]
    .map((address) => createAddressFromString(address));
  await initialStateManager._initializeForAddresses(initialAddresses);
  initialStateManager._channelId = channelId;
  for (const address of initialAddresses) {
    initialStateManager._commitResolvedStorageEntries(address, []);
  }
  const initialSnapshot = await initialStateManager.captureStateSnapshot();
  const depositStateManager = await buildStateManager(initialSnapshot, contractCodes);

  for (const participant of participants) {
    participant.noteReceive = await deriveNoteReceiveKeyMaterial({
      signer: participant.l1,
      chainId: 31337,
      channelId,
      channelName,
      account: participant.l1.address,
    });
  }

  const participantKeys = new Map();
  for (const participant of participants) {
    const key = mappingKeyHex(participant.l2Address, liquidBalancesSlot);
    participantKeys.set(participant.index, key);
  }
  expect(new Set([...participantKeys.values()].map((value) => value.toLowerCase())).size === participants.length,
    "Participant vault keys must be unique.");

  const depositTransitions = [];
  for (const participant of participants) {
    depositTransitions.push(
      await buildGrothTransition(
        `deposit-user-${participant.index}`,
        depositStateManager,
        vaultAddress,
        participantKeys.get(participant.index),
        depositAmount,
      ),
    );
  }

  const postDepositSnapshot = depositTransitions[depositTransitions.length - 1].nextSnapshot;

  const encryptedTransfers = {
    aToB: buildEncryptedTransferOutput({
      owner: participants[1].l2Address,
      value: 1n * amountUnit,
      label: "private-state-e2e:a-to-b",
      recipientNoteReceivePubKey: participants[1].noteReceive.noteReceivePubKey,
      chainId: 31337,
      channelId,
    }),
    aToC: buildEncryptedTransferOutput({
      owner: participants[2].l2Address,
      value: 2n * amountUnit,
      label: "private-state-e2e:a-to-c",
      recipientNoteReceivePubKey: participants[2].noteReceive.noteReceivePubKey,
      chainId: 31337,
      channelId,
    }),
    bToC: buildEncryptedTransferOutput({
      owner: participants[2].l2Address,
      value: 4n * amountUnit,
      label: "private-state-e2e:b-to-c",
      recipientNoteReceivePubKey: participants[2].noteReceive.noteReceivePubKey,
      chainId: 31337,
      channelId,
    }),
  };
  const encryptedMints = {
    aMint: buildEncryptedMintOutput({
      owner: participants[0].l2Address,
      ownerNoteReceivePubKey: participants[0].noteReceive.noteReceivePubKey,
      value: depositAmount,
      label: "private-state-e2e:a-mint",
      chainId: 31337,
      channelId,
    }),
    bMint: buildEncryptedMintOutput({
      owner: participants[1].l2Address,
      ownerNoteReceivePubKey: participants[1].noteReceive.noteReceivePubKey,
      value: depositAmount,
      label: "private-state-e2e:b-mint",
      chainId: 31337,
      channelId,
    }),
    cMint: buildEncryptedMintOutput({
      owner: participants[2].l2Address,
      ownerNoteReceivePubKey: participants[2].noteReceive.noteReceivePubKey,
      value: depositAmount,
      label: "private-state-e2e:c-mint",
      chainId: 31337,
      channelId,
    }),
  };

  const notes = {
    aMint: encryptedMints.aMint.note,
    bMint: encryptedMints.bMint.note,
    cMint: encryptedMints.cMint.note,
    aToB: encryptedTransfers.aToB.note,
    aToC: encryptedTransfers.aToC.note,
    bToC: encryptedTransfers.bToC.note,
  };

  const tokamakScenarios = [
    {
      name: "mint-a",
      sender: participants[0],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData(
        "mintNotes1",
        [[[
          encryptedMints.aMint.output.value,
          encryptedNoteValueTuple(encryptedMints.aMint.output.encryptedNoteValue),
        ]]],
      ),
    },
    {
      name: "mint-b",
      sender: participants[1],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData(
        "mintNotes1",
        [[[
          encryptedMints.bMint.output.value,
          encryptedNoteValueTuple(encryptedMints.bMint.output.encryptedNoteValue),
        ]]],
      ),
    },
    {
      name: "mint-c",
      sender: participants[2],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData(
        "mintNotes1",
        [[[
          encryptedMints.cMint.output.value,
          encryptedNoteValueTuple(encryptedMints.cMint.output.encryptedNoteValue),
        ]]],
      ),
    },
    {
      name: "transfer-a-1-to-2",
      sender: participants[0],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData(
        "transferNotes1To2",
        [
          [
            [
              encryptedTransfers.aToB.output.owner,
              encryptedTransfers.aToB.output.value,
              encryptedNoteValueTuple(encryptedTransfers.aToB.output.encryptedNoteValue),
            ],
            [
              encryptedTransfers.aToC.output.owner,
              encryptedTransfers.aToC.output.value,
              encryptedNoteValueTuple(encryptedTransfers.aToC.output.encryptedNoteValue),
            ],
          ],
          [[notes.aMint.owner, notes.aMint.value, notes.aMint.salt]],
        ],
      ),
    },
    {
      name: "transfer-b-2-to-1",
      sender: participants[1],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData(
        "transferNotes2To1",
        [
          [
            [
              encryptedTransfers.bToC.output.owner,
              encryptedTransfers.bToC.output.value,
              encryptedNoteValueTuple(encryptedTransfers.bToC.output.encryptedNoteValue),
            ],
          ],
          [
            [notes.bMint.owner, notes.bMint.value, notes.bMint.salt],
            [notes.aToB.owner, notes.aToB.value, notes.aToB.salt],
          ],
        ],
      ),
    },
    {
      name: "redeem-c-a-to-c",
      sender: participants[2],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData(
        "redeemNotes1",
        [
          [
            [notes.aToC.owner, notes.aToC.value, notes.aToC.salt],
          ],
          participants[2].l2Address,
        ],
      ),
    },
    {
      name: "redeem-c-b-to-c",
      sender: participants[2],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData(
        "redeemNotes1",
        [
          [
            [notes.bToC.owner, notes.bToC.value, notes.bToC.salt],
          ],
          participants[2].l2Address,
        ],
      ),
    },
    {
      name: "redeem-c-own",
      sender: participants[2],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData(
        "redeemNotes1",
        [
          [
            [notes.cMint.owner, notes.cMint.value, notes.cMint.salt],
          ],
          participants[2].l2Address,
        ],
      ),
    },
  ];

  const metadataRun = await materializeTokamakResults(
    tokamakScenarios,
    postDepositSnapshot,
    bootstrapBlockInfo,
    contractCodes,
    options,
  );

  const dApps = buildDAppDefinitions(metadataRun.tokamakResults.map((result) => result.metadataRecord));
  expect(dApps.length === 1, `Expected one derived DApp, found ${dApps.length}.`);
  const derivedDApp = dApps[0];
  const uniqueAPubBlockHashes = new Set(metadataRun.tokamakResults.map((result) => result.metadataRecord.aPubBlockHash.toLowerCase()));
  expect(uniqueAPubBlockHashes.size === 1, "All Tokamak steps must share one aPubBlockHash for the channel.");

  console.log("E2E: deploying bridge stack.");
  const bridgeDeployment = await deployBridgeStack();
  const bridgeDeployer = new Wallet(anvilDeployerPrivateKey, provider);
  const bridgeCore = new Contract(bridgeDeployment.bridgeCore, bridgeCoreAbi, bridgeDeployer);
  const canonicalAssetAddress = getAddress(await bridgeCore.canonicalAsset());
  const mockAssetCode = await provider.getCode(bridgeDeployment.mockAsset);
  expect(mockAssetCode !== "0x", "Mock asset deployment must exist before installing canonical asset code.");
  await provider.send("anvil_setCode", [canonicalAssetAddress, mockAssetCode]);
  const asset = new Contract(canonicalAssetAddress, mockErc20Abi, bridgeDeployer);
  const dAppManager = new Contract(bridgeDeployment.dAppManager, dAppManagerAbi, bridgeDeployer);
  let bridgeDeployerNonce = await provider.getTransactionCount(bridgeDeployer.address, "latest");
  const participantNonces = new Map();
  for (const participant of participants) {
    participantNonces.set(
      participant.l1.address,
      await provider.getTransactionCount(participant.l1.address, "latest"),
    );
  }

  for (const participant of participants) {
    console.log(`E2E: funding L1 wallet ${participant.l1.address}.`);
    await (
      await asset.mint(participant.l1.address, depositAmount + joinFee, { nonce: bridgeDeployerNonce++ })
    ).wait();
  }

  console.log("E2E: registering derived DApp on bridge.");
  await (
    await dAppManager.registerDApp(
      dappId,
      keccak256(ethers.toUtf8Bytes("private-state-e2e")),
      toStorageMetadata(derivedDApp.storageMetadata),
      toFunctionMetadata(derivedDApp.functions),
      { nonce: bridgeDeployerNonce++ },
    )
  ).wait();

  console.log("E2E: creating channel.");
  await (
    await bridgeCore.createChannel(channelId, dappId, leader, joinFee, { nonce: bridgeDeployerNonce++ })
  ).wait();
  const channelDeployment = await bridgeCore.getChannel(channelId);

  const channelManager = new Contract(channelDeployment.manager, channelManagerAbi, deployer);
  const channelBlockInfo = await getBlockInfoAt(provider, Number(await channelManager.genesisBlockNumber()));
  const channelAPubBlockHash = hashTokamakPublicInputs(encodeTokamakBlockInfo(channelBlockInfo));
  expect(
    normalizeBytes32Hex(channelAPubBlockHash) === normalizeBytes32Hex(channelDeployment.aPubBlockHash),
    "Derived channel block_info hash must match the stored channel aPubBlockHash.",
  );
  const bridgeTokenVault = new Contract(channelDeployment.bridgeTokenVault, bridgeTokenVaultAbi, deployer);

  const executionRun = await materializeTokamakResults(
    tokamakScenarios,
    postDepositSnapshot,
    channelBlockInfo,
    contractCodes,
    options,
  );
  const tokamakResults = executionRun.tokamakResults;
  const finalRedeemSnapshot = executionRun.finalSnapshot;
  const postRedeemStateManager = await buildStateManager(finalRedeemSnapshot, contractCodes);
  const withdrawTransition = await buildGrothTransition(
    "withdraw-c",
    postRedeemStateManager,
    vaultAddress,
    participantKeys.get(participants[2].index),
    0n,
  );

  for (const participant of participants) {
    console.log(`E2E: approving and funding bridge vault for ${participant.l1.address}.`);
    const participantAsset = asset.connect(participant.l1);
    await (
      await participantAsset.approve(
        channelDeployment.bridgeTokenVault,
        depositAmount + joinFee,
        { nonce: consumeAccountNonce(participantNonces, participant.l1.address) },
      )
    ).wait();
    await (
      await bridgeTokenVault.connect(participant.l1).fund(depositAmount, {
        nonce: consumeAccountNonce(participantNonces, participant.l1.address),
      })
    ).wait();
    await (
      await bridgeTokenVault.connect(participant.l1).joinChannel(
        channelId,
        participant.l2Address,
        participantKeys.get(participant.index),
        deriveLeafIndex(participantKeys.get(participant.index)),
        participant.noteReceive.noteReceivePubKey,
        { nonce: consumeAccountNonce(participantNonces, participant.l1.address) },
      )
    ).wait();
  }

  for (let index = 0; index < participants.length; index += 1) {
    const participant = participants[index];
    const depositTransition = depositTransitions[index];
    console.log(`E2E: applying Groth deposit for participant ${participant.index}.`);
    await (
      await bridgeTokenVault.connect(participant.l1).deposit(
        channelId,
        depositTransition.proof,
        depositTransition.update,
        { nonce: consumeAccountNonce(participantNonces, participant.l1.address) },
      )
    ).wait();
  }

  let onchainRootVectorHash = await channelManager.currentRootVectorHash();
  expect(
    normalizeBytes32Hex(onchainRootVectorHash)
      === normalizeBytes32Hex(hashRootVector(tokamakResults[0].previousSnapshot.stateRoots)),
    "Bridge roots must match the first Tokamak step pre-state after Groth deposits.",
  );

  for (const result of tokamakResults) {
    console.log(`E2E: submitting Tokamak proof for ${result.scenario.name}.`);
    await (await channelManager.executeChannelTransaction(result.payload, { nonce: bridgeDeployerNonce++ })).wait();

    onchainRootVectorHash = await channelManager.currentRootVectorHash();
    expect(
      normalizeBytes32Hex(onchainRootVectorHash)
        === normalizeBytes32Hex(hashRootVector(result.nextSnapshot.stateRoots)),
      `Bridge roots must match Tokamak post-state for ${result.scenario.name}.`,
    );
    console.log(`E2E: Tokamak proof accepted for ${result.scenario.name}.`);
  }

  console.log("E2E: applying final Groth withdrawal for account C.");
  await (
    await bridgeTokenVault.connect(participants[2].l1).withdraw(
      channelId,
      withdrawTransition.proof,
      withdrawTransition.update,
      { nonce: consumeAccountNonce(participantNonces, participants[2].l1.address) },
    )
  ).wait();

  const cBalanceBeforeClaim = await asset.balanceOf(participants[2].l1.address);
  console.log("E2E: claiming ERC-20 back to account C.");
  await (
    await bridgeTokenVault.connect(participants[2].l1).claimToWallet(
      9n * amountUnit,
      { nonce: consumeAccountNonce(participantNonces, participants[2].l1.address) },
    )
  ).wait();
  const cBalanceAfterClaim = await asset.balanceOf(participants[2].l1.address);

  const accountA = await bridgeTokenVault.availableBalanceOf(participants[0].l1.address);
  const accountB = await bridgeTokenVault.availableBalanceOf(participants[1].l1.address);
  const accountC = await bridgeTokenVault.availableBalanceOf(participants[2].l1.address);

  expect(accountA === 0n, "Account A should have no L1-claimable balance after transferring all value.");
  expect(accountB === 0n, "Account B should have no L1-claimable balance after transferring all value.");
  expect(accountC === 0n, "Account C should have no remaining L1-claimable balance after claiming.");
  expect(cBalanceAfterClaim - cBalanceBeforeClaim === 9n * amountUnit, "Account C must receive the full redeemed amount.");

  const summary = {
    providerUrl,
    channelName,
    channelId,
    dappId,
    bridgeDeployment,
    privateStateDeployment: appDeployment,
    participants: participants.map((participant) => ({
      index: participant.index,
      l1Address: participant.l1.address,
      l2Address: participant.l2Address,
      liquidBalanceStorageKey: participantKeys.get(participant.index),
    })),
    tokamakSteps: tokamakResults.map((result) => ({
      name: result.scenario.name,
      directory: result.stepDir,
      functionSig: functionSelectorHex(result.scenario.calldata),
      previousRoots: result.previousSnapshot.stateRoots,
      updatedRoots: result.nextSnapshot.stateRoots,
    })),
    finalWithdraw: {
      directory: withdrawTransition.stepDir,
      currentRootVector: withdrawTransition.update.currentRootVector,
      updatedRoot: withdrawTransition.update.updatedRoot,
      key: withdrawTransition.update.currentUserKey,
      amount: (9n * amountUnit).toString(),
    },
  };
  writeJson(summaryPath, summary);

  console.log("E2E private-state bridge flow succeeded.");
  console.log(`Summary: ${summaryPath}`);

  if (!options.keepAnvil) {
    run("make", ["-C", appRoot, "anvil-stop"], { cwd: repoRoot });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
