#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import readline from "node:readline/promises";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import AdmZip from "adm-zip";
import {
  createHash,
  createCipheriv,
  randomBytes,
  scryptSync,
} from "node:crypto";
import {
  AbiCoder,
  Contract,
  Interface,
  JsonRpcProvider,
  Wallet,
  ethers,
  getAddress,
  keccak256,
} from "ethers";
import {
  TokamakL2StateManager,
  createTokamakL2Common,
  fromEdwardsToAddress,
  poseidon,
  readStorageValueFromStateSnapshot,
} from "tokamak-l2js";
import {
  addHexPrefix,
  bytesToHex,
  createAddressFromString,
  hexToBigInt,
  hexToBytes,
} from "@ethereumjs/util";
import { resolveCliNetwork } from "@tokamak-private-dapps/common-library/network-config";
import {
  requireCanonicalCompatibleBackendVersion,
  requireExactSemverVersion,
} from "@tokamak-private-dapps/common-library/proof-backend-versioning";
import {
  bigintToHex32,
  buildStateManager,
  buildTokamakTxSnapshot,
  currentStorageBigInt,
  deriveChannelTokenVaultLeafIndex,
  deriveLiquidBalanceStorageKey,
  fetchContractCodes,
  getBlockInfoAt,
  normalizeBytesHex,
  normalizeBytes32Hex,
  serializeBigInts,
} from "@tokamak-private-dapps/common-library/tokamak-l2-helpers";
import {
  resolveTokamakBlockInputConfig,
} from "@tokamak-private-dapps/common-library/tokamak-runtime-paths";
import { toGroth16SolidityProof } from "@tokamak-private-dapps/common-library/groth16-solidity-proof";
import {
  requireCanonicalGroth16CompatibleBackendVersion,
} from "@tokamak-private-dapps/groth16/public-drive-crs";
import {
  CHANNEL_BOUND_L2_DERIVATION_MODE,
  deriveChannelIdFromName,
  deriveParticipantIdentityFromSigner,
  parseWalletName,
  slugifyPathComponent,
  workspaceChannelDir,
  workspaceDirForName,
  workspaceNetworkDir,
  workspaceWalletsDir,
  walletDirForName,
  walletNameForChannelAndAddress,
} from "./private-state-cli-shared.mjs";
import {
  buildDoctorReport,
  installGroth16RuntimeForPrivateState,
  installPrivateStateCliArtifacts,
  installTokamakCliRuntimeForPrivateState,
  inspectGroth16Runtime,
  normalizeInstallMode,
  parseJsonReport,
  printDoctorHumanReport,
  privateStateCliArtifactRequiredFiles,
  privateStateCliArtifactPaths,
  PRIVATE_STATE_INSTALL_MODES,
  readTokamakCliPackageReport,
  requireActiveTokamakCliRuntimeRoot,
  resolveActiveGroth16ProverRuntime,
  resolveActiveTokamakCliInvocation,
  resolveArtifactCacheBaseRoot,
  resolvePrivateStateInstallRuntimeVersions,
  resolveTokamakCliResourceDirForRuntimeRoot,
  stripAnsi,
  writePrivateStateCliInstallManifest,
} from "./private-state-runtime-management.mjs";
import {
  PRIVATE_STATE_CLI_COMMANDS,
  PRIVATE_STATE_CLI_FIELD_CATALOG,
  privateStateCliCommandDisplay,
  privateStateCliCommandInstallMode,
  privateStateCliCommandOptionKeys,
  privateStateCliCommandRequiredOptionKeys,
  privateStateCliCommandSynopsis,
} from "./private-state-cli-command-registry.mjs";
import {
  BLS12_381_SCALAR_FIELD_MODULUS,
  ENCRYPTED_NOTE_SCHEME_SELF_MINT,
  ENCRYPTED_NOTE_SCHEME_TRANSFER,
  NOTE_RECEIVE_KEY_DERIVATION_VERSION,
  NOTE_RECEIVE_TYPED_DATA_METHOD,
  computeEncryptedNoteSalt,
  computeNoteCommitment,
  computeNullifier,
  decryptEncryptedNoteValue,
  decryptMintEncryptedNoteValue,
  deriveNoteReceiveKeyMaterial,
  encryptMintNoteValueForOwner,
  encryptNoteValueForRecipient,
  normalizeEncryptedNoteValueWords,
  unpackEncryptedNoteValue,
} from "./private-state-note-delivery.mjs";
const require = createRequire(import.meta.url);
const defaultCommandCwd = process.cwd();
const privateStateCliPackageJson = require("../package.json");
const privateStateCliPackageRoot = path.dirname(require.resolve("../package.json"));
const workspaceRoot = path.resolve(os.homedir(), "tokamak-private-channels", "workspace");
const secretRoot = path.resolve(os.homedir(), "tokamak-private-channels", "secrets");
const flatDeploymentArtifactPathsByChainId = new Map();
const PRIVATE_STATE_UNINSTALL_CONFIRMATION =
  "I understand that the wallet secrets deleted due to this decision cannot be recovered";
const ACTION_IMPACT_CONFIRMATION =
  "I understand the public and private impact of this action";
const PRIVATE_STATE_CLI_PACKAGE_NAME = privateStateCliPackageJson.name;
const PRIVATE_STATE_OBSERVER_URL = "https://observer.tonnel.io";
const GROTH16_PACKAGE_NAME = "@tokamak-private-dapps/groth16";
const TOKAMAK_ZKEVM_CLI_PACKAGE_NAME = "@tokamak-zk-evm/cli";
const WALLET_BACKUP_EXPORT_FORMAT = "tokamak-private-state-wallet-backup-export";
const WALLET_KEY_EXPORT_FORMAT = "tokamak-private-state-wallet-key-export";
const WALLET_INDEX_FORMAT = "tokamak-private-state-wallet-index";
const WALLET_EVIDENCE_BUNDLE_FORMAT = "tokamak-private-state-raw-evidence-bundle";
const WALLET_EXPORT_FORMAT_VERSION = 2;
const WALLET_INDEX_FORMAT_VERSION = 1;
const WALLET_EVIDENCE_BUNDLE_FORMAT_VERSION = 2;
const WALLET_WORKSPACE_FORMAT_VERSION = 2;
const CHANNEL_WORKSPACE_MIRROR_PROTOCOL_VERSION = 2;
const CHANNEL_WORKSPACE_MIRROR_MANIFEST_PATH_PREFIX =
  ".well-known/tokamak-private-state/channel-workspace";
const CHANNEL_WORKSPACE_MIRROR_ARCHIVE_FILES = Object.freeze(new Set([
  "workspace.json",
  "state_snapshot.json",
  "block_info.json",
  "contract_codes.json",
]));
let jsonOutputRequested = false;

const CLI_ERROR_CODES = Object.freeze({
  MISSING_RPC_URL: "MISSING_RPC_URL",
  UNKNOWN_WALLET: "UNKNOWN_WALLET",
  MISSING_DEPLOYMENT_ARTIFACTS: "MISSING_DEPLOYMENT_ARTIFACTS",
  MISSING_CHANNEL_REGISTRATION: "MISSING_CHANNEL_REGISTRATION",
  STALE_WORKSPACE: "STALE_WORKSPACE",
});

class PrivateStateCliError extends Error {
  constructor(code, message, options = {}) {
    super(message, options);
    this.name = "PrivateStateCliError";
    this.code = code;
  }
}

function cliError(code, message, options = {}) {
  return new PrivateStateCliError(code, message, options);
}

const abiCoder = AbiCoder.defaultAbiCoder();
const erc20MetadataAbi = [
  "function decimals() view returns (uint8)",
];
const channelVerifierVersionAbi = [
  "function grothVerifierCompatibleBackendVersion() view returns (string)",
  "function tokamakVerifierCompatibleBackendVersion() view returns (string)",
];
const {
  aPubBlockLength: TOKAMAK_APUB_BLOCK_LENGTH,
  previousBlockHashCount: TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT,
} = resolveTokamakBlockInputConfig();
const WALLET_ENCRYPTION_VERSION = 1;
const WALLET_ENCRYPTION_ALGORITHM = "aes-256-gcm";
const PRIVATE_STATE_DAPP_LABEL = "private-state";
const JOIN_TOLL_REFUND_BPS_DENOMINATOR = 10_000n;
const NOTE_RECEIVE_EVENT_ABI = [
  "event NoteValueEncrypted(bytes32[3] encryptedNoteValue)",
];
const noteValueEncryptedEventInterface = new Interface(NOTE_RECEIVE_EVENT_ABI);
const NOTE_VALUE_ENCRYPTED_TOPIC = noteValueEncryptedEventInterface.getEvent("NoteValueEncrypted").topicHash;
const CONTROLLER_STORAGE_KEY_OBSERVED_EVENT_ABI = [
  "event StorageKeyObserved(bytes32 storageKey)",
];
const controllerStorageKeyObservedEventInterface = new Interface(CONTROLLER_STORAGE_KEY_OBSERVED_EVENT_ABI);
const CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC =
  controllerStorageKeyObservedEventInterface.getEvent("StorageKeyObserved").topicHash;
const VAULT_STORAGE_WRITE_OBSERVED_EVENT_ABI = [
  "event LiquidBalanceStorageWriteObserved(address l2Address, bytes32 value)",
];
const vaultStorageWriteObservedEventInterface = new Interface(VAULT_STORAGE_WRITE_OBSERVED_EVENT_ABI);
const VAULT_STORAGE_WRITE_OBSERVED_TOPIC =
  vaultStorageWriteObservedEventInterface.getEvent("LiquidBalanceStorageWriteObserved").topicHash;
const ZERO_TOPIC = normalizeBytes32Hex(ethers.ZeroHash);
const AUTO_RECOVERY_BLOCK_BUDGET = 7200;
const RPC_PROVIDER_LOG_LIMITS = Object.freeze({
  ankr: {
    provider: "ankr",
    logRequestsPerSecond: 27,
    blockRangeCap: 3000,
  },
  chainstack: {
    provider: "chainstack",
    logRequestsPerSecond: 22.5,
    blockRangeCap: 100,
  },
  chainnodes: {
    provider: "chainnodes",
    logRequestsPerSecond: 22.5,
    blockRangeCap: 20000,
  },
  quicknode: {
    provider: "quicknode",
    logRequestsPerSecond: 13.5,
    blockRangeCap: 5,
  },
  alchemy: {
    provider: "alchemy",
    logRequestsPerSecond: 7.497,
    blockRangeCap: 10,
  },
});
const RPC_PROVIDER_ALIASES = Object.freeze({
  ankr: "ankr",
  chainstack: "chainstack",
  chainnodes: "chainnodes",
  quicknode: "quicknode",
  quicknodes: "quicknode",
  alchemy: "alchemy",
});
let lastLogRequestStartedAtMs = 0;
let logRequestQueue = Promise.resolve();
let activeRpcLogConfig = null;

function printImmutableChannelPolicyWarning({
  action,
  channelName,
  channelId,
  channelManager = null,
  policySnapshot = null,
}) {
  const details = [
    `WARNING: ${action} commits to an immutable channel policy.`,
    `Channel: ${channelName} (${channelId.toString()})`,
  ];
  if (channelManager) {
    details.push(`ChannelManager: ${channelManager}`);
  }
  details.push(
    "The channel verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund policy are fixed for this channel.",
    "Those policy fields are intentionally not upgraded in place without channel-user consent.",
    "If a policy bug is discovered later, the expected mitigation is creating or joining a new channel, not mutating this channel.",
    "Review the DApp digest, digest schema, verifier addresses, and compatible backend versions before signing.",
  );
  if (policySnapshot) {
    details.push(
      "Channel policy snapshot:",
      `  DApp id: ${policySnapshot.dappId}`,
      `  DApp metadata digest schema: ${policySnapshot.dappMetadataDigestSchema}`,
      `  DApp metadata digest: ${policySnapshot.dappMetadataDigest}`,
      `  DApp function root: ${policySnapshot.functionRoot}`,
      `  Groth16 verifier: ${policySnapshot.grothVerifier}`,
      `  Groth16 compatible backend version: ${policySnapshot.grothVerifierCompatibleBackendVersion}`,
      `  Tokamak verifier: ${policySnapshot.tokamakVerifier}`,
      `  Tokamak compatible backend version: ${policySnapshot.tokamakVerifierCompatibleBackendVersion}`,
      "Do not sign if any snapshot value is unexpected or has not been reviewed.",
    );
  }
  console.error(details.join("\n"));
}

const ACTION_IMPACT_SUMMARIES = Object.freeze({
  "account-deposit-bridge": {
    display: "account deposit-bridge",
    l1PublicEvent: "Yes. ERC-20 approval and bridge vault funding transactions are public L1 events.",
    privateNoteState: "No. This action only moves canonical tokens into the shared bridge vault.",
    publicFields: ({ l1Address, amountInput, bridgeTokenVault }) => [
      `L1 account: ${l1Address}`,
      `Bridge token vault: ${bridgeTokenVault}`,
      `Amount: ${amountInput}`,
      "Approval and funding transaction hashes, block numbers, and event logs.",
    ],
    notPublic: [
      "No private note owner, value, salt, counterparty, or note provenance is created by this action.",
    ],
    noteProvenance: "Not applicable for this bridge-edge action.",
    exchangeControlledAddressWarning: "Do not use an exchange-controlled address as a self-custody bridge source.",
    policy: "No channel policy is accepted by this action.",
  },
  "account-withdraw-bridge": {
    display: "account withdraw-bridge",
    l1PublicEvent: "Yes. The bridge withdrawal transaction and claim event are public L1 data.",
    privateNoteState: "No. This action claims shared bridge-vault balance to the local L1 account.",
    publicFields: ({ l1Address, amountInput, bridgeTokenVault }) => [
      `L1 recipient/account: ${l1Address}`,
      `Bridge token vault: ${bridgeTokenVault}`,
      `Amount: ${amountInput}`,
      "Withdrawal transaction hash, block number, and event log.",
    ],
    notPublic: [
      "The private note path that produced any prior channel balance is not reconstructed from this event alone.",
    ],
    noteProvenance: "Public observers cannot reconstruct prior internal note provenance from this withdrawal alone.",
    exchangeControlledAddressWarning: "Do not use an exchange deposit address as the direct bridge withdrawal target unless the user has explicitly accepted the compliance implications. Prefer a self-custody L1 wallet.",
    policy: "No channel policy is accepted by this action.",
  },
  "channel-join": {
    display: "channel join",
    l1PublicEvent: "Yes. Channel join and token-vault registration transactions are public L1 data; any join toll is paid directly from the L1 wallet.",
    privateNoteState: "No. This action registers identity and note-receive metadata; it does not create or spend notes.",
    publicFields: ({ l1Address, l2Address, noteReceivePubKey, joinToll, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `L1 account: ${l1Address}`,
      `L2 address: ${l2Address}`,
      `Note-receive public key: ${noteReceivePubKey}`,
      `Join toll: ${joinToll}`,
    ],
    notPublic: [
      "Wallet secret, L2 spending private key, note-receive private key, and future note plaintext.",
    ],
    noteProvenance: "Future note provenance is not made public by joining.",
    policy: "Joining accepts the displayed immutable channel policy snapshot.",
  },
  "wallet-deposit-channel": {
    display: "wallet deposit-channel",
    l1PublicEvent: "Yes. The proof-backed channel accounting transaction is public L1 data.",
    privateNoteState: "No. This action increases liquid channel accounting balance; it does not create notes.",
    publicFields: ({ l1Address, l2Address, amountInput, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `L1 submitter/account: ${l1Address}`,
      `Registered L2 address: ${l2Address}`,
      `Amount: ${amountInput}`,
      "Transaction hash, accepted proof surface, and accounting root update.",
    ],
    notPublic: [
      "No note owner, value, salt, counterparty, or note provenance is created by this action.",
    ],
    noteProvenance: "Not applicable; this action does not transfer note ownership.",
    policy: "This action uses the channel policy snapshot accepted by the registered wallet.",
  },
  "wallet-withdraw-channel": {
    display: "wallet withdraw-channel",
    l1PublicEvent: "Yes. The proof-backed channel accounting transaction is public L1 data.",
    privateNoteState: "No. This action decreases liquid channel accounting balance; it does not spend notes directly.",
    publicFields: ({ l1Address, l2Address, amountInput, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `L1 submitter/account: ${l1Address}`,
      `Registered L2 address: ${l2Address}`,
      `Amount: ${amountInput}`,
      "Transaction hash, accepted proof surface, and accounting root update.",
    ],
    notPublic: [
      "Any prior private note path that produced the liquid balance is not reconstructed from this action alone.",
    ],
    noteProvenance: "Public observers cannot reconstruct prior internal note provenance from this withdrawal-channel action alone.",
    policy: "This action uses the channel policy snapshot accepted by the registered wallet.",
  },
  "wallet-mint-notes": {
    display: "wallet mint-notes",
    l1PublicEvent: "Yes. executeChannelTransaction, accepted transition, commitments, encrypted note events, and root updates are public L1 data.",
    privateNoteState: "Yes. This action creates private-state notes tracked by the local wallet.",
    publicFields: ({ l1Address, l2Address, amounts, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `L1 submitter/account: ${l1Address}`,
      `Registered L2 address: ${l2Address}`,
      `Requested note amounts: ${amounts}`,
      "New commitments, encrypted note-delivery events, transaction hash, and root updates.",
    ],
    notPublic: [
      "Note owner, value, salt, plaintext note contents, and later note provenance are not public by default.",
    ],
    noteProvenance: "Public observers cannot reconstruct later note provenance without user-controlled disclosure.",
    policy: "This action uses the channel policy snapshot accepted by the registered wallet.",
  },
  "wallet-transfer-notes": {
    display: "wallet transfer-notes",
    l1PublicEvent: "Yes. executeChannelTransaction, nullifiers, output commitments, encrypted note events, and root updates are public L1 data.",
    privateNoteState: "Yes. This action spends selected input notes and creates output notes.",
    publicFields: ({ l1Address, l2Address, noteIds, amounts, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `L1 submitter/account: ${l1Address}`,
      `Registered L2 address: ${l2Address}`,
      `Input note commitments: ${noteIds}`,
      `Output amounts supplied to the CLI: ${amounts}`,
      "Input nullifiers, output commitments, encrypted note-delivery events, transaction hash, and root updates.",
    ],
    notPublic: [
      "Sender-recipient relationship, recipient note plaintext, and note provenance are not public by default.",
    ],
    noteProvenance: "Public observers cannot reconstruct private note counterparty relationships or provenance from public contract state alone.",
    policy: "This action uses the channel policy snapshot accepted by the registered wallet.",
  },
  "wallet-redeem-notes": {
    display: "wallet redeem-notes",
    l1PublicEvent: "Yes. executeChannelTransaction, nullifier usage, accounting update, and root updates are public L1 data.",
    privateNoteState: "Yes. This action consumes selected notes and credits liquid channel accounting balance.",
    publicFields: ({ l1Address, l2Address, noteIds, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `L1 submitter/account: ${l1Address}`,
      `Registered L2 address: ${l2Address}`,
      `Input note commitments: ${noteIds}`,
      "Input nullifiers, accounting update, transaction hash, and root updates.",
    ],
    notPublic: [
      "The prior path by which the redeemed note was received is not public by default.",
    ],
    noteProvenance: "Public observers cannot reconstruct prior internal note provenance from this redeem action alone.",
    policy: "This action uses the channel policy snapshot accepted by the registered wallet.",
  },
});

async function requireActionImpactAcknowledgement(commandId, args, details = {}) {
  const summary = ACTION_IMPACT_SUMMARIES[commandId];
  if (!summary) {
    throw new Error(`Missing action-impact summary for ${commandId}.`);
  }
  printActionImpactSummary(summary, details);
  if (args.acknowledgeActionImpact === true) {
    return;
  }
  if (args.acknowledgeActionImpact !== undefined) {
    throw new Error(`${summary.display} option --acknowledge-action-impact does not accept a value.`);
  }
  if (!process.stdin.isTTY) {
    throw new Error(`${summary.display} requires --acknowledge-action-impact after reviewing the action-impact warning.`);
  }
  const prompt = [
    `Type exactly: ${ACTION_IMPACT_CONFIRMATION}`,
    "> ",
  ].join("\n");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stderr,
    terminal: process.stdin.isTTY && process.stderr.isTTY,
  });
  try {
    const answer = await rl.question(prompt);
    if (answer !== ACTION_IMPACT_CONFIRMATION) {
      throw new Error(`${summary.display} action-impact confirmation did not match. No transaction was submitted.`);
    }
  } finally {
    rl.close();
  }
}

function printActionImpactSummary(summary, details) {
  const lines = [
    `ACTION IMPACT SUMMARY: ${summary.display}`,
    `- L1 public event: ${summary.l1PublicEvent}`,
    `- Private note state change: ${summary.privateNoteState}`,
    "- Public addresses and amounts:",
    ...normalizeImpactLines(summary.publicFields, details).map((line) => `  - ${line}`),
    "- Not public by default:",
    ...normalizeImpactLines(summary.notPublic, details).map((line) => `  - ${line}`),
    `- Note provenance: ${summary.noteProvenance}`,
    `- Illegal-use prohibition: Do not use this command for money laundering, sanctions evasion, terrorist financing, illegal gambling, criminal-proceeds concealment, or regulatory evasion.`,
    `- Secret recovery: Losing wallet secrets, viewing keys, or spending keys can prevent note discovery or note use. The CLI cannot recover lost secrets.`,
    `- Channel policy: ${summary.policy}`,
  ];
  if (summary.exchangeControlledAddressWarning) {
    lines.push(`- Exchange-controlled address warning: ${summary.exchangeControlledAddressWarning}`);
  }
  lines.push(`- Confirmation: pass --acknowledge-action-impact or type the exact confirmation phrase when prompted.`);
  console.error(lines.join("\n"));
}

function normalizeImpactLines(value, details) {
  const resolved = typeof value === "function" ? value(details) : value;
  return Array.isArray(resolved) ? resolved : [resolved];
}

function normalizeDAppPolicySnapshot({
  dappId,
  metadataDigest,
  metadataDigestSchema,
  functionRoot,
  verifierSnapshot,
}) {
  return {
    dappId: Number(dappId),
    dappMetadataDigestSchema: normalizeBytes32Hex(metadataDigestSchema),
    dappMetadataDigest: normalizeBytes32Hex(metadataDigest),
    functionRoot: normalizeBytes32Hex(functionRoot),
    grothVerifier: getAddress(verifierSnapshot.grothVerifier),
    grothVerifierCompatibleBackendVersion: requireVersionString(
      verifierSnapshot.grothVerifierCompatibleBackendVersion,
      "registered DApp Groth16 verifier compatibleBackendVersion",
    ),
    tokamakVerifier: getAddress(verifierSnapshot.tokamakVerifier),
    tokamakVerifierCompatibleBackendVersion: requireVersionString(
      verifierSnapshot.tokamakVerifierCompatibleBackendVersion,
      "registered DApp Tokamak verifier compatibleBackendVersion",
    ),
  };
}

function prepareDeploymentArtifacts(chainId, { mode = PRIVATE_STATE_INSTALL_MODES.FULL } = {}) {
  const normalizedChainId = Number(chainId);
  const normalizedMode = normalizeInstallMode(mode);
  const existingEntry = flatDeploymentArtifactPathsByChainId.get(normalizedChainId);
  if (existingEntry?.preparedModes.has(normalizedMode)) {
    return existingEntry.paths.rootDir;
  }

  const cacheBaseRoot = resolveArtifactCacheBaseRoot();
  const artifactPaths = existingEntry?.paths ?? privateStateCliArtifactPaths(cacheBaseRoot, normalizedChainId);
  requireInstalledDeploymentArtifacts(artifactPaths, normalizedChainId, normalizedMode);
  const preparedModes = existingEntry?.preparedModes ?? new Set();
  preparedModes.add(normalizedMode);
  flatDeploymentArtifactPathsByChainId.set(normalizedChainId, {
    paths: artifactPaths,
    preparedModes,
  });
  return artifactPaths.rootDir;
}

function prepareDeploymentArtifactsForCommand(commandId, chainId) {
  const command = PRIVATE_STATE_CLI_COMMANDS.find((entry) => entry.id === commandId);
  expect(command, `Missing CLI command metadata for ${commandId}.`);
  const mode = privateStateCliCommandInstallMode(command);
  expect(mode !== "none", `${privateStateCliCommandDisplay(command)} does not require installed deployment artifacts.`);
  return prepareDeploymentArtifacts(chainId, { mode });
}

function flatDeploymentArtifactPathsForChainId(chainId) {
  return flatDeploymentArtifactPathsByChainId.get(Number(chainId))?.paths ?? null;
}

function requireFlatDeploymentArtifactPathsForChainId(chainId) {
  const paths = flatDeploymentArtifactPathsForChainId(chainId);
  if (!paths) {
    throw new Error(`Deployment artifacts for chain ${Number(chainId)} were not prepared.`);
  }
  return paths;
}

function requireInstalledDeploymentArtifacts(artifactPaths, chainId, mode) {
  const missingFiles = missingInstalledDeploymentArtifactFiles(artifactPaths, mode);
  if (missingFiles.length === 0) {
    return;
  }
  throw cliError(
    CLI_ERROR_CODES.MISSING_DEPLOYMENT_ARTIFACTS,
    [
      `Missing ${mode} installed deployment artifacts for chain ${chainId} under ${artifactPaths.rootDir}.`,
      mode === PRIVATE_STATE_INSTALL_MODES.FULL
        ? "Run install before running private-state CLI commands that write channel state."
        : "Run install --read-only before running private-state CLI commands that read channel state.",
      `Original error: ${missingFiles.map((entry) => `Missing ${entry.label}: ${entry.path}.`).join(" ")}`,
    ].join(" "),
  );
}

function missingInstalledDeploymentArtifactFiles(artifactPaths, mode) {
  return privateStateCliArtifactRequiredFiles(artifactPaths, mode)
    .filter((entry) => !fs.existsSync(entry.path));
}

async function handleChannelCreate({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const signer = requireL1Signer(args, provider);
  const leader = getAddress(signer.address);
  const workspaceName = channelName;

  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    signer,
  );
  const canonicalAsset = getAddress(await bridgeCore.canonicalAsset());
  const canonicalAssetDecimals = await fetchTokenDecimals(provider, canonicalAsset);
  const joinTollInput = requireArg(args.joinToll, "--join-toll");
  const joinToll = parseTokenAmount(joinTollInput, canonicalAssetDecimals);
  const channelId = deriveChannelIdFromName(channelName);
  const dapp = await resolveDAppIdByLabel({
    provider,
    bridgeResources,
    dappLabel: PRIVATE_STATE_DAPP_LABEL,
  });
  const dappId = dapp.dappId;
  const policySnapshot = dapp.policySnapshot;

  printImmutableChannelPolicyWarning({
    action: "channel create",
    channelName,
    channelId,
    policySnapshot,
  });
  const receipt =
    await waitForReceipt(await bridgeCore.createChannel(channelId, dappId, joinToll, dapp.metadataDigest));
  const channelInfo = await bridgeCore.getChannel(channelId);

  const workspaceResult = await syncChannelWorkspace({
    workspaceName,
    channelName,
    network,
    provider,
    bridgeResources,
    persist: true,
    fromGenesis: true,
    minimumToBlock: receipt.blockNumber,
    progressAction: "channel create",
  });

  printJson({
    action: "channel create",
    channelName,
    channelId: channelId.toString(),
    dappId,
    dappMetadataDigest: dapp.metadataDigest,
    dappMetadataDigestSchema: dapp.metadataDigestSchema,
    policySnapshot,
    leader,
    joinTollBaseUnits: joinToll.toString(),
    joinTollTokens: ethers.formatUnits(joinToll, canonicalAssetDecimals),
    canonicalAsset,
    canonicalAssetDecimals,
    asset: channelInfo.asset,
    manager: channelInfo.manager,
    bridgeTokenVault: channelInfo.bridgeTokenVault,
    gasUsed: receiptGasUsed(receipt),
    txUrl: explorerTxUrl(network, receipt.hash),
    receipt: sanitizeReceipt(receipt),
    workspace: workspaceResult?.workspaceDir ?? null,
  });
}

async function resolveDAppIdByLabel({ provider, bridgeResources, dappLabel }) {
  const dAppManager = new Contract(
    bridgeResources.bridgeDeployment.dAppManager,
    bridgeResources.bridgeAbiManifest.contracts.dAppManager.abi,
    provider,
  );
  const expectedLabelHash = normalizeBytes32Hex(keccak256(ethers.toUtf8Bytes(dappLabel)));
  const manifestPath = requireFlatDeploymentArtifactPathsForChainId(bridgeResources.chainId).dappRegistrationPath;
  const manifest = readJson(manifestPath);
  const manifestLabel = typeof manifest.dappLabel === "string" ? manifest.dappLabel : null;
  const manifestDappId = manifest.dappId;
  const manifestManager = typeof manifest.dAppManager === "string" ? getAddress(manifest.dAppManager) : null;
  const manifestMetadataDigest = normalizeBytes32Hex(manifest.registration?.metadataDigest);
  const manifestMetadataDigestSchema = normalizeBytes32Hex(manifest.registration?.metadataDigestSchema);
  const manifestFunctionRoot = normalizeBytes32Hex(manifest.registration?.functionRoot);

  expect(manifestLabel === dappLabel, `DApp registration manifest label mismatch in ${manifestPath}.`);
  expect(Number.isInteger(manifestDappId), `DApp registration manifest is missing an integer dappId: ${manifestPath}.`);
  expect(manifestMetadataDigest !== null, `DApp registration manifest is missing registration.metadataDigest: ${manifestPath}.`);
  expect(
    manifestMetadataDigestSchema !== null,
    `DApp registration manifest is missing registration.metadataDigestSchema: ${manifestPath}.`,
  );
  expect(
    manifestFunctionRoot !== null,
    `DApp registration manifest is missing registration.functionRoot: ${manifestPath}.`,
  );
  expect(
    manifestManager !== null
      && ethers.toBigInt(manifestManager) === ethers.toBigInt(getAddress(bridgeResources.bridgeDeployment.dAppManager)),
    `DApp registration manifest manager mismatch in ${manifestPath}.`,
  );

  const info = await dAppManager.getDAppInfo(manifestDappId);
  expect(info.exists, `DApp id ${manifestDappId} from ${manifestPath} is not registered on-chain.`);
  expect(
    ethers.toBigInt(normalizeBytes32Hex(info.labelHash)) === ethers.toBigInt(expectedLabelHash),
    `DApp id ${manifestDappId} from ${manifestPath} does not match label ${dappLabel} on-chain.`,
  );
  const onchainMetadataDigest = normalizeBytes32Hex(info.metadataDigest);
  const onchainMetadataDigestSchema = normalizeBytes32Hex(info.metadataDigestSchema);
  const onchainFunctionRoot = normalizeBytes32Hex(info.functionRoot);
  const verifierSnapshot = await dAppManager.getDAppVerifierSnapshot(manifestDappId);
  const policySnapshot = normalizeDAppPolicySnapshot({
    dappId: manifestDappId,
    metadataDigest: onchainMetadataDigest,
    metadataDigestSchema: onchainMetadataDigestSchema,
    functionRoot: onchainFunctionRoot,
    verifierSnapshot,
  });
  expect(
    ethers.toBigInt(onchainMetadataDigest) === ethers.toBigInt(manifestMetadataDigest),
    `DApp id ${manifestDappId} metadata digest ${onchainMetadataDigest} does not match ${manifestMetadataDigest} from ${manifestPath}.`,
  );
  expect(
    ethers.toBigInt(onchainMetadataDigestSchema) === ethers.toBigInt(manifestMetadataDigestSchema),
    `DApp id ${manifestDappId} metadata digest schema ${onchainMetadataDigestSchema} does not match ${manifestMetadataDigestSchema} from ${manifestPath}.`,
  );
  expect(
    ethers.toBigInt(onchainFunctionRoot) === ethers.toBigInt(manifestFunctionRoot),
    `DApp id ${manifestDappId} function root ${onchainFunctionRoot} does not match ${manifestFunctionRoot} from ${manifestPath}.`,
  );
  return {
    dappId: Number(manifestDappId),
    metadataDigest: onchainMetadataDigest,
    metadataDigestSchema: onchainMetadataDigestSchema,
    functionRoot: onchainFunctionRoot,
    policySnapshot,
  };
}

async function handleWorkspaceInit({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const workspaceName = channelName;
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const recoverySource = resolveWorkspaceRecoverySource(args);
  const outputRawRpcCallHistory = args.outputRaw === true;

  const {
    workspaceDir,
    workspace,
    currentSnapshot,
    blockInfo,
    contractCodes,
    cleanRebuildBackup,
    rpcCallHistory,
  } = await syncChannelWorkspace({
    workspaceName,
    channelName,
    network,
    provider,
    bridgeResources,
    persist: true,
    allowExistingWorkspaceSync: true,
    useWorkspaceRecoveryIndex: true,
    fromGenesis: args.fromGenesis === true,
    recoverySource,
    outputRawRpcCallHistory,
    progressAction: "channel recover-workspace",
  });

  const publishedWorkspaceMirror = args.publishWorkspaceMirror === true
    ? await publishChannelWorkspaceMirrorFromRecoveredWorkspace({
      args,
      network,
      provider,
      bridgeResources,
      channelName,
      local: {
        workspace,
        stateSnapshot: currentSnapshot,
        blockInfo,
        contractCodes,
        recoveryLastScannedBlock: workspace.recoveryLastScannedBlock,
        recoveryRootVectorHash: workspace.recoveryRootVectorHash,
      },
    })
    : null;

  printJson({
    action: "channel recover-workspace",
    source: workspace.recoverySource ?? recoverySource,
    workspace: workspaceName,
    workspaceDir,
    cleanRebuildBackup: cleanRebuildBackup ?? null,
    channelName,
    channelId: workspace.channelId,
    channelManager: workspace.channelManager,
    bridgeTokenVault: workspace.bridgeTokenVault,
    controller: workspace.controller,
    l2AccountingVault: workspace.l2AccountingVault,
    currentRoots: currentSnapshot.stateRoots,
    recoveryLastScannedBlock: workspace.recoveryLastScannedBlock,
    recoveryRootVectorHash: workspace.recoveryRootVectorHash,
    recoveryScanRange: workspace.recoveryScanRange,
    rpcCallHistory,
    workspaceMirror: workspace.workspaceMirror ?? null,
    publishedWorkspaceMirror,
  });
}

async function handleGetChannel({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    provider,
  );
  const channelId = deriveChannelIdFromName(channelName);

  let channelInfo;
  try {
    channelInfo = await bridgeCore.getChannel(channelId);
  } catch (error) {
    if (isContractError(error, bridgeCore.interface, "UnknownChannel")) {
      printJson({
        action: "channel get-meta",
        channelName,
        channelId: channelId.toString(),
        exists: false,
        bridgeCore: getAddress(bridgeResources.bridgeDeployment.bridgeCore),
      });
      return;
    }
    throw error;
  }

  const channelManager = new Contract(
    channelInfo.manager,
    bridgeResources.bridgeAbiManifest.contracts.channelManager.abi,
    provider,
  );
  const asset = getAddress(channelInfo.asset);
  const [
    canonicalAssetDecimals,
    joinToll,
    currentRootVectorHash,
    genesisBlockNumber,
    managedStorageAddresses,
    policySnapshot,
    refundSchedule,
  ] = await Promise.all([
    fetchTokenDecimals(provider, asset),
    channelManager.joinToll(),
    channelManager.currentRootVectorHash(),
    channelManager.genesisBlockNumber(),
    channelManager.getManagedStorageAddresses(),
    readChannelPolicySnapshot({
      channelManager,
      dappId: Number(channelInfo.dappId),
    }),
    readChannelRefundSchedule(channelManager),
  ]);

  printJson({
    action: "channel get-meta",
    channelName,
    channelId: channelId.toString(),
    exists: true,
    dappId: Number(channelInfo.dappId),
    leader: getAddress(channelInfo.leader),
    asset,
    manager: getAddress(channelInfo.manager),
    bridgeTokenVault: getAddress(channelInfo.bridgeTokenVault),
    aPubBlockHash: normalizeBytes32Hex(channelInfo.aPubBlockHash),
    dappMetadataDigestSchema: normalizeBytes32Hex(channelInfo.dappMetadataDigestSchema),
    dappMetadataDigest: normalizeBytes32Hex(channelInfo.dappMetadataDigest),
    joinTollBaseUnits: joinToll.toString(),
    joinTollTokens: ethers.formatUnits(joinToll, canonicalAssetDecimals),
    currentRootVectorHash: normalizeBytes32Hex(currentRootVectorHash),
    genesisBlockNumber: Number(genesisBlockNumber),
    managedStorageAddresses: normalizedAddressVector(managedStorageAddresses),
    policySnapshot,
    refundSchedule,
    bridgeCore: getAddress(bridgeResources.bridgeDeployment.bridgeCore),
    workspaceMirror: await readChannelWorkspaceMirror({ bridgeCore, channelId }),
  });
}

async function handleSetChannelWorkspaceMirror({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const url = requireWorkspaceMirrorUrl(args.url);
  const signer = requireL1Signer(args, provider);
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    signer,
  );
  const channelId = deriveChannelIdFromName(channelName);
  const previousUrl = await readChannelWorkspaceMirror({ bridgeCore, channelId });
  const receipt = await waitForReceipt(await bridgeCore.setChannelWorkspaceMirror(channelId, url));
  const currentUrl = await readChannelWorkspaceMirror({ bridgeCore, channelId });

  printJson({
    action: "channel set-workspace-mirror",
    channelName,
    channelId: channelId.toString(),
    leader: getAddress(signer.address),
    previousUrl,
    url: currentUrl,
    bridgeCore: getAddress(bridgeResources.bridgeDeployment.bridgeCore),
    gasUsed: receiptGasUsed(receipt),
    txUrl: explorerTxUrl(network, receipt.hash),
    receipt: sanitizeReceipt(receipt),
  });
}

async function publishChannelWorkspaceMirrorFromRecoveredWorkspace({
  args,
  network,
  provider,
  bridgeResources,
  channelName,
  local,
}) {
  const outputRoot = path.resolve(String(requireArg(args.output, "--output")));
  const force = args.force === true;
  const { signer, account: leaderAccount } = requireLeaderSigner(args, provider);
  const { bridgeDeployment, bridgeAbiManifest } = bridgeResources;
  const bridgeCore = new Contract(
    bridgeDeployment.bridgeCore,
    bridgeAbiManifest.contracts.bridgeCore.abi,
    signer,
  );
  const channelId = deriveChannelIdFromName(channelName);
  const channelInfo = await bridgeCore.getChannel(channelId);
  expect(channelInfo.exists, `Unknown channel ${channelId.toString()} in bridge core ${bridgeDeployment.bridgeCore}.`);
  expect(
    ethers.toBigInt(getAddress(signer.address)) === ethers.toBigInt(getAddress(channelInfo.leader)),
    "Only the channel leader can publish a signed workspace mirror checkpoint.",
  );

  const registeredUrl = String(await readChannelWorkspaceMirror({ bridgeCore, channelId })).trim();
  expect(
    registeredUrl.length > 0,
    `No workspace mirror URL is registered for channel ${channelName}. Run channel set-workspace-mirror first.`,
  );
  const manifestUrl = channelWorkspaceMirrorManifestUrl({
    registeredUrl,
    chainId: network.chainId,
    channelId,
  });

  const remote = await readRemoteWorkspaceMirrorCheckpoint({
    manifestUrl,
    chainId: network.chainId,
    channelId,
    channelName,
    bridgeCoreAddress: bridgeDeployment.bridgeCore,
    channelInfo,
    blockInfo: local.blockInfo,
    contractCodes: local.contractCodes,
    force,
  });
  expect(
    !remote.exists || Number(local.recoveryLastScannedBlock) > Number(remote.recoveryLastScannedBlock),
    [
      `Recovered workspace index ${local.recoveryLastScannedBlock} is not ahead of the registered mirror`,
      `checkpoint ${remote.exists ? remote.recoveryLastScannedBlock : "<missing>"}.`,
      "No newer workspace mirror checkpoint can be published.",
    ].join(" "),
  );

  const publishTarget = workspaceMirrorPublishTarget({
    outputRoot,
    registeredUrl,
    chainId: network.chainId,
    channelId,
  });
  const mirrorDir = publishTarget.mirrorDir;
  ensureDir(mirrorDir);

  const checkpointBundle = buildWorkspaceMirrorCheckpointBundle({
    workspace: local.workspace,
    stateSnapshot: local.stateSnapshot,
    blockInfo: local.blockInfo,
    contractCodes: local.contractCodes,
  });
  const checkpointBundlePath = path.join(mirrorDir, "checkpoint.zip");
  fs.writeFileSync(checkpointBundlePath, checkpointBundle.bytes);

  const deltaBundles = [];
  if (remote.exists) {
    const delta = await buildWorkspaceMirrorDeltaBundle({
      provider,
      bridgeAbiManifest,
      channelInfo,
      chainId: network.chainId,
      channelId,
      fromBlock: Number(remote.recoveryLastScannedBlock),
      toBlock: Number(local.recoveryLastScannedBlock) - 1,
      baseRecoveryRootVectorHash: remote.recoveryRootVectorHash,
      recoveryRootVectorHash: local.recoveryRootVectorHash,
    });
    const deltaRelativePath = `deltas/${delta.fromBlock}-${delta.toBlock}.json`;
    const deltaBytes = Buffer.from(`${JSON.stringify(normalizeCliOutput(delta), null, 2)}\n`, "utf8");
    const deltaPath = path.join(mirrorDir, deltaRelativePath);
    ensureDir(path.dirname(deltaPath));
    fs.writeFileSync(deltaPath, deltaBytes);
    deltaBundles.push({
      fromBlock: delta.fromBlock,
      toBlock: delta.toBlock,
      url: deltaRelativePath,
      sha256: sha256Hex(deltaBytes),
      sizeBytes: deltaBytes.length,
    });
  }

  const unsignedManifest = {
    protocolVersion: CHANNEL_WORKSPACE_MIRROR_PROTOCOL_VERSION,
    chainId: Number(network.chainId),
    channelId: channelId.toString(),
    channelName,
    bridgeCore: getAddress(bridgeDeployment.bridgeCore),
    channelManager: getAddress(channelInfo.manager),
    bridgeTokenVault: getAddress(channelInfo.bridgeTokenVault),
    leader: getAddress(channelInfo.leader),
    checkpoint: {
      recoveryLastScannedBlock: Number(local.recoveryLastScannedBlock),
      recoveryRootVectorHash: local.recoveryRootVectorHash,
      workspaceHash: hashJsonValue(local.workspace),
      stateSnapshotHash: hashJsonValue(local.stateSnapshot),
      blockInfoHash: hashJsonValue(local.blockInfo),
      contractCodesHash: hashJsonValue(local.contractCodes),
      bundle: {
        url: "checkpoint.zip",
        sha256: checkpointBundle.sha256,
        sizeBytes: checkpointBundle.bytes.length,
      },
    },
    deltaBundles,
    validationCertificate: {
      schema: "tokamak-private-state-workspace-mirror",
      signer: getAddress(signer.address),
      signedAt: new Date().toISOString(),
      canary: {
        proofVerified: true,
        description: "The channel leader attests that the checkpoint workspace passed the operator's canary proof generation and verification workflow.",
      },
    },
    createdAt: new Date().toISOString(),
    minCliVersion: privateStateCliPackageJson.version,
  };
  const signature = await signer.signMessage(ethers.getBytes(hashWorkspaceMirrorCertificatePayload(unsignedManifest)));
  const manifest = {
    ...unsignedManifest,
    validationCertificate: {
      ...unsignedManifest.validationCertificate,
      signature,
    },
  };
  writeJson(publishTarget.manifestPath, manifest);

  return {
    action: "channel recover-workspace publish-workspace-mirror",
    channelName,
    channelId: channelId.toString(),
    force,
    leaderAccount,
    leader: getAddress(signer.address),
    outputRoot,
    mirrorDir,
    manifestPath: publishTarget.manifestPath,
    registeredUrl,
    manifestUrl,
    remoteCheckpoint: remote.exists
      ? {
        recoveryLastScannedBlock: remote.recoveryLastScannedBlock,
        recoveryRootVectorHash: remote.recoveryRootVectorHash,
      }
      : null,
    ignoredRemoteCheckpoint: remote.ignored
      ? {
        manifestUrl,
        error: remote.error,
      }
      : null,
    checkpoint: {
      recoveryLastScannedBlock: local.recoveryLastScannedBlock,
      recoveryRootVectorHash: local.recoveryRootVectorHash,
      bundlePath: checkpointBundlePath,
      sha256: checkpointBundle.sha256,
      sizeBytes: checkpointBundle.bytes.length,
    },
    deltaBundles,
  };
}

function resolveWorkspaceRecoverySource(args) {
  const source = args.source === undefined ? "rpc" : String(args.source).trim().toLowerCase();
  if (!["rpc", "mirror"].includes(source)) {
    throw new Error("--source must be one of: rpc, mirror.");
  }
  if (args.fromGenesis === true && (args.source === undefined || source !== "rpc")) {
    throw new Error("--from-genesis requires explicit --source rpc.");
  }
  return source;
}

function requireWorkspaceMirrorUrl(value) {
  const url = String(requireArg(value, "--url")).trim();
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
      throw new Error("unsupported protocol");
    }
  } catch {
    throw new Error("--url must be an http or https URL.");
  }
  return url;
}

async function readChannelWorkspaceMirror({ bridgeCore, channelId }) {
  return String(await bridgeCore.getChannelWorkspaceMirror(channelId));
}

async function readRemoteWorkspaceMirrorCheckpoint({
  manifestUrl,
  chainId,
  channelId,
  channelName,
  bridgeCoreAddress,
  channelInfo,
  blockInfo,
  contractCodes,
  force = false,
}) {
  const ignoreRemote = (error) => {
    if (!force) {
      throw error;
    }
    return {
      exists: false,
      ignored: true,
      error: error.message,
      recoveryLastScannedBlock: null,
      recoveryRootVectorHash: null,
    };
  };
  let manifest;
  try {
    manifest = await fetchJsonFromUrl(manifestUrl, { maxBytes: 1024 * 1024 });
  } catch (error) {
    if (/\bHTTP (404|410)\b/u.test(error.message)) {
      return {
        exists: false,
        ignored: false,
        error: null,
        recoveryLastScannedBlock: null,
        recoveryRootVectorHash: null,
      };
    }
    return ignoreRemote(new Error(`Unable to read registered workspace mirror manifest before publish: ${error.message}`));
  }
  let checkpoint;
  try {
    checkpoint = validateWorkspaceMirrorManifest({
      manifest,
      chainId,
      channelId,
      channelName,
      bridgeCoreAddress,
      channelInfo,
      blockInfo,
      contractCodes,
    });
  } catch (error) {
    return ignoreRemote(new Error(`Registered workspace mirror manifest is invalid before publish: ${error.message}`));
  }
  return {
    exists: true,
    ignored: false,
    error: null,
    recoveryLastScannedBlock: checkpoint.recoveryLastScannedBlock,
    recoveryRootVectorHash: checkpoint.recoveryRootVectorHash,
  };
}

function buildWorkspaceMirrorCheckpointBundle({
  workspace,
  stateSnapshot,
  blockInfo,
  contractCodes,
}) {
  const archive = new AdmZip();
  const files = {
    "workspace.json": workspace,
    "state_snapshot.json": stateSnapshot,
    "block_info.json": blockInfo,
    "contract_codes.json": contractCodes,
  };
  for (const [fileName, value] of Object.entries(files)) {
    archive.addFile(fileName, Buffer.from(`${JSON.stringify(normalizeCliOutput(value), null, 2)}\n`, "utf8"));
  }
  const bytes = archive.toBuffer();
  return {
    bytes,
    sha256: sha256Hex(bytes),
  };
}

async function buildWorkspaceMirrorDeltaBundle({
  provider,
  bridgeAbiManifest,
  channelInfo,
  chainId,
  channelId,
  fromBlock,
  toBlock,
  baseRecoveryRootVectorHash,
  recoveryRootVectorHash,
}) {
  expect(Number.isInteger(fromBlock) && Number.isInteger(toBlock) && toBlock >= fromBlock, "Invalid workspace mirror delta block range.");
  const { channelManagerLogs, bridgeVaultLogs } = await fetchChannelRecoveryLogs({
    provider,
    bridgeAbiManifest,
    channelInfo,
    fromBlock,
    toBlock,
  });
  const logs = [...channelManagerLogs, ...bridgeVaultLogs]
    .sort(compareLogsByPosition)
    .map(serializeWorkspaceMirrorDeltaLog);
  return {
    protocolVersion: CHANNEL_WORKSPACE_MIRROR_PROTOCOL_VERSION,
    chainId: Number(chainId),
    channelId: channelId.toString(),
    fromBlock,
    toBlock,
    baseRecoveryRootVectorHash: normalizeBytes32Hex(baseRecoveryRootVectorHash),
    recoveryRootVectorHash: normalizeBytes32Hex(recoveryRootVectorHash),
    logs,
  };
}

function serializeWorkspaceMirrorDeltaLog(log) {
  return {
    address: getAddress(log.address),
    topics: (log.topics ?? []).map((topic) => normalizeBytes32Hex(topic)),
    data: log.data ?? "0x",
    blockNumber: Number(log.blockNumber),
    transactionHash: normalizeBytes32Hex(log.transactionHash),
    transactionIndex: Number(log.transactionIndex),
    index: Number(log.index ?? log.logIndex),
  };
}

function workspaceMirrorPublishTarget({ outputRoot, registeredUrl, chainId, channelId }) {
  const parsed = new URL(registeredUrl);
  const registeredSegments = safeUrlPathSegments(parsed.pathname);
  if (parsed.pathname.endsWith(".json")) {
    const manifestPath = path.join(outputRoot, ...registeredSegments);
    return {
      mirrorDir: path.dirname(manifestPath),
      manifestPath,
    };
  }
  const mirrorDir = path.join(
    outputRoot,
    ...registeredSegments,
    ...CHANNEL_WORKSPACE_MIRROR_MANIFEST_PATH_PREFIX.split("/"),
    String(chainId),
    channelId.toString(),
  );
  return {
    mirrorDir,
    manifestPath: path.join(mirrorDir, "manifest.json"),
  };
}

function safeUrlPathSegments(pathname) {
  return pathname
    .split("/")
    .filter(Boolean)
    .map((segment) => decodeURIComponent(segment))
    .filter((segment) => segment !== ".")
    .map((segment) => {
      expect(segment !== ".." && !segment.includes("/") && !segment.includes("\\"), "Workspace mirror URL path contains an unsafe segment.");
      return segment;
    });
}

async function loadWorkspaceMirrorRecoveryIndex({
  recoverySource,
  bridgeCore,
  channelId,
  channelName,
  network,
  bridgeDeployment,
  channelInfo,
  genesisBlockNumber,
  managedStorageAddresses,
  blockInfo,
  contractCodes,
  latestBlock,
  localRecoveryIndex = null,
  bridgeAbiManifest,
  controllerAddress,
  l2AccountingVaultAddress,
  liquidBalancesSlot,
}) {
  const baseStatus = {
    source: recoverySource,
    used: false,
    registeredUrl: null,
    manifestUrl: null,
    bundleUrl: null,
    skippedReason: null,
    recoveryLastScannedBlock: null,
    recoveryRootVectorHash: null,
    error: null,
  };
  if (recoverySource === "rpc") {
    return { recoveryIndex: null, workspaceMirror: baseStatus };
  }

  let registeredUrl;
  try {
    registeredUrl = String(await readChannelWorkspaceMirror({ bridgeCore, channelId })).trim();
  } catch (error) {
    throw new Error(`Unable to read channel workspace mirror registry: ${error.message}`);
  }
  if (!registeredUrl) {
    throw new Error(`No workspace mirror URL is registered for channel ${channelName}.`);
  }

  try {
    const mirror = await fetchChannelWorkspaceMirror({
      registeredUrl,
      chainId: Number(network.chainId),
      channelId,
      channelName,
      bridgeCoreAddress: bridgeDeployment.bridgeCore,
      channelInfo,
      genesisBlockNumber,
      managedStorageAddresses,
      blockInfo,
      contractCodes,
      latestBlock,
      localRecoveryIndex,
      bridgeAbiManifest,
      controllerAddress,
      l2AccountingVaultAddress,
      liquidBalancesSlot,
    });
    return {
      recoveryIndex: mirror.recoveryIndex,
      workspaceMirror: {
        source: recoverySource,
        used: mirror.recoveryIndex !== null,
        registeredUrl,
        manifestUrl: mirror.manifestUrl,
        bundleUrl: mirror.bundleUrl,
        skippedReason: mirror.skippedReason ?? null,
        recoveryLastScannedBlock: mirror.recoveryIndex?.nextBlock ?? null,
        recoveryRootVectorHash: mirror.recoveryIndex?.recoveryRootVectorHash ?? null,
        error: null,
      },
    };
  } catch (error) {
    throw new Error(`Workspace mirror recovery failed: ${error.message}`);
  }
}

async function fetchChannelWorkspaceMirror({
  registeredUrl,
  chainId,
  channelId,
  channelName,
  bridgeCoreAddress,
  channelInfo,
  genesisBlockNumber,
  managedStorageAddresses,
  blockInfo,
  contractCodes,
  latestBlock,
  localRecoveryIndex = null,
  bridgeAbiManifest,
  controllerAddress,
  l2AccountingVaultAddress,
  liquidBalancesSlot,
}) {
  const manifestUrl = channelWorkspaceMirrorManifestUrl({ registeredUrl, chainId, channelId });
  const manifest = await fetchJsonFromUrl(manifestUrl, { maxBytes: 1024 * 1024 });
  const manifestPrecheck = validateWorkspaceMirrorManifest({
    manifest,
    chainId,
    channelId,
    channelName,
    bridgeCoreAddress,
    channelInfo,
    blockInfo,
    contractCodes,
  });

  if (
    localRecoveryIndex
    && Number(manifestPrecheck.recoveryLastScannedBlock) <= Number(localRecoveryIndex.nextBlock)
  ) {
    return {
      manifestUrl,
      bundleUrl: null,
      recoveryIndex: null,
      skippedReason: "mirror-checkpoint-not-ahead-of-local",
    };
  }

  const mirrorAheadOfLocal = localRecoveryIndex
    && Number(manifestPrecheck.recoveryLastScannedBlock) > Number(localRecoveryIndex.nextBlock);
  const deltaBundleDescriptor = mirrorAheadOfLocal
    ? selectWorkspaceMirrorDeltaBundle({
      manifest,
      fromBlock: Number(localRecoveryIndex.nextBlock),
      toBlock: Number(manifest.checkpoint.recoveryLastScannedBlock) - 1,
    })
    : null;
  const bundleResult = mirrorAheadOfLocal && deltaBundleDescriptor
    ? await fetchAndApplyWorkspaceMirrorDelta({
      manifest,
      manifestUrl,
      bundleDescriptor: deltaBundleDescriptor,
      localRecoveryIndex,
      chainId,
      channelId,
      channelInfo,
      bridgeAbiManifest,
      managedStorageAddresses,
      contractCodes,
      controllerAddress,
      l2AccountingVaultAddress,
      liquidBalancesSlot,
    })
    : await fetchWorkspaceMirrorCheckpoint({
      manifest,
      manifestUrl,
      chainId,
      channelId,
      channelName,
      bridgeCoreAddress,
      channelInfo,
      genesisBlockNumber,
      managedStorageAddresses,
      blockInfo,
      contractCodes,
      latestBlock,
    });

  return {
    manifestUrl,
    bundleUrl: bundleResult.bundleUrl,
    recoveryIndex: bundleResult.recoveryIndex,
  };
}

function channelWorkspaceMirrorManifestUrl({ registeredUrl, chainId, channelId }) {
  const parsed = new URL(registeredUrl);
  if (parsed.pathname.endsWith(".json")) {
    return parsed.toString();
  }
  parsed.search = "";
  parsed.hash = "";
  const basePath = parsed.pathname.replace(/\/+$/u, "");
  parsed.pathname = [
    basePath,
    CHANNEL_WORKSPACE_MIRROR_MANIFEST_PATH_PREFIX,
    String(chainId),
    channelId.toString(),
    "manifest.json",
  ].filter(Boolean).join("/");
  return parsed.toString();
}

function resolveWorkspaceMirrorBundleUrl(manifestUrl, bundlePath, label) {
  expect(typeof bundlePath === "string" && bundlePath.length > 0, `Workspace mirror manifest is missing ${label}.url.`);
  return new URL(bundlePath, manifestUrl).toString();
}

async function fetchJsonFromUrl(url, { maxBytes = null } = {}) {
  const bytes = await fetchBytesFromUrl(url, { maxBytes });
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    throw new Error(`Invalid JSON from ${url}: ${error.message}`);
  }
}

async function fetchBytesFromUrl(url, {
  maxBytes = null,
  expectedBytes = null,
  onProgress = null,
} = {}) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`GET ${url} failed with HTTP ${response.status}.`);
  }
  const contentLength = Number(response.headers.get("content-length"));
  const hasExpectedBytes = expectedBytes !== null && expectedBytes !== undefined && Number.isFinite(Number(expectedBytes));
  const hasContentLength = response.headers.get("content-length") !== null && Number.isFinite(contentLength);
  const totalBytes = hasExpectedBytes
    ? Number(expectedBytes)
    : hasContentLength
      ? contentLength
      : null;
  const chunks = [];
  let downloadedBytes = 0;
  onProgress?.({
    status: "start",
    downloadedBytes,
    totalBytes,
  });

  const reportProgress = () => onProgress?.({
    status: "progress",
    downloadedBytes,
    totalBytes,
  });

  if (!response.body?.getReader) {
    if (maxBytes !== null && hasContentLength && contentLength > Number(maxBytes)) {
      throw new Error(`GET ${url} Content-Length ${contentLength} exceeds the ${maxBytes} byte limit.`);
    }
    const bytes = Buffer.from(await response.arrayBuffer());
    if (maxBytes !== null && bytes.length > Number(maxBytes)) {
      throw new Error(`GET ${url} returned ${bytes.length} bytes, above the ${maxBytes} byte limit.`);
    }
    onProgress?.({
      status: "done",
      downloadedBytes: bytes.length,
      totalBytes: totalBytes ?? bytes.length,
    });
    return bytes;
  }

  const reader = response.body.getReader();
  let lastProgressAtMs = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      const chunk = Buffer.from(value);
      chunks.push(chunk);
      downloadedBytes += chunk.length;
      if (maxBytes !== null && downloadedBytes > Number(maxBytes)) {
        throw new Error(`GET ${url} returned more than ${maxBytes} bytes.`);
      }
      const now = Date.now();
      if (now - lastProgressAtMs >= 250) {
        reportProgress();
        lastProgressAtMs = now;
      }
    }
  } catch (error) {
    onProgress?.({
      status: "error",
      downloadedBytes,
      totalBytes,
    });
    throw error;
  }

  const bytes = Buffer.concat(chunks, downloadedBytes);
  onProgress?.({
    status: "done",
    downloadedBytes,
    totalBytes: totalBytes ?? downloadedBytes,
  });
  return bytes;
}

function sha256Hex(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function parseWorkspaceMirrorArchive(bytes) {
  const zip = new AdmZip(bytes);
  const parsed = {};
  for (const entry of zip.getEntries()) {
    const entryName = entry.entryName.replace(/\\/gu, "/");
    if (entry.isDirectory) {
      continue;
    }
    expect(
      !entryName.startsWith("/") && !entryName.includes("/") && !entryName.includes(".."),
      `Workspace mirror checkpoint bundle contains unsupported path: ${entry.entryName}.`,
    );
    expect(
      CHANNEL_WORKSPACE_MIRROR_ARCHIVE_FILES.has(entryName),
      `Workspace mirror checkpoint bundle contains unsupported file: ${entry.entryName}.`,
    );
    expect(parsed[entryName] === undefined, `Workspace mirror checkpoint bundle contains duplicate file: ${entry.entryName}.`);
    parsed[entryName] = JSON.parse(entry.getData().toString("utf8"));
  }
  for (const fileName of CHANNEL_WORKSPACE_MIRROR_ARCHIVE_FILES) {
    expect(parsed[fileName] !== undefined, `Workspace mirror checkpoint bundle is missing ${fileName}.`);
  }
  return {
    workspace: parsed["workspace.json"],
    stateSnapshot: parsed["state_snapshot.json"],
    blockInfo: parsed["block_info.json"],
    contractCodes: parsed["contract_codes.json"],
  };
}

function validateWorkspaceMirrorManifest({
  manifest,
  chainId,
  channelId,
  channelName,
  bridgeCoreAddress,
  channelInfo,
  blockInfo,
  contractCodes,
}) {
  expect(Number(manifest.protocolVersion) === CHANNEL_WORKSPACE_MIRROR_PROTOCOL_VERSION, "Unsupported workspace mirror protocolVersion.");
  expect(Number(manifest.chainId) === Number(chainId), "Workspace mirror manifest chainId mismatch.");
  expect(
    ethers.toBigInt(manifest.channelId) === ethers.toBigInt(channelId),
    "Workspace mirror manifest channelId mismatch.",
  );
  if (manifest.channelName !== undefined) {
    expect(String(manifest.channelName) === channelName, "Workspace mirror manifest channelName mismatch.");
  }
  expect(
    ethers.toBigInt(getAddress(manifest.bridgeCore)) === ethers.toBigInt(getAddress(bridgeCoreAddress)),
    "Workspace mirror manifest bridgeCore mismatch.",
  );
  expect(
    ethers.toBigInt(getAddress(manifest.channelManager)) === ethers.toBigInt(getAddress(channelInfo.manager)),
    "Workspace mirror manifest channelManager mismatch.",
  );
  expect(
    ethers.toBigInt(getAddress(manifest.bridgeTokenVault)) === ethers.toBigInt(getAddress(channelInfo.bridgeTokenVault)),
    "Workspace mirror manifest bridgeTokenVault mismatch.",
  );
  expect(
    ethers.toBigInt(getAddress(manifest.leader)) === ethers.toBigInt(getAddress(channelInfo.leader)),
    "Workspace mirror manifest leader mismatch.",
  );
  const checkpoint = manifest.checkpoint;
  expect(checkpoint && typeof checkpoint === "object", "Workspace mirror manifest checkpoint is required.");
  const recoveryLastScannedBlock = Number(checkpoint.recoveryLastScannedBlock);
  expect(Number.isInteger(recoveryLastScannedBlock), "Workspace mirror checkpoint recoveryLastScannedBlock must be an integer.");
  const recoveryRootVectorHash = normalizeBytes32Hex(checkpoint.recoveryRootVectorHash);
  expect(recoveryRootVectorHash !== null, "Workspace mirror checkpoint recoveryRootVectorHash is required.");
  expect(typeof checkpoint.stateSnapshotHash === "string", "Workspace mirror checkpoint stateSnapshotHash is required.");
  expect(typeof checkpoint.workspaceHash === "string", "Workspace mirror checkpoint workspaceHash is required.");
  expect(hashJsonValue(blockInfo) === normalizeBytes32Hex(checkpoint.blockInfoHash), "Workspace mirror checkpoint blockInfoHash mismatch.");
  expect(hashJsonValue(contractCodes) === normalizeBytes32Hex(checkpoint.contractCodesHash), "Workspace mirror checkpoint contractCodesHash mismatch.");
  validateWorkspaceMirrorCertificate({ manifest });
  return {
    recoveryLastScannedBlock,
    recoveryRootVectorHash,
  };
}

function validateWorkspaceMirrorCertificate({ manifest }) {
  const certificate = manifest.validationCertificate;
  expect(certificate && typeof certificate === "object", "Workspace mirror validationCertificate is required.");
  expect(certificate.schema === "tokamak-private-state-workspace-mirror", "Workspace mirror validationCertificate schema mismatch.");
  expect(certificate.canary?.proofVerified === true, "Workspace mirror validationCertificate must confirm canary proof verification.");
  expect(typeof certificate.signature === "string", "Workspace mirror validationCertificate signature is required.");
  const signer = getAddress(certificate.signer ?? manifest.leader);
  expect(
    ethers.toBigInt(signer) === ethers.toBigInt(getAddress(manifest.leader)),
    "Workspace mirror validationCertificate signer must be the channel leader.",
  );
  const payloadHash = hashWorkspaceMirrorCertificatePayload(manifest);
  const recoveredSigner = getAddress(ethers.verifyMessage(ethers.getBytes(payloadHash), certificate.signature));
  expect(
    ethers.toBigInt(recoveredSigner) === ethers.toBigInt(getAddress(manifest.leader)),
    "Workspace mirror validationCertificate signature was not produced by the channel leader.",
  );
}

function hashWorkspaceMirrorCertificatePayload(manifest) {
  const certificate = { ...(manifest.validationCertificate ?? {}) };
  delete certificate.signature;
  return hashJsonValue({
    protocolVersion: manifest.protocolVersion,
    chainId: manifest.chainId,
    channelId: manifest.channelId,
    channelName: manifest.channelName,
    bridgeCore: manifest.bridgeCore,
    channelManager: manifest.channelManager,
    bridgeTokenVault: manifest.bridgeTokenVault,
    leader: manifest.leader,
    checkpoint: manifest.checkpoint,
    deltaBundles: manifest.deltaBundles ?? [],
    validationCertificate: certificate,
  });
}

async function fetchWorkspaceMirrorCheckpoint({
  manifest,
  manifestUrl,
  chainId,
  channelId,
  channelName,
  bridgeCoreAddress,
  channelInfo,
  genesisBlockNumber,
  managedStorageAddresses,
  blockInfo,
  contractCodes,
  latestBlock,
}) {
  const bundleDescriptor = manifest.checkpoint?.bundle;
  expect(bundleDescriptor?.url, "Workspace mirror checkpoint.bundle.url is required when no usable local recovery index exists.");
  expect(bundleDescriptor?.sha256, "Workspace mirror checkpoint.bundle.sha256 is required.");
  const bundleUrl = resolveWorkspaceMirrorBundleUrl(manifestUrl, bundleDescriptor.url, "checkpoint.bundle");
  const archiveBytes = await fetchWorkspaceMirrorBundleBytes({
    bundleUrl,
    bundleDescriptor,
    label: "workspace mirror checkpoint",
  });
  const archive = parseWorkspaceMirrorArchive(archiveBytes);
  const recoveryIndex = validateWorkspaceMirrorCheckpointArchive({
    manifest,
    archive,
    chainId,
    channelId,
    channelName,
    bridgeCoreAddress,
    channelInfo,
    genesisBlockNumber,
    managedStorageAddresses,
    blockInfo,
    contractCodes,
    latestBlock,
  });
  return { bundleUrl, recoveryIndex };
}

function validateWorkspaceMirrorCheckpointArchive({
  manifest,
  archive,
  chainId,
  channelId,
  channelName,
  bridgeCoreAddress,
  channelInfo,
  genesisBlockNumber,
  managedStorageAddresses,
  blockInfo,
  contractCodes,
  latestBlock,
}) {
  const workspace = archive.workspace;
  expect(Number(workspace.chainId) === Number(chainId), "Workspace mirror workspace chainId mismatch.");
  expect(ethers.toBigInt(workspace.channelId) === ethers.toBigInt(channelId), "Workspace mirror workspace channelId mismatch.");
  expect(String(workspace.channelName) === channelName, "Workspace mirror workspace channelName mismatch.");
  expect(
    ethers.toBigInt(getAddress(workspace.bridgeCore)) === ethers.toBigInt(getAddress(bridgeCoreAddress)),
    "Workspace mirror workspace bridgeCore mismatch.",
  );
  expect(
    ethers.toBigInt(getAddress(workspace.channelManager)) === ethers.toBigInt(getAddress(channelInfo.manager)),
    "Workspace mirror workspace channelManager mismatch.",
  );
  expect(
    ethers.toBigInt(getAddress(workspace.bridgeTokenVault)) === ethers.toBigInt(getAddress(channelInfo.bridgeTokenVault)),
    "Workspace mirror workspace bridgeTokenVault mismatch.",
  );
  expect(Number(workspace.genesisBlockNumber) === Number(genesisBlockNumber), "Workspace mirror genesisBlockNumber mismatch.");
  const mirroredManagedStorageAddresses = normalizedAddressVector(workspace.managedStorageAddresses ?? []);
  expect(
    mirroredManagedStorageAddresses.length === managedStorageAddresses.length
      && mirroredManagedStorageAddresses.every(
        (address, index) => ethers.toBigInt(getAddress(address)) === ethers.toBigInt(getAddress(managedStorageAddresses[index])),
      ),
    "Workspace mirror managedStorageAddresses mismatch.",
  );
  expect(hashJsonValue(workspace) === normalizeBytes32Hex(manifest.checkpoint.workspaceHash), "Workspace mirror workspace hash mismatch.");
  expect(
    hashJsonValue(archive.stateSnapshot) === normalizeBytes32Hex(manifest.checkpoint.stateSnapshotHash),
    "Workspace mirror state_snapshot hash mismatch.",
  );
  expect(hashJsonValue(archive.blockInfo) === hashJsonValue(blockInfo), "Workspace mirror block_info.json does not match the channel genesis block.");
  expect(
    hashJsonValue(archive.contractCodes) === hashJsonValue(contractCodes),
    "Workspace mirror contract_codes.json does not match current managed storage contract code.",
  );
  const workspaceRootVectorHash = normalizeBytes32Hex(workspace.recoveryRootVectorHash);
  expect(
    ethers.toBigInt(normalizeBytes32Hex(manifest.checkpoint.recoveryRootVectorHash)) === ethers.toBigInt(workspaceRootVectorHash),
    "Workspace mirror recoveryRootVectorHash mismatch between manifest and workspace.",
  );
  const snapshotRootVectorHash = normalizeBytes32Hex(hashRootVector(archive.stateSnapshot.stateRoots));
  expect(
    ethers.toBigInt(snapshotRootVectorHash) === ethers.toBigInt(workspaceRootVectorHash),
    "Workspace mirror state_snapshot root vector hash mismatch.",
  );
  const mirrorRecoveryLastScannedBlock = Number(manifest.checkpoint.recoveryLastScannedBlock);
  expect(
    Number.isInteger(mirrorRecoveryLastScannedBlock)
      && mirrorRecoveryLastScannedBlock === Number(workspace.recoveryLastScannedBlock),
    "Workspace mirror recoveryLastScannedBlock mismatch between manifest and workspace.",
  );
  const recoveryIndex = getUsableWorkspaceRecoveryIndex({
    existingArtifacts: {
      workspace: {
        recoveryLastScannedBlock: mirrorRecoveryLastScannedBlock,
        recoveryRootVectorHash: workspaceRootVectorHash,
      },
      stateSnapshot: archive.stateSnapshot,
    },
    genesisBlockNumber,
    latestBlock,
    managedStorageAddresses,
  });
  expect(recoveryIndex, "Workspace mirror recovery index is missing or unusable.");
  return {
    ...recoveryIndex,
    source: "mirror",
  };
}

async function fetchAndApplyWorkspaceMirrorDelta({
  manifest,
  manifestUrl,
  bundleDescriptor,
  localRecoveryIndex,
  chainId,
  channelId,
  channelInfo,
  bridgeAbiManifest,
  managedStorageAddresses,
  contractCodes,
  controllerAddress,
  l2AccountingVaultAddress,
  liquidBalancesSlot,
}) {
  const fromBlock = Number(localRecoveryIndex.nextBlock);
  const toBlock = Number(manifest.checkpoint.recoveryLastScannedBlock) - 1;
  expect(
    bundleDescriptor,
    `Workspace mirror does not provide a delta bundle for local recovery index ${fromBlock} to checkpoint block ${toBlock}.`,
  );
  const bundleUrl = resolveWorkspaceMirrorBundleUrl(manifestUrl, bundleDescriptor.url, "deltaBundles[]");
  const bundleBytes = await fetchWorkspaceMirrorBundleBytes({
    bundleUrl,
    bundleDescriptor,
    label: "workspace mirror delta",
  });
  const delta = parseJsonBytes(bundleBytes, bundleUrl);
  const recoveryIndex = await applyWorkspaceMirrorDeltaBundle({
    delta,
    localRecoveryIndex,
    manifest,
    chainId,
    channelId,
    channelInfo,
    bridgeAbiManifest,
    managedStorageAddresses,
    contractCodes,
    controllerAddress,
    l2AccountingVaultAddress,
    liquidBalancesSlot,
  });
  return { bundleUrl, recoveryIndex };
}

function selectWorkspaceMirrorDeltaBundle({ manifest, fromBlock, toBlock }) {
  const bundles = Array.isArray(manifest.deltaBundles) ? manifest.deltaBundles : [];
  return bundles.find((bundle) => Number(bundle.fromBlock) === fromBlock && Number(bundle.toBlock) === toBlock) ?? null;
}

async function fetchWorkspaceMirrorBundleBytes({ bundleUrl, bundleDescriptor, label }) {
  expect(bundleDescriptor?.sizeBytes !== undefined, `Workspace mirror ${label} sizeBytes is required.`);
  const expectedBytes = Number(bundleDescriptor.sizeBytes);
  expect(
    Number.isSafeInteger(expectedBytes) && expectedBytes >= 0,
    `Workspace mirror ${label} sizeBytes must be a non-negative safe integer.`,
  );
  const bytes = await fetchBytesFromUrl(bundleUrl, {
    maxBytes: expectedBytes,
    expectedBytes,
    onProgress: createByteDownloadProgress({
      action: "channel recover-workspace",
      label,
      url: bundleUrl,
    }),
  });
  expect(
    expectedBytes === bytes.length,
    `Workspace mirror bundle size mismatch. Expected ${expectedBytes}, got ${bytes.length}.`,
  );
  const bundleSha256 = sha256Hex(bytes);
  expect(
    String(bundleDescriptor.sha256).toLowerCase() === bundleSha256,
    `Workspace mirror bundle sha256 mismatch. Expected ${bundleDescriptor.sha256}, got ${bundleSha256}.`,
  );
  return bytes;
}

function parseJsonBytes(bytes, url) {
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    throw new Error(`Invalid JSON from ${url}: ${error.message}`);
  }
}

function selectWorkspaceRecoveryIndex(localRecoveryIndex, mirrorRecoveryIndex) {
  if (!localRecoveryIndex) {
    return mirrorRecoveryIndex ?? null;
  }
  if (!mirrorRecoveryIndex) {
    return localRecoveryIndex;
  }
  return Number(mirrorRecoveryIndex.nextBlock) > Number(localRecoveryIndex.nextBlock)
    ? mirrorRecoveryIndex
    : localRecoveryIndex;
}

async function syncChannelWorkspace({
  workspaceName,
  channelName,
  network,
  provider,
  bridgeResources,
  persist,
  allowExistingWorkspaceSync = false,
  useWorkspaceRecoveryIndex = false,
  fromGenesis = false,
  recoverySource = "rpc",
  outputRawRpcCallHistory = false,
  minimumToBlock = null,
  progressAction = null,
}) {
  const workspaceDir = channelWorkspacePath(networkNameFromChainId(network.chainId), workspaceName);
  const channelDir = channelDataPath(workspaceDir);
  let cleanRebuildBackup = null;
  const hasPersistedChannelData = fs.existsSync(channelWorkspaceConfigPath(workspaceDir))
    || fs.existsSync(channelWorkspaceCurrentPath(workspaceDir))
    || fs.existsSync(channelWorkspaceOperationsPath(workspaceDir));

  if (persist && hasPersistedChannelData && !allowExistingWorkspaceSync) {
    throw new Error(`Workspace already exists: ${workspaceDir}.`);
  }

  const existingArtifacts = persist && hasPersistedChannelData
    ? loadExistingWorkspaceArtifacts(workspaceDir)
    : null;
  if (persist && useWorkspaceRecoveryIndex && fromGenesis) {
    cleanRebuildBackup = backupWorkspaceForCleanRebuild({
      workspaceDir,
      networkName: networkNameFromChainId(network.chainId),
      channelName,
    });
  }

  const rpcCallHistoryRecorder = outputRawRpcCallHistory
    ? createRpcCallHistoryRecorder({ workspaceDir })
    : null;
  const activeProvider = rpcCallHistoryRecorder
    ? attachRpcCallHistoryRecorderToProvider(provider, rpcCallHistoryRecorder)
    : provider;

  const { bridgeDeployment, bridgeAbiManifest } = bridgeResources;
  const bridgeCore = new Contract(bridgeDeployment.bridgeCore, bridgeAbiManifest.contracts.bridgeCore.abi, activeProvider);
  const channelId = deriveChannelIdFromName(channelName);
  const channelInfo = await bridgeCore.getChannel(channelId);
  if (!channelInfo.exists) {
    throw new Error(`Unknown channel ${channelId.toString()} in bridge core ${bridgeDeployment.bridgeCore}.`);
  }

  const channelManager = new Contract(
    channelInfo.manager,
    bridgeAbiManifest.contracts.channelManager.abi,
    activeProvider,
  );
  const canonicalAsset = getAddress(channelInfo.asset);
  const canonicalAssetDecimals = await fetchTokenDecimals(activeProvider, canonicalAsset);
  const currentRootVectorHash = normalizeBytes32Hex(await channelManager.currentRootVectorHash());
  const genesisBlockNumber = Number(await channelManager.genesisBlockNumber());
  const observedLatestBlock = await activeProvider.getBlockNumber();
  const latestBlock = minimumToBlock === null
    ? observedLatestBlock
    : Math.max(observedLatestBlock, Number(minimumToBlock));
  const managedStorageAddresses = normalizedAddressVector(await channelManager.getManagedStorageAddresses());
  const policySnapshot = await readChannelPolicySnapshot({
    channelManager,
    dappId: Number(channelInfo.dappId),
  });
  const deploymentManifestPath = dappDeploymentManifestPath(network.chainId);
  const storageLayoutManifestPath = dappStorageLayoutManifestPath(network.chainId);
  const deploymentManifest = readJson(deploymentManifestPath);
  const storageLayoutManifest = readJson(storageLayoutManifestPath);
  const controllerAddress = getAddress(deploymentManifest.contracts.controller);
  const l2AccountingVaultAddress = getAddress(deploymentManifest.contracts.l2AccountingVault);
  const liquidBalancesSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "L2AccountingVault", "liquidBalances"));

  expect(
    managedStorageAddresses.some((address) => ethers.toBigInt(getAddress(address)) === ethers.toBigInt(controllerAddress)),
    `Managed storage vector does not include controller ${controllerAddress}.`,
  );
  expect(
    managedStorageAddresses.some(
      (address) => ethers.toBigInt(getAddress(address)) === ethers.toBigInt(l2AccountingVaultAddress),
    ),
    `Managed storage vector does not include L2 accounting vault ${l2AccountingVaultAddress}.`,
  );

  const contractCodes = await fetchContractCodes(activeProvider, managedStorageAddresses);
  const blockInfo = await getBlockInfoAt(activeProvider, genesisBlockNumber);
  const derivedAPubBlockHash = normalizeBytes32Hex(hashTokamakPublicInputs(encodeTokamakBlockInfo(blockInfo)));
  expect(
    ethers.toBigInt(derivedAPubBlockHash) === ethers.toBigInt(normalizeBytes32Hex(channelInfo.aPubBlockHash)),
    `Derived channel block-info hash ${derivedAPubBlockHash} does not match onchain ${channelInfo.aPubBlockHash}.`,
  );
  const recoveryIndex = useWorkspaceRecoveryIndex && !fromGenesis
    ? getUsableWorkspaceRecoveryIndex({
      existingArtifacts,
      genesisBlockNumber,
      latestBlock,
      managedStorageAddresses,
    })
    : null;
  const mirrorRecovery = useWorkspaceRecoveryIndex && !fromGenesis
    ? await loadWorkspaceMirrorRecoveryIndex({
      recoverySource,
      bridgeCore,
      channelId,
      channelName,
      network,
      bridgeDeployment,
      channelInfo,
      genesisBlockNumber,
      managedStorageAddresses,
      blockInfo,
      contractCodes,
      latestBlock,
      localRecoveryIndex: recoveryIndex,
      bridgeAbiManifest,
      controllerAddress,
      l2AccountingVaultAddress,
      liquidBalancesSlot,
    })
    : {
      recoveryIndex: null,
      workspaceMirror: {
        source: recoverySource,
        used: false,
        registeredUrl: null,
        manifestUrl: null,
        error: null,
      },
    };
  const selectedRecoveryIndex = selectWorkspaceRecoveryIndex(recoveryIndex, mirrorRecovery.recoveryIndex);
  const localSnapshotReusable = !fromGenesis && (!useWorkspaceRecoveryIndex || recoveryIndex)
    && canReuseLocalWorkspaceSnapshot({
      existingArtifacts,
      currentRootVectorHash,
      managedStorageAddresses,
    });
  const mirrorSnapshotReusable = !fromGenesis && mirrorRecovery.recoveryIndex
    && ethers.toBigInt(normalizeBytes32Hex(mirrorRecovery.recoveryIndex.recoveryRootVectorHash))
      === ethers.toBigInt(normalizeBytes32Hex(currentRootVectorHash));
  if (
    useWorkspaceRecoveryIndex
    && !fromGenesis
    && !localSnapshotReusable
    && !mirrorSnapshotReusable
    && !selectedRecoveryIndex
  ) {
    throw new Error([
      `Workspace recovery index is missing or unusable for channel ${channelName} on ${networkNameFromChainId(network.chainId)}.`,
      "The CLI will not fall back to replaying channel logs from genesis unless explicitly requested.",
      "Run channel recover-workspace first to refresh the local channel workspace.",
    ].join(" "));
  }
  const workspaceBase = {
    name: workspaceName,
    network: networkNameFromChainId(network.chainId),
    chainId: network.chainId,
    appDeploymentPath: deploymentManifestPath,
    storageLayoutPath: storageLayoutManifestPath,
    channelId: channelId.toString(),
    channelName,
    dappId: Number(channelInfo.dappId),
    genesisBlockNumber,
    bridgeCore: getAddress(bridgeDeployment.bridgeCore),
    channelManager: getAddress(channelInfo.manager),
    bridgeTokenVault: getAddress(channelInfo.bridgeTokenVault),
    canonicalAsset,
    canonicalAssetDecimals,
    controller: controllerAddress,
    l2AccountingVault: l2AccountingVaultAddress,
    aPubBlockHash: normalizeBytes32Hex(channelInfo.aPubBlockHash),
    dappMetadataDigestSchema: policySnapshot.dappMetadataDigestSchema,
    dappMetadataDigest: policySnapshot.dappMetadataDigest,
    functionRoot: policySnapshot.functionRoot,
    policySnapshot,
    managedStorageAddresses,
    liquidBalancesSlot: liquidBalancesSlot.toString(),
    recoverySource,
    workspaceMirror: mirrorRecovery.workspaceMirror,
  };
  const buildWorkspaceForSnapshot = ({ currentSnapshot, scanRange }) => {
    const recoveryRootVectorHash = normalizeBytes32Hex(hashRootVector(currentSnapshot.stateRoots));
    return {
      ...workspaceBase,
      recoveryLastScannedBlock: Number(scanRange.toBlock) + 1,
      recoveryRootVectorHash,
      recoveryScanRange: scanRange,
    };
  };
  const persistWorkspaceCheckpoint = persist
    ? ({ currentSnapshot, scanRange }) => {
      persistChannelWorkspaceFiles({
        workspaceDir,
        channelDir,
        workspace: buildWorkspaceForSnapshot({ currentSnapshot, scanRange }),
        currentSnapshot,
        blockInfo,
        contractCodes,
      });
    }
    : null;
  rpcCallHistoryRecorder?.setScanRange({
    fromBlock: selectedRecoveryIndex?.nextBlock ?? genesisBlockNumber,
    toBlock: latestBlock,
  });
  const reconstruction = localSnapshotReusable
    ? {
      currentSnapshot: existingArtifacts.stateSnapshot,
      scanRange: {
        fromBlock: latestBlock + 1,
        toBlock: latestBlock,
        mode: "reused-current-snapshot",
      },
    }
    : mirrorSnapshotReusable
      ? {
        currentSnapshot: mirrorRecovery.recoveryIndex.stateSnapshot,
        scanRange: {
          fromBlock: latestBlock + 1,
          toBlock: latestBlock,
          mode: "reused-mirror-snapshot",
        },
      }
    : await reconstructChannelSnapshot({
      provider: activeProvider,
      bridgeAbiManifest,
      channelInfo,
      channelManager,
      currentRootVectorHash,
      managedStorageAddresses,
      contractCodes,
      genesisBlockNumber,
      channelId,
      controllerAddress,
      l2AccountingVaultAddress,
      liquidBalancesSlot,
      baseSnapshot: selectedRecoveryIndex?.stateSnapshot ?? null,
      fromBlock: selectedRecoveryIndex?.nextBlock ?? genesisBlockNumber,
      toBlock: latestBlock,
      progressAction,
      onCheckpoint: persistWorkspaceCheckpoint,
      rpcCallHistoryRecorder,
    });
  rpcCallHistoryRecorder?.setScanRange(reconstruction.scanRange);
  const currentSnapshot = reconstruction.currentSnapshot;
  const workspace = buildWorkspaceForSnapshot({
    currentSnapshot,
    scanRange: reconstruction.scanRange,
  });

  if (persist) {
    persistChannelWorkspaceFiles({
      workspaceDir,
      channelDir,
      workspace,
      currentSnapshot,
      blockInfo,
      contractCodes,
    });
  }

  return {
    workspaceDir,
    workspace,
    currentSnapshot,
    blockInfo,
    contractCodes,
    cleanRebuildBackup,
    rpcCallHistory: rpcCallHistoryRecorder?.finish() ?? null,
  };
}

async function handleDepositBridge({ args, network, provider }) {
  if (args.wallet !== undefined) {
    throw new Error(
      "--wallet is not supported by account deposit-bridge. Channel wallet keys are set up only by channel join.",
    );
  }
  const signer = requireL1Signer(args, provider);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId: network.chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
  await requireActionImpactAcknowledgement("account-deposit-bridge", args, {
    l1Address: signer.address,
    amountInput,
    bridgeTokenVault: bridgeVaultContext.bridgeTokenVaultAddress,
  });
  const bridgeTokenVault = new Contract(
    bridgeVaultContext.bridgeTokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const asset = new Contract(
    bridgeVaultContext.canonicalAsset,
    bridgeVaultContext.bridgeAbiManifest.contracts.erc20.abi,
    signer,
  );
  let nextNonce = await provider.getTransactionCount(signer.address, "pending");
  const approveReceipt =
    await waitForReceipt(await asset.approve(bridgeVaultContext.bridgeTokenVaultAddress, amount, { nonce: nextNonce++ }));
  const fundReceipt = await waitForReceipt(await bridgeTokenVault.fund(amount, { nonce: nextNonce++ }));
  const availableBalance = await bridgeTokenVault.availableBalanceOf(signer.address);

  printJson({
    action: "account deposit-bridge",
    amountInput,
    amountBaseUnits: amount.toString(),
    l1Address: signer.address,
    availableBalance: availableBalance.toString(),
    bridgeTokenVault: bridgeVaultContext.bridgeTokenVaultAddress,
    approveGasUsed: receiptGasUsed(approveReceipt),
    fundGasUsed: receiptGasUsed(fundReceipt),
    totalGasUsed: (ethers.toBigInt(approveReceipt.gasUsed) + ethers.toBigInt(fundReceipt.gasUsed)).toString(),
    approveTxUrl: explorerTxUrl(network, approveReceipt.hash),
    fundTxUrl: explorerTxUrl(network, fundReceipt.hash),
    approveReceipt: sanitizeReceipt(approveReceipt),
    fundReceipt: sanitizeReceipt(fundReceipt),
  });
}

async function handleAccountGetBridgeFund({ args, provider }) {
  const signer = requireL1Signer(args, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId });
  const bridgeTokenVault = new Contract(
    bridgeVaultContext.bridgeTokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const availableBalance = await bridgeTokenVault.availableBalanceOf(signer.address);

  printJson({
    action: "account get-bridge-fund",
    l1Address: signer.address,
    bridgeTokenVault: bridgeVaultContext.bridgeTokenVaultAddress,
    canonicalAsset: bridgeVaultContext.canonicalAsset,
    canonicalAssetDecimals: Number(bridgeVaultContext.canonicalAssetDecimals),
    availableBalanceBaseUnits: availableBalance.toString(),
    availableBalanceTokens: ethers.formatUnits(
      availableBalance,
      Number(bridgeVaultContext.canonicalAssetDecimals),
    ),
  });
}

async function handleRecoverWallet({ args, network, provider, rpcUrl }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const signer = requireL1Signer(args, provider);
  const walletName = walletNameForChannelAndAddress(channelName, signer.address);
  const channelContextResult = await loadFreshChannelWorkspaceContextResult({
    channelName,
    networkName: requireNetworkName(args),
    provider,
    progressAction: "wallet recover-workspace",
  });
  const context = channelContextResult.context;
  const noteReceiveKeyMaterial = await deriveNoteReceiveKeyMaterial({
    signer,
    chainId: network.chainId,
    channelId: context.workspace.channelId,
    channelName,
    account: signer.address,
  });
  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  const recoveredSpendingIdentity = await deriveRecoverWalletSpendingIdentity({
    args,
    signer,
    channelName,
    context,
    registration,
  });
  const walletRecoveryTargetBlock = walletNoteReceiveTargetBlock(context);
  const recoveryEventScan = await scanWalletRecoveryEvents({
    context,
    provider,
    l1Address: signer.address,
    toBlock: walletRecoveryTargetBlock,
    progressAction: "wallet recover-workspace",
  });
  const lifecycleEpoch = selectWalletLifecycleEpoch({
    epochs: recoveryEventScan.lifecycleEpochs,
    registration,
  });
  expect(
    lifecycleEpoch,
    cliError(
      CLI_ERROR_CODES.MISSING_CHANNEL_REGISTRATION,
      `No channelTokenVault registration history exists for ${signer.address}. Run channel join first.`,
    ),
  );
  const registeredNoteReceivePubKey = lifecycleEpoch.noteReceivePubKey;
  expect(
    ethers.toBigInt(normalizeBytes32Hex(registeredNoteReceivePubKey.x))
      === ethers.toBigInt(normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x)),
    "The existing note-receive public key X does not match the derived note-receive public key.",
  );
  expect(
    Number(registeredNoteReceivePubKey.yParity) === Number(noteReceiveKeyMaterial.noteReceivePubKey.yParity),
    "The existing note-receive public key parity does not match the derived note-receive public key.",
  );
  if (recoveredSpendingIdentity) {
    const expectedRecoveredStorageKey = deriveLiquidBalanceStorageKey(
      recoveredSpendingIdentity.l2Address,
      context.workspace.liquidBalancesSlot,
    );
    expect(
      lifecycleEpoch.lifecycleStatus === "active",
      "--wallet-secret-path can only recover the spending key for an active wallet epoch.",
    );
    expect(
      ethers.toBigInt(getAddress(lifecycleEpoch.l2Address))
        === ethers.toBigInt(getAddress(recoveredSpendingIdentity.l2Address)),
      "The recovered spending key does not match the recovered wallet lifecycle L2 address.",
    );
    expect(
      ethers.toBigInt(normalizeBytes32Hex(lifecycleEpoch.channelTokenVaultKey))
        === ethers.toBigInt(normalizeBytes32Hex(expectedRecoveredStorageKey)),
      "The recovered spending key does not match the recovered wallet lifecycle storage key.",
    );
  }
  const l2Identity = recoveredSpendingIdentity ?? {
    l2PrivateKey: null,
    l2PublicKey: null,
    l2Address: getAddress(lifecycleEpoch.l2Address),
  };
  const storageKey = normalizeBytes32Hex(lifecycleEpoch.channelTokenVaultKey);

  const walletDir = walletEpochPath(walletName, context.workspace.network, lifecycleEpoch.epochId);
  const existingWallet = walletConfigExists(walletDir)
    ? loadWalletFromDir({
      walletName,
      networkName: context.workspace.network,
      walletDir,
    })
    : null;
  const status = existingWallet ? "already-recovered" : "recovered";
  const walletContext = existingWallet ?? ensureWallet({
    channelContext: context,
    signerAddress: signer.address,
    signerPrivateKey: signer.privateKey,
    l2Identity,
    walletSecret: noteReceiveKeyMaterial.privateKey,
    storageKey,
    leafIndex: lifecycleEpoch.leafIndex,
    noteReceiveKeyMaterial,
    lifecycleEpoch,
    rpcUrl,
  });
  if (existingWallet) {
    walletContext.wallet.noteReceivePrivateKey = noteReceiveKeyMaterial.privateKey;
    applyWalletLifecycleEpoch(walletContext.wallet, lifecycleEpoch);
    if (recoveredSpendingIdentity) {
      walletContext.wallet.l2PrivateKey = ethers.hexlify(recoveredSpendingIdentity.l2PrivateKey);
      walletContext.wallet.l2PublicKey = ethers.hexlify(recoveredSpendingIdentity.l2PublicKey);
      walletContext.wallet.l2Address = recoveredSpendingIdentity.l2Address;
      walletContext.wallet.l2DerivationMode = CHANNEL_BOUND_L2_DERIVATION_MODE;
      walletContext.wallet.l2DerivationChannelName = channelName;
      walletContext.wallet.l2StorageKey = storageKey;
    }
    persistWalletKeys(walletContext);
    persistWallet(walletContext);
    persistWalletIndexForContext(walletContext);
  }

  const noteScanStartBlock = args.fromGenesis === true
    ? Number(context.workspace.genesisBlockNumber)
    : walletNoteReceiveCursorDelta({
      walletContext,
      context,
      targetNextBlock: recoveryEventScan.scanRange.toBlock + 1,
    }).localNextBlock;
  const recoveredDeliveryState = await recoverDeliveredNotesFromCollectedLogs({
    walletContext,
    context,
    noteReceivePrivateKey: noteReceiveKeyMaterial.privateKey,
    logs: recoveryEventScan.deliveryLogs,
    storageObservationLogs: recoveryEventScan.storageObservationLogs,
    scanStartBlock: noteScanStartBlock,
    latestBlock: recoveryEventScan.scanRange.toBlock,
  });

  printJson({
    action: "wallet recover-workspace",
    status,
    wallet: walletName,
    walletDir: walletContext.walletDir,
    recoveredChannelWorkspace: channelContextResult.recoveredWorkspace,
    channelAutoRecoveryBlockDelta: channelContextResult.autoRecoveryBlockDelta,
    workspace: context.workspaceName,
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    spendingKeyRecovered: Boolean(recoveredSpendingIdentity),
    leafIndex: lifecycleEpoch.leafIndex.toString(),
    epochId: lifecycleEpoch.epochId,
    lifecycleStatus: lifecycleEpoch.lifecycleStatus,
    exitedAtTxHash: lifecycleEpoch.exitedAtTxHash,
    noteReceivePubKey: noteReceiveKeyMaterial.noteReceivePubKey,
    l2Nonce: walletContext.wallet.l2Nonce,
    recoveredFromLogs: recoveredDeliveryState.importedNotes,
    scannedDeliveryLogs: recoveredDeliveryState.scannedLogs,
    linkedEvidence: recoveredDeliveryState.linkedEvidence,
    noteReceiveScanRange: recoveredDeliveryState.scanRange,
  });
}

async function deriveRecoverWalletSpendingIdentity({
  args,
  signer,
  channelName,
  context,
  registration,
}) {
  if (args.walletSecretPath === undefined) {
    return null;
  }
  expect(
    registration.exists,
    [
      "--wallet-secret-path can only recover a spending key for an active channel registration.",
      "This account is not currently registered in the channel.",
      "Run wallet recover-workspace without --wallet-secret-path to recover viewing/evidence history for exited wallets.",
    ].join(" "),
  );
  const walletSecret = readWalletSecretSourceFile(args);
  const l2Identity = await deriveParticipantIdentityFromSigner({
    channelName,
    walletSecret,
    signer,
  });
  const expectedStorageKey = deriveLiquidBalanceStorageKey(
    l2Identity.l2Address,
    context.workspace.liquidBalancesSlot,
  );
  expect(
    walletRegistrationMatchesIdentity({ registration, l2Identity, expectedStorageKey }),
    "The recovered spending key does not match the current registered L2 address or channel token vault key.",
  );
  return l2Identity;
}

async function handleInstallZkEvm({ args }) {
  const installMode = args.readOnly === true
    ? PRIVATE_STATE_INSTALL_MODES.READ_ONLY
    : PRIVATE_STATE_INSTALL_MODES.FULL;
  const selectedVersions = installMode === PRIVATE_STATE_INSTALL_MODES.FULL
    ? await resolvePrivateStateInstallRuntimeVersions(args)
    : null;
  const tokamakCliRuntime = installMode === PRIVATE_STATE_INSTALL_MODES.FULL
    ? await installTokamakCliRuntimeForPrivateState({
      version: selectedVersions.tokamak,
      docker: Boolean(args.docker),
    })
    : null;
  const groth16Runtime = installMode === PRIVATE_STATE_INSTALL_MODES.FULL
    ? await installGroth16RuntimeForPrivateState({
      version: selectedVersions.groth16,
      docker: Boolean(args.docker),
    })
    : null;
  const localDeploymentBaseRoot = args.includeLocalArtifacts ? process.cwd() : null;
  const deploymentArtifacts = await installPrivateStateCliArtifacts({
    dappName: PRIVATE_STATE_DAPP_LABEL,
    installMode,
    localDeploymentBaseRoot,
    groth16CrsVersion: groth16Runtime?.compatibleBackendVersion ?? null,
  });
  const installManifest = writePrivateStateCliInstallManifest({
    installMode,
    dockerRequested: Boolean(args.docker),
    includeLocalArtifacts: Boolean(args.includeLocalArtifacts),
    localDeploymentBaseRoot,
    deploymentArtifacts,
    selectedVersions,
    tokamakCliRuntime,
    groth16Runtime,
  });
  printJson({
    action: "install",
    installMode,
    selectedVersions,
    tokamakCli: tokamakCliRuntime?.entryPath ?? null,
    runtimeRoot: tokamakCliRuntime?.runtimeRoot ?? null,
    tokamakCliRuntime,
    groth16Runtime,
    docker: Boolean(args.docker),
    includeLocalArtifacts: Boolean(args.includeLocalArtifacts),
    localDeploymentBaseRoot,
    deploymentArtifactCacheRoot: deploymentArtifacts.cacheBaseRoot,
    deploymentArtifactRoot: deploymentArtifacts.artifactRoot,
    installedDeploymentArtifacts: deploymentArtifacts.installed.map((entry) => ({
      chainId: entry.chainId,
      source: entry.source,
      bridgeTimestamp: entry.bridgeTimestamp,
      dappTimestamp: entry.dappTimestamp,
      artifactDir: entry.artifactDir,
    })),
    installManifestPath: installManifest.manifestPath,
  });
}

async function handleUninstall() {
  await requireUninstallConfirmation();

  const privateStateRoots = uniquePaths([
    path.resolve(os.homedir(), "tokamak-private-channels"),
    resolveArtifactCacheBaseRoot(),
  ]);
  const tokamakZkEvmRoot = resolveTokamakCliCacheRoot();
  const removedPrivateStateRoots = privateStateRoots.map((rootPath) =>
    removeManagedRoot({ label: "private-state-local-root", rootPath }),
  );
  const removedTokamakZkEvmRoot = removeManagedRoot({
    label: "tokamak-zk-evm-runtime-root",
    rootPath: tokamakZkEvmRoot,
  });
  const globalPackage = uninstallGlobalPrivateStateCliPackage();

  printJson({
    action: "uninstall",
    confirmationAccepted: true,
    removedPrivateStateRoots,
    removedTokamakZkEvmRoot,
    globalPackage,
  });
}

async function handleSetRpc({ args }) {
  const networkName = requireNetworkName(args);
  const network = {
    ...resolveCliNetwork(networkName),
    name: networkName,
  };
  const rpcUrl = requireArg(args.rpcUrl, "--rpc-url").trim();
  validateRpcUrl(rpcUrl, "--rpc-url");
  const rpcScanLimits = resolveRpcScanLimitsFromArgs(args);
  const provider = new JsonRpcProvider(rpcUrl, Number(network.chainId), { staticNetwork: true });
  await assertProviderChainIdMatchesNetwork({ provider, network, rpcUrl });
  const rpcConfig = writeRpcConfig(networkName, {
    RPC_URL: rpcUrl,
    RPC_PROVIDER: rpcScanLimits.provider ?? "custom",
    LOG_REQUESTS_PER_SECOND: rpcScanLimits.logRequestsPerSecond,
    LOG_CHUNK_SIZE: rpcScanLimits.blockRangeCap,
    RPC_BLOCK_RANGE_CAP: rpcScanLimits.blockRangeCap,
  });
  printJson({
    action: "set rpc",
    network: networkName,
    rpcConfigPath: rpcConfigEnvPath(networkName),
    rpcUrl: redactRpcUrl(rpcConfig.rpcUrl),
    provider: rpcConfig.provider,
    logRequestsPerSecond: rpcConfig.logRequestsPerSecond,
    logChunkSize: rpcConfig.logChunkSize,
    blockRangeCap: rpcConfig.blockRangeCap,
  });
}

async function requireUninstallConfirmation() {
  const prompt = [
    "This permanently deletes local private-state CLI workspaces, wallet secrets, installed private-state artifacts,",
    "the Groth16 workspace, and the Tokamak zk-EVM runtime workspace.",
    `Type exactly: ${PRIVATE_STATE_UNINSTALL_CONFIRMATION}`,
    "> ",
  ].join("\n");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stderr,
    terminal: process.stdin.isTTY && process.stderr.isTTY,
  });
  try {
    const answer = await rl.question(prompt);
    if (answer !== PRIVATE_STATE_UNINSTALL_CONFIRMATION) {
      throw new Error("Uninstall confirmation did not match. Nothing was deleted.");
    }
  } finally {
    rl.close();
  }
}

function uniquePaths(paths) {
  return [...new Set(paths.map((entry) => path.resolve(entry)))];
}

function backupWorkspaceForCleanRebuild({ workspaceDir, networkName, channelName }) {
  const resolvedWorkspaceDir = path.resolve(workspaceDir);
  if (!fs.existsSync(resolvedWorkspaceDir)) {
    return null;
  }
  expectPathWithinRoot(
    resolvedWorkspaceDir,
    workspaceRoot,
    `Clean rebuild refuses to move a path outside the private-state workspace root: ${resolvedWorkspaceDir}.`,
  );

  const backupRoot = path.join(
    privateStateCliDataRoot(),
    "workspace-rebuild-backups",
    slugifyPathComponent(networkName),
  );
  ensureDir(backupRoot);
  const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const backupBasePath = path.join(
    backupRoot,
    `${slugifyPathComponent(channelName)}-${timestamp}`,
  );
  const backupPath = nextAvailablePath(backupBasePath);
  fs.renameSync(resolvedWorkspaceDir, backupPath);
  return {
    workspaceDir: resolvedWorkspaceDir,
    backupPath,
    secretsPreserved: true,
  };
}

function persistChannelWorkspaceFiles({
  workspaceDir,
  channelDir,
  workspace,
  currentSnapshot,
  blockInfo,
  contractCodes,
}) {
  ensureDir(channelDir);
  ensureDir(channelWorkspaceCurrentPath(workspaceDir));
  ensureDir(channelWorkspaceOperationsPath(workspaceDir));
  ensureDir(workspaceWalletsDir(workspaceDir));

  writeJsonIfChanged(path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.json"), currentSnapshot);
  writeJsonIfChanged(
    path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.normalized.json"),
    currentSnapshot,
  );
  writeJsonIfChanged(path.join(channelWorkspaceCurrentPath(workspaceDir), "block_info.json"), blockInfo);
  writeJsonIfChanged(path.join(channelWorkspaceCurrentPath(workspaceDir), "contract_codes.json"), contractCodes);
  writeJsonIfChanged(channelWorkspaceConfigPath(workspaceDir), workspace);
}

function channelWorkspaceRpcCallHistoryPath(workspaceDir) {
  return path.join(channelDataPath(workspaceDir), "rpcCallHistory");
}

function createRpcCallHistoryRecorder({ workspaceDir }) {
  const historyDir = channelWorkspaceRpcCallHistoryPath(workspaceDir);
  const entriesByFile = new Map();
  let scanRange = null;
  let callCount = 0;
  ensureDir(historyDir);

  const pushEntry = ({ method, eventName = null, entry }) => {
    const file = rpcCallHistoryFileName(method, eventName);
    const entries = entriesByFile.get(file) ?? [];
    entries.push({
      method,
      ...(eventName ? { event: eventName } : {}),
      ...entry,
    });
    entriesByFile.set(file, entries);
  };

  return {
    historyDir,
    setScanRange(nextScanRange) {
      scanRange = {
        fromBlock: Number(nextScanRange.fromBlock),
        toBlock: Number(nextScanRange.toBlock),
        ...(nextScanRange.mode ? { mode: nextScanRange.mode } : {}),
      };
    },
    recordRpcCall({ method, params, response, error = null }) {
      if (method === "eth_getLogs") {
        return;
      }
      callCount += 1;
      pushEntry({
        method,
        entry: {
          recordedAt: new Date().toISOString(),
          request: buildRawJsonRpcRequest(method, params),
          ...(error ? { error } : { response }),
        },
      });
    },
    recordEthGetLogs({ request, logs, groupedValues, chunkFromBlock, chunkToBlock }) {
      callCount += 1;
      const eventBuckets = groupRawEthGetLogsByRecoveryEvent({ logs, groupedValues });
      for (const [eventName, response] of eventBuckets.entries()) {
        pushEntry({
          method: "eth_getLogs",
          eventName,
          entry: {
            recordedAt: new Date().toISOString(),
            chunkRange: { fromBlock: Number(chunkFromBlock), toBlock: Number(chunkToBlock) },
            request: buildRawEthGetLogsRequest(request),
            response,
          },
        });
      }
    },
    finish() {
      const files = [...entriesByFile.entries()].map(([file, entries]) =>
        appendRpcCallHistoryEntries({
          historyDir,
          file,
          entries: entries.map((entry) => ({ scanRange, ...entry })),
        }));
      return {
        historyDir,
        scanRange,
        callCount,
        files: files.sort((left, right) => left.file.localeCompare(right.file)),
      };
    },
  };
}

function attachRpcCallHistoryRecorderToProvider(provider, recorder) {
  const send = provider.send.bind(provider);
  provider.send = async (method, params) => {
    try {
      const response = await send(method, params);
      recorder.recordRpcCall({ method, params, response });
      return response;
    } catch (error) {
      recorder.recordRpcCall({ method, params, error: normalizeRpcCallHistoryError(error) });
      throw error;
    }
  };
  return provider;
}

function normalizeRpcCallHistoryError(error) {
  return {
    name: error?.name ?? "Error",
    code: error?.code ?? null,
    message: error?.message ?? String(error),
  };
}

function appendRpcCallHistoryEntries({ historyDir, file, entries }) {
  const filePath = path.join(historyDir, file);
  const { method, event: eventName = null } = entries[0];
  const current = readJsonIfExists(filePath) ?? {
    method,
    ...(eventName ? { event: eventName } : {}),
    entries: [],
  };
  expect(current.method === method, `RPC call history file method mismatch: ${filePath}.`);
  expect(Array.isArray(current.entries), `RPC call history file entries must be an array: ${filePath}.`);
  if (eventName) {
    expect(current.event === eventName, `RPC call history file event mismatch: ${filePath}.`);
  }
  current.updatedAt = new Date().toISOString();
  current.entries.push(...entries);
  writeJson(filePath, current);
  return {
    method,
    ...(eventName ? { event: eventName } : {}),
    file,
    path: filePath,
    entriesAdded: entries.length,
    totalEntries: current.entries.length,
  };
}

function buildRawJsonRpcRequest(method, params = []) {
  return {
    jsonrpc: "2.0",
    method,
    params: params ?? [],
  };
}

function rpcCallHistoryFileName(method, eventName = null) {
  const suffix = eventName ? `.${safeRpcCallHistoryFileToken(eventName)}` : "";
  return `${safeRpcCallHistoryFileToken(method)}${suffix}.json`;
}

function safeRpcCallHistoryFileToken(value) {
  return String(value).replace(/[^A-Za-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "") || "unknown";
}

function groupRawEthGetLogsByRecoveryEvent({ logs, groupedValues }) {
  if (logs.length === 0) {
    return new Map([["noLogs", []]]);
  }
  const eventNamesByLog = new Map();
  for (const group of groupedValues) {
    for (const event of group) {
      eventNamesByLog.set(recoveryLogHistoryKey(event), channelRecoveryEventName(event));
    }
  }
  const buckets = new Map();
  for (const log of logs) {
    const eventName = eventNamesByLog.get(recoveryLogHistoryKey(log)) ?? "unknown";
    const bucket = buckets.get(eventName) ?? [];
    bucket.push(log);
    buckets.set(eventName, bucket);
  }
  return buckets;
}

function recoveryLogHistoryKey(log) {
  return `${normalizeBytes32Hex(log.transactionHash)}:${Number(log.index ?? log.logIndex)}`;
}

function channelRecoveryEventName(event) {
  if (event.fragment?.name) {
    return event.fragment.name;
  }
  const topic0 = event.topics[0] ? normalizeBytes32Hex(event.topics[0]) : null;
  if (topic0 === normalizeBytes32Hex(CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC)) {
    return "StorageKeyObserved";
  }
  if (topic0 === normalizeBytes32Hex(VAULT_STORAGE_WRITE_OBSERVED_TOPIC)) {
    return "LiquidBalanceStorageWriteObserved";
  }
  return "unknown";
}

function buildRawEthGetLogsRequest(request) {
  const filter = {
    address: request.address,
    topics: request.topics,
    fromBlock: ethers.toQuantity(request.fromBlock),
    toBlock: ethers.toQuantity(request.toBlock),
  };
  return buildRawJsonRpcRequest("eth_getLogs", [filter]);
}

function nextAvailablePath(basePath) {
  if (!fs.existsSync(basePath)) {
    return basePath;
  }
  for (let index = 1; index <= 1000; index += 1) {
    const candidate = `${basePath}-${index}`;
    if (!fs.existsSync(candidate)) {
      return candidate;
    }
  }
  throw new Error(`Unable to allocate a clean rebuild backup path for ${basePath}.`);
}

function removeManagedRoot({ label, rootPath }) {
  const resolvedPath = path.resolve(rootPath);
  try {
    assertSafeManagedRoot(resolvedPath, label);
  } catch (error) {
    return {
      label,
      path: resolvedPath,
      existed: fs.existsSync(resolvedPath),
      removed: false,
      error: error.message,
    };
  }
  const existed = fs.existsSync(resolvedPath);
  if (existed) {
    fs.rmSync(resolvedPath, { recursive: true, force: true });
  }
  return {
    label,
    path: resolvedPath,
    existed,
    removed: existed && !fs.existsSync(resolvedPath),
  };
}

function assertSafeManagedRoot(rootPath, label) {
  const protectedPaths = new Set([
    path.resolve(os.homedir()),
    path.parse(rootPath).root,
    path.resolve(defaultCommandCwd),
    path.resolve(privateStateCliPackageRoot),
  ]);
  if (protectedPaths.has(rootPath)) {
    throw new Error(`Refusing to delete protected ${label}: ${rootPath}`);
  }
}

function npmCommandName() {
  return process.platform === "win32" ? "npm.cmd" : "npm";
}

function inspectGlobalPrivateStateCliPackage() {
  const list = runCaptured(npmCommandName(), ["ls", "-g", PRIVATE_STATE_CLI_PACKAGE_NAME, "--depth=0", "--json"]);
  const report = parseJsonReport(list.stdout);
  const packageReport = report?.dependencies?.[PRIVATE_STATE_CLI_PACKAGE_NAME] ?? null;
  const installed = Boolean(packageReport);
  if (!installed) {
    const missing = /empty|missing|not found|not installed/iu.test(`${list.stdout}\n${list.stderr}`);
    return {
      installed: false,
      version: null,
      status: list.status,
      reason: missing || report ? "global package is not installed" : "unable to inspect global npm package",
      stderr: stripAnsi(list.stderr).trim(),
    };
  }
  return {
    installed: true,
    version: packageReport.version ?? null,
    status: list.status,
  };
}

function uninstallGlobalPrivateStateCliPackage() {
  const inspection = inspectGlobalPrivateStateCliPackage();
  if (!inspection.installed) {
    return {
      attempted: false,
      installed: false,
      reason: inspection.reason,
      status: inspection.status,
      stderr: inspection.stderr,
    };
  }
  const uninstall = runCaptured(npmCommandName(), ["uninstall", "-g", PRIVATE_STATE_CLI_PACKAGE_NAME]);
  return {
    attempted: true,
    installed: true,
    removed: uninstall.status === 0,
    status: uninstall.status,
    stdout: stripAnsi(uninstall.stdout).trim(),
    stderr: stripAnsi(uninstall.stderr).trim(),
  };
}

async function handleUpdate() {
  const currentVersion = privateStateCliPackageJson.version;
  const latestVersion = await fetchLatestPrivateStateCliVersion();
  const registryComparison = compareSemver(currentVersion, latestVersion);
  const globalPackage = inspectGlobalPrivateStateCliPackage();
  const runningFromRepositoryCheckout = isRepositoryCliPackageRoot(privateStateCliPackageRoot);
  const updateAvailable = registryComparison < 0;

  const result = {
    action: "update",
    packageName: PRIVATE_STATE_CLI_PACKAGE_NAME,
    currentVersion,
    latestVersion,
    updateAvailable,
    registryState: registryComparison > 0 ? "local-version-ahead-of-registry" : "normal",
    runningFromRepositoryCheckout,
    globalPackage,
    attempted: false,
    updated: false,
    command: `npm install -g ${PRIVATE_STATE_CLI_PACKAGE_NAME}@latest`,
  };

  if (!updateAvailable) {
    printJson(result);
    return;
  }

  if (runningFromRepositoryCheckout) {
    printJson({
      ...result,
      reason: "running from a repository checkout; update the checkout with git/npm instead of mutating source files",
    });
    return;
  }

  if (!globalPackage.installed) {
    printJson({
      ...result,
      reason: "global npm package is not installed; install or update the CLI with the printed command",
    });
    return;
  }

  const install = runCaptured(npmCommandName(), ["install", "-g", `${PRIVATE_STATE_CLI_PACKAGE_NAME}@latest`]);
  if (install.status !== 0) {
    throw new Error([
      `Unable to update ${PRIVATE_STATE_CLI_PACKAGE_NAME} to ${latestVersion}.`,
      stripAnsi(install.stderr || install.stdout).trim(),
    ].filter(Boolean).join(" "));
  }
  printJson({
    ...result,
    attempted: true,
    updated: true,
    installedVersion: latestVersion,
    stdout: stripAnsi(install.stdout).trim(),
    stderr: stripAnsi(install.stderr).trim(),
  });
}

async function fetchLatestPrivateStateCliVersion() {
  const url = `https://registry.npmjs.org/${encodeURIComponent(PRIVATE_STATE_CLI_PACKAGE_NAME)}/latest`;
  const response = await fetch(url, {
    redirect: "follow",
    signal: typeof globalThis.AbortSignal?.timeout === "function" ? globalThis.AbortSignal.timeout(10_000) : undefined,
  });
  if (!response.ok) {
    throw new Error(`Unable to fetch ${PRIVATE_STATE_CLI_PACKAGE_NAME} latest version from npm registry: HTTP ${response.status}.`);
  }
  const metadata = await response.json();
  const version = metadata?.version;
  if (typeof version !== "string" || version.trim() === "") {
    throw new Error(`npm registry response for ${PRIVATE_STATE_CLI_PACKAGE_NAME} did not include a version.`);
  }
  return version;
}

function compareSemver(left, right) {
  const parse = (value) => String(value).split("-", 1)[0].split(".").map((part) => {
    const parsed = Number.parseInt(part, 10);
    return Number.isFinite(parsed) ? parsed : 0;
  });
  const leftParts = parse(left);
  const rightParts = parse(right);
  const length = Math.max(leftParts.length, rightParts.length);
  for (let index = 0; index < length; index += 1) {
    const delta = (leftParts[index] ?? 0) - (rightParts[index] ?? 0);
    if (delta !== 0) {
      return delta < 0 ? -1 : 1;
    }
  }
  return 0;
}

function isRepositoryCliPackageRoot(packageRoot) {
  const segments = path.resolve(packageRoot).split(path.sep);
  const suffix = ["packages", "apps", "private-state", "cli"];
  return suffix.every((segment, index) => segments[segments.length - suffix.length + index] === segment);
}

async function handleDoctor({ args }) {
  const report = buildDoctorReport({ probeGpu: args.gpu === true });
  if (isJsonOutputRequested()) {
    printJson(report);
  } else {
    printDoctorHumanReport(report);
  }
  if (!report.ok) {
    process.exitCode = 1;
  }
}

function handleObserver() {
  printJson({
    action: "observer",
    url: PRIVATE_STATE_OBSERVER_URL,
    scope: "Public monitoring observer for Tokamak Private App Channels and the private-state DApp.",
    notes: [
      "The observer helps users and reviewers inspect public monitoring surfaces.",
      "The observer does not receive wallet secrets, spending keys, viewing keys, or private note plaintext.",
    ],
  });
}

function handleInvestigator() {
  const htmlPath = resolveInvestigatorIndexPath();
  const fileUrl = pathToFileURL(htmlPath).href;
  const browser = openFileInDefaultBrowser(fileUrl);
  printJson({
    action: "investigator",
    htmlPath,
    fileUrl,
    browserOpened: browser.opened,
    browserOpenCommand: browser.command,
    browserOpenError: browser.error,
    nextSteps: [
      "Create a raw evidence ZIP with wallet get-notes --export-evidence and --acknowledge-full-note-plaintext-export.",
      "Load the raw evidence ZIP in the browser investigator.",
      "Filter the raw bundle and export a user-consent disclosure ZIP.",
      "Do not submit the raw evidence ZIP unless full wallet-history disclosure is intended.",
    ],
  });
}

function resolveInvestigatorIndexPath() {
  const candidates = [
    path.join(privateStateCliPackageRoot, "investigator", "index.html"),
  ];
  const htmlPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!htmlPath) {
    throw new Error(
      [
        "Missing investigator HTML asset.",
        `Checked: ${candidates.join(", ")}`,
        "Reinstall the private-state CLI package or run from a complete repository checkout.",
      ].join(" "),
    );
  }
  return htmlPath;
}

function openFileInDefaultBrowser(fileUrl) {
  const opener = defaultBrowserOpenCommand(fileUrl);
  const result = spawnSync(opener.command, opener.args, {
    stdio: "ignore",
    windowsHide: true,
  });
  return {
    command: [opener.command, ...opener.args].join(" "),
    opened: result.status === 0,
    status: result.status,
    error: result.error?.message ?? null,
  };
}

function defaultBrowserOpenCommand(fileUrl) {
  if (process.platform === "darwin") {
    return { command: "open", args: [fileUrl] };
  }
  if (process.platform === "win32") {
    return { command: "cmd", args: ["/c", "start", "", fileUrl] };
  }
  return { command: "xdg-open", args: [fileUrl] };
}

async function handleTransactionFees({ network, provider, rpcUrl }) {
  const feeAsset = loadTransactionFeeAsset();
  const feeData = await provider.getFeeData();
  const gasPrices = requireTransactionFeeGasPrices(feeData);
  const ethUsd = await fetchEthUsdPrice();
  const rows = buildTransactionFeeRows({
    commands: feeAsset.commands,
    typicalGasPriceWei: gasPrices.typical,
    worstCaseGasPriceWei: gasPrices.worstCase,
    ethUsd,
  });

  printJson({
    action: "transaction-fees",
    generatedAt: new Date().toISOString(),
    network: network.name,
    chainId: Number(network.chainId),
    rpcUrl,
    asset: {
      schema: feeAsset.schema,
      measuredAt: feeAsset.measuredAt,
      measurementBasis: feeAsset.measurementBasis,
      notes: feeAsset.notes,
    },
    livePricing: {
      typicalGasPriceWei: gasPrices.typical.toString(),
      typicalGasPriceGwei: formatGwei(gasPrices.typical),
      typicalGasPriceSource: gasPrices.typicalSource,
      worstCaseGasPriceWei: gasPrices.worstCase.toString(),
      worstCaseGasPriceGwei: formatGwei(gasPrices.worstCase),
      worstCaseGasPriceSource: gasPrices.worstCaseSource,
      maxFeePerGasWei: feeData.maxFeePerGas?.toString() ?? null,
      maxPriorityFeePerGasWei: feeData.maxPriorityFeePerGas?.toString() ?? null,
      gasPriceWei: feeData.gasPrice?.toString() ?? null,
      ethUsd,
      ethUsdSource: "CoinGecko simple price API",
    },
    rows,
  });
}

function loadTransactionFeeAsset() {
  const assetPath = path.join(privateStateCliPackageRoot, "assets", "tx-fees.json");
  const asset = readJson(assetPath);
  expect(asset.schema === "tokamak-private-state-cli-tx-fees.v1", `Unsupported transaction fee asset schema: ${assetPath}`);
  expect(Array.isArray(asset.commands), `Transaction fee asset is missing commands: ${assetPath}`);
  return asset;
}

function requireTransactionFeeGasPrices(feeData) {
  const typical = feeData.gasPrice ?? feeData.maxFeePerGas;
  const worstCase = feeData.maxFeePerGas ?? feeData.gasPrice;
  if (typical === null || typical === undefined || worstCase === null || worstCase === undefined) {
    throw new Error("RPC provider did not return gasPrice or maxFeePerGas.");
  }
  return {
    typical: ethers.toBigInt(typical),
    typicalSource: feeData.gasPrice ? "gasPrice" : "maxFeePerGas",
    worstCase: ethers.toBigInt(worstCase),
    worstCaseSource: feeData.maxFeePerGas ? "maxFeePerGas" : "gasPrice",
  };
}

async function fetchEthUsdPrice() {
  const url = "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd";
  const response = await fetch(url, {
    headers: {
      accept: "application/json",
      "user-agent": `${privateStateCliPackageJson.name}/${privateStateCliPackageJson.version}`,
    },
  });
  if (!response.ok) {
    throw new Error(`Unable to fetch live ETH/USD price from CoinGecko: HTTP ${response.status}.`);
  }
  const payload = await response.json();
  const value = Number(payload?.ethereum?.usd);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error("CoinGecko response did not include a valid ethereum.usd price.");
  }
  return value;
}

function buildTransactionFeeRows({ commands, typicalGasPriceWei, worstCaseGasPriceWei, ethUsd }) {
  return commands.map((entry) => {
    const transactions = expectTransactionFeeTransactions(entry);
    const gasUsed = transactions.reduce((sum, transaction) => sum + Number(transaction.gasUsed), 0);
    const typicalEth = ethers.formatEther(BigInt(gasUsed) * typicalGasPriceWei);
    const worstCaseEth = ethers.formatEther(BigInt(gasUsed) * worstCaseGasPriceWei);
    return {
      command: entry.command,
      description: entry.description,
      transactions: transactions.map((transaction) => transaction.label).join(" + "),
      gasUsed,
      typicalGasPriceGwei: formatGwei(typicalGasPriceWei),
      typicalEth: formatEthForDisplay(typicalEth),
      typicalUsd: formatUsdForDisplay(Number(typicalEth) * ethUsd),
      worstCaseGasPriceGwei: formatGwei(worstCaseGasPriceWei),
      worstCaseEth: formatEthForDisplay(worstCaseEth),
      worstCaseUsd: formatUsdForDisplay(Number(worstCaseEth) * ethUsd),
      sources: [...new Set(transactions.map((transaction) => transaction.source))].join(", "),
      sourceDetails: transactions.map((transaction) => transaction.sourceDetail),
    };
  });
}

function expectTransactionFeeTransactions(entry) {
  expect(typeof entry?.command === "string" && entry.command.length > 0, "Transaction fee asset contains a command without command name.");
  expect(Array.isArray(entry.transactions) && entry.transactions.length > 0, `Transaction fee asset command ${entry.command} has no transactions.`);
  for (const transaction of entry.transactions) {
    expect(Number.isInteger(transaction.gasUsed) && transaction.gasUsed > 0, `Transaction fee asset command ${entry.command} has invalid gasUsed.`);
  }
  return entry.transactions;
}

function formatGwei(wei) {
  return trimFixedNumber(ethers.formatUnits(wei, "gwei"), 6);
}

function formatEthForDisplay(value) {
  return trimFixedNumber(value, 8);
}

function formatUsdForDisplay(value) {
  if (value > 0 && value < 0.01) {
    return "<0.01";
  }
  return value.toFixed(2);
}

function trimFixedNumber(value, maxDecimals) {
  const [integer, decimals = ""] = String(value).split(".");
  if (!decimals || maxDecimals <= 0) {
    return integer;
  }
  const trimmed = decimals.slice(0, maxDecimals).replace(/0+$/u, "");
  return trimmed ? `${integer}.${trimmed}` : integer;
}

function handleAccountGetL1Address({ args }) {
  const signer = requireL1Signer(args);
  printJson({
    action: "account get-l1-address",
    l1Address: signer.address,
    account: args.account ?? null,
  });
}

function handleAccountImport({ args }) {
  const networkName = requireNetworkName(args);
  resolveCliNetwork(networkName);
  const account = requireAccountName(args);
  const privateKey = resolveStandalonePrivateKeySource(args);
  const signer = new Wallet(privateKey);
  const privateKeyPath = accountPrivateKeyPath(networkName, account);
  const metadataPath = accountMetadataPath(networkName, account);
  if (fs.existsSync(privateKeyPath)) {
    throw new Error(
      `Account secret already exists at ${privateKeyPath}. Remove it manually before importing a different key.`,
    );
  }
  writeSecretFile(privateKeyPath, privateKey);
  writeJsonWithMode(metadataPath, {
    account,
    network: networkName,
    l1Address: getAddress(signer.address),
    privateKeyPath,
  }, 0o600);
  printJson({
    action: "account import",
    account,
    network: networkName,
    l1Address: getAddress(signer.address),
    privateKeySource: "account-default",
    privateKeyPath,
  });
}

function handleListLocalWallets({ args }) {
  const networkFilter = args.network ? requireNetworkName(args) : null;
  if (networkFilter) {
    resolveCliNetwork(networkFilter);
  }
  const channelFilter = args.channelName ? slugifyPathComponent(requireArg(args.channelName, "--channel-name")) : null;
  const wallets = listLocalWallets({
    networkFilter,
    channelFilter,
  });

  printJson({
    action: "wallet list",
    workspaceRoot,
    filters: {
      network: networkFilter,
      channelName: args.channelName ?? null,
    },
    wallets,
  });
}

function handleWalletExportBackup({ args }) {
  const outputPath = path.resolve(String(requireArg(args.output, "--output")));
  expect(!fs.existsSync(outputPath), `Export output already exists: ${outputPath}.`);
  ensureDir(path.dirname(outputPath));

  const wallets = [resolveExportWalletInfo({
    networkName: requireNetworkName(args),
    walletName: requireWalletName(args),
  })];

  expect(
    wallets.length > 0,
    "No local wallet is available to export.",
  );

  const archive = new AdmZip();
  const files = new Map();
  const exportedWallets = [];
  for (const wallet of wallets) {
    const normalized = normalizeExportWalletInfo(wallet);
    exportedWallets.push({
      network: normalized.network,
      channelName: normalized.channelName,
      wallet: normalized.wallet,
    });
    for (const filePath of walletBackupExportFilePaths(normalized)) {
      const archivePath = archivePathForLocalCliFile(filePath);
      if (!files.has(archivePath)) {
        files.set(archivePath, filePath);
      }
    }
  }

  const manifest = {
    format: WALLET_BACKUP_EXPORT_FORMAT,
    formatVersion: WALLET_EXPORT_FORMAT_VERSION,
    createdAt: new Date().toISOString(),
    cliPackage: PRIVATE_STATE_CLI_PACKAGE_NAME,
    cliVersion: privateStateCliPackageJson.version,
    exportMode: "backup",
    notes: [
      "Includes wallet note-tracking metadata, public key metadata, and channel workspace cache.",
      "Excludes spending keys, viewing keys, key derivation material, owner, value, and salt.",
    ],
    wallets: exportedWallets,
    files: [...files.keys()].sort(),
  };

  archive.addFile("manifest.json", Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8"));
  for (const archivePath of manifest.files) {
    const filePath = files.get(archivePath);
    validateBackupExportFile(filePath);
    archive.addFile(archivePath, fs.readFileSync(filePath));
  }
  archive.writeZip(outputPath);
  protectSecretFile(outputPath, "wallet export ZIP");

  printJson({
    action: "wallet export backup",
    output: outputPath,
    exportMode: manifest.exportMode,
    walletCount: exportedWallets.length,
    fileCount: manifest.files.length,
    wallets: exportedWallets.map(({ network, channelName, wallet }) => ({ network, channelName, wallet })),
  });
}

function handleWalletExportKey({ args, keyKind }) {
  const outputPath = path.resolve(String(requireArg(args.output, "--output")));
  expect(!fs.existsSync(outputPath), `Export output already exists: ${outputPath}.`);
  ensureDir(path.dirname(outputPath));
  const networkName = requireNetworkName(args);
  const walletName = requireWalletName(args);
  const wallet = loadWallet(walletName, networkName);
  const secretPath = keyKind === "spending"
    ? walletSpendingKeySecretPath(networkName, walletName)
    : walletViewingKeySecretPath(networkName, walletName);
  expect(fs.existsSync(secretPath), `Wallet ${walletName} is missing its ${keyKind} key.`);
  const payload = JSON.parse(readSecretFile(secretPath, `${keyKind} key`));
  validateWalletKeyPayload(payload, keyKind);
  fs.writeFileSync(outputPath, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
  protectSecretFile(outputPath, `${keyKind} key export`);
  printJson({
    action: `wallet export ${keyKind}-key`,
    wallet: wallet.walletName,
    network: networkName,
    output: outputPath,
    keyKind,
    metadata: payload.metadata,
  });
}

function handleWalletImportBackup({ args }) {
  const inputPath = path.resolve(String(requireArg(args.input, "--input")));
  expect(fs.existsSync(inputPath), `Import ZIP does not exist: ${inputPath}.`);

  const { archive, manifest } = readWalletImportArchive(inputPath);

  const archiveFiles = new Set(manifest.files);
  for (const entry of archive.getEntries()) {
    if (entry.isDirectory) {
      continue;
    }
    expect(
      entry.entryName === "manifest.json" || archiveFiles.has(entry.entryName),
      `Unexpected file in wallet import ZIP: ${entry.entryName}.`,
    );
  }

  const targetRoot = privateStateCliDataRoot();
  ensureDir(targetRoot);
  const plannedWrites = manifest.files.map((archivePath) => {
    validateWalletArchivePath(archivePath);
    const entry = archive.getEntry(archivePath);
    expect(entry && !entry.isDirectory, `Wallet import ZIP is missing ${archivePath}.`);
    const targetPath = path.resolve(targetRoot, archivePath);
    expectPathWithinRoot(targetPath, targetRoot, `Unsafe import target for ${archivePath}.`);
    expect(!fs.existsSync(targetPath), `Refusing to overwrite existing file: ${targetPath}.`);
    return {
      archivePath,
      targetPath,
      data: entry.getData(),
    };
  });

  commitWalletImportFiles({ targetRoot, plannedWrites });

  printJson({
    action: "wallet import backup",
    input: inputPath,
    exportMode: manifest.exportMode,
    walletCount: manifest.wallets.length,
    fileCount: plannedWrites.length,
    wallets: manifest.wallets.map(({ network, channelName, wallet }) => ({ network, channelName, wallet })),
    nextStep: "Import viewing-key and spending-key files separately when the wallet needs those capabilities.",
  });
}

function handleWalletImportKey({ args, keyKind }) {
  const inputPath = path.resolve(String(requireArg(args.input, "--input")));
  expect(fs.existsSync(inputPath), `Key import file does not exist: ${inputPath}.`);
  const payload = JSON.parse(readImportSecretSourceFile(inputPath, "--input"));
  validateWalletKeyPayload(payload, keyKind);
  const metadata = payload.metadata;
  const networkName = requireNetworkName({ network: metadata.network });
  const walletName = requireWalletName({ wallet: metadata.wallet });
  const targetPath = keyKind === "spending"
    ? walletSpendingKeySecretPath(networkName, walletName)
    : walletViewingKeySecretPath(networkName, walletName);
  expect(!fs.existsSync(targetPath), `Refusing to overwrite existing ${keyKind} key: ${targetPath}.`);
  writeSecretFile(targetPath, JSON.stringify(payload, null, 2));
  const walletRoot = walletRootPath(walletName, networkName);
  const walletIndex = fs.existsSync(walletRoot)
    ? requireWalletIndex({ walletRoot, walletName, networkName })
    : null;
  const selectedEpoch = walletIndex ? selectedWalletEpoch(walletIndex, walletName, networkName) : null;
  if (selectedEpoch) {
    const walletDir = walletEpochPathFromRoot(walletRoot, selectedEpoch.epochId);
    const metadataPath = keyKind === "spending"
      ? walletSpendingKeyMetadataPath(walletDir)
      : walletViewingKeyMetadataPath(walletDir);
    if (fs.existsSync(metadataPath)) {
      expect(
        JSON.stringify(readJson(metadataPath)) === JSON.stringify(normalizeCliOutput(metadata)),
        `Refusing to overwrite mismatched ${keyKind} key metadata: ${metadataPath}.`,
      );
    } else {
      writeJson(metadataPath, metadata);
    }
  }
  printJson({
    action: `wallet import ${keyKind}-key`,
    input: inputPath,
    network: networkName,
    wallet: walletName,
    keyKind,
    metadata,
  });
}

function readWalletImportArchive(inputPath) {
  try {
    const archive = new AdmZip(inputPath);
    const manifestEntry = archive.getEntry("manifest.json");
    expect(manifestEntry, "Wallet import ZIP is missing manifest.json.");
    const manifest = JSON.parse(manifestEntry.getData().toString("utf8"));
    validateWalletExportManifest(manifest);
    return { archive, manifest };
  } catch (error) {
    throw new Error(`Failed to read wallet import ZIP ${inputPath}: ${error.message}`);
  }
}

function validateBackupExportFile(filePath) {
  if (path.basename(filePath) !== "wallet-notes.metadata.json") {
    return;
  }
  const metadata = readJson(filePath);
  const forbidden = findForbiddenBackupMetadataPaths(metadata);
  expect(
    forbidden.length === 0,
    `wallet export backup refuses to export plaintext note secrets or key material: ${forbidden.join(", ")}.`,
  );
}

function findForbiddenBackupMetadataPaths(value, pathParts = []) {
  const forbiddenNames = new Set([
    "owner",
    "value",
    "salt",
    "l1PrivateKey",
    "l2PrivateKey",
    "noteReceivePrivateKey",
    "walletSecret",
    "seedSignature",
  ]);
  if (Array.isArray(value)) {
    return value.flatMap((entry, index) => findForbiddenBackupMetadataPaths(entry, [...pathParts, String(index)]));
  }
  if (!value || typeof value !== "object") {
    return [];
  }
  const found = [];
  for (const [key, entry] of Object.entries(value)) {
    const nextPath = [...pathParts, key];
    if (forbiddenNames.has(key) && entry !== undefined && entry !== null) {
      found.push(nextPath.join("."));
      continue;
    }
    found.push(...findForbiddenBackupMetadataPaths(entry, nextPath));
  }
  return found;
}

function commitWalletImportFiles({ targetRoot, plannedWrites }) {
  const stagingRoot = fs.mkdtempSync(path.join(targetRoot, ".wallet-import-"));
  const committedPaths = [];
  try {
    for (const write of plannedWrites) {
      write.stagingPath = path.resolve(stagingRoot, write.archivePath);
      expectPathWithinRoot(write.stagingPath, stagingRoot, `Unsafe staging target for ${write.archivePath}.`);
      ensureDir(path.dirname(write.stagingPath));
      fs.writeFileSync(write.stagingPath, write.data);
      applyImportedWalletFileMode(write.archivePath, write.stagingPath);
    }

    for (const write of plannedWrites) {
      expect(!fs.existsSync(write.targetPath), `Refusing to overwrite existing file: ${write.targetPath}.`);
    }

    for (const write of plannedWrites) {
      ensureDir(path.dirname(write.targetPath));
      fs.renameSync(write.stagingPath, write.targetPath);
      committedPaths.push(write.targetPath);
    }
  } catch (error) {
    for (const committedPath of committedPaths.reverse()) {
      fs.rmSync(committedPath, { force: true });
    }
    throw error;
  } finally {
    fs.rmSync(stagingRoot, { recursive: true, force: true });
  }
}

async function handleGuide({ args }) {
  const guide = {
    action: "guide",
    generatedAt: new Date().toISOString(),
    selectors: {
      network: args.network ?? null,
      channelName: args.channelName ?? null,
      account: args.account ?? null,
      wallet: args.wallet ?? null,
    },
    checks: [],
    state: {},
    nextSafeAction: null,
    why: null,
    candidateCommands: [],
    privacyTip: "For wallet mint-notes, wallet transfer-notes, and wallet redeem-notes, add --tx-submitter <ACCOUNT> to let a separate local L1 account submit executeChannelTransaction and pay gas.",
    mirrorTip: "Channel leaders refresh mirror files with channel recover-workspace --publish-workspace-mirror --leader-account <ACCOUNT> --output <PATH>; the standalone channel publish-workspace-mirror command is no longer available.",
  };

  guide.state.local = inspectGuideLocalState(args);
  guide.checks.push(guideCheck(
    "local private-state workspace",
    guide.state.local.workspaceRootExists || guide.state.local.secretRootExists ? "ok" : "missing",
    {
      workspaceRoot,
      secretRoot,
      workspaceNetworks: guide.state.local.workspaceNetworks,
      secretNetworks: guide.state.local.secretNetworks,
    },
  ));
  if (guide.state.local.walletSelectorError) {
    guide.checks.push(guideCheck("wallet selector", "error", {
      wallet: args.wallet,
      error: guide.state.local.walletSelectorError,
    }));
  }

  if (!args.network) {
    setGuideNextAction(guide, {
      command: "help guide --network <NAME>",
      why: "Select a network before the guide can inspect RPC, deployment artifacts, channels, accounts, or wallets.",
      candidates: [
        "help guide --network mainnet",
        "help guide --network sepolia",
        "help guide --network anvil",
      ],
    });
    printJson(guide);
    return;
  }

  const networkName = requireNetworkName(args);
  const networkRuntime = inspectGuideNetworkRuntime(networkName);
  guide.state.network = networkRuntime.state;
  guide.checks.push(networkRuntime.check);
  if (!networkRuntime.network) {
    setGuideNextAction(guide, {
      command: "help guide --network <NAME>",
      why: `The requested network ${networkName} is not supported by the CLI network config.`,
    });
    printJson(guide);
    return;
  }

  const artifactState = inspectGuideDeploymentArtifacts(networkRuntime.network.chainId);
  guide.state.deploymentArtifacts = artifactState;
  guide.checks.push(guideCheck(
    "installed deployment artifacts",
    artifactState.readOnlyInstalled ? "ok" : "missing",
    {
      chainId: networkRuntime.network.chainId,
      rootDir: artifactState.rootDir,
      missingFiles: artifactState.readOnlyMissingFiles,
      fullMissingFiles: artifactState.fullMissingFiles,
    },
  ));
  if (artifactState.readOnlyInstalled) {
    flatDeploymentArtifactPathsByChainId.set(Number(networkRuntime.network.chainId), {
      paths: artifactState.paths,
      preparedModes: new Set([PRIVATE_STATE_INSTALL_MODES.READ_ONLY]),
    });
  }

  const provider = networkRuntime.provider;
  if (args.channelName) {
    guide.state.channel = await inspectGuideChannel({
      channelName: String(args.channelName),
      network: networkRuntime.network,
      provider,
      artifactsInstalled: artifactState.readOnlyInstalled,
    });
    guide.checks.push(guideCheck(
      "channel",
      guide.state.channel.onchain?.exists || guide.state.channel.local?.workspaceExists ? "ok" : "missing",
      {
        channelName: args.channelName,
        localWorkspaceExists: Boolean(guide.state.channel.local?.workspaceExists),
        onchainExists: guide.state.channel.onchain?.exists ?? null,
        error: guide.state.channel.error ?? null,
      },
    ));
  } else {
    guide.state.channels = listGuideLocalChannels(networkName);
  }

  if (args.account) {
    guide.state.account = await inspectGuideAccount({
      account: String(args.account),
      networkName,
      network: networkRuntime.network,
      provider,
      artifactsInstalled: artifactState.readOnlyInstalled,
    });
    guide.checks.push(guideCheck(
      "local account secret",
      guide.state.account.exists ? "ok" : "missing",
      {
        account: args.account,
        privateKeyPath: guide.state.account.privateKeyPath,
        l1Address: guide.state.account.l1Address,
        error: guide.state.account.error ?? null,
      },
    ));
  }

  if (args.wallet && !guide.state.local.walletSelectorError) {
    guide.state.wallet = await inspectGuideWallet({
      walletName: String(args.wallet),
      networkName,
      provider,
      artifactsInstalled: artifactState.readOnlyInstalled,
    });
    guide.checks.push(guideCheck(
      "local wallet",
      guide.state.wallet.exists ? "ok" : "missing",
      {
        wallet: args.wallet,
        walletDir: guide.state.wallet.walletDir,
        channelName: guide.state.wallet.channelName,
        l1Address: guide.state.wallet.l1Address,
        error: guide.state.wallet.error ?? null,
      },
    ));
  }

  destroyGuideProvider(provider);
  applyGuideNextAction(guide);
  printJson(guide);
}

function inspectGuideLocalState(args) {
  let selectedWalletCandidates = [];
  let walletSelectorError = null;
  if (args.wallet) {
    try {
      selectedWalletCandidates = resolveWalletPathCandidates(String(args.wallet));
    } catch (error) {
      walletSelectorError = error.message;
    }
  }

  return {
    workspaceRoot,
    secretRoot,
    workspaceRootExists: fs.existsSync(workspaceRoot),
    secretRootExists: fs.existsSync(secretRoot),
    workspaceNetworks: listDirectoryNames(workspaceRoot),
    secretNetworks: listDirectoryNames(secretRoot),
    selectedWalletCandidates,
    walletSelectorError,
  };
}

function inspectGuideNetworkRuntime(networkName) {
  let network;
  try {
    network = {
      ...resolveCliNetwork(networkName),
      name: networkName,
    };
  } catch (error) {
    return {
      network: null,
      provider: null,
      state: {
        name: networkName,
        supported: false,
        error: error.message,
      },
      check: guideCheck("network config", "error", {
        network: networkName,
        error: error.message,
      }),
    };
  }

  let rpcUrl = null;
  let rpcSource = null;
  let provider = null;
  let error = null;
  try {
    const rpcConfig = resolveCommandRpcConfig({ network: networkName });
    rpcUrl = rpcConfig.rpcUrl;
    rpcSource = rpcConfig.configPath;
    setActiveRpcLogConfig(rpcConfig);
    provider = new JsonRpcProvider(rpcUrl, Number(network.chainId), { staticNetwork: true });
  } catch (caught) {
    error = caught.message;
  }

  return {
    network,
    provider,
    state: {
      name: networkName,
      chainId: network.chainId,
      supported: true,
      rpcConfigured: Boolean(rpcUrl),
      rpcSource,
      rpcUrl: rpcUrl ? redactRpcUrl(rpcUrl) : null,
      rpcConfigEnvPath: rpcConfigEnvPath(networkName),
      error,
    },
    check: guideCheck("network RPC", rpcUrl ? "ok" : "missing", {
      network: networkName,
      rpcSource,
      error,
    }),
  };
}

function inspectGuideDeploymentArtifacts(chainId) {
  const paths = privateStateCliArtifactPaths(resolveArtifactCacheBaseRoot(), chainId);
  const readOnlyMissingFiles = missingInstalledDeploymentArtifactFiles(paths, PRIVATE_STATE_INSTALL_MODES.READ_ONLY)
    .map((entry) => entry.path);
  const fullMissingFiles = missingInstalledDeploymentArtifactFiles(paths, PRIVATE_STATE_INSTALL_MODES.FULL)
    .map((entry) => entry.path);
  return {
    installed: readOnlyMissingFiles.length === 0,
    readOnlyInstalled: readOnlyMissingFiles.length === 0,
    fullInstalled: fullMissingFiles.length === 0,
    rootDir: paths.rootDir,
    missingFiles: readOnlyMissingFiles,
    readOnlyMissingFiles,
    fullMissingFiles,
    paths,
  };
}

async function inspectGuideChannel({ channelName, network, provider, artifactsInstalled }) {
  const channelId = deriveChannelIdFromName(channelName);
  const local = inspectGuideLocalChannel({ networkName: network.name, channelName });
  const result = {
    channelName,
    channelId: channelId.toString(),
    local,
    onchain: null,
    error: null,
  };
  if (!provider || !artifactsInstalled) {
    return result;
  }

  try {
    const bridgeResources = loadBridgeResources({ chainId: network.chainId });
    const bridgeCore = new Contract(
      bridgeResources.bridgeDeployment.bridgeCore,
      bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
      provider,
    );
    const channelInfo = await bridgeCore.getChannel(channelId);
    result.onchain = {
      exists: Boolean(channelInfo.exists),
      manager: channelInfo.exists ? getAddress(channelInfo.manager) : null,
      bridgeTokenVault: channelInfo.exists ? getAddress(channelInfo.bridgeTokenVault) : null,
      leader: channelInfo.exists ? getAddress(channelInfo.leader) : null,
      dappId: channelInfo.exists ? Number(channelInfo.dappId) : null,
    };
    if (channelInfo.exists) {
      const channelManager = new Contract(
        channelInfo.manager,
        bridgeResources.bridgeAbiManifest.contracts.channelManager.abi,
        provider,
      );
      const [joinToll, refundSchedule] = await Promise.all([
        channelManager.joinToll(),
        readChannelRefundSchedule(channelManager),
      ]);
      result.onchain.joinTollBaseUnits = joinToll.toString();
      result.onchain.refundSchedule = refundSchedule;
    }
  } catch (error) {
    result.error = error.message;
  }
  return result;
}

function inspectGuideLocalChannel({ networkName, channelName }) {
  const workspaceDir = channelWorkspacePath(networkName, channelName);
  const workspacePath = channelWorkspaceConfigPath(workspaceDir);
  const currentDir = channelWorkspaceCurrentPath(workspaceDir);
  const workspace = readJsonIfExists(workspacePath);
  return {
    workspaceDir,
    workspaceExists: fs.existsSync(workspacePath),
    hasCurrentSnapshot: fs.existsSync(path.join(currentDir, "state_snapshot.json")),
    hasBlockInfo: fs.existsSync(path.join(currentDir, "block_info.json")),
    hasContractCodes: fs.existsSync(path.join(currentDir, "contract_codes.json")),
    channelManager: workspace?.channelManager ?? null,
    bridgeTokenVault: workspace?.bridgeTokenVault ?? null,
    recoveryLastScannedBlock: workspace?.recoveryLastScannedBlock ?? null,
  };
}

async function inspectGuideAccount({ account, networkName, network, provider, artifactsInstalled }) {
  const privateKeyPath = accountPrivateKeyPath(networkName, account);
  const metadataPath = accountMetadataPath(networkName, account);
  const result = {
    account,
    network: networkName,
    privateKeyPath,
    metadataPath,
    exists: fs.existsSync(privateKeyPath),
    metadataExists: fs.existsSync(metadataPath),
    l1Address: null,
    bridgeBalanceBaseUnits: null,
    bridgeBalanceTokens: null,
    error: null,
  };
  if (!result.exists) {
    return result;
  }
  try {
    const privateKey = normalizePrivateKey(readSecretFile(privateKeyPath, "--account"));
    const signer = new Wallet(privateKey, provider ?? undefined);
    result.l1Address = getAddress(signer.address);
    if (provider && artifactsInstalled) {
      const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId: network.chainId });
      const bridgeTokenVault = new Contract(
        bridgeVaultContext.bridgeTokenVaultAddress,
        bridgeVaultContext.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
        provider,
      );
      const availableBalance = await bridgeTokenVault.availableBalanceOf(signer.address);
      result.bridgeBalanceBaseUnits = availableBalance.toString();
      result.bridgeBalanceTokens = ethers.formatUnits(availableBalance, Number(bridgeVaultContext.canonicalAssetDecimals));
    }
  } catch (error) {
    result.error = error.message;
  }
  return result;
}

async function inspectGuideWallet({ walletName, networkName, provider, artifactsInstalled }) {
  let walletDir = walletRootPath(walletName, networkName);
  let workspaceError = null;
  try {
    walletDir = selectedWalletEpochDir(walletName, networkName);
  } catch (error) {
    workspaceError = error.message;
  }
  const viewingKeyFile = walletViewingKeySecretPath(networkName, walletName);
  const spendingKeyFile = walletSpendingKeySecretPath(networkName, walletName);
  const result = {
    wallet: walletName,
    network: networkName,
    walletDir,
    exists: walletConfigExists(walletDir),
    metadataExists: fs.existsSync(walletNotesMetadataPath(walletDir)),
    viewingKeyFile,
    viewingKeyFileExists: fs.existsSync(viewingKeyFile),
    spendingKeyFile,
    spendingKeyFileExists: fs.existsSync(spendingKeyFile),
    channelName: null,
    l1Address: null,
    l2Address: null,
    registrationExists: null,
    channelBalanceBaseUnits: null,
    channelBalanceTokens: null,
    unusedNoteCount: null,
    unusedNoteBalanceBaseUnits: null,
    unusedNoteBalanceTokens: null,
    spentNoteCount: null,
    error: workspaceError,
  };
  if (workspaceError || !result.exists) {
    return result;
  }

  try {
    const walletContext = loadWallet(walletName, networkName);
    const walletMetadata = loadWalletMetadata(walletName, networkName);
    assertWalletMatchesMetadata(walletContext, walletMetadata);
    result.channelName = walletContext.wallet.channelName;
    result.l1Address = getAddress(walletContext.wallet.l1Address);
    result.l2Address = getAddress(walletContext.wallet.l2Address);
    result.unusedNoteCount = Object.keys(walletContext.wallet.notes.unused).length;
    result.spentNoteCount = Object.keys(walletContext.wallet.notes.spent).length;
    const unusedValues = Object.values(walletContext.wallet.notes.unused).map((note) => note.value);
    if (unusedValues.every((value) => value !== null)) {
      const unusedNoteBalance = Object.values(walletContext.wallet.notes.unused)
        .reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n);
      result.unusedNoteBalanceBaseUnits = unusedNoteBalance.toString();
      result.unusedNoteBalanceTokens = ethers.formatUnits(unusedNoteBalance, Number(walletContext.wallet.canonicalAssetDecimals));
    }

    if (provider && artifactsInstalled && walletChannelWorkspaceIsReady(walletContext)) {
      const context = await loadWorkspaceContext(walletContext.wallet.channelName, networkName, provider);
      const registration = await context.channelManager.getChannelTokenVaultRegistration(result.l1Address);
      result.registrationExists = Boolean(registration.exists);
      if (registration.exists) {
        const stateManager = await buildStateManager(context.currentSnapshot, context.contractCodes);
        const channelBalance = await currentStorageBigInt(
          stateManager,
          context.workspace.l2AccountingVault,
          normalizeBytes32Hex(registration.channelTokenVaultKey),
        );
        result.channelBalanceBaseUnits = channelBalance.toString();
        result.channelBalanceTokens = ethers.formatUnits(channelBalance, Number(context.workspace.canonicalAssetDecimals));
      }
    }
  } catch (error) {
    result.error = error.message;
  }
  return result;
}

function applyGuideNextAction(guide) {
  if (guide.state.local?.walletSelectorError && guide.selectors.network) {
    setGuideNextAction(guide, {
      command: `wallet list --network ${guide.selectors.network}`,
      why: "The selected wallet name is malformed. List local wallets and retry help guide with an existing deterministic wallet name.",
    });
    return;
  }
  if (guide.state.network && !guide.state.network.rpcConfigured) {
    setGuideNextAction(guide, {
      command: `set rpc --network ${guide.selectors.network} --rpc-url <URL> --provider <PROVIDER>`,
      why: `Configure RPC settings in ${guide.state.network.rpcConfigEnvPath}.`,
    });
    return;
  }
  if (guide.state.deploymentArtifacts && !guide.state.deploymentArtifacts.installed) {
    setGuideNextAction(guide, {
      command: "install",
      why: "The private-state deployment artifacts or proof runtime files are not installed for the selected network.",
    });
    return;
  }
  if (guide.selectors.account && guide.state.account && !guide.state.account.exists) {
    setGuideNextAction(guide, {
      command: `account import --account ${guide.selectors.account} --network ${guide.selectors.network} --private-key-file <PATH>`,
      why: "The selected L1 account name does not have a protected local private-key secret yet.",
    });
    return;
  }
  if (guide.selectors.channelName && guide.state.channel?.onchain?.exists === false) {
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `channel create --channel-name ${guide.selectors.channelName} --join-toll <TOKENS> --network ${guide.selectors.network} --account ${account}`,
      why: "The selected channel name is not registered on-chain yet.",
    });
    return;
  }
  if (guide.selectors.channelName && guide.state.channel?.onchain?.exists && !guide.state.channel?.local?.workspaceExists) {
    setGuideNextAction(guide, {
      command: `channel recover-workspace --channel-name ${guide.selectors.channelName} --network ${guide.selectors.network} --source rpc --from-genesis`,
      why: "The channel exists on-chain, but the local channel workspace has not been recovered yet, so there is no local recovery index to resume from.",
    });
    return;
  }
  if (guide.selectors.wallet && guide.state.wallet && !guide.state.wallet.exists) {
    const channelName = guide.selectors.channelName ?? guide.state.channel?.channelName ?? "<CHANNEL>";
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `channel join --channel-name ${channelName} --network ${guide.selectors.network} --account ${account} --wallet-secret-path <PATH> --acknowledge-action-impact`,
      why: "The selected local wallet does not exist. Join the channel to create the wallet, register the channel L2 identity, and pay any join toll directly from the L1 wallet.",
    });
    return;
  }
  if (guide.state.wallet?.registrationExists === false) {
    const channelName = guide.state.wallet.channelName ?? guide.selectors.channelName ?? "<CHANNEL>";
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `channel join --channel-name ${channelName} --network ${guide.selectors.network} --account ${account} --wallet-secret-path <PATH> --acknowledge-action-impact`,
      why: "The local wallet exists, but the corresponding L1 address is not registered in the channel; joining pays any join toll directly from the L1 wallet.",
    });
    return;
  }

  const bridgeBalance = guide.state.account?.bridgeBalanceBaseUnits == null
    ? null
    : ethers.toBigInt(guide.state.account.bridgeBalanceBaseUnits);
  const channelBalance = guide.state.wallet?.channelBalanceBaseUnits == null
    ? null
    : ethers.toBigInt(guide.state.wallet.channelBalanceBaseUnits);
  const unusedNotes = guide.state.wallet?.unusedNoteCount ?? null;

  if (guide.state.wallet?.exists && bridgeBalance === 0n && (channelBalance === null || channelBalance === 0n) && unusedNotes === 0) {
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `account deposit-bridge --amount <TOKENS> --network ${guide.selectors.network} --account ${account} --acknowledge-action-impact`,
      why: "The wallet is joined, but there is no bridge balance, channel balance, or local unused note to spend; bridge deposits fund channel liquidity and do not pay join tolls.",
    });
    return;
  }
  if (guide.state.wallet?.exists && bridgeBalance !== null && bridgeBalance > 0n && channelBalance === 0n) {
    setGuideNextAction(guide, {
      command: `wallet deposit-channel --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --amount <TOKENS> --acknowledge-action-impact`,
      why: "The account has funds in the shared bridge vault, but the wallet has no channel L2 accounting balance.",
    });
    return;
  }
  if (guide.state.wallet?.exists && channelBalance !== null && channelBalance > 0n && unusedNotes === 0) {
    setGuideNextAction(guide, {
      command: `wallet mint-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --amounts <JSON_ARRAY> --acknowledge-action-impact [--tx-submitter <ACCOUNT>]`,
      why: "The wallet has channel L2 balance and no unused private notes yet. Use --tx-submitter for stronger transaction-submission privacy.",
    });
    return;
  }
  if (guide.state.wallet?.exists && unusedNotes !== null && unusedNotes > 0) {
    setGuideNextAction(guide, {
      command: `wallet transfer-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --note-ids <JSON_ARRAY> --recipients <JSON_ARRAY> --amounts <JSON_ARRAY> --acknowledge-action-impact [--tx-submitter <ACCOUNT>]`,
      why: "The wallet has unused private notes. It can transfer or redeem those notes. Use --tx-submitter for stronger transaction-submission privacy.",
      candidates: [
        `wallet get-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network}`,
        `wallet redeem-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --note-ids <JSON_ARRAY> --acknowledge-action-impact [--tx-submitter <ACCOUNT>]`,
      ],
    });
    return;
  }
  if (guide.state.wallet?.exists && channelBalance === 0n) {
    setGuideNextAction(guide, {
      command: `channel exit --wallet ${guide.selectors.wallet} --network ${guide.selectors.network}`,
      why: "The wallet has zero channel balance, so channel exit is allowed by both the CLI and bridge contract.",
    });
    return;
  }

  setGuideNextAction(guide, {
    command: "help guide --network <NAME> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET>",
    why: "Provide more selectors so the guide can choose a single next safe action.",
  });
}

function setGuideNextAction(guide, { command, why, candidates = [] }) {
  guide.nextSafeAction = command;
  guide.why = why;
  guide.candidateCommands = candidates;
}

function guideCheck(name, status, details = {}) {
  return {
    name,
    status,
    ...details,
  };
}

function listDirectoryNames(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return [];
  }
  return fs.readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));
}

function listGuideLocalChannels(networkName) {
  const networkWorkspaceRoot = path.join(workspaceRoot, slugifyPathComponent(networkName));
  return listDirectoryNames(networkWorkspaceRoot).map((channelName) =>
    inspectGuideLocalChannel({ networkName, channelName })
  );
}

function destroyGuideProvider(provider) {
  if (provider && typeof provider.destroy === "function") {
    provider.destroy();
  }
}

function redactRpcUrl(rpcUrl) {
  try {
    const parsed = new URL(rpcUrl);
    if (parsed.password) {
      parsed.password = "***";
    }
    if (parsed.username) {
      parsed.username = "***";
    }
    if (parsed.search) {
      parsed.search = "?...";
    }
    const pathParts = parsed.pathname.split("/").filter(Boolean);
    if (pathParts.length > 1) {
      parsed.pathname = `/${pathParts[0]}/...`;
    }
    return parsed.toString();
  } catch {
    return "<configured>";
  }
}

async function handleWalletGetMeta({ args, provider }) {
  const { wallet, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  const contextResult = await loadFreshWalletChannelContext({
    walletContext: wallet,
    provider,
    progressAction: "wallet get-meta",
  });
  const context = contextResult.context;
  const {
    signer,
    l2Identity,
    registration,
    expectedStorageKey,
    matchesWallet,
  } = await loadWalletChannelRegistrationState({
    walletContext: wallet,
    context,
    provider,
  });

  printJson({
    action: "wallet get-meta",
    wallet: wallet.walletName,
    ...walletLifecycleMetadata(wallet.wallet),
    network: walletMetadata.network,
    channelName: walletMetadata.channelName,
    l1Address: signer.address,
    walletL2Address: l2Identity.l2Address,
    walletL2StorageKey: expectedStorageKey,
    registrationExists: Boolean(registration.exists),
    matchesWallet,
    registeredL2Address: registration.exists ? getAddress(registration.l2Address) : null,
    registeredL2StorageKey: registration.exists ? normalizeBytes32Hex(registration.channelTokenVaultKey) : null,
    registeredLeafIndex: registration.exists ? registration.leafIndex.toString() : null,
    registeredNoteReceivePubKey: registration.exists
      ? {
        x: normalizeBytes32Hex(registration.noteReceivePubKey.x),
        yParity: Number(registration.noteReceivePubKey.yParity),
      }
      : null,
  });
}

async function loadWalletChannelFundState({ walletContext, provider, progressAction = "wallet get-channel-fund" }) {
  const contextResult = await loadFreshWalletChannelContext({
    walletContext,
    provider,
    progressAction,
  });
  const context = contextResult.context;
  const {
    signer,
    l2Identity,
    registration,
    expectedStorageKey,
  } = await loadWalletChannelRegistrationState({
    walletContext,
    context,
    provider,
    requireRegistration: true,
  });

  const stateManager = await buildStateManager(context.currentSnapshot, context.contractCodes);
  const channelDeposit = await currentStorageBigInt(
    stateManager,
    context.workspace.l2AccountingVault,
    normalizeBytes32Hex(registration.channelTokenVaultKey),
  );
  return {
    signer,
    l2Identity,
    contextResult,
    context,
    registration,
    expectedStorageKey,
    channelFund: channelDeposit,
  };
}

async function loadWalletChannelRegistrationState({
  walletContext,
  context,
  provider,
  requireRegistration = false,
}) {
  const signer = requireWalletOwnerSigner(walletContext, provider);
  const l2Identity = restoreParticipantIdentityFromWallet(walletContext.wallet);
  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  const expectedStorageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  const matchesWallet = walletRegistrationMatchesIdentity({ registration, l2Identity, expectedStorageKey });

  if (requireRegistration) {
    expect(
      registration.exists,
      cliError(
        CLI_ERROR_CODES.MISSING_CHANNEL_REGISTRATION,
        `No channelTokenVault registration exists for ${signer.address}. Run channel join first.`,
      ),
    );
    expect(
      matchesWallet,
      "The local wallet L2 address or storage key does not match the registered channelTokenVault state.",
    );
  }

  return {
    signer,
    l2Identity,
    registration,
    expectedStorageKey,
    matchesWallet,
  };
}

function walletRegistrationMatchesIdentity({ registration, l2Identity, expectedStorageKey }) {
  return registration.exists
    && ethers.toBigInt(getAddress(registration.l2Address)) === ethers.toBigInt(getAddress(l2Identity.l2Address))
    && ethers.toBigInt(normalizeBytes32Hex(registration.channelTokenVaultKey))
      === ethers.toBigInt(normalizeBytes32Hex(expectedStorageKey));
}

function selectWalletLifecycleEpoch({ epochs, registration = null }) {
  if (registration?.exists) {
    const active = [...epochs].reverse().find((epoch) => (
      epoch.lifecycleStatus === "active"
      && ethers.toBigInt(getAddress(epoch.l2Address)) === ethers.toBigInt(getAddress(registration.l2Address))
      && ethers.toBigInt(normalizeBytes32Hex(epoch.channelTokenVaultKey))
        === ethers.toBigInt(normalizeBytes32Hex(registration.channelTokenVaultKey))
    ));
    if (active) {
      return active;
    }
  }
  return epochs[epochs.length - 1] ?? null;
}

async function buildWalletLifecycleEpochsFromLogs({ registeredLogs, exitedLogs, provider }) {
  const exits = await Promise.all(exitedLogs.map((log) => walletExitFromLog({ log, provider })));
  const epochs = [];
  for (const log of registeredLogs.sort(compareLogsByPosition)) {
    const registered = await walletEpochFromRegisteredLog({ log, provider });
    const exit = exits.find((entry) => (
      compareLogPosition(entry, registered) > 0
      && ethers.toBigInt(entry.leafIndex) === ethers.toBigInt(registered.leafIndex)
      && !epochs.some((epoch) => epoch.exitedAtTxHash === entry.exitedAtTxHash)
    ));
    if (exit) {
      epochs.push({
        ...registered,
        lifecycleStatus: "exited",
        exitedAtTxHash: exit.exitedAtTxHash,
        exitedAtBlockNumber: exit.exitedAtBlockNumber,
        exitedAtLogIndex: exit.exitedAtLogIndex,
        exitedAtBlockTimestamp: exit.exitedAtBlockTimestamp,
        exitedAtBlockTimestampIso: exit.exitedAtBlockTimestampIso,
      });
    } else {
      epochs.push(registered);
    }
  }
  return epochs.sort(compareWalletEpochs);
}

async function walletEpochFromJoinReceipt({ receipt, context, provider, l1Address, registration }) {
  const registeredTopic = normalizeBytes32Hex(
    context.channelManager.interface.getEvent("ChannelTokenVaultIdentityRegistered").topicHash,
  );
  const normalizedManager = getAddress(context.workspace.channelManager);
  const normalizedL1Address = getAddress(l1Address);
  const matchingLogs = [];

  for (const log of receipt.logs ?? []) {
    if (ethers.toBigInt(getAddress(log.address)) !== ethers.toBigInt(normalizedManager)) {
      continue;
    }
    const topic0 = log.topics?.[0] ? normalizeBytes32Hex(log.topics[0]) : null;
    if (topic0 !== registeredTopic) {
      continue;
    }
    const parsedLog = context.channelManager.interface.parseLog(log);
    if (ethers.toBigInt(getAddress(parsedLog.args.l1Address)) !== ethers.toBigInt(normalizedL1Address)) {
      continue;
    }
    matchingLogs.push({
      ...log,
      args: parsedLog.args,
      fragment: parsedLog.fragment,
    });
  }

  expect(
    matchingLogs.length === 1,
    `Expected exactly one ChannelTokenVaultIdentityRegistered log for ${normalizedL1Address} in the join transaction, found ${matchingLogs.length}.`,
  );
  const epoch = await walletEpochFromRegisteredLog({ log: matchingLogs[0], provider });
  if (registration?.exists) {
    expect(
      ethers.toBigInt(getAddress(epoch.l2Address)) === ethers.toBigInt(getAddress(registration.l2Address)),
      "Join transaction registration log does not match the current registered L2 address.",
    );
    expect(
      ethers.toBigInt(normalizeBytes32Hex(epoch.channelTokenVaultKey))
        === ethers.toBigInt(normalizeBytes32Hex(registration.channelTokenVaultKey)),
      "Join transaction registration log does not match the current channel token vault key.",
    );
  }
  return epoch;
}

async function scanWalletRecoveryEvents({ context, provider, l1Address, toBlock, progressAction = null }) {
  const fromBlock = Number(context.workspace.genesisBlockNumber ?? 0);
  const normalizedToBlock = Number(toBlock);
  expect(
    Number.isInteger(normalizedToBlock) && normalizedToBlock >= fromBlock - 1,
    "Wallet recovery event scan target block is invalid.",
  );
  const registeredTopic = context.channelManager.interface.getEvent("ChannelTokenVaultIdentityRegistered").topicHash;
  const exitedTopic = context.channelManager.interface.getEvent("ChannelTokenVaultIdentityExited").topicHash;
  const normalizedRegisteredTopic = normalizeBytes32Hex(registeredTopic);
  const normalizedExitedTopic = normalizeBytes32Hex(exitedTopic);
  const normalizedNoteTopic = normalizeBytes32Hex(NOTE_VALUE_ENCRYPTED_TOPIC);
  const normalizedStorageObservedTopic = normalizeBytes32Hex(CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC);
  const normalizedL1Address = getAddress(l1Address);
  const registeredLogs = [];
  const exitedLogs = [];
  const deliveryLogs = [];
  const storageObservationLogs = [];

  await fetchLogsChunked(provider, {
    address: context.workspace.channelManager,
    topics: [[registeredTopic, exitedTopic, NOTE_VALUE_ENCRYPTED_TOPIC, CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC]],
    fromBlock,
    toBlock: normalizedToBlock,
    collectLogs: false,
    onProgress: progressAction
      ? createRpcLogScanProgress({ action: progressAction, label: "wallet-recovery events" })
      : null,
    onChunk: async ({ logs }) => {
      for (const log of logs) {
        const normalizedTopic0 = normalizeBytes32Hex(log.topics?.[0] ?? ZERO_TOPIC);
        if (normalizedTopic0 === normalizedNoteTopic) {
          deliveryLogs.push(log);
          continue;
        }
        if (normalizedTopic0 === normalizedStorageObservedTopic) {
          storageObservationLogs.push(log);
          continue;
        }
        if (normalizedTopic0 !== normalizedRegisteredTopic && normalizedTopic0 !== normalizedExitedTopic) {
          continue;
        }
        const parsedLog = context.channelManager.interface.parseLog(log);
        if (ethers.toBigInt(getAddress(parsedLog.args.l1Address)) !== ethers.toBigInt(normalizedL1Address)) {
          continue;
        }
        const eventLog = {
          ...log,
          args: parsedLog.args,
          fragment: parsedLog.fragment,
        };
        if (normalizedTopic0 === normalizedRegisteredTopic) {
          registeredLogs.push(eventLog);
        } else {
          exitedLogs.push(eventLog);
        }
      }
    },
  });

  return {
    lifecycleEpochs: await buildWalletLifecycleEpochsFromLogs({ registeredLogs, exitedLogs, provider }),
    registeredLogs,
    exitedLogs,
    deliveryLogs,
    storageObservationLogs,
    scanRange: {
      fromBlock,
      toBlock: normalizedToBlock,
    },
  };
}

async function walletEpochFromRegisteredLog({ log, provider }) {
  const block = await provider.getBlock(log.blockNumber).catch(() => null);
  const args = log.args;
  return {
    epochId: walletEpochIdFromLog(log),
    lifecycleStatus: "active",
    joinedAtTxHash: log.transactionHash,
    joinedAtBlockNumber: log.blockNumber,
    joinedAtLogIndex: log.index ?? log.logIndex ?? null,
    joinedAtBlockTimestamp: block?.timestamp ?? Number(args.joinedAt ?? 0) ?? null,
    joinedAtBlockTimestampIso: block?.timestamp
      ? new Date(Number(block.timestamp) * 1000).toISOString()
      : Number(args.joinedAt ?? 0) > 0
        ? new Date(Number(args.joinedAt) * 1000).toISOString()
        : null,
    exitedAtTxHash: null,
    exitedAtBlockNumber: null,
    exitedAtLogIndex: null,
    exitedAtBlockTimestamp: null,
    exitedAtBlockTimestampIso: null,
    l2Address: getAddress(args.l2Address),
    channelTokenVaultKey: normalizeBytes32Hex(args.channelTokenVaultKey),
    leafIndex: args.leafIndex,
    noteReceivePubKey: {
      x: normalizeBytes32Hex(args.noteReceivePubKeyX),
      yParity: Number(args.noteReceivePubKeyYParity),
    },
  };
}

async function walletExitFromLog({ log, provider }) {
  const block = await provider.getBlock(log.blockNumber).catch(() => null);
  return {
    exitedAtTxHash: log.transactionHash,
    exitedAtBlockNumber: log.blockNumber,
    exitedAtLogIndex: log.index ?? log.logIndex ?? null,
    exitedAtBlockTimestamp: block?.timestamp ?? null,
    exitedAtBlockTimestampIso: block?.timestamp ? new Date(Number(block.timestamp) * 1000).toISOString() : null,
    leafIndex: log.args.leafIndex,
  };
}

function walletEpochIdFromLog(log) {
  return `join-${String(log.transactionHash).toLowerCase()}-${Number(log.index ?? log.logIndex ?? 0)}`;
}

function compareLogPosition(left, right) {
  return Number(left.exitedAtBlockNumber ?? left.blockNumber ?? 0) - Number(right.joinedAtBlockNumber ?? right.blockNumber ?? 0)
    || Number((left.exitedAtLogIndex ?? left.index ?? left.logIndex) ?? 0)
      - Number((right.joinedAtLogIndex ?? right.index ?? right.logIndex) ?? 0);
}

function compareWalletEpochs(left, right) {
  return Number(left.joinedAtBlockNumber ?? 0) - Number(right.joinedAtBlockNumber ?? 0)
    || Number(left.joinedAtLogIndex ?? 0) - Number(right.joinedAtLogIndex ?? 0)
    || String(left.epochId).localeCompare(String(right.epochId));
}

async function handleWalletGetChannelFund({ args, provider }) {
  const { wallet, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  const {
    signer,
    l2Identity,
    context,
    registration,
    expectedStorageKey,
    channelFund,
  } = await loadWalletChannelFundState({
    walletContext: wallet,
    provider,
  });

  printJson({
    action: "wallet get-channel-fund",
    wallet: wallet.walletName,
    network: walletMetadata.network,
    channelName: walletMetadata.channelName,
    l1Address: signer.address,
    walletL2Address: l2Identity.l2Address,
    walletL2StorageKey: expectedStorageKey,
    registeredLeafIndex: registration.leafIndex.toString(),
    channelDepositBaseUnits: channelFund.toString(),
    channelDepositTokens: ethers.formatUnits(
      channelFund,
      Number(context.workspace.canonicalAssetDecimals),
    ),
    canonicalAsset: context.workspace.canonicalAsset,
    canonicalAssetDecimals: Number(context.workspace.canonicalAssetDecimals),
    l2AccountingVault: context.workspace.l2AccountingVault,
  });
}

async function handleJoinChannel({ args, network, provider, rpcUrl }) {
  const context = await loadJoinChannelContext({
    args,
    network,
    provider,
  });
  const signer = requireL1Signer(args, provider);
  const walletName = walletNameForChannelAndAddress(context.workspace.channelName, signer.address);
  const existingRegistration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  expect(
    !existingRegistration.exists,
    [
      `L1 address ${signer.address} is already registered in channel ${context.workspace.channelName}.`,
      "Use wallet recover-workspace or normal wallet commands for an existing channel registration.",
    ].join(" "),
  );
  const walletSecret = prepareJoinWalletSecretForName({
    args,
    networkName: network.name,
    walletName,
  });
  const l2Identity = await deriveParticipantIdentityFromSigner({
    channelName: context.workspace.channelName,
    walletSecret,
    signer,
  });
  const noteReceiveKeyMaterial = await deriveNoteReceiveKeyMaterial({
    signer,
    chainId: network.chainId,
    channelId: context.workspace.channelId,
    channelName: context.workspace.channelName,
    account: signer.address,
  });
  const storageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  const leafIndex = deriveChannelTokenVaultLeafIndex(storageKey);

  let approveReceipt = null;
  let receipt = null;
  const joinToll = ethers.toBigInt(await context.channelManager.joinToll());
  const asset = new Contract(
    context.workspace.canonicalAsset,
    context.bridgeAbiManifest.contracts.erc20.abi,
    signer,
  );
  let nextNonce = await provider.getTransactionCount(signer.address, "pending");
  printImmutableChannelPolicyWarning({
    action: "channel join",
    channelName: context.workspace.channelName,
    channelId: ethers.toBigInt(context.workspace.channelId),
    channelManager: context.workspace.channelManager,
    policySnapshot: context.workspace.policySnapshot,
  });
  await requireActionImpactAcknowledgement("channel-join", args, {
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    noteReceivePubKey: JSON.stringify(noteReceiveKeyMaterial.noteReceivePubKey),
    joinToll: ethers.formatUnits(joinToll, Number(context.workspace.canonicalAssetDecimals)),
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
  });
  if (joinToll !== 0n) {
    approveReceipt = await waitForReceipt(
      await asset.approve(context.workspace.bridgeTokenVault, joinToll, { nonce: nextNonce++ }),
    );
  }
  receipt = await waitForReceipt(
    await context.bridgeTokenVault.connect(signer).joinChannel(
      ethers.toBigInt(context.workspace.channelId),
      l2Identity.l2Address,
      storageKey,
      leafIndex,
      noteReceiveKeyMaterial.noteReceivePubKey,
      { nonce: nextNonce++ },
    ),
  );
  const registered = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  const lifecycleEpoch = await walletEpochFromJoinReceipt({
    receipt,
    context,
    provider,
    l1Address: signer.address,
    registration: registered,
  });
  await refreshPersistedWorkspaceAfterLocalTransaction({
    context,
    provider,
    receipt,
    progressAction: "channel join",
  });

  const walletContext = ensureWallet({
    channelContext: context,
    signerAddress: signer.address,
    signerPrivateKey: signer.privateKey,
    l2Identity,
    walletSecret,
    storageKey,
    leafIndex,
    noteReceiveKeyMaterial,
    lifecycleEpoch,
    rpcUrl,
  });

  printJson({
    action: "channel join",
    workspace: context.workspaceName,
    wallet: walletContext.walletName,
    walletSecretSource: "wallet-secret-path-one-time-derivation",
    walletSecretStored: false,
    walletSecretRecoveryWarning: "Keep the wallet secret source backed up. If the spending-key file is lost and this wallet secret source is also lost, the CLI cannot rederive the spending key; notes for this wallet cannot be spent, transferred, or redeemed through the normal note flow.",
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    leafIndex: leafIndex.toString(),
    epochId: lifecycleEpoch.epochId,
    lifecycleStatus: lifecycleEpoch.lifecycleStatus,
    joinedAtTxHash: lifecycleEpoch.joinedAtTxHash,
    joinedAtBlockNumber: lifecycleEpoch.joinedAtBlockNumber,
    joinTollBaseUnits: joinToll.toString(),
    joinTollTokens: ethers.formatUnits(joinToll, Number(context.workspace.canonicalAssetDecimals)),
    noteReceivePubKey: noteReceiveKeyMaterial.noteReceivePubKey,
    policySnapshot: context.workspace.policySnapshot,
    approveGasUsed: approveReceipt ? receiptGasUsed(approveReceipt) : null,
    gasUsed: receipt ? receiptGasUsed(receipt) : null,
    approveTxUrl: approveReceipt ? explorerTxUrl(network, approveReceipt.hash) : null,
    txUrl: receipt ? explorerTxUrl(network, receipt.hash) : null,
    approveReceipt: approveReceipt ? sanitizeReceipt(approveReceipt) : null,
    receipt: receipt ? sanitizeReceipt(receipt) : null,
    status: "joined",
  });
}

async function handleExitChannel({ args, provider }) {
  const { wallet: walletContext, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  requireActiveWalletLifecycle(walletContext, "channel exit");
  const { signer, context, channelFund, contextResult } = await loadWalletChannelFundState({
    walletContext,
    provider,
    progressAction: "channel exit",
  });
  const ownerSigner = requireWalletOwnerSigner(walletContext, provider);
  const network = contextResult.network;
  expect(
    channelFund === 0n,
    [
      `The current channel fund for ${ownerSigner.address} is ${channelFund.toString()}.`,
      "channel exit requires a zero channel balance.",
      "Run wallet withdraw-channel first, then retry channel exit.",
    ].join(" "),
  );
  const [refundAmount, refundBps] = await context.channelManager.getExitTollRefundQuote(ownerSigner.address);
  const receipt = await waitForReceipt(
    await context.bridgeTokenVault.connect(ownerSigner).exitChannel(ethers.toBigInt(context.workspace.channelId)),
  );
  const lifecycleEpoch = await markWalletEpochExited({
    walletContext,
    receipt,
    provider,
  });

  printJson({
    action: "channel exit",
    wallet: walletContext.walletName,
    network: walletMetadata.network,
    channelName: walletMetadata.channelName,
    channelId: context.workspace.channelId,
    l1Address: ownerSigner.address,
    currentUserValue: channelFund.toString(),
    refundAmountBaseUnits: refundAmount.toString(),
    refundAmountTokens: ethers.formatUnits(refundAmount, Number(context.workspace.canonicalAssetDecimals)),
    refundBps: Number(refundBps),
    canonicalAsset: context.workspace.canonicalAsset,
    canonicalAssetDecimals: Number(context.workspace.canonicalAssetDecimals),
    gasUsed: receiptGasUsed(receipt),
    txUrl: explorerTxUrl(network, receipt.hash),
    receipt: sanitizeReceipt(receipt),
    epochId: lifecycleEpoch.epochId,
    lifecycleStatus: lifecycleEpoch.lifecycleStatus,
    exitedAtTxHash: lifecycleEpoch.exitedAtTxHash,
    exitedAtBlockNumber: lifecycleEpoch.exitedAtBlockNumber,
    exitedAtBlockTimestampIso: lifecycleEpoch.exitedAtBlockTimestampIso,
    archivedWalletDir: walletContext.walletDir,
  });
}

async function handleGrothVaultMove({ args, provider, direction }) {
  const operationName = args.command === "wallet-withdraw-channel"
    ? "wallet withdraw-channel"
    : direction === "deposit"
      ? "wallet deposit-channel"
      : "wallet withdraw-channel";
  emitProgress(operationName, "loading");
  const { wallet: walletContext } = loadUnlockedWalletWithMetadata(args);
  requireActiveWalletLifecycle(walletContext, operationName);
  const contextResult = await loadFreshWalletChannelContext({
    walletContext,
    provider,
    progressAction: operationName,
  });
  const context = contextResult.context;
  const network = contextResult.network;
  expect(
    ethers.toBigInt(walletContext.wallet.channelId) === ethers.toBigInt(context.workspace.channelId),
    "The provided wallet does not belong to the selected channel.",
  );
  await assertChannelProofBackendVersionCompatibility({ context, operationName });

  const { signer, l2Identity } = restoreWalletParticipant(walletContext, provider);
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(context.workspace.canonicalAssetDecimals));
  await requireActionImpactAcknowledgement(args.command, args, {
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    amountInput,
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
  });
  const storageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  const bridgeTokenVault = new Contract(
    context.workspace.bridgeTokenVault,
    context.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const availableBalance = await bridgeTokenVault.availableBalanceOf(signer.address);
  if (direction === "deposit") {
    expect(
      availableBalance >= amount,
      [
        `Deposit amount ${amount.toString()} exceeds the shared bridge-vault balance`,
        `${availableBalance.toString()} for ${signer.address}. Run account deposit-bridge first.`,
      ].join(" "),
    );
  }
  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  expect(
    registration.exists,
    cliError(
      CLI_ERROR_CODES.MISSING_CHANNEL_REGISTRATION,
      `No channelTokenVault registration exists for ${signer.address}. Run channel join first.`,
    ),
  );
  expect(
    ethers.toBigInt(normalizeBytes32Hex(registration.channelTokenVaultKey))
      === ethers.toBigInt(normalizeBytes32Hex(storageKey)),
    "The derived L2 storage key does not match the registered channelTokenVault key.",
  );
  expect(
    ethers.toBigInt(getAddress(registration.l2Address)) === ethers.toBigInt(getAddress(l2Identity.l2Address)),
    "The derived L2 address does not match the registered channel L2 address.",
  );

  await assertWorkspaceAlignedWithChain(context);
  const stateManager = await buildStateManager(context.currentSnapshot, context.contractCodes);
  const keyHex = storageKey;
  const currentValue = await currentStorageBigInt(stateManager, context.workspace.l2AccountingVault, keyHex);
  let nextValue;
  if (direction === "deposit") {
    nextValue = currentValue + amount;
    if (nextValue >= BLS12_381_SCALAR_FIELD_MODULUS) {
      throw new Error("Deposit would overflow the BLS12-381 scalar field bound.");
    }
  } else {
    if (currentValue < amount) {
      throw new Error("Withdraw amount exceeds the current L2 accounting balance.");
    }
    nextValue = currentValue - amount;
  }

  const operationDir = createWalletOperationDir(
    walletContext.walletName,
    walletContext.wallet.network,
    `${operationName}-${shortAddress(signer.address)}`,
  );

  emitProgress(operationName, "proving");
  const transition = await buildGrothTransition({
    operationDir,
    workspace: context.workspace,
    stateManager,
    vaultAddress: context.workspace.l2AccountingVault,
    keyHex,
    nextValue,
  });

  const methodName = direction === "deposit" ? "depositToChannelVault" : "withdrawFromChannelVault";
  await assertWorkspaceAlignedWithChain(context);
  emitProgress(operationName, "submitting");
  const receipt = await waitForReceipt(
    await bridgeTokenVault[methodName](ethers.toBigInt(context.workspace.channelId), transition.proof, transition.update),
  );
  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  expect(
    onchainRootVectorHash === normalizeBytes32Hex(hashRootVector(transition.nextSnapshot.stateRoots)),
    `On-chain roots do not match the ${direction} post-state roots.`,
  );

  emitProgress(operationName, "persisting");
  writeJson(path.join(operationDir, `${operationName}-receipt.json`), sanitizeReceipt(receipt));
  writeJson(path.join(operationDir, "state_snapshot.json"), transition.nextSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), transition.nextSnapshot);
  sealWalletOperationDir(operationDir, walletOperationSealSecret(walletContext));

  context.currentSnapshot = transition.nextSnapshot;
  await refreshPersistedWorkspaceAfterLocalTransaction({
    context,
    provider,
    receipt,
    progressAction: operationName,
  });

  emitProgress(operationName, "done");
  printJson({
    action: operationName,
    workspace: context.workspaceName,
    wallet: walletContext.walletName,
    operationDir,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    amountInput,
    amountBaseUnits: amount.toString(),
    currentRootVector: transition.update.currentRootVector,
    updatedRoot: transition.update.updatedRoot,
    gasUsed: receiptGasUsed(receipt),
    txUrl: explorerTxUrl(network, receipt.hash),
    usedWorkspaceCache: contextResult.usingWorkspaceCache,
    recoveredWorkspace: contextResult.recoveredWorkspace,
  });
}

async function handleWithdrawBridge({ args, network, provider }) {
  const signer = requireL1Signer(args, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
  await requireActionImpactAcknowledgement("account-withdraw-bridge", args, {
    l1Address: signer.address,
    amountInput,
    bridgeTokenVault: bridgeVaultContext.bridgeTokenVaultAddress,
  });
  const bridgeTokenVault = new Contract(
    bridgeVaultContext.bridgeTokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const receipt = await waitForReceipt(await bridgeTokenVault.claimToWallet(amount));

  printJson({
    action: "account withdraw-bridge",
    l1Address: signer.address,
    amountInput,
    amountBaseUnits: amount.toString(),
    bridgeTokenVault: bridgeVaultContext.bridgeTokenVaultAddress,
    canonicalAsset: bridgeVaultContext.canonicalAsset,
    canonicalAssetDecimals: Number(bridgeVaultContext.canonicalAssetDecimals),
    gasUsed: receiptGasUsed(receipt),
    txUrl: explorerTxUrl(network, receipt.hash),
    receipt: sanitizeReceipt(receipt),
  });
}

function resolveFunctionMetadataProofForExecution({
  chainId,
  controllerAddress,
  functionSelector,
  preprocessInputHash,
  expectedFunctionRoot,
}) {
  const manifestPath = requireFlatDeploymentArtifactPathsForChainId(chainId).dappRegistrationPath;
  const manifest = readJson(manifestPath);
  const proofRoot = normalizeBytes32Hex(manifest.functionMetadataProofs?.root);
  const expectedRoot = normalizeBytes32Hex(expectedFunctionRoot);
  expect(
    ethers.toBigInt(proofRoot) === ethers.toBigInt(expectedRoot),
    `DApp function proof root ${proofRoot} does not match channel function root ${expectedRoot}.`,
  );

  const functions = manifest.functionMetadataProofs?.functions;
  expect(Array.isArray(functions), `DApp registration manifest is missing functionMetadataProofs.functions: ${manifestPath}.`);
  const normalizedController = getAddress(controllerAddress);
  const normalizedSelector = normalizeBytesHex(functionSelector, 4);
  const normalizedPreprocessInputHash = normalizeBytes32Hex(preprocessInputHash);
  const entry = functions.find((candidate) => {
    const metadata = candidate?.metadata;
    return metadata
      && getAddress(metadata.entryContract) === normalizedController
      && normalizeBytesHex(metadata.functionSig, 4) === normalizedSelector
      && normalizeBytes32Hex(metadata.preprocessInputHash) === normalizedPreprocessInputHash;
  });
  expect(
    entry !== undefined,
    [
      `No DApp function metadata proof found for ${normalizedController} ${normalizedSelector}.`,
      `Expected preprocess input hash: ${normalizedPreprocessInputHash}.`,
      `Manifest: ${manifestPath}.`,
    ].join(" "),
  );

  return {
    metadata: {
      entryContract: getAddress(entry.metadata.entryContract),
      functionSig: normalizeBytesHex(entry.metadata.functionSig, 4),
      preprocessInputHash: normalizeBytes32Hex(entry.metadata.preprocessInputHash),
      instanceLayout: {
        entryContractOffsetWords: Number(entry.metadata.instanceLayout.entryContractOffsetWords),
        functionSigOffsetWords: Number(entry.metadata.instanceLayout.functionSigOffsetWords),
        currentRootVectorOffsetWords: Number(entry.metadata.instanceLayout.currentRootVectorOffsetWords),
        updatedRootVectorOffsetWords: Number(entry.metadata.instanceLayout.updatedRootVectorOffsetWords),
        eventLogs: entry.metadata.instanceLayout.eventLogs.map((eventLog) => ({
          startOffsetWords: Number(eventLog.startOffsetWords),
          topicCount: Number(eventLog.topicCount),
        })),
      },
    },
    siblings: entry.merkleProof.map((sibling) => normalizeBytes32Hex(sibling)),
  };
}

async function handleMintNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  requireActiveWalletLifecycle(wallet, "wallet mint-notes");
  requireWalletViewingCapability(wallet);
  requireWalletSpendingCapability(wallet);
  const canonicalAssetDecimals = Number(wallet.wallet.canonicalAssetDecimals);
  const amountInputs = parseAmountVector(requireArg(args.amounts, "--amounts"), {
    allowZeroEntries: true,
    requireAnyPositive: true,
  });
  const baseUnitAmounts = amountInputs
    .map((value, index) => ({
      index,
      amountInput: value,
      amountBaseUnits: parseTokenAmount(value, canonicalAssetDecimals),
    }))
    .filter(({ amountBaseUnits }) => amountBaseUnits > 0n);
  expect(
    baseUnitAmounts.length > 0,
    "Invalid --amounts. The array must contain at least one amount greater than zero.",
  );
  const totalMintAmount = baseUnitAmounts.reduce((sum, { amountBaseUnits }) => sum + amountBaseUnits, 0n);
  const { channelFund, contextResult: preparedContextResult } = await loadWalletChannelFundState({
    walletContext: wallet,
    provider,
    progressAction: "wallet mint-notes",
  });
  expect(
    totalMintAmount <= channelFund,
    [
      `Mint amount total ${totalMintAmount.toString()} exceeds the current channel fund`,
      `${channelFund.toString()}. Run wallet get-channel-fund to inspect the available balance.`,
    ].join(" "),
  );
  const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);
  const { txSubmitter } = resolveTxSubmitterSigner({
    args,
    ownerSigner: signer,
    provider,
  });
  await requireActionImpactAcknowledgement("wallet-mint-notes", args, {
    l1Address: txSubmitter.address,
    l2Address: l2Identity.l2Address,
    amounts: baseUnitAmounts.map(({ amountInput }) => amountInput).join(", "),
    channelName: wallet.wallet.channelName,
    channelId: wallet.wallet.channelId,
  });
  const templatePayload = buildMintNotesTemplatePayload({
    wallet,
    baseUnitAmounts: baseUnitAmounts.map(({ amountBaseUnits }) => amountBaseUnits),
  });
  const { execution, contextResult, walletWarnings } = await executeWalletDirectTemplateCommand({
    args,
    wallet,
    provider,
    operationName: "wallet mint-notes",
    templatePayload,
    preparedContextResult,
  });

  printJson({
    action: "wallet mint-notes",
    wallet: wallet.walletName,
    workspace: execution.context.workspaceName,
    operationDir: execution.operationDir,
    l1Submitter: execution.txSubmitter.address,
    l1WalletOwner: execution.signer.address,
    txSubmitterSource: execution.txSubmitterSource,
    txSubmitterAccount: execution.txSubmitterAccount,
    l2Address: execution.l2Identity.l2Address,
    underlyingMethod: templatePayload.method,
    nonce: execution.nonce,
    amountInputs: baseUnitAmounts.map(({ amountInput }) => amountInput),
    amountBaseUnits: baseUnitAmounts.map(({ amountBaseUnits }) => amountBaseUnits.toString()),
    outputNotes: buildLifecycleTrackedOutputs({
      outputNotes: templatePayload.lifecycleOutputs,
      sourceFunction: templatePayload.method,
      sourceTxHash: execution.receipt.hash,
      sourceBlockNumber: execution.receipt.blockNumber,
    }),
    gasUsed: receiptGasUsed(execution.receipt),
    txUrl: explorerTxUrl(contextResult.network, execution.receipt.hash),
    usedWorkspaceCache: contextResult.usingWorkspaceCache,
    recoveredWorkspace: contextResult.recoveredWorkspace,
    postTransactionRecovery: execution.postTransactionRecovery,
    warnings: walletWarnings,
    updatedRoots: execution.context.currentSnapshot.stateRoots,
  });
}

async function handleRedeemNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  requireActiveWalletLifecycle(wallet, "wallet redeem-notes");
  requireWalletViewingCapability(wallet);
  requireWalletSpendingCapability(wallet);
  const noteIds = parseNoteIdVector(requireArg(args.noteIds, "--note-ids"));
  const preparedContextResult = await loadFreshWalletChannelContext({
    walletContext: wallet,
    provider,
    progressAction: "wallet redeem-notes",
  });
  await ensureWalletNoteReceiveStateCurrent({
    walletContext: wallet,
    context: preparedContextResult.context,
    provider,
    progressAction: "wallet redeem-notes",
    preConsumedBlockDelta: preparedContextResult.autoRecoveryBlockDelta,
  });
  const inputNotes = loadWalletUnusedInputNotes(wallet, noteIds);
  const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);
  const { txSubmitter } = resolveTxSubmitterSigner({
    args,
    ownerSigner: signer,
    provider,
  });
  await requireActionImpactAcknowledgement("wallet-redeem-notes", args, {
    l1Address: txSubmitter.address,
    l2Address: l2Identity.l2Address,
    noteIds: noteIds.join(", "),
    channelName: wallet.wallet.channelName,
    channelId: wallet.wallet.channelId,
  });
  const templatePayload = buildRedeemNotesTemplatePayload({
    wallet,
    inputNotes,
  });
  const { execution, contextResult, walletWarnings } = await executeWalletDirectTemplateCommand({
    args,
    wallet,
    provider,
    operationName: "wallet redeem-notes",
    templatePayload,
    preparedContextResult,
  });

  printJson({
    action: "wallet redeem-notes",
    wallet: wallet.walletName,
    workspace: execution.context.workspaceName,
    operationDir: execution.operationDir,
    l1Submitter: execution.txSubmitter.address,
    l1WalletOwner: execution.signer.address,
    txSubmitterSource: execution.txSubmitterSource,
    txSubmitterAccount: execution.txSubmitterAccount,
    l2Address: execution.l2Identity.l2Address,
    receiver: wallet.wallet.l2Address,
    underlyingMethod: templatePayload.method,
    nonce: execution.nonce,
    noteIds,
    redeemedNotes: inputNotes.map((note) => buildTrackedNote(note, templatePayload.method, execution.receipt.hash)),
    redeemedAmountBaseUnits: inputNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n).toString(),
    redeemedAmountTokens: ethers.formatUnits(
      inputNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n),
      Number(wallet.wallet.canonicalAssetDecimals),
    ),
    gasUsed: receiptGasUsed(execution.receipt),
    txUrl: explorerTxUrl(contextResult.network, execution.receipt.hash),
    usedWorkspaceCache: contextResult.usingWorkspaceCache,
    recoveredWorkspace: contextResult.recoveredWorkspace,
    postTransactionRecovery: execution.postTransactionRecovery,
    warnings: walletWarnings,
    updatedRoots: execution.context.currentSnapshot.stateRoots,
  });
}

async function handleWalletGetNotes({ args, provider }) {
  const { wallet, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  expect(
    typeof wallet.wallet.controller === "string" && wallet.wallet.controller.length > 0,
    `Wallet ${wallet.walletName} is missing the stored controller address.`,
  );
  const canonicalAssetDecimals = Number(wallet.wallet.canonicalAssetDecimals);
  const contextResult = await loadFreshWalletChannelContext({
    walletContext: wallet,
    provider,
    progressAction: "wallet get-notes",
  });
  const context = contextResult.context;
  const noteReceiveFreshness = wallet.wallet.noteReceivePrivateKey
    ? await ensureWalletNoteReceiveStateCurrent({
      walletContext: wallet,
      context,
      provider,
      progressAction: "wallet get-notes",
      preConsumedBlockDelta: contextResult.autoRecoveryBlockDelta,
    })
    : {
      nextBlock: wallet.wallet.noteReceiveLastScannedBlock,
      targetBlock: walletNoteReceiveTargetBlock(context),
      targetNextBlock: channelWorkspaceRecoveryTargetNextBlock(context),
      recoveredWalletWorkspace: false,
      recoveredDeliveryState: null,
    };

  const unusedTrackedNotes = wallet.wallet.notes.unusedOrder
    .map((commitment) => wallet.wallet.notes.unused[commitment])
    .filter(Boolean);
  const spentTrackedNotes = Object.values(wallet.wallet.notes.spent).sort(compareNotesByValueDesc);

  const unusedNotes = await Promise.all(unusedTrackedNotes.map((note) => buildWalletNoteBridgeStatus({
    note,
    currentSnapshot: context.currentSnapshot,
    controllerAddress: wallet.wallet.controller,
    canonicalAssetDecimals,
  })));
  const spentNotes = await Promise.all(spentTrackedNotes.map((note) => buildWalletNoteBridgeStatus({
    note,
    currentSnapshot: context.currentSnapshot,
    controllerAddress: wallet.wallet.controller,
    canonicalAssetDecimals,
  })));

  const canComputeTotals = [...unusedTrackedNotes, ...spentTrackedNotes].every((note) => note.value !== null);
  const unusedTotal = canComputeTotals ? unusedTrackedNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n) : null;
  const spentTotal = canComputeTotals ? spentTrackedNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n) : null;
  const evidenceExport = args.exportEvidence
    ? await exportWalletGetNotesEvidenceBundle({
      args,
      provider,
      walletContext: wallet,
      walletMetadata,
      context,
      unusedTrackedNotes,
      spentTrackedNotes,
    })
    : null;

  printJson({
    action: "wallet get-notes",
    wallet: wallet.walletName,
    network: walletMetadata.network,
    channelName: walletMetadata.channelName,
    controller: wallet.wallet.controller,
    unusedNotes,
    spentNotes,
    unusedTotalBaseUnits: unusedTotal?.toString() ?? null,
    unusedTotalTokens: unusedTotal === null ? null : ethers.formatUnits(unusedTotal, canonicalAssetDecimals),
    spentTotalBaseUnits: spentTotal?.toString() ?? null,
    spentTotalTokens: spentTotal === null ? null : ethers.formatUnits(spentTotal, canonicalAssetDecimals),
    bridgeStatusMismatches: [...unusedNotes, ...spentNotes].filter((note) => !note.walletStatusMatchesBridge).length,
    noteReceiveLastScannedBlock: noteReceiveFreshness.nextBlock,
    noteReceiveTargetBlock: noteReceiveFreshness.targetBlock,
    noteReceiveTargetNextBlock: noteReceiveFreshness.targetNextBlock,
    viewingKeyAvailable: Boolean(wallet.wallet.noteReceivePrivateKey),
    recoveredWalletWorkspace: noteReceiveFreshness.recoveredWalletWorkspace,
    recoveredFromLogs: noteReceiveFreshness.recoveredDeliveryState?.importedNotes ?? 0,
    scannedDeliveryLogs: noteReceiveFreshness.recoveredDeliveryState?.scannedLogs ?? 0,
    linkedEvidence: noteReceiveFreshness.recoveredDeliveryState?.linkedEvidence ?? null,
    noteReceiveScanRange: noteReceiveFreshness.recoveredDeliveryState?.scanRange ?? null,
    evidenceExport,
  });
}

async function exportWalletGetNotesEvidenceBundle({
  args,
  provider,
  walletContext,
  walletMetadata,
  context,
  unusedTrackedNotes,
  spentTrackedNotes,
}) {
  const outputPath = path.resolve(String(requireArg(args.exportEvidence, "--export-evidence")));
  ensureDir(path.dirname(outputPath));

  const evidenceWalletContexts = loadWalletEpochContextsForEvidence({
    baseWalletContext: walletContext,
    networkName: walletMetadata.network,
  });
  const noteInputs = [];
  for (const candidateWalletContext of evidenceWalletContexts) {
    const notes = candidateWalletContext === walletContext
      ? [
        ...unusedTrackedNotes.map(normalizeTrackedNote),
        ...spentTrackedNotes.map(normalizeTrackedNote),
      ]
      : [
        ...Object.values(candidateWalletContext.wallet.notes.unused).map(normalizeTrackedNote),
        ...Object.values(candidateWalletContext.wallet.notes.spent).map(normalizeTrackedNote),
      ];
    for (const note of notes) {
      validateEvidenceNotePlaintext(note, candidateWalletContext.wallet);
      noteInputs.push({ note, walletContext: candidateWalletContext });
    }
  }
  noteInputs.sort((left, right) =>
    String(left.walletContext.wallet.walletEpochId ?? "").localeCompare(String(right.walletContext.wallet.walletEpochId ?? ""))
    || left.note.commitment.localeCompare(right.note.commitment));

  const txHashes = uniqueNonNull([
    ...noteInputs.map(({ note }) => note.createdAtTxHash),
    ...noteInputs.map(({ note }) => note.nullifierObservedAtTxHash),
    ...noteInputs.map(({ note }) => note.spentAtTxHash),
  ]);
  const transactionEvidence = await buildTransactionEvidenceMap({ provider, txHashes });
  const blockTimestampCache = buildBlockTimestampCache(transactionEvidence);
  const noteRecords = noteInputs.map(({ note, walletContext: noteWalletContext }) => buildEvidenceNoteRecord({
    note,
    walletContext: noteWalletContext,
    walletMetadata,
    context,
    transactionEvidence,
    blockTimestampCache,
  }));
  const indexes = buildEvidenceIndexes(noteRecords);
  const manifest = buildEvidenceManifest({
    outputPath,
    walletContext,
    walletContexts: evidenceWalletContexts,
    walletMetadata,
    context,
    noteRecords,
    txHashes,
  });

  const archive = new AdmZip();
  addEvidenceJson(archive, "manifest.json", manifest);
  addEvidenceJson(archive, "indexes/by-commitment.json", indexes.byCommitment);
  addEvidenceJson(archive, "indexes/by-nullifier.json", indexes.byNullifier);
  addEvidenceJson(archive, "indexes/by-creation-tx.json", indexes.byCreationTx);
  addEvidenceJson(archive, "indexes/by-spend-tx.json", indexes.bySpendTx);
  addEvidenceJson(archive, "indexes/by-block-range.json", indexes.byBlockRange);
  addEvidenceJson(archive, "indexes/by-counterparty.json", indexes.byCounterparty);
  for (const record of noteRecords) {
    addEvidenceJson(archive, evidenceNotePath(record), record);
  }
  for (const [txHash, txRecord] of Object.entries(transactionEvidence)) {
    addEvidenceJson(archive, `transactions/${txHash}.json`, txRecord.transaction);
    addEvidenceJson(archive, `receipts/${txHash}.json`, txRecord.receipt);
    addEvidenceJson(archive, `events/${txHash}.json`, txRecord.events);
  }

  assertEvidenceBundleDoesNotContainSecrets({
    wallets: evidenceWalletContexts.map((entry) => entry.wallet),
    payload: {
      manifest,
      indexes,
      noteRecords,
      transactionEvidence,
    },
  });
  fs.rmSync(outputPath, { force: true });
  archive.writeZip(outputPath);
  protectSecretFile(outputPath, "wallet evidence export ZIP");

  return {
    output: outputPath,
    format: WALLET_EVIDENCE_BUNDLE_FORMAT,
    formatVersion: WALLET_EVIDENCE_BUNDLE_FORMAT_VERSION,
    noteCount: noteRecords.length,
    walletEpochCount: evidenceWalletContexts.length,
    transactionCount: txHashes.length,
    containsNotePlaintext: true,
    containsSpendingKey: false,
    containsViewingKey: false,
    containsWalletSecret: false,
    warning: "Local full-note evidence bundle. Do not submit as-is unless full wallet-history disclosure is intended.",
  };
}

function loadWalletEpochContextsForEvidence({ baseWalletContext, networkName }) {
  const walletRoot = walletRootPath(baseWalletContext.walletName, networkName);
  const index = requireWalletIndex({
    walletRoot,
    walletName: baseWalletContext.walletName,
    networkName,
  });
  const contexts = [];
  for (const epoch of index.epochs) {
    const walletDir = walletEpochPathFromRoot(walletRoot, epoch.epochId);
    if (!walletConfigExists(walletDir)) {
      continue;
    }
    const context = loadWalletFromDir({
      walletName: baseWalletContext.walletName,
      networkName,
      walletDir,
    });
    contexts.push(context);
  }
  expect(
    contexts.length > 0,
    `Wallet ${baseWalletContext.walletName} on ${networkName} has no readable wallet epochs. Run wallet recover-workspace and then wallet get-notes --export-evidence again.`,
  );
  return contexts;
}

function validateEvidenceNotePlaintext(note, wallet) {
  expect(
    note.owner && note.value !== null && note.salt && note.encryptedNoteValue,
    [
      `Cannot export evidence for note ${note.commitment} because plaintext note data is incomplete.`,
      "Import the wallet viewing key and run wallet recover-workspace before exporting evidence.",
    ].join(" "),
  );
  expect(
    getAddress(note.owner) === getAddress(wallet.l2Address),
    `Cannot export evidence for note ${note.commitment}: owner does not match wallet L2 address.`,
  );
  const recomputedSalt = computeEncryptedNoteSalt(note.encryptedNoteValue);
  expect(
    ethers.toBigInt(recomputedSalt) === ethers.toBigInt(note.salt),
    `Cannot export evidence for note ${note.commitment}: encrypted note salt mismatch.`,
  );
  const plaintext = normalizePlaintextNote(note);
  expect(
    ethers.toBigInt(computeNoteCommitment(plaintext)) === ethers.toBigInt(note.commitment),
    `Cannot export evidence for note ${note.commitment}: commitment mismatch.`,
  );
  expect(
    ethers.toBigInt(computeNullifier(plaintext)) === ethers.toBigInt(note.nullifier),
    `Cannot export evidence for note ${note.commitment}: nullifier mismatch.`,
  );
}

function buildEvidencePublicLinkageMap({ context, noteInputs, storageObservationLogs }) {
  const storageLayoutManifest = readJson(context.workspace.storageLayoutPath);
  const commitmentExistsSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "commitmentExists"));
  const nullifierUsedSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "nullifierUsed"));
  const linkageByCommitment = {};
  const targetKeys = new Map();
  for (const { note } of noteInputs) {
    const commitmentKey = normalizeBytes32Hex(
      note.bridgeCommitmentKey ?? derivePrivateStateControllerMappingStorageKey(note.commitment, commitmentExistsSlot),
    );
    const nullifierKey = normalizeBytes32Hex(
      note.bridgeNullifierKey ?? derivePrivateStateControllerMappingStorageKey(note.nullifier, nullifierUsedSlot),
    );
    linkageByCommitment[note.commitment] = {
      commitment: {
        storageKey: commitmentKey,
        observation: null,
      },
      nullifier: {
        storageKey: nullifierKey,
        observation: null,
      },
    };
    targetKeys.set(ethers.toBigInt(commitmentKey).toString(), {
      commitment: note.commitment,
      type: "commitment",
    });
    targetKeys.set(ethers.toBigInt(nullifierKey).toString(), {
      commitment: note.commitment,
      type: "nullifier",
    });
  }
  for (const log of storageObservationLogs ?? []) {
    const storageKey = decodeControllerStorageKeyObservedLog(log);
    if (!storageKey) {
      continue;
    }
    const target = targetKeys.get(ethers.toBigInt(storageKey).toString());
    if (!target) {
      continue;
    }
    const linkage = linkageByCommitment[target.commitment]?.[target.type];
    if (!linkage || linkage.observation) {
      continue;
    }
    linkage.observation = {
      txHash: normalizeBytes32Hex(log.transactionHash),
      blockNumber: Number(log.blockNumber),
      logIndex: Number(log.index ?? log.logIndex),
      contract: getAddress(log.address),
      storageKey,
    };
  }
  return linkageByCommitment;
}

function decodeControllerStorageKeyObservedLog(log) {
  try {
    const topic0 = log.topics?.[0] ? normalizeBytes32Hex(log.topics[0]) : null;
    if (topic0 !== normalizeBytes32Hex(CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC)) {
      return null;
    }
    const { storageKey } = controllerStorageKeyObservedEventInterface.decodeEventLog(
      "StorageKeyObserved",
      log.data,
      log.topics,
    );
    return normalizeBytes32Hex(storageKey);
  } catch {
    return null;
  }
}

function applyEvidencePublicLinkage(note, linkage) {
  if (!linkage) {
    return note;
  }
  const commitmentObservation = linkage.commitment?.observation ?? null;
  const nullifierObservation = linkage.nullifier?.observation ?? null;
  const observedSpendTxHash = note.status === "spent" ? nullifierObservation?.txHash ?? null : null;
  const observedSpendReplacesExisting =
    observedSpendTxHash
    && (!note.spentAtTxHash || ethers.toBigInt(note.spentAtTxHash) !== ethers.toBigInt(observedSpendTxHash));
  return {
    ...note,
    bridgeCommitmentKey: note.bridgeCommitmentKey ?? linkage.commitment?.storageKey ?? null,
    bridgeNullifierKey: note.bridgeNullifierKey ?? linkage.nullifier?.storageKey ?? null,
    commitmentObservedAtTxHash: note.commitmentObservedAtTxHash ?? commitmentObservation?.txHash ?? null,
    commitmentObservedAtBlockNumber: note.commitmentObservedAtBlockNumber ?? commitmentObservation?.blockNumber ?? null,
    commitmentObservedAtLogIndex: note.commitmentObservedAtLogIndex ?? commitmentObservation?.logIndex ?? null,
    nullifierObservedAtTxHash: note.nullifierObservedAtTxHash ?? nullifierObservation?.txHash ?? null,
    nullifierObservedAtBlockNumber: note.nullifierObservedAtBlockNumber ?? nullifierObservation?.blockNumber ?? null,
    nullifierObservedAtLogIndex: note.nullifierObservedAtLogIndex ?? nullifierObservation?.logIndex ?? null,
    createdAtTxHash: note.createdAtTxHash ?? commitmentObservation?.txHash ?? null,
    createdAtBlockNumber: note.createdAtBlockNumber ?? commitmentObservation?.blockNumber ?? null,
    createdAtLogIndex: note.createdAtLogIndex ?? commitmentObservation?.logIndex ?? null,
    spentAtTxHash: observedSpendTxHash ?? note.spentAtTxHash ?? null,
    spentAtBlockNumber: observedSpendTxHash ? nullifierObservation?.blockNumber ?? null : note.spentAtBlockNumber ?? null,
    spentAtLogIndex: observedSpendTxHash ? nullifierObservation?.logIndex ?? null : note.spentAtLogIndex ?? null,
    spentByFunction: observedSpendReplacesExisting ? null : note.spentByFunction ?? null,
    commitmentObservation,
    nullifierObservation,
  };
}

function applyEvidenceLinkageToWalletFromStorageObservations({ walletContext, context, storageObservationLogs }) {
  const unusedNotes = Object.values(walletContext.wallet.notes.unused ?? {}).map(normalizeTrackedNote);
  const spentNotes = Object.values(walletContext.wallet.notes.spent ?? {}).map(normalizeTrackedNote);
  const allNotes = [...unusedNotes, ...spentNotes];
  if (allNotes.length === 0) {
    return {
      linkedCommitments: 0,
      linkedNullifiers: 0,
    };
  }

  const linkageByCommitment = buildEvidencePublicLinkageMap({
    context,
    noteInputs: allNotes.map((note) => ({ note })),
    storageObservationLogs,
  });
  let linkedCommitments = 0;
  let linkedNullifiers = 0;
  const linkNote = (note) => {
    const linkedNote = normalizeTrackedNote(applyEvidencePublicLinkage(note, linkageByCommitment[note.commitment]));
    if (linkedNote.commitmentObservedAtTxHash) {
      linkedCommitments += 1;
    }
    if (linkedNote.nullifierObservedAtTxHash) {
      linkedNullifiers += 1;
    }
    return linkedNote;
  };
  const linkedUnusedNotes = unusedNotes.map(linkNote);
  const linkedSpentNotes = spentNotes.map(linkNote);
  walletContext.wallet.notes.unused = Object.fromEntries(linkedUnusedNotes.map((note) => [note.commitment, note]));
  walletContext.wallet.notes.spent = Object.fromEntries(linkedSpentNotes.map((note) => [note.nullifier, note]));
  walletContext.wallet = normalizeWallet(walletContext.wallet);
  return {
    linkedCommitments,
    linkedNullifiers,
  };
}

async function buildTransactionEvidenceMap({ provider, txHashes }) {
  const entries = {};
  for (const txHash of txHashes) {
    const [transaction, receipt] = await Promise.all([
      provider.getTransaction(txHash).catch(() => null),
      provider.getTransactionReceipt(txHash).catch(() => null),
    ]);
    const blockNumber = receipt?.blockNumber ?? transaction?.blockNumber ?? null;
    const block = blockNumber === null ? null : await provider.getBlock(blockNumber).catch(() => null);
    entries[txHash] = {
      transaction: sanitizeTransactionEvidence(transaction, block),
      receipt: receipt ? sanitizeReceipt(receipt) : null,
      events: receipt ? sanitizeReceiptEvents(receipt) : [],
    };
  }
  return entries;
}

function sanitizeTransactionEvidence(transaction, block) {
  if (!transaction) {
    return null;
  }
  return normalizeCliOutput(serializeBigInts({
    hash: transaction.hash,
    from: transaction.from,
    to: transaction.to,
    nonce: transaction.nonce,
    data: transaction.data,
    value: transaction.value,
    chainId: transaction.chainId,
    blockHash: transaction.blockHash,
    blockNumber: transaction.blockNumber,
    blockTimestamp: block?.timestamp ?? null,
    blockTimestampIso: block?.timestamp ? new Date(Number(block.timestamp) * 1000).toISOString() : null,
  }));
}

function sanitizeReceiptEvents(receipt) {
  return (receipt.logs ?? []).map((log) => normalizeCliOutput(serializeBigInts({
    address: log.address,
    blockHash: log.blockHash,
    blockNumber: log.blockNumber,
    transactionHash: log.transactionHash,
    transactionIndex: log.transactionIndex,
    logIndex: log.index ?? log.logIndex ?? null,
    topics: log.topics,
    data: log.data,
  })));
}

function buildBlockTimestampCache(transactionEvidence) {
  const cache = {};
  for (const txRecord of Object.values(transactionEvidence)) {
    const tx = txRecord.transaction;
    if (tx?.blockNumber !== null && tx?.blockNumber !== undefined) {
      cache[Number(tx.blockNumber)] = {
        timestamp: tx.blockTimestamp ?? null,
        iso: tx.blockTimestampIso ?? null,
      };
    }
  }
  return cache;
}

function buildEvidenceNoteRecord({
  note,
  walletContext,
  walletMetadata,
  context,
  transactionEvidence,
  blockTimestampCache,
}) {
  const creationBlockNumber = note.createdAtBlockNumber
    ?? transactionEvidence[note.createdAtTxHash]?.transaction?.blockNumber
    ?? null;
  const spentTxHash = note.nullifierObservedAtTxHash ?? note.spentAtTxHash ?? null;
  const spentBlockNumber = note.nullifierObservedAtBlockNumber
    ?? note.spentAtBlockNumber
    ?? transactionEvidence[spentTxHash]?.transaction?.blockNumber
    ?? null;
  const commitmentObservationTxHash = note.commitmentObservedAtTxHash ?? note.createdAtTxHash ?? null;
  const commitmentObservationBlockNumber = note.commitmentObservedAtBlockNumber ?? creationBlockNumber;
  const nullifierObservationTxHash = note.nullifierObservedAtTxHash ?? spentTxHash;
  const nullifierObservationBlockNumber = note.nullifierObservedAtBlockNumber ?? spentBlockNumber;
  const spentLogIndex = note.nullifierObservedAtLogIndex ?? note.spentAtLogIndex ?? null;
  const commitmentObservation = commitmentObservationTxHash ? {
    txHash: commitmentObservationTxHash,
    blockNumber: commitmentObservationBlockNumber,
    logIndex: note.commitmentObservedAtLogIndex,
    contract: context.workspace.channelManager,
    storageKey: note.bridgeCommitmentKey,
  } : null;
  const nullifierObservation = nullifierObservationTxHash ? {
    txHash: nullifierObservationTxHash,
    blockNumber: nullifierObservationBlockNumber,
    logIndex: spentLogIndex,
    contract: context.workspace.channelManager,
    storageKey: note.bridgeNullifierKey,
  } : null;
  const scheme = note.encryptedNoteValue ? unpackEncryptedNoteValue(note.encryptedNoteValue).scheme : null;
  return normalizeCliOutput({
    recordType: "note-evidence",
    recordVersion: 1,
    noteId: note.commitment,
    walletScope: {
      network: walletMetadata.network,
      chainId: walletContext.wallet.chainId,
      channelName: walletMetadata.channelName,
      channelId: walletContext.wallet.channelId,
      wallet: walletContext.walletName,
      ...walletLifecycleMetadata(walletContext.wallet),
      walletL1Address: walletContext.wallet.l1Address,
      walletL2Address: walletContext.wallet.l2Address,
      controller: context.workspace.controller,
    },
    plaintext: {
      owner: note.owner,
      value: note.value,
      salt: note.salt,
    },
    derived: {
      commitment: note.commitment,
      nullifier: note.nullifier,
      commitmentStorageKey: note.bridgeCommitmentKey,
      nullifierStorageKey: note.bridgeNullifierKey,
    },
    publicStorageObservations: {
      commitment: commitmentObservation,
      nullifier: nullifierObservation,
    },
    encryptedDelivery: {
      encryptedNoteValue: note.encryptedNoteValue,
      saltDerivation: "poseidon(encryptedNoteValue)",
      scheme: encryptedNoteSchemeLabel(scheme),
      event: {
        txHash: note.createdAtTxHash,
        blockNumber: creationBlockNumber,
        blockTimestamp: blockTimestampCache[Number(creationBlockNumber)]?.timestamp ?? null,
        blockTimestampIso: blockTimestampCache[Number(creationBlockNumber)]?.iso ?? null,
        logIndex: note.createdAtLogIndex,
        contract: context.workspace.channelManager,
      },
    },
    creation: {
      txHash: note.createdAtTxHash,
      blockNumber: creationBlockNumber,
      blockTimestamp: blockTimestampCache[Number(creationBlockNumber)]?.timestamp ?? null,
      blockTimestampIso: blockTimestampCache[Number(creationBlockNumber)]?.iso ?? null,
      function: note.createdByFunction,
      outputIndex: note.createdOutputIndex,
      acceptedTransition: acceptedTransitionReference(note.createdAtTxHash),
      storageObservation: commitmentObservation,
    },
    spend: {
      status: note.status,
      txHash: spentTxHash,
      blockNumber: spentBlockNumber,
      blockTimestamp: blockTimestampCache[Number(spentBlockNumber)]?.timestamp ?? null,
      blockTimestampIso: blockTimestampCache[Number(spentBlockNumber)]?.iso ?? null,
      logIndex: spentLogIndex,
      function: note.spentByFunction,
      inputIndex: note.spentInputIndex,
      acceptedTransition: spentTxHash ? acceptedTransitionReference(spentTxHash) : null,
      storageObservation: nullifierObservation,
    },
    relationshipHints: {
      direction: note.counterpartyDirection ?? inferEvidenceDirection(note, scheme),
      counterpartyL2Address: note.counterpartyL2Address,
      counterpartyL1Address: null,
      confidence: note.counterpartyConfidence ?? (note.counterpartyL2Address ? "direct-local-metadata" : "unavailable"),
    },
    verificationClaims: {
      commitmentRecomputesFromPlaintext: true,
      nullifierRecomputesFromPlaintext: true,
      ownerMatchesWalletL2Address: true,
      spendingKeyIncluded: false,
      viewingKeyIncluded: false,
      walletSecretIncluded: false,
      fullWalletHistoryRequiredForFinalDisclosure: false,
    },
  });
}

function acceptedTransitionReference(txHash) {
  if (!txHash) {
    return null;
  }
  return {
    txHash,
    transactionPath: `transactions/${txHash}.json`,
    receiptPath: `receipts/${txHash}.json`,
    eventsPath: `events/${txHash}.json`,
    proofCalldataLocation: "transactions[].data",
    localProofArtifactIncluded: false,
  };
}

function encryptedNoteSchemeLabel(scheme) {
  if (scheme === ENCRYPTED_NOTE_SCHEME_SELF_MINT) {
    return "self-mint";
  }
  if (scheme === ENCRYPTED_NOTE_SCHEME_TRANSFER) {
    return "transfer";
  }
  return "unknown";
}

function inferEvidenceDirection(note, scheme) {
  if (scheme === ENCRYPTED_NOTE_SCHEME_SELF_MINT) {
    return "self-mint";
  }
  if (note.spentByFunction?.startsWith("transferNotes")) {
    return "sent";
  }
  if (note.createdByFunction?.startsWith("transferNotes")) {
    return "received";
  }
  return "unknown";
}

function buildEvidenceIndexes(noteRecords) {
  const indexes = {
    byCommitment: {},
    byNullifier: {},
    byCreationTx: {},
    bySpendTx: {},
    byBlockRange: [],
    byCounterparty: {
      unavailable: [],
    },
  };
  for (const record of noteRecords) {
    const pathName = evidenceNotePath(record);
    indexes.byCommitment[record.derived.commitment] = pathName;
    indexes.byNullifier[record.derived.nullifier] = pathName;
    pushIndexEntry(indexes.byCreationTx, record.creation.txHash, pathName);
    pushIndexEntry(indexes.bySpendTx, record.spend.txHash, pathName);
    indexes.byBlockRange.push({
      commitment: record.derived.commitment,
      createdAtBlockNumber: record.creation.blockNumber,
      spentAtBlockNumber: record.spend.blockNumber,
      path: pathName,
    });
    const counterparty = record.relationshipHints.counterpartyL2Address;
    if (counterparty) {
      if (!indexes.byCounterparty[counterparty]) {
        indexes.byCounterparty[counterparty] = { sent: [], received: [], both: [] };
      }
      const direction = record.relationshipHints.direction === "received" ? "received" : "sent";
      indexes.byCounterparty[counterparty][direction].push(pathName);
      indexes.byCounterparty[counterparty].both.push(pathName);
    } else {
      indexes.byCounterparty.unavailable.push(pathName);
    }
  }
  indexes.byBlockRange.sort((left, right) =>
    Number(left.createdAtBlockNumber ?? Number.MAX_SAFE_INTEGER)
      - Number(right.createdAtBlockNumber ?? Number.MAX_SAFE_INTEGER));
  return indexes;
}

function evidenceNotePath(record) {
  expect(
    record.walletScope?.canonicalWalletName && record.walletScope?.epochId,
    "Evidence note path requires the current epoch-aware wallet scope.",
  );
  return [
    "wallets",
    slugifyPathComponent(record.walletScope.canonicalWalletName),
    "epochs",
    slugifyPathComponent(record.walletScope.epochId),
    "notes",
    `${record.derived.commitment}.json`,
  ].join("/");
}

function pushIndexEntry(index, key, value) {
  if (!key) {
    return;
  }
  if (!index[key]) {
    index[key] = [];
  }
  index[key].push(value);
}

function buildEvidenceManifest({
  outputPath,
  walletContext,
  walletContexts = [walletContext],
  walletMetadata,
  context,
  noteRecords,
  txHashes,
}) {
  return normalizeCliOutput({
    format: WALLET_EVIDENCE_BUNDLE_FORMAT,
    formatVersion: WALLET_EVIDENCE_BUNDLE_FORMAT_VERSION,
    bundleType: "local-full-note-evidence",
    generatedAt: new Date().toISOString(),
    outputFileName: path.basename(outputPath),
    network: walletMetadata.network,
    chainId: walletContext.wallet.chainId,
    channelName: walletMetadata.channelName,
    channelId: walletContext.wallet.channelId,
    wallet: walletContext.walletName,
    walletL1Address: walletContext.wallet.l1Address,
    walletL2Address: walletContext.wallet.l2Address,
    wallets: walletContexts.map((entry) => ({
      wallet: entry.walletName,
      ...walletLifecycleMetadata(entry.wallet),
      walletL1Address: entry.wallet.l1Address,
      walletL2Address: entry.wallet.l2Address,
    })),
    controller: context.workspace.controller,
    channelManager: context.workspace.channelManager,
    bridgeTokenVault: context.workspace.bridgeTokenVault,
    containsAllLocallyKnownNotes: true,
    containsAllLocalWalletEpochs: true,
    containsNotePlaintext: true,
    noteCount: noteRecords.length,
    transactionCount: txHashes.length,
    intendedUse: "Input for private-state-cli investigator; not a default exchange submission package.",
    warning: "DO_NOT_SUBMIT_AS_IS unless full wallet-history disclosure is intended.",
    excludedSecrets: {
      spendingKey: true,
      viewingKey: true,
      walletSecret: true,
      accountPrivateKey: true,
      keyFiles: true,
    },
  });
}

function addEvidenceJson(archive, archivePath, value) {
  archive.addFile(archivePath, Buffer.from(`${JSON.stringify(normalizeCliOutput(value), null, 2)}\n`, "utf8"));
}

function assertEvidenceBundleDoesNotContainSecrets({ wallet = null, wallets = null, payload }) {
  const serialized = JSON.stringify(payload);
  const walletList = wallets ?? (wallet ? [wallet] : []);
  const forbiddenValues = walletList.flatMap((entry) => [
    entry.l2PrivateKey,
    entry.noteReceivePrivateKey,
  ]).filter((value) => typeof value === "string" && value.length > 0);
  for (const value of forbiddenValues) {
    expect(
      !serialized.includes(value),
      "Evidence export refused to write authority-bearing wallet secret material.",
    );
  }
}

function uniqueNonNull(values) {
  return [...new Set(values.filter((value) => typeof value === "string" && value.length > 0))];
}

async function handleTransferNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  requireActiveWalletLifecycle(wallet, "wallet transfer-notes");
  requireWalletViewingCapability(wallet);
  requireWalletSpendingCapability(wallet);
  const { signer } = restoreWalletParticipant(wallet, provider);
  const preparedContextResult = await loadFreshWalletChannelContext({
    walletContext: wallet,
    provider,
    progressAction: "wallet transfer-notes",
  });
  const context = preparedContextResult.context;
  await ensureWalletNoteReceiveStateCurrent({
    walletContext: wallet,
    context,
    provider,
    signer,
    progressAction: "wallet transfer-notes",
    preConsumedBlockDelta: preparedContextResult.autoRecoveryBlockDelta,
  });
  const canonicalAssetDecimals = Number(wallet.wallet.canonicalAssetDecimals);
  const noteIds = parseNoteIdVector(requireArg(args.noteIds, "--note-ids"));
  const recipients = parseRecipientVector(requireArg(args.recipients, "--recipients"));
  const amountInputs = parseAmountVector(requireArg(args.amounts, "--amounts"));
  expect(
    recipients.length === amountInputs.length,
    "--amounts length must match --recipients length.",
  );

  const outputAmounts = amountInputs.map((value, index) => {
    const parsed = parseTokenAmount(value, canonicalAssetDecimals);
    expect(parsed > 0n, `Invalid --amounts[${index}]. Each amount must be greater than zero.`);
    return parsed;
  });
  const inputNotes = loadWalletUnusedInputNotes(wallet, noteIds);
  const totalInput = inputNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n);
  const totalOutput = outputAmounts.reduce((sum, value) => sum + value, 0n);
  expect(
    totalInput === totalOutput,
    "The sum of --amounts must equal the sum of the selected input note values.",
  );

  const { txSubmitter } = resolveTxSubmitterSigner({
    args,
    ownerSigner: signer,
    provider,
  });
  await requireActionImpactAcknowledgement("wallet-transfer-notes", args, {
    l1Address: txSubmitter.address,
    l2Address: wallet.wallet.l2Address,
    noteIds: noteIds.join(", "),
    amounts: amountInputs.join(", "),
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
  });
  const templatePayload = await buildTransferNotesTemplatePayload({
    context,
    signer,
    inputNotes,
    recipients,
    outputAmounts,
  });
  const { execution, contextResult, walletWarnings } = await executeWalletDirectTemplateCommand({
    args,
    wallet,
    provider,
    operationName: "wallet transfer-notes",
    templatePayload,
    preparedContextResult,
  });
  const outputNotes = buildLifecycleTrackedOutputs({
    outputNotes: templatePayload.lifecycleOutputs,
    sourceFunction: templatePayload.method,
    sourceTxHash: execution.receipt.hash,
    sourceBlockNumber: execution.receipt.blockNumber,
    counterpartyL2Addresses: templatePayload.recipientAddresses,
    counterpartyDirection: "sent",
  });

  printJson({
    action: "wallet transfer-notes",
    wallet: wallet.walletName,
    workspace: execution.context.workspaceName,
    operationDir: execution.operationDir,
    l1Submitter: execution.txSubmitter.address,
    l1WalletOwner: execution.signer.address,
    txSubmitterSource: execution.txSubmitterSource,
    txSubmitterAccount: execution.txSubmitterAccount,
    l2Address: execution.l2Identity.l2Address,
    underlyingMethod: templatePayload.method,
    nonce: execution.nonce,
    noteIds,
    recipients,
    amountInputs,
    amountBaseUnits: outputAmounts.map((value) => value.toString()),
    outputNotes,
    deliveredRecipients: [],
    noteDelivery: "ethereum-event-log",
    gasUsed: receiptGasUsed(execution.receipt),
    txUrl: explorerTxUrl(contextResult.network, execution.receipt.hash),
    usedWorkspaceCache: contextResult.usingWorkspaceCache,
    recoveredWorkspace: contextResult.recoveredWorkspace,
    postTransactionRecovery: execution.postTransactionRecovery,
    warnings: walletWarnings,
    updatedRoots: execution.context.currentSnapshot.stateRoots,
  });
}

function mergeTrackedNotesIntoWallet(walletContext, trackedNotes) {
  const imported = [];
  for (const note of trackedNotes) {
    const trackedNote = buildImportedTrackedNote(note);
    expect(
      trackedNote.owner === walletContext.wallet.l2Address,
      [
        `Imported note owner ${trackedNote.owner} does not match wallet ${walletContext.walletName}`,
        `owner ${walletContext.wallet.l2Address}.`,
      ].join(" "),
    );
    const existingSpent = walletContext.wallet.notes.spent[trackedNote.nullifier];
    if (existingSpent) {
      continue;
    }
    const existingUnused = walletContext.wallet.notes.unused[trackedNote.commitment];
    if (existingUnused) {
      continue;
    }
    walletContext.wallet.notes.unused[trackedNote.commitment] = trackedNote;
    imported.push(trackedNote);
  }
  walletContext.wallet = normalizeWallet(walletContext.wallet);
  return imported;
}

async function reconcileWalletNotesWithBridgeState({
  walletContext,
  currentSnapshot,
  controllerAddress,
}) {
  const reconciledUnused = {};
  const reconciledSpent = {};
  const trackedNotes = [
    ...Object.values(walletContext.wallet.notes.unused),
    ...Object.values(walletContext.wallet.notes.spent),
  ];

  for (const note of trackedNotes) {
    const normalizedNote = normalizeTrackedNote(note);
    const commitmentExists = await readBooleanStorageValueFromSnapshot({
      snapshot: currentSnapshot,
      storageAddress: controllerAddress,
      storageKey: normalizedNote.bridgeCommitmentKey,
    });
    if (!commitmentExists) {
      continue;
    }

    const nullifierUsed = await readBooleanStorageValueFromSnapshot({
      snapshot: currentSnapshot,
      storageAddress: controllerAddress,
      storageKey: normalizedNote.bridgeNullifierKey,
    });
    const reconciledNote = {
      ...normalizedNote,
      status: nullifierUsed ? "spent" : "unused",
    };
    if (nullifierUsed) {
      reconciledSpent[reconciledNote.nullifier] = reconciledNote;
    } else {
      reconciledUnused[reconciledNote.commitment] = reconciledNote;
    }
  }

  walletContext.wallet.notes = {
    unused: reconciledUnused,
    spent: reconciledSpent,
    unusedOrder: Object.values(reconciledUnused)
      .sort(compareNotesByValueDesc)
      .map((note) => note.commitment),
    unusedBalance: Object.values(reconciledUnused)
      .reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n)
      .toString(),
  };
  walletContext.wallet = normalizeWallet(walletContext.wallet);
  return {
    unusedCount: Object.keys(walletContext.wallet.notes.unused).length,
    spentCount: Object.keys(walletContext.wallet.notes.spent).length,
  };
}

function ensureWallet({
  channelContext,
  signerAddress,
  signerPrivateKey,
  l2Identity,
  walletSecret,
  storageKey,
  leafIndex,
  noteReceiveKeyMaterial,
  lifecycleEpoch,
  rpcUrl,
}) {
  const walletName = walletNameForChannelAndAddress(channelContext.workspace.channelName, signerAddress);
  const walletRoot = walletRootPath(walletName, channelContext.workspace.network);
  if (fs.existsSync(walletRoot)) {
    requireWalletIndex({
      walletRoot,
      walletName,
      networkName: channelContext.workspace.network,
    });
  }
  expect(lifecycleEpoch, "Current wallet workspace creation requires an on-chain wallet lifecycle epoch.");
  const walletDir = walletEpochPath(walletName, channelContext.workspace.network, lifecycleEpoch.epochId);
  expect(!walletConfigExists(walletDir), `Wallet ${walletName} already exists on ${channelContext.workspace.network}.`);
  ensureDir(walletDir);
  ensureDir(path.join(walletDir, "operations"));

  const wallet = normalizeWallet({
    walletFormatVersion: WALLET_WORKSPACE_FORMAT_VERSION,
    name: walletName,
    canonicalWalletName: walletName,
    walletEpochId: lifecycleEpoch.epochId,
    lifecycleStatus: lifecycleEpoch.lifecycleStatus,
    joinedAtTxHash: lifecycleEpoch.joinedAtTxHash,
    joinedAtBlockNumber: lifecycleEpoch.joinedAtBlockNumber,
    joinedAtLogIndex: lifecycleEpoch.joinedAtLogIndex,
    joinedAtBlockTimestamp: lifecycleEpoch.joinedAtBlockTimestamp,
    joinedAtBlockTimestampIso: lifecycleEpoch.joinedAtBlockTimestampIso,
    exitedAtTxHash: lifecycleEpoch.exitedAtTxHash,
    exitedAtBlockNumber: lifecycleEpoch.exitedAtBlockNumber,
    exitedAtLogIndex: lifecycleEpoch.exitedAtLogIndex,
    exitedAtBlockTimestamp: lifecycleEpoch.exitedAtBlockTimestamp,
    exitedAtBlockTimestampIso: lifecycleEpoch.exitedAtBlockTimestampIso,
    network: channelContext.workspace.network,
    rpcUrl,
    chainId: channelContext.workspace.chainId,
    appDeploymentPath: channelContext.workspace.appDeploymentPath,
    storageLayoutPath: channelContext.workspace.storageLayoutPath,
    channelName: channelContext.workspace.channelName,
    channelId: channelContext.workspace.channelId,
    channelManager: channelContext.workspace.channelManager,
    bridgeTokenVault: channelContext.workspace.bridgeTokenVault,
    canonicalAsset: channelContext.workspace.canonicalAsset,
    canonicalAssetDecimals: channelContext.workspace.canonicalAssetDecimals,
    controller: channelContext.workspace.controller,
    l2AccountingVault: channelContext.workspace.l2AccountingVault,
    liquidBalancesSlot: channelContext.workspace.liquidBalancesSlot,
    l1Address: signerAddress,
    l2Address: l2Identity.l2Address,
    l2PublicKey: l2Identity.l2PublicKey ? ethers.hexlify(l2Identity.l2PublicKey) : null,
    l2DerivationMode: CHANNEL_BOUND_L2_DERIVATION_MODE,
    l2DerivationChannelName: channelContext.workspace.channelName,
    l2StorageKey: storageKey,
    leafIndex: leafIndex?.toString() ?? null,
    noteReceiveDerivationVersion: NOTE_RECEIVE_KEY_DERIVATION_VERSION,
    noteReceiveTypedDataMethod: NOTE_RECEIVE_TYPED_DATA_METHOD,
    noteReceivePubKeyX: normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x),
    noteReceivePubKeyYParity: Number(noteReceiveKeyMaterial.noteReceivePubKey.yParity),
    noteReceiveLastScannedBlock: Number(channelContext.workspace.genesisBlockNumber),
    l2Nonce: 0,
    notes: {
      unused: {},
      spent: {},
    },
  });
  if (l2Identity.l2PrivateKey) {
    wallet.l2PrivateKey = ethers.hexlify(l2Identity.l2PrivateKey);
  }
  wallet.noteReceivePrivateKey = normalizePrivateKey(noteReceiveKeyMaterial.privateKey);

  const context = {
    walletName,
    walletDir,
    wallet,
    walletSecret: wallet.l2PrivateKey,
  };
  persistWalletKeys(context);
  persistWallet(context);
  persistWalletIndexForContext(context);
  return context;
}

function applyWalletLifecycleEpoch(wallet, epoch) {
  wallet.canonicalWalletName = wallet.name;
  wallet.walletEpochId = epoch.epochId;
  wallet.lifecycleStatus = epoch.lifecycleStatus;
  wallet.joinedAtTxHash = epoch.joinedAtTxHash;
  wallet.joinedAtBlockNumber = epoch.joinedAtBlockNumber;
  wallet.joinedAtLogIndex = epoch.joinedAtLogIndex;
  wallet.joinedAtBlockTimestamp = epoch.joinedAtBlockTimestamp;
  wallet.joinedAtBlockTimestampIso = epoch.joinedAtBlockTimestampIso;
  wallet.exitedAtTxHash = epoch.exitedAtTxHash;
  wallet.exitedAtBlockNumber = epoch.exitedAtBlockNumber;
  wallet.exitedAtLogIndex = epoch.exitedAtLogIndex;
  wallet.exitedAtBlockTimestamp = epoch.exitedAtBlockTimestamp;
  wallet.exitedAtBlockTimestampIso = epoch.exitedAtBlockTimestampIso;
}

function walletLifecycleMetadata(wallet) {
  expect(wallet.walletEpochId, "Current wallet workspace metadata is missing walletEpochId.");
  return {
    canonicalWalletName: wallet.canonicalWalletName ?? wallet.name,
    epochId: wallet.walletEpochId,
    lifecycleStatus: wallet.lifecycleStatus ?? "active",
    joinedAtTxHash: wallet.joinedAtTxHash ?? null,
    joinedAtBlockNumber: wallet.joinedAtBlockNumber ?? null,
    joinedAtLogIndex: wallet.joinedAtLogIndex ?? null,
    joinedAtBlockTimestamp: wallet.joinedAtBlockTimestamp ?? null,
    joinedAtBlockTimestampIso: wallet.joinedAtBlockTimestampIso ?? null,
    exitedAtTxHash: wallet.exitedAtTxHash ?? null,
    exitedAtBlockNumber: wallet.exitedAtBlockNumber ?? null,
    exitedAtLogIndex: wallet.exitedAtLogIndex ?? null,
    exitedAtBlockTimestamp: wallet.exitedAtBlockTimestamp ?? null,
    exitedAtBlockTimestampIso: wallet.exitedAtBlockTimestampIso ?? null,
  };
}

function normalizeWallet(wallet) {
  assertWalletHasCurrentFormat(wallet, wallet.name ?? "unknown");
  expect(wallet.walletEpochId, "Current wallet metadata requires walletEpochId. Run wallet recover-workspace to rebuild this wallet.");
  const unusedNotes = Object.values(wallet.notes.unused).map(normalizeTrackedNote);
  unusedNotes.sort(compareNotesByValueDesc);
  const spentNotes = Object.values(wallet.notes.spent).map(normalizeTrackedNote);

  return {
    ...wallet,
    canonicalWalletName: wallet.canonicalWalletName ?? wallet.name,
    walletEpochId: wallet.walletEpochId,
    lifecycleStatus: wallet.lifecycleStatus ?? "active",
    canonicalAssetDecimals: Number(wallet.canonicalAssetDecimals),
    l2Nonce: Number(wallet.l2Nonce),
    l2PrivateKey: wallet.l2PrivateKey ? ethers.hexlify(wallet.l2PrivateKey) : null,
    l2PublicKey: wallet.l2PublicKey ? ethers.hexlify(wallet.l2PublicKey) : null,
    noteReceivePrivateKey: wallet.noteReceivePrivateKey ? normalizePrivateKey(wallet.noteReceivePrivateKey) : null,
    noteReceiveDerivationVersion: Number(wallet.noteReceiveDerivationVersion),
    noteReceiveTypedDataMethod: wallet.noteReceiveTypedDataMethod,
    noteReceivePubKeyX: normalizeBytes32Hex(wallet.noteReceivePubKeyX),
    noteReceivePubKeyYParity: Number(wallet.noteReceivePubKeyYParity),
    noteReceiveLastScannedBlock: Number(wallet.noteReceiveLastScannedBlock),
    notes: {
      unused: Object.fromEntries(unusedNotes.map((note) => [note.commitment, note])),
      spent: Object.fromEntries(spentNotes.map((note) => [note.nullifier, note])),
      unusedOrder: unusedNotes.map((note) => note.commitment),
      unusedBalance: unusedNotes.every((note) => note.value !== null)
        ? unusedNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n).toString()
        : null,
    },
  };
}

function assertWalletHasCurrentFormat(wallet, walletName) {
  const requiredKeys = [
    "walletFormatVersion",
    "canonicalAssetDecimals",
    "l2Nonce",
    "noteReceiveDerivationVersion",
    "noteReceiveTypedDataMethod",
    "noteReceivePubKeyX",
    "noteReceivePubKeyYParity",
    "noteReceiveLastScannedBlock",
  ];
  const missingKeys = requiredKeys.filter((key) => wallet[key] === undefined || wallet[key] === null);
  expect(
    missingKeys.length === 0,
    `Wallet ${walletName} was not created with the current CLI wallet format. Missing key(s): ${missingKeys.join(", ")}.`,
  );
  expect(
    wallet.notes && typeof wallet.notes.unused === "object" && typeof wallet.notes.spent === "object",
    `Wallet ${walletName} was not created with the current CLI notes format.`,
  );
  expect(
    Number(wallet.walletFormatVersion) === WALLET_WORKSPACE_FORMAT_VERSION,
    [
      `Wallet ${walletName} uses unsupported wallet workspace format ${wallet.walletFormatVersion ?? "missing"}.`,
      "Rebuild the wallet metadata with wallet recover-workspace.",
    ].join(" "),
  );
}

function normalizeTrackedNote(note) {
  const nullifierObservedAtTxHash = note.nullifierObservedAtTxHash ? normalizeBytes32Hex(note.nullifierObservedAtTxHash) : null;
  const nullifierObservedAtBlockNumber = note.nullifierObservedAtBlockNumber !== undefined && note.nullifierObservedAtBlockNumber !== null
    ? Number(note.nullifierObservedAtBlockNumber)
    : null;
  const nullifierObservedAtLogIndex = note.nullifierObservedAtLogIndex !== undefined && note.nullifierObservedAtLogIndex !== null
    ? Number(note.nullifierObservedAtLogIndex)
    : null;
  const explicitSpentAtTxHash = note.spentAtTxHash ? normalizeBytes32Hex(note.spentAtTxHash) : null;
  const spentAtTxHash = note.status === "spent"
    ? nullifierObservedAtTxHash ?? explicitSpentAtTxHash
    : explicitSpentAtTxHash;
  const spentTxReplacedByNullifierObservation =
    note.status === "spent"
    && nullifierObservedAtTxHash
    && explicitSpentAtTxHash
    && ethers.toBigInt(nullifierObservedAtTxHash) !== ethers.toBigInt(explicitSpentAtTxHash);
  const spentAtBlockNumber = note.status === "spent" && nullifierObservedAtBlockNumber !== null
    ? nullifierObservedAtBlockNumber
    : note.spentAtBlockNumber !== undefined && note.spentAtBlockNumber !== null
      ? Number(note.spentAtBlockNumber)
      : null;
  const spentAtLogIndex = note.status === "spent" && nullifierObservedAtLogIndex !== null
    ? nullifierObservedAtLogIndex
    : note.spentAtLogIndex !== undefined && note.spentAtLogIndex !== null
      ? Number(note.spentAtLogIndex)
      : null;
  return {
    owner: note.owner ? getAddress(note.owner) : null,
    value: note.value !== undefined && note.value !== null ? ethers.toBigInt(note.value).toString() : null,
    salt: note.salt ? normalizeBytes32Hex(note.salt) : null,
    commitment: normalizeBytes32Hex(note.commitment),
    nullifier: normalizeBytes32Hex(note.nullifier),
    encryptedNoteValue: note.encryptedNoteValue ? normalizeEncryptedNoteValueWords(note.encryptedNoteValue) : null,
    status: note.status,
    sourceFunction: note.sourceFunction ?? null,
    sourceTxHash: note.sourceTxHash ?? null,
    createdAtTxHash: note.createdAtTxHash ?? (note.status === "unused" ? note.sourceTxHash ?? null : null),
    createdAtBlockNumber: note.createdAtBlockNumber !== undefined && note.createdAtBlockNumber !== null
      ? Number(note.createdAtBlockNumber)
      : null,
    createdAtLogIndex: note.createdAtLogIndex !== undefined && note.createdAtLogIndex !== null
      ? Number(note.createdAtLogIndex)
      : null,
    createdByFunction: note.createdByFunction ?? (note.status === "unused" ? note.sourceFunction ?? null : null),
    createdOutputIndex: note.createdOutputIndex !== undefined && note.createdOutputIndex !== null
      ? Number(note.createdOutputIndex)
      : null,
    spentAtTxHash,
    spentAtBlockNumber,
    spentAtLogIndex,
    spentByFunction: spentTxReplacedByNullifierObservation ? null : note.spentByFunction ?? null,
    spentInputIndex: note.spentInputIndex !== undefined && note.spentInputIndex !== null
      ? Number(note.spentInputIndex)
      : null,
    counterpartyL2Address: note.counterpartyL2Address ? getAddress(note.counterpartyL2Address) : null,
    counterpartyDirection: note.counterpartyDirection ?? null,
    counterpartyConfidence: note.counterpartyConfidence ?? null,
    bridgeCommitmentKey: note.bridgeCommitmentKey ? normalizeBytes32Hex(note.bridgeCommitmentKey) : null,
    bridgeNullifierKey: note.bridgeNullifierKey ? normalizeBytes32Hex(note.bridgeNullifierKey) : null,
    commitmentObservedAtTxHash: note.commitmentObservedAtTxHash ? normalizeBytes32Hex(note.commitmentObservedAtTxHash) : null,
    commitmentObservedAtBlockNumber: note.commitmentObservedAtBlockNumber !== undefined && note.commitmentObservedAtBlockNumber !== null
      ? Number(note.commitmentObservedAtBlockNumber)
      : null,
    commitmentObservedAtLogIndex: note.commitmentObservedAtLogIndex !== undefined && note.commitmentObservedAtLogIndex !== null
      ? Number(note.commitmentObservedAtLogIndex)
      : null,
    nullifierObservedAtTxHash,
    nullifierObservedAtBlockNumber,
    nullifierObservedAtLogIndex,
  };
}

async function buildWalletNoteBridgeStatus({
  note,
  currentSnapshot,
  controllerAddress,
  canonicalAssetDecimals,
}) {
  const commitmentExists = await readBooleanStorageValueFromSnapshot({
    snapshot: currentSnapshot,
    storageAddress: controllerAddress,
    storageKey: note.bridgeCommitmentKey,
  });
  const nullifierUsed = await readBooleanStorageValueFromSnapshot({
    snapshot: currentSnapshot,
    storageAddress: controllerAddress,
    storageKey: note.bridgeNullifierKey,
  });
  const expectedNullifierUsed = note.status === "spent";
  return {
    owner: note.owner,
    valueBaseUnits: note.value,
    valueTokens: note.value === null ? null : ethers.formatUnits(ethers.toBigInt(note.value), canonicalAssetDecimals),
    commitment: note.commitment,
    nullifier: note.nullifier,
    encryptedNoteValue: note.encryptedNoteValue,
    walletStatus: note.status,
    bridgeCommitmentExists: commitmentExists,
    bridgeNullifierUsed: nullifierUsed,
    walletStatusMatchesBridge: commitmentExists && nullifierUsed === expectedNullifierUsed,
    sourceFunction: note.sourceFunction ?? null,
    sourceTxHash: note.sourceTxHash ?? null,
    createdAtTxHash: note.createdAtTxHash ?? null,
    createdAtBlockNumber: note.createdAtBlockNumber ?? null,
    createdAtLogIndex: note.createdAtLogIndex ?? null,
    createdByFunction: note.createdByFunction ?? null,
    createdOutputIndex: note.createdOutputIndex ?? null,
    spentAtTxHash: note.spentAtTxHash ?? null,
    spentAtBlockNumber: note.spentAtBlockNumber ?? null,
    spentAtLogIndex: note.spentAtLogIndex ?? null,
    spentByFunction: note.spentByFunction ?? null,
    spentInputIndex: note.spentInputIndex ?? null,
    counterpartyL2Address: note.counterpartyL2Address ?? null,
    counterpartyDirection: note.counterpartyDirection ?? null,
    counterpartyConfidence: note.counterpartyConfidence ?? null,
  };
}

async function readBooleanStorageValueFromSnapshot({ snapshot, storageAddress, storageKey }) {
  if (!storageKey) {
    return false;
  }
  return (
    hexToBigInt(
      addHexPrefix(
        String(await readStorageValueFromStateSnapshot(snapshot, storageAddress, storageKey) ?? "").replace(/^0x/i, ""),
      ),
    ) !== 0n
  );
}

function compareNotesByValueDesc(left, right) {
  const leftValue = left.value === null || left.value === undefined ? 0n : ethers.toBigInt(left.value);
  const rightValue = right.value === null || right.value === undefined ? 0n : ethers.toBigInt(right.value);
  if (leftValue === rightValue) {
    return left.commitment.localeCompare(right.commitment);
  }
  return leftValue > rightValue ? -1 : 1;
}

function buildTrackedNote(note, sourceFunction, sourceTxHash, bridgeKeys = {}) {
  const normalizedNote = normalizePlaintextNote(note);
  const createdTxHash = bridgeKeys.createdAtTxHash ?? sourceTxHash ?? null;
  const createdFunction = bridgeKeys.createdByFunction ?? sourceFunction ?? null;
  return {
    ...normalizedNote,
    commitment: normalizeBytes32Hex(computeNoteCommitment(normalizedNote)),
    nullifier: normalizeBytes32Hex(computeNullifier(normalizedNote)),
    encryptedNoteValue: note.encryptedNoteValue ? normalizeEncryptedNoteValueWords(note.encryptedNoteValue) : null,
    status: "unused",
    sourceFunction,
    sourceTxHash,
    createdAtTxHash: createdTxHash,
    createdAtBlockNumber: bridgeKeys.createdAtBlockNumber ?? null,
    createdAtLogIndex: bridgeKeys.createdAtLogIndex ?? null,
    createdByFunction: createdFunction,
    createdOutputIndex: bridgeKeys.createdOutputIndex ?? null,
    spentAtTxHash: bridgeKeys.spentAtTxHash ?? null,
    spentAtBlockNumber: bridgeKeys.spentAtBlockNumber ?? null,
    spentAtLogIndex: bridgeKeys.spentAtLogIndex ?? null,
    spentByFunction: bridgeKeys.spentByFunction ?? null,
    spentInputIndex: bridgeKeys.spentInputIndex ?? null,
    counterpartyL2Address: bridgeKeys.counterpartyL2Address ? getAddress(bridgeKeys.counterpartyL2Address) : null,
    counterpartyDirection: bridgeKeys.counterpartyDirection ?? null,
    counterpartyConfidence: bridgeKeys.counterpartyConfidence ?? null,
    bridgeCommitmentKey: bridgeKeys.bridgeCommitmentKey
      ? normalizeBytes32Hex(bridgeKeys.bridgeCommitmentKey)
      : null,
    bridgeNullifierKey: bridgeKeys.bridgeNullifierKey
      ? normalizeBytes32Hex(bridgeKeys.bridgeNullifierKey)
      : null,
    commitmentObservedAtTxHash: bridgeKeys.commitmentObservedAtTxHash ?? null,
    commitmentObservedAtBlockNumber: bridgeKeys.commitmentObservedAtBlockNumber ?? null,
    commitmentObservedAtLogIndex: bridgeKeys.commitmentObservedAtLogIndex ?? null,
    nullifierObservedAtTxHash: bridgeKeys.nullifierObservedAtTxHash ?? null,
    nullifierObservedAtBlockNumber: bridgeKeys.nullifierObservedAtBlockNumber ?? null,
    nullifierObservedAtLogIndex: bridgeKeys.nullifierObservedAtLogIndex ?? null,
  };
}

function buildLifecycleTrackedOutputs({
  outputNotes,
  sourceFunction,
  sourceTxHash,
  bridgeCommitmentKeys,
  sourceBlockNumber = null,
  counterpartyL2Addresses = [],
  counterpartyDirection = null,
}) {
  return (outputNotes ?? []).map((note, index) => buildTrackedNote(note, sourceFunction, sourceTxHash, {
    bridgeCommitmentKey: bridgeCommitmentKeys?.[index] ?? null,
    createdAtTxHash: sourceTxHash,
    createdAtBlockNumber: sourceBlockNumber,
    createdByFunction: sourceFunction,
    createdOutputIndex: index,
    counterpartyL2Address: counterpartyL2Addresses?.[index] ?? null,
    counterpartyDirection,
    counterpartyConfidence: counterpartyL2Addresses?.[index] ? "direct-local-metadata" : null,
  }));
}

async function recoverWalletReceivedNotes({
  walletContext,
  context,
  provider,
  signer,
  noteReceiveKeyMaterial = null,
  toBlock = null,
  progressAction = null,
  fromGenesis = false,
}) {
  const resolvedNoteReceiveKeyMaterial = noteReceiveKeyMaterial ?? {
    privateKey: walletContext.wallet.noteReceivePrivateKey,
    noteReceivePubKey: walletNoteReceivePubKey(walletContext),
  };
  requireWalletViewingCapability(walletContext);
  const recoveredDeliveryState = await recoverDeliveredNotesFromEventLogs({
    walletContext,
    context,
    provider,
    noteReceivePrivateKey: resolvedNoteReceiveKeyMaterial.privateKey,
    toBlock,
    progressAction,
    fromGenesis,
  });
  return {
    noteReceiveKeyMaterial: resolvedNoteReceiveKeyMaterial,
    recoveredDeliveryState,
  };
}

async function recoverDeliveredNotesFromEventLogs({
  walletContext,
  context,
  provider,
  noteReceivePrivateKey,
  toBlock = null,
  storageObservationLogs = null,
  progressAction = null,
  fromGenesis = false,
}) {
  const latestBlock = toBlock === null ? await fetchFreshBlockNumber(provider) : Number(toBlock);
  expect(
    Number.isInteger(latestBlock) && latestBlock >= Number(context.workspace.genesisBlockNumber) - 1,
    "Wallet note recovery target block is invalid.",
  );
  const scanStartBlock = fromGenesis
    ? Number(context.workspace.genesisBlockNumber)
    : walletNoteReceiveCursorDelta({
      walletContext,
      context,
      targetNextBlock: latestBlock + 1,
    }).localNextBlock;
  const scanRange = {
    fromBlock: scanStartBlock,
    toBlock: latestBlock,
  };

  if (scanStartBlock > latestBlock) {
    const reconciledState = await reconcileWalletNotesWithBridgeState({
      walletContext,
      currentSnapshot: context.currentSnapshot,
      controllerAddress: context.workspace.controller,
    });
    const linkedEvidence = applyEvidenceLinkageToWalletFromStorageObservations({
      walletContext,
      context,
      storageObservationLogs: storageObservationLogs ?? [],
    });
    walletContext.wallet.noteReceiveLastScannedBlock = Math.max(
      Number(walletContext.wallet.noteReceiveLastScannedBlock),
      latestBlock + 1,
    );
    persistWallet(walletContext);
    return {
      importedNotes: [],
      reconciledState,
      scannedLogs: 0,
      linkedEvidence,
      scanRange,
    };
  }

  const storageLayoutManifest = readJson(
    walletContext.wallet.storageLayoutPath ?? context.workspace.storageLayoutPath,
  );
  const commitmentExistsSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "commitmentExists"));
  const nullifierUsedSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "nullifierUsed"));
  const importedNotes = [];
  let reconciledState = null;
  let scannedLogs = 0;

  const collectedStorageObservationLogs = [];
  await fetchLogsChunked(provider, {
    address: context.workspace.channelManager,
    topics: [[NOTE_VALUE_ENCRYPTED_TOPIC, CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC]],
    fromBlock: scanStartBlock,
    toBlock: latestBlock,
    collectLogs: false,
    onProgress: progressAction
      ? createRpcLogScanProgress({ action: progressAction, label: "note-delivery events" })
      : null,
    onChunk: async ({ logs, chunkToBlock }) => {
      const deliveryLogs = [];
      const storageLogs = [];
      for (const log of logs) {
        const topic0 = log.topics?.[0] ? normalizeBytes32Hex(log.topics[0]) : null;
        if (topic0 === normalizeBytes32Hex(NOTE_VALUE_ENCRYPTED_TOPIC)) {
          deliveryLogs.push(log);
        } else if (topic0 === normalizeBytes32Hex(CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC)) {
          storageLogs.push(log);
        }
      }
      scannedLogs += deliveryLogs.length;
      collectedStorageObservationLogs.push(...storageLogs);
      const importedCandidates = await recoverDeliveredNoteCandidatesFromLogs({
        logs: deliveryLogs,
        walletContext,
        context,
        noteReceivePrivateKey,
        commitmentExistsSlot,
        nullifierUsedSlot,
      });
      if (importedCandidates.length > 0) {
        importedNotes.push(...mergeTrackedNotesIntoWallet(walletContext, importedCandidates));
        reconciledState = await reconcileWalletNotesWithBridgeState({
          walletContext,
          currentSnapshot: context.currentSnapshot,
          controllerAddress: context.workspace.controller,
        });
      }
      walletContext.wallet.noteReceiveLastScannedBlock = Number(chunkToBlock) + 1;
      persistWallet(walletContext);
    },
  });

  reconciledState = await reconcileWalletNotesWithBridgeState({
    walletContext,
    currentSnapshot: context.currentSnapshot,
    controllerAddress: context.workspace.controller,
  });
  const linkedEvidence = applyEvidenceLinkageToWalletFromStorageObservations({
    walletContext,
    context,
    storageObservationLogs: storageObservationLogs ?? collectedStorageObservationLogs,
  });
  walletContext.wallet.noteReceiveLastScannedBlock = latestBlock + 1;
  persistWallet(walletContext);
  return {
    importedNotes,
    reconciledState,
    scannedLogs,
    linkedEvidence,
    scanRange,
  };
}

async function recoverDeliveredNotesFromCollectedLogs({
  walletContext,
  context,
  noteReceivePrivateKey,
  logs,
  storageObservationLogs = [],
  scanStartBlock,
  latestBlock,
}) {
  const scanRange = {
    fromBlock: scanStartBlock,
    toBlock: latestBlock,
  };

  if (scanStartBlock > latestBlock) {
    const reconciledState = await reconcileWalletNotesWithBridgeState({
      walletContext,
      currentSnapshot: context.currentSnapshot,
      controllerAddress: context.workspace.controller,
    });
    const linkedEvidence = applyEvidenceLinkageToWalletFromStorageObservations({
      walletContext,
      context,
      storageObservationLogs,
    });
    walletContext.wallet.noteReceiveLastScannedBlock = Math.max(
      Number(walletContext.wallet.noteReceiveLastScannedBlock),
      latestBlock + 1,
    );
    persistWallet(walletContext);
    return {
      importedNotes: [],
      reconciledState,
      scannedLogs: 0,
      linkedEvidence,
      scanRange,
    };
  }

  const storageLayoutManifest = readJson(
    walletContext.wallet.storageLayoutPath ?? context.workspace.storageLayoutPath,
  );
  const commitmentExistsSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "commitmentExists"));
  const nullifierUsedSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "nullifierUsed"));
  const deliveryLogs = logs.filter((log) => {
    const blockNumber = Number(log.blockNumber);
    return blockNumber >= scanStartBlock && blockNumber <= latestBlock;
  });
  const importedCandidates = await recoverDeliveredNoteCandidatesFromLogs({
    logs: deliveryLogs,
    walletContext,
    context,
    noteReceivePrivateKey,
    commitmentExistsSlot,
    nullifierUsedSlot,
  });
  const importedNotes = mergeTrackedNotesIntoWallet(walletContext, importedCandidates);
  const reconciledState = await reconcileWalletNotesWithBridgeState({
    walletContext,
    currentSnapshot: context.currentSnapshot,
    controllerAddress: context.workspace.controller,
  });
  const linkedEvidence = applyEvidenceLinkageToWalletFromStorageObservations({
    walletContext,
    context,
    storageObservationLogs,
  });
  walletContext.wallet.noteReceiveLastScannedBlock = latestBlock + 1;
  persistWallet(walletContext);
  return {
    importedNotes,
    reconciledState,
    scannedLogs: deliveryLogs.length,
    linkedEvidence,
    scanRange,
  };
}

async function recoverDeliveredNoteCandidatesFromLogs({
  logs,
  walletContext,
  context,
  noteReceivePrivateKey,
  commitmentExistsSlot,
  nullifierUsedSlot,
}) {
  const importedCandidates = [];
  for (const log of logs) {
    const encryptedNoteValue = extractEncryptedNoteValueFromBridgeLog(log);
    if (!encryptedNoteValue) {
      continue;
    }
    const { scheme } = unpackEncryptedNoteValue(encryptedNoteValue);
    let recoveredValue;
    let sourceFunction;
    try {
      if (scheme === ENCRYPTED_NOTE_SCHEME_TRANSFER) {
        recoveredValue = decryptEncryptedNoteValue({
          encryptedValue: encryptedNoteValue,
          noteReceivePrivateKey,
          chainId: context.workspace.chainId,
          channelId: context.workspace.channelId,
          owner: walletContext.wallet.l2Address,
        });
        sourceFunction = "transferNotes";
      } else if (scheme === ENCRYPTED_NOTE_SCHEME_SELF_MINT) {
        recoveredValue = decryptMintEncryptedNoteValue({
          encryptedValue: encryptedNoteValue,
          noteReceivePrivateKey,
          chainId: context.workspace.chainId,
          channelId: context.workspace.channelId,
          owner: walletContext.wallet.l2Address,
        });
        sourceFunction = "mintNotes";
      } else {
        continue;
      }
    } catch {
      continue;
    }

    const plaintextNote = normalizePlaintextNote({
      owner: walletContext.wallet.l2Address,
      value: recoveredValue,
      salt: computeEncryptedNoteSalt(encryptedNoteValue),
      encryptedNoteValue,
    });
    const commitment = normalizeBytes32Hex(computeNoteCommitment(plaintextNote));
    const nullifier = normalizeBytes32Hex(computeNullifier(plaintextNote));
    const trackedNote = buildTrackedNote({
      ...plaintextNote,
      encryptedNoteValue,
    }, sourceFunction, log.transactionHash, {
      bridgeCommitmentKey: derivePrivateStateControllerMappingStorageKey(commitment, commitmentExistsSlot),
      bridgeNullifierKey: derivePrivateStateControllerMappingStorageKey(nullifier, nullifierUsedSlot),
      createdAtTxHash: log.transactionHash,
      createdAtBlockNumber: log.blockNumber !== undefined ? Number(log.blockNumber) : null,
      createdAtLogIndex: log.index ?? log.logIndex ?? null,
      createdByFunction: sourceFunction,
      counterpartyDirection: scheme === ENCRYPTED_NOTE_SCHEME_SELF_MINT ? "self-mint" : "received",
      counterpartyConfidence: scheme === ENCRYPTED_NOTE_SCHEME_SELF_MINT ? "direct-local-metadata" : "unavailable",
    });
    const commitmentExists = await readBooleanStorageValueFromSnapshot({
      snapshot: context.currentSnapshot,
      storageAddress: context.workspace.controller,
      storageKey: trackedNote.bridgeCommitmentKey,
    });
    if (!commitmentExists) {
      continue;
    }
    importedCandidates.push(trackedNote);
  }
  return importedCandidates;
}

function channelWorkspaceRecoveryTargetNextBlock(context) {
  const targetNextBlock = Number(context.workspace.recoveryLastScannedBlock);
  const genesisBlockNumber = Number(context.workspace.genesisBlockNumber);
  expect(
    Number.isInteger(targetNextBlock) && targetNextBlock >= genesisBlockNumber,
    "Channel workspace recovery frontier is missing or unusable.",
  );
  return targetNextBlock;
}

function walletNoteReceiveTargetBlock(context) {
  return channelWorkspaceRecoveryTargetNextBlock(context) - 1;
}

function computeRecoveryCursorDelta({
  localNextBlock,
  targetNextBlock,
  genesisBlockNumber,
  label,
}) {
  const normalizedLocalNextBlock = Number(localNextBlock);
  const normalizedTargetNextBlock = Number(targetNextBlock);
  const normalizedGenesisBlockNumber = Number(genesisBlockNumber);
  if (
    !Number.isInteger(normalizedLocalNextBlock)
    || !Number.isInteger(normalizedTargetNextBlock)
    || !Number.isInteger(normalizedGenesisBlockNumber)
    || normalizedLocalNextBlock < normalizedGenesisBlockNumber
    || normalizedTargetNextBlock < normalizedGenesisBlockNumber
  ) {
    throw new Error([
      `${label} recovery cursor is missing or unusable.`,
      `Expected localNextBlock and targetNextBlock to be integers greater than or equal to ${normalizedGenesisBlockNumber}.`,
    ].join(" "));
  }
  const fromBlock = normalizedLocalNextBlock;
  const toBlock = normalizedTargetNextBlock - 1;
  const blockDelta = Math.max(0, normalizedTargetNextBlock - normalizedLocalNextBlock);
  return {
    fresh: normalizedLocalNextBlock >= normalizedTargetNextBlock,
    localNextBlock: normalizedLocalNextBlock,
    targetNextBlock: normalizedTargetNextBlock,
    fromBlock,
    toBlock,
    blockDelta,
  };
}

function walletNoteReceiveCursorDelta({ walletContext, context, targetNextBlock = channelWorkspaceRecoveryTargetNextBlock(context) }) {
  const nextBlock = Number(walletContext.wallet.noteReceiveLastScannedBlock);
  const genesisBlockNumber = Number(context.workspace.genesisBlockNumber);
  try {
    return computeRecoveryCursorDelta({
      localNextBlock: nextBlock,
      targetNextBlock,
      genesisBlockNumber,
      label: `Wallet note workspace ${walletContext.walletName}`,
    });
  } catch (error) {
    throw new Error([
      `Wallet note recovery index is missing or unusable for wallet ${walletContext.walletName}.`,
      `Expected noteReceiveLastScannedBlock to be an integer greater than or equal to ${genesisBlockNumber}.`,
      "Run wallet recover-workspace --from-genesis to restart received-note scanning from channel genesis.",
      `Details: ${error.message}`,
    ].join(" "));
  }
}

function assertWalletNoteReceiveStateFresh({ walletContext, context }) {
  const cursorDelta = walletNoteReceiveCursorDelta({ walletContext, context });
  if (!cursorDelta.fresh) {
    throw new Error([
      `Wallet note workspace is stale for wallet ${walletContext.walletName}.`,
      `noteReceiveLastScannedBlock is ${cursorDelta.localNextBlock}, but channel workspace recovery frontier requires ${cursorDelta.targetNextBlock}.`,
      "Run wallet recover-workspace before using commands that read or spend wallet notes.",
    ].join(" "));
  }
  return {
    targetBlock: cursorDelta.toBlock,
    targetNextBlock: cursorDelta.targetNextBlock,
    nextBlock: cursorDelta.localNextBlock,
    blockDelta: cursorDelta.blockDelta,
  };
}

async function ensureWalletNoteReceiveStateCurrent({
  walletContext,
  context,
  provider,
  signer = null,
  progressAction = null,
  preConsumedBlockDelta = 0,
}) {
  let cursorDelta;
  try {
    cursorDelta = walletNoteReceiveCursorDelta({ walletContext, context });
  } catch (indexError) {
    throw new Error([
      `Wallet note recovery index is missing or unusable for wallet ${walletContext.walletName}.`,
      "Automatic wallet recovery uses only the saved note recovery index and will not replay from genesis.",
      `Run wallet recover-workspace --channel-name ${context.workspace.channelName} --network ${context.workspace.network} --account <ACCOUNT> --from-genesis if received-note scanning must restart from channel genesis.`,
      `Details: ${indexError.message}`,
    ].join(" "));
  }

  if (cursorDelta.fresh) {
    return {
      targetBlock: cursorDelta.toBlock,
      targetNextBlock: cursorDelta.targetNextBlock,
      nextBlock: cursorDelta.localNextBlock,
      recoveredWalletWorkspace: false,
      recoveredDeliveryState: null,
      autoRecoveryBlockDelta: 0,
    };
  }
  const remainingBlockBudget = AUTO_RECOVERY_BLOCK_BUDGET - Math.max(0, Number(preConsumedBlockDelta));
  const autoRecoveryBlockDelta = assertAutoRecoveryBlockBudget({
    label: `wallet note workspace ${walletContext.walletName}`,
    fromBlock: cursorDelta.fromBlock,
    toBlock: cursorDelta.toBlock,
    recoveryCommand: `wallet recover-workspace --channel-name ${context.workspace.channelName} --network ${context.workspace.network} --account <ACCOUNT>`,
    blockBudget: remainingBlockBudget,
  });

  const resolvedSigner = signer ?? restoreWalletParticipant(walletContext, provider).signer;
  let recoveredDeliveryState;
  try {
    ({ recoveredDeliveryState } = await recoverWalletReceivedNotes({
      walletContext,
      context,
      provider,
      signer: resolvedSigner,
      toBlock: cursorDelta.toBlock,
      progressAction,
      fromGenesis: false,
    }));
  } catch (recoveryError) {
    throw new Error([
      `Wallet workspace is not current for wallet ${walletContext.walletName}.`,
      "Automatic wallet recovery uses only the saved note recovery index and will not replay from genesis.",
      `Run wallet recover-workspace --channel-name ${context.workspace.channelName} --network ${context.workspace.network} --account <ACCOUNT> --from-genesis if received-note scanning must restart from channel genesis.`,
      `Details: ${recoveryError.message}`,
    ].join(" "));
  }
  return {
    ...assertWalletNoteReceiveStateFresh({ walletContext, context }),
    recoveredWalletWorkspace: true,
    recoveredDeliveryState,
    autoRecoveryBlockDelta,
  };
}

function extractEncryptedNoteValueFromBridgeLog(log) {
  if (!Array.isArray(log?.topics) || log.topics.length !== 1) {
    return null;
  }

  const normalizedTopic0 = normalizeBytes32Hex(log.topics[0]);
  if (normalizedTopic0 === normalizeBytes32Hex(NOTE_VALUE_ENCRYPTED_TOPIC)) {
    try {
      const parsedLog = noteValueEncryptedEventInterface.parseLog(log);
      return normalizeEncryptedNoteValueWords(parsedLog.args.encryptedNoteValue);
    } catch {
      return null;
    }
  }

  if (normalizedTopic0 !== ZERO_TOPIC) {
    return null;
  }

  const dataBytes = ethers.getBytes(log.data ?? "0x");
  if (dataBytes.length !== 96) {
    return null;
  }

  try {
    const [encryptedNoteValue] = abiCoder.decode(["bytes32[3]"], log.data);
    return normalizeEncryptedNoteValueWords(encryptedNoteValue);
  } catch {
    return null;
  }
}

function buildImportedTrackedNote(note) {
  const trackedNote = buildTrackedNote(note, note.sourceFunction ?? null, note.sourceTxHash ?? null, {
    bridgeCommitmentKey: note.bridgeCommitmentKey ?? null,
    bridgeNullifierKey: note.bridgeNullifierKey ?? null,
    createdAtTxHash: note.createdAtTxHash ?? note.sourceTxHash ?? null,
    createdAtBlockNumber: note.createdAtBlockNumber ?? null,
    createdAtLogIndex: note.createdAtLogIndex ?? null,
    createdByFunction: note.createdByFunction ?? note.sourceFunction ?? null,
    createdOutputIndex: note.createdOutputIndex ?? null,
    spentAtTxHash: note.spentAtTxHash ?? null,
    spentAtBlockNumber: note.spentAtBlockNumber ?? null,
    spentAtLogIndex: note.spentAtLogIndex ?? null,
    spentByFunction: note.spentByFunction ?? null,
    spentInputIndex: note.spentInputIndex ?? null,
    counterpartyL2Address: note.counterpartyL2Address ?? null,
    counterpartyDirection: note.counterpartyDirection ?? null,
    counterpartyConfidence: note.counterpartyConfidence ?? null,
    commitmentObservedAtTxHash: note.commitmentObservedAtTxHash ?? null,
    commitmentObservedAtBlockNumber: note.commitmentObservedAtBlockNumber ?? null,
    commitmentObservedAtLogIndex: note.commitmentObservedAtLogIndex ?? null,
    nullifierObservedAtTxHash: note.nullifierObservedAtTxHash ?? null,
    nullifierObservedAtBlockNumber: note.nullifierObservedAtBlockNumber ?? null,
    nullifierObservedAtLogIndex: note.nullifierObservedAtLogIndex ?? null,
  });
  if (note.commitment !== undefined) {
    expect(
      ethers.toBigInt(normalizeBytes32Hex(note.commitment)) === ethers.toBigInt(trackedNote.commitment),
      `Imported note commitment mismatch for ${trackedNote.commitment}.`,
    );
  }
  if (note.nullifier !== undefined) {
    expect(
      ethers.toBigInt(normalizeBytes32Hex(note.nullifier)) === ethers.toBigInt(trackedNote.nullifier),
      `Imported note nullifier mismatch for ${trackedNote.commitment}.`,
    );
  }
  return trackedNote;
}

function normalizePlaintextNote(note) {
  return {
    owner: getAddress(note.owner),
    value: ethers.toBigInt(note.value).toString(),
    salt: normalizeBytes32Hex(note.salt),
  };
}

function derivePrivateStateControllerMappingStorageKey(keyHex, slot) {
  const encoded = abiCoder.encode(["bytes32", "uint256"], [normalizeBytes32Hex(keyHex), ethers.toBigInt(slot)]);
  return normalizeBytes32Hex(bytesToHex(poseidon(hexToBytes(addHexPrefix(String(encoded ?? "").replace(/^0x/i, ""))))));
}

function buildMintNotesTemplatePayload({ wallet, baseUnitAmounts }) {
  const method = selectMintNotesMethod(baseUnitAmounts.length);
  const { mintOutputs, lifecycleOutputs } = buildMintEncryptedOutputs({
    wallet,
    values: baseUnitAmounts,
  });
  return {
    abiFile: "PrivateStateController.callable-abi.json",
    method,
    args: [mintOutputs],
    lifecycleOutputs,
  };
}

function buildRedeemNotesTemplatePayload({ wallet, inputNotes }) {
  return {
    abiFile: "PrivateStateController.callable-abi.json",
    method: selectRedeemNotesMethod(inputNotes.length),
    args: [inputNotes, wallet.wallet.l2Address],
  };
}

function selectMintNotesMethod(noteCount) {
  expect(noteCount >= 1, "wallet mint-notes requires at least one output amount.");
  expect(
    noteCount <= 2,
    "wallet mint-notes supports only one or two output amounts with the currently registered DApp.",
  );
  return `mintNotes${noteCount}`;
}

function selectRedeemNotesMethod(noteCount) {
  expect(noteCount === 1, "wallet redeem-notes supports exactly one input note with the currently registered DApp.");
  return `redeemNotes${noteCount}`;
}

function walletNoteReceivePubKey(walletContext) {
  const x = walletContext.wallet.noteReceivePubKeyX;
  const yParity = walletContext.wallet.noteReceivePubKeyYParity;
  expect(
    typeof x === "string" && x.length > 0,
    `Wallet ${walletContext.walletName} is missing a stored note-receive public key.`,
  );
  expect(
    Number(yParity) === 0 || Number(yParity) === 1,
    `Wallet ${walletContext.walletName} has an invalid stored note-receive public key parity.`,
  );
  return {
    x: normalizeBytes32Hex(x),
    yParity: Number(yParity),
  };
}

function buildMintEncryptedOutputs({ wallet, values }) {
  const mintOutputs = [];
  const lifecycleOutputs = [];
  const ownerNoteReceivePubKey = walletNoteReceivePubKey(wallet);
  for (const value of values) {
    const encryptedNoteValue = encryptMintNoteValueForOwner({
      value,
      ownerNoteReceivePubKey,
      chainId: wallet.wallet.chainId,
      channelId: wallet.wallet.channelId,
      owner: wallet.wallet.l2Address,
    });
    mintOutputs.push({
      value: ethers.toBigInt(value).toString(),
      encryptedNoteValue,
    });
    lifecycleOutputs.push({
      owner: wallet.wallet.l2Address,
      value: ethers.toBigInt(value).toString(),
      salt: computeEncryptedNoteSalt(encryptedNoteValue),
      encryptedNoteValue,
    });
  }
  return {
    mintOutputs,
    lifecycleOutputs,
  };
}

function assertRegisteredNoteReceivePubKey(noteReceivePubKey, recipient) {
  expect(noteReceivePubKey, `Missing note-receive public key for ${recipient}.`);
  expect(
    noteReceivePubKey.x
      && ethers.toBigInt(normalizeBytes32Hex(noteReceivePubKey.x)) !== ethers.toBigInt(normalizeBytes32Hex("0x0")),
    `Recipient ${recipient} is missing a registered note-receive public key.`,
  );
  expect(
    Number(noteReceivePubKey.yParity) === 0 || Number(noteReceivePubKey.yParity) === 1,
    `Recipient ${recipient} has an invalid note-receive public key parity.`,
  );
}

async function buildTransferNotesTemplatePayload({
  context,
  signer,
  inputNotes,
  recipients,
  outputAmounts,
}) {
  const method = selectTransferNotesMethod(inputNotes.length, recipients.length);
  const transferOutputs = [];
  const lifecycleOutputs = [];
  const recipientAddresses = recipients.map(getAddress);
  const recipientPubKeys = await Promise.all(
    recipientAddresses.map((recipient) => context.channelManager.getNoteReceivePubKeyByL2Address(recipient)),
  );

  for (let index = 0; index < recipientAddresses.length; index += 1) {
    const recipient = recipientAddresses[index];
    const noteReceivePubKey = recipientPubKeys[index];
    assertRegisteredNoteReceivePubKey(noteReceivePubKey, recipient);
    const encryptedNoteValue = encryptNoteValueForRecipient({
      value: outputAmounts[index],
      recipientNoteReceivePubKey: noteReceivePubKey,
      chainId: context.workspace.chainId,
      channelId: context.workspace.channelId,
      owner: recipient,
    });
    const salt = computeEncryptedNoteSalt(encryptedNoteValue);
    transferOutputs.push({
      owner: recipient,
      value: ethers.toBigInt(outputAmounts[index]).toString(),
      encryptedNoteValue,
    });
    lifecycleOutputs.push({
      owner: recipient,
      value: ethers.toBigInt(outputAmounts[index]).toString(),
      salt,
      encryptedNoteValue,
    });
  }
  return {
    abiFile: "PrivateStateController.callable-abi.json",
    method,
    args: [transferOutputs, inputNotes],
    lifecycleInputs: inputNotes,
    lifecycleOutputs,
    recipientAddresses,
  };
}

function selectTransferNotesMethod(inputCount, outputCount) {
  if (inputCount === 1 && outputCount === 1) {
    return "transferNotes1To1";
  }
  if (inputCount === 1 && outputCount === 2) {
    return "transferNotes1To2";
  }
  if (inputCount === 2 && outputCount === 1) {
    return "transferNotes2To1";
  }
  throw new Error("wallet transfer-notes supports only 1->1, 1->2, and 2->1 note transfers.");
}

function loadWalletUnusedInputNotes(walletContext, noteIds) {
  return noteIds.map((noteId) => {
    const trackedNote = walletContext.wallet.notes.unused[noteId];
    expect(trackedNote, `Unknown unused note commitment: ${noteId}.`);
    expect(
      trackedNote.owner && trackedNote.value !== null && trackedNote.salt,
      `Note ${noteId} is encrypted-only. Import the wallet viewing key before spending it.`,
    );
    return normalizePlaintextNote(trackedNote);
  });
}

function parseAmountVector(value, { allowZeroEntries = false, requireAnyPositive = false } = {}) {
  let parsed;
  try {
    parsed = JSON.parse(String(value));
  } catch {
    throw new Error("Invalid --amounts. Expected a JSON array such as [1,2,3].");
  }
  expect(Array.isArray(parsed), "Invalid --amounts. Expected a JSON array.");
  expect(parsed.length > 0, "Invalid --amounts. The array must not be empty.");
  const normalizedAmounts = parsed.map((entry, index) => {
    const normalized = typeof entry === "string" || typeof entry === "number" ? String(entry) : null;
    expect(
      normalized !== null && normalized.length > 0,
      `Invalid --amounts[${index}]. Each amount must be a string or number.`,
    );
    expect(!normalized.startsWith("-"), `Invalid --amounts[${index}]. Each amount must be zero or greater.`);
    if (!allowZeroEntries) {
      expect(
        normalized !== "0" && normalized !== "0.0",
        `Invalid --amounts[${index}]. Each amount must be greater than zero.`,
      );
    }
    return normalized;
  });
  if (requireAnyPositive) {
    const hasNonZeroEntry = normalizedAmounts.some((normalized) => {
      const trimmed = normalized.trim();
      if (trimmed.length === 0) {
        return false;
      }
      return Number.parseFloat(trimmed) !== 0;
    });
    expect(
      hasNonZeroEntry,
      "Invalid --amounts. The array must contain at least one amount greater than zero.",
    );
  }
  return normalizedAmounts;
}

function parseNoteIdVector(value) {
  let parsed;
  try {
    parsed = JSON.parse(String(value));
  } catch {
    throw new Error("Invalid --note-ids. Expected a JSON array of note commitments.");
  }
  expect(Array.isArray(parsed), "Invalid --note-ids. Expected a JSON array.");
  expect(parsed.length > 0, "Invalid --note-ids. The array must not be empty.");

  const noteIds = parsed.map((entry, index) => {
    expect(
      typeof entry === "string" && entry.length > 0,
      `Invalid --note-ids[${index}]. Each note ID must be a non-empty string.`,
    );
    return normalizeBytes32Hex(entry);
  });
  expect(
    new Set(noteIds).size === noteIds.length,
    "Invalid --note-ids. Duplicate note commitments are not allowed.",
  );
  return noteIds;
}

function parseRecipientVector(value) {
  let parsed;
  try {
    parsed = JSON.parse(String(value));
  } catch {
    throw new Error("Invalid --recipients. Expected a JSON array of L2 addresses.");
  }
  expect(Array.isArray(parsed), "Invalid --recipients. Expected a JSON array.");
  expect(parsed.length > 0, "Invalid --recipients. The array must not be empty.");
  return parsed.map((entry, index) => {
    expect(
      typeof entry === "string" && entry.length > 0,
      `Invalid --recipients[${index}]. Each recipient must be a non-empty address string.`,
    );
    return getAddress(entry);
  });
}

function walletChannelWorkspaceIsReady(walletContext) {
  const workspaceDir = channelWorkspacePath(walletContext.wallet.network, walletContext.wallet.channelName);
  return fs.existsSync(channelWorkspaceConfigPath(workspaceDir))
    && fs.existsSync(path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.json"))
    && fs.existsSync(path.join(channelWorkspaceCurrentPath(workspaceDir), "block_info.json"))
    && fs.existsSync(path.join(channelWorkspaceCurrentPath(workspaceDir), "contract_codes.json"));
}

async function loadFreshWalletChannelContext({
  walletContext,
  provider,
  progressAction = null,
}) {
  const contextResult = await loadFreshChannelWorkspaceContextResult({
    channelName: walletContext.wallet.channelName,
    networkName: walletContext.wallet.network,
    provider,
    progressAction,
  });
  return {
    context: contextResult.context,
    network: resolveCliNetwork(contextResult.context.workspace.network),
    usingWorkspaceCache: !contextResult.recoveredWorkspace,
    recoveredWorkspace: contextResult.recoveredWorkspace,
    autoRecoveryBlockDelta: contextResult.autoRecoveryBlockDelta,
  };
}

async function loadFreshChannelWorkspaceContext({
  channelName,
  networkName,
  provider,
  progressAction = null,
}) {
  const { context } = await loadFreshChannelWorkspaceContextResult({
    channelName,
    networkName,
    provider,
    progressAction,
  });
  return context;
}

async function loadFreshChannelWorkspaceContextResult({
  channelName,
  networkName,
  provider,
  progressAction = null,
}) {
  let context;
  try {
    context = await loadWorkspaceContext(channelName, networkName, provider);
    await assertWorkspaceAlignedWithChain(context);
    return {
      context,
      recoveredWorkspace: false,
      autoRecoveryBlockDelta: 0,
    };
  } catch (error) {
    const recovery = await recoverChannelWorkspaceFromIndexOnly({
      channelName,
      networkName,
      provider,
      progressAction,
      cause: error,
    });
    return {
      context: recovery.context,
      recoveredWorkspace: true,
      autoRecoveryBlockDelta: recovery.autoRecoveryBlockDelta,
    };
  }
}

async function recoverChannelWorkspaceFromIndexOnly({
  channelName,
  networkName,
  provider,
  progressAction = null,
  cause = null,
}) {
  const network = resolveCliNetwork(networkName);
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const readiness = await requireChannelWorkspaceRecoveryIndexForAutoRefresh({
    channelName,
    networkName,
    provider,
    bridgeResources,
    cause,
  });
  if (readiness.alreadyCurrent) {
    return {
      context: await loadWorkspaceContext(channelName, networkName, provider),
      autoRecoveryBlockDelta: 0,
    };
  }
  try {
    await syncChannelWorkspace({
      workspaceName: channelName,
      channelName,
      network,
      provider,
      bridgeResources,
      persist: true,
      allowExistingWorkspaceSync: true,
      useWorkspaceRecoveryIndex: true,
      fromGenesis: false,
      progressAction,
    });
  } catch (recoveryError) {
    throw new Error([
      `Channel workspace is not current for ${channelName} on ${networkName}.`,
      "Automatic channel workspace recovery uses only the saved recovery index and will not replay from genesis.",
      `Run channel recover-workspace --channel-name ${channelName} --network ${networkName} first.`,
      `Details: ${recoveryError.message}`,
      cause ? `Initial freshness failure: ${cause.message}` : null,
    ].filter(Boolean).join(" "));
  }

  const context = await loadWorkspaceContext(channelName, networkName, provider);
  try {
    await assertWorkspaceAlignedWithChain(context);
  } catch (postRecoveryError) {
    throw new Error([
      `Channel workspace is still stale after recovery-index sync for ${channelName} on ${networkName}.`,
      "Automatic channel workspace recovery will not replay from genesis.",
      `Run channel recover-workspace --channel-name ${channelName} --network ${networkName} first.`,
      `Details: ${postRecoveryError.message}`,
      cause ? `Initial freshness failure: ${cause.message}` : null,
    ].filter(Boolean).join(" "));
  }
  return {
    context,
    autoRecoveryBlockDelta: readiness.autoRecoveryBlockDelta,
  };
}

async function requireChannelWorkspaceRecoveryIndexForAutoRefresh({
  channelName,
  networkName,
  provider,
  bridgeResources,
  cause = null,
}) {
  const workspaceDir = channelWorkspacePath(networkName, channelName);
  const existingArtifacts = loadExistingWorkspaceArtifacts(workspaceDir);
  const fail = (message) => {
    throw new Error([
      message,
      "Automatic channel workspace recovery uses only the saved recovery index and will not replay from genesis.",
      `Run channel recover-workspace --channel-name ${channelName} --network ${networkName} first.`,
      cause ? `Initial freshness failure: ${cause.message}` : null,
    ].filter(Boolean).join(" "));
  };
  if (!existingArtifacts.workspace || !existingArtifacts.stateSnapshot) {
    fail(`Channel workspace recovery index is missing for ${channelName} on ${networkName}.`);
  }

  const { bridgeDeployment, bridgeAbiManifest } = bridgeResources;
  const bridgeCore = new Contract(bridgeDeployment.bridgeCore, bridgeAbiManifest.contracts.bridgeCore.abi, provider);
  const channelId = deriveChannelIdFromName(channelName);
  const channelInfo = await bridgeCore.getChannel(channelId);
  if (!channelInfo.exists) {
    fail(`Unknown channel ${channelId.toString()} in bridge core ${bridgeDeployment.bridgeCore}.`);
  }
  const channelManager = new Contract(
    channelInfo.manager,
    bridgeAbiManifest.contracts.channelManager.abi,
    provider,
  );
  const genesisBlockNumber = Number(await channelManager.genesisBlockNumber());
  const latestBlock = await provider.getBlockNumber();
  const managedStorageAddresses = normalizedAddressVector(await channelManager.getManagedStorageAddresses());
  const currentRootVectorHash = normalizeBytes32Hex(await channelManager.currentRootVectorHash());
  if (canReuseLocalWorkspaceSnapshot({ existingArtifacts, currentRootVectorHash, managedStorageAddresses })) {
    return { alreadyCurrent: true };
  }
  const recoveryIndex = getUsableWorkspaceRecoveryIndex({
    existingArtifacts,
    genesisBlockNumber,
    latestBlock,
    managedStorageAddresses,
  });
  if (!recoveryIndex) {
    fail(`Channel workspace recovery index is unusable for ${channelName} on ${networkName}.`);
  }
  const cursorDelta = computeRecoveryCursorDelta({
    localNextBlock: recoveryIndex.nextBlock,
    targetNextBlock: Number(latestBlock) + 1,
    genesisBlockNumber,
    label: `Channel workspace ${channelName} on ${networkName}`,
  });
  if (cursorDelta.fresh) {
    fail(`Channel workspace recovery index has already scanned through block ${recoveryIndex.nextBlock - 1}, but the local snapshot is not current.`);
  }
  const autoRecoveryBlockDelta = assertAutoRecoveryBlockBudget({
    label: `channel workspace ${channelName} on ${networkName}`,
    fromBlock: cursorDelta.fromBlock,
    toBlock: cursorDelta.toBlock,
    recoveryCommand: `channel recover-workspace --channel-name ${channelName} --network ${networkName}`,
  });
  return { alreadyCurrent: false, autoRecoveryBlockDelta };
}

async function refreshPersistedWorkspaceAfterLocalTransaction({
  context,
  provider,
  receipt,
  progressAction = null,
}) {
  if (!context.persistChannelWorkspace || !context.workspaceDir) {
    return context;
  }
  const network = resolveCliNetwork(context.workspace.network);
  const bridgeResources = loadBridgeResources({ chainId: Number(context.workspace.chainId) });
  const refreshed = await syncChannelWorkspace({
    workspaceName: context.workspaceName,
    channelName: context.workspace.channelName,
    network,
    provider,
    bridgeResources,
    persist: true,
    allowExistingWorkspaceSync: true,
    useWorkspaceRecoveryIndex: true,
    minimumToBlock: receipt?.blockNumber ?? null,
    progressAction,
  });

  context.workspaceDir = refreshed.workspaceDir;
  context.workspace = refreshed.workspace;
  context.currentSnapshot = refreshed.currentSnapshot;
  context.blockInfo = refreshed.blockInfo;
  context.contractCodes = refreshed.contractCodes;
  context.bridgeAbiManifest = bridgeResources.bridgeAbiManifest;
  context.channelManager = new Contract(
    refreshed.workspace.channelManager,
    bridgeResources.bridgeAbiManifest.contracts.channelManager.abi,
    provider,
  );
  context.bridgeTokenVault = new Contract(
    refreshed.workspace.bridgeTokenVault,
    bridgeResources.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    provider,
  );
  return context;
}

async function recoverLocalWorkspacesAfterAcceptedNoteTransaction({
  wallet,
  context,
  provider,
  receipt,
  progressAction = null,
}) {
  emitProgress(progressAction, "recovering-channel-workspace");
  await refreshPersistedWorkspaceAfterLocalTransaction({
    context,
    provider,
    receipt,
    progressAction,
  });
  emitProgress(progressAction, "recovering-wallet-workspace");
  const { recoveredDeliveryState } = await recoverWalletReceivedNotes({
    walletContext: wallet,
    context,
    provider,
    toBlock: walletNoteReceiveTargetBlock(context),
    progressAction,
    fromGenesis: false,
  });
  const freshness = await assertWalletNoteReceiveStateFresh({
    walletContext: wallet,
    context,
  });
  return {
    channelRecoveryLastScannedBlock: context.workspace.recoveryLastScannedBlock,
    channelRecoveryScanRange: context.workspace.recoveryScanRange,
    walletNoteReceiveNextBlock: freshness.nextBlock,
    walletTargetBlock: freshness.targetBlock,
    recoveredFromLogs: recoveredDeliveryState.importedNotes,
    scannedDeliveryLogs: recoveredDeliveryState.scannedLogs,
    linkedEvidence: recoveredDeliveryState.linkedEvidence,
    noteReceiveScanRange: recoveredDeliveryState.scanRange,
  };
}

function assertWalletMatchesChannelContext(walletContext, l2Identity, context) {
  expect(
    ethers.toBigInt(walletContext.wallet.channelId) === ethers.toBigInt(context.workspace.channelId),
    "The provided wallet does not belong to the selected channel.",
  );
  expect(
    walletContext.wallet.l2Address === l2Identity.l2Address,
    "The provided wallet does not match the derived L2 identity.",
  );
}

async function executeWalletDirectTemplateCommand({
  args,
  wallet,
  provider,
  operationName,
  templatePayload,
  preparedContextResult,
}) {
  emitProgress(operationName, "loading");
  const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);
  requireWalletSpendingCapability(wallet);
  const {
    txSubmitter,
    source: txSubmitterSource,
    account: txSubmitterAccount,
  } = resolveTxSubmitterSigner({
    args,
    ownerSigner: signer,
    provider,
  });
  expect(preparedContextResult?.context, "Internal error: prepared channel context is required before proof generation.");
  const contextResult = preparedContextResult;
  const execution = await executeWalletTemplateSend({
    wallet,
    signer,
    txSubmitter,
    txSubmitterSource,
    txSubmitterAccount,
    l2Identity,
    context: contextResult.context,
    provider,
    operationName,
    functionName: templatePayload.method,
    templatePayload,
  });
  emitProgress(operationName, "done");
  return {
    execution,
    contextResult,
    recoveredWorkspace: contextResult.recoveredWorkspace,
    walletWarnings: [],
  };
}

async function executeWalletTemplateSend({
  wallet,
  signer,
  txSubmitter,
  txSubmitterSource,
  txSubmitterAccount,
  l2Identity,
  context,
  provider,
  operationName,
  functionName,
  templatePayload,
}) {
  await assertWorkspaceAlignedWithChain(context, signer.provider);
  assertWalletMatchesChannelContext(wallet, l2Identity, context);
  await assertChannelProofBackendVersionCompatibility({ context, operationName });

  const controllerAbi = readJson(
    requireLatestDappDeployArtifactPath(context.workspace.chainId, path.basename(templatePayload.abiFile)),
  );
  const calldata = new Interface(controllerAbi).encodeFunctionData(
    templatePayload.method,
    templatePayload.args ?? [],
  );
  const nonce = Number(wallet.wallet.l2Nonce);
  const operationDir = createWalletOperationDir(
    wallet.walletName,
    wallet.wallet.network,
    `${operationName}-${shortAddress(l2Identity.l2Address)}`,
  );
  ensureDir(operationDir);

  const transactionSnapshot = buildTokamakTxSnapshot({
    signerPrivateKey: l2Identity.l2PrivateKey,
    senderPubKey: l2Identity.l2PublicKey,
    to: context.workspace.controller,
    data: calldata,
    nonce,
  });

  writeJson(path.join(operationDir, "previous_state_snapshot.json"), context.currentSnapshot);
  writeJson(path.join(operationDir, "transaction.json"), transactionSnapshot);
  writeJson(path.join(operationDir, "block_info.json"), context.blockInfo);
  writeJson(path.join(operationDir, "contract_codes.json"), context.contractCodes);

  const bundlePath = path.join(operationDir, `${operationName}.zip`);
  emitProgress(operationName, "proving");
  runTokamakProofPipeline({ operationDir, bundlePath });

  const rawNextSnapshot = readJson(path.join(operationDir, "resource", "synthesizer", "output", "state_snapshot.json"));
  if (Array.isArray(rawNextSnapshot.storageAddresses)) {
    rawNextSnapshot.storageAddresses = rawNextSnapshot.storageAddresses
      .map((address) => createAddressFromString(address).toString());
  }
  const nextSnapshot = rawNextSnapshot;
  writeJson(path.join(operationDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"), nextSnapshot);

  const payload = loadTokamakPayloadFromStep(operationDir);
  const functionProof = resolveFunctionMetadataProofForExecution({
    chainId: context.workspace.chainId,
    controllerAddress: context.workspace.controller,
    functionSelector: calldata.slice(0, 10),
    preprocessInputHash: hashTokamakPointEncoding(
      payload.functionPreprocessPart1,
      payload.functionPreprocessPart2,
    ),
    expectedFunctionRoot: context.workspace.functionRoot ?? context.workspace.policySnapshot?.functionRoot,
  });
  const aPubBlockHash = hashTokamakPublicInputs(payload.aPubBlock);
  expect(
    ethers.toBigInt(normalizeBytes32Hex(aPubBlockHash))
      === ethers.toBigInt(normalizeBytes32Hex(context.workspace.aPubBlockHash)),
    "Generated Tokamak proof does not match the channel aPubBlockHash. Check the workspace block_info.json context.",
  );

  await assertWorkspaceAlignedWithChain(context);
  emitProgress(operationName, "submitting");
  const receipt =
    await waitForReceipt(
      await context.channelManager.connect(txSubmitter).executeChannelTransaction(payload, functionProof),
    );
  await waitForProviderBlockAtLeast(provider, receipt.blockNumber, { action: operationName });

  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  expect(
    ethers.toBigInt(onchainRootVectorHash) === ethers.toBigInt(normalizeBytes32Hex(hashRootVector(nextSnapshot.stateRoots))),
    `On-chain roots do not match the Tokamak post-state roots for ${functionName}.`,
  );

  writeJson(path.join(operationDir, "bridge-submit-receipt.json"), sanitizeReceipt(receipt));
  writeJson(path.join(operationDir, "state_snapshot.json"), nextSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), nextSnapshot);

  emitProgress(operationName, "persisting");
  wallet.wallet.l2Nonce = nonce + 1;
  persistWallet(wallet);
  const postTransactionRecovery = await recoverLocalWorkspacesAfterAcceptedNoteTransaction({
    wallet,
    context,
    provider,
    receipt,
    progressAction: operationName,
  });
  sealWalletOperationDir(operationDir, walletOperationSealSecret(wallet));

  return {
    wallet,
    signer,
    txSubmitter,
    txSubmitterSource,
    txSubmitterAccount,
    l2Identity,
    context,
    postTransactionRecovery,
    nonce,
    operationDir,
    receipt,
  };
}

async function loadWorkspaceContext(workspaceName, networkName, provider) {
  const normalizedWorkspaceName = requireWorkspaceName({ workspace: workspaceName });
  const workspaceDir = channelWorkspacePath(networkName, normalizedWorkspaceName);
  const workspace = readJson(channelWorkspaceConfigPath(workspaceDir));
  const bridgeDeploymentPath = defaultBridgeDeploymentPath(workspace.chainId);
  const bridgeAbiManifestPath = defaultBridgeAbiManifestPath(workspace.chainId);
  const bridgeDeployment = readJson(bridgeDeploymentPath);
  const bridgeAbiManifest = loadBridgeAbiManifest(bridgeAbiManifestPath);
  const currentSnapshot = readJson(path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.json"));
  if (Array.isArray(currentSnapshot.storageAddresses)) {
    currentSnapshot.storageAddresses = currentSnapshot.storageAddresses
      .map((address) => createAddressFromString(address).toString());
  }
  const blockInfo = readJson(path.join(channelWorkspaceCurrentPath(workspaceDir), "block_info.json"));
  const contractCodes = readJson(path.join(channelWorkspaceCurrentPath(workspaceDir), "contract_codes.json"));
  const channelManager = new Contract(workspace.channelManager, bridgeAbiManifest.contracts.channelManager.abi, provider);
  const bridgeTokenVault = new Contract(
    workspace.bridgeTokenVault,
    bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    provider,
  );

  return {
    workspaceName: normalizedWorkspaceName,
    workspaceDir,
    persistChannelWorkspace: true,
    workspace,
    bridgeAbiManifest,
    currentSnapshot,
    blockInfo,
    contractCodes,
    channelManager,
    bridgeTokenVault,
  };
}

async function loadJoinChannelContext({ args, network, provider }) {
  const chainId = Number((await provider.getNetwork()).chainId);
  const resolvedNetworkName = network?.name ?? networkNameFromChainId(chainId);
  const channelName = requireArg(args.channelName, "--channel-name");

  const bridgeResources = loadBridgeResources({ chainId });
  const context = await loadFreshChannelWorkspaceContext({
    channelName,
    networkName: resolvedNetworkName,
    provider,
    progressAction: "channel join",
  });

  return {
    workspaceName: channelName,
    workspaceDir: context.workspaceDir,
    persistChannelWorkspace: true,
    workspace: context.workspace,
    bridgeAbiManifest: bridgeResources.bridgeAbiManifest,
    currentSnapshot: context.currentSnapshot,
    blockInfo: context.blockInfo,
    contractCodes: context.contractCodes,
    channelManager: new Contract(
      context.workspace.channelManager,
      bridgeResources.bridgeAbiManifest.contracts.channelManager.abi,
      provider,
    ),
    bridgeTokenVault: new Contract(
      context.workspace.bridgeTokenVault,
      bridgeResources.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
      provider,
    ),
  };
}

function loadWallet(walletName, networkName) {
  const normalizedWalletName = requireWalletName({ wallet: walletName });
  const normalizedNetworkName = requireNetworkName({ network: networkName });
  const walletDir = selectedWalletEpochDir(normalizedWalletName, normalizedNetworkName);
  return loadWalletFromDir({
    walletName: normalizedWalletName,
    networkName: normalizedNetworkName,
    walletDir,
  });
}

function loadWalletFromDir({ walletName, networkName, walletDir }) {
  const normalizedWalletName = requireWalletName({ wallet: walletName });
  const normalizedNetworkName = requireNetworkName({ network: networkName });
  if (!walletConfigExists(walletDir)) {
    throw cliError(CLI_ERROR_CODES.UNKNOWN_WALLET, `Unknown wallet: ${normalizedWalletName} on ${normalizedNetworkName}.`);
  }
  const rawWallet = readJson(walletNotesMetadataPath(walletDir));
  const spendingKey = readWalletKeySecretIfExists({
    networkName: normalizedNetworkName,
    walletName: normalizedWalletName,
    keyKind: "spending",
  });
  const viewingKey = readWalletKeySecretIfExists({
    networkName: normalizedNetworkName,
    walletName: normalizedWalletName,
    keyKind: "viewing",
  });
  if (spendingKey && walletSpendingKeyMatchesWallet(spendingKey.metadata, rawWallet)) {
    rawWallet.l2PrivateKey = spendingKey.privateKey;
    rawWallet.l2PublicKey = spendingKey.metadata?.l2PublicKey ?? rawWallet.l2PublicKey;
  }
  if (viewingKey && walletViewingKeyMatchesWallet(viewingKey.metadata, rawWallet)) {
    rawWallet.noteReceivePrivateKey = viewingKey.privateKey;
  }
  assertWalletHasRequiredKeys(rawWallet, normalizedWalletName);
  const wallet = normalizeWallet(rawWallet);
  assertWalletUsesChannelBoundDerivation(wallet, normalizedWalletName);
  if (wallet.l2PrivateKey) {
    const restoredIdentity = restoreParticipantIdentityFromWallet(wallet);
    expect(
      wallet.l2Address === restoredIdentity.l2Address,
      `Wallet ${normalizedWalletName} is internally inconsistent: stored keys do not match the stored L2 address.`,
    );
  }
  hydrateWalletNotesWithViewingKey(wallet);
  const context = {
    walletName: normalizedWalletName,
    walletDir,
    wallet,
    walletSecret: wallet.l2PrivateKey ?? wallet.noteReceivePrivateKey ?? null,
  };
  return context;
}

function walletSpendingKeyMatchesWallet(metadata, wallet) {
  return metadata?.l2Address
    && ethers.toBigInt(getAddress(metadata.l2Address)) === ethers.toBigInt(getAddress(wallet.l2Address));
}

function walletViewingKeyMatchesWallet(metadata, wallet) {
  return metadata?.noteReceivePubKey?.x
    && ethers.toBigInt(normalizeBytes32Hex(metadata.noteReceivePubKey.x))
      === ethers.toBigInt(normalizeBytes32Hex(wallet.noteReceivePubKeyX))
    && Number(metadata.noteReceivePubKey.yParity) === Number(wallet.noteReceivePubKeyYParity);
}

function loadUnlockedWalletWithMetadata(args) {
  const networkName = requireNetworkName(args);
  const wallet = loadWallet(requireWalletName(args), networkName);
  const walletMetadata = loadWalletMetadata(wallet.walletName, networkName);
  assertWalletMatchesMetadata(wallet, walletMetadata);
  expect(
    wallet.wallet.network === networkName,
    [
      `Wallet ${wallet.walletName} belongs to network ${wallet.wallet.network},`,
      `but the command requested --network ${networkName}.`,
    ].join(" "),
  );
  return {
    wallet,
    walletMetadata,
  };
}

function readWalletKeySecretIfExists({ networkName, walletName, keyKind }) {
  const secretPath = keyKind === "spending"
    ? walletSpendingKeySecretPath(networkName, walletName)
    : walletViewingKeySecretPath(networkName, walletName);
  if (!fs.existsSync(secretPath)) {
    return null;
  }
  const payload = JSON.parse(readSecretFile(secretPath, `${keyKind} key`));
  validateWalletKeyPayload(payload, keyKind);
  return payload;
}

function validateWalletKeyPayload(payload, keyKind) {
  expect(payload?.format === WALLET_KEY_EXPORT_FORMAT, `Invalid ${keyKind} key file format.`);
  expect(Number(payload.formatVersion) === WALLET_EXPORT_FORMAT_VERSION, `Unsupported ${keyKind} key file version.`);
  expect(payload.keyKind === keyKind, `Expected ${keyKind} key file, received ${payload.keyKind}.`);
  expect(typeof payload.privateKey === "string" && payload.privateKey.length > 0, `Missing ${keyKind} private key.`);
  expect(payload.metadata && typeof payload.metadata === "object", `Missing ${keyKind} key metadata.`);
}

function hydrateWalletNotesWithViewingKey(wallet) {
  if (!wallet.noteReceivePrivateKey) {
    return;
  }
  const noteGroups = [wallet.notes?.unused ?? {}, wallet.notes?.spent ?? {}];
  for (const notes of noteGroups) {
    for (const note of Object.values(notes)) {
      if (!note.encryptedNoteValue || note.value !== null) {
        continue;
      }
      try {
        const { scheme } = unpackEncryptedNoteValue(note.encryptedNoteValue);
        let value;
        if (scheme === ENCRYPTED_NOTE_SCHEME_TRANSFER) {
          value = decryptEncryptedNoteValue({
            encryptedValue: note.encryptedNoteValue,
            noteReceivePrivateKey: wallet.noteReceivePrivateKey,
            chainId: wallet.chainId,
            channelId: wallet.channelId,
            owner: wallet.l2Address,
          });
        } else if (scheme === ENCRYPTED_NOTE_SCHEME_SELF_MINT) {
          value = decryptMintEncryptedNoteValue({
            encryptedValue: note.encryptedNoteValue,
            noteReceivePrivateKey: wallet.noteReceivePrivateKey,
            chainId: wallet.chainId,
            channelId: wallet.channelId,
            owner: wallet.l2Address,
          });
        } else {
          continue;
        }
        note.owner = wallet.l2Address;
        note.value = ethers.toBigInt(value).toString();
        note.salt = computeEncryptedNoteSalt(note.encryptedNoteValue);
      } catch {
        // Keep encrypted-only note records readable even when the local viewing key cannot decrypt them.
      }
    }
  }
  wallet.notes = normalizeWallet(wallet).notes;
}

function assertWalletHasRequiredKeys(wallet, walletName) {
  expect(wallet.walletFormatVersion !== undefined, `Wallet ${walletName} is missing walletFormatVersion.`);
}

function assertWalletUsesChannelBoundDerivation(wallet, walletName) {
  expect(
    wallet.l2DerivationMode === CHANNEL_BOUND_L2_DERIVATION_MODE,
    [
      `Wallet ${walletName} was not created with the current channel-bound L2 derivation rule.`,
      "Create a fresh wallet with channel join.",
    ].join(" "),
  );
  expect(
    wallet.l2DerivationChannelName === wallet.channelName,
    [
      `Wallet ${walletName} derivation channel (${wallet.l2DerivationChannelName ?? "missing"})`,
      `does not match the wallet channel (${wallet.channelName}).`,
    ].join(" "),
  );
}

function restoreParticipantIdentityFromWallet(wallet) {
  if (!wallet.l2PrivateKey) {
    return {
      l2PrivateKey: null,
      l2PublicKey: wallet.l2PublicKey ? Uint8Array.from(ethers.getBytes(wallet.l2PublicKey)) : null,
      l2Address: getAddress(wallet.l2Address),
    };
  }
  const l2PrivateKey = Uint8Array.from(ethers.getBytes(wallet.l2PrivateKey));
  const l2PublicKey = Uint8Array.from(ethers.getBytes(wallet.l2PublicKey));
  const l2Address = getAddress(fromEdwardsToAddress(l2PublicKey).toString());
  return {
    l2PrivateKey,
    l2PublicKey,
    l2Address,
  };
}

function restoreWalletSigner(walletContext, provider) {
  const privateKey = findAccountPrivateKeyForAddress(walletContext.wallet.network, walletContext.wallet.l1Address);
  if (privateKey) {
    return new Wallet(privateKey, provider);
  }
  return {
    address: getAddress(walletContext.wallet.l1Address),
    provider,
  };
}

function restoreWalletParticipant(walletContext, provider) {
  return {
    signer: restoreWalletSigner(walletContext, provider),
    l2Identity: restoreParticipantIdentityFromWallet(walletContext.wallet),
  };
}

function requireWalletOwnerSigner(walletContext, provider) {
  const signer = restoreWalletSigner(walletContext, provider);
  expect(
    typeof signer.privateKey === "string",
    [
      `Missing local account secret for wallet owner ${walletContext.wallet.l1Address}.`,
      "Import the matching account secret or use a command-specific transaction submitter where supported.",
    ].join(" "),
  );
  return signer;
}

function requireWalletSpendingCapability(walletContext) {
  expect(
    walletContext.wallet.l2PrivateKey,
    [
      `Wallet ${walletContext.walletName} is missing its spending key.`,
      "Import it with wallet import spending-key before commands that spend notes or change L2 channel accounting state.",
    ].join(" "),
  );
}

function requireWalletViewingCapability(walletContext) {
  expect(
    walletContext.wallet.noteReceivePrivateKey,
    [
      `Wallet ${walletContext.walletName} is missing its viewing key.`,
      "Import it with wallet import viewing-key before commands that decrypt or refresh received notes.",
    ].join(" "),
  );
}

function requireActiveWalletLifecycle(walletContext, commandName) {
  expect(
    walletContext.wallet.lifecycleStatus !== "exited",
    [
      `${commandName} cannot operate on exited wallet epoch ${walletContext.wallet.walletEpochId ?? "unknown"}.`,
      "Exited wallet epochs are read-only. Use wallet get-notes or wallet get-notes --export-evidence for historical disclosure.",
    ].join(" "),
  );
}

function walletOperationSealSecret(walletContext) {
  const secret = walletContext.wallet.l2PrivateKey
    ?? walletContext.wallet.noteReceivePrivateKey
    ?? findAccountPrivateKeyForAddress(walletContext.wallet.network, walletContext.wallet.l1Address);
  expect(
    secret,
    `Wallet ${walletContext.walletName} needs a local key to seal operation artifacts.`,
  );
  return secret;
}

function findAccountPrivateKeyForAddress(networkName, l1Address) {
  const accountsRoot = path.join(secretRoot, requireNetworkName({ network: networkName }), "accounts");
  if (!fs.existsSync(accountsRoot)) {
    return null;
  }
  for (const entry of fs.readdirSync(accountsRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) {
      continue;
    }
    const privateKeyPath = path.join(accountsRoot, entry.name, "private-key");
    if (!fs.existsSync(privateKeyPath)) {
      continue;
    }
    try {
      const privateKey = normalizePrivateKey(readSecretFile(privateKeyPath, "--account"));
      const signer = new Wallet(privateKey);
      if (ethers.toBigInt(getAddress(signer.address)) === ethers.toBigInt(getAddress(l1Address))) {
        return privateKey;
      }
    } catch {
      continue;
    }
  }
  return null;
}

function loadBridgeResources({ chainId }) {
  const bridgeDeploymentPath = defaultBridgeDeploymentPath(chainId);
  const bridgeDeployment = readJson(bridgeDeploymentPath);
  const bridgeAbiManifestPath = defaultBridgeAbiManifestPath(chainId);
  const bridgeAbiManifest = loadBridgeAbiManifest(bridgeAbiManifestPath);
  return {
    chainId,
    bridgeDeploymentPath,
    bridgeDeployment,
    bridgeAbiManifestPath,
    bridgeAbiManifest,
  };
}

function loadWalletMetadata(walletName, networkName) {
  const normalizedWalletName = requireWalletName({ wallet: walletName });
  const normalizedNetworkName = requireNetworkName({ network: networkName });
  const walletDir = selectedWalletEpochDir(normalizedWalletName, normalizedNetworkName);
  if (!walletConfigExists(walletDir)) {
    throw cliError(CLI_ERROR_CODES.UNKNOWN_WALLET, `Unknown wallet: ${normalizedWalletName} on ${normalizedNetworkName}.`);
  }
  const metadataPath = walletNotesMetadataPath(walletDir);
  if (!fs.existsSync(metadataPath)) {
    throw new Error(`Wallet ${normalizedWalletName} is missing unencrypted metadata at ${metadataPath}.`);
  }
  const metadata = readJson(metadataPath);
  expect(
    typeof metadata.network === "string" && metadata.network.length > 0,
    `Wallet ${normalizedWalletName} metadata is missing network.`,
  );
  expect(
    typeof metadata.channelName === "string" && metadata.channelName.length > 0,
      `Wallet ${normalizedWalletName} metadata is missing channelName.`,
  );
  expect(
    metadata.network === normalizedNetworkName,
    `Wallet ${normalizedWalletName} metadata network (${metadata.network}) does not match --network ${normalizedNetworkName}.`,
  );
  return metadata;
}

function assertWalletMatchesMetadata(walletContext, walletMetadata) {
  expect(
    walletContext.wallet.network === walletMetadata.network,
    [
      `Wallet ${walletContext.walletName} metadata network (${walletMetadata.network}) does not match`,
      `the wallet note metadata network (${walletContext.wallet.network}).`,
    ].join(" "),
  );
  expect(
    walletContext.wallet.channelName === walletMetadata.channelName,
    [
      `Wallet ${walletContext.walletName} metadata channelName (${walletMetadata.channelName}) does not match`,
      `the wallet note metadata channel (${walletContext.wallet.channelName}).`,
    ].join(" "),
  );
}

async function loadBridgeVaultContext({ provider, chainId }) {
  const bridgeResources = loadBridgeResources({ chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    provider,
  );
  const bridgeTokenVaultAddress = getAddress(
    bridgeResources.bridgeDeployment.bridgeTokenVault ?? await bridgeCore.bridgeTokenVault(),
  );
  const canonicalAsset = getAddress(await bridgeCore.canonicalAsset());
  const canonicalAssetDecimals = await fetchTokenDecimals(provider, canonicalAsset);
  const storageLayoutManifestPath = dappStorageLayoutManifestPath(chainId);
  const storageLayoutManifest = readJson(storageLayoutManifestPath);
  const liquidBalancesSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "L2AccountingVault", "liquidBalances"));

  return {
    ...bridgeResources,
    bridgeCore,
    bridgeTokenVaultAddress,
    canonicalAsset,
    canonicalAssetDecimals,
    liquidBalancesSlot,
  };
}

async function assertWorkspaceAlignedWithChain(context) {
  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  const snapshotRootVectorHash = normalizeBytes32Hex(hashRootVector(context.currentSnapshot.stateRoots));
  expect(
    onchainRootVectorHash === snapshotRootVectorHash,
    cliError(
      CLI_ERROR_CODES.STALE_WORKSPACE,
      [
        "The workspace snapshot is stale relative to the bridge channel state.",
        `Workspace: ${context.workspaceDir}`,
        `Run channel recover-workspace --channel-name ${context.workspace.channelName} --network ${context.workspace.network}.`,
      ].join(" "),
    ),
  );
}

async function assertChannelProofBackendVersionCompatibility({ context, operationName }) {
  const channelVersions = await readChannelVerifierCompatibleBackendVersions(context);
  const localVersions = readLocalProofBackendPackageVersions();
  const checks = [
    {
      label: "Groth16",
      packageName: GROTH16_PACKAGE_NAME,
      versionKind: "compatible backend version",
      channelVersion: requireCanonicalGroth16CompatibleBackendVersion(
        channelVersions.groth16,
        "channel Groth16 verifier compatibleBackendVersion",
      ),
      localVersion: localVersions.groth16.compatibleBackendVersion,
    },
    {
      label: "Tokamak zk-EVM",
      packageName: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      versionKind: "compatible backend version",
      channelVersion: requireCanonicalCompatibleBackendVersion(
        channelVersions.tokamak,
        "channel Tokamak verifier compatibleBackendVersion",
      ),
      localVersion: localVersions.tokamak.compatibleBackendVersion,
    },
  ];
  const mismatches = checks.filter(({ channelVersion, localVersion }) => channelVersion !== localVersion);
  if (mismatches.length === 0) {
    return;
  }

  throw new Error(
    [
      `Channel proof backend version mismatch before ${operationName} proof generation.`,
      `Channel: ${context.workspace.channelName ?? context.workspaceName ?? context.workspace.channelId}.`,
      ...mismatches.map(({ label, packageName, versionKind, channelVersion, localVersion }) => (
        `${label} verifier expects ${packageName} ${versionKind} ${channelVersion}, `
          + `but the local installed ${versionKind} is ${localVersion ?? "<missing>"}.`
      )),
      "Install proof backend runtimes compatible with this channel before generating proofs.",
    ].join(" "),
  );
}

async function readChannelVerifierCompatibleBackendVersions(context) {
  const channelManagerAddress = getAddress(context.workspace.channelManager);
  const channelManager = new Contract(
    channelManagerAddress,
    channelVerifierVersionAbi,
    context.channelManager.runner,
  );
  try {
    const [groth16, tokamak] = await Promise.all([
      channelManager.grothVerifierCompatibleBackendVersion(),
      channelManager.tokamakVerifierCompatibleBackendVersion(),
    ]);
    return {
      groth16: requireVersionString(groth16, "channel Groth16 verifier compatibleBackendVersion"),
      tokamak: requireVersionString(tokamak, "channel Tokamak verifier compatibleBackendVersion"),
    };
  } catch (error) {
    throw new Error(
      [
        `Unable to read verifier compatibleBackendVersion values from channel manager ${channelManagerAddress}.`,
        "The target channel must expose grothVerifierCompatibleBackendVersion() and tokamakVerifierCompatibleBackendVersion().",
      ].join(" "),
      { cause: error },
    );
  }
}

async function readChannelPolicySnapshot({ channelManager, dappId }) {
  const channelManagerAddress = getAddress(await channelManager.getAddress());
  try {
    const [
      dappMetadataDigestSchema,
      dappMetadataDigest,
      functionRoot,
      grothVerifier,
      grothVerifierCompatibleBackendVersion,
      tokamakVerifier,
      tokamakVerifierCompatibleBackendVersion,
    ] = await Promise.all([
      channelManager.dappMetadataDigestSchema(),
      channelManager.dappMetadataDigest(),
      channelManager.functionRoot(),
      channelManager.grothVerifier(),
      channelManager.grothVerifierCompatibleBackendVersion(),
      channelManager.tokamakVerifier(),
      channelManager.tokamakVerifierCompatibleBackendVersion(),
    ]);
    return {
      dappId: Number(dappId),
      dappMetadataDigestSchema: normalizeBytes32Hex(dappMetadataDigestSchema),
      dappMetadataDigest: normalizeBytes32Hex(dappMetadataDigest),
      functionRoot: normalizeBytes32Hex(functionRoot),
      grothVerifier: getAddress(grothVerifier),
      grothVerifierCompatibleBackendVersion: requireVersionString(
        grothVerifierCompatibleBackendVersion,
        "channel Groth16 verifier compatibleBackendVersion",
      ),
      tokamakVerifier: getAddress(tokamakVerifier),
      tokamakVerifierCompatibleBackendVersion: requireVersionString(
        tokamakVerifierCompatibleBackendVersion,
        "channel Tokamak verifier compatibleBackendVersion",
      ),
    };
  } catch (error) {
    throw new Error(
      [
        `Unable to read immutable policy snapshot from channel manager ${channelManagerAddress}.`,
        "The target channel must expose DApp digest, verifier address, and compatibleBackendVersion getters.",
      ].join(" "),
      { cause: error },
    );
  }
}

async function readChannelRefundSchedule(channelManager) {
  const [
    cutoff1,
    bps1,
    cutoff2,
    bps2,
    cutoff3,
    bps3,
    bps4,
  ] = await Promise.all([
    channelManager.joinTollRefundCutoff1(),
    channelManager.joinTollRefundBps1(),
    channelManager.joinTollRefundCutoff2(),
    channelManager.joinTollRefundBps2(),
    channelManager.joinTollRefundCutoff3(),
    channelManager.joinTollRefundBps3(),
    channelManager.joinTollRefundBps4(),
  ]);
  return {
    cutoff1Seconds: Number(cutoff1),
    bps1: formatBpsRatio(bps1),
    cutoff2Seconds: Number(cutoff2),
    bps2: formatBpsRatio(bps2),
    cutoff3Seconds: Number(cutoff3),
    bps3: formatBpsRatio(bps3),
    bps4: formatBpsRatio(bps4),
  };
}

function formatBpsRatio(value) {
  const normalized = ethers.toBigInt(value);
  const whole = normalized / JOIN_TOLL_REFUND_BPS_DENOMINATOR;
  const fraction = normalized % JOIN_TOLL_REFUND_BPS_DENOMINATOR;
  if (fraction === 0n) {
    return whole.toString();
  }
  return `${whole.toString()}.${fraction.toString().padStart(4, "0").replace(/0+$/, "")}`;
}

function isContractError(error, contractInterface, errorName) {
  if (error?.revert?.name === errorName) {
    return true;
  }
  for (const errorData of extractContractErrorDataCandidates(error)) {
    try {
      if (contractInterface.parseError(errorData)?.name === errorName) {
        return true;
      }
    } catch {
      // Keep scanning nested provider error payloads.
    }
  }
  return false;
}

function extractContractErrorDataCandidates(error) {
  return [
    error?.data,
    error?.error?.data,
    error?.info?.error?.data,
    error?.info?.error?.error?.data,
  ].filter((value) => typeof value === "string" && /^0x[0-9a-fA-F]+$/.test(value));
}

function readLocalProofBackendPackageVersions() {
  const groth16Runtime = inspectGroth16Runtime();
  const tokamakPackageReport = readTokamakCliPackageReport();
  return {
    groth16: {
      packageVersion: groth16Runtime.packageVersion,
      compatibleBackendVersion: groth16Runtime.crsCompatibleBackendVersion
        ?? groth16Runtime.compatibleBackendVersion,
    },
    tokamak: {
      packageVersion: requirePackageReportVersion(tokamakPackageReport),
      compatibleBackendVersion: requirePackageReportCompatibleBackendVersion(tokamakPackageReport),
    },
  };
}

function requirePackageReportVersion(report) {
  if (!report.version) {
    throw new Error(
      `Unable to determine local ${report.name} package version${report.error ? `: ${report.error}` : "."}`,
    );
  }
  return requireVersionString(report.version, `${report.name} package version`);
}

function requirePackageReportCompatibleBackendVersion(report) {
  if (!report.compatibleBackendVersion) {
    throw new Error(
      `Unable to determine local ${report.name} compatible backend version${report.error ? `: ${report.error}` : "."}`,
    );
  }
  return requireVersionString(report.compatibleBackendVersion, `${report.name} compatible backend version`);
}

function requireVersionString(value, label) {
  const normalized = String(value ?? "").trim();
  expect(normalized.length > 0, `${label} is missing.`);
  return normalized;
}

async function buildGrothTransition({ operationDir, workspace, stateManager, vaultAddress, keyHex, nextValue }) {
  const vaultAddressObj = createAddressFromString(vaultAddress);
  const keyBigInt = ethers.toBigInt(keyHex);
  const proof = stateManager.merkleTrees.getProof(vaultAddressObj, keyBigInt);
  const currentRoot = stateManager.merkleTrees.getRoot(vaultAddressObj);
  const currentValue = await currentStorageBigInt(stateManager, vaultAddress, keyHex);
  const currentSnapshot = await stateManager.captureStateSnapshot();

  await stateManager.putStorage(
    vaultAddressObj,
    hexToBytes(addHexPrefix(String(keyHex ?? "").replace(/^0x/i, ""))),
    hexToBytes(addHexPrefix(String(bigintToHex32(nextValue) ?? "").replace(/^0x/i, ""))),
  );
  const updatedRoot = stateManager.merkleTrees.getRoot(vaultAddressObj);
  const nextSnapshot = await stateManager.captureStateSnapshot();

  const input = {
    root_before: currentRoot.toString(),
    root_after: updatedRoot.toString(),
    leaf_index: ethers.toBigInt(proof.leafIndex).toString(),
    storage_key: keyBigInt.toString(),
    storage_value_before: currentValue.toString(),
    storage_value_after: nextValue.toString(),
    proof: proof.siblings.map((siblings) => ethers.toBigInt(siblings[0] ?? 0n).toString()),
  };

  const inputPath = path.join(operationDir, "input.json");
  writeJson(inputPath, input);
  const proofManifest = runGroth16UpdateTreeProof(inputPath);

  const proofJson = readJson(proofManifest.proofPath);
  const publicSignals = readJson(proofManifest.publicPath);

  return {
    input,
    proofJson,
    publicSignals,
    proof: toGroth16SolidityProof(proofJson),
    update: {
      currentRootVector: normalizedRootVector(currentSnapshot.stateRoots),
      updatedRoot: bigintToHex32(updatedRoot),
      currentUserKey: normalizeBytes32Hex(keyHex),
      currentUserValue: currentValue,
      updatedUserKey: normalizeBytes32Hex(keyHex),
      updatedUserValue: nextValue,
    },
    nextSnapshot,
  };
}

function run(command, args, { cwd = defaultCommandCwd, env = process.env, quiet = false } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: quiet ? ["ignore", "ignore", "ignore"] : "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}.`);
  }
}

function runCaptured(command, args, { cwd = defaultCommandCwd, env = process.env } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
  });
  return {
    status: result.status,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

function runGroth16UpdateTreeProof(inputPath) {
  const {
    packageRoot,
    entryPath,
    proofManifestPath,
  } = resolveActiveGroth16ProverRuntime();
  run(process.execPath, [entryPath, "--prove", inputPath], {
    cwd: packageRoot,
    quiet: isJsonOutputRequested(),
  });
  const manifest = readJson(proofManifestPath);
  expect(typeof manifest.proofPath === "string" && manifest.proofPath.length > 0, "Groth16 proof manifest is missing proofPath.");
  expect(typeof manifest.publicPath === "string" && manifest.publicPath.length > 0, "Groth16 proof manifest is missing publicPath.");
  return manifest;
}

function runTokamakProofPipeline({ operationDir, bundlePath }) {
  runTokamakCliStage({
    operationDir,
    stageName: "synthesize",
    args: ["--synthesize", operationDir],
  });
  runTokamakCliStage({
    operationDir,
    stageName: "preprocess",
    args: ["--preprocess"],
  });
  runTokamakCliStage({
    operationDir,
    stageName: "prove",
    args: ["--prove"],
  });
  runTokamakCliStage({
    operationDir,
    stageName: "extract-proof",
    args: ["--extract-proof", bundlePath],
  });
  runTokamakCliStage({
    operationDir,
    stageName: "verify",
    args: ["--verify", bundlePath],
  });
  copyTokamakOperationArtifacts(operationDir);
}

function runTokamakCliStage({ operationDir, stageName, args }) {
  const invocation = resolveActiveTokamakCliInvocation();
  const result = runCaptured(invocation.command, [...invocation.args, ...args], { cwd: invocation.packageRoot });
  const logPath = writeTokamakCliStageLog(operationDir, stageName, result);
  if (result.status !== 0) {
    throw new Error(
      [
        `Tokamak ${stageName} failed with exit code ${result.status ?? "unknown"}.`,
        `See ${logPath} for the full terminal output.`,
      ].join(" "),
    );
  }

  const consoleError = findTokamakConsoleError({ stdout: result.stdout, stderr: result.stderr });
  if (consoleError) {
    throw new Error(
      [
        `Tokamak ${stageName} reported internal errors in its terminal output.`,
        `First reported message: ${consoleError}`,
        `See ${logPath} for the full terminal output.`,
      ].join(" "),
    );
  }
}

function writeTokamakCliStageLog(operationDir, stageName, { stdout, stderr }) {
  const logsDir = path.join(operationDir, "tokamak-cli-logs");
  ensureDir(logsDir);
  const logPath = path.join(logsDir, `${stageName}.log`);
  const sections = [
    `# Stage: ${stageName}`,
    "",
    "## stdout",
    stdout.trimEnd(),
    "",
    "## stderr",
    stderr.trimEnd(),
    "",
  ];
  fs.writeFileSync(logPath, sections.join("\n"), "utf8");
  return logPath;
}

function findTokamakConsoleError({ stdout, stderr }) {
  const lines = `${stdout}\n${stderr}`
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  const errorPatterns = [
    /\[error\]/i,
    /^error:/i,
  ];

  const matchedLine = lines.find((line) => errorPatterns.some((pattern) => pattern.test(line)));
  return matchedLine ?? null;
}

function copyTokamakOperationArtifacts(operationDir) {
  const resourceRoot = path.join(operationDir, "resource");
  fs.rmSync(resourceRoot, { recursive: true, force: true });
  const runtimeRoot = requireActiveTokamakCliRuntimeRoot();

  const requiredFiles = [
    ["preprocess", "output", "preprocess.json"],
    ["prove", "output", "proof.json"],
    ["synthesizer", "output", "instance.json"],
    ["synthesizer", "output", "state_snapshot.json"],
  ];

  for (const segments of requiredFiles) {
    const sourcePath = resolveTokamakCliResourceDirForRuntimeRoot(runtimeRoot, ...segments);
    const targetPath = path.join(resourceRoot, ...segments);
    ensureDir(path.dirname(targetPath));
    fs.copyFileSync(sourcePath, targetPath);
  }
}

function loadTokamakPayloadFromStep(operationDir) {
  const proofJson = readJson(path.join(operationDir, "resource", "prove", "output", "proof.json"));
  const preprocessJson = readJson(path.join(operationDir, "resource", "preprocess", "output", "preprocess.json"));
  const instanceJson = readJson(path.join(operationDir, "resource", "synthesizer", "output", "instance.json"));

  return {
    proofPart1: proofJson.proof_entries_part1.map((value) => ethers.toBigInt(value)),
    proofPart2: proofJson.proof_entries_part2.map((value) => ethers.toBigInt(value)),
    functionPreprocessPart1: preprocessJson.preprocess_entries_part1.map((value) => ethers.toBigInt(value)),
    functionPreprocessPart2: preprocessJson.preprocess_entries_part2.map((value) => ethers.toBigInt(value)),
    aPubUser: instanceJson.a_pub_user.map((value) => ethers.toBigInt(value)),
    aPubBlock: normalizeTokamakAPubBlock(instanceJson.a_pub_block.map((value) => ethers.toBigInt(value))),
  };
}

async function fetchTokenDecimals(provider, assetAddress) {
  const asset = new Contract(assetAddress, erc20MetadataAbi, provider);
  return Number(await asset.decimals());
}

function normalizedRootVector(roots) {
  return roots.map((value) => normalizeBytes32Hex(value));
}

function hashRootVector(roots) {
  return keccak256(abiCoder.encode(["bytes32[]"], [normalizedRootVector(roots)]));
}

function normalizedAddressVector(addresses) {
  return addresses.map((value) => getAddress(value));
}

function normalizeBytes12Hex(value) {
  return normalizeBytesHex(value, 12);
}

function hashTokamakPublicInputs(values) {
  return keccak256(abiCoder.encode(["uint256[]"], [values]));
}

function hashTokamakPointEncoding(part1, part2) {
  return keccak256(abiCoder.encode(["uint128[]", "uint256[]"], [part1, part2]));
}

function encodeTokamakBlockInfo(blockInfo) {
  const values = new Array(TOKAMAK_APUB_BLOCK_LENGTH).fill(0n);
  appendSplitWord(values, 0, ethers.toBigInt(blockInfo.coinBase));
  appendSplitWord(values, 2, ethers.toBigInt(blockInfo.timeStamp));
  appendSplitWord(values, 4, ethers.toBigInt(blockInfo.blockNumber));
  appendSplitWord(values, 6, ethers.toBigInt(blockInfo.prevRanDao));
  appendSplitWord(values, 8, ethers.toBigInt(blockInfo.gasLimit));
  appendSplitWord(values, 10, ethers.toBigInt(blockInfo.chainId));
  appendSplitWord(values, 12, ethers.toBigInt(blockInfo.selfBalance));
  appendSplitWord(values, 14, ethers.toBigInt(blockInfo.baseFee));
  for (let index = 0; index < TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT; index += 1) {
    appendSplitWord(values, 16 + index * 2, ethers.toBigInt(blockInfo.prevBlockHashes[index] ?? 0n));
  }
  return values;
}

function normalizeTokamakAPubBlock(values) {
  let normalizedValues = values.slice();
  if (normalizedValues.length > TOKAMAK_APUB_BLOCK_LENGTH) {
    const trailingValues = normalizedValues.slice(TOKAMAK_APUB_BLOCK_LENGTH);
    if (!trailingValues.every((value) => value === 0n)) {
      throw new Error(
        `a_pub_block length ${normalizedValues.length} exceeds the fixed Tokamak block input length ${TOKAMAK_APUB_BLOCK_LENGTH}.`,
      );
    }
    normalizedValues = normalizedValues.slice(0, TOKAMAK_APUB_BLOCK_LENGTH);
  }
  return normalizedValues.concat(new Array(TOKAMAK_APUB_BLOCK_LENGTH - normalizedValues.length).fill(0n));
}

function appendSplitWord(target, startIndex, value) {
  const normalized = ethers.toBigInt(value);
  target[startIndex] = normalized & ((1n << 128n) - 1n);
  target[startIndex + 1] = normalized >> 128n;
}

async function fetchChannelRecoveryLogs({
  provider,
  bridgeAbiManifest,
  channelInfo,
  channelManager = null,
  fromBlock,
  toBlock,
  progressAction = null,
}) {
  const recoveryFilter = buildChannelRecoveryLogFilter({
    bridgeAbiManifest,
    channelInfo,
    channelManager,
  });
  const logs = await fetchLogsChunked(provider, {
    address: recoveryFilter.addresses,
    topics: recoveryFilter.topics,
    fromBlock,
    toBlock,
    onProgress: progressAction
      ? createRpcLogScanProgress({ action: progressAction, label: "channel-recovery events" })
      : null,
  });
  return {
    currentRootVectorObservedTopic: recoveryFilter.currentRootVectorObservedTopic,
    channelManagerLogs: logs.filter((log) =>
      ethers.toBigInt(getAddress(log.address)) === ethers.toBigInt(getAddress(channelInfo.manager))),
    bridgeVaultLogs: logs.filter((log) =>
      ethers.toBigInt(getAddress(log.address)) === ethers.toBigInt(getAddress(channelInfo.bridgeTokenVault))),
  };
}

async function fetchChannelRecoveryEventGroupsChunked({
  provider,
  bridgeAbiManifest,
  channelInfo,
  channelManager = null,
  fromBlock,
  toBlock,
  progressAction = null,
  rpcCallHistoryRecorder = null,
  onChunk,
}) {
  const recoveryFilter = buildChannelRecoveryLogFilter({
    bridgeAbiManifest,
    channelInfo,
    channelManager,
  });

  await fetchLogsChunked(provider, {
    address: recoveryFilter.addresses,
    topics: recoveryFilter.topics,
    fromBlock,
    toBlock,
    collectLogs: false,
    onProgress: progressAction
      ? createRpcLogScanProgress({ action: progressAction, label: "channel-recovery chunks" })
      : null,
    onChunk: async ({ request, logs, chunkFromBlock, chunkToBlock }) => {
      const groupedValues = normalizeWorkspaceMirrorDeltaEventGroups({
        logs,
        channelInfo,
        bridgeAbiManifest,
        fromBlock: chunkFromBlock,
        toBlock: chunkToBlock,
      });
      rpcCallHistoryRecorder?.recordEthGetLogs({
        request,
        logs,
        groupedValues,
        chunkFromBlock,
        chunkToBlock,
      });
      await onChunk?.({
        groupedValues,
        chunkFromBlock,
        chunkToBlock,
      });
    },
  });
}

function buildChannelRecoveryLogFilter({ bridgeAbiManifest, channelInfo, channelManager = null }) {
  const resolvedChannelManager = channelManager ?? new Contract(
    channelInfo.manager,
    bridgeAbiManifest.contracts.channelManager.abi,
  );
  const bridgeTokenVault = new Contract(
    channelInfo.bridgeTokenVault,
    bridgeAbiManifest.contracts.bridgeTokenVault.abi,
  );
  const currentRootVectorObservedTopic =
    normalizeBytes32Hex(resolvedChannelManager.interface.getEvent("CurrentRootVectorObserved").topicHash);
  const bridgeVaultStorageWriteObservedTopic =
    normalizeBytes32Hex(bridgeTokenVault.interface.getEvent("StorageWriteObserved").topicHash);
  return {
    addresses: [
      getAddress(channelInfo.manager),
      getAddress(channelInfo.bridgeTokenVault),
    ],
    topics: [[
      currentRootVectorObservedTopic,
      CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC,
      VAULT_STORAGE_WRITE_OBSERVED_TOPIC,
      bridgeVaultStorageWriteObservedTopic,
    ]],
    currentRootVectorObservedTopic,
    bridgeVaultStorageWriteObservedTopic,
  };
}

async function reconstructChannelSnapshot({
  provider,
  bridgeAbiManifest,
  channelInfo,
  channelManager,
  currentRootVectorHash,
  managedStorageAddresses,
  contractCodes,
  genesisBlockNumber,
  channelId,
  controllerAddress,
  l2AccountingVaultAddress,
  liquidBalancesSlot,
  baseSnapshot = null,
  fromBlock = genesisBlockNumber,
  toBlock = null,
  progressAction = null,
  onCheckpoint = null,
  rpcCallHistoryRecorder = null,
}) {
  let startingSnapshot = baseSnapshot;
  if (!startingSnapshot) {
    const genesisStateManager = new TokamakL2StateManager({ common: createTokamakL2Common() });
    const managedAddressObjects = managedStorageAddresses.map((address) => createAddressFromString(address));
    await genesisStateManager._initializeForAddresses(managedAddressObjects);
    genesisStateManager._channelId = channelId.toString();
    for (const address of managedAddressObjects) {
      genesisStateManager._commitResolvedStorageEntries(address, []);
    }
    startingSnapshot = await genesisStateManager.captureStateSnapshot();
  }

  const latestBlock = toBlock === null ? await provider.getBlockNumber() : Number(toBlock);
  const scanFromBlock = Math.max(Number(genesisBlockNumber), Number(fromBlock));
  let currentSnapshot = startingSnapshot;
  if (onCheckpoint && scanFromBlock <= latestBlock) {
    await onCheckpoint({
      currentSnapshot,
      scanRange: {
        fromBlock: scanFromBlock,
        toBlock: scanFromBlock - 1,
        mode: baseSnapshot ? "recovery-index-initial" : "genesis-initial",
      },
    });
  }
  const stateManager = await buildStateManager(currentSnapshot, contractCodes);

  await fetchChannelRecoveryEventGroupsChunked({
    provider,
    bridgeAbiManifest,
    channelInfo,
    channelManager,
    fromBlock: scanFromBlock,
    toBlock: latestBlock,
    progressAction,
    rpcCallHistoryRecorder,
    onChunk: async ({ groupedValues, chunkFromBlock, chunkToBlock }) => {
      currentSnapshot = await applyChannelRecoveryEventGroupsToStateManager({
        stateManager,
        fallbackSnapshot: currentSnapshot,
        groupedValues,
        channelInfo,
        controllerAddress,
        l2AccountingVaultAddress,
        liquidBalancesSlot,
      });
      await onCheckpoint?.({
        currentSnapshot,
        scanRange: {
          fromBlock: scanFromBlock,
          toBlock: chunkToBlock,
          chunkFromBlock,
          chunkToBlock,
          mode: baseSnapshot ? "recovery-index" : "genesis",
        },
      });
    },
  });

  expect(
    ethers.toBigInt(normalizeBytes32Hex(hashRootVector(currentSnapshot.stateRoots)))
      === ethers.toBigInt(normalizeBytes32Hex(currentRootVectorHash)),
    "Reconstructed channel snapshot does not match the current on-chain root vector hash.",
  );

  return {
    currentSnapshot,
    scanRange: {
      fromBlock: scanFromBlock,
      toBlock: latestBlock,
      mode: baseSnapshot ? "recovery-index" : "genesis",
    },
  };
}

async function applyChannelRecoveryEventGroups({
  startingSnapshot,
  groupedValues,
  contractCodes,
  channelInfo,
  controllerAddress,
  l2AccountingVaultAddress,
  liquidBalancesSlot,
}) {
  const stateManager = await buildStateManager(startingSnapshot, contractCodes);
  return applyChannelRecoveryEventGroupsToStateManager({
    stateManager,
    fallbackSnapshot: startingSnapshot,
    groupedValues,
    channelInfo,
    controllerAddress,
    l2AccountingVaultAddress,
    liquidBalancesSlot,
  });
}

async function applyChannelRecoveryEventGroupsToStateManager({
  stateManager,
  fallbackSnapshot,
  groupedValues,
  channelInfo,
  controllerAddress,
  l2AccountingVaultAddress,
  liquidBalancesSlot,
}) {
  let currentSnapshot = fallbackSnapshot;
  for (const group of groupedValues) {
    const orderedGroup = [...group].sort(compareLogsByPosition);
    const rootEvent = orderedGroup.find(
      (event) => ethers.toBigInt(getAddress(event.address)) === ethers.toBigInt(getAddress(channelInfo.manager))
        && event.fragment?.name === "CurrentRootVectorObserved",
    );
    if (!rootEvent) {
      continue;
    }

    const emittedRootVector = normalizedRootVector(rootEvent.args.rootVector);
    const emittedRootVectorHash = normalizeBytes32Hex(rootEvent.args.rootVectorHash);

    for (const event of orderedGroup) {
      if (event.fragment?.name === "StorageWriteObserved") {
        const storageAddr = getAddress(event.args.storageAddr);
        const storageKey = bigintToHex32(ethers.toBigInt(event.args.storageKey));
        const storageValue = bigintToHex32(ethers.toBigInt(event.args.value));
        await stateManager.putStorage(
          createAddressFromString(storageAddr),
          hexToBytes(addHexPrefix(String(storageKey ?? "").replace(/^0x/i, ""))),
          hexToBytes(addHexPrefix(String(storageValue ?? "").replace(/^0x/i, ""))),
        );
        continue;
      }

      const topic0 = event.topics[0] ? normalizeBytes32Hex(event.topics[0]) : null;
      if (topic0 !== null && ethers.toBigInt(topic0) === ethers.toBigInt(normalizeBytes32Hex(CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC))) {
        const { storageKey } = controllerStorageKeyObservedEventInterface.decodeEventLog(
          "StorageKeyObserved",
          event.data,
          event.topics,
        );
        await stateManager.putStorage(
          createAddressFromString(controllerAddress),
          hexToBytes(addHexPrefix(String(normalizeBytes32Hex(storageKey) ?? "").replace(/^0x/i, ""))),
          hexToBytes(addHexPrefix(String(bigintToHex32(1n) ?? "").replace(/^0x/i, ""))),
        );
        continue;
      }

      if (topic0 !== null && ethers.toBigInt(topic0) === ethers.toBigInt(normalizeBytes32Hex(VAULT_STORAGE_WRITE_OBSERVED_TOPIC))) {
        const { l2Address, value } = vaultStorageWriteObservedEventInterface.decodeEventLog(
          "LiquidBalanceStorageWriteObserved",
          event.data,
          event.topics,
        );
        const storageKey = deriveLiquidBalanceStorageKey(
          getAddress(l2Address),
          ethers.toBigInt(liquidBalancesSlot),
        );
        await stateManager.putStorage(
          createAddressFromString(l2AccountingVaultAddress),
          hexToBytes(addHexPrefix(String(normalizeBytes32Hex(storageKey) ?? "").replace(/^0x/i, ""))),
          hexToBytes(addHexPrefix(String(normalizeBytes32Hex(value) ?? "").replace(/^0x/i, ""))),
        );
      }
    }

    currentSnapshot = await stateManager.captureStateSnapshot();
    expect(
      ethers.toBigInt(normalizeBytes32Hex(hashRootVector(currentSnapshot.stateRoots))) === ethers.toBigInt(emittedRootVectorHash),
      `CurrentRootVectorObserved hash mismatch at tx ${rootEvent.transactionHash}.`,
    );
    expect(
      currentSnapshot.stateRoots.length === emittedRootVector.length
        && currentSnapshot.stateRoots.every(
          (root, index) => ethers.toBigInt(normalizeBytes32Hex(root)) === ethers.toBigInt(emittedRootVector[index]),
        ),
      `CurrentRootVectorObserved root vector mismatch at tx ${rootEvent.transactionHash}.`,
    );
  }
  return currentSnapshot;
}

async function applyWorkspaceMirrorDeltaBundle({
  delta,
  localRecoveryIndex,
  manifest,
  chainId,
  channelId,
  channelInfo,
  bridgeAbiManifest,
  managedStorageAddresses,
  contractCodes,
  controllerAddress,
  l2AccountingVaultAddress,
  liquidBalancesSlot,
}) {
  expect(Number(delta.protocolVersion) === CHANNEL_WORKSPACE_MIRROR_PROTOCOL_VERSION, "Workspace mirror delta protocolVersion mismatch.");
  expect(Number(delta.chainId) === Number(chainId), "Workspace mirror delta chainId mismatch.");
  expect(ethers.toBigInt(delta.channelId) === ethers.toBigInt(channelId), "Workspace mirror delta channelId mismatch.");
  const fromBlock = Number(localRecoveryIndex.nextBlock);
  const toBlock = Number(manifest.checkpoint.recoveryLastScannedBlock) - 1;
  expect(Number(delta.fromBlock) === fromBlock, "Workspace mirror delta fromBlock mismatch.");
  expect(Number(delta.toBlock) === toBlock, "Workspace mirror delta toBlock mismatch.");
  expect(
    ethers.toBigInt(normalizeBytes32Hex(delta.baseRecoveryRootVectorHash))
      === ethers.toBigInt(normalizeBytes32Hex(localRecoveryIndex.recoveryRootVectorHash)),
    "Workspace mirror delta base root mismatch.",
  );
  expect(
    ethers.toBigInt(normalizeBytes32Hex(delta.recoveryRootVectorHash))
      === ethers.toBigInt(normalizeBytes32Hex(manifest.checkpoint.recoveryRootVectorHash)),
    "Workspace mirror delta recovery root mismatch.",
  );
  const groupedValues = normalizeWorkspaceMirrorDeltaEventGroups({
    logs: delta.logs,
    channelInfo,
    bridgeAbiManifest,
    fromBlock,
    toBlock,
  });
  const currentSnapshot = await applyChannelRecoveryEventGroups({
    startingSnapshot: localRecoveryIndex.stateSnapshot,
    groupedValues,
    contractCodes,
    channelInfo,
    controllerAddress,
    l2AccountingVaultAddress,
    liquidBalancesSlot,
  });
  const recoveryRootVectorHash = normalizeBytes32Hex(hashRootVector(currentSnapshot.stateRoots));
  expect(
    ethers.toBigInt(recoveryRootVectorHash) === ethers.toBigInt(normalizeBytes32Hex(manifest.checkpoint.recoveryRootVectorHash)),
    "Workspace mirror delta result root does not match the manifest checkpoint root.",
  );
  expect(
    Array.isArray(currentSnapshot.storageAddresses)
      && currentSnapshot.storageAddresses.length === managedStorageAddresses.length
      && currentSnapshot.storageAddresses.every(
        (address, index) => ethers.toBigInt(getAddress(address)) === ethers.toBigInt(getAddress(managedStorageAddresses[index])),
      ),
    "Workspace mirror delta result storage address vector mismatch.",
  );
  return {
    nextBlock: Number(manifest.checkpoint.recoveryLastScannedBlock),
    stateSnapshot: currentSnapshot,
    recoveryRootVectorHash,
    source: "mirror",
  };
}

function normalizeWorkspaceMirrorDeltaEventGroups({
  logs,
  channelInfo,
  bridgeAbiManifest,
  fromBlock,
  toBlock,
}) {
  expect(Array.isArray(logs), "Workspace mirror delta logs must be an array.");
  const channelManager = new Contract(
    channelInfo.manager,
    bridgeAbiManifest.contracts.channelManager.abi,
  );
  const bridgeTokenVault = new Contract(
    channelInfo.bridgeTokenVault,
    bridgeAbiManifest.contracts.bridgeTokenVault.abi,
  );
  const currentRootVectorObservedTopic =
    normalizeBytes32Hex(channelManager.interface.getEvent("CurrentRootVectorObserved").topicHash);
  const groupedEvents = new Map();
  for (const rawLog of logs) {
    const event = normalizeWorkspaceMirrorDeltaLog({
      rawLog,
      channelInfo,
      channelManager,
      bridgeTokenVault,
      currentRootVectorObservedTopic,
      fromBlock,
      toBlock,
    });
    const group = groupedEvents.get(event.transactionHash) ?? [];
    group.push(event);
    groupedEvents.set(event.transactionHash, group);
  }
  return [...groupedEvents.values()].sort((left, right) => compareLogsByPosition(left[0], right[0]));
}

function normalizeWorkspaceMirrorDeltaLog({
  rawLog,
  channelInfo,
  channelManager,
  bridgeTokenVault,
  currentRootVectorObservedTopic,
  fromBlock,
  toBlock,
}) {
  const event = {
    ...rawLog,
    address: getAddress(rawLog.address),
    topics: (rawLog.topics ?? []).map((topic) => normalizeBytes32Hex(topic)),
    data: rawLog.data ?? "0x",
    blockNumber: Number(rawLog.blockNumber),
    transactionHash: normalizeBytes32Hex(rawLog.transactionHash),
    transactionIndex: Number(rawLog.transactionIndex),
    index: Number(rawLog.index ?? rawLog.logIndex),
  };
  expect(event.blockNumber >= fromBlock && event.blockNumber <= toBlock, "Workspace mirror delta log block is outside the declared range.");
  expect(Number.isInteger(event.transactionIndex) && Number.isInteger(event.index), "Workspace mirror delta log is missing transactionIndex or index.");
  const topic0 = event.topics[0] ? normalizeBytes32Hex(event.topics[0]) : null;
  if (ethers.toBigInt(event.address) === ethers.toBigInt(getAddress(channelInfo.manager))) {
    if (topic0 === currentRootVectorObservedTopic) {
      const parsed = channelManager.interface.parseLog(event);
      return {
        ...event,
        args: parsed.args,
        fragment: parsed.fragment,
      };
    }
    expect(
      topic0 === normalizeBytes32Hex(CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC)
        || topic0 === normalizeBytes32Hex(VAULT_STORAGE_WRITE_OBSERVED_TOPIC),
      "Workspace mirror delta contains unsupported channel manager log topic.",
    );
    return event;
  }
  expect(
    ethers.toBigInt(event.address) === ethers.toBigInt(getAddress(channelInfo.bridgeTokenVault)),
    "Workspace mirror delta contains a log from an unsupported address.",
  );
  const parsed = bridgeTokenVault.interface.parseLog(event);
  expect(parsed.fragment?.name === "StorageWriteObserved", "Workspace mirror delta contains unsupported bridge vault log.");
  return {
    ...event,
    args: parsed.args,
    fragment: parsed.fragment,
  };
}

function compareLogsByPosition(left, right) {
  if (left.blockNumber !== right.blockNumber) {
    return Number(left.blockNumber - right.blockNumber);
  }
  if (left.transactionIndex !== right.transactionIndex) {
    return Number(left.transactionIndex - right.transactionIndex);
  }
  return Number(left.index - right.index);
}

async function fetchLogsChunked(provider, {
  address,
  topics,
  fromBlock,
  toBlock,
  collectLogs = true,
  onProgress = null,
  onChunk = null,
}) {
  const rpcLogConfig = requireActiveRpcLogConfig();
  const normalizedFromBlock = Number(fromBlock);
  const resolvedToBlock = toBlock === "latest" ? await fetchFreshBlockNumber(provider) : Number(toBlock);
  const aggregatedLogs = [];
  let logsFound = 0;

  if (normalizedFromBlock > resolvedToBlock) {
    onProgress?.({
      status: "skipped",
      fromBlock: normalizedFromBlock,
      toBlock: resolvedToBlock,
      scannedBlocks: 0,
      totalBlocks: 0,
      logsFound: 0,
    });
    return aggregatedLogs;
  }

  const totalBlocks = resolvedToBlock - normalizedFromBlock + 1;
  onProgress?.({
    status: "start",
    fromBlock: normalizedFromBlock,
    toBlock: resolvedToBlock,
    scannedBlocks: 0,
    totalBlocks,
    logsFound: 0,
  });

  const chunkSize = rpcLogConfig.logChunkSize;
  let cursor = normalizedFromBlock;
  while (cursor <= resolvedToBlock) {
    const chunkToBlock = Math.min(resolvedToBlock, cursor + chunkSize - 1);
    let logs;
    const request = {
      address,
      topics,
      fromBlock: cursor,
      toBlock: chunkToBlock,
    };
    try {
      logs = await fetchLogsRateLimited(provider, request);
    } catch (error) {
      throw buildRpcLogQueryConfigError({
        error,
        fromBlock: cursor,
        toBlock: chunkToBlock,
        rpcLogConfig,
      });
    }
    logsFound += logs.length;
    if (collectLogs) {
      aggregatedLogs.push(...logs);
    }
    onProgress?.({
      status: "progress",
      fromBlock: normalizedFromBlock,
      toBlock: resolvedToBlock,
      chunkFromBlock: cursor,
      chunkToBlock,
      scannedBlocks: chunkToBlock - normalizedFromBlock + 1,
      totalBlocks,
      logsFound,
      chunkLogs: logs.length,
    });
    await onChunk?.({
      status: "progress",
      fromBlock: normalizedFromBlock,
      toBlock: resolvedToBlock,
      chunkFromBlock: cursor,
      chunkToBlock,
      scannedBlocks: chunkToBlock - normalizedFromBlock + 1,
      totalBlocks,
      logsFound,
      chunkLogs: logs.length,
      request,
      logs,
    });
    cursor = chunkToBlock + 1;
  }

  onProgress?.({
    status: "done",
    fromBlock: normalizedFromBlock,
    toBlock: resolvedToBlock,
    scannedBlocks: totalBlocks,
    totalBlocks,
    logsFound,
  });

  return aggregatedLogs;
}

async function fetchFreshBlockNumber(provider) {
  expect(typeof provider?.send === "function", "Provider does not support fresh eth_blockNumber RPC calls.");
  return Number(ethers.toBigInt(await provider.send("eth_blockNumber", [])));
}

async function waitForProviderBlockAtLeast(provider, targetBlock, {
  action = "transaction",
  timeoutMs = 60_000,
  pollIntervalMs = 1_000,
} = {}) {
  const normalizedTargetBlock = Number(targetBlock);
  expect(Number.isInteger(normalizedTargetBlock) && normalizedTargetBlock >= 0, "Invalid receipt block number.");
  const startedAt = Date.now();
  while (true) {
    const latestBlock = await fetchFreshBlockNumber(provider);
    if (latestBlock >= normalizedTargetBlock) {
      return latestBlock;
    }
    if (Date.now() - startedAt >= timeoutMs) {
      throw new Error([
        `RPC provider did not report block ${normalizedTargetBlock} after ${action}.`,
        `Latest reported block is ${latestBlock}.`,
        "Retry the command after the RPC provider catches up, or run channel recover-workspace and wallet recover-workspace manually.",
      ].join(" "));
    }
    await sleep(pollIntervalMs);
  }
}

function recoveryBlockDelta({ fromBlock, toBlock }) {
  const normalizedFromBlock = Number(fromBlock);
  const normalizedToBlock = Number(toBlock);
  if (!Number.isInteger(normalizedFromBlock) || !Number.isInteger(normalizedToBlock)) {
    return Number.POSITIVE_INFINITY;
  }
  if (normalizedFromBlock > normalizedToBlock) {
    return 0;
  }
  return normalizedToBlock - normalizedFromBlock + 1;
}

function assertAutoRecoveryBlockBudget({
  label,
  fromBlock,
  toBlock,
  recoveryCommand,
  blockBudget = AUTO_RECOVERY_BLOCK_BUDGET,
}) {
  const blockDelta = recoveryBlockDelta({ fromBlock, toBlock });
  const normalizedBudget = Math.max(0, Number(blockBudget));
  if (blockDelta <= normalizedBudget) {
    return blockDelta;
  }
  const normalizedFromBlock = Number(fromBlock);
  const normalizedToBlock = Number(toBlock);
  throw new Error([
    `Automatic recovery for ${label} would exceed the ${AUTO_RECOVERY_BLOCK_BUDGET}-block pre-command budget.`,
    `Recovery delta is ${blockDelta} blocks from ${normalizedFromBlock} to ${normalizedToBlock}.`,
    `Remaining automatic recovery budget is ${normalizedBudget} blocks.`,
    `Run ${recoveryCommand} first.`,
  ].join(" "));
}

async function fetchLogsRateLimited(provider, request) {
  const rpcLogConfig = requireActiveRpcLogConfig();
  let releaseQueue;
  const previousRequest = logRequestQueue;
  logRequestQueue = new Promise((resolve) => {
    releaseQueue = resolve;
  });
  await previousRequest;
  try {
    const elapsedMs = Date.now() - lastLogRequestStartedAtMs;
    if (elapsedMs < rpcLogConfig.requestIntervalMs) {
      await sleep(rpcLogConfig.requestIntervalMs - elapsedMs);
    }
    lastLogRequestStartedAtMs = Date.now();
    return await provider.getLogs(request);
  } finally {
    releaseQueue();
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRateLimitError(error) {
  const serializedError = [
    error?.code,
    error?.status,
    error?.message,
    error?.shortMessage,
    error?.info?.responseStatus,
    error?.info?.responseBody,
  ].filter((value) => value !== undefined && value !== null).join("\n");

  return /\b429\b|too many requests|rate limit|compute units/i.test(serializedError);
}

function buildRpcLogQueryConfigError({ error, fromBlock, toBlock, rpcLogConfig }) {
  const reason = isRateLimitError(error)
    ? "The RPC provider reported a rate-limit error."
    : "The RPC provider rejected the configured eth_getLogs request.";
  return new Error([
    reason,
    `Configured LOG_CHUNK_SIZE=${rpcLogConfig.logChunkSize}, LOG_REQUESTS_PER_SECOND=${rpcLogConfig.logRequestsPerSecond}.`,
    `Failed block range: ${fromBlock}-${toBlock}.`,
    `Run private-state-cli set rpc --network ${rpcLogConfig.networkName} --rpc-url <URL> --provider <PROVIDER>,`,
    "or set explicit --log-requests-per-second and --block-range-cap values that match your RPC plan.",
    `RPC config file: ${rpcLogConfig.configPath}.`,
    `Original error: ${error?.shortMessage ?? error?.message ?? String(error)}`,
  ].join(" "), { cause: error });
}

const OUTPUT_BYTES32_SCALAR_KEYS = new Set([
  "aPubBlockHash",
  "blockHash",
  "bridgeCommitmentKey",
  "bridgeNullifierKey",
  "channelTokenVaultKey",
  "commitment",
  "currentRootVectorHash",
  "currentUserKey",
  "createdAtTxHash",
  "emittedRootVectorHash",
  "ephemeralPubKeyX",
  "hash",
  "labelHash",
  "l2StorageKey",
  "noteReceivePubKeyX",
  "nullifier",
  "prevRanDao",
  "previousRoot",
  "registeredL2StorageKey",
  "rootVectorHash",
  "salt",
  "sourceTxHash",
  "spentAtTxHash",
  "topic0",
  "transactionHash",
  "txHash",
  "updatedRoot",
  "updatedUserKey",
  "walletL2StorageKey",
]);

const OUTPUT_BYTES32_ARRAY_KEYS = new Set([
  "currentRootVector",
  "encryptedNoteValue",
  "prevBlockHashes",
  "stateRoots",
  "storageKeys",
  "storageTrieRoots",
  "topics",
  "updatedRoots",
]);

function normalizeCliOutput(value) {
  return normalizeCliOutputValue(value, []);
}

function normalizeCliOutputValue(value, pathParts) {
  if (shouldNormalizeOutputBytes32(pathParts, value)) {
    return normalizeBytes32Hex(value);
  }
  if (Array.isArray(value)) {
    return value.map((entry, index) => normalizeCliOutputValue(entry, [...pathParts, index]));
  }
  if (value && typeof value === "object" && !isByteArrayLike(value)) {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, normalizeCliOutputValue(entry, [...pathParts, key])]),
    );
  }
  return value;
}

function shouldNormalizeOutputBytes32(pathParts, value) {
  if (!isNormalizableBytesValue(value)) {
    return false;
  }
  const lastKey = lastStringPathPart(pathParts);
  if (lastKey && OUTPUT_BYTES32_SCALAR_KEYS.has(lastKey)) {
    return true;
  }
  if (lastKey === "x" && parentStringPathPart(pathParts) === "noteReceivePubKey") {
    return true;
  }
  return pathParts.some((part) => typeof part === "string" && OUTPUT_BYTES32_ARRAY_KEYS.has(part));
}

function lastStringPathPart(pathParts) {
  for (let index = pathParts.length - 1; index >= 0; index -= 1) {
    if (typeof pathParts[index] === "string") {
      return pathParts[index];
    }
  }
  return null;
}

function parentStringPathPart(pathParts) {
  let seenLastString = false;
  for (let index = pathParts.length - 1; index >= 0; index -= 1) {
    if (typeof pathParts[index] !== "string") {
      continue;
    }
    if (!seenLastString) {
      seenLastString = true;
      continue;
    }
    return pathParts[index];
  }
  return null;
}

function isNormalizableBytesValue(value) {
  return typeof value === "string" || isByteArrayLike(value);
}

function isByteArrayLike(value) {
  return value instanceof Uint8Array || Buffer.isBuffer(value);
}

function sanitizeReceipt(receipt) {
  return normalizeCliOutput(serializeBigInts({
    hash: receipt.hash,
    blockHash: receipt.blockHash,
    blockNumber: receipt.blockNumber,
    gasUsed: receipt.gasUsed,
    from: receipt.from,
    to: receipt.to,
    status: receipt.status,
    logs: receipt.logs,
  }));
}

function receiptGasUsed(receipt) {
  return ethers.toBigInt(receipt.gasUsed).toString();
}

function explorerTxUrl(network, txHash) {
  if (!network?.explorerTxBaseUrl || typeof txHash !== "string" || txHash.length === 0) {
    return null;
  }
  return `${network.explorerTxBaseUrl}/${txHash}`;
}

async function waitForReceipt(txResponse) {
  return txResponse.wait();
}

function networkNameFromChainId(chainId) {
  if (chainId === 1) return "mainnet";
  if (chainId === 11155111) return "sepolia";
  if (chainId === 31337) return "anvil";
  throw new Error(`Unsupported chain ID for private-state bridge CLI: ${chainId}`);
}

function findStorageSlot(storageLayoutManifest, contractName, label) {
  const contract = storageLayoutManifest.contracts[contractName];
  if (!contract) {
    throw new Error(
      `Missing ${contractName} storage layout. Available contracts: ${
        Object.keys(storageLayoutManifest.contracts ?? {}).join(", ") || "<none>"
      }.`,
    );
  }

  const entry = contract.storageLayout.storage.find((item) => item.label === label);
  if (!entry) {
    throw new Error(`Missing storage slot ${label} in ${contractName}.`);
  }
  return entry.slot;
}

function defaultBridgeDeploymentPath(chainId) {
  return requireFlatDeploymentArtifactPathsForChainId(chainId).bridgeDeploymentPath;
}

function requireLatestDappDeployArtifactPath(chainId, fileName) {
  const flatPaths = requireFlatDeploymentArtifactPathsForChainId(chainId);
  const filePath = path.join(flatPaths.rootDir, fileName);
  expect(fs.existsSync(filePath), `Missing DApp deployment artifact for chain ${chainId}: ${filePath}.`);
  return filePath;
}

function dappDeploymentManifestPath(chainId) {
  return requireFlatDeploymentArtifactPathsForChainId(chainId).dappDeploymentPath;
}

function dappStorageLayoutManifestPath(chainId) {
  return requireFlatDeploymentArtifactPathsForChainId(chainId).dappStorageLayoutPath;
}

function defaultBridgeAbiManifestPath(chainId) {
  return requireFlatDeploymentArtifactPathsForChainId(chainId).bridgeAbiManifestPath;
}

function loadBridgeAbiManifest(manifestPath) {
  const manifest = readJson(manifestPath);
  const requiredContracts = ["bridgeCore", "channelManager", "bridgeTokenVault", "erc20"];
  for (const contractName of requiredContracts) {
    if (!Array.isArray(manifest.contracts?.[contractName]?.abi)) {
      throw new Error(`Bridge ABI manifest is missing contracts.${contractName}.abi: ${manifestPath}`);
    }
  }
  return manifest;
}

function parseArgs(argv) {
  const parsed = { positional: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--help" || token === "-h") {
      parsed.help = true;
      continue;
    }
    if (token.startsWith("--")) {
      const [key, inlineValue] = token.slice(2).split("=", 2);
      const value = inlineValue ?? (argv[index + 1]?.startsWith("--") ? undefined : argv[++index]);
      parsed[toCamelCase(key)] = value ?? true;
      continue;
    }
    parsed.positional.push(token);
  }

  parsed.command = parsed.positional[0];
  if (
    (parsed.command === "account"
      || parsed.command === "channel"
      || parsed.command === "set"
      || parsed.command === "wallet"
      || parsed.command === "help")
    && parsed.positional[1]
  ) {
    parsed.command = `${parsed.command}-${parsed.positional[1]}`;
    if (
      parsed.positional[0] === "wallet"
      && (parsed.positional[1] === "export" || parsed.positional[1] === "import")
      && parsed.positional[2]
    ) {
      parsed.command = `${parsed.command}-${parsed.positional[2]}`;
    }
    parsed.positional = [parsed.command];
  }
  return parsed;
}

function configureOutput(args) {
  jsonOutputRequested = args.json === true;
}

function isJsonOutputRequested() {
  return jsonOutputRequested;
}

function toCamelCase(value) {
  return value.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
}

function toKebabCase(value) {
  return value.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
}

function parseTokenAmount(value, decimals) {
  try {
    return ethers.parseUnits(String(value), decimals);
  } catch {
    throw new Error(`Invalid token amount ${value} for asset decimals=${decimals}.`);
  }
}

function requireArg(value, label) {
  if (value === undefined || value === null || value === "") {
    throw new Error(`Missing ${label}.`);
  }
  return value;
}

function assertVersionArgs(args) {
  if (args.version !== true) {
    throw new Error("--version does not accept a value.");
  }
  if (args.command) {
    throw new Error("--version must be used without a command.");
  }
  const allowedKeys = new Set(["version", "json"]);
  const unknownKeys = Object.keys(args)
    .filter((key) => key !== "positional" && key !== "command" && !allowedKeys.has(key));
  if (unknownKeys.length > 0) {
    throw new Error(`Unsupported --version option(s): ${unknownKeys.map(toKebabCase).join(", ")}.`);
  }
}

function printVersion() {
  if (isJsonOutputRequested()) {
    printJson({
      action: "version",
      packageName: privateStateCliPackageJson.name,
      version: privateStateCliPackageJson.version,
    });
    return;
  }
  console.log(privateStateCliPackageJson.version);
}

function requireWorkspaceName(args) {
  const value = typeof args === "string" ? args : args.workspace;
  if (!value) {
    throw new Error("Missing --workspace.");
  }
  return String(value);
}

function requireWalletName(args) {
  const value = typeof args === "string" ? args : args.wallet;
  if (!value) {
    throw new Error("Missing --wallet.");
  }
  return String(value);
}

function requireNetworkName(args) {
  return String(requireArg(args.network, "--network"));
}

function requireAccountName(args) {
  return String(requireArg(args.account, "--account"));
}

function requireL1Signer(args, provider) {
  return new Wallet(resolvePrivateKeySource(args), provider);
}

function requireLeaderSigner(args, provider) {
  const networkName = requireNetworkName(args);
  const account = String(requireArg(args.leaderAccount, "--leader-account")).trim();
  expect(account.length > 0, "--leader-account requires a local account name.");
  return {
    signer: new Wallet(
      normalizePrivateKey(readSecretFile(accountPrivateKeyPath(networkName, account), "--leader-account")),
      provider,
    ),
    account,
  };
}

function resolveTxSubmitterSigner({ args, ownerSigner, provider }) {
  if (args.txSubmitter === undefined) {
    expect(
      typeof ownerSigner.privateKey === "string",
      [
        `Missing local account secret for wallet owner ${ownerSigner.address}.`,
        "Pass --tx-submitter <ACCOUNT> or import the matching local account secret.",
      ].join(" "),
    );
    return {
      txSubmitter: ownerSigner,
      source: "wallet-owner",
      account: null,
    };
  }
  if (args.txSubmitter === true || String(args.txSubmitter).trim() === "") {
    throw new Error("--tx-submitter requires a local account name.");
  }
  const networkName = requireNetworkName(args);
  const account = String(args.txSubmitter).trim();
  return {
    txSubmitter: new Wallet(
      normalizePrivateKey(readSecretFile(accountPrivateKeyPath(networkName, account), "--tx-submitter")),
      provider,
    ),
    source: "tx-submitter-account",
    account,
  };
}

function resolvePrivateKeySource(args) {
  const networkName = requireNetworkName(args);
  const account = requireAccountName(args);
  return normalizePrivateKey(readSecretFile(accountPrivateKeyPath(networkName, account), "--account"));
}

function resolveStandalonePrivateKeySource(args) {
  return normalizePrivateKey(readImportSecretSourceFile(
    requireArg(args.privateKeyFile, "--private-key-file"),
    "--private-key-file",
  ));
}

function prepareJoinWalletSecretForName({
  args,
  networkName,
  walletName,
}) {
  const { channelName } = parseWalletName(walletName);
  const walletRoot = walletRootPath(walletName, networkName);
  const walletIndex = fs.existsSync(walletRoot)
    ? requireWalletIndex({ walletRoot, walletName, networkName })
    : null;
  const activeEpoch = walletIndex ? activeWalletEpoch(walletIndex) : null;
  expect(
    !activeEpoch,
    [
      `Wallet ${walletName} already exists on ${networkName}.`,
      "channel join creates a new active wallet epoch.",
      "Use normal wallet commands for an existing active local wallet.",
      `For exited history, keep using wallet recover-workspace --channel-name ${channelName} --network ${networkName} --account ${args.account ?? "<ACCOUNT>"}.`,
    ].join(" "),
  );
  return readWalletSecretSourceFile(args);
}

function readWalletSecretSourceFile(args) {
  const sourcePath = path.resolve(String(requireArg(args.walletSecretPath, "--wallet-secret-path")));
  return readImportSecretSourceFile(sourcePath, "--wallet-secret-path");
}

function channelWorkspacePath(networkName, name) {
  return workspaceDirForName(workspaceRoot, networkName, name);
}

function walletRootPath(name, networkName) {
  const walletName = String(name);
  const { channelName } = parseWalletName(walletName);
  const normalizedNetworkName = requireNetworkName({ network: networkName });
  const workspaceDir = channelWorkspacePath(normalizedNetworkName, channelName);
  return walletDirForName(workspaceWalletsDir(workspaceDir), walletName);
}

function selectedWalletEpochDir(name, networkName) {
  const root = walletRootPath(name, networkName);
  const walletName = requireWalletName({ wallet: name });
  const normalizedNetworkName = requireNetworkName({ network: networkName });
  expect(
    fs.existsSync(root),
    cliError(CLI_ERROR_CODES.UNKNOWN_WALLET, `Unknown wallet: ${walletName} on ${normalizedNetworkName}.`),
  );
  const index = requireWalletIndex({ walletRoot: root, walletName, networkName: normalizedNetworkName });
  const selected = selectedWalletEpoch(index, walletName, normalizedNetworkName);
  return walletEpochPathFromRoot(root, selected.epochId);
}

function walletEpochPath(walletName, networkName, epochId) {
  return walletEpochPathFromRoot(walletRootPath(walletName, networkName), epochId);
}

function walletEpochPathFromRoot(walletRoot, epochId) {
  return path.join(walletRoot, "epochs", slugifyPathComponent(epochId));
}

function walletIndexMetadataPath(walletRoot) {
  return path.join(walletRoot, "wallet-index.metadata.json");
}

function readWalletIndexIfExists(walletRoot) {
  const indexPath = walletIndexMetadataPath(walletRoot);
  if (!fs.existsSync(indexPath)) {
    return null;
  }
  return normalizeWalletIndex(readJson(indexPath));
}

function requireWalletIndex({ walletRoot, walletName, networkName }) {
  const index = readWalletIndexIfExists(walletRoot);
  expect(index, currentWalletIndexRequiredMessage({ walletName, networkName, walletRoot }));
  return index;
}

function selectedWalletEpoch(index, walletName, networkName) {
  const selected = activeWalletEpoch(index) ?? latestWalletEpoch(index);
  expect(
    selected,
    `Wallet ${walletName} on ${networkName} has no epoch entries. Run wallet recover-workspace to rebuild the workspace in the current format.`,
  );
  return selected;
}

function currentWalletIndexRequiredMessage({ walletName, networkName, walletRoot }) {
  const channelName = parseWalletName(walletName).channelName;
  return [
    `Current wallet index is required for ${walletName} on ${networkName}: ${walletRoot}.`,
    `Run wallet recover-workspace --channel-name ${channelName} --network ${networkName} --account <ACCOUNT> to rebuild the workspace.`,
  ].join(" ");
}

function activeWalletEpoch(index) {
  const activeEpochId = index?.activeEpochId ?? null;
  return activeEpochId
    ? (index.epochs ?? []).find((epoch) => epoch.epochId === activeEpochId && epoch.lifecycleStatus === "active") ?? null
    : null;
}

function latestWalletEpoch(index) {
  const epochs = [...(index?.epochs ?? [])];
  epochs.sort((left, right) =>
    Number(right.joinedAtBlockNumber ?? 0) - Number(left.joinedAtBlockNumber ?? 0)
    || String(right.epochId).localeCompare(String(left.epochId)));
  return epochs[0] ?? null;
}

function normalizeWalletIndex(index) {
  expect(index?.format === WALLET_INDEX_FORMAT, "Invalid wallet index format.");
  expect(Number(index.formatVersion) === WALLET_INDEX_FORMAT_VERSION, "Unsupported wallet index format version.");
  expect(Array.isArray(index.epochs), "Wallet index is missing epochs[].");
  return {
    ...index,
    epochs: index.epochs.map((epoch) => ({
      ...epoch,
      epochId: String(epoch.epochId),
      lifecycleStatus: epoch.lifecycleStatus === "active" ? "active" : "exited",
    })),
  };
}

function accountPrivateKeyPath(networkName, accountName) {
  return path.join(
    secretRoot,
    requireNetworkName({ network: networkName }),
    "accounts",
    slugifyPathComponent(accountName),
    "private-key",
  );
}

function accountMetadataPath(networkName, accountName) {
  return path.join(
    secretRoot,
    requireNetworkName({ network: networkName }),
    "accounts",
    slugifyPathComponent(accountName),
    "account.json",
  );
}

function walletSecretPath(networkName, walletName) {
  return path.join(
    secretRoot,
    requireNetworkName({ network: networkName }),
    "wallets",
    slugifyPathComponent(walletName),
    "secret",
  );
}

function walletViewingKeySecretPath(networkName, walletName) {
  return walletKeySecretPath(networkName, walletName, "viewing");
}

function walletSpendingKeySecretPath(networkName, walletName) {
  return walletKeySecretPath(networkName, walletName, "spending");
}

function walletKeySecretPath(networkName, walletName, keyKind) {
  return path.join(
    secretRoot,
    requireNetworkName({ network: networkName }),
    "wallets",
    slugifyPathComponent(walletName),
    `${keyKind}.key`,
  );
}

function resolveWalletPathCandidates(walletName) {
  if (!fs.existsSync(workspaceRoot)) {
    return [];
  }

  const { channelName } = parseWalletName(walletName);
  const channelSlug = slugifyPathComponent(channelName);
  const walletSlug = slugifyPathComponent(walletName);
  const candidates = [];

  for (const entry of fs.readdirSync(workspaceRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) {
      continue;
    }
    const candidate = path.join(
      workspaceRoot,
      entry.name,
      channelSlug,
      "wallets",
      walletSlug,
    );
    if (fs.existsSync(candidate)) {
      requireWalletIndex({ walletRoot: candidate, walletName, networkName: entry.name });
      candidates.push(candidate);
    }
  }

  return candidates;
}

function listLocalWallets({ networkFilter = null, channelFilter = null } = {}) {
  if (!fs.existsSync(workspaceRoot)) {
    return [];
  }

  const wallets = [];
  for (const networkEntry of fs.readdirSync(workspaceRoot, { withFileTypes: true })) {
    if (!networkEntry.isDirectory() || (networkFilter && networkEntry.name !== slugifyPathComponent(networkFilter))) {
      continue;
    }
    const networkDir = path.join(workspaceRoot, networkEntry.name);
    for (const channelEntry of fs.readdirSync(networkDir, { withFileTypes: true })) {
      if (!channelEntry.isDirectory() || (channelFilter && channelEntry.name !== channelFilter)) {
        continue;
      }
      const walletsDir = path.join(networkDir, channelEntry.name, "wallets");
      if (!fs.existsSync(walletsDir)) {
        continue;
      }
      for (const walletEntry of fs.readdirSync(walletsDir, { withFileTypes: true })) {
        if (!walletEntry.isDirectory()) {
          continue;
        }
        const walletRoot = path.join(walletsDir, walletEntry.name);
        const walletIndex = requireWalletIndex({
          walletRoot,
          walletName: walletEntry.name,
          networkName: networkEntry.name,
        });
        const selectedEpoch = selectedWalletEpoch(walletIndex, walletEntry.name, networkEntry.name);
        const walletDir = walletEpochPathFromRoot(walletRoot, selectedEpoch.epochId);
        wallets.push({
          wallet: walletEntry.name,
          network: networkEntry.name,
          channelName: channelEntry.name,
          walletDir,
          walletRoot,
          activeEpochId: walletIndex?.activeEpochId ?? null,
          selectedEpochId: selectedEpoch?.epochId ?? null,
          lifecycleStatus: selectedEpoch.lifecycleStatus,
          epochs: walletIndex.epochs,
          metadataPath: walletNotesMetadataPath(walletDir),
          hasMetadata: fs.existsSync(walletNotesMetadataPath(walletDir)),
          hasEncryptedWallet: false,
          hasBackupMetadata: walletConfigExists(walletDir),
          hasViewingKey: fs.existsSync(walletViewingKeySecretPath(networkEntry.name, walletEntry.name)),
          hasSpendingKey: fs.existsSync(walletSpendingKeySecretPath(networkEntry.name, walletEntry.name)),
        });
      }
    }
  }
  return wallets.sort((left, right) =>
    [left.network, left.channelName, left.wallet].join("\0")
      .localeCompare([right.network, right.channelName, right.wallet].join("\0")),
  );
}

function privateStateCliDataRoot() {
  const root = path.dirname(workspaceRoot);
  expect(
    path.dirname(secretRoot) === root,
    `Unexpected CLI data root layout: ${workspaceRoot} and ${secretRoot} are not siblings.`,
  );
  return root;
}

function resolveExportWalletInfo({ networkName, walletName }) {
  resolveCliNetwork(networkName);
  const walletDir = selectedWalletEpochDir(walletName, networkName);
  return {
    wallet: walletName,
    network: networkName,
    channelName: parseWalletName(walletName).channelName,
    walletDir,
    metadataPath: walletNotesMetadataPath(walletDir),
    hasMetadata: fs.existsSync(walletNotesMetadataPath(walletDir)),
    hasEncryptedWallet: walletConfigExists(walletDir),
  };
}

function normalizeExportWalletInfo(walletInfo) {
  const wallet = requireWalletName({ wallet: walletInfo.wallet });
  const network = requireNetworkName({ network: walletInfo.network });
  const walletDir = walletInfo.walletDir ?? selectedWalletEpochDir(wallet, network);
  const metadataPath = walletNotesMetadataPath(walletDir);
  const metadata = readJsonIfExists(metadataPath);
  const channelName = metadata?.channelName ?? walletInfo.channelName ?? parseWalletName(wallet).channelName;

  expect(fs.existsSync(metadataPath), `Wallet export cannot find wallet metadata file: ${metadataPath}.`);
  expect(
    metadata.network === network,
    `Wallet export metadata network ${metadata.network} does not match ${network}.`,
  );
  expect(
    metadata.channelName === channelName,
    `Wallet export metadata channel ${metadata.channelName} does not match ${channelName}.`,
  );

  return {
    network,
    channelName,
    wallet,
    walletDir,
  };
}

function walletBackupExportFilePaths(walletInfo) {
  const walletFiles = [
    walletNotesMetadataPath(walletInfo.walletDir),
  ];
  const walletRoot = walletRootPath(walletInfo.wallet, walletInfo.network);
  requireWalletIndex({
    walletRoot,
    walletName: walletInfo.wallet,
    networkName: walletInfo.network,
  });
  walletFiles.push(walletIndexMetadataPath(walletRoot));
  for (const metadataPath of [
    walletViewingKeyMetadataPath(walletInfo.walletDir),
    walletSpendingKeyMetadataPath(walletInfo.walletDir),
  ]) {
    if (fs.existsSync(metadataPath)) {
      walletFiles.push(metadataPath);
    }
  }

  const workspaceDir = channelWorkspacePath(walletInfo.network, walletInfo.channelName);
  const currentDir = channelWorkspaceCurrentPath(workspaceDir);
  const workspaceFiles = [
    channelWorkspaceConfigPath(workspaceDir),
    path.join(currentDir, "state_snapshot.json"),
    path.join(currentDir, "state_snapshot.normalized.json"),
    path.join(currentDir, "block_info.json"),
    path.join(currentDir, "contract_codes.json"),
  ];
  for (const filePath of workspaceFiles) {
    expect(
      fs.existsSync(filePath),
      [
        `wallet export backup requires channel workspace cache file: ${filePath}.`,
        "Run channel recover-workspace first.",
      ].join(" "),
    );
  }
  return [...walletFiles, ...workspaceFiles];
}

function archivePathForLocalCliFile(filePath) {
  const root = privateStateCliDataRoot();
  const absolutePath = path.resolve(filePath);
  expectPathWithinRoot(absolutePath, root, `Cannot export file outside CLI data root: ${absolutePath}.`);
  return path.relative(root, absolutePath).split(path.sep).join("/");
}

function validateWalletExportManifest(manifest) {
  expect(manifest?.format === WALLET_BACKUP_EXPORT_FORMAT, "Wallet import ZIP has an unsupported format.");
  expect(
    Number(manifest.formatVersion) === WALLET_EXPORT_FORMAT_VERSION,
    `Wallet import ZIP format version ${manifest?.formatVersion} is not supported.`,
  );
  expect(Array.isArray(manifest.files), "Wallet import ZIP manifest is missing files[].");
  expect(Array.isArray(manifest.wallets), "Wallet import ZIP manifest is missing wallets[].");
  expect(manifest.wallets.length > 0, "Wallet import ZIP manifest does not list any wallets.");
  const uniqueFiles = new Set(manifest.files);
  expect(uniqueFiles.size === manifest.files.length, "Wallet import ZIP manifest contains duplicate file paths.");
  expect(manifest.files.length > 0, "Wallet import ZIP manifest does not list any files.");
  for (const filePath of manifest.files) {
    validateWalletArchivePath(filePath);
  }
  for (const wallet of manifest.wallets) {
    const networkName = requireNetworkName({ network: wallet.network });
    const walletName = requireWalletName({ wallet: wallet.wallet });
    requireArg(wallet.channelName, "wallets[].channelName");
    const walletRoot = walletRootPath(walletName, networkName);
    const expectedIndexPath = archivePathForLocalCliFile(walletIndexMetadataPath(walletRoot));
    expect(
      uniqueFiles.has(expectedIndexPath),
      [
        "Wallet import ZIP must include the current wallet index metadata.",
        "Run wallet recover-workspace with the current CLI, then export a new backup.",
      ].join(" "),
    );
  }
}

function validateWalletArchivePath(archivePath) {
  expect(typeof archivePath === "string" && archivePath.length > 0, "Wallet import ZIP contains an empty path.");
  expect(!archivePath.includes("\0"), `Wallet import ZIP contains an invalid path: ${archivePath}.`);
  expect(!archivePath.includes("\\"), `Wallet import ZIP path must use forward slashes: ${archivePath}.`);
  expect(!path.posix.isAbsolute(archivePath), `Wallet import ZIP path must be relative: ${archivePath}.`);
  expect(path.posix.normalize(archivePath) === archivePath, `Wallet import ZIP path is not normalized: ${archivePath}.`);
  expect(
    archivePath.startsWith("workspace/"),
    `Wallet backup import ZIP path must start with workspace/: ${archivePath}.`,
  );
}

function expectPathWithinRoot(targetPath, rootPath, message) {
  const relative = path.relative(path.resolve(rootPath), path.resolve(targetPath));
  expect(relative !== "" && !relative.startsWith("..") && !path.isAbsolute(relative), message);
}

function applyImportedWalletFileMode(archivePath, targetPath) {
  if (
    archivePath.endsWith("/wallet-notes.metadata.json")
    || archivePath.endsWith("/wallet-viewing-key.metadata.json")
    || archivePath.endsWith("/wallet-spending-key.metadata.json")
  ) {
    protectSecretFile(targetPath, `imported wallet file ${archivePath}`);
  }
}

function channelDataPath(workspaceDir) {
  return workspaceChannelDir(workspaceDir);
}

function channelWorkspaceConfigPath(workspaceDir) {
  return path.join(channelDataPath(workspaceDir), "workspace.json");
}

function channelWorkspaceCurrentPath(workspaceDir) {
  return path.join(channelDataPath(workspaceDir), "current");
}

function channelWorkspaceOperationsPath(workspaceDir) {
  return path.join(channelDataPath(workspaceDir), "operations");
}

function walletNotesMetadataPath(walletDir) {
  return path.join(walletDir, "wallet-notes.metadata.json");
}

function walletViewingKeyMetadataPath(walletDir) {
  return path.join(walletDir, "wallet-viewing-key.metadata.json");
}

function walletSpendingKeyMetadataPath(walletDir) {
  return path.join(walletDir, "wallet-spending-key.metadata.json");
}

function walletConfigExists(walletDir) {
  return fs.existsSync(walletNotesMetadataPath(walletDir));
}

const COMMAND_ARG_SCHEMAS = Object.freeze(
  Object.fromEntries(PRIVATE_STATE_CLI_COMMANDS.map((command) => [command.id, {
    label: privateStateCliCommandDisplay(command),
    keys: privateStateCliCommandOptionKeys(command),
    requiredKeys: privateStateCliCommandRequiredOptionKeys(command),
    usage: command.usage,
  }])),
);

function assertAllowedCommandSchema(args, schemaKey, { label } = {}) {
  const schema = COMMAND_ARG_SCHEMAS[schemaKey];
  if (!schema) {
    throw new Error(`Missing CLI command schema for ${schemaKey}.`);
  }
  assertAllowedCommandKeys(args, label ?? schema.label, new Set(schema.keys), schema.usage);
  for (const key of schema.requiredKeys) {
    const field = PRIVATE_STATE_CLI_FIELD_CATALOG[key];
    requireArg(args[key], field?.option ?? `--${toKebabCase(key)}`);
  }
}

function assertAllowedCommandKeys(args, commandName, allowedKeys, acceptedUsage) {
  const unsupported = Object.keys(args)
    .filter((key) => key !== "json" && !allowedKeys.has(key))
    .map((key) => `--${toKebabCase(key)}`);
  if (unsupported.length > 0) {
    throw new Error(
      `${commandName} only accepts ${acceptedUsage}. Unsupported option(s): ${unsupported.join(", ")}.`,
    );
  }
  assertBooleanFlag(args, "json", `${commandName} option --json`);
  expect(
    (args.positional ?? []).length === 1,
    `${commandName} does not accept positional arguments beyond the command name.`,
  );
}

function assertBooleanFlag(args, key, label) {
  if (args[key] !== undefined && args[key] !== true) {
    throw new Error(`${label} does not accept a value.`);
  }
}

function assertWalletChannelMoveArgs(args, commandName) {
  assertAllowedCommandSchema(args, commandName);
  assertActionImpactArg(args, COMMAND_ARG_SCHEMAS[commandName]?.label ?? commandName);
}

function assertInstallZkEvmArgs(args) {
  assertAllowedCommandSchema(args, "install");
  assertBooleanFlag(args, "readOnly", "install option --read-only");
  if (args.readOnly === true && args.docker !== undefined) {
    throw new Error("install --read-only does not accept --docker because proof runtimes are not installed.");
  }
  if (args.readOnly === true && args.groth16CliVersion !== undefined) {
    throw new Error("install --read-only does not accept --groth16-cli-version because Groth16 is not installed.");
  }
  if (args.readOnly === true && args.tokamakZkEvmCliVersion !== undefined) {
    throw new Error(
      "install --read-only does not accept --tokamak-zk-evm-cli-version because Tokamak zk-EVM is not installed.",
    );
  }
  if (args.groth16CliVersion !== undefined) {
    requireSemverVersion(args.groth16CliVersion, "--groth16-cli-version");
  }
  if (args.tokamakZkEvmCliVersion !== undefined) {
    requireSemverVersion(args.tokamakZkEvmCliVersion, "--tokamak-zk-evm-cli-version");
  }
}

function assertUninstallArgs(args) {
  assertAllowedCommandSchema(args, "uninstall");
}

function assertSetRpcArgs(args) {
  assertAllowedCommandSchema(args, "set-rpc");
  requireNetworkName(args);
  requireArg(args.rpcUrl, "--rpc-url");
  resolveRpcScanLimitsFromArgs(args);
}

function assertHelpCommandsArgs(args) {
  assertAllowedCommandSchema(args, "help-commands");
}

function assertUpdateArgs(args) {
  assertAllowedCommandSchema(args, "help-update");
}

function assertDoctorArgs(args) {
  assertAllowedCommandSchema(args, "help-doctor");
  assertBooleanFlag(args, "gpu", "help doctor option --gpu");
}

function assertGuideArgs(args) {
  if (args.network !== undefined) {
    requireNetworkName(args);
  }
  if (args.channelName !== undefined) {
    requireArg(args.channelName, "--channel-name");
  }
  if (args.account !== undefined) {
    requireAccountName(args);
  }
  if (args.wallet !== undefined) {
    requireWalletName(args);
  }
  assertAllowedCommandSchema(args, "help-guide");
}

function assertObserverArgs(args) {
  assertAllowedCommandSchema(args, "help-observer");
}

function assertTransactionFeesArgs(args) {
  assertAllowedCommandSchema(args, "help-transaction-fees");
}

function assertInvestigatorArgs(args) {
  assertAllowedCommandSchema(args, "investigator");
}

function assertAccountImportArgs(args) {
  assertAllowedCommandSchema(args, "account-import");
}

function assertMintNotesArgs(args) {
  assertAllowedCommandSchema(args, "wallet-mint-notes");
  assertActionImpactArg(args, "wallet mint-notes");
  assertTxSubmitterArg(args);
  parseAmountVector(args.amounts, {
    allowZeroEntries: true,
    requireAnyPositive: true,
  });
}

function assertRedeemNotesArgs(args) {
  assertAllowedCommandSchema(args, "wallet-redeem-notes");
  assertActionImpactArg(args, "wallet redeem-notes");
  assertTxSubmitterArg(args);
  selectRedeemNotesMethod(parseNoteIdVector(args.noteIds).length);
}

function assertTransferNotesArgs(args) {
  assertAllowedCommandSchema(args, "wallet-transfer-notes");
  assertActionImpactArg(args, "wallet transfer-notes");
  assertTxSubmitterArg(args);
  const noteIds = parseNoteIdVector(args.noteIds);
  const recipients = parseRecipientVector(args.recipients);
  const amounts = parseAmountVector(args.amounts);
  expect(
    recipients.length === amounts.length,
    "--amounts length must match --recipients length.",
  );
  selectTransferNotesMethod(noteIds.length, recipients.length);
}

function assertTxSubmitterArg(args) {
  if (args.txSubmitter === undefined) {
    return;
  }
  if (args.txSubmitter === true || String(args.txSubmitter).trim() === "") {
    throw new Error("--tx-submitter requires a local account name.");
  }
}

function assertActionImpactArg(args, commandName) {
  assertBooleanFlag(args, "acknowledgeActionImpact", `${commandName} option --acknowledge-action-impact`);
  if (args.acknowledgeActionImpact !== true && !process.stdin.isTTY) {
    throw new Error(`${commandName} requires --acknowledge-action-impact after reviewing the action-impact warning.`);
  }
}

function assertWalletGetNotesArgs(args) {
  assertAllowedCommandSchema(args, "wallet-get-notes");
  if (args.exportEvidence !== undefined) {
    requireArg(args.exportEvidence, "--export-evidence");
    if (args.acknowledgeFullNotePlaintextExport !== true) {
      throw new Error(
        "wallet get-notes --export-evidence requires --acknowledge-full-note-plaintext-export.",
      );
    }
  }
  assertBooleanFlag(
    args,
    "acknowledgeFullNotePlaintextExport",
    "wallet get-notes option --acknowledge-full-note-plaintext-export",
  );
}

function assertCreateChannelArgs(args) {
  assertAllowedCommandSchema(args, "channel-create");
}

function assertRecoverWorkspaceArgs(args) {
  assertAllowedCommandSchema(args, "channel-recover-workspace");
  const source = resolveWorkspaceRecoverySource(args);
  assertBooleanFlag(args, "fromGenesis", "channel recover-workspace option --from-genesis");
  assertBooleanFlag(args, "outputRaw", "channel recover-workspace option --output-raw");
  assertBooleanFlag(args, "publishWorkspaceMirror", "channel recover-workspace option --publish-workspace-mirror");
  assertBooleanFlag(args, "force", "channel recover-workspace option --force");
  if (args.outputRaw === true && source !== "rpc") {
    throw new Error("channel recover-workspace option --output-raw requires --source rpc.");
  }
  if (args.publishWorkspaceMirror === true) {
    requireArg(args.leaderAccount, "--leader-account");
    requireArg(args.output, "--output");
  } else {
    if (args.leaderAccount !== undefined) {
      throw new Error("channel recover-workspace option --leader-account requires --publish-workspace-mirror.");
    }
    if (args.output !== undefined) {
      throw new Error("channel recover-workspace option --output requires --publish-workspace-mirror.");
    }
    if (args.force !== undefined) {
      throw new Error("channel recover-workspace option --force requires --publish-workspace-mirror.");
    }
  }
}

function assertGetChannelArgs(args) {
  assertAllowedCommandSchema(args, "channel-get-meta");
}

function assertSetWorkspaceMirrorArgs(args) {
  assertAllowedCommandSchema(args, "channel-set-workspace-mirror");
  requireWorkspaceMirrorUrl(args.url);
}

function assertDepositBridgeArgs(args) {
  assertAllowedCommandSchema(args, "account-deposit-bridge");
  assertActionImpactArg(args, "account deposit-bridge");
}

function assertAccountGetBridgeFundArgs(args) {
  assertAllowedCommandSchema(args, "account-get-bridge-fund");
}

function assertRecoverWalletArgs(args) {
  assertAllowedCommandSchema(args, "wallet-recover-workspace");
  assertBooleanFlag(args, "fromGenesis", "wallet recover-workspace option --from-genesis");
}

function assertJoinChannelArgs(args) {
  assertAllowedCommandSchema(args, "channel-join");
  assertActionImpactArg(args, "channel join");
}

function assertWalletGetMetaArgs(args) {
  assertAllowedCommandSchema(args, "wallet-get-meta");
}

function assertAccountGetL1AddressArgs(args) {
  assertAllowedCommandSchema(args, "account-get-l1-address");
}

function assertListLocalWalletsArgs(args) {
  if (args.network !== undefined) {
    requireNetworkName(args);
  }
  if (args.channelName !== undefined) {
    requireArg(args.channelName, "--channel-name");
  }
  assertAllowedCommandSchema(args, "wallet-list");
}

function assertWalletExportBackupArgs(args) {
  assertAllowedCommandSchema(args, "wallet-export-backup");
  requireArg(args.output, "--output");
  requireNetworkName(args);
  requireWalletName(args);
}

function assertWalletExportKeyArgs(args, commandName) {
  assertAllowedCommandSchema(args, commandName);
  requireArg(args.output, "--output");
  requireNetworkName(args);
  requireWalletName(args);
}

function assertWalletImportBackupArgs(args) {
  assertAllowedCommandSchema(args, "wallet-import-backup");
}

function assertWalletImportKeyArgs(args, commandName) {
  assertAllowedCommandSchema(args, commandName);
}

function assertWithdrawBridgeArgs(args) {
  assertAllowedCommandSchema(args, "account-withdraw-bridge");
  assertActionImpactArg(args, "account withdraw-bridge");
}

function assertWalletGetChannelFundArgs(args) {
  assertAllowedCommandSchema(args, "wallet-get-channel-fund");
}

function assertExitChannelArgs(args) {
  assertAllowedCommandSchema(args, "channel-exit");
}

function createWalletOperationDir(walletName, networkName, suffix) {
  const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const operationDir = path.join(
    selectedWalletEpochDir(walletName, networkName),
    "operations",
    `${timestamp}-${slugifyPathComponent(suffix)}`,
  );
  ensureDir(operationDir);
  return operationDir;
}

function persistWallet(context) {
  writeJson(walletNotesMetadataPath(context.walletDir), sanitizeWalletForNotesMetadata(context.wallet));
  if (context.wallet?.l2PrivateKey || context.wallet?.l2PublicKey || context.wallet?.l2Address) {
    writeJson(walletSpendingKeyMetadataPath(context.walletDir), buildWalletSpendingKeyMetadata(context.wallet));
  }
  if (context.wallet?.noteReceivePubKeyX || context.wallet?.noteReceivePubKeyYParity !== undefined) {
    writeJson(walletViewingKeyMetadataPath(context.walletDir), buildWalletViewingKeyMetadata(context.wallet));
  }
}

function persistWalletKeys(context) {
  if (context.wallet?.l2PrivateKey) {
    writeSecretFile(
      walletSpendingKeySecretPath(context.wallet.network, context.walletName),
      JSON.stringify({
        format: WALLET_KEY_EXPORT_FORMAT,
        formatVersion: WALLET_EXPORT_FORMAT_VERSION,
        keyKind: "spending",
        metadata: buildWalletSpendingKeyMetadata(context.wallet),
        privateKey: normalizePrivateKey(context.wallet.l2PrivateKey),
      }, null, 2),
    );
  }
  if (context.wallet?.noteReceivePrivateKey) {
    writeSecretFile(
      walletViewingKeySecretPath(context.wallet.network, context.walletName),
      JSON.stringify({
        format: WALLET_KEY_EXPORT_FORMAT,
        formatVersion: WALLET_EXPORT_FORMAT_VERSION,
        keyKind: "viewing",
        metadata: buildWalletViewingKeyMetadata(context.wallet),
        privateKey: normalizePrivateKey(context.wallet.noteReceivePrivateKey),
      }, null, 2),
    );
  }
}

function persistWalletIndexForContext(context) {
  const walletRoot = walletRootPath(context.walletName, context.wallet.network);
  ensureDir(walletRoot);
  const currentIndex = readWalletIndexIfExists(walletRoot) ?? {
    format: WALLET_INDEX_FORMAT,
    formatVersion: WALLET_INDEX_FORMAT_VERSION,
    canonicalWalletName: context.walletName,
    network: context.wallet.network,
    channelName: context.wallet.channelName,
    channelId: context.wallet.channelId,
    l1Address: context.wallet.l1Address,
    activeEpochId: null,
    epochs: [],
  };
  const epoch = walletEpochSummaryFromWallet(context.wallet);
  const epochs = [
    ...currentIndex.epochs.filter((entry) => entry.epochId !== epoch.epochId),
    epoch,
  ].sort((left, right) =>
    Number(left.joinedAtBlockNumber ?? 0) - Number(right.joinedAtBlockNumber ?? 0)
    || String(left.epochId).localeCompare(String(right.epochId)));
  const activeEpoch = epochs.find((entry) => entry.lifecycleStatus === "active") ?? null;
  const nextIndex = {
    ...currentIndex,
    canonicalWalletName: context.walletName,
    network: context.wallet.network,
    channelName: context.wallet.channelName,
    channelId: context.wallet.channelId,
    l1Address: context.wallet.l1Address,
    activeEpochId: activeEpoch?.epochId ?? null,
    epochs,
  };
  writeJson(walletIndexMetadataPath(walletRoot), nextIndex);
}

async function markWalletEpochExited({ walletContext, receipt, provider }) {
  const block = receipt?.blockNumber === null || receipt?.blockNumber === undefined
    ? null
    : await provider.getBlock(receipt.blockNumber).catch(() => null);
  const exitedAtBlockTimestamp = block?.timestamp ?? null;
  walletContext.wallet.lifecycleStatus = "exited";
  walletContext.wallet.exitedAtTxHash = receipt?.hash ?? null;
  walletContext.wallet.exitedAtBlockNumber = receipt?.blockNumber ?? null;
  walletContext.wallet.exitedAtLogIndex = firstReceiptLogIndex(receipt);
  walletContext.wallet.exitedAtBlockTimestamp = exitedAtBlockTimestamp;
  walletContext.wallet.exitedAtBlockTimestampIso = exitedAtBlockTimestamp === null
    ? null
    : new Date(Number(exitedAtBlockTimestamp) * 1000).toISOString();
  persistWallet(walletContext);
  persistWalletIndexForContext(walletContext);
  return walletEpochSummaryFromWallet(walletContext.wallet);
}

function firstReceiptLogIndex(receipt) {
  const first = receipt?.logs?.[0] ?? null;
  return first?.index ?? first?.logIndex ?? null;
}

function walletEpochSummaryFromWallet(wallet) {
  const lifecycle = walletLifecycleMetadata(wallet);
  return {
    ...lifecycle,
    walletDirName: slugifyPathComponent(lifecycle.epochId),
    l2Address: wallet.l2Address,
    l2StorageKey: wallet.l2StorageKey,
    leafIndex: wallet.leafIndex,
  };
}

function sanitizeWalletForNotesMetadata(wallet) {
  const normalized = normalizeWallet({
    ...wallet,
    l2PrivateKey: null,
    noteReceivePrivateKey: null,
  });
  const { l2PrivateKey: _l2PrivateKey, noteReceivePrivateKey: _noteReceivePrivateKey, ...publicWallet } = normalized;
  return {
    ...publicWallet,
    notes: {
      unused: sanitizeTrackedNoteMap(normalized.notes.unused),
      spent: sanitizeTrackedNoteMap(normalized.notes.spent),
      unusedOrder: normalized.notes.unusedOrder,
      unusedBalance: null,
    },
  };
}

function sanitizeTrackedNoteMap(notes) {
  return Object.fromEntries(Object.entries(notes ?? {}).map(([key, note]) => [key, sanitizeTrackedNoteForPersistence(note)]));
}

function sanitizeTrackedNoteForPersistence(note) {
  const normalized = normalizeTrackedNote(note);
  return {
    commitment: normalized.commitment,
    nullifier: normalized.nullifier,
    encryptedNoteValue: normalized.encryptedNoteValue,
    status: normalized.status,
    sourceFunction: normalized.sourceFunction,
    sourceTxHash: normalized.sourceTxHash,
    createdAtTxHash: normalized.createdAtTxHash,
    createdAtBlockNumber: normalized.createdAtBlockNumber,
    createdAtLogIndex: normalized.createdAtLogIndex,
    createdByFunction: normalized.createdByFunction,
    createdOutputIndex: normalized.createdOutputIndex,
    spentAtTxHash: normalized.spentAtTxHash,
    spentAtBlockNumber: normalized.spentAtBlockNumber,
    spentAtLogIndex: normalized.spentAtLogIndex,
    spentByFunction: normalized.spentByFunction,
    spentInputIndex: normalized.spentInputIndex,
    counterpartyL2Address: normalized.counterpartyL2Address,
    counterpartyDirection: normalized.counterpartyDirection,
    counterpartyConfidence: normalized.counterpartyConfidence,
    bridgeCommitmentKey: normalized.bridgeCommitmentKey,
    bridgeNullifierKey: normalized.bridgeNullifierKey,
    commitmentObservedAtTxHash: normalized.commitmentObservedAtTxHash,
    commitmentObservedAtBlockNumber: normalized.commitmentObservedAtBlockNumber,
    commitmentObservedAtLogIndex: normalized.commitmentObservedAtLogIndex,
    nullifierObservedAtTxHash: normalized.nullifierObservedAtTxHash,
    nullifierObservedAtBlockNumber: normalized.nullifierObservedAtBlockNumber,
    nullifierObservedAtLogIndex: normalized.nullifierObservedAtLogIndex,
  };
}

function buildWalletSpendingKeyMetadata(wallet) {
  return normalizeCliOutput({
    walletFormatVersion: WALLET_WORKSPACE_FORMAT_VERSION,
    network: wallet.network,
    wallet: wallet.name,
    ...walletLifecycleMetadata(wallet),
    channelName: wallet.channelName,
    channelId: wallet.channelId,
    l1Address: wallet.l1Address,
    l2Address: wallet.l2Address,
    l2PublicKey: wallet.l2PublicKey,
    l2DerivationMode: wallet.l2DerivationMode,
    l2DerivationChannelName: wallet.l2DerivationChannelName,
    l2StorageKey: wallet.l2StorageKey,
    leafIndex: wallet.leafIndex,
  });
}

function buildWalletViewingKeyMetadata(wallet) {
  return normalizeCliOutput({
    walletFormatVersion: WALLET_WORKSPACE_FORMAT_VERSION,
    network: wallet.network,
    wallet: wallet.name,
    ...walletLifecycleMetadata(wallet),
    channelName: wallet.channelName,
    channelId: wallet.channelId,
    l1Address: wallet.l1Address,
    l2Address: wallet.l2Address,
    noteReceiveDerivationVersion: wallet.noteReceiveDerivationVersion,
    noteReceiveTypedDataMethod: wallet.noteReceiveTypedDataMethod,
    noteReceivePubKey: {
      x: wallet.noteReceivePubKeyX,
      yParity: wallet.noteReceivePubKeyYParity,
    },
  });
}

function printHelp() {
  const commandHelp = PRIVATE_STATE_CLI_COMMANDS.map((command) => [
    `  ${privateStateCliCommandSynopsis(command)}`,
    `      ${command.description}`,
    ...(command.help ?? []).map((line) => `      ${line}`),
  ].join("\n")).join("\n\n");
  console.log(`
Commands:
${commandHelp}

Secret source options:
  Use account import --private-key-file once to create a protected local account secret.
  L1 signing commands use --account only.
  A wallet secret source file is arbitrary high-entropy secret text read once by channel join.
  Create one before joining a channel, for example:
      openssl rand -hex 32 > ./wallet-secret.txt
      private-state-cli channel join --channel-name <NAME> --network <NAME> --account <NAME> --wallet-secret-path ./wallet-secret.txt --acknowledge-action-impact
  Configure each network RPC endpoint once with set rpc. The CLI reads RPC_URL, LOG_CHUNK_SIZE,
  and LOG_REQUESTS_PER_SECOND from ~/tokamak-private-channels/workspace/<network>/rpc-config.env.
  Wallet commands use separate protected viewing-key and spending-key files when those capabilities are needed.
  Source files passed to --private-key-file and --wallet-secret-path are not required to use 0600 permissions, but
  canonical CLI secret files remain protected. On macOS/Linux this means 0600; on Windows the CLI repairs ACLs when possible.

Options:
  --version
      Print the private-state CLI package version and exit.

  --json
      Print the command result as JSON. Without --json, commands print human-readable output.

  --help
      Show this help. Equivalent to help commands.
`);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJsonIfExists(filePath) {
  return fs.existsSync(filePath) ? readJson(filePath) : null;
}

function writeJson(filePath, value) {
  const normalizedValue = normalizeCliOutput(value);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(normalizedValue, null, 2)}\n`);
}

function writeJsonWithMode(filePath, value, mode) {
  writeJson(filePath, value);
  if (mode === 0o600) {
    protectSecretFile(filePath, "private JSON file");
  } else {
    fs.chmodSync(filePath, mode);
  }
}

function formatEnvValue(value) {
  if (/^[^\s#"'`$\\]+$/u.test(value)) {
    return value;
  }
  return JSON.stringify(value);
}

function resolveCommandRpcConfig(args) {
  const networkName = requireNetworkName(args);
  const rpcConfig = readRpcConfig(networkName);
  if (rpcConfig) {
    return rpcConfig;
  }
  throw cliError(
    CLI_ERROR_CODES.MISSING_RPC_URL,
    [
      `Missing RPC configuration for ${networkName}.`,
      `Run private-state-cli set rpc --network ${networkName} --rpc-url <URL> --provider <PROVIDER>,`,
      "or provide --log-requests-per-second and --block-range-cap explicitly.",
      `Expected config file: ${rpcConfigEnvPath(networkName)}.`,
    ].join(" "),
  );
}

function validateRpcUrl(value, label) {
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      throw new Error("unsupported protocol");
    }
  } catch {
    throw new Error(`${label} must be a valid http(s) RPC URL.`);
  }
}

function rpcConfigEnvPath(networkName) {
  return path.join(workspaceNetworkDir(workspaceRoot, requireNetworkName({ network: networkName })), "rpc-config.env");
}

function readRpcConfig(networkName) {
  const envPath = rpcConfigEnvPath(networkName);
  if (!fs.existsSync(envPath)) {
    return null;
  }
  const env = readPlainEnvFile(envPath);
  return normalizeRpcConfig({
    networkName,
    configPath: envPath,
    rpcUrl: env.RPC_URL,
    provider: env.RPC_PROVIDER,
    logRequestsPerSecond: env.LOG_REQUESTS_PER_SECOND,
    logChunkSize: env.LOG_CHUNK_SIZE ?? env.RPC_BLOCK_RANGE_CAP,
    blockRangeCap: env.RPC_BLOCK_RANGE_CAP ?? env.LOG_CHUNK_SIZE,
  });
}

function writeRpcConfig(networkName, updates) {
  const envPath = rpcConfigEnvPath(networkName);
  const next = normalizeRpcConfig({
    networkName,
    configPath: envPath,
    rpcUrl: updates.RPC_URL,
    provider: updates.RPC_PROVIDER,
    logRequestsPerSecond: updates.LOG_REQUESTS_PER_SECOND,
    logChunkSize: updates.LOG_CHUNK_SIZE,
    blockRangeCap: updates.RPC_BLOCK_RANGE_CAP,
  });
  const lines = [
    ["LOG_CHUNK_SIZE", next.logChunkSize],
    ["LOG_REQUESTS_PER_SECOND", next.logRequestsPerSecond],
    ["RPC_BLOCK_RANGE_CAP", next.blockRangeCap],
    ["RPC_PROVIDER", next.provider],
    ["RPC_URL", next.rpcUrl],
  ].map(([key, value]) => `${key}=${formatEnvValue(value)}`);
  ensureDir(path.dirname(envPath));
  fs.writeFileSync(envPath, `${lines.join("\n")}\n`, "utf8");
  return next;
}

function readPlainEnvFile(filePath) {
  const result = {};
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/u)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex <= 0) {
      continue;
    }
    const key = trimmed.slice(0, separatorIndex).trim();
    let value = trimmed.slice(separatorIndex + 1).trim();
    if (
      (value.startsWith("\"") && value.endsWith("\""))
      || (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    result[key] = value;
  }
  return result;
}

function normalizeRpcConfig({
  networkName,
  configPath,
  rpcUrl,
  provider,
  logRequestsPerSecond,
  logChunkSize,
  blockRangeCap,
}) {
  validateRpcUrl(String(rpcUrl ?? ""), `${configPath} RPC_URL`);
  const normalizedLogRequestsPerSecond = Number(logRequestsPerSecond);
  const normalizedLogChunkSize = Number(logChunkSize);
  const normalizedBlockRangeCap = Number(blockRangeCap);
  expect(
    Number.isFinite(normalizedLogRequestsPerSecond) && normalizedLogRequestsPerSecond > 0,
    `${configPath} LOG_REQUESTS_PER_SECOND must be a positive number.`,
  );
  expect(
    Number.isInteger(normalizedLogChunkSize) && normalizedLogChunkSize > 0,
    `${configPath} LOG_CHUNK_SIZE must be a positive integer.`,
  );
  expect(
    Number.isInteger(normalizedBlockRangeCap) && normalizedBlockRangeCap > 0,
    `${configPath} RPC_BLOCK_RANGE_CAP must be a positive integer.`,
  );
  expect(
    normalizedLogChunkSize === normalizedBlockRangeCap,
    `${configPath} LOG_CHUNK_SIZE must match RPC_BLOCK_RANGE_CAP.`,
  );
  return {
    networkName,
    configPath,
    rpcUrl: String(rpcUrl).trim(),
    provider: String(provider ?? "custom").trim() || "custom",
    logRequestsPerSecond: normalizedLogRequestsPerSecond,
    logChunkSize: normalizedLogChunkSize,
    blockRangeCap: normalizedBlockRangeCap,
    requestIntervalMs: Math.ceil(1000 / normalizedLogRequestsPerSecond),
  };
}

function resolveRpcScanLimitsFromArgs(args) {
  const providerInput = typeof args.provider === "string" ? args.provider.trim() : "";
  const hasProvider = providerInput.length > 0;
  const hasManualLimits = args.logRequestsPerSecond !== undefined || args.blockRangeCap !== undefined;
  expect(
    hasProvider !== hasManualLimits,
    "set rpc requires either --provider or both --log-requests-per-second and --block-range-cap.",
  );
  if (hasProvider) {
    if (args.provider === true) {
      throw new Error("--provider requires a provider name.");
    }
    const providerKey = normalizeRpcProviderKey(providerInput);
    const limits = RPC_PROVIDER_LOG_LIMITS[providerKey];
    expect(
      limits,
      `Unsupported RPC provider ${providerInput}. Supported providers: ${Object.keys(RPC_PROVIDER_LOG_LIMITS).join(", ")}.`,
    );
    return limits;
  }
  return {
    provider: "custom",
    logRequestsPerSecond: parsePositiveNumberOption(args.logRequestsPerSecond, "--log-requests-per-second"),
    blockRangeCap: parsePositiveIntegerOption(args.blockRangeCap, "--block-range-cap"),
  };
}

function normalizeRpcProviderKey(value) {
  const normalized = String(value).toLowerCase().replace(/[^a-z0-9]/gu, "");
  return RPC_PROVIDER_ALIASES[normalized] ?? normalized;
}

function parsePositiveNumberOption(value, label) {
  if (value === true || value === undefined) {
    throw new Error(`${label} requires a positive number.`);
  }
  const parsed = Number(value);
  expect(Number.isFinite(parsed) && parsed > 0, `${label} must be a positive number.`);
  return parsed;
}

function parsePositiveIntegerOption(value, label) {
  if (value === true || value === undefined) {
    throw new Error(`${label} requires a positive integer.`);
  }
  const parsed = Number(value);
  expect(Number.isInteger(parsed) && parsed > 0, `${label} must be a positive integer.`);
  return parsed;
}

function setActiveRpcLogConfig(rpcConfig) {
  activeRpcLogConfig = rpcConfig;
}

function requireActiveRpcLogConfig() {
  expect(
    activeRpcLogConfig,
    "RPC log scan configuration is missing. Run private-state-cli set rpc before commands that scan logs.",
  );
  return activeRpcLogConfig;
}

function readSecretFile(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
  assertSecretFilePermissions(filePath, label);
  return fs.readFileSync(filePath, "utf8").trim();
}

function readImportSecretSourceFile(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) {
    throw new Error(`${label} is not a regular file: ${filePath}`);
  }
  return fs.readFileSync(filePath, "utf8").trim();
}

function writeSecretFile(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true, mode: 0o700 });
  fs.writeFileSync(filePath, `${String(value).trim()}\n`, { mode: 0o600 });
  protectSecretFile(filePath, "canonical secret file");
}

function protectSecretFile(filePath, label) {
  if (process.platform === "win32") {
    repairWindowsSecretFileAcl(filePath);
  } else {
    fs.chmodSync(filePath, 0o600);
  }
  assertSecretFilePermissions(filePath, label);
}

function assertSecretFilePermissions(filePath, label) {
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) {
    throw new Error(`${label} is not a regular file: ${filePath}`);
  }
  if (process.platform === "win32") {
    assertWindowsSecretFilePermissions(filePath, label);
    return;
  }
  if ((stat.mode & 0o077) !== 0) {
    throw new Error(
      `${label} must not be group/world-readable or writable: ${filePath}. Run: chmod 600 ${filePath}`,
    );
  }
}

function repairWindowsSecretFileAcl(filePath) {
  const userName = process.env.USERNAME?.trim() || os.userInfo().username;
  const commands = [
    ["icacls", [filePath, "/inheritance:r"]],
    ["icacls", [filePath, "/grant:r", `${userName}:(R,W)`]],
    ["icacls", [
      filePath,
      "/remove:g",
      "Everyone",
      "Users",
      "Authenticated Users",
      "BUILTIN\\Users",
      "NT AUTHORITY\\Authenticated Users",
    ]],
  ];
  for (const [command, args] of commands) {
    const result = runCaptured(command, args);
    if (result.status !== 0) {
      throw new Error(
        `Unable to protect Windows secret file ACL: ${filePath}. ${stripAnsi(result.stderr || result.stdout).trim()}`,
      );
    }
  }
}

function assertWindowsSecretFilePermissions(filePath, label) {
  const result = runCaptured("icacls", [filePath]);
  if (result.status !== 0) {
    throw new Error(
      `Unable to inspect Windows ACL for ${label}: ${filePath}. ${stripAnsi(result.stderr || result.stdout).trim()}`,
    );
  }
  const output = stripAnsi(`${result.stdout}\n${result.stderr}`);
  const broadReadPattern =
    /(?:^|\s)(?:Everyone|BUILTIN\\Users|NT AUTHORITY\\Authenticated Users|Authenticated Users|[^:\r\n\\]+\\Users):\(([^)\r\n]*(?:F|M|W|R|RX|GR|GW)[^)\r\n]*)\)/imu;
  if (broadReadPattern.test(output)) {
    throw new Error(
      `${label} must not grant broad Windows read/write access: ${filePath}. Re-import or let the CLI rewrite the canonical secret file.`,
    );
  }
}

function canonicalizeJsonValue(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalizeJsonValue);
  }
  if (value && typeof value === "object") {
    return Object.keys(value)
      .sort()
      .reduce((accumulator, key) => {
        accumulator[key] = canonicalizeJsonValue(value[key]);
        return accumulator;
      }, {});
  }
  return value;
}

function hashJsonValue(value) {
  return keccak256(
    ethers.toUtf8Bytes(
      JSON.stringify(canonicalizeJsonValue(serializeBigInts(normalizeCliOutput(value)))),
    ),
  );
}

function writeJsonIfChanged(filePath, value) {
  const normalizedValue = normalizeCliOutput(value);
  const nextHash = hashJsonValue(normalizedValue);
  if (fs.existsSync(filePath) && hashJsonValue(readJson(filePath)) === nextHash) {
    return false;
  }
  writeJson(filePath, normalizedValue);
  return true;
}

function loadExistingWorkspaceArtifacts(workspaceDir) {
  const currentDir = channelWorkspaceCurrentPath(workspaceDir);
  const stateSnapshot = readJsonIfExists(path.join(currentDir, "state_snapshot.json"));
  if (Array.isArray(stateSnapshot?.storageAddresses)) {
    stateSnapshot.storageAddresses = stateSnapshot.storageAddresses
      .map((address) => createAddressFromString(address).toString());
  }
  return {
    workspace: readJsonIfExists(channelWorkspaceConfigPath(workspaceDir)),
    stateSnapshot,
    blockInfo: readJsonIfExists(path.join(currentDir, "block_info.json")),
    contractCodes: readJsonIfExists(path.join(currentDir, "contract_codes.json")),
  };
}

function canReuseLocalWorkspaceSnapshot({ existingArtifacts, currentRootVectorHash, managedStorageAddresses }) {
  const localSnapshot = existingArtifacts?.stateSnapshot;
  if (!localSnapshot) {
    return false;
  }
  return ethers.toBigInt(normalizeBytes32Hex(hashRootVector(localSnapshot.stateRoots)))
    === ethers.toBigInt(normalizeBytes32Hex(currentRootVectorHash))
    && localSnapshot.storageAddresses.length === managedStorageAddresses.length
    && localSnapshot.storageAddresses.every(
      (address, index) => ethers.toBigInt(getAddress(address)) === ethers.toBigInt(getAddress(managedStorageAddresses[index])),
    );
}

function getUsableWorkspaceRecoveryIndex({
  existingArtifacts,
  genesisBlockNumber,
  latestBlock,
  managedStorageAddresses,
}) {
  const workspace = existingArtifacts?.workspace;
  const stateSnapshot = existingArtifacts?.stateSnapshot;
  if (!workspace || !stateSnapshot) {
    return null;
  }
  const nextBlock = Number(workspace.recoveryLastScannedBlock);
  if (typeof workspace.recoveryRootVectorHash !== "string") {
    return null;
  }
  const recoveryRootVectorHash = normalizeBytes32Hex(workspace.recoveryRootVectorHash);
  try {
    computeRecoveryCursorDelta({
      localNextBlock: nextBlock,
      targetNextBlock: Number(latestBlock) + 1,
      genesisBlockNumber,
      label: "Channel workspace",
    });
  } catch {
    return null;
  }
  if (recoveryRootVectorHash === null) {
    return null;
  }
  if (!Array.isArray(stateSnapshot.storageAddresses) || stateSnapshot.storageAddresses.length !== managedStorageAddresses.length) {
    return null;
  }
  const storageAddressesMatch = stateSnapshot.storageAddresses.every(
    (address, index) => ethers.toBigInt(getAddress(address)) === ethers.toBigInt(getAddress(managedStorageAddresses[index])),
  );
  if (!storageAddressesMatch) {
    return null;
  }
  const snapshotRootVectorHash = normalizeBytes32Hex(hashRootVector(stateSnapshot.stateRoots));
  if (ethers.toBigInt(snapshotRootVectorHash) !== ethers.toBigInt(recoveryRootVectorHash)) {
    return null;
  }
  return {
    nextBlock,
    stateSnapshot,
    recoveryRootVectorHash,
  };
}

function writeEncryptedWalletFile(filePath, plaintextBytes, walletSecret) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const salt = randomBytes(16);
  const encryptionKey = deriveWalletEncryptionKey(walletSecret, salt);
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintextBytes), cipher.final()]);
  const tag = cipher.getAuthTag();
  const envelope = {
    version: WALLET_ENCRYPTION_VERSION,
    algorithm: WALLET_ENCRYPTION_ALGORITHM,
    kdf: "scrypt",
    salt: normalizeBytesHex(salt, 16),
    iv: normalizeBytes12Hex(iv),
    tag: normalizeBytesHex(tag, 16),
    ciphertext: ethers.hexlify(ciphertext),
  };
  fs.writeFileSync(filePath, `${JSON.stringify(envelope, null, 2)}\n`);
}

function deriveWalletEncryptionKey(walletSecret, salt) {
  return scryptSync(String(walletSecret), salt, 32);
}

function sealWalletOperationDir(operationDir, walletSecret) {
  for (const entry of fs.readdirSync(operationDir, { withFileTypes: true })) {
    const targetPath = path.join(operationDir, entry.name);
    if (entry.isDirectory()) {
      sealWalletOperationDir(targetPath, walletSecret);
      continue;
    }
    const plaintextBytes = fs.readFileSync(targetPath);
    writeEncryptedWalletFile(targetPath, plaintextBytes, walletSecret);
  }
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function loadExplicitCommandRuntime(args, { staticNetwork = false, prepareArtifacts = false } = {}) {
  const networkName = requireNetworkName(args);
  const network = {
    ...resolveCliNetwork(networkName),
    name: networkName,
  };
  const rpcConfig = resolveCommandRpcConfig(args);
  setActiveRpcLogConfig(rpcConfig);
  const provider = staticNetwork
    ? new JsonRpcProvider(rpcConfig.rpcUrl, Number(network.chainId), { staticNetwork: true })
    : new JsonRpcProvider(rpcConfig.rpcUrl);
  if (prepareArtifacts) prepareDeploymentArtifactsForCommand(args.command, network.chainId);
  return {
    network,
    rpcUrl: rpcConfig.rpcUrl,
    rpcConfig,
    provider,
  };
}

async function assertProviderChainIdMatchesNetwork({ provider, network, rpcUrl }) {
  const remoteChainId = ethers.toBigInt(await provider.send("eth_chainId", []));
  const expectedChainId = ethers.toBigInt(network.chainId);
  expect(
    remoteChainId === expectedChainId,
    [
      `RPC URL ${redactRpcUrl(rpcUrl)} is connected to chainId ${remoteChainId.toString()},`,
      `but --network ${network.name} requires chainId ${expectedChainId.toString()}.`,
    ].join(" "),
  );
}

function loadWalletCommandRuntime(args, { prepareArtifacts = false } = {}) {
  const networkName = requireNetworkName(args);
  loadWalletMetadata(requireWalletName(args), networkName);
  const network = {
    ...resolveCliNetwork(networkName),
    name: networkName,
  };
  const rpcConfig = resolveCommandRpcConfig(args);
  setActiveRpcLogConfig(rpcConfig);
  if (prepareArtifacts) prepareDeploymentArtifactsForCommand(args.command, network.chainId);
  return {
    network,
    rpcConfig,
    provider: new JsonRpcProvider(rpcConfig.rpcUrl),
  };
}

const HUMAN_RESULT_RENDERERS = Object.freeze({
  guide: printGuideHumanResult,
  investigator: printInvestigatorHumanResult,
  observer: printObserverHumanResult,
  "transaction-fees": printTransactionFeesHumanResult,
  update: printUpdateHumanResult,
});

function normalizePrivateKey(value) {
  return value.startsWith("0x") ? value : `0x${value}`;
}

function printJson(value) {
  const normalized = normalizeCliOutput(value);
  if (isJsonOutputRequested()) {
    console.log(JSON.stringify(normalized, null, 2));
    return;
  }
  const renderer = HUMAN_RESULT_RENDERERS[normalized?.action];
  if (renderer) {
    renderer(normalized);
    return;
  }
  printHumanResult(normalized);
}

function printGuideHumanResult(guide) {
  const selectors = guide.selectors ?? {};
  const lines = [
    "Guide",
    `Generated: ${formatHumanValue(guide.generatedAt)}`,
    "",
    "Selectors",
    `Network: ${formatGuideSelector(selectors.network)}`,
    `Channel: ${formatGuideSelector(selectors.channelName)}`,
    `Account: ${formatGuideSelector(selectors.account)}`,
    `Wallet: ${formatGuideSelector(selectors.wallet)}`,
    "",
    "Checks",
    ...formatGuideChecks(guide.checks),
    "",
    "Next Safe Action",
    `Command: ${formatHumanValue(guide.nextSafeAction)}`,
    `Why: ${formatHumanValue(guide.why)}`,
  ];

  if (Array.isArray(guide.candidateCommands) && guide.candidateCommands.length > 0) {
    lines.push(
      "",
      "Candidate Commands",
      ...guide.candidateCommands.map((command) => `- ${command}`),
    );
  }

  lines.push("", "Run with --json to inspect the full guide state.");
  lines.push(
    "",
    "Privacy Tip",
    formatHumanValue(guide.privacyTip),
  );
  lines.push(
    "",
    "Mirror Tip",
    formatHumanValue(guide.mirrorTip),
  );
  console.log(lines.join("\n"));
}

function printInvestigatorHumanResult(result) {
  const lines = [
    "Private-State Evidence Investigator",
    `HTML path: ${formatHumanValue(result.htmlPath)}`,
    `File URL: ${formatHumanValue(result.fileUrl)}`,
    `Browser opened: ${result.browserOpened ? "yes" : "no"}`,
  ];
  if (!result.browserOpened) {
    lines.push(
      `Open command: ${formatHumanValue(result.browserOpenCommand)}`,
      `Open error: ${formatHumanValue(result.browserOpenError ?? "none")}`,
    );
  }
  if (Array.isArray(result.nextSteps) && result.nextSteps.length > 0) {
    lines.push(
      "",
      "Next Steps",
      ...result.nextSteps.map((step) => `- ${step}`),
    );
  }
  console.log(lines.join("\n"));
}

function printObserverHumanResult(result) {
  const lines = [
    "Private-State Public Observer",
    `URL: ${formatHumanValue(result.url)}`,
  ];
  if (result.scope) {
    lines.push(`Scope: ${formatHumanValue(result.scope)}`);
  }
  if (Array.isArray(result.notes) && result.notes.length > 0) {
    lines.push(
      "",
      "Notes",
      ...result.notes.map((note) => `- ${note}`),
    );
  }
  console.log(lines.join("\n"));
}

function printTransactionFeesHumanResult(report) {
  const lines = [
    "Transaction Fees",
    `Generated: ${formatHumanValue(report.generatedAt)}`,
    `Network: ${formatHumanValue(report.network)} (${formatHumanValue(report.chainId)})`,
    `Typical gas price: ${formatHumanValue(report.livePricing?.typicalGasPriceGwei)} gwei (${formatHumanValue(report.livePricing?.typicalGasPriceSource)})`,
    `Worst-case gas price: ${formatHumanValue(report.livePricing?.worstCaseGasPriceGwei)} gwei (${formatHumanValue(report.livePricing?.worstCaseGasPriceSource)})`,
    `ETH/USD: $${formatHumanValue(report.livePricing?.ethUsd)} (${formatHumanValue(report.livePricing?.ethUsdSource)})`,
    `Measured gas asset: ${formatHumanValue(report.asset?.schema)}, measured ${formatHumanValue(report.asset?.measuredAt)}`,
    "",
    formatHumanTable(
      ["Command", "Transactions", "Gas", "Typical ETH", "Typical USD", "Worst ETH", "Worst USD", "Source"],
      (report.rows ?? []).map((row) => [
        row.command,
        row.transactions,
        String(row.gasUsed),
        row.typicalEth,
        `$${row.typicalUsd}`,
        row.worstCaseEth,
        `$${row.worstCaseUsd}`,
        row.sources,
      ]),
    ),
  ];
  if (Array.isArray(report.asset?.notes) && report.asset.notes.length > 0) {
    lines.push(
      "",
      "Notes",
      ...report.asset.notes.map((note) => `- ${note}`),
    );
  }
  console.log(lines.join("\n"));
}

function printUpdateHumanResult(report) {
  const lines = [
    "Private-State CLI Update",
    `Package: ${formatHumanValue(report.packageName)}`,
    `Current version: ${formatHumanValue(report.currentVersion)}`,
    `Latest registry version: ${formatHumanValue(report.latestVersion)}`,
  ];
  if (report.registryState === "local-version-ahead-of-registry") {
    lines.push("Status: local version is newer than the npm registry latest tag.");
  } else if (!report.updateAvailable) {
    lines.push("Status: up to date.");
  } else if (report.updated) {
    lines.push("Status: updated global npm install.");
  } else {
    lines.push(
      "Status: update available.",
      `Reason: ${formatHumanValue(report.reason)}`,
      `Command: ${formatHumanValue(report.command)}`,
    );
  }
  lines.push(
    `Global install: ${report.globalPackage?.installed ? `yes (${formatHumanValue(report.globalPackage.version)})` : "no"}`,
    `Repository checkout: ${report.runningFromRepositoryCheckout ? "yes" : "no"}`,
    "",
    "Run with --json to inspect the full update report.",
  );
  console.log(lines.join("\n"));
}

function formatHumanTable(headers, rows) {
  const values = [headers, ...rows].map((row) => row.map((value) => String(value ?? "")));
  const widths = headers.map((_header, columnIndex) =>
    Math.max(...values.map((row) => row[columnIndex].length)),
  );
  const formatRow = (row) => `| ${row.map((value, index) => value.padEnd(widths[index])).join(" | ")} |`;
  return [
    formatRow(values[0]),
    formatRow(widths.map((width) => "-".repeat(width))),
    ...values.slice(1).map(formatRow),
  ].join("\n");
}

function formatGuideSelector(value) {
  return value === null || value === undefined || value === "" ? "not selected" : String(value);
}

function formatGuideChecks(checks) {
  if (!Array.isArray(checks) || checks.length === 0) {
    return ["none"];
  }
  return checks.map((check) => {
    const status = String(check.status ?? "unknown").toUpperCase().padEnd(7);
    const detail = formatGuideCheckDetail(check);
    return `- ${status} ${check.name ?? "unnamed check"}${detail ? ` - ${detail}` : ""}`;
  });
}

function formatGuideCheckDetail(check) {
  const parts = [];
  for (const key of ["network", "chainId", "channelName", "account", "wallet", "l1Address", "rpcSource"]) {
    if (check[key] !== null && check[key] !== undefined && check[key] !== "") {
      parts.push(`${humanizeLabel(key)}: ${formatHumanValue(check[key])}`);
    }
  }
  if (typeof check.localWorkspaceExists === "boolean") {
    parts.push(`Local workspace: ${check.localWorkspaceExists ? "yes" : "no"}`);
  }
  if (typeof check.onchainExists === "boolean") {
    parts.push(`On-chain: ${check.onchainExists ? "yes" : "no"}`);
  }
  if (Array.isArray(check.missingFiles) && check.missingFiles.length > 0) {
    parts.push(`Missing files: ${check.missingFiles.length}`);
  }
  if (check.error) {
    parts.push(`Error: ${check.error}`);
  }
  return parts.join("; ");
}

function printHumanResult(value) {
  const action = typeof value?.action === "string" && value.action.length > 0 ? value.action : "result";
  const entries = Object.entries(value ?? {}).filter(([key]) => key !== "action");
  const lines = [
    `${humanizeLabel(action)} result`,
    ...entries.map(([key, entry]) => `${humanizeLabel(key)}: ${formatHumanValue(entry)}`),
  ];
  console.log(lines.join("\n"));
}

function formatHumanValue(value) {
  if (value === null || value === undefined) {
    return "none";
  }
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  if (typeof value === "bigint") {
    return value.toString();
  }
  return JSON.stringify(value);
}

function humanizeLabel(value) {
  return String(value)
    .replace(/-/g, " ")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^./u, (letter) => letter.toUpperCase());
}

function emitProgress(action, phase) {
  const line = `[${action}] ${phase}`;
  if (isJsonOutputRequested()) {
    console.error(line);
  } else {
    console.log(line);
  }
}

function createByteDownloadProgress({ action, label, url }) {
  const startedAtMs = Date.now();
  const useInlineProgress = process.stderr.isTTY && !isJsonOutputRequested();
  let lastLineLength = 0;
  const writeInline = (line, done = false) => {
    if (!useInlineProgress) {
      if (done) {
        emitProgress(action, line);
      }
      return;
    }
    const paddedLine = line.padEnd(lastLineLength, " ");
    process.stderr.write(`\r[${action}] ${paddedLine}`);
    lastLineLength = line.length;
    if (done) {
      process.stderr.write("\n");
      lastLineLength = 0;
    }
  };
  return (event) => {
    const downloadedBytes = Number(event.downloadedBytes ?? 0);
    const totalBytes = Number.isFinite(Number(event.totalBytes)) ? Number(event.totalBytes) : null;
    const elapsedSeconds = Math.max(0.001, (Date.now() - startedAtMs) / 1000);
    const bytesPerSecond = downloadedBytes / elapsedSeconds;
    const remainingBytes = totalBytes !== null ? Math.max(0, totalBytes - downloadedBytes) : null;
    const etaSeconds = remainingBytes !== null && bytesPerSecond > 0
      ? remainingBytes / bytesPerSecond
      : null;
    const percent = totalBytes && totalBytes > 0
      ? `${Math.min(100, (downloadedBytes * 100) / totalBytes).toFixed(1)}%`
      : "unknown";
    const base = [
      `${label}: ${percent}`,
      `${formatByteCount(downloadedBytes)}/${totalBytes !== null ? formatByteCount(totalBytes) : "unknown"}`,
      `${formatByteRate(bytesPerSecond)}`,
      `ETA ${etaSeconds !== null ? formatDurationSeconds(etaSeconds) : "unknown"}`,
    ].join(" ");
    if (event.status === "start") {
      writeInline(`${base} from ${url}`);
      return;
    }
    if (event.status === "done") {
      writeInline(`${label}: 100% (${formatByteCount(downloadedBytes)}, done)`, true);
      return;
    }
    if (event.status === "error") {
      writeInline(`${label}: failed after ${formatByteCount(downloadedBytes)}`, true);
      return;
    }
    if (event.status === "progress") {
      writeInline(base);
    }
  };
}

function formatByteCount(bytes) {
  const value = Number(bytes);
  if (!Number.isFinite(value)) {
    return "unknown";
  }
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let scaled = Math.max(0, value);
  let unitIndex = 0;
  while (scaled >= 1024 && unitIndex < units.length - 1) {
    scaled /= 1024;
    unitIndex += 1;
  }
  const decimals = unitIndex === 0 ? 0 : 1;
  return `${scaled.toFixed(decimals)} ${units[unitIndex]}`;
}

function formatByteRate(bytesPerSecond) {
  return `${formatByteCount(bytesPerSecond)}/s`;
}

function formatDurationSeconds(seconds) {
  const value = Math.max(0, Number(seconds));
  if (!Number.isFinite(value)) {
    return "unknown";
  }
  if (value < 60) {
    return `${Math.ceil(value)}s`;
  }
  const minutes = Math.floor(value / 60);
  const remainingSeconds = Math.ceil(value % 60);
  return `${minutes}m ${remainingSeconds}s`;
}

function createRpcLogScanProgress({ action, label }) {
  let lastBucket = -1;
  return (event) => {
    const totalBlocks = Number(event.totalBlocks ?? 0);
    const scannedBlocks = Number(event.scannedBlocks ?? 0);
    const logsFound = Number(event.logsFound ?? 0);
    if (event.status === "skipped") {
      emitProgress(action, `rpc-log-scan ${label}: skipped (no blocks to scan, ${logsFound} logs)`);
      return;
    }
    if (event.status === "start") {
      lastBucket = 0;
      emitProgress(
        action,
        `rpc-log-scan ${label}: 0% (0/${totalBlocks} blocks, ${logsFound} logs, blocks ${event.fromBlock}-${event.toBlock})`,
      );
      return;
    }
    if (event.status === "done") {
      emitProgress(
        action,
        `rpc-log-scan ${label}: 100% (${totalBlocks}/${totalBlocks} blocks, ${logsFound} logs, done)`,
      );
      return;
    }
    if (event.status !== "progress" || totalBlocks <= 0) {
      return;
    }

    const percent = Math.min(100, Math.floor((scannedBlocks * 100) / totalBlocks));
    if (percent >= 100) {
      return;
    }
    const bucket = Math.floor(percent / 10) * 10;
    if (bucket <= lastBucket) {
      return;
    }
    lastBucket = bucket;
    emitProgress(
      action,
      `rpc-log-scan ${label}: ${percent}% (${scannedBlocks}/${totalBlocks} blocks, ${logsFound} logs)`,
    );
  };
}

function formatCliErrorForDisplay(error, args = {}) {
  const message = String(error?.message ?? error);
  const hints = buildRecoveryHints(error, args);
  if (hints.length === 0) {
    return message;
  }
  return [
    message,
    "",
    ...hints.map((hint) => `Try: ${hint}`),
  ].join("\n");
}

function buildRecoveryHints(error, args = {}) {
  const message = String(error?.message ?? error);
  const hints = [];
  const networkName = typeof args.network === "string" && args.network.length > 0
    ? args.network
    : "<NETWORK>";
  const channelName = typeof args.channelName === "string" && args.channelName.length > 0
    ? args.channelName
    : "<CHANNEL>";
  const accountName = typeof args.account === "string" && args.account.length > 0
    ? args.account
    : "<ACCOUNT>";
  const walletName = typeof args.wallet === "string" && args.wallet.length > 0
    ? args.wallet
    : extractUnknownWalletName(message) ?? "<WALLET>";

  if (
    error?.code === CLI_ERROR_CODES.MISSING_RPC_URL
    || message.includes("Missing RPC configuration")
    || message.includes("RPC log query")
  ) {
    hints.push(`private-state-cli set rpc --network ${networkName} --rpc-url <URL> --provider <PROVIDER>`);
  }

  if (
    error?.code === CLI_ERROR_CODES.UNKNOWN_WALLET
    || message.includes("Unable to derive the channel name from wallet")
    || message.includes("Missing --wallet")
    || message.includes("does not match the wallet channel")
    || message.includes("The provided wallet does not belong to the selected channel")
  ) {
    hints.push(`private-state-cli wallet list --network ${networkName}`);
    hints.push(`private-state-cli help guide --network ${networkName} --wallet ${walletName}`);
  }

  if (
    message.startsWith("Missing --account:")
    || message.includes("Missing --account.")
  ) {
    hints.push(`private-state-cli account import --account ${accountName} --network ${networkName} --private-key-file <PATH>`);
    hints.push(`private-state-cli help guide --network ${networkName} --account ${accountName}`);
  }

  if (
    error?.code === CLI_ERROR_CODES.MISSING_DEPLOYMENT_ARTIFACTS
    || message.includes("DApp deployment artifact")
  ) {
    hints.push("private-state-cli install");
    hints.push("private-state-cli help doctor --json");
  }

  if (error?.code === CLI_ERROR_CODES.MISSING_CHANNEL_REGISTRATION) {
    hints.push(`private-state-cli channel join --channel-name ${channelName} --network ${networkName} --account ${accountName} --wallet-secret-path <PATH> --acknowledge-action-impact`);
    hints.push(`private-state-cli help guide --network ${networkName} --channel-name ${channelName} --account ${accountName}`);
  }

  if (error?.code === CLI_ERROR_CODES.STALE_WORKSPACE) {
    hints.push(`private-state-cli channel recover-workspace --channel-name ${channelName} --network ${networkName}`);
    hints.push(`private-state-cli help guide --network ${networkName} --channel-name ${channelName}`);
  }

  if (message.includes("Workspace recovery index is missing or unusable")) {
    hints.push(`private-state-cli channel recover-workspace --channel-name ${channelName} --network ${networkName}`);
  }

  if (message.includes("Wallet note recovery index is missing or unusable")) {
    hints.push(`private-state-cli wallet recover-workspace --channel-name ${channelName} --network ${networkName} --account ${accountName} --from-genesis`);
  }

  if (message.includes("Missing channel selector")) {
    hints.push(`private-state-cli wallet list --network ${networkName}`);
    hints.push(`private-state-cli help guide --network ${networkName} --channel-name <CHANNEL> --wallet <WALLET>`);
  }

  return [...new Set(hints)];
}

function extractUnknownWalletName(message) {
  const match = /^Unknown wallet: ([^ ]+) on /u.exec(message);
  return match?.[1] ?? null;
}

function shortAddress(address) {
  return getAddress(address).slice(2, 10).toLowerCase();
}

function expect(condition, message) {
  if (!condition) {
    if (message instanceof Error) {
      throw message;
    }
    throw new Error(message);
  }
}

function requireSemverVersion(value, label) {
  return requireExactSemverVersion(value, label);
}

export {
  parseArgs,
  configureOutput,
  assertVersionArgs,
  printVersion,
  printHelp,
  assertHelpCommandsArgs,
  assertInstallZkEvmArgs,
  assertUninstallArgs,
  assertSetRpcArgs,
  assertUpdateArgs,
  assertDoctorArgs,
  assertGuideArgs,
  assertObserverArgs,
  assertTransactionFeesArgs,
  assertInvestigatorArgs,
  assertAccountGetL1AddressArgs,
  assertAccountImportArgs,
  assertListLocalWalletsArgs,
  assertWalletExportBackupArgs,
  assertWalletExportKeyArgs,
  assertWalletImportBackupArgs,
  assertWalletImportKeyArgs,
  assertMintNotesArgs,
  assertRedeemNotesArgs,
  assertWalletGetNotesArgs,
  assertTransferNotesArgs,
  assertWalletChannelMoveArgs,
  assertWalletGetMetaArgs,
  assertWalletGetChannelFundArgs,
  assertExitChannelArgs,
  assertCreateChannelArgs,
  assertRecoverWorkspaceArgs,
  assertGetChannelArgs,
  assertSetWorkspaceMirrorArgs,
  assertDepositBridgeArgs,
  assertWithdrawBridgeArgs,
  assertAccountGetBridgeFundArgs,
  assertRecoverWalletArgs,
  assertJoinChannelArgs,
  handleInstallZkEvm,
  handleUninstall,
  handleSetRpc,
  handleUpdate,
  handleDoctor,
  handleGuide,
  handleObserver,
  handleTransactionFees,
  handleInvestigator,
  handleAccountGetL1Address,
  handleAccountImport,
  handleListLocalWallets,
  handleWalletExportBackup,
  handleWalletExportKey,
  handleWalletImportBackup,
  handleWalletImportKey,
  handleMintNotes,
  handleRedeemNotes,
  handleWalletGetNotes,
  handleTransferNotes,
  handleGrothVaultMove,
  handleWalletGetMeta,
  handleWalletGetChannelFund,
  handleExitChannel,
  handleChannelCreate,
  handleWorkspaceInit,
  handleGetChannel,
  handleSetChannelWorkspaceMirror,
  handleDepositBridge,
  handleWithdrawBridge,
  handleAccountGetBridgeFund,
  handleRecoverWallet,
  handleJoinChannel,
  loadExplicitCommandRuntime,
  loadWalletCommandRuntime,
  assertProviderChainIdMatchesNetwork,
  formatCliErrorForDisplay,
};
