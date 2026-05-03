#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { AbiCoder, Contract, JsonRpcProvider, Wallet, ethers, getAddress, keccak256 } from "ethers";
import {
  createTimestampLabel,
  dappArtifactDir,
  dappArtifactPaths,
  requireLatestBridgeArtifactDir,
  requireLatestDappArtifactDir,
} from "../../scripts/deployment/lib/deployment-layout.mjs";
import {
  buildSourceCodeMetadata,
  PRIVATE_STATE_DAPP_SOURCE_PATHS,
} from "../../scripts/deployment/lib/source-code-metadata.mjs";
import { deriveRpcUrl, resolveAppNetwork } from "@tokamak-private-dapps/common-library/network-config";
import {
  buildTokamakCliInvocation,
  resolveTokamakBlockInputConfig,
  resolveTokamakCliPreprocessOutputDir,
  resolveTokamakCliSynthOutputDir,
} from "@tokamak-private-dapps/common-library/tokamak-runtime-paths";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const privateStateExampleRoot = path.join(
  repoRoot,
  "packages",
  "apps",
  "private-state",
  "examples",
  "synthesizer",
  "privateState",
);
const defaultArtifactsRoot = path.join(repoRoot, "bridge", "deployments", "dapp-registration-artifacts");
const uploadDappArtifactsScriptPath = path.join(
  repoRoot,
  "bridge",
  "scripts",
  "upload-dapp-artifacts.mjs",
);
const privateStateCliPackageJsonPath = path.join(
  repoRoot,
  "packages",
  "apps",
  "private-state",
  "cli",
  "package.json",
);
const abiCoder = AbiCoder.defaultAbiCoder();
const FUNCTION_ITEM_DOMAIN = keccak256(ethers.toUtf8Bytes("dapp.metadata.v1.function-item"));
const FUNCTION_MERKLE_NODE_DOMAIN = keccak256(ethers.toUtf8Bytes("dapp.metadata.v1.function-merkle-node"));
const INSTANCE_LAYOUT_DOMAIN = keccak256(ethers.toUtf8Bytes("dapp.metadata.v1.instance-layout"));
const EVENT_LOG_ROOT_DOMAIN = keccak256(ethers.toUtf8Bytes("dapp.metadata.v1.event-log-root"));
const EVENT_LOG_ITEM_DOMAIN = keccak256(ethers.toUtf8Bytes("dapp.metadata.v1.event-log-item"));
const { aPubBlockLength: TOKAMAK_APUB_BLOCK_LENGTH } = resolveTokamakBlockInputConfig();
const TIMESTAMP_LABEL_PATTERN = /^\d{8}T\d{6}Z$/;
const CAPACITY_ERROR_PATTERNS = [
  /insufficient .* length/i,
  /insufficient s_max/i,
  /ask the qap-compiler/i,
  /input signal array access exceeds the size/i,
  /failed to update constants\.circom/i,
];

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

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function copyDir(sourceDir, targetDir) {
  fs.rmSync(targetDir, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(targetDir), { recursive: true });
  fs.cpSync(sourceDir, targetDir, { recursive: true });
}

function copyFile(sourcePath, targetPath) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.copyFileSync(sourcePath, targetPath);
}

function readNpmPackageSource(packageJsonPath) {
  const packageJson = readJson(packageJsonPath);
  return {
    kind: "npm",
    name: packageJson.name,
    version: packageJson.version,
  };
}

function slugify(value) {
  return value
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}

function isCapacityError(output) {
  return CAPACITY_ERROR_PATTERNS.some((pattern) => pattern.test(output));
}

function toBigIntArray(values, label) {
  if (!Array.isArray(values)) {
    throw new Error(`${label} must be an array.`);
  }
  return values.map((value, index) => {
    try {
      return ethers.toBigInt(value);
    } catch (error) {
      throw new Error(`${label}[${index}] is not a valid integer: ${String(value)}`);
    }
  });
}

function findDescriptionOffset(entries, pattern, label, descriptionPath) {
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    if (typeof entry === "string" && pattern.test(entry)) {
      if (index > 0xff) {
        throw new Error(`${label} offset ${index} exceeds uint8 range in ${descriptionPath}.`);
      }
      return index;
    }
  }
  throw new Error(`Unable to locate ${label} in ${descriptionPath}.`);
}

function extractFunctionLayout(instanceDescriptionJsonPath) {
  const description = readJson(instanceDescriptionJsonPath);
  const entries = description.a_pub_user_description;
  if (!Array.isArray(entries)) {
    throw new Error(`instance_description.json is missing a_pub_user_description: ${instanceDescriptionJsonPath}`);
  }

  return {
    entryContractOffsetWords: findDescriptionOffset(
      entries,
      /^Contract address to call \(lower 16 bytes\)$/,
      "entry contract offset",
      instanceDescriptionJsonPath,
    ),
    functionSigOffsetWords: findDescriptionOffset(
      entries,
      /^Selector for a function to call \(lower 16 bytes\)$/,
      "function selector offset",
      instanceDescriptionJsonPath,
    ),
    currentRootVectorOffsetWords: findDescriptionOffset(
      entries,
      /^Initial Merkle tree root hash of 0x[0-9a-fA-F]{40} \(lower 16 bytes\)$/,
      "current root-vector offset",
      instanceDescriptionJsonPath,
    ),
    updatedRootVectorOffsetWords: findDescriptionOffset(
      entries,
      /^Resulting Merkle tree root hash of 0x[0-9a-fA-F]{40} \(lower 16 bytes\)$/,
      "updated root-vector offset",
      instanceDescriptionJsonPath,
    ),
  };
}

function hashTokamakPointEncoding(part1, part2) {
  return keccak256(abiCoder.encode(["uint128[]", "uint256[]"], [part1, part2]));
}

function hashTokamakPublicInputs(values) {
  return keccak256(abiCoder.encode(["uint256[]"], [values]));
}

