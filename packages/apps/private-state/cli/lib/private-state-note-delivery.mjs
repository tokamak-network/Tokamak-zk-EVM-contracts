import { randomBytes } from "node:crypto";
import { AbiCoder, ethers } from "ethers";
import { deriveL2KeysFromSignature, poseidon } from "tokamak-l2js";
import { jubjub } from "@noble/curves/jubjub";

const abiCoder = AbiCoder.defaultAbiCoder();

export const NOTE_RECEIVE_TYPED_DATA_METHOD = "eth_signTypedData_v4";
export const NOTE_RECEIVE_KEY_DERIVATION_VERSION = 2;
export const ENCRYPTED_NOTE_SCHEME_TRANSFER = 0;
export const ENCRYPTED_NOTE_SCHEME_SELF_MINT = 1;
export const BLS12_381_SCALAR_FIELD_MODULUS =
  ethers.toBigInt("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");

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
const TRANSFER_NOTE_FIELD_ENCRYPTION_INFO = "PRIVATE_STATE_NOTE_FIELD_ENCRYPTION_V1";
const MINT_NOTE_FIELD_ENCRYPTION_INFO = "PRIVATE_STATE_SELF_MINT_NOTE_FIELD_ENCRYPTION_V1";
const NOTE_COMMITMENT_DOMAIN = ethers.keccak256(ethers.toUtf8Bytes("PRIVATE_STATE_NOTE_COMMITMENT"));
const NULLIFIER_DOMAIN = ethers.keccak256(ethers.toUtf8Bytes("PRIVATE_STATE_NULLIFIER"));
const JUBJUB_ORDER = jubjub.CURVE.n;
const JUBJUB_FP = jubjub.CURVE.Fp;
const JUBJUB_A = jubjub.CURVE.a;
const JUBJUB_D = jubjub.CURVE.d;

function expect(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function normalizeBytes32Hex(value) {
  return ethers.hexlify(ethers.zeroPadValue(ethers.hexlify(value), 32)).toLowerCase();
}

function normalizeBytes16Hex(value) {
  return ethers.hexlify(ethers.zeroPadValue(ethers.hexlify(value), 16)).toLowerCase();
}

function poseidonHexFromBytes(bytesLike) {
  return ethers.hexlify(poseidon(ethers.getBytes(bytesLike))).toLowerCase();
}

function noteReceivePubKeyFromPoint(point) {
  const affine = point.toAffine();
  return {
    x: normalizeBytes32Hex(ethers.toBeHex(affine.x)),
    yParity: Number(affine.y & 1n),
  };
}

function pointFromNoteReceivePubKey(noteReceivePubKey) {
  const x = ethers.toBigInt(noteReceivePubKey.x);
  expect(x < JUBJUB_FP.ORDER, "Jubjub note-receive public key x-coordinate is out of range.");
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
  expect(
    scalar > 0n && scalar < JUBJUB_ORDER,
    "Jubjub note-receive private key must be within the scalar field range.",
  );
  return scalar;
}

function deriveEphemeralJubjubScalar() {
  const raw = ethers.toBigInt(ethers.hexlify(jubjub.utils.randomPrivateKey(randomBytes(32))));
  return (raw % (JUBJUB_ORDER - 1n)) + 1n;
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
      channelId: ethers.toBigInt(channelId).toString(),
      channelName,
      account: ethers.getAddress(account),
    },
  };
}

export function computeNoteCommitment(note) {
  const data = ethers.getBytes(ethers.concat([
    NOTE_COMMITMENT_DOMAIN,
    ethers.zeroPadValue(ethers.getAddress(note.owner), 32),
    ethers.toBeHex(ethers.toBigInt(note.value), 32),
    normalizeBytes32Hex(note.salt),
  ]));
  return normalizeBytes32Hex(poseidonHexFromBytes(data));
}

export function computeNullifier(note) {
  const data = ethers.getBytes(ethers.concat([
    NULLIFIER_DOMAIN,
    ethers.zeroPadValue(ethers.getAddress(note.owner), 32),
    ethers.toBeHex(ethers.toBigInt(note.value), 32),
    normalizeBytes32Hex(note.salt),
  ]));
  return normalizeBytes32Hex(poseidonHexFromBytes(data));
}

