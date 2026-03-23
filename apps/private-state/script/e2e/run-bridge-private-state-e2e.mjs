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
import { buildDAppDefinitions, buildFunctionDefinition, writeJson } from "../../../../script/zk/lib/tokamak-artifacts.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
const appRoot = path.resolve(repoRoot, "apps", "private-state");
const bridgeRoot = path.resolve(repoRoot, "bridge");
const tokamakRoot = path.resolve(repoRoot, "submodules", "Tokamak-zk-EVM");
const tokamakCliPath = path.resolve(tokamakRoot, "tokamak-cli");
const outputRoot = path.resolve(appRoot, "script", "e2e", "output", "private-state-bridge-genesis");
const deploymentManifestPath = path.resolve(appRoot, "deploy", "deployment.31337.latest.json");
const storageLayoutManifestPath = path.resolve(appRoot, "deploy", "storage-layout.31337.latest.json");
const controllerAbiPath = path.resolve(appRoot, "deploy", "PrivateStateController.callable-abi.json");
const bridgeDeploymentArtifactPath = path.resolve(bridgeRoot, "deployments", "private-state-bridge-e2e-latest.json");
const bridgeDeploymentSummaryPath = path.resolve(outputRoot, "bridge-deployment.json");
const grothInputDir = path.resolve(outputRoot, "groth-inputs");
const tokamakStepsDir = path.resolve(outputRoot, "tokamak-steps");
const summaryPath = path.resolve(outputRoot, "summary.json");
const providerUrl = process.env.ANVIL_RPC_URL?.trim() || "http://127.0.0.1:8545";
const anvilMnemonic = process.env.APPS_ANVIL_MNEMONIC?.trim() || "test test test test test test test test test test test junk";
const anvilDeployerPrivateKey =
  process.env.APPS_ANVIL_DEPLOYER_PRIVATE_KEY?.trim()
    || "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const channelId = 1;
const dappId = 1;
const rootZero = "0x0ce3a78a0131c84050bbe2205642f9e176ffe98488dbddb19336b987420f3bde";
const amountUnit = 10n ** 18n;
const depositAmount = 3n * amountUnit;
const blsScalarFieldModulus = BigInt("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");
const abiCoder = AbiCoder.defaultAbiCoder();
const deployerAddress = new Wallet(anvilDeployerPrivateKey).address;
const bridgeCoreAbi = [
  "function createChannel(uint256 channelId, uint256 dappId, address leader, address asset, bytes32 aPubBlockHash) external returns (address manager, address vault)",
  "function getChannel(uint256 channelId) external view returns (tuple(bool exists,uint256 dappId,address leader,address asset,address manager,address vault,bytes32 aPubBlockHash))",
];
const dAppManagerAbi = [
  "function registerDApp(uint256 dappId, bytes32 labelHash, tuple(address storageAddr, bytes32[] preAllocatedKeys, uint8[] userStorageSlots, bool isTokenVaultStorage)[] storages, tuple(address entryContract, bytes4 functionSig, address[] storageAddrs, bytes32 preprocessInputHash)[] functions) external",
];
const channelManagerAbi = [
  "function getCurrentRootVector() external view returns (bytes32[] memory)",
  "function submitTokamakProof(bytes proof, (bytes32[] currentRootVector, bytes32[] updatedRootVector, address entryContract, bytes4 functionSig) instance) external returns (bool)",
];
const tokenVaultAbi = [
  "function registerAndFund(bytes32 l2TokenVaultKey, uint256 amount) external",
  "function deposit((uint256[4] pA,uint256[8] pB,uint256[4] pC) proof, (bytes32 currentRoot,bytes32 updatedRoot,bytes32 currentUserKey,uint256 currentUserValue,bytes32 updatedUserKey,uint256 updatedUserValue) update) external returns (bool)",
  "function withdraw((uint256[4] pA,uint256[8] pB,uint256[4] pC) proof, (bytes32 currentRoot,bytes32 updatedRoot,bytes32 currentUserKey,uint256 currentUserValue,bytes32 updatedUserKey,uint256 updatedUserValue) update) external returns (bool)",
  "function claimToWallet(uint256 amount) external",
  "function getRegistration(address user) external view returns (tuple(bool exists, bytes32 l2TokenVaultKey, uint256 leafIndex, uint256 availableBalance))",
];
const mockErc20Abi = [
  "function mint(address to, uint256 amount) external",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
];