function hashEventLogMetadata(eventLogs) {
  let eventLogsHash = keccak256(
    abiCoder.encode(["bytes32", "uint256"], [EVENT_LOG_ROOT_DOMAIN, eventLogs.length]),
  );
  for (const eventLog of eventLogs) {
    eventLogsHash = keccak256(
      abiCoder.encode(
        ["bytes32", "bytes32", "uint16", "uint8"],
        [EVENT_LOG_ITEM_DOMAIN, eventLogsHash, eventLog.startOffsetWords, eventLog.topicCount],
      ),
    );
  }
  return eventLogsHash;
}

function functionMetadataForManifest(fn) {
  return {
    entryContract: getAddress(fn.entryContract),
    functionSig: fn.functionSig,
    preprocessInputHash: normalizeBytes32(fn.preprocessInputHash),
    instanceLayout: {
      entryContractOffsetWords: fn.entryContractOffsetWords,
      functionSigOffsetWords: fn.functionSigOffsetWords,
      currentRootVectorOffsetWords: fn.currentRootVectorOffsetWords,
      updatedRootVectorOffsetWords: fn.updatedRootVectorOffsetWords,
      eventLogs: fn.eventLogs.map((eventLog) => ({
        startOffsetWords: eventLog.startOffsetWords,
        topicCount: eventLog.topicCount,
      })),
    },
  };
}

function hashFunctionMetadata(fn) {
  const metadata = functionMetadataForManifest(fn);
  const eventLogsHash = hashEventLogMetadata(metadata.instanceLayout.eventLogs);
  const instanceLayoutHash = keccak256(
    abiCoder.encode(
      ["bytes32", "uint8", "uint8", "uint8", "uint8", "bytes32"],
      [
        INSTANCE_LAYOUT_DOMAIN,
        metadata.instanceLayout.entryContractOffsetWords,
        metadata.instanceLayout.functionSigOffsetWords,
        metadata.instanceLayout.currentRootVectorOffsetWords,
        metadata.instanceLayout.updatedRootVectorOffsetWords,
        eventLogsHash,
      ],
    ),
  );
  return keccak256(
    abiCoder.encode(
      ["bytes32", "address", "bytes4", "bytes32", "bytes32"],
      [
        FUNCTION_ITEM_DOMAIN,
        metadata.entryContract,
        metadata.functionSig,
        metadata.preprocessInputHash,
        instanceLayoutHash,
      ],
    ),
  );
}

function hashFunctionMerklePair(left, right) {
  const [first, second] = ethers.toBigInt(left) <= ethers.toBigInt(right)
    ? [left, right]
    : [right, left];
  return keccak256(
    abiCoder.encode(["bytes32", "bytes32", "bytes32"], [FUNCTION_MERKLE_NODE_DOMAIN, first, second]),
  );
}

function computeFunctionMerkleRoot(leaves) {
  let level = leaves.slice();
  while (level.length > 1) {
    const next = [];
    for (let index = 0; index < level.length; index += 2) {
      const left = level[index];
      const right = index + 1 < level.length ? level[index + 1] : left;
      next.push(hashFunctionMerklePair(left, right));
    }
    level = next;
  }
  return level[0];
}

function buildFunctionMerkleProof(leaves, leafIndex) {
  const proof = [];
  let index = leafIndex;
  let level = leaves.slice();
  while (level.length > 1) {
    const siblingIndex = index % 2 === 0
      ? Math.min(index + 1, level.length - 1)
      : index - 1;
    proof.push(level[siblingIndex]);

    const next = [];
    for (let pairIndex = 0; pairIndex < level.length; pairIndex += 2) {
      const left = level[pairIndex];
      const right = pairIndex + 1 < level.length ? level[pairIndex + 1] : left;
      next.push(hashFunctionMerklePair(left, right));
    }
    index = Math.floor(index / 2);
    level = next;
  }
  return proof;
}

function buildFunctionMetadataProofs(functions) {
  const leaves = functions.map((fn) => hashFunctionMetadata(fn));
  const root = computeFunctionMerkleRoot(leaves);
  return {
    root,
    functions: functions.map((fn, index) => ({
      exampleNames: fn.exampleNames,
      metadata: functionMetadataForManifest(fn),
      merkleLeaf: leaves[index],
      merkleProof: buildFunctionMerkleProof(leaves, index),
    })),
  };
}

function normalizeTokamakAPubBlock(values) {
  let normalizedValues = values.slice();
  if (normalizedValues.length > TOKAMAK_APUB_BLOCK_LENGTH) {
    const trailingValues = normalizedValues.slice(TOKAMAK_APUB_BLOCK_LENGTH);
    if (!trailingValues.every((value) => value === 0n)) {
      throw new Error(
        `a_pub_block length ${normalizedValues.length} exceeds the fixed Tokamak block input length ${TOKAMAK_APUB_BLOCK_LENGTH}.`,
      );
    }
    normalizedValues = normalizedValues.slice(0, TOKAMAK_APUB_BLOCK_LENGTH);
  }
  return normalizedValues.concat(new Array(TOKAMAK_APUB_BLOCK_LENGTH - normalizedValues.length).fill(0n));
}

function extractTokamakRegistrationArtifacts(part1, part2, preprocessJsonPath) {
  if (part1.length !== 6 || part2.length !== 6) {
    throw new Error(
      `Unexpected preprocess layout in ${preprocessJsonPath}. Expected 3 G1 points encoded as 6 part1 and 6 part2 entries.`,
    );
  }

  const functionPreprocessPart1 = part1.slice(0, 4);
  const functionPreprocessPart2 = part2.slice(0, 4);
  const functionInstancePart1 = part1.slice(4, 6);
  const functionInstancePart2 = part2.slice(4, 6);

  return {
    functionInstancePart1,
    functionInstancePart2,
    functionPreprocessPart1,
    functionPreprocessPart2,
  };
}

