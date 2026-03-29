import {
  createCipheriv,
  createDecipheriv,
  hkdfSync,
  randomBytes,
} from "node:crypto";
import { AbiCoder, ethers } from "ethers";
import { deriveL2KeysFromSignature, poseidon } from "tokamak-l2js";
import { jubjub } from "@noble/curves/jubjub";

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
const NOTE_RECEIVE_TYPED_DATA_PROTOCOL = "PRIVATE_STATE_NOTE_RECEIVE_KEY_V2";
const NOTE_RECEIVE_TYPED_DATA_DAPP = "private-state";
const NOTE_RECEIVE_ECIES_INFO = Buffer.from("PRIVATE_STATE_NOTE_ECIES_V2", "utf8");
const NOTE_RECEIVE_AAD_LABEL = "PRIVATE_STATE_TRANSFER_NOTE_V2";
const JUBJUB_ORDER = jubjub.CURVE.n;
const JUBJUB_FP = jubjub.CURVE.Fp;
const JUBJUB_A = jubjub.CURVE.a;
const JUBJUB_D = jubjub.CURVE.d;

function noteReceivePubKeyFromPoint(point) {
  const affine = point.toAffine();
  return {
    x: normalizeBytes32Hex(ethers.toBeHex(affine.x)),
    yParity: Number(affine.y & 1n),
  };
}

function pointFromNoteReceivePubKey(noteReceivePubKey) {
  const x = ethers.toBigInt(noteReceivePubKey.x);
  if (x >= JUBJUB_FP.ORDER) {
    throw new Error("Jubjub note-receive public key x-coordinate is out of range.");
  }
  const xSquared = JUBJUB_FP.mul(x, x);
  const numerator = JUBJUB_FP.sub(1n, JUBJUB_FP.mul(JUBJUB_A, xSquared));
  const denominator = JUBJUB_FP.sub(1n, JUBJUB_FP.mul(JUBJUB_D, xSquared));
  let y = JUBJUB_FP.sqrt(JUBJUB_FP.div(numerator, denominator));
  if (Number(y & 1n) !== Number(noteReceivePubKey.yParity)) {
    y = JUBJUB_FP.neg(y);
  }
  return jubjub.ExtendedPoint.fromAffine({ x, y });
}

function parseJubjubPrivateScalar(privateKey) {
  const scalar = ethers.toBigInt(privateKey);
  if (scalar <= 0n || scalar >= JUBJUB_ORDER) {
    throw new Error("Jubjub note-receive private key must be within the scalar field range.");
  }
  return scalar;
}

function deriveEphemeralJubjubScalar() {
  const raw = ethers.toBigInt(ethers.hexlify(jubjub.utils.randomPrivateKey(randomBytes(32))));
  return (raw % (JUBJUB_ORDER - 1n)) + 1n;
}

function normalizeBytes32Hex(value) {
  return ethers.hexlify(ethers.zeroPadValue(ethers.hexlify(value), 32)).toLowerCase();
}

function normalizeEncryptedNoteValueWords(encryptedNoteValue) {
  if (!Array.isArray(encryptedNoteValue) || encryptedNoteValue.length !== 3) {
    throw new Error("Encrypted note value must be a bytes32[3] payload.");
  }
  return encryptedNoteValue.map((word) => normalizeBytes32Hex(word));
}

function poseidonHexFromBytes(bytesLike) {
  return ethers.hexlify(poseidon(ethers.getBytes(bytesLike))).toLowerCase();
}

function packEncryptedNoteValue({
  ephemeralPubKeyX,
  ephemeralPubKeyYParity,
  nonce,
  ciphertextValue,
  tag,
}) {
  const parity = Number(ephemeralPubKeyYParity);
  if (parity !== 0 && parity !== 1) {
    throw new Error("Encrypted note value y parity must be 0 or 1.");
  }
  return normalizeEncryptedNoteValueWords([
    ephemeralPubKeyX,
    ethers.hexlify(ethers.concat([
      Uint8Array.from([parity]),
      ethers.getBytes(ethers.zeroPadValue(nonce, 12)),
      ethers.getBytes(ethers.zeroPadValue(tag, 16)),
      new Uint8Array(3),
    ])),
    ciphertextValue,
  ]);
}