function usage() {
  console.log(`Usage:
  node apps/private-state/script/e2e/run-bridge-private-state-e2e.mjs [options]

Options:
  --install-arg <ALCHEMY_API_KEY|ALCHEMY_RPC_URL>  Run tokamak-cli --install before the flow
  --keep-anvil                                    Leave anvil running after success
  --help                                          Show this help
`);
}

function parseArgs(argv) {
  const options = {
    installArg: null,
    keepAnvil: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    const next = argv[index + 1];
    switch (current) {
      case "--install-arg":
        if (!next || next.startsWith("--")) {
          throw new Error("Missing value for --install-arg.");
        }
        options.installArg = next;
        index += 1;
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
  return ethers.zeroPadValue(hexValue, 32);
}

function buildL1Wallet(index, provider) {
  const node = HDNodeWallet.fromPhrase(anvilMnemonic, undefined, `m/44'/60'/0'/0/${index}`);
  return node.connect(provider);
}

function buildParticipant(index) {
  const signature = ethers.id(`private-state participant ${index}`);
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
  const blockNumber = Math.max(latestNumber, 4);
  const blockTag = ethers.toQuantity(blockNumber);
  const block = await rpcCall(provider, "eth_getBlockByNumber", [blockTag, false]);
  const prevBlockHashes = [];
  for (let offset = 1; offset <= 4; offset += 1) {
    const previousBlock =
      await rpcCall(provider, "eth_getBlockByNumber", [ethers.toQuantity(blockNumber - offset), false]);
    prevBlockHashes.push(previousBlock.hash);
  }
  const chainId = await rpcCall(provider, "eth_chainId", []);
  return {
    coinBase: block.miner,
    timeStamp: block.timestamp,
    blockNumber: block.number,
    prevRanDao: block.prevRandao ?? block.difficulty ?? "0x0",
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
    const code = await provider.getCode(address);
    codes.push({
      address: getAddress(address),
      code,
    });
  }
  return codes;
}

function buildGenesisSnapshot(controllerAddress, vaultAddress) {
  return {
    channelId,
    stateRoots: [rootZero, rootZero],
    storageAddresses: [getAddress(controllerAddress), getAddress(vaultAddress)],
    storageEntries: [[], []],
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
  const encoded = abiCoder.encode(["address", "uint256"], [address, slot]);
  return bytesToHex(poseidon(hexToBytes(encoded)));
}

function bigintToHex32(value) {
  return ethers.zeroPadValue(ethers.toBeHex(value), 32);
}

function saltHex(label) {
  const raw = BigInt(ethers.id(label));
  const normalized = (raw % (blsScalarFieldModulus - 1n)) + 1n;
  return bytes32FromHex(ethers.toBeHex(normalized));
}

function note(owner, value, saltLabel) {
  return {
    owner: getAddress(owner),
    value,
    salt: saltHex(saltLabel),
  };
}

function serializeBigInts(value) {
  return JSON.parse(JSON.stringify(value, (_key, current) => (
    typeof current === "bigint" ? current.toString() : current
  )));
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
    storageEntries: snapshot.storageEntries.map((entries) => entries
      .filter((entry) => !isZeroLikeStorageValue(entry.value))
      .map((entry) => ({
        key: entry.key.toLowerCase(),
        value: entry.value.toLowerCase(),
      }))),
  };
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

function copyTokamakArtifacts(stepDir) {
  const resourceRoot = path.join(stepDir, "resource");
  cleanDir(resourceRoot);
  fs.cpSync(path.join(tokamakRoot, "dist", "resource"), resourceRoot, { recursive: true });
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
    aPubBlock: instanceJson.a_pub_block.map((value) => BigInt(value)),
  };
}

function encodeTokamakPayload(payload) {
  return abiCoder.encode(
    ["tuple(uint128[] proofPart1,uint256[] proofPart2,uint128[] functionPreprocessPart1,uint256[] functionPreprocessPart2,uint256[] aPubUser,uint256[] aPubBlock)"],
    [[
      payload.proofPart1,
      payload.proofPart2,
      payload.functionPreprocessPart1,
      payload.functionPreprocessPart2,
      payload.aPubUser,
      payload.aPubBlock,
    ]],
  );
}

function functionSelectorHex(calldata) {
  return calldata.slice(0, 10);
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
  run(tokamakCliPath, ["--preprocess"], { cwd: tokamakRoot });
  run(tokamakCliPath, ["--prove"], { cwd: tokamakRoot });

  const bundlePath = path.join(stepDir, `${step.name}.zip`);
  run(tokamakCliPath, ["--extract-proof", bundlePath], { cwd: tokamakRoot });
  run(tokamakCliPath, ["--verify", bundlePath], { cwd: tokamakRoot });

  copyTokamakArtifacts(stepDir);

  const nextSnapshot = normalizeStateSnapshot(
    readJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.json")),
  );
  writeJson(path.join(stepDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"), nextSnapshot);
  const metadataRecord = buildFunctionDefinition({
    groupName: "private-state-e2e",
    exampleName: step.name,
    transactionJsonPath: path.join(stepDir, "transaction.json"),
    snapshotJsonPath: path.join(stepDir, "previous_state_snapshot.json"),
    preprocessJsonPath: path.join(stepDir, "resource", "preprocess", "output", "preprocess.json"),
    instanceJsonPath: path.join(stepDir, "resource", "synthesizer", "output", "instance.json"),
  });

  return {
    stepDir,
    transactionSnapshot,
    metadataRecord,
    payload: loadTokamakPayloadFromStep(stepDir),
    nextSnapshot,
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

  await stateManager.putStorage(vaultAddressObj, hexToBytes(keyHex), hexToBytes(bigintToHex32(nextValue)));
  const updatedRoot = stateManager.merkleTrees.getRoot(vaultAddressObj);

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

  run("node", ["groth16/prover/updateTree/generateProof.mjs", "--input", inputPath], { cwd: repoRoot });

  const proofJson = readJson(path.join(repoRoot, "groth16", "prover", "updateTree", "proof.json"));
  const publicSignals = readJson(path.join(repoRoot, "groth16", "prover", "updateTree", "public.json"));

  writeJson(path.join(stepDir, "proof.json"), proofJson);
  writeJson(path.join(stepDir, "public.json"), publicSignals);

  const solidityProof = toGrothSolidityProof(proofJson);
  const grothUpdate = {
    currentRoot: bytes32FromHex(ethers.toBeHex(currentRoot)),
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
    nextSnapshot: await stateManager.captureStateSnapshot(),
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
    BRIDGE_OUTPUT_PATH: bridgeDeploymentArtifactPath,
    BRIDGE_DEPLOY_MOCK_ASSET: "true",
  };

  run(
    "forge",
    ["script", "script/DeployBridgeStack.s.sol:DeployBridgeStackScript", "--sig", "run()"],
    { cwd: bridgeRoot, env },
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
    isTokenVaultStorage: entry.isTokenVaultStorage,
  }));
}

function toFunctionMetadata(entries) {
  return entries.map((entry) => ({
    entryContract: entry.entryContract,
    functionSig: entry.functionSig,
    storageAddrs: entry.storageAddresses,
    preprocessInputHash: entry.preprocessInputHash,
  }));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  cleanDir(outputRoot);
  ensureDir(grothInputDir);
  ensureDir(tokamakStepsDir);

  await bootstrapAnvil();

  if (options.installArg !== null) {
    run(tokamakCliPath, ["--install", options.installArg], { cwd: tokamakRoot });
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
  const blockInfo = await getFixedBlockInfo(provider);
  const blockHash = keccak256(abiCoder.encode(["uint256[]"], [blockInfo.prevBlockHashes.concat([
    blockInfo.coinBase,
  ])]));
  void blockHash;

  const initialSnapshot = buildGenesisSnapshot(controllerAddress, vaultAddress);
  const depositStateManager = await buildStateManager(initialSnapshot, contractCodes);

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

  let currentSnapshot = depositTransitions[depositTransitions.length - 1].nextSnapshot;

  const notes = {
    aMint: note(participants[0].l2Address, depositAmount, "private-state-e2e:a-mint"),
    bMint: note(participants[1].l2Address, depositAmount, "private-state-e2e:b-mint"),
    cMint: note(participants[2].l2Address, depositAmount, "private-state-e2e:c-mint"),
    aToB: note(participants[1].l2Address, 1n * amountUnit, "private-state-e2e:a-to-b"),
    aToC: note(participants[2].l2Address, 2n * amountUnit, "private-state-e2e:a-to-c"),
    bToC: note(participants[2].l2Address, 4n * amountUnit, "private-state-e2e:b-to-c"),
  };

  const tokamakScenarios = [
    {
      name: "mint-a",
      sender: participants[0],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData("mintNotes1", [[[notes.aMint.owner, notes.aMint.value, notes.aMint.salt]]]),
    },
    {
      name: "mint-b",
      sender: participants[1],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData("mintNotes1", [[[notes.bMint.owner, notes.bMint.value, notes.bMint.salt]]]),
    },
    {
      name: "mint-c",
      sender: participants[2],
      nonce: 0,
      controllerAddress,
      calldata: controllerInterface.encodeFunctionData("mintNotes1", [[[notes.cMint.owner, notes.cMint.value, notes.cMint.salt]]]),
    },
    {
      name: "transfer-a-1-to-2",
      sender: participants[0],
      nonce: 0,
      controllerAddress,
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
      name: "transfer-b-2-to-1",
      sender: participants[1],
      nonce: 0,
      controllerAddress,
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

  const tokamakResults = [];
  for (const scenario of tokamakScenarios) {
    const result = await runTokamakStep(scenario, currentSnapshot, blockInfo, contractCodes);
    tokamakResults.push({
      ...result,
      scenario,
      previousSnapshot: currentSnapshot,
    });
    currentSnapshot = result.nextSnapshot;
  }

  const finalRedeemSnapshot = currentSnapshot;
  const postRedeemStateManager = await buildStateManager(finalRedeemSnapshot, contractCodes);
  const withdrawTransition = await buildGrothTransition(
    "withdraw-c",
    postRedeemStateManager,
    vaultAddress,
    participantKeys.get(participants[2].index),
    0n,
  );

  const dApps = buildDAppDefinitions(tokamakResults.map((result) => result.metadataRecord));
  expect(dApps.length === 1, `Expected one derived DApp, found ${dApps.length}.`);
  const derivedDApp = dApps[0];
  const uniqueAPubBlockHashes = new Set(tokamakResults.map((result) => result.metadataRecord.aPubBlockHash.toLowerCase()));
  expect(uniqueAPubBlockHashes.size === 1, "All Tokamak steps must share one aPubBlockHash for the channel.");
  const aPubBlockHash = tokamakResults[0].metadataRecord.aPubBlockHash;

  const bridgeDeployment = await deployBridgeStack();
  const bridgeDeployer = new Wallet(anvilDeployerPrivateKey, provider);
  const asset = new Contract(bridgeDeployment.mockAsset, mockErc20Abi, bridgeDeployer);
  const dAppManager = new Contract(bridgeDeployment.dAppManager, dAppManagerAbi, bridgeDeployer);
  const bridgeCore = new Contract(bridgeDeployment.bridgeCore, bridgeCoreAbi, bridgeDeployer);
  let bridgeDeployerNonce = await provider.getTransactionCount(bridgeDeployer.address, "latest");

  for (const participant of participants) {
    await (await asset.mint(participant.l1.address, depositAmount, { nonce: bridgeDeployerNonce++ })).wait();
  }

  await (
    await dAppManager.registerDApp(
      dappId,
      keccak256(ethers.toUtf8Bytes("private-state-e2e")),
      toStorageMetadata(derivedDApp.storageMetadata),
      toFunctionMetadata(derivedDApp.functions),
      { nonce: bridgeDeployerNonce++ },
    )
  ).wait();

  await (
    await bridgeCore.createChannel(
      channelId,
      dappId,
      leader,
      bridgeDeployment.mockAsset,
      aPubBlockHash,
      { nonce: bridgeDeployerNonce++ },
    )
  ).wait();
  const channelDeployment = await bridgeCore.getChannel(channelId);

  const channelManager = new Contract(channelDeployment.manager, channelManagerAbi, deployer);
  const tokenVault = new Contract(channelDeployment.vault, tokenVaultAbi, deployer);

  for (const participant of participants) {
    const participantAsset = asset.connect(participant.l1);
    await (await participantAsset.approve(channelDeployment.vault, depositAmount)).wait();
    await (await tokenVault.connect(participant.l1).registerAndFund(participantKeys.get(participant.index), depositAmount)).wait();
  }

  for (let index = 0; index < participants.length; index += 1) {
    const participant = participants[index];
    const depositTransition = depositTransitions[index];
    await (
      await tokenVault.connect(participant.l1).deposit(depositTransition.proof, depositTransition.update)
    ).wait();
  }

  let onchainRoots = await channelManager.getCurrentRootVector();
  expect(
    JSON.stringify(onchainRoots.map((value) => value.toLowerCase()))
      === JSON.stringify(tokamakResults[0].previousSnapshot.stateRoots.map((value) => value.toLowerCase())),
    "Bridge roots must match the first Tokamak step pre-state after Groth deposits.",
  );

  for (const result of tokamakResults) {
    const payloadBytes = encodeTokamakPayload(result.payload);
    const instance = {
      currentRootVector: result.previousSnapshot.stateRoots,
      updatedRootVector: result.nextSnapshot.stateRoots,
      entryContract: result.scenario.controllerAddress,
      functionSig: functionSelectorHex(result.scenario.calldata),
    };
    await (await channelManager.submitTokamakProof(payloadBytes, instance)).wait();

    onchainRoots = await channelManager.getCurrentRootVector();
    expect(
      JSON.stringify(onchainRoots.map((value) => value.toLowerCase()))
        === JSON.stringify(result.nextSnapshot.stateRoots.map((value) => value.toLowerCase())),
      `Bridge roots must match Tokamak post-state for ${result.scenario.name}.`,
    );
  }

  await (
    await tokenVault.connect(participants[2].l1).withdraw(withdrawTransition.proof, withdrawTransition.update)
  ).wait();

  const cBalanceBeforeClaim = await asset.balanceOf(participants[2].l1.address);
  await (await tokenVault.connect(participants[2].l1).claimToWallet(9n * amountUnit)).wait();
  const cBalanceAfterClaim = await asset.balanceOf(participants[2].l1.address);

  const registrationA = await tokenVault.getRegistration(participants[0].l1.address);
  const registrationB = await tokenVault.getRegistration(participants[1].l1.address);
  const registrationC = await tokenVault.getRegistration(participants[2].l1.address);

  expect(registrationA.availableBalance === 0n, "Account A should have no L1-claimable balance after transferring all value.");
  expect(registrationB.availableBalance === 0n, "Account B should have no L1-claimable balance after transferring all value.");
  expect(registrationC.availableBalance === 0n, "Account C should have no remaining L1-claimable balance after claiming.");
  expect(cBalanceAfterClaim - cBalanceBeforeClaim === 9n * amountUnit, "Account C must receive the full redeemed amount.");

  const summary = {
    providerUrl,
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
      currentRoot: withdrawTransition.update.currentRoot,
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