function extractEventLogs(instanceDescriptionJsonPath) {
  const description = readJson(instanceDescriptionJsonPath);
  const entries = description.a_pub_user_description;
  if (!Array.isArray(entries)) {
    throw new Error(`instance_description.json is missing a_pub_user_description: ${instanceDescriptionJsonPath}`);
  }

  const eventLogs = [];
  const topicStartPattern =
    /^Log topic for LOG([0-4]) instruction, topic index: 0 \(lower 16 bytes\)$/;
  const valueStartPattern =
    /^Log value for LOG0 instruction, data index: 0 \(lower 16 bytes\)$/;

  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    if (typeof entry !== "string") {
      continue;
    }

    const topicMatch = entry.match(topicStartPattern);
    if (topicMatch) {
      eventLogs.push({
        startOffsetWords: index,
        topicCount: Number(topicMatch[1]),
      });
      continue;
    }

    if (valueStartPattern.test(entry)) {
      eventLogs.push({
        startOffsetWords: index,
        topicCount: 0,
      });
    }
  }

  return eventLogs;
}

function deriveFunctionSelectorFromTransaction(transactionJsonPath) {
  const transaction = readJson(transactionJsonPath);
  if (typeof transaction.data !== "string" || transaction.data.length < 10) {
    throw new Error(`Transaction data is missing a 4-byte selector: ${transactionJsonPath}`);
  }
  return transaction.data.slice(0, 10).toLowerCase();
}

function inferChannelTokenVaultStorageAddress(storageAddresses, entryContract) {
  if (!Array.isArray(storageAddresses) || storageAddresses.length === 0) {
    throw new Error("Snapshot does not declare any managed storage addresses.");
  }

  if (storageAddresses.length === 1) {
    return getAddress(storageAddresses[0]);
  }

  const normalizedEntryContract = getAddress(entryContract);
  const nonEntryStorageAddresses = storageAddresses
    .map((storageAddress) => getAddress(storageAddress))
    .filter((storageAddress) => storageAddress !== normalizedEntryContract);

  if (nonEntryStorageAddresses.length !== 1) {
    throw new Error(
      [
        "Unable to infer a unique token-vault storage address from the snapshot.",
        `Entry contract: ${normalizedEntryContract}.`,
        `Storage addresses: ${storageAddresses.join(", ")}.`,
      ].join(" "),
    );
  }

  return nonEntryStorageAddresses[0];
}

function deriveRegistrationMetadataFromSnapshot(snapshotJsonPath, entryContract) {
  const snapshot = readJson(snapshotJsonPath);
  if (!Array.isArray(snapshot.storageAddresses) || !Array.isArray(snapshot.storageKeys)) {
    throw new Error(`Snapshot is missing storage vectors: ${snapshotJsonPath}`);
  }
  if (snapshot.storageAddresses.length !== snapshot.storageKeys.length) {
    throw new Error(`storageAddresses/storageKeys length mismatch in ${snapshotJsonPath}`);
  }

  const channelTokenVaultStorageAddress = inferChannelTokenVaultStorageAddress(snapshot.storageAddresses, entryContract);

  return snapshot.storageAddresses.map((storageAddress, index) => ({
    storageAddress: getAddress(storageAddress),
    preAllocKeys: snapshot.storageKeys[index],
    userSlots: [],
    isChannelTokenVaultStorage:
      ethers.toBigInt(getAddress(storageAddress)) === ethers.toBigInt(channelTokenVaultStorageAddress),
  }));
}

function deriveEntryContractFromTransaction(transactionJsonPath) {
  const transaction = readJson(transactionJsonPath);
  if (typeof transaction.to !== "string") {
    throw new Error(`Transaction "to" is missing: ${transactionJsonPath}`);
  }
  return getAddress(transaction.to);
}

async function fetchTargetContractCodes(provider, appContext) {
  const contractAddresses = [
    appContext.entryContract,
    ...appContext.storageMetadata.map((entry) => entry.storageAddress),
  ];
  const uniqueAddresses = [];
  const seen = new Set();

  for (const address of contractAddresses) {
    const normalizedAddress = getAddress(address);
    const key = normalizedAddress.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    uniqueAddresses.push(normalizedAddress);
  }

  const contractCodes = [];
  for (const address of uniqueAddresses) {
    const code = await provider.getCode(address);
    if (code === "0x") {
      throw new Error(`No deployed bytecode found for target DApp contract at ${address}.`);
    }
    contractCodes.push({ address, code });
  }

  return contractCodes;
}

function materializeTargetExampleInputs({ entry, exampleOutputRoot, appContext, contractCodes }) {
  const inputRoot = path.join(exampleOutputRoot, "launch-input");
  ensureDir(inputRoot);

  const transaction = readJson(entry.files.transaction);
  if (getAddress(transaction.to) !== appContext.entryContract) {
    throw new Error(
      [
        `Transaction target ${transaction.to} does not match target DApp entry contract ${appContext.entryContract}.`,
        `Refusing to rewrite ${entry.files.transaction} because Tokamak L2 signatures bind the target address.`,
        "Regenerate the registration launch inputs for the target deployment before registering the DApp.",
      ].join(" "),
    );
  }

  const previousState = readJson(entry.files.previousState);
  if (!Array.isArray(previousState.storageAddresses)) {
    throw new Error(`previous_state_snapshot.json is missing storageAddresses: ${entry.files.previousState}`);
  }
  if (previousState.storageAddresses.length !== appContext.storageMetadata.length) {
    throw new Error(
      [
        `Storage address vector length mismatch for ${entry.files.previousState}.`,
        `Example has ${previousState.storageAddresses.length}, target DApp has ${appContext.storageMetadata.length}.`,
      ].join(" "),
    );
  }
  const targetStorageAddresses = appContext.storageMetadata.map((storage) => storage.storageAddress);
  for (let index = 0; index < targetStorageAddresses.length; index += 1) {
    if (getAddress(previousState.storageAddresses[index]) !== targetStorageAddresses[index]) {
      throw new Error(
        [
          `Snapshot storage address ${previousState.storageAddresses[index]} at index ${index}`,
          `does not match target DApp storage address ${targetStorageAddresses[index]}.`,
          `Regenerate ${entry.files.previousState} for the target deployment before registering the DApp.`,
        ].join(" "),
      );
    }
  }

  const files = {
    previousState: path.join(inputRoot, "previous_state_snapshot.json"),
    transaction: path.join(inputRoot, "transaction.json"),
    blockInfo: path.join(inputRoot, "block_info.json"),
    contractCode: path.join(inputRoot, "contract_codes.json"),
  };

  copyFile(entry.files.previousState, files.previousState);
  copyFile(entry.files.transaction, files.transaction);
  copyFile(entry.files.blockInfo, files.blockInfo);
  writeJson(files.contractCode, contractCodes);

  return files;
}

