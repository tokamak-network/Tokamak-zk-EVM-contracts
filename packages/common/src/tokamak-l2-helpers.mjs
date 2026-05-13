import { ethers, getAddress } from "ethers";
import {
  MAX_MT_LEAVES,
  TokamakL2StateManager,
  createTokamakL2Common,
  createTokamakL2StateManagerFromStateSnapshot,
  createTokamakL2Tx,
  getUserStorageKey,
  poseidon,
} from "tokamak-l2js";
import {
  addHexPrefix,
  createAddressFromString,
  hexToBytes,
} from "@ethereumjs/util";
import {
  resolveTokamakBlockInputConfig,
} from "./tokamak-runtime-paths.mjs";

const { previousBlockHashCount: tokamakPrevBlockHashCount } = resolveTokamakBlockInputConfig();

export function normalizeBytesHex(value, byteLength) {
  if (!Number.isInteger(byteLength) || byteLength <= 0) {
    throw new Error("normalizeBytesHex requires a positive byte length.");
  }
  let normalizedValue = value;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!/^0x[0-9a-fA-F]*$/.test(trimmed)) {
      throw new Error(`Expected a hex string, received ${value}.`);
    }
    normalizedValue = trimmed === "0x" ? 0n : trimmed;
  }
  return ethers.toBeHex(ethers.toBigInt(normalizedValue), byteLength).toLowerCase();
}

export function normalizeBytes32Hex(value) {
  return normalizeBytesHex(value, 32);
}

export function bigintToHex32(value) {
  return ethers.toBeHex(value, 32).toLowerCase();
}

export function poseidonHexFromBytes(bytesLike) {
  return ethers.hexlify(poseidon(ethers.getBytes(bytesLike))).toLowerCase();
}

export function serializeBigInts(value) {
  return JSON.parse(JSON.stringify(value, (_key, current) => (
    typeof current === "bigint" ? current.toString() : current
  )));
}

export function buildTokamakTxSnapshot({ signerPrivateKey, senderPubKey, to, data, nonce }) {
  return serializeBigInts(
    createTokamakL2Tx(
      {
        nonce: ethers.toBigInt(nonce),
        to: createAddressFromString(to),
        data: hexToBytes(addHexPrefix(String(data ?? "").replace(/^0x/i, ""))),
        senderPubKey,
      },
      { common: createTokamakL2Common() },
    )
      .sign(signerPrivateKey)
      .captureTxSnapshot(),
  );
}

export async function fetchContractCodes(provider, addresses, { requireBytecode = false } = {}) {
  const codes = [];
  for (const address of addresses) {
    const normalizedAddress = getAddress(address);
    const code = await provider.getCode(normalizedAddress);
    if (requireBytecode && code === "0x") {
      throw new Error(`No deployed bytecode found at ${normalizedAddress}.`);
    }
    codes.push({ address: normalizedAddress, code });
  }
  return codes;
}

export async function buildStateManager(snapshot, contractCodes) {
  return createTokamakL2StateManagerFromStateSnapshot(snapshot, {
    contractCodes: contractCodes.map((entry) => ({
      address: createAddressFromString(entry.address),
      code: ethers.hexlify(ethers.getBytes(entry.code ?? "0x")),
    })),
  });
}

export async function currentStorageBigInt(stateManager, address, keyHex) {
  const valueBytes = await stateManager.getStorage(
    createAddressFromString(address),
    ethers.getBytes(normalizeBytes32Hex(keyHex)),
  );
  if (valueBytes.length === 0) {
    return 0n;
  }
  return ethers.toBigInt(valueBytes);
}

export async function putStorageValue(stateManager, address, keyHex, nextValue) {
  await stateManager.putStorage(
    createAddressFromString(address),
    ethers.getBytes(normalizeBytes32Hex(keyHex)),
    ethers.getBytes(bigintToHex32(nextValue)),
  );
}

export async function putStorageAndCapture(stateManager, address, keyHex, nextValue) {
  await currentStorageBigInt(stateManager, address, keyHex);
  await putStorageValue(stateManager, address, keyHex, nextValue);
  return stateManager.captureStateSnapshot();
}

export async function initializePrivateStateSnapshot({ controllerAddress, vaultAddress, channelId }) {
  const stateManager = new TokamakL2StateManager({ common: createTokamakL2Common() });
  const addresses = [controllerAddress, vaultAddress].map((address) => createAddressFromString(address));
  await stateManager._initializeForAddresses(addresses);
  stateManager._channelId = channelId;
  for (const address of addresses) {
    stateManager._commitResolvedStorageEntries(address, []);
  }
  return stateManager.captureStateSnapshot();
}

export async function getBlockInfoAt(provider, blockNumber, { send = (method, params) => provider.send(method, params) } = {}) {
  const blockTag = ethers.toQuantity(blockNumber);
  const block = await send("eth_getBlockByNumber", [blockTag, false]);
  const prevBlockHashes = [];
  for (let offset = 1; offset <= tokamakPrevBlockHashCount; offset += 1) {
    if (blockNumber <= offset) {
      prevBlockHashes.push("0x0");
      continue;
    }
    const previousBlock = await send("eth_getBlockByNumber", [ethers.toQuantity(blockNumber - offset), false]);
    prevBlockHashes.push(previousBlock.hash);
  }
  const chainId = await send("eth_chainId", []);
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

export async function getFixedBlockInfo(provider, options = {}) {
  const send = options.send ?? ((method, params) => provider.send(method, params));
  const latestNumberHex = await send("eth_blockNumber", []);
  const latestNumber = Number(ethers.toBigInt(latestNumberHex));
  return getBlockInfoAt(provider, latestNumber, { send });
}

export function deriveLiquidBalanceStorageKey(l2Address, slot) {
  return normalizeBytes32Hex(ethers.hexlify(getUserStorageKey([l2Address, ethers.toBigInt(slot)], "TokamakL2")));
}

export function deriveChannelTokenVaultLeafIndex(storageKey) {
  return ethers.toBigInt(storageKey) % ethers.toBigInt(MAX_MT_LEAVES);
}