export function normalizeEncryptedNoteValueWords(encryptedNoteValue) {
  expect(
    Array.isArray(encryptedNoteValue) && encryptedNoteValue.length === 3,
    "Encrypted note value must be a bytes32[3] payload.",
  );
  return encryptedNoteValue.map((word) => normalizeBytes32Hex(word));
}

function packEncryptedNoteValue({
  ephemeralPubKeyX,
  ephemeralPubKeyYParity,
  nonce,
  ciphertextValue,
  tag,
  scheme = ENCRYPTED_NOTE_SCHEME_TRANSFER,
}) {
  const parity = Number(ephemeralPubKeyYParity);
  expect(parity === 0 || parity === 1, "Encrypted note value y parity must be 0 or 1.");
  const normalizedScheme = Number(scheme);
  expect(
    Number.isInteger(normalizedScheme) && normalizedScheme >= 0 && normalizedScheme <= 255,
    "Encrypted note value scheme must fit in one byte.",
  );
  return normalizeEncryptedNoteValueWords([
    normalizeBytes32Hex(ephemeralPubKeyX),
    ethers.hexlify(ethers.concat([
      Uint8Array.from([parity]),
      ethers.getBytes(ethers.zeroPadValue(nonce, 12)),
      ethers.getBytes(ethers.zeroPadValue(tag, 16)),
      Uint8Array.from([normalizedScheme, 0, 0]),
    ])),
    normalizeBytes32Hex(ciphertextValue),
  ]);
}

export function unpackEncryptedNoteValue(encryptedNoteValue) {
  const [ephemeralPubKeyX, packedMeta, ciphertextValue] = normalizeEncryptedNoteValueWords(encryptedNoteValue);
  const packedMetaBytes = ethers.getBytes(packedMeta);
  return {
    ephemeralPubKeyX,
    ephemeralPubKeyYParity: packedMetaBytes[0],
    nonce: ethers.hexlify(packedMetaBytes.slice(1, 13)),
    ciphertextValue,
    tag: ethers.hexlify(packedMetaBytes.slice(13, 29)),
    scheme: packedMetaBytes[29],
  };
}

export function computeEncryptedNoteSalt(encryptedValue) {
  const normalized = normalizeEncryptedNoteValueWords(encryptedValue);
  return normalizeBytes32Hex(poseidonHexFromBytes(ethers.getBytes(ethers.concat(normalized))));
}

function encodeNoteValuePlaintext(value) {
  const scalar = ethers.toBigInt(value);
  expect(
    scalar >= 0n && scalar < BLS12_381_SCALAR_FIELD_MODULUS,
    "Encrypted note plaintext value must fit within the BLS12-381 scalar field.",
  );
  return scalar;
}

function decodeNoteValuePlaintext(valueBytes) {
  return ethers.toBigInt(valueBytes).toString();
}

function fieldElementHex(value) {
  return normalizeBytes32Hex(ethers.toBeHex(value));
}

function deriveFieldMask({ sharedSecretPoint, chainId, channelId, owner, nonce, encryptionInfo }) {
  const affine = sharedSecretPoint.toAffine();
  return ethers.toBigInt(
    poseidonHexFromBytes(
      abiCoder.encode(
        ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12"],
        [
          encryptionInfo,
          ethers.toBigInt(chainId),
          ethers.toBigInt(channelId),
          ethers.getAddress(owner),
          affine.x,
          affine.y,
          ethers.zeroPadValue(nonce, 12),
        ],
      ),
    ),
  );
}