function buildFunctionDefinition({
  groupName,
  exampleName,
  transactionJsonPath,
  snapshotJsonPath,
  preprocessJsonPath,
  instanceJsonPath,
  instanceDescriptionJsonPath,
  entryContractOverride,
  storageMetadataOverride,
}) {
  const selector = deriveFunctionSelectorFromTransaction(transactionJsonPath);
  const derivedEntryContract = deriveEntryContractFromTransaction(transactionJsonPath);
  const derivedStorageMetadata = deriveRegistrationMetadataFromSnapshot(snapshotJsonPath, derivedEntryContract);
  const instance = readJson(instanceJsonPath);
  const preprocess = readJson(preprocessJsonPath);
  const preprocessPart1 = toBigIntArray(preprocess.preprocess_entries_part1, "preprocess_entries_part1");
  const preprocessPart2 = toBigIntArray(preprocess.preprocess_entries_part2, "preprocess_entries_part2");
  const extracted = extractTokamakRegistrationArtifacts(preprocessPart1, preprocessPart2, preprocessJsonPath);
  const eventLogs = extractEventLogs(instanceDescriptionJsonPath);
  const functionLayout = extractFunctionLayout(instanceDescriptionJsonPath);
  const entryContract = entryContractOverride ? getAddress(entryContractOverride) : derivedEntryContract;
  const storageMetadata = storageMetadataOverride
    ? storageMetadataOverride.map((entry) => ({
      storageAddress: getAddress(entry.storageAddress),
      preAllocKeys: [...entry.preAllocKeys],
      userSlots: [...entry.userSlots],
      isChannelTokenVaultStorage: entry.isChannelTokenVaultStorage,
    }))
    : derivedStorageMetadata;

  return {
    groupName,
    exampleName,
    functionSig: selector,
    entryContract,
    storageAddresses: storageMetadata.map((entry) => entry.storageAddress),
    storageMetadata,
    preprocessInputHash: hashTokamakPointEncoding(preprocessPart1, preprocessPart2),
    entryContractOffsetWords: functionLayout.entryContractOffsetWords,
    functionSigOffsetWords: functionLayout.functionSigOffsetWords,
    currentRootVectorOffsetWords: functionLayout.currentRootVectorOffsetWords,
    updatedRootVectorOffsetWords: functionLayout.updatedRootVectorOffsetWords,
    eventLogs,
    aPubBlockHash: hashTokamakPublicInputs(
      normalizeTokamakAPubBlock(toBigIntArray(instance.a_pub_block, "a_pub_block")),
    ),
    functionInstancePart1: extracted.functionInstancePart1.map((value) => value.toString()),
    functionInstancePart2: extracted.functionInstancePart2.map((value) => value.toString()),
    functionPreprocessPart1: extracted.functionPreprocessPart1.map((value) => value.toString()),
    functionPreprocessPart2: extracted.functionPreprocessPart2.map((value) => value.toString()),
  };
}

function mergeStorageMetadata(records) {
  const merged = new Map();

  for (const record of records) {
    for (const storage of record.storageMetadata) {
      const existing = merged.get(storage.storageAddress);
      if (!existing) {
        merged.set(storage.storageAddress, {
          storageAddress: storage.storageAddress,
          preAllocKeys: [...storage.preAllocKeys],
          userSlots: [...storage.userSlots],
          isChannelTokenVaultStorage: storage.isChannelTokenVaultStorage,
        });
        continue;
      }

      const keySet = new Set(existing.preAllocKeys);
      for (const key of storage.preAllocKeys) {
        keySet.add(key);
      }
      existing.preAllocKeys = [...keySet];

      const slotSet = new Set(existing.userSlots);
      for (const slot of storage.userSlots) {
        slotSet.add(slot);
      }
      existing.userSlots = [...slotSet].sort((a, b) => a - b);

      if (existing.isChannelTokenVaultStorage !== storage.isChannelTokenVaultStorage) {
        throw new Error(
          `Conflicting token-vault classification for storage address ${storage.storageAddress}.`,
        );
      }
    }
  }

  return [...merged.values()];
}

function mergeFunctionDefinitions(records) {
  const merged = new Map();

  for (const record of records) {
    const mergedKey = `${record.entryContract.toLowerCase()}:${record.functionSig}`;
    const existing = merged.get(mergedKey);
    if (!existing) {
      merged.set(mergedKey, {
        ...record,
        exampleNames: [`${record.groupName}/${record.exampleName}`],
      });
      continue;
    }

    const mismatches = [];
    if (
      existing.storageAddresses.length !== record.storageAddresses.length
      || existing.storageAddresses.some(
        (address, index) => ethers.toBigInt(getAddress(address)) !== ethers.toBigInt(getAddress(record.storageAddresses[index])),
      )
    ) {
      mismatches.push("managed storage vector");
    }
    if (ethers.toBigInt(existing.preprocessInputHash) !== ethers.toBigInt(record.preprocessInputHash)) {
      mismatches.push("preprocess input hash");
    }
    if (existing.entryContractOffsetWords !== record.entryContractOffsetWords) {
      mismatches.push("entry-contract offset");
    }
    if (existing.functionSigOffsetWords !== record.functionSigOffsetWords) {
      mismatches.push("function-signature offset");
    }
    if (existing.currentRootVectorOffsetWords !== record.currentRootVectorOffsetWords) {
      mismatches.push("current-root offset");
    }
    if (existing.updatedRootVectorOffsetWords !== record.updatedRootVectorOffsetWords) {
      mismatches.push("updated-root offset");
    }
    if (JSON.stringify(existing.eventLogs) !== JSON.stringify(record.eventLogs)) {
      mismatches.push("event log metadata");
    }

    if (mismatches.length > 0) {
      throw new Error(
        [
          `Function metadata mismatch for ${record.entryContract} ${record.functionSig}.`,
          `Conflicting fields: ${mismatches.join(", ")}.`,
          `Existing example: ${existing.exampleNames.join(", ")}.`,
          `Conflicting example: ${record.groupName}/${record.exampleName}.`,
        ].join(" "),
      );
    }

    existing.exampleNames.push(`${record.groupName}/${record.exampleName}`);
  }

  return [...merged.values()];
}

