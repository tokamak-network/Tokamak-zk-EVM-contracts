import { Interface, ethers, getAddress } from "ethers";
import {
  computeEncryptedNoteSalt,
  encryptMintNoteValueForOwner,
  encryptNoteValueForRecipient,
} from "../../cli/lib/private-state-note-delivery.mjs";
export {
  buildStateManager,
  buildTokamakTxSnapshot,
  currentStorageBigInt,
  deriveChannelTokenVaultLeafIndex,
  deriveLiquidBalanceStorageKey,
  fetchContractCodes,
  getFixedBlockInfo,
  initializePrivateStateSnapshot,
  normalizeBytes32Hex,
  putStorageAndCapture,
  putStorageValue,
} from "../../cli/lib/private-state-tokamak-helpers.mjs";
import {
  deriveChannelTokenVaultLeafIndex,
  deriveLiquidBalanceStorageKey,
  normalizeBytes32Hex,
  poseidonHexFromBytes,
} from "../../cli/lib/private-state-tokamak-helpers.mjs";

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
