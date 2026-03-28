import {
  createECDH,
  createCipheriv,
  hkdfSync,
  randomBytes,
} from "node:crypto";
import { AbiCoder, SigningKey, ethers, keccak256 } from "ethers";

const abiCoder = AbiCoder.defaultAbiCoder();
const NOTE_RECEIVE_TYPED_DATA_DOMAIN = {
  name: "TokamakPrivateState",
  version: "1",
};
const NOTE_RECEIVE_TYPED_DATA_TYPES = {
  NoteReceiveKey: [
    { name: "protocol", type: "string" },
    { name: "dapp", type: "string" },
    { name: "channelId", type: "uint256" },
    { name: "channelName", type: "string" },
    { name: "account", type: "address" },
  ],
};
const NOTE_RECEIVE_TYPED_DATA_PROTOCOL = "PRIVATE_STATE_NOTE_RECEIVE_KEY_V1";
const NOTE_RECEIVE_TYPED_DATA_DAPP = "private-state";
const NOTE_RECEIVE_ECIES_INFO = Buffer.from("PRIVATE_STATE_NOTE_ECIES_V1", "utf8");
const NOTE_RECEIVE_AAD_LABEL = "PRIVATE_STATE_TRANSFER_NOTE_V1";
const SECP256K1_ORDER =
  BigInt("0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141");

function deriveSecp256k1PrivateKeyFromSeed(seedHex) {
  const seed = BigInt(seedHex);
  const scalar = (seed % (SECP256K1_ORDER - 1n)) + 1n;
  return ethers.zeroPadValue(ethers.toBeHex(scalar), 32);
}

function noteReceivePubKeyFromCompressedHex(compressedHex) {
  const bytes = ethers.getBytes(compressedHex);
  if (bytes.length !== 33) {
    throw new Error("Compressed secp256k1 public key must be 33 bytes.");
  }
  if (bytes[0] !== 0x02 && bytes[0] !== 0x03) {
    throw new Error("Compressed secp256k1 public key must use prefix 0x02 or 0x03.");
  }
  return {
    x: ethers.hexlify(bytes.slice(1)),
    yParity: bytes[0] === 0x03 ? 1 : 0,
  };
}

function compressedHexFromNoteReceivePubKey(noteReceivePubKey) {
  const prefix = Number(noteReceivePubKey.yParity) === 1 ? "03" : "02";
  return `0x${prefix}${ethers.zeroPadValue(noteReceivePubKey.x, 32).slice(2)}`;
}

function normalizeEncryptedNoteValue(encryptedValue) {
  return {
    ephemeralPubKeyX: ethers.zeroPadValue(ethers.toBeHex(BigInt(encryptedValue.ephemeralPubKeyX)), 32).toLowerCase(),
    ephemeralPubKeyYParity: Number(encryptedValue.ephemeralPubKeyYParity),
    nonce: ethers.hexlify(ethers.getBytes(encryptedValue.nonce)),
    ciphertextValue: ethers.zeroPadValue(ethers.toBeHex(BigInt(encryptedValue.ciphertextValue)), 32).toLowerCase(),
    tag: ethers.hexlify(ethers.getBytes(encryptedValue.tag)),
  };
}

function buildNoteReceiveTypedData({ chainId, channelId, channelName, account }) {
  return {
    domain: {
      ...NOTE_RECEIVE_TYPED_DATA_DOMAIN,
      chainId,
    },
    types: NOTE_RECEIVE_TYPED_DATA_TYPES,
    value: {
      protocol: NOTE_RECEIVE_TYPED_DATA_PROTOCOL,
      dapp: NOTE_RECEIVE_TYPED_DATA_DAPP,
      channelId: BigInt(channelId).toString(),
      channelName,
      account: ethers.getAddress(account),
    },
  };
}

function buildNoteReceiveAAD({ chainId, channelId, owner }) {
  return Buffer.from(
    ethers.getBytes(
      abiCoder.encode(
        ["string", "uint256", "uint256", "address"],
        [NOTE_RECEIVE_AAD_LABEL, BigInt(chainId), BigInt(channelId), ethers.getAddress(owner)],
      ),
    ),
  );
}

function encodeNoteValuePlaintext(value) {
  return Buffer.from(ethers.getBytes(ethers.zeroPadValue(ethers.toBeHex(BigInt(value)), 32)));
}

export async function deriveNoteReceiveKeyMaterial({
  signer,
  chainId,
  channelId,
  channelName,
  account,
}) {
  const typedData = buildNoteReceiveTypedData({
    chainId,
    channelId,
    channelName,
    account,
  });
  const signature = await signer.signTypedData(typedData.domain, typedData.types, typedData.value);
  const privateKey = deriveSecp256k1PrivateKeyFromSeed(keccak256(signature));
  const compressedPubKey = SigningKey.computePublicKey(privateKey, true);
  return {
    typedData,
    signature,
    privateKey,
    noteReceivePubKey: noteReceivePubKeyFromCompressedHex(compressedPubKey),
  };
}

export function computeEncryptedNoteSalt(encryptedValue) {
  const normalized = normalizeEncryptedNoteValue(encryptedValue);
  return ethers.zeroPadValue(
    keccak256(
      abiCoder.encode(
        ["bytes32", "uint8", "bytes12", "bytes32", "bytes16"],
        [
          normalized.ephemeralPubKeyX,
          normalized.ephemeralPubKeyYParity,
          normalized.nonce,
          normalized.ciphertextValue,
          normalized.tag,
        ],
      ),
    ),
    32,
  ).toLowerCase();
}

export function encryptNoteValueForRecipient({
  value,
  recipientNoteReceivePubKey,
  chainId,
  channelId,
  owner,
  nonce = null,
}) {
  const recipientCompressedPubKey = compressedHexFromNoteReceivePubKey(recipientNoteReceivePubKey);
  const ephemeral = createECDH("secp256k1");
  ephemeral.generateKeys();
  const sharedSecret = ephemeral.computeSecret(Buffer.from(ethers.getBytes(recipientCompressedPubKey)));
  const aad = buildNoteReceiveAAD({ chainId, channelId, owner });
  const encryptionKey = Buffer.from(hkdfSync("sha256", sharedSecret, NOTE_RECEIVE_ECIES_INFO, aad, 32));
  const cipherNonce = nonce ? Buffer.from(ethers.getBytes(nonce)) : randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey, cipherNonce);
  cipher.setAAD(aad);
  const ciphertextValue = Buffer.concat([cipher.update(encodeNoteValuePlaintext(value)), cipher.final()]);
  const tag = cipher.getAuthTag();
  const ephemeralCompressedPubKey = ethers.hexlify(ephemeral.getPublicKey(undefined, "compressed"));
  const parsedEphemeralPubKey = noteReceivePubKeyFromCompressedHex(ephemeralCompressedPubKey);

  if (ciphertextValue.length !== 32) {
    throw new Error("Encrypted note value ciphertext must remain 32 bytes.");
  }
  if (tag.length !== 16) {
    throw new Error("Encrypted note value tag must remain 16 bytes.");
  }

  return normalizeEncryptedNoteValue({
    ephemeralPubKeyX: parsedEphemeralPubKey.x,
    ephemeralPubKeyYParity: parsedEphemeralPubKey.yParity,
    nonce: ethers.hexlify(cipherNonce),
    ciphertextValue: ethers.hexlify(ciphertextValue),
    tag: ethers.hexlify(tag),
  });
}
