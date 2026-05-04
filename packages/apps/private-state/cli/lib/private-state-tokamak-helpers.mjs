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
  bytesToBigInt,
  bytesToHex,
  createAddressFromString,
  hexToBigInt,
  hexToBytes,
} from "@ethereumjs/util";
import {
  resolveTokamakBlockInputConfig,
} from "@tokamak-private-dapps/common-library/tokamak-runtime-paths";

const { previousBlockHashCount: tokamakPrevBlockHashCount } = resolveTokamakBlockInputConfig();

export function normalizeBytesHex(value, byteLength) {
  if (!Number.isInteger(byteLength) || byteLength <= 0) {
    throw new Error("normalizeBytesHex requires a positive byte length.");
  }
  const targetHexLength = byteLength * 2;
  let hex;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!/^0x[0-9a-fA-F]*$/.test(trimmed)) {
      throw new Error(`Expected a hex string, received ${value}.`);
    }
    hex = trimmed.replace(/^0x/i, "");
    if (hex.length % 2 !== 0) {
      hex = `0${hex}`;
    }
  } else {
    hex = ethers.hexlify(value).replace(/^0x/i, "");
  }
  if (hex.length > targetHexLength) {
    throw new Error(`Expected at most ${byteLength} bytes, received ${Math.ceil(hex.length / 2)} bytes.`);
  }
  return `0x${hex.padStart(targetHexLength, "0").toLowerCase()}`;
}

export function normalizeBytes32Hex(hexValue) {
  return normalizeBytesHex(hexValue, 32);
}

export function bytes32FromHex(hexValue) {
  return normalizeBytes32Hex(hexValue);
}

export function bigintToHex32(value) {
  return normalizeBytes32Hex(ethers.toBeHex(value));
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
      code: addHexPrefix(entry.code),
    })),
  });
}

export async function currentStorageBigInt(stateManager, address, keyHex) {
  const valueBytes = await stateManager.getStorage(
    createAddressFromString(address),
    hexToBytes(addHexPrefix(String(keyHex ?? "").replace(/^0x/i, ""))),
  );
  if (valueBytes.length === 0) {
    return 0n;
  }
  return bytesToBigInt(valueBytes);
}

export async function putStorageValue(stateManager, address, keyHex, nextValue) {
  await stateManager.putStorage(
    createAddressFromString(address),
    hexToBytes(addHexPrefix(String(keyHex ?? "").replace(/^0x/i, ""))),
    hexToBytes(addHexPrefix(String(bigintToHex32(nextValue) ?? "").replace(/^0x/i, ""))),
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
  const latestNumber = Number(hexToBigInt(addHexPrefix(String(latestNumberHex ?? "").replace(/^0x/i, ""))));
  return getBlockInfoAt(provider, latestNumber, { send });
}

export function deriveLiquidBalanceStorageKey(l2Address, slot) {
  return normalizeBytes32Hex(bytesToHex(getUserStorageKey([l2Address, ethers.toBigInt(slot)], "TokamakL2")));
}

export function deriveChannelTokenVaultLeafIndex(storageKey) {
  return hexToBigInt(addHexPrefix(String(storageKey ?? "").replace(/^0x/i, ""))) % ethers.toBigInt(MAX_MT_LEAVES);
}