function unpackEncryptedNoteValue(encryptedNoteValue) {
  const [ephemeralPubKeyX, packedMeta, ciphertextValue] = normalizeEncryptedNoteValueWords(encryptedNoteValue);
  const packedMetaBytes = ethers.getBytes(packedMeta);
  return {
    ephemeralPubKeyX,
    ephemeralPubKeyYParity: packedMetaBytes[0],
    nonce: ethers.hexlify(packedMetaBytes.slice(1, 13)),
    ciphertextValue,
    tag: ethers.hexlify(packedMetaBytes.slice(13, 29)),
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

function decodeNoteValuePlaintext(valueBytes) {
  if (valueBytes.length !== 32) {
    throw new Error("Encrypted note plaintext must decode to 32 bytes.");
  }
  return BigInt(ethers.hexlify(valueBytes)).toString();
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
  const derivedKeys = deriveL2KeysFromSignature(signature);
  const privateKey = ethers.hexlify(derivedKeys.privateKey);
  const noteReceivePoint = jubjub.ExtendedPoint.fromHex(derivedKeys.publicKey);
  return {
    typedData,
    signature,
    privateKey,
    noteReceivePubKey: noteReceivePubKeyFromPoint(noteReceivePoint),
  };
}

export function computeEncryptedNoteSalt(encryptedValue) {
  const normalized = normalizeEncryptedNoteValueWords(encryptedValue);
  return ethers.zeroPadValue(
    poseidonHexFromBytes(abiCoder.encode(["bytes32[3]"], [normalized])),
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
  const recipientPoint = pointFromNoteReceivePubKey(recipientNoteReceivePubKey);
  const ephemeralPrivateScalar = deriveEphemeralJubjubScalar();
  const ephemeralPoint = jubjub.ExtendedPoint.BASE.multiply(ephemeralPrivateScalar);
  const sharedSecret = Buffer.from(recipientPoint.multiply(ephemeralPrivateScalar).toRawBytes());
  const aad = buildNoteReceiveAAD({ chainId, channelId, owner });
  const encryptionKey = Buffer.from(hkdfSync("sha256", sharedSecret, NOTE_RECEIVE_ECIES_INFO, aad, 32));
  const cipherNonce = nonce ? Buffer.from(ethers.getBytes(nonce)) : randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey, cipherNonce);
  cipher.setAAD(aad);
  const ciphertextValue = Buffer.concat([cipher.update(encodeNoteValuePlaintext(value)), cipher.final()]);
  const tag = cipher.getAuthTag();
  const parsedEphemeralPubKey = noteReceivePubKeyFromPoint(ephemeralPoint);

  if (ciphertextValue.length !== 32) {
    throw new Error("Encrypted note value ciphertext must remain 32 bytes.");
  }
  if (tag.length !== 16) {
    throw new Error("Encrypted note value tag must remain 16 bytes.");
  }

  return packEncryptedNoteValue({
    ephemeralPubKeyX: parsedEphemeralPubKey.x,
    ephemeralPubKeyYParity: parsedEphemeralPubKey.yParity,
    nonce: ethers.hexlify(cipherNonce),
    ciphertextValue: ethers.hexlify(ciphertextValue),
    tag: ethers.hexlify(tag),
  });
}

export function decryptEncryptedNoteValue({
  encryptedValue,
  noteReceivePrivateKey,
  chainId,
  channelId,
  owner,
}) {
  const normalized = unpackEncryptedNoteValue(encryptedValue);
  const sharedSecret = Buffer.from(
    pointFromNoteReceivePubKey({
      x: normalized.ephemeralPubKeyX,
      yParity: normalized.ephemeralPubKeyYParity,
    }).multiply(parseJubjubPrivateScalar(noteReceivePrivateKey)).toRawBytes(),
  );
  const aad = buildNoteReceiveAAD({ chainId, channelId, owner });
  const encryptionKey = Buffer.from(hkdfSync("sha256", sharedSecret, NOTE_RECEIVE_ECIES_INFO, aad, 32));
  const decipher = createDecipheriv(
    "aes-256-gcm",
    encryptionKey,
    Buffer.from(ethers.getBytes(normalized.nonce)),
  );
  decipher.setAAD(aad);
  decipher.setAuthTag(Buffer.from(ethers.getBytes(normalized.tag)));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(ethers.getBytes(normalized.ciphertextValue))),
    decipher.final(),
  ]);
  return decodeNoteValuePlaintext(plaintext);
}

export function encryptedNoteValueTuple(encryptedValue) {
  return normalizeEncryptedNoteValueWords(encryptedValue);
}
