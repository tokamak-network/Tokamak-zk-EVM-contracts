import path from "node:path";
import {
  ethers,
  getAddress,
  keccak256,
} from "ethers";
import {
  deriveL2KeysFromSignature,
  fromEdwardsToAddress,
} from "tokamak-l2js";

export const L2_PASSWORD_SIGNING_DOMAIN = "Tokamak private-state L2 password binding";
export const CHANNEL_BOUND_L2_DERIVATION_MODE = "channel-name-plus-password-v1";

export function slugifyPathComponent(value) {
  return String(value)
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}

export function deriveChannelIdFromName(channelName) {
  return BigInt(keccak256(ethers.toUtf8Bytes(channelName)));
}

export function buildL2PasswordSigningMessage({ channelName, password }) {
  if (typeof channelName !== "string" || channelName.length === 0) {
    throw new Error("Missing channel name for L2 identity derivation.");
  }
  return [
    L2_PASSWORD_SIGNING_DOMAIN,
    `channel:${channelName}`,
    `password:${String(password)}`,
  ].join("\n");
}

export async function deriveParticipantIdentityFromSigner({ channelName, password, signer }) {
  const seedSignature = await signer.signMessage(buildL2PasswordSigningMessage({ channelName, password }));
  const keySet = deriveL2KeysFromSignature(seedSignature);
  const l2Address = getAddress(fromEdwardsToAddress(keySet.publicKey).toString());
  return {
    seedSignature,
    l2PrivateKey: keySet.privateKey,
    l2PublicKey: keySet.publicKey,
    l2Address,
  };
}

export function walletNameForChannelAndAddress(channelName, l2Address) {
  return `${channelName}-${getAddress(l2Address)}`;
}

export function walletDirForName(walletsRoot, walletName) {
  return path.join(walletsRoot, slugifyPathComponent(walletName));
}

export function walletMetadataPathForDir(walletDir) {
  return path.join(walletDir, "wallet.metadata.json");
}

export function walletInboxPathForDir(walletDir) {
  return path.join(walletDir, "incoming-notes.json");
}
