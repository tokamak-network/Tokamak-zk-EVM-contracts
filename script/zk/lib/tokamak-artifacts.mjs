import fs from "node:fs";
import path from "node:path";
import { AbiCoder, getAddress, keccak256 } from "ethers";

const abiCoder = AbiCoder.defaultAbiCoder();

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
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
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

export function deriveFunctionSelectorFromTransaction(transactionJsonPath) {
  const transaction = readJson(transactionJsonPath);
  if (typeof transaction.data !== "string" || transaction.data.length < 10) {
    throw new Error(`Transaction data is missing a 4-byte selector: ${transactionJsonPath}`);
  }
  return transaction.data.slice(0, 10).toLowerCase();
}

export function deriveRegistrationMetadataFromSnapshot(snapshotJsonPath) {
  const snapshot = readJson(snapshotJsonPath);
  if (!Array.isArray(snapshot.storageAddresses) || !Array.isArray(snapshot.storageEntries)) {
    throw new Error(`Snapshot is missing storage vectors: ${snapshotJsonPath}`);
  }
  if (snapshot.storageAddresses.length !== snapshot.storageEntries.length) {
    throw new Error(`storageAddresses/storageEntries length mismatch in ${snapshotJsonPath}`);
  }

  return snapshot.storageAddresses.map((storageAddress, index) => ({
    storageAddress: getAddress(storageAddress),
    preAllocKeys: snapshot.storageEntries[index].map((entry) => entry.key),
    userSlots: [],
    isTokenVaultStorage: false,
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
}) {
  const selector = deriveFunctionSelectorFromTransaction(transactionJsonPath);
  const entryContract = deriveEntryContractFromTransaction(transactionJsonPath);
  const storageMetadata = deriveRegistrationMetadataFromSnapshot(snapshotJsonPath);
  const extracted = extractTokamakRegistrationArtifacts(preprocessJsonPath);

  return {
    groupName,
    exampleName,
    functionSig: selector,
    entryContract,
    storageAddresses: storageMetadata.map((entry) => entry.storageAddress),
    storageMetadata,
    functionInstanceHash: extracted.functionInstanceHash,
    functionPreprocessHash: extracted.functionPreprocessHash,
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
          isTokenVaultStorage: storage.isTokenVaultStorage,
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

      if (existing.isTokenVaultStorage !== storage.isTokenVaultStorage) {
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
    const existing = merged.get(record.functionSig);
    if (!existing) {
      merged.set(record.functionSig, {
        ...record,
        exampleNames: [`${record.groupName}/${record.exampleName}`],
      });
      continue;
    }

    const mismatches = [];
    if (existing.entryContract !== record.entryContract) {
      mismatches.push("entry contract");
    }
    if (JSON.stringify(existing.storageAddresses) !== JSON.stringify(record.storageAddresses)) {
      mismatches.push("managed storage vector");
    }
    if (existing.functionInstanceHash !== record.functionInstanceHash) {
      mismatches.push("function instance hash");
    }
    if (existing.functionPreprocessHash !== record.functionPreprocessHash) {
      mismatches.push("function preprocess hash");
    }

    if (mismatches.length > 0) {
      throw new Error(
        [
          `Selector collision for ${record.functionSig}: bridge registration is keyed only by function selector.`,
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
