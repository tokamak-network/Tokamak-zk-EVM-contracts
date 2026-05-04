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

export const L2_WALLET_SECRET_SIGNING_DOMAIN = "Tokamak private-state L2 wallet secret binding";
export const CHANNEL_BOUND_L2_DERIVATION_MODE = "channel-name-plus-wallet-secret-v1";

export function slugifyPathComponent(value) {
  return String(value)
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}

export function deriveChannelIdFromName(channelName) {
  return ethers.toBigInt(keccak256(ethers.toUtf8Bytes(channelName)));
}

export function buildL2WalletSecretSigningMessage({ channelName, walletSecret }) {
  if (typeof channelName !== "string" || channelName.length === 0) {
    throw new Error("Missing channel name for L2 identity derivation.");
  }
  return [
    L2_WALLET_SECRET_SIGNING_DOMAIN,
    `channel:${channelName}`,
    `walletSecret:${String(walletSecret)}`,
  ].join("\n");
}

export async function deriveParticipantIdentityFromSigner({ channelName, walletSecret, signer }) {
  const seedSignature = await signer.signMessage(buildL2WalletSecretSigningMessage({ channelName, walletSecret }));
  const keySet = deriveL2KeysFromSignature(seedSignature);
  const l2Address = getAddress(fromEdwardsToAddress(keySet.publicKey).toString());
  return {
    seedSignature,
    l2PrivateKey: keySet.privateKey,
    l2PublicKey: keySet.publicKey,
    l2Address,
  };
}

export function walletNameForChannelAndAddress(channelName, l1Address) {
  return `${channelName}-${getAddress(l1Address)}`;
}

export function parseWalletName(walletName) {
  const match = /^(.*)-(0x[a-fA-F0-9]{40})$/.exec(String(walletName));
  if (!match || match[1].length === 0) {
    throw new Error(
      [
        `Unable to derive the channel name from wallet ${walletName}.`,
        "Expected the deterministic <channelName>-<l1Address> format.",
      ].join(" "),
    );
  }
  return {
    channelName: match[1],
    l1Address: getAddress(match[2]),
  };
}

export function workspaceNetworkDir(workspaceRoot, networkName) {
  return path.join(workspaceRoot, slugifyPathComponent(networkName));
}

export function workspaceDirForName(workspaceRoot, networkName, workspaceName) {
  return path.join(
    workspaceNetworkDir(workspaceRoot, networkName),
    slugifyPathComponent(workspaceName),
  );
}

export function workspaceChannelDir(workspaceDir) {
  return path.join(workspaceDir, "channel");
}

export function workspaceWalletsDir(workspaceDir) {
  return path.join(workspaceDir, "wallets");
}

export function walletDirForName(walletsRoot, walletName) {
  return path.join(walletsRoot, slugifyPathComponent(walletName));
}

export function walletMetadataPathForDir(walletDir) {
  return path.join(walletDir, "wallet.metadata.json");
}