function buildDAppDefinitions(records) {
  const grouped = new Map();

  for (const record of records) {
    const group = grouped.get(record.groupName) ?? {
      groupName: record.groupName,
      labelHash: keccak256(Buffer.from(record.groupName, "utf8")),
      examples: [],
      records: [],
    };
    group.examples.push({
      exampleName: record.exampleName,
      entryContract: record.entryContract,
      functionSig: record.functionSig,
      aPubBlockHash: record.aPubBlockHash,
      storageAddresses: record.storageAddresses,
    });
    group.records.push(record);
    grouped.set(record.groupName, group);
  }

  return [...grouped.values()]
    .sort((left, right) => left.groupName.localeCompare(right.groupName))
    .map((group) => {
      const commonStorageAddresses = group.records[0].storageAddresses;
      for (const record of group.records) {
        if (
          record.storageAddresses.length !== commonStorageAddresses.length
          || record.storageAddresses.some(
            (address, index) => ethers.toBigInt(getAddress(address)) !== ethers.toBigInt(getAddress(commonStorageAddresses[index])),
          )
        ) {
          throw new Error(
            [
              `DApp group ${group.groupName} has inconsistent managed storage vectors across functions.`,
              `Expected ${JSON.stringify(commonStorageAddresses)}.`,
              `Observed ${JSON.stringify(record.storageAddresses)} in ${record.exampleName}.`,
            ].join(" "),
          );
        }
      }

      return {
        groupName: group.groupName,
        labelHash: group.labelHash,
        storageMetadata: mergeStorageMetadata(group.records),
        functions: mergeFunctionDefinitions(group.records).map((record) => ({
          entryContract: record.entryContract,
          functionSig: record.functionSig,
          preprocessInputHash: record.preprocessInputHash,
          entryContractOffsetWords: record.entryContractOffsetWords,
          functionSigOffsetWords: record.functionSigOffsetWords,
          currentRootVectorOffsetWords: record.currentRootVectorOffsetWords,
          updatedRootVectorOffsetWords: record.updatedRootVectorOffsetWords,
          eventLogs: record.eventLogs,
          exampleNames: record.exampleNames,
        })),
        examples: group.examples.sort((left, right) => left.exampleName.localeCompare(right.exampleName)),
      };
    });
}

function usage() {
  console.log(`Usage:
  node bridge/scripts/admin-add-dapp.mjs --network <anvil|sepolia|mainnet> --group <example-group> [--group <example-group> ...] --dapp-id <uint> [options]

Options:
  --network <name>                  Bridge network used for RPC and bridge deployment snapshots
  --deployment-path <path>          Bridge deployment JSON path; defaults to the latest bridge snapshot for the resolved chain
  --abi-manifest <path>             ABI manifest path; defaults to the latest bridge snapshot for the resolved chain
  --dapp-manager <address>          Override DAppManager address; defaults from deployment JSON
  --dapp-label <name>               Logical DApp label used to merge multiple example groups
  --app-network <name>              App deployment network whose manifests should be used; defaults to --network
  --app-deployment-path <path>      App deployment manifest; defaults to private-state latest for the app chain
  --storage-layout-path <path>      App storage-layout manifest; defaults to private-state latest for the app chain
  --example-root <path>             Example root containing <group>/<example-name>/ canonical Tokamak inputs
  --rpc-url <url>                   JSON-RPC URL; defaults from --network plus BRIDGE_ALCHEMY_API_KEY
  --private-key <hex>               Broadcaster key; defaults from BRIDGE_DEPLOYER_PRIVATE_KEY
  --manifest-out <path>             Output manifest path; defaults to deployment/chain-id-<chain>/dapps/<dapp-name>/<timestamp>/dapp-registration.<chain-id>.json
  --artifacts-out <path>            Directory for archived synthesizer/preprocess outputs
  --replace-existing                Update an existing DApp ID with a matching immutable labelHash

Example groups are resolved relative to:
  <example-root>/<group>/<example-name>/

The transaction and previous-state inputs must already target the selected app deployment.
The script fetches contract_codes.json from the target app RPC before synthesizing.
`);
}

function parseArgs(argv) {
  const options = {
    groups: [],
    dappId: null,
    network: null,
    deploymentPath: null,
    abiManifestPath: null,
    dAppManager: null,
    dappLabel: null,
    appNetwork: null,
    appDeploymentPath: null,
    storageLayoutPath: null,
    exampleRoot: privateStateExampleRoot,
    rpcUrl: null,
    privateKey: process.env.BRIDGE_DEPLOYER_PRIVATE_KEY ?? null,
    manifestOut: null,
    artifactsOut: defaultArtifactsRoot,
    replaceExisting: false,
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
      case "--network":
        options.network = take(current);
        break;
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
      case "--example-root":
        options.exampleRoot = path.resolve(process.cwd(), take(current));
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
      case "--replace-existing":
        options.replaceExisting = true;
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
  if (!options.network) {
    throw new Error("--network is required.");
  }
  resolveBridgeNetwork(options.network);

  return options;
}

function resolveRpcUrl(options) {
  if (options.rpcUrl) {
    return options.rpcUrl;
  }

  if (process.env.BRIDGE_RPC_URL_OVERRIDE) {
    return process.env.BRIDGE_RPC_URL_OVERRIDE;
  }

  const network = options.network;
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
      throw new Error(`Unsupported --network=${network}`);
  }
}