function deriveCipherTag({ sharedSecretPoint, chainId, channelId, owner, nonce, ciphertextValue, encryptionInfo }) {
  const affine = sharedSecretPoint.toAffine();
  return ethers.dataSlice(
    poseidonHexFromBytes(
      abiCoder.encode(
        ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12", "bytes32"],
        [
          `${encryptionInfo}:tag`,
          ethers.toBigInt(chainId),
          ethers.toBigInt(channelId),
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

export async function deriveNoteReceiveKeyMaterial({ signer, chainId, channelId, channelName, account }) {
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

function encryptFieldNoteValue({
  value,
  recipientPoint,
  chainId,
  channelId,
  owner,
  nonce,
  encryptionInfo,
  scheme,
}) {
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
    encryptionInfo,
  });
  const ciphertextValue = (plaintextValue + fieldMask) % BLS12_381_SCALAR_FIELD_MODULUS;
  const tag = deriveCipherTag({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce: cipherNonce,
    ciphertextValue,
    encryptionInfo,
  });
  const parsedEphemeralPubKey = noteReceivePubKeyFromPoint(ephemeralPoint);

  return packEncryptedNoteValue({
    ephemeralPubKeyX: parsedEphemeralPubKey.x,
    ephemeralPubKeyYParity: parsedEphemeralPubKey.yParity,
    nonce: cipherNonce,
    ciphertextValue: fieldElementHex(ciphertextValue),
    tag,
    scheme,
  });
}

export function encryptNoteValueForRecipient({
  value,
  recipientNoteReceivePubKey,
  chainId,
  channelId,
  owner,
  nonce = null,
}) {
  return encryptFieldNoteValue({
    value,
    recipientPoint: pointFromNoteReceivePubKey(recipientNoteReceivePubKey),
    chainId,
    channelId,
    owner,
    nonce,
    encryptionInfo: TRANSFER_NOTE_FIELD_ENCRYPTION_INFO,
    scheme: ENCRYPTED_NOTE_SCHEME_TRANSFER,
  });
}

export function encryptMintNoteValueForOwner({
  value,
  ownerNoteReceivePubKey,
  chainId,
  channelId,
  owner,
  nonce = null,
}) {
  return encryptFieldNoteValue({
    value,
    recipientPoint: pointFromNoteReceivePubKey(ownerNoteReceivePubKey),
    chainId,
    channelId,
    owner,
    nonce,
    encryptionInfo: MINT_NOTE_FIELD_ENCRYPTION_INFO,
    scheme: ENCRYPTED_NOTE_SCHEME_SELF_MINT,
  });
}

function decryptFieldEncryptedNoteValue({
  encryptedValue,
  privateKey,
  chainId,
  channelId,
  owner,
  encryptionInfo,
  expectedScheme,
}) {
  const normalized = unpackEncryptedNoteValue(encryptedValue);
  expect(
    normalized.scheme === expectedScheme,
    `Encrypted note value scheme mismatch. Expected ${expectedScheme}, received ${normalized.scheme}.`,
  );
  const sharedSecretPoint = pointFromNoteReceivePubKey({
    x: normalized.ephemeralPubKeyX,
    yParity: normalized.ephemeralPubKeyYParity,
  }).multiply(parseJubjubPrivateScalar(privateKey));
  const expectedTag = deriveCipherTag({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce: normalized.nonce,
    ciphertextValue: ethers.toBigInt(normalized.ciphertextValue),
    encryptionInfo,
  });
  expect(
    normalizeBytes16Hex(expectedTag) === normalizeBytes16Hex(normalized.tag),
    "Encrypted note value integrity tag mismatch.",
  );
  const fieldMask = deriveFieldMask({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce: normalized.nonce,
    encryptionInfo,
  });
  const plaintext = (
    ethers.toBigInt(normalized.ciphertextValue)
    - fieldMask
    + BLS12_381_SCALAR_FIELD_MODULUS
  ) % BLS12_381_SCALAR_FIELD_MODULUS;
  return decodeNoteValuePlaintext(plaintext);
}

export function decryptEncryptedNoteValue({ encryptedValue, noteReceivePrivateKey, chainId, channelId, owner }) {
  return decryptFieldEncryptedNoteValue({
    encryptedValue,
    privateKey: noteReceivePrivateKey,
    chainId,
    channelId,
    owner,
    encryptionInfo: TRANSFER_NOTE_FIELD_ENCRYPTION_INFO,
    expectedScheme: ENCRYPTED_NOTE_SCHEME_TRANSFER,
  });
}

export function decryptMintEncryptedNoteValue({ encryptedValue, noteReceivePrivateKey, chainId, channelId, owner }) {
  return decryptFieldEncryptedNoteValue({
    encryptedValue,
    privateKey: noteReceivePrivateKey,
    chainId,
    channelId,
    owner,
    encryptionInfo: MINT_NOTE_FIELD_ENCRYPTION_INFO,
    expectedScheme: ENCRYPTED_NOTE_SCHEME_SELF_MINT,
  });
}
