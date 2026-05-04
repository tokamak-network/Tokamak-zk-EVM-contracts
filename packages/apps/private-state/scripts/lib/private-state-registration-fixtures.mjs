import { Interface, ethers, getAddress } from "ethers";
import {
  MAX_MT_LEAVES,
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
  computeEncryptedNoteSalt,
  encryptMintNoteValueForOwner,
  encryptNoteValueForRecipient,
} from "../e2e/private-state-note-delivery.mjs";

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
