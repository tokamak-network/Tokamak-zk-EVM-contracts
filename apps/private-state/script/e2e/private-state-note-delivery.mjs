import {
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
const NOTE_RECEIVE_FIELD_ENCRYPTION_INFO = "PRIVATE_STATE_NOTE_FIELD_ENCRYPTION_V1";
const BLS12_381_SCALAR_FIELD_MODULUS =
  BigInt("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");
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

function fieldElementHex(value) {
  return normalizeBytes32Hex(ethers.toBeHex(value));
}

function normalizeTagHex(value) {
  return ethers.hexlify(ethers.zeroPadValue(value, 16)).toLowerCase();
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

function encodeNoteValuePlaintext(value) {
  const scalar = BigInt(value);
  if (scalar < 0n || scalar >= BLS12_381_SCALAR_FIELD_MODULUS) {
    throw new Error("Encrypted note plaintext value must fit within the BLS12-381 scalar field.");
  }
  return scalar;
}

function decodeNoteValuePlaintext(valueField) {
  return BigInt(valueField).toString();
}

function deriveFieldMask({
  sharedSecretPoint,
  chainId,
  channelId,
  owner,
  nonce,
}) {
  const affine = sharedSecretPoint.toAffine();
  return BigInt(poseidonHexFromBytes(
    abiCoder.encode(
      ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12"],
      [
        NOTE_RECEIVE_FIELD_ENCRYPTION_INFO,
        BigInt(chainId),
        BigInt(channelId),
        ethers.getAddress(owner),
        affine.x,
        affine.y,
        ethers.zeroPadValue(nonce, 12),
      ],
    ),
  ));
}

function deriveCipherTag({
  sharedSecretPoint,
  chainId,
  channelId,
  owner,
  nonce,
  ciphertextValue,
}) {
  const affine = sharedSecretPoint.toAffine();
  return ethers.dataSlice(
    poseidonHexFromBytes(
      abiCoder.encode(
        ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12", "bytes32"],
        [
          `${NOTE_RECEIVE_FIELD_ENCRYPTION_INFO}:tag`,
          BigInt(chainId),
          BigInt(channelId),
          ethers.getAddress(owner),
          affine.x,
          affine.y,
          ethers.zeroPadValue(nonce, 12),
          fieldElementHex(ciphertextValue),
        ],
      ),
    ),
    0,
    16,
  );
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
  return ethers.zeroPadValue(poseidonHexFromBytes(ethers.concat(normalized)), 32).toLowerCase();
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
  const sharedSecretPoint = recipientPoint.multiply(ephemeralPrivateScalar);
  const cipherNonce = nonce ? ethers.zeroPadValue(nonce, 12) : ethers.hexlify(randomBytes(12));
  const plaintextValue = encodeNoteValuePlaintext(value);
  const fieldMask = deriveFieldMask({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce: cipherNonce,
  });
  const ciphertextValue = (plaintextValue + fieldMask) % BLS12_381_SCALAR_FIELD_MODULUS;
  const tag = deriveCipherTag({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce: cipherNonce,
    ciphertextValue,
  });
  const parsedEphemeralPubKey = noteReceivePubKeyFromPoint(ephemeralPoint);

  return packEncryptedNoteValue({
    ephemeralPubKeyX: parsedEphemeralPubKey.x,
    ephemeralPubKeyYParity: parsedEphemeralPubKey.yParity,
    nonce: cipherNonce,
    ciphertextValue: fieldElementHex(ciphertextValue),
    tag,
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
  const sharedSecretPoint = pointFromNoteReceivePubKey({
      x: normalized.ephemeralPubKeyX,
      yParity: normalized.ephemeralPubKeyYParity,
    }).multiply(parseJubjubPrivateScalar(noteReceivePrivateKey));
  const expectedTag = deriveCipherTag({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce: normalized.nonce,
    ciphertextValue: ethers.toBigInt(normalized.ciphertextValue),
  });
  if (normalizeTagHex(expectedTag) !== normalizeTagHex(normalized.tag)) {
    throw new Error("Encrypted note value integrity tag mismatch.");
  }
  const fieldMask = deriveFieldMask({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce: normalized.nonce,
  });
  const plaintext = (
    ethers.toBigInt(normalized.ciphertextValue)
    - fieldMask
    + BLS12_381_SCALAR_FIELD_MODULUS
  ) % BLS12_381_SCALAR_FIELD_MODULUS;
  return decodeNoteValuePlaintext(plaintext);
}

export function encryptedNoteValueTuple(encryptedValue) {
  return normalizeEncryptedNoteValueWords(encryptedValue);
}
