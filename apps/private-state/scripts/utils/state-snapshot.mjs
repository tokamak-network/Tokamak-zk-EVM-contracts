import { MerklePatriciaTrie } from "@ethereumjs/mpt";
import { RLP } from "@ethereumjs/rlp";
import {
  addHexPrefix,
  bytesToHex,
  createAddressFromString,
  hexToBytes,
} from "@ethereumjs/util";
import {
  TokamakL2StateManager,
  createTokamakL2Common,
} from "tokamak-l2js";
import {
  ethers,
  getAddress,
  keccak256,
} from "ethers";

function normalizeBytes32Hex(hexValue) {
  return ethers.zeroPadValue(ethers.toBeHex(BigInt(hexValue)), 32).toLowerCase();
}

function normalizeHex(hexValue) {
  return ethers.hexlify(ethers.getBytes(hexValue)).toLowerCase();
}

function isZeroLikeStorageValue(value) {
  if (typeof value !== "string") {
    return false;
  }
  const normalized = value.trim().toLowerCase();
  return normalized === "0x" || normalized === "0x0" || normalized === "0x00";
}

function normalizeStorageEntries(entries) {
  if (!Array.isArray(entries)) {
    return undefined;
  }
  return entries.map((perAddressEntries) => perAddressEntries
    .filter((entry) => !isZeroLikeStorageValue(entry.value))
    .map((entry) => ({
      key: normalizeBytes32Hex(entry.key),
      value: normalizeHex(entry.value),
    })));
}

function maybeStorageTrieKeyPrefix(storageAddress, trieDbEntries) {
  const dbKey = trieDbEntries.find((entry) => typeof entry?.key === "string")?.key;
  if (typeof dbKey !== "string") {
    return undefined;
  }
  const normalizedDbKey = normalizeHex(dbKey);
  if (normalizedDbKey.length <= 66) {
    return undefined;
  }
  const addressHash = ethers.getBytes(keccak256(createAddressFromString(storageAddress).bytes));
  return addressHash.slice(0, 7);
}

async function buildStorageTrie({ storageAddress, storageTrieRoot, storageTrieDb }) {
  const trie = new MerklePatriciaTrie({
    useKeyHashing: true,
    common: createTokamakL2Common(),
    keyPrefix: maybeStorageTrieKeyPrefix(storageAddress, storageTrieDb),
  });
  const trieDbOps = storageTrieDb.map((entry) => ({
    type: "put",
    key: normalizeHex(entry.key).slice(2),
    value: hexToBytes(addHexPrefix(entry.value)),
  }));
  await trie.database().db.batch(trieDbOps);
  trie.root(hexToBytes(addHexPrefix(storageTrieRoot)));
  return trie;
}

export function normalizeStateSnapshot(snapshot) {
  const normalizedSnapshot = {
    ...snapshot,
    channelId: typeof snapshot.channelId === "bigint" ? snapshot.channelId.toString() : String(snapshot.channelId),
    stateRoots: snapshot.stateRoots.map((value) => normalizeBytes32Hex(value)),
    storageAddresses: snapshot.storageAddresses.map((value) => getAddress(value)),
  };
  if (Array.isArray(snapshot.storageKeys)) {
    normalizedSnapshot.storageKeys = snapshot.storageKeys.map((keys) => keys.map((key) => normalizeBytes32Hex(key)));
  }
  if (Array.isArray(snapshot.storageTrieRoots)) {
    normalizedSnapshot.storageTrieRoots = snapshot.storageTrieRoots.map((value) => normalizeHex(value));
  }
  if (Array.isArray(snapshot.storageTrieDb)) {
    normalizedSnapshot.storageTrieDb = snapshot.storageTrieDb.map((entries) => entries.map((entry) => ({
      key: normalizeHex(entry.key),
      value: normalizeHex(entry.value),
    })));
  }
  const normalizedEntries = normalizeStorageEntries(snapshot.storageEntries);
  if (normalizedEntries !== undefined) {
    normalizedSnapshot.storageEntries = normalizedEntries;
  }
  return normalizedSnapshot;
}

export async function captureNormalizedStateSnapshot(stateManager) {
  return normalizeStateSnapshot(await stateManager.captureStateSnapshot());
}

export async function createStateSnapshotFromStorageEntries({
  channelId,
  storageAddresses,
  storageEntries,
}) {
  if (storageAddresses.length !== storageEntries.length) {
    throw new Error("storageAddresses/storageEntries length mismatch when building a state snapshot.");
  }
  const stateManager = new TokamakL2StateManager({ common: createTokamakL2Common() });
  const addressObjects = storageAddresses.map((address) => createAddressFromString(address));
  await stateManager._initializeForAddresses(addressObjects);
  stateManager._channelId = channelId;

  for (const [addressIndex, address] of addressObjects.entries()) {
    stateManager._commitResolvedStorageEntries(address, []);
    for (const entry of storageEntries[addressIndex]) {
      await stateManager.putStorage(
        address,
        hexToBytes(addHexPrefix(entry.key)),
        hexToBytes(addHexPrefix(entry.value)),
      );
    }
  }

  return normalizeStateSnapshot(await stateManager.captureStateSnapshot());
}

export async function createEmptyStateSnapshot({ channelId, storageAddresses }) {
  return createStateSnapshotFromStorageEntries({
    channelId,
    storageAddresses,
    storageEntries: storageAddresses.map(() => []),
  });
}

export function snapshotStorageKeysForAddress(snapshot, storageAddress) {
  const normalizedAddress = getAddress(storageAddress);
  const addressIndex = snapshot.storageAddresses.findIndex(
    (entry) => getAddress(entry) === normalizedAddress,
  );
  if (addressIndex < 0) {
    throw new Error(`Storage snapshot does not include ${normalizedAddress}.`);
  }
  if (!Array.isArray(snapshot.storageKeys)) {
    return (snapshot.storageEntries?.[addressIndex] ?? []).map((entry) => normalizeBytes32Hex(entry.key));
  }
  return snapshot.storageKeys[addressIndex] ?? [];
}

export async function readStorageValueFromSnapshot({ snapshot, storageAddress, storageKey }) {
  if (!Array.isArray(snapshot.storageTrieRoots) || !Array.isArray(snapshot.storageTrieDb)) {
    const normalizedAddress = getAddress(storageAddress);
    const addressIndex = snapshot.storageAddresses.findIndex(
      (entry) => getAddress(entry) === normalizedAddress,
    );
    if (addressIndex < 0) {
      throw new Error(`Storage snapshot does not include ${normalizedAddress}.`);
    }
    const entry = (snapshot.storageEntries?.[addressIndex] ?? []).find(
      (item) => normalizeBytes32Hex(item.key) === normalizeBytes32Hex(storageKey),
    );
    return entry?.value ?? "0x";
  }

  const normalizedAddress = getAddress(storageAddress);
  const addressIndex = snapshot.storageAddresses.findIndex(
    (entry) => getAddress(entry) === normalizedAddress,
  );
  if (addressIndex < 0) {
    throw new Error(`Storage snapshot does not include ${normalizedAddress}.`);
  }

  const trie = await buildStorageTrie({
    storageAddress: normalizedAddress,
    storageTrieRoot: snapshot.storageTrieRoots[addressIndex],
    storageTrieDb: snapshot.storageTrieDb[addressIndex],
  });
  const encodedValue = await trie.get(hexToBytes(normalizeBytes32Hex(storageKey)));
  if (encodedValue === null) {
    return "0x";
  }
  const decodedValue = RLP.decode(encodedValue);
  return bytesToHex(decodedValue);
}
