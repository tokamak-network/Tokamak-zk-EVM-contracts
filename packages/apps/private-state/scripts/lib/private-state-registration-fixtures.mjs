import { Interface, ethers, getAddress } from "ethers";
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
  resolveTokamakBlockInputConfig,
} from "@tokamak-private-dapps/common-library/tokamak-runtime-paths";
import {
  addHexPrefix,
  bytesToBigInt,
  bytesToHex,
  createAddressFromString,
  hexToBigInt,
  hexToBytes,
} from "@ethereumjs/util";
import {
  computeEncryptedNoteSalt,
  encryptMintNoteValueForOwner,
  encryptNoteValueForRecipient,
} from "../../cli/lib/private-state-note-delivery.mjs";

const { previousBlockHashCount: tokamakPrevBlockHashCount } = resolveTokamakBlockInputConfig();

export function bytes32FromHex(hexValue) {
  return ethers.zeroPadValue(
    ethers.toBeHex(hexToBigInt(addHexPrefix(String(hexValue ?? "").replace(/^0x/i, "")))),
    32,
  );
}

export function normalizeBytes32Hex(hexValue) {
  return bytes32FromHex(hexValue).toLowerCase();
}

export function bigintToHex32(value) {
  return ethers.zeroPadValue(ethers.toBeHex(value), 32);
}

export function poseidonHexFromBytes(bytesLike) {
  return ethers.hexlify(poseidon(ethers.getBytes(bytesLike))).toLowerCase();
}

export function buildMintInterface(outputCount) {
  return new Interface([
    `function mintNotes${outputCount}((uint256 value,bytes32[3] encryptedNoteValue)[${outputCount}] outputs)`,
  ]);
}

export function buildTransferInterface(inputCount, outputCount) {
  return new Interface([
    `function transferNotes${inputCount}To${outputCount}((address owner,uint256 value,bytes32[3] encryptedNoteValue)[${outputCount}] outputs,(address owner,uint256 value,bytes32 salt)[${inputCount}] inputNotes)`,
  ]);
}

export function buildRedeemInterface(inputCount) {
  return new Interface([
    `function redeemNotes${inputCount}((address owner,uint256 value,bytes32 salt)[${inputCount}] inputNotes,address receiver)`,
  ]);
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

export function buildEncryptedMintOutput({ owner, ownerNoteReceivePubKey, value, label, chainId, channelId }) {
  const nonce = ethers.dataSlice(poseidonHexFromBytes(ethers.toUtf8Bytes(`${label}:nonce`)), 0, 12);
  const encryptedNoteValue = encryptMintNoteValueForOwner({
    value,
    ownerNoteReceivePubKey,
    chainId,
    channelId,
    owner,
    nonce,
  });
  return {
    output: { value, encryptedNoteValue },
    note: {
      owner: getAddress(owner),
      value,
      salt: computeEncryptedNoteSalt(encryptedNoteValue),
    },
  };
}

export function buildEncryptedTransferOutput({ owner, value, label, recipientNoteReceivePubKey, chainId, channelId }) {
  const nonce = ethers.dataSlice(poseidonHexFromBytes(ethers.toUtf8Bytes(`${label}:nonce`)), 0, 12);
  const encryptedNoteValue = encryptNoteValueForRecipient({
    value,
    recipientNoteReceivePubKey,
    chainId,
    channelId,
    owner,
    nonce,
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