function resolveBridgeNetwork(networkName) {
  try {
    return resolveAppNetwork(networkName);
  } catch {
    throw new Error(`Unsupported --network=${networkName}`);
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
  const latestDir = requireLatestDappArtifactDir(rootDir, chainId, "private-state");
  return path.join(latestDir, `${kind}.${chainId}.latest.json`);
}

function resolveDappSourceRoot(rootDir, dappLabel) {
  const appRoot = path.join(rootDir, "packages", "apps", dappLabel);
  const sourceRoot = path.join(appRoot, "src");

  if (fs.existsSync(sourceRoot) && fs.statSync(sourceRoot).isDirectory()) {
    return sourceRoot;
  }

  throw new Error(
    `Unable to locate source directory for ${dappLabel}: ${sourceRoot}`,
  );
}

function resolveDappSnapshotTimestamp(rootDir, chainId, dappLabel, manifestOut, fallbackTimestamp) {
  const manifestDir = path.resolve(path.dirname(manifestOut));
  const timestampLabel = path.basename(manifestDir);
  if (!TIMESTAMP_LABEL_PATTERN.test(timestampLabel)) {
    return fallbackTimestamp;
  }

  const expectedDir = path.resolve(dappArtifactDir(rootDir, chainId, dappLabel, timestampLabel));
  return manifestDir === expectedDir ? timestampLabel : fallbackTimestamp;
}

function resolveBridgeDeploymentPath(chainId) {
  const latestDir = requireLatestBridgeArtifactDir(repoRoot, chainId);
  return path.join(latestDir, `bridge.${chainId}.json`);
}

function resolveBridgeAbiManifestPath(chainId) {
  const latestDir = requireLatestBridgeArtifactDir(repoRoot, chainId);
  return path.join(latestDir, `bridge-abi-manifest.${chainId}.json`);
}

function resolveAppChainId(appNetwork) {
  try {
    return resolveAppNetwork(appNetwork).chainId;
  } catch {
    throw new Error(`Unsupported --app-network=${appNetwork}`);
  }
}

function resolveAppRpcUrl(appNetwork) {
  return deriveRpcUrl({
    networkName: appNetwork,
    alchemyApiKey: process.env.APPS_ALCHEMY_API_KEY?.trim(),
    rpcUrlOverride: process.env.APPS_RPC_URL_OVERRIDE?.trim(),
  });
}

function shouldSkipArtifactUpload(bridgeChainId, appChainId) {
  return bridgeChainId === 31337 || appChainId === 31337;
}

function loadPrivateStateAppContext({ appDeploymentPath, storageLayoutPath }) {
  const deployment = readJson(appDeploymentPath);
  const storageLayout = readJson(storageLayoutPath);

  const controller = deployment.contracts?.controller;
  const l2AccountingVault = deployment.contracts?.l2AccountingVault;
  if (!controller || !l2AccountingVault) {
    throw new Error(`App deployment manifest is missing controller/L2AccountingVault: ${appDeploymentPath}`);
  }
  const controllerAddress = getAddress(controller);
  const l2AccountingVaultAddress = getAddress(l2AccountingVault);

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
    entryContract: controllerAddress,
    storageMetadata: [
      {
        storageAddress: controllerAddress,
        preAllocKeys: [],
        userSlots: [],
        isChannelTokenVaultStorage: false,
      },
      {
        storageAddress: l2AccountingVaultAddress,
        preAllocKeys: [],
        userSlots: [liquidBalanceSlotNumber],
        isChannelTokenVaultStorage: true,
      },
    ],
    contractCodes: [],
  };
}

