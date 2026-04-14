import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { AbiCoder, getAddress, keccak256 } from "ethers";

const abiCoder = AbiCoder.defaultAbiCoder();
const TOKAMAK_APUB_BLOCK_LENGTH = 63;

const CAPACITY_ERROR_PATTERNS = [
  /insufficient .* length/i,
  /insufficient s_max/i,
  /ask the qap-compiler/i,
  /input signal array access exceeds the size/i,
  /failed to update constants\.circom/i,
];

export function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

export function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(
    filePath,
    `${JSON.stringify(value, (_key, current) => (
      typeof current === "bigint" ? current.toString() : current
    ), 2)}\n`,
  );
}

export function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

export function copyDir(sourceDir, targetDir) {
  fs.rmSync(targetDir, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(targetDir), { recursive: true });
  fs.cpSync(sourceDir, targetDir, { recursive: true });
}

export function copyFile(sourcePath, targetPath) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.copyFileSync(sourcePath, targetPath);
}

export function ensureTokamakDistBackendBinaries(tokamakRoot) {
  const normalizedRoot = path.resolve(tokamakRoot);
  const releaseDir = path.join(normalizedRoot, "packages", "backend", "target", "release");
  const distBinDir = path.join(normalizedRoot, "dist", "bin");
  const backendLibSourceDir = path.join(normalizedRoot, "packages", "backend", "external-lib", process.platform === "darwin" ? "mac" : "linux");
  const backendLibTargetDir = path.join(normalizedRoot, "dist", "backend-lib", "icicle");
  const binaries = ["trusted-setup", "preprocess", "prove", "verify"];

  fs.mkdirSync(distBinDir, { recursive: true });
  if (fs.existsSync(backendLibSourceDir)) {
    fs.rmSync(backendLibTargetDir, { recursive: true, force: true });
    fs.mkdirSync(path.dirname(backendLibTargetDir), { recursive: true });
    fs.cpSync(backendLibSourceDir, backendLibTargetDir, { recursive: true });
  }

  const copied = [];
  for (const binary of binaries) {
    const sourcePath = path.join(releaseDir, binary);
    const targetPath = path.join(distBinDir, binary);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Missing Tokamak backend binary: ${sourcePath}`);
    }
    if (!fs.existsSync(targetPath)) {
      fs.copyFileSync(sourcePath, targetPath);
      fs.chmodSync(targetPath, 0o755);
      copied.push(binary);
      continue;
    }

    const sourceStat = fs.statSync(sourcePath);
    const targetStat = fs.statSync(targetPath);
    if (sourceStat.size !== targetStat.size || sourceStat.mtimeMs > targetStat.mtimeMs) {
      fs.copyFileSync(sourcePath, targetPath);
      fs.chmodSync(targetPath, 0o755);
      copied.push(binary);
    }
  }

  if (process.platform === "darwin" && fs.existsSync(path.join(backendLibTargetDir, "lib"))) {
    const rpath = "@executable_path/../backend-lib/icicle/lib";
    for (const binary of binaries) {
      const targetPath = path.join(distBinDir, binary);
      const probe = spawnSync("otool", ["-l", targetPath], { encoding: "utf8" });
      if (probe.status === 0 && probe.stdout.includes(rpath)) {
        continue;
      }
      const installResult = spawnSync("install_name_tool", ["-add_rpath", rpath, targetPath], { encoding: "utf8" });
      if (installResult.status !== 0 && !String(installResult.stderr ?? "").includes("would duplicate path")) {
        throw new Error(`Failed to add rpath to ${targetPath}: ${installResult.stderr ?? installResult.stdout}`);
      }
    }
  }

  return copied;
}

export function slugify(value) {
  return value
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}

export function isCapacityError(output) {
  return CAPACITY_ERROR_PATTERNS.some((pattern) => pattern.test(output));
}

export function assertExists(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
}

export function loadExampleManifest(manifestPath) {
  const entries = readJson(manifestPath);
  if (!Array.isArray(entries)) {
    throw new Error(`Expected array manifest: ${manifestPath}`);
  }
  return entries;
}

function toBigIntArray(values, label) {
  if (!Array.isArray(values)) {
    throw new Error(`${label} must be an array.`);
  }
  return values.map((value, index) => {
    try {
      return BigInt(value);
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

export function extractTokamakRegistrationArtifacts(preprocessJsonPath) {
  const preprocess = readJson(preprocessJsonPath);
  const part1 = toBigIntArray(preprocess.preprocess_entries_part1, "preprocess_entries_part1");
  const part2 = toBigIntArray(preprocess.preprocess_entries_part2, "preprocess_entries_part2");

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
    functionInstanceHash: hashTokamakPointEncoding(functionInstancePart1, functionInstancePart2),
    functionPreprocessHash: hashTokamakPointEncoding(functionPreprocessPart1, functionPreprocessPart2),
  };
}

export function hashTokamakPointEncoding(part1, part2) {
  return keccak256(abiCoder.encode(["uint128[]", "uint256[]"], [part1, part2]));
}

export function hashTokamakPublicInputs(values) {
  return keccak256(abiCoder.encode(["uint256[]"], [values]));
}

export function normalizeTokamakAPubBlock(values) {
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

export function deriveFunctionSelectorFromTransaction(transactionJsonPath) {
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

export function deriveRegistrationMetadataFromSnapshot(snapshotJsonPath, entryContract) {
  const snapshot = readJson(snapshotJsonPath);
  const storageKeys = Array.isArray(snapshot.storageKeys)
    ? snapshot.storageKeys
    : Array.isArray(snapshot.storageEntries)
      ? snapshot.storageEntries.map((entries) => entries.map((entry) => entry.key))
      : null;
  if (!Array.isArray(snapshot.storageAddresses) || !Array.isArray(storageKeys)) {
    throw new Error(`Snapshot is missing storage vectors: ${snapshotJsonPath}`);
  }
  if (snapshot.storageAddresses.length !== storageKeys.length) {
    throw new Error(`storageAddresses/storageKeys length mismatch in ${snapshotJsonPath}`);
  }

  const channelTokenVaultStorageAddress = inferChannelTokenVaultStorageAddress(snapshot.storageAddresses, entryContract);

  return snapshot.storageAddresses.map((storageAddress, index) => ({
    storageAddress: getAddress(storageAddress),
    preAllocKeys: storageKeys[index],
    userSlots: [],
    isChannelTokenVaultStorage: getAddress(storageAddress) === channelTokenVaultStorageAddress,
  }));
}

export function deriveEntryContractFromTransaction(transactionJsonPath) {
  const transaction = readJson(transactionJsonPath);
  if (typeof transaction.to !== "string") {
    throw new Error(`Transaction "to" is missing: ${transactionJsonPath}`);
  }
  return getAddress(transaction.to);
}

export function buildFunctionDefinition({
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
  const extracted = extractTokamakRegistrationArtifacts(preprocessJsonPath);
  const instance = readJson(instanceJsonPath);
  const preprocess = readJson(preprocessJsonPath);
  const preprocessPart1 = toBigIntArray(preprocess.preprocess_entries_part1, "preprocess_entries_part1");
  const preprocessPart2 = toBigIntArray(preprocess.preprocess_entries_part2, "preprocess_entries_part2");
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

export function mergeStorageMetadata(records) {
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

export function mergeFunctionDefinitions(records) {
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
    if (JSON.stringify(existing.storageAddresses) !== JSON.stringify(record.storageAddresses)) {
      mismatches.push("managed storage vector");
    }
    if (existing.preprocessInputHash !== record.preprocessInputHash) {
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

export function buildDAppDefinitions(records) {
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
        if (JSON.stringify(record.storageAddresses) !== JSON.stringify(commonStorageAddresses)) {
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