async function writeDeploymentSnapshotWithBytecode({ provider, sourcePath, targetPath }) {
  const deployment = readJson(sourcePath);
  const deployedBytecode = {};

  for (const [contractName, address] of Object.entries(deployment.contracts ?? {})) {
    if (typeof address !== "string" || address.length === 0) {
      continue;
    }

    const normalizedAddress = getAddress(address);
    const code = await provider.getCode(normalizedAddress);
    if (code === "0x") {
      throw new Error(`No deployed bytecode found for ${contractName} at ${normalizedAddress}.`);
    }
    deployedBytecode[contractName] = code;
  }

  deployment.deployedBytecode = deployedBytecode;
  deployment.sourceCode = buildSourceCodeMetadata(repoRoot, PRIVATE_STATE_DAPP_SOURCE_PATHS);
  writeJson(targetPath, deployment);
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

async function runTokamakInstall() {
  const invocation = buildTokamakCliInvocation(["--install"]);
  await run(invocation.command, invocation.args, { cwd: repoRoot });
}

function buildTokamakCliArgs(files) {
  return [
    "--synthesize",
    "--previous-state",
    files.previousState,
    "--transaction",
    files.transaction,
    "--block-info",
    files.blockInfo,
    "--contract-code",
    files.contractCode,
  ];
}

function synthOutputDir() {
  return resolveTokamakCliSynthOutputDir();
}

function preprocessOutputPath() {
  return path.join(resolveTokamakCliPreprocessOutputDir(), "preprocess.json");
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

function loadExampleGroupEntries(groupName, exampleRoot) {
  const groupRoot = path.join(exampleRoot, groupName);
  if (!fs.existsSync(groupRoot)) {
    throw new Error(`Unknown DApp example group: ${groupName} under ${exampleRoot}`);
  }

  return fs.readdirSync(groupRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const exampleRoot = path.join(groupRoot, entry.name);
      const files = {
        previousState: path.join(exampleRoot, "previous_state_snapshot.json"),
        transaction: path.join(exampleRoot, "transaction.json"),
        blockInfo: path.join(exampleRoot, "block_info.json"),
        contractCode: path.join(exampleRoot, "contract_codes.json"),
      };

      for (const [label, filePath] of Object.entries(files)) {
        if (!fs.existsSync(filePath)) {
          throw new Error(`Missing ${label} input for ${groupName}/${entry.name}: ${filePath}`);
        }
      }

      return {
        name: entry.name,
        files,
      };
    })
    .sort((left, right) => left.name.localeCompare(right.name));
}

async function processDAppGroup(groupName, archiveRoot, appContext, dappLabel, exampleRoot) {
  ensureDir(archiveRoot);
  const entries = loadExampleGroupEntries(groupName, exampleRoot);
  const processed = [];
  const skipped = [];

  for (const entry of entries) {
    const exampleName = entry.name;
    const exampleOutputRoot = path.join(archiveRoot, slugify(exampleName));
    const targetInputFiles = materializeTargetExampleInputs({
      entry,
      exampleOutputRoot,
      appContext,
      contractCodes: appContext.contractCodes,
    });

    try {
      const invocation = buildTokamakCliInvocation(buildTokamakCliArgs(targetInputFiles));
      await run(invocation.command, invocation.args, { cwd: repoRoot });
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

    const preprocessInvocation = buildTokamakCliInvocation(["--preprocess"]);
    await run(preprocessInvocation.command, preprocessInvocation.args, { cwd: repoRoot });
    copyFile(preprocessOutputPath(), path.join(exampleOutputRoot, "preprocess.json"));

    processed.push(
      buildFunctionDefinition({
        groupName: dappLabel,
        exampleName: `${groupName}/${exampleName}`,
        transactionJsonPath: targetInputFiles.transaction,
        snapshotJsonPath: targetInputFiles.previousState,
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

function buildDAppManagerMetadata(dapp) {
  return {
    storages: dapp.storageMetadata.map((storage) => ({
      storageAddr: storage.storageAddress,
      preAllocatedKeys: storage.preAllocKeys,
      userStorageSlots: storage.userSlots,
      isChannelTokenVaultStorage: storage.isChannelTokenVaultStorage,
    })),
    functions: dapp.functions.map((fn) => ({
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
    })),
  };
}

function normalizeBytes32(value) {
  return ethers.hexlify(value).toLowerCase();
}

async function resolveDAppRegistrationMode(dAppManager, dappId, replaceExisting, labelHash) {
  try {
    const info = await dAppManager.getDAppInfo(dappId);
    if (!replaceExisting) {
      throw new Error(`DApp ${dappId} already exists. Pass --replace-existing to update its metadata.`);
    }
    if (normalizeBytes32(info.labelHash) !== normalizeBytes32(labelHash)) {
      throw new Error(
        `DApp ${dappId} already exists with immutable labelHash ${info.labelHash}; ` +
          `refusing to replace it with ${labelHash}. Use a new dappId for a different label.`,
      );
    }
    return {
      operation: "update",
      existingRegistration: true,
      previousLabelHash: info.labelHash,
    };
  } catch (error) {
    const revertName = error?.revert?.name ?? error?.info?.errorName ?? error?.errorName;
    const shortMessage = error?.shortMessage ?? error?.message ?? "";
    if (revertName === "UnknownDApp" || shortMessage.includes("UnknownDApp")) {
      return {
        operation: "register",
        existingRegistration: false,
        previousLabelHash: null,
      };
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
  const bridgeNetwork = resolveBridgeNetwork(options.network);
  const provider = new JsonRpcProvider(rpcUrl);
  const chainId = Number((await provider.getNetwork()).chainId);
  if (chainId !== bridgeNetwork.chainId) {
    throw new Error(`Bridge RPC chain ID mismatch for --network ${options.network}: expected ${bridgeNetwork.chainId}, received ${chainId}.`);
  }
  const deploymentPath = options.deploymentPath ?? resolveBridgeDeploymentPath(chainId);
  const deployment = readJson(deploymentPath);
  const abiManifestPath = resolveAbiManifestPath(options, deployment, deploymentPath);
  const dAppManagerAddress = options.dAppManager ?? deployment.dAppManager;
  if (!dAppManagerAddress) {
    throw new Error("Unable to resolve DAppManager address from arguments or deployment artifact.");
  }
  const appNetwork = options.appNetwork ?? options.network;
  const appChainId = resolveAppChainId(appNetwork);
  let appProvider = provider;
  if (appChainId !== chainId) {
    const appRpcUrl = resolveAppRpcUrl(appNetwork);
    appProvider = appRpcUrl === rpcUrl ? provider : new JsonRpcProvider(appRpcUrl);
    const resolvedAppChainId = Number((await appProvider.getNetwork()).chainId);
    if (resolvedAppChainId !== appChainId) {
      throw new Error(`App RPC chain ID mismatch: expected ${appChainId}, received ${resolvedAppChainId}.`);
    }
  }
  await runTokamakInstall();
  const appDeploymentPath =
    options.appDeploymentPath ?? resolvePrivateStateManifestPath(repoRoot, appChainId, "deployment");
  const storageLayoutPath =
    options.storageLayoutPath ?? resolvePrivateStateManifestPath(repoRoot, appChainId, "storage-layout");
  const dappLabel = options.dappLabel ?? "private-state";
  const sourceRoot = resolveDappSourceRoot(repoRoot, dappLabel);
  const generatedTimestamp = createTimestampLabel();
  const defaultDappSnapshot = dappArtifactPaths(repoRoot, chainId, dappLabel, generatedTimestamp);
  const manifestOut = options.manifestOut ?? defaultDappSnapshot.registrationManifestPath;
  const uploadTimestamp = resolveDappSnapshotTimestamp(
    repoRoot,
    chainId,
    dappLabel,
    manifestOut,
    generatedTimestamp,
  );
  const dappSnapshot = dappArtifactPaths(repoRoot, chainId, dappLabel, uploadTimestamp);
  const manifestPendingOut = path.join(
    repoRoot,
    "deployment",
    ".pending",
    `chain-id-${chainId}`,
    "dapps",
    dappLabel,
    uploadTimestamp,
    path.basename(manifestOut),
  );
  const artifactsRoot = path.join(options.artifactsOut, dappLabel);
  ensureDir(artifactsRoot);
  const appContext = loadPrivateStateAppContext({ appDeploymentPath, storageLayoutPath });
  appContext.contractCodes = await fetchTargetContractCodes(appProvider, appContext);
  const sourceDeploymentDir = path.dirname(appDeploymentPath);
  const sourceControllerAbiPath = path.join(sourceDeploymentDir, "PrivateStateController.callable-abi.json");
  const sourceVaultAbiPath = path.join(sourceDeploymentDir, "L2AccountingVault.callable-abi.json");

  if (!shouldSkipArtifactUpload(chainId, appChainId)) {
    await run(
      "node",
      [
        uploadDappArtifactsScriptPath,
        "--dapp-name",
        dappLabel,
        "--bridge-chain-id",
        String(chainId),
        "--app-chain-id",
        String(appChainId),
        "--registration-manifest",
        manifestPendingOut,
        "--app-deployment-path",
        appDeploymentPath,
        "--storage-layout-path",
        storageLayoutPath,
        "--timestamp",
        uploadTimestamp,
        "--preflight",
      ],
      {
        cwd: repoRoot,
      },
    );
  }

  const allProcessed = [];
  const allSkipped = [];
  for (const groupName of options.groups) {
    const processedGroup = await processDAppGroup(
      groupName,
      artifactsRoot,
      appContext,
      dappLabel,
      options.exampleRoot,
    );
    allProcessed.push(...processedGroup.processed);
    allSkipped.push(...processedGroup.skipped);
  }

  const dapps = buildDAppDefinitions(allProcessed);
  if (dapps.length !== 1) {
    throw new Error(`Expected exactly one DApp definition for ${dappLabel}, received ${dapps.length}.`);
  }
  const dapp = dapps[0];
  const functionProofs = buildFunctionMetadataProofs(dapp.functions);

  const wallet = new Wallet(privateKey, provider);
  const dAppManager = new Contract(dAppManagerAddress, loadDAppManagerAbi(abiManifestPath), wallet);

  const metadata = buildDAppManagerMetadata(dapp);
  const registrationMode = await resolveDAppRegistrationMode(
    dAppManager,
    options.dappId,
    options.replaceExisting,
    dapp.labelHash,
  );

  const tx =
    registrationMode.operation === "update"
      ? await dAppManager.updateDAppMetadata(options.dappId, metadata.storages, metadata.functions)
      : await dAppManager.registerDApp(options.dappId, dapp.labelHash, metadata.storages, metadata.functions);
  const receipt = await tx.wait();
  const registeredInfo = await dAppManager.getDAppInfo(options.dappId);
  if (normalizeBytes32(registeredInfo.functionRoot) !== normalizeBytes32(functionProofs.root)) {
    throw new Error(
      `On-chain functionRoot ${registeredInfo.functionRoot} does not match locally computed root ${functionProofs.root}.`,
    );
  }
  ensureDir(dappSnapshot.rootDir);
  await writeDeploymentSnapshotWithBytecode({
    provider: appProvider,
    sourcePath: appDeploymentPath,
    targetPath: dappSnapshot.deploymentPath,
  });
  copyFile(storageLayoutPath, dappSnapshot.storageLayoutPath);
  copyFile(sourceControllerAbiPath, dappSnapshot.privateStateControllerAbiPath);
  copyFile(sourceVaultAbiPath, dappSnapshot.l2AccountingVaultAbiPath);
  copyDir(sourceRoot, dappSnapshot.sourceDir);

  const manifest = {
    generatedAt: new Date().toISOString(),
    appNetwork,
    appChainId,
    groupNames: options.groups,
    dappLabel,
    dappId: options.dappId,
    dAppManager: dAppManagerAddress,
    artifactSources: {
      privateStateCli: readNpmPackageSource(privateStateCliPackageJsonPath),
      uploadedFiles: [
        path.basename(manifestPendingOut),
        path.basename(dappSnapshot.deploymentPath),
        path.basename(dappSnapshot.storageLayoutPath),
        path.basename(dappSnapshot.privateStateControllerAbiPath),
        path.basename(dappSnapshot.l2AccountingVaultAbiPath),
        "source/PrivateStateController.sol",
        "source/L2AccountingVault.sol",
      ],
    },
    processedExamples: allProcessed.map((entry) => ({
      groupName: entry.groupName,
      exampleName: entry.exampleName,
      entryContract: entry.entryContract,
      functionSig: entry.functionSig,
    })),
    skippedExamples: allSkipped,
    registration: {
      operation: registrationMode.operation,
      txHash: tx.hash,
      blockNumber: receipt?.blockNumber ?? null,
      existingRegistration: registrationMode.existingRegistration,
      updatedExistingRegistration: registrationMode.operation === "update",
      previousLabelHash: registrationMode.previousLabelHash,
      labelHash: dapp.labelHash,
      metadataDigestSchema: registeredInfo.metadataDigestSchema,
      metadataDigest: registeredInfo.metadataDigest,
      functionRoot: registeredInfo.functionRoot,
      storageCount: dapp.storageMetadata.length,
      functionCount: dapp.functions.length,
    },
    functionMetadataProofs: {
      root: functionProofs.root,
      functions: functionProofs.functions,
    },
  };
  writeJson(manifestPendingOut, manifest);

  let publication = null;
  if (!shouldSkipArtifactUpload(chainId, appChainId)) {
    const uploadReceiptPath = path.join(path.dirname(manifestPendingOut), `${path.basename(manifestPendingOut)}.upload.json`);
    await run(
      "node",
      [
        uploadDappArtifactsScriptPath,
        "--dapp-name",
        dappLabel,
        "--bridge-chain-id",
        String(chainId),
        "--app-chain-id",
        String(appChainId),
        "--registration-manifest",
        manifestPendingOut,
        "--app-deployment-path",
        dappSnapshot.deploymentPath,
        "--storage-layout-path",
        dappSnapshot.storageLayoutPath,
        "--timestamp",
        uploadTimestamp,
        "--receipt-out",
        uploadReceiptPath,
      ],
      {
        cwd: repoRoot,
      },
    );
    publication = readJson(uploadReceiptPath);
    fs.rmSync(uploadReceiptPath, { force: true });
  }

  if (publication) {
    manifest.publication = publication;
    writeJson(manifestPendingOut, manifest);
  }

  ensureDir(path.dirname(manifestOut));
  fs.renameSync(manifestPendingOut, manifestOut);
  console.log(`Using app deployment manifest: ${appDeploymentPath}`);
  console.log(`Using app storage layout manifest: ${storageLayoutPath}`);
  const operationLabel = registrationMode.operation === "update" ? "Updated" : "Registered";
  console.log(`${operationLabel} DApp ${options.dappId} for groups ${options.groups.join(", ")} as ${dappLabel}.`);
  console.log(`Wrote manifest: ${manifestOut}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
