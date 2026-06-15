#!/usr/bin/env node

import fs from "node:fs";
import http from "node:http";
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
  readPrivateStateTermsText,
  readPrivateStateTermsMetadata,
} from "./private-state-terms.mjs";
import {
  buildEip712Payload,
  normalizeBrowserTransaction,
  personalSignPayload,
  safeJsonForScript,
} from "./private-state-browser-wallet-helpers.mjs";
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
  readPrivateStateCliTermsAcceptance,
  readTokamakCliPackageReport,
  requireActiveTokamakCliRuntimeRoot,
  resolveActiveGroth16ProverRuntime,
  resolveActiveTokamakCliInvocation,
  resolveArtifactCacheBaseRoot,
  resolvePrivateStateInstallRuntimeVersions,
  resolveTokamakCliCacheRoot,
  resolveTokamakCliResourceDirForRuntimeRoot,
  stripAnsi,
  writePrivateStateCliTermsAcceptance,
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
const PRIVATE_STATE_UNINSTALL_PRESERVE_KEYS_CONFIRMATION =
  "I understand that uninstall deletes local private-state data but preserves wallet keys";
const PRIVATE_STATE_UNINSTALL_INCLUDE_KEYS_CONFIRMATION =
  "I understand that uninstall will delete wallet keys and they cannot be recovered";
const PRIVATE_STATE_TERMS_ACCEPTANCE_CONFIRMATION =
  "I accept the Tonnel Service Terms";
const L1_SIGNER_MODES = Object.freeze({
  LOCAL_ACCOUNT: "local-account",
  BROWSER_WALLET: "browser-wallet",
});
const TX_SUBMITTER_SOURCES = Object.freeze({
  WALLET_OWNER: "wallet-owner",
  TX_SUBMITTER_ACCOUNT: "tx-submitter-account",
  BROWSER_WALLET: "browser-wallet",
  BROWSER_WALLET_OWNER: "browser-wallet-owner",
});
const PRIVATE_STATE_TERMS_ACCEPTANCE_CATEGORIES = Object.freeze([
  Object.freeze({
    id: "scope-and-eligibility",
    title: "Service scope, product boundary, acceptance, and eligibility",
    termsRefs: Object.freeze(["1", "2", "3"]),
  }),
  Object.freeze({
    id: "public-records-and-privacy-limits",
    title: "Public Ethereum mainnet records and private application-state limits",
    termsRefs: Object.freeze(["4", "5", "10"]),
  }),
  Object.freeze({
    id: "self-custody-and-secrets",
    title: "Self-custody, secrets, no recovery method, and user responsibilities",
    termsRefs: Object.freeze(["6", "8"]),
  }),
  Object.freeze({
    id: "prohibited-use-and-third-parties",
    title: "Prohibited use and Third-Party Services",
    termsRefs: Object.freeze(["7", "11", "12", "13"]),
  }),
  Object.freeze({
    id: "risks-and-liability",
    title: "Risk disclosures, no warranties, limitation of liability, and user indemnity",
    termsRefs: Object.freeze(["14", "15", "16", "17"]),
  }),
  Object.freeze({
    id: "changes-and-disputes",
    title: "Changes to Terms, Service changes, governing law, venue, and notices",
    termsRefs: Object.freeze(["18", "19", "20"]),
  }),
]);
const PRIVATE_STATE_CLI_PACKAGE_NAME = privateStateCliPackageJson.name;
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
const TERMS_GATED_COMMAND_IDS = Object.freeze(new Set([
  "uninstall",
  "secret-create-private-key-source",
  "secret-create-wallet-secret-source",
  "account-import",
  "account-deposit-bridge",
  "account-withdraw-bridge",
  "channel-create",
  "channel-set-workspace-mirror",
  "channel-abandon-operation",
  "channel-join",
  "channel-exit",
  "wallet-export-backup",
  "wallet-export-viewing-key",
  "wallet-export-spending-key",
  "wallet-import-backup",
  "wallet-import-viewing-key",
  "wallet-import-spending-key",
  "wallet-recover-workspace",
  "wallet-deposit-channel",
  "wallet-withdraw-channel",
  "wallet-mint-notes",
  "wallet-redeem-notes",
  "wallet-transfer-notes",
]));
let jsonOutputRequested = false;

const CLI_ERROR_CODES = Object.freeze({
  TERMS_ACCEPTANCE_REQUIRED: "TERMS_ACCEPTANCE_REQUIRED",
  MISSING_RPC_URL: "MISSING_RPC_URL",
  UNKNOWN_WALLET: "UNKNOWN_WALLET",
  MISSING_DEPLOYMENT_ARTIFACTS: "MISSING_DEPLOYMENT_ARTIFACTS",
  MISSING_CHANNEL_REGISTRATION: "MISSING_CHANNEL_REGISTRATION",
  UNKNOWN_CHANNEL: "UNKNOWN_CHANNEL",
  MISSING_CHANNEL_OBSERVER: "MISSING_CHANNEL_OBSERVER",
  CHANNEL_OPERATION_ABANDONED: "CHANNEL_OPERATION_ABANDONED",
  STALE_WORKSPACE: "STALE_WORKSPACE",
  STALE_CHANNEL_ROOT: "STALE_CHANNEL_ROOT",
  TX_DRY_RUN_FAILED: "TX_DRY_RUN_FAILED",
  TX_SUBMIT_FAILED: "TX_SUBMIT_FAILED",
});

class PrivateStateCliError extends Error {
  constructor(code, message, options = {}) {
    super(message, options);
    this.name = "PrivateStateCliError";
    this.code = code;
    if (options.details !== undefined) {
      this.details = options.details;
    }
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
  cliOutput.warning("channel-policy", details.join("\n"), {
    action,
    channelName,
    channelId: channelId.toString(),
    channelManager,
    policySnapshot,
  });
}

const COMMAND_WARNING_SUMMARIES = Object.freeze({
  "account-deposit-bridge": {
    display: "account deposit-bridge",
    l1PublicEvent: "Yes. ERC-20 approval and bridge vault funding transactions are public Ethereum mainnet events.",
    privateNoteState: "No. This action only moves canonical tokens into the shared bridge vault.",
    publicFields: ({ l1Address, amountInput, bridgeTokenVault }) => [
      `Ethereum account: ${l1Address}`,
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
    l1PublicEvent: "Yes. The bridge withdrawal transaction and claim event are public Ethereum mainnet data.",
    privateNoteState: "No. This action claims shared bridge-vault balance to the local Ethereum account.",
    publicFields: ({ l1Address, amountInput, bridgeTokenVault }) => [
      `Ethereum recipient/account: ${l1Address}`,
      `Bridge token vault: ${bridgeTokenVault}`,
      `Amount: ${amountInput}`,
      "Withdrawal transaction hash, block number, and event log.",
    ],
    notPublic: [
      "The private note path that produced any prior channel balance is not reconstructed from this event alone.",
    ],
    noteProvenance: "Public observers cannot reconstruct prior internal note provenance from this withdrawal alone.",
    exchangeControlledAddressWarning: "Do not use an exchange deposit address as the direct bridge withdrawal target unless the user has explicitly accepted the compliance implications. Prefer a self-custody Ethereum wallet.",
    policy: "No channel policy is accepted by this action.",
  },
  "channel-join": {
    display: "channel join",
    l1PublicEvent: "Yes. Channel join and token-vault registration transactions are public Ethereum mainnet data; any Join Toll is paid directly from the Ethereum wallet.",
    privateNoteState: "No. This action registers identity and note-receive metadata; it does not create or spend notes.",
    publicFields: ({ l1Address, l2Address, noteReceivePubKey, joinToll, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `Ethereum account: ${l1Address}`,
      `Channel-local address: ${l2Address}`,
      `Note-receive public key: ${noteReceivePubKey}`,
      `Join Toll: ${joinToll}`,
    ],
    notPublic: [
      "Wallet secret, spending private key, note-receive private key, and future note plaintext.",
    ],
    noteProvenance: "Future note provenance is not made public by joining.",
    policy: "Joining accepts the displayed immutable channel policy snapshot.",
  },
  "channel-exit": {
    display: "channel exit",
    l1PublicEvent: "Yes. The channel exit transaction, wallet registration exit status, and any Join Toll refund are public Ethereum mainnet data.",
    privateNoteState: "No new private notes are created or spent by this action. Locally, the current wallet epoch is marked as exited.",
    publicFields: ({ l1Address, l2Address, channelName, channelId, currentUserValue, refundAmount, refundBps }) => [
      `Channel: ${channelName} (${channelId})`,
      `Ethereum account: ${l1Address}`,
      `Registered channel-local address: ${l2Address}`,
      `Required current channel balance in base units: ${currentUserValue}`,
      `Quoted Join Toll refund: ${refundAmount}`,
      `Refund rate in basis points: ${refundBps}`,
      "Exit transaction hash, block number, event logs, and wallet registration exit status.",
    ],
    notPublic: [
      "Private note plaintext, historical note counterparties, and prior note provenance are not revealed by the exit transaction alone.",
    ],
    noteProvenance: "Public observers cannot reconstruct prior internal note provenance from this exit action alone.",
    policy: "This action uses the channel policy snapshot accepted by the registered wallet, including the Join Toll refund schedule.",
  },
  "wallet-deposit-channel": {
    display: "wallet deposit-channel",
    l1PublicEvent: "Yes. The proof-backed channel accounting transaction is public Ethereum mainnet data.",
    privateNoteState: "No. This action increases liquid channel accounting balance; it does not create notes.",
    publicFields: ({ l1Address, l2Address, amountInput, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `Ethereum submitter/account: ${l1Address}`,
      `Registered channel-local address: ${l2Address}`,
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
    l1PublicEvent: "Yes. The proof-backed channel accounting transaction is public Ethereum mainnet data.",
    privateNoteState: "No. This action decreases liquid channel accounting balance; it does not spend notes directly.",
    publicFields: ({ l1Address, l2Address, amountInput, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `Ethereum submitter/account: ${l1Address}`,
      `Registered channel-local address: ${l2Address}`,
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
    l1PublicEvent: "Yes. executeChannelTransaction, accepted transition, commitments, encrypted note events, and root updates are public Ethereum mainnet data.",
    privateNoteState: "Yes. This action creates private-state notes tracked by the local wallet.",
    publicFields: ({ l1Address, l2Address, amounts, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `Ethereum submitter/account: ${l1Address}`,
      `Registered channel-local address: ${l2Address}`,
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
    l1PublicEvent: "Yes. executeChannelTransaction, nullifiers, output commitments, encrypted note events, and root updates are public Ethereum mainnet data.",
    privateNoteState: "Yes. This action spends selected input notes and creates output notes.",
    publicFields: ({ l1Address, l2Address, noteIds, amounts, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `Ethereum submitter/account: ${l1Address}`,
      `Registered channel-local address: ${l2Address}`,
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
    l1PublicEvent: "Yes. executeChannelTransaction, nullifier usage, accounting update, and root updates are public Ethereum mainnet data.",
    privateNoteState: "Yes. This action consumes selected notes and credits liquid channel accounting balance.",
    publicFields: ({ l1Address, l2Address, noteIds, channelName, channelId }) => [
      `Channel: ${channelName} (${channelId})`,
      `Ethereum submitter/account: ${l1Address}`,
      `Registered channel-local address: ${l2Address}`,
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

async function printCommandWarningSummary(commandId, args, details = {}) {
  const summary = COMMAND_WARNING_SUMMARIES[commandId];
  if (!summary) {
    throw new Error(`Missing warning summary for ${commandId}.`);
  }
  void args;
  printWarningSummary(summary, details);
}

function printWarningSummary(summary, details) {
  const lines = [
    `WARNING SUMMARY: ${summary.display}`,
    `- Ethereum mainnet public event: ${summary.l1PublicEvent}`,
    `- Private note state change: ${summary.privateNoteState}`,
    "- Public addresses and amounts:",
    ...normalizeImpactLines(summary.publicFields, details).map((line) => `  - ${line}`),
    "- Not public by default:",
    ...normalizeImpactLines(summary.notPublic, details).map((line) => `  - ${line}`),
    `- Note provenance: ${summary.noteProvenance}`,
    `- Illegal-use prohibition: Do not use this command for money laundering, sanctions evasion, terrorist financing, illegal gambling, criminal-proceeds concealment, or regulatory evasion.`,
    `- Secret recovery: Losing wallet secrets, viewing keys, or spending keys can prevent note discovery or note use. If all required secret material and backups are lost, no recovery method exists.`,
    `- Channel policy: ${summary.policy}`,
    "- User confirmation: Read this warning yourself. User-Controlled AI Agents must not accept Terms or confirmations for you.",
  ];
  if (summary.exchangeControlledAddressWarning) {
    lines.push(`- Exchange-controlled address warning: ${summary.exchangeControlledAddressWarning}`);
  }
  cliOutput.warning("warning-summary", lines.join("\n"), {
    command: summary.display,
    l1PublicEvent: summary.l1PublicEvent,
    privateNoteState: summary.privateNoteState,
    publicFields: normalizeImpactLines(summary.publicFields, details),
    notPublic: normalizeImpactLines(summary.notPublic, details),
    noteProvenance: summary.noteProvenance,
    policy: summary.policy,
    exchangeControlledAddressWarning: summary.exchangeControlledAddressWarning ?? null,
  });
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
  const signer = await requireL1Signer(args, provider);
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
  const receipt = await dryRunThenSubmitTransaction({
    operationName: "channel create",
    call: contractTxCall(
      bridgeCore.createChannel,
      [channelId, dappId, joinToll, dapp.metadataDigest],
      undefined,
      bridgeCore.interface,
    ),
  });
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

  cliOutput.result({
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

  cliOutput.result({
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
      cliOutput.result({
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
  const bridgeTokenVault = new Contract(
    channelInfo.bridgeTokenVault,
    bridgeResources.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
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
    channelOperation,
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
    readChannelOperationAbandonmentStatus({
      workspace: {
        channelName,
        channelId: channelId.toString(),
      },
      bridgeTokenVault,
    }),
  ]);

  cliOutput.result({
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
    channelOperation,
    bridgeCore: getAddress(bridgeResources.bridgeDeployment.bridgeCore),
    workspaceMirror: await readChannelWorkspaceMirror({ bridgeCore, channelId }),
  });
}

async function handleSetChannelWorkspaceMirror({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const url = requireWorkspaceMirrorUrl(args.url);
  const signer = await requireL1Signer(args, provider);
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    signer,
  );
  const channelId = deriveChannelIdFromName(channelName);
  const previousUrl = await readChannelWorkspaceMirror({ bridgeCore, channelId });
  const receipt = await dryRunThenSubmitTransaction({
    operationName: "channel set-workspace-mirror",
    call: contractTxCall(
      bridgeCore.setChannelWorkspaceMirror,
      [channelId, url],
      undefined,
      bridgeCore.interface,
    ),
  });
  const currentUrl = await readChannelWorkspaceMirror({ bridgeCore, channelId });

  cliOutput.result({
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

async function handleAbandonChannelOperation({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const signer = await requireL1Signer(args, provider);
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    provider,
  );
  const channelId = deriveChannelIdFromName(channelName);
  const channelInfo = await bridgeCore.getChannel(channelId);
  expect(channelInfo.exists, `Unknown channel ${channelName} (${channelId.toString()}).`);
  expect(
    ethers.toBigInt(getAddress(signer.address)) === ethers.toBigInt(getAddress(channelInfo.leader)),
    "Only the on-chain channel leader can abandon channel operation.",
  );

  const bridgeTokenVault = new Contract(
    channelInfo.bridgeTokenVault,
    bridgeResources.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  expect(
    contractInterfaceHasFunction(bridgeTokenVault, "abandonChannelOperation"),
    "Installed bridge artifacts do not support channel operation abandonment. Update the private-state CLI artifacts after the bridge upgrade.",
  );
  const beforeStatus = await readChannelOperationAbandonmentStatus({
    workspace: {
      channelName,
      channelId: channelId.toString(),
    },
    bridgeTokenVault,
  });
  expect(
    !beforeStatus.isAbandoned,
    `Channel ${channelName} (${channelId.toString()}) has already been abandoned.`,
  );

  const receipt = await dryRunThenSubmitTransaction({
    operationName: "channel abandon-operation",
    call: contractTxCall(
      bridgeTokenVault.abandonChannelOperation,
      [channelId],
      undefined,
      bridgeTokenVault.interface,
    ),
  });
  const channelOperation = await readChannelOperationAbandonmentStatus({
    workspace: {
      channelName,
      channelId: channelId.toString(),
    },
    bridgeTokenVault,
  });

  cliOutput.result({
    action: "channel abandon-operation",
    channelName,
    channelId: channelId.toString(),
    leader: getAddress(signer.address),
    bridgeTokenVault: getAddress(channelInfo.bridgeTokenVault),
    channelOperation,
    blockedCommands: ["channel join", "wallet deposit-channel"],
    allowedCommands: [
      "wallet mint-notes",
      "wallet transfer-notes",
      "wallet redeem-notes",
      "wallet withdraw-channel",
      "channel exit",
    ],
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

async function readChannelObserver({ bridgeCore, channelId }) {
  requireBridgeCoreAbiFunction(bridgeCore, "getChannelObserver");
  return String(await bridgeCore.getChannelObserver(channelId));
}

function requireBridgeCoreAbiFunction(bridgeCore, functionName) {
  try {
    if (!bridgeCore.interface.getFunction(functionName)) {
      throw new Error(`missing ${functionName}`);
    }
  } catch {
    throw cliError(
      CLI_ERROR_CODES.MISSING_DEPLOYMENT_ARTIFACTS,
      [
        `Installed bridge deployment artifacts do not include BridgeCore.${functionName}.`,
        "Run private-state-cli install after the bridge observer registry upgrade is published.",
      ].join(" "),
      {
        details: {
          functionName,
        },
      },
    );
  }
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
    `Managed storage vector does not include channel accounting vault ${l2AccountingVaultAddress}.`,
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
      `If a workspace mirror is registered, run channel recover-workspace --channel-name ${channelName} --network ${networkNameFromChainId(network.chainId)} --source mirror first.`,
      `Use channel recover-workspace --channel-name ${channelName} --network ${networkNameFromChainId(network.chainId)} --source rpc --from-genesis only when no compatible mirror is available.`,
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
  const signer = await requireL1Signer(args, provider);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId: network.chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
  await printCommandWarningSummary("account-deposit-bridge", args, {
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
  const usesLocalL1PrivateKey = typeof signer.privateKey === "string";
  let nextNonce = usesLocalL1PrivateKey ? await provider.getTransactionCount(signer.address, "pending") : null;
  const nextL1TransactionOverrides = () => usesLocalL1PrivateKey ? { nonce: nextNonce++ } : undefined;
  let approveReceipt = null;
  const currentAllowance = ethers.toBigInt(await asset.allowance(signer.address, bridgeVaultContext.bridgeTokenVaultAddress));
  if (currentAllowance < amount) {
    approveReceipt = await dryRunThenSubmitTransaction({
      operationName: "account deposit-bridge approve",
      call: contractTxCall(
        asset.approve,
        [bridgeVaultContext.bridgeTokenVaultAddress, amount],
        nextL1TransactionOverrides(),
        asset.interface,
      ),
    });
  }
  const fundReceipt = await dryRunThenSubmitTransaction({
    operationName: "account deposit-bridge fund",
    call: contractTxCall(
      bridgeTokenVault.fund,
      [amount],
      nextL1TransactionOverrides(),
      bridgeTokenVault.interface,
    ),
    submittedBefore: approveReceipt ? [submittedReceiptSummary("account deposit-bridge approve", approveReceipt)] : [],
  });
  const availableBalance = await bridgeTokenVault.availableBalanceOf(signer.address);

  cliOutput.result({
    action: "account deposit-bridge",
    amountInput,
    amountBaseUnits: amount.toString(),
    l1Address: signer.address,
    availableBalance: availableBalance.toString(),
    bridgeTokenVault: bridgeVaultContext.bridgeTokenVaultAddress,
    approveSkipped: approveReceipt === null,
    allowanceBefore: currentAllowance.toString(),
    approveGasUsed: approveReceipt ? receiptGasUsed(approveReceipt) : null,
    fundGasUsed: receiptGasUsed(fundReceipt),
    totalGasUsed: ((approveReceipt ? ethers.toBigInt(approveReceipt.gasUsed) : 0n) + ethers.toBigInt(fundReceipt.gasUsed)).toString(),
    approveTxUrl: approveReceipt ? explorerTxUrl(network, approveReceipt.hash) : null,
    fundTxUrl: explorerTxUrl(network, fundReceipt.hash),
    approveReceipt: approveReceipt ? sanitizeReceipt(approveReceipt) : null,
    fundReceipt: sanitizeReceipt(fundReceipt),
  });
}

async function handleAccountGetBridgeFund({ args, provider }) {
  const signer = await requireL1Signer(args, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId });
  const bridgeTokenVault = new Contract(
    bridgeVaultContext.bridgeTokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const availableBalance = await bridgeTokenVault.availableBalanceOf(signer.address);

  cliOutput.result({
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
  const signer = await requireL1Signer(args, provider);
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
      "The recovered spending key does not match the recovered wallet lifecycle channel-local address.",
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

  cliOutput.result({
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
    "The recovered spending key does not match the current registered channel-local address or channel token vault key.",
  );
  return l2Identity;
}

async function handleInstallZkEvm({ args }) {
  const installMode = args.readOnly === true
    ? PRIVATE_STATE_INSTALL_MODES.READ_ONLY
    : PRIVATE_STATE_INSTALL_MODES.FULL;
  const terms = readPrivateStateTermsMetadata();
  if (isJsonOutputRequested()) {
    cliOutput.result({
      action: "install",
      installMode,
      terms,
      installed: false,
      requiresInteractiveTermsAcceptance: true,
      terms_acceptance_flow: "browser_localhost_interactive",
      termsAcceptanceCanBeProvidedByJson: false,
      terms_refs: privateStateTermsRefsForOutput(),
      terms_acceptance_action: "accept_terms_and_continue_installation_button",
      nextSafeAction: args.readOnly === true ? "private-state-cli install --read-only" : "private-state-cli install",
      message: "Run the install command again without --json. The CLI will open a local browser Terms page for the human user to review and accept before installation proceeds.",
    });
    return;
  }
  const termsAcceptance = await requireInstallTermsAcceptance({
    terms,
    installMode,
    terminalTerms: args.terminalTerms === true,
  });
  const progress = createInstallProgressReporter(installMode);
  progress.info(`Install mode: ${installMode}.`);
  let selectedVersions = null;
  let tokamakCliRuntime = null;
  let groth16Runtime = null;
  if (installMode === PRIVATE_STATE_INSTALL_MODES.FULL) {
    progress.start("Resolving runtime package versions.");
    selectedVersions = await resolvePrivateStateInstallRuntimeVersions(args);
    progress.done(`Resolved runtime versions: Tokamak zk-EVM CLI ${selectedVersions.tokamak}, Groth16 ${selectedVersions.groth16}.`);

    progress.start(`Installing Tokamak zk-EVM CLI runtime ${selectedVersions.tokamak}.`);
    tokamakCliRuntime = await installTokamakCliRuntimeForPrivateState({
      version: selectedVersions.tokamak,
      docker: Boolean(args.docker),
    });
    progress.done("Tokamak zk-EVM CLI runtime is installed.");

    progress.start(`Installing Groth16 runtime ${selectedVersions.groth16} and CRS files when needed.`);
    groth16Runtime = await installGroth16RuntimeForPrivateState({
      version: selectedVersions.groth16,
      docker: Boolean(args.docker),
    });
    progress.done("Groth16 runtime is installed.");
  } else {
    progress.info("Read-only mode selected. Proof runtimes are skipped.");
  }
  const localDeploymentBaseRoot = args.includeLocalArtifacts ? process.cwd() : null;
  progress.start("Installing deployment artifacts.");
  const deploymentArtifacts = await installPrivateStateCliArtifacts({
    dappName: PRIVATE_STATE_DAPP_LABEL,
    installMode,
    localDeploymentBaseRoot,
    groth16CrsVersion: groth16Runtime?.compatibleBackendVersion ?? null,
  });
  progress.done(`Deployment artifacts installed for ${deploymentArtifacts.installed.length} chain${deploymentArtifacts.installed.length === 1 ? "" : "s"}.`);
  progress.start("Writing the local install manifest.");
  const installManifest = writePrivateStateCliInstallManifest({
    installMode,
    dockerRequested: Boolean(args.docker),
    includeLocalArtifacts: Boolean(args.includeLocalArtifacts),
    localDeploymentBaseRoot,
    termsAcceptance,
    deploymentArtifacts,
    selectedVersions,
    tokamakCliRuntime,
    groth16Runtime,
  });
  progress.done("Local install manifest is written.");
  cliOutput.result({
    action: "install",
    installMode,
    terms,
    termsAcceptance,
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

function createInstallProgressReporter(installMode) {
  const totalSteps = installMode === PRIVATE_STATE_INSTALL_MODES.FULL ? 5 : 2;
  const startedAtMs = Date.now();
  let currentStep = 0;
  const elapsed = () => formatDurationSeconds((Date.now() - startedAtMs) / 1000);
  return {
    info(message) {
      cliOutput.progress("install", "info", {
        message: `Install: ${message}`,
      });
    },
    start(message) {
      currentStep += 1;
      cliOutput.progress("install", `step-${currentStep}-start`, {
        message: `Install ${currentStep}/${totalSteps}: ${message}`,
      });
    },
    done(message) {
      cliOutput.progress("install", `step-${currentStep}-done`, {
        message: `Install ${currentStep}/${totalSteps}: ${message} Elapsed ${elapsed()}.`,
      });
    },
  };
}

async function handleUninstall({ args }) {
  const includeWalletKeys = Boolean(args.includeWalletKeys);
  await requireUninstallConfirmation({ includeWalletKeys });
  const preservedWalletKeys = includeWalletKeys ? null : preserveWalletKeyFilesForUninstall();

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
  const restoredWalletKeys = preservedWalletKeys ? restorePreservedWalletKeyFiles(preservedWalletKeys) : [];

  cliOutput.result({
    action: "uninstall",
    confirmationAccepted: true,
    includeWalletKeys,
    removedPrivateStateRoots,
    removedTokamakZkEvmRoot,
    restoredWalletKeys,
    globalPackage,
  });
}

async function requireInstallTermsAcceptance({ terms, installMode, terminalTerms = false }) {
  if (terminalTerms) {
    return requireTerminalTermsAcceptance({
      terms,
      contextLines: [`Install mode: ${installMode}`],
      acceptanceSource: "interactive-install-terminal",
      finalAcknowledgement: "Terms accepted. Starting installation...",
    });
  }
  return requireBrowserTermsAcceptance({
    terms,
    contextLines: [`Install mode: ${installMode}`],
    acceptanceSource: "interactive-install-browser",
    finalAcknowledgement: "Terms accepted in browser. Starting installation...",
  });
}

async function requireBrowserTermsAcceptance({
  terms,
  contextLines = [],
  acceptanceSource,
  finalAcknowledgement,
}) {
  const termsText = readPrivateStateTermsText();
  const nonce = randomBytes(32).toString("hex");
  const acceptedAt = new Date().toISOString();
  const acceptedCategories = PRIVATE_STATE_TERMS_ACCEPTANCE_CATEGORIES.map((category) => ({
    id: category.id,
    title: category.title,
    termsRefs: [...category.termsRefs],
    acceptedAt,
  }));
  const acceptance = await openBrowserTermsAcceptancePage({
    terms,
    termsText,
    contextLines,
    nonce,
  });
  if (acceptance.accepted !== true) {
    throw new Error("Browser Terms acceptance was not completed. Nothing was changed.");
  }
  process.stderr.write(`${finalAcknowledgement}\n`);
  return {
    termsVersion: terms.termsVersion,
    termsHash: terms.termsHash,
    termsHashAlgorithm: terms.termsHashAlgorithm,
    acceptedAt,
    cliPackageVersion: privateStateCliPackageJson.version,
    acceptanceSource,
    acceptedByJson: false,
    acceptanceMethod: "browser-localhost",
    browserLocalhost: true,
    acceptedCategoryIds: acceptedCategories.map((category) => category.id),
    acceptedCategories,
  };
}

async function openBrowserTermsAcceptancePage({
  terms,
  termsText,
  contextLines,
  nonce,
}) {
  let resolveAcceptance;
  let rejectAcceptance;
  let accepted = false;
  const acceptancePromise = new Promise((resolve, reject) => {
    resolveAcceptance = resolve;
    rejectAcceptance = reject;
  });
  const server = http.createServer(async (request, response) => {
    try {
      const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
      if (request.method === "GET" && requestUrl.pathname === "/terms") {
        if (requestUrl.searchParams.get("token") !== nonce) {
          writeBrowserTermsResponse(response, 403, "text/plain; charset=utf-8", "Invalid Terms acceptance token.");
          return;
        }
        writeBrowserTermsResponse(
          response,
          200,
          "text/html; charset=utf-8",
          browserTermsAcceptanceHtml({ terms, termsText, contextLines, nonce }),
        );
        return;
      }
      if (request.method === "POST" && requestUrl.pathname === "/accept") {
        const body = await readRequestBodyText(request);
        const form = new URLSearchParams(body);
        const token = form.get("token");
        if (token !== nonce) {
          writeBrowserTermsResponse(response, 400, "text/plain; charset=utf-8", "Terms acceptance was invalid.");
          return;
        }
        accepted = true;
        writeBrowserTermsResponse(
          response,
          200,
          "text/html; charset=utf-8",
          browserTermsAcceptedHtml(),
        );
        resolveAcceptance({ accepted: true });
        return;
      }
      writeBrowserTermsResponse(response, 404, "text/plain; charset=utf-8", "Not found.");
    } catch (error) {
      writeBrowserTermsResponse(response, 500, "text/plain; charset=utf-8", `Terms acceptance error: ${error.message}`);
      rejectAcceptance(error);
    }
  });
  server.on("error", rejectAcceptance);
  const timeout = setTimeout(() => {
    if (!accepted) {
      rejectAcceptance(new Error("Timed out waiting for browser Terms acceptance."));
    }
  }, 30 * 60 * 1000);
  try {
    await new Promise((resolve, reject) => {
      server.listen(0, "127.0.0.1", () => resolve());
      server.once("error", reject);
    });
    const address = server.address();
    if (!address || typeof address === "string") {
      throw new Error("Could not determine local Terms acceptance server address.");
    }
    const termsUrl = `http://127.0.0.1:${address.port}/terms?token=${encodeURIComponent(nonce)}`;
    const browser = openUrlInDefaultBrowser(termsUrl);
    process.stderr.write([
      "Opening Service Terms in your browser.",
      `Terms URL: ${termsUrl}`,
      browser.opened
        ? "Browser opened. Review the Terms page and click Accept Terms and Continue Installation."
        : "The browser did not open automatically. Copy the Terms URL above into your browser.",
      "User-Controlled AI Agents must not click the browser acceptance controls for you.",
      "",
    ].join("\n"));
    return await acceptancePromise;
  } finally {
    clearTimeout(timeout);
    await closeLocalTermsServer(server);
  }
}

async function closeLocalTermsServer(server) {
  if (!server.listening) {
    return;
  }
  await new Promise((resolve) => server.close(() => resolve()));
}

async function readRequestBodyText(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

function writeBrowserTermsResponse(response, statusCode, contentType, body) {
  response.writeHead(statusCode, {
    "content-type": contentType,
    "cache-control": "no-store",
  });
  response.end(body);
}

function browserTermsAcceptanceHtml({ terms, termsText, nonce }) {
  const renderedTerms = renderMarkdownDocument(termsText);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Tonnel Service Terms</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #f5f6f8; color: #15171a; }
    main { max-width: 960px; margin: 0 auto; padding: 36px 20px 48px; }
    header { margin-bottom: 18px; }
    h1 { margin: 0 0 8px; font-size: 34px; line-height: 1.12; letter-spacing: 0; }
    .lead { margin: 0; color: #4c525a; line-height: 1.55; }
    .panel { background: #fff; border: 1px solid #d9dee5; border-radius: 8px; padding: 20px; }
    .meta { display: flex; flex-wrap: wrap; gap: 10px 18px; margin-top: 14px; color: #34383f; font-size: 14px; }
    .terms-markdown { margin-top: 18px; padding: 28px; line-height: 1.62; }
    .terms-markdown h1 { margin: 0 0 8px; font-size: 30px; }
    .terms-markdown h2 { margin: 32px 0 10px; padding-top: 20px; border-top: 1px solid #e6e9ee; font-size: 21px; }
    .terms-markdown h3 { margin: 24px 0 8px; font-size: 17px; }
    .terms-markdown p { margin: 10px 0; }
    .terms-markdown ul, .terms-markdown ol { margin: 10px 0 16px; padding-left: 26px; }
    .terms-markdown li { margin: 7px 0; }
    .terms-markdown code { padding: 2px 5px; border-radius: 4px; background: #eef1f5; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 0.94em; }
    .accept-panel { position: sticky; bottom: 0; margin-top: 18px; display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 14px; box-shadow: 0 -8px 24px rgba(21, 23, 26, 0.06); }
    .accept-copy { margin: 0; color: #4c525a; line-height: 1.45; }
    button { font: inherit; font-weight: 700; padding: 12px 18px; border: 0; border-radius: 6px; background: #111; color: #fff; cursor: pointer; }
    button:focus { outline: 3px solid #7aa7ff; outline-offset: 2px; }
    @media (max-width: 640px) {
      main { padding: 24px 14px 32px; }
      h1 { font-size: 28px; }
      .terms-markdown { padding: 20px 16px; }
      .accept-panel { position: static; }
      button { width: 100%; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Tonnel Service Terms</h1>
      <p class="lead">Please review these Terms. Installation continues only after you accept them yourself.</p>
      <div class="meta">
        <div><strong>Terms version:</strong> ${escapeHtml(terms.termsVersion)}</div>
      </div>
    </header>

    <article class="panel terms-markdown">
${renderedTerms}
    </article>

    <form method="post" action="/accept" class="panel accept-panel">
      <input type="hidden" name="token" value="${escapeHtml(nonce)}">
      <p class="accept-copy">By accepting, you confirm that you reviewed the Terms and want installation to continue.</p>
      <button id="accept-button" type="submit">Accept Terms and Continue Installation</button>
    </form>
  </main>
</body>
</html>`;
}

function renderMarkdownDocument(markdown) {
  const lines = String(markdown).trimEnd().split(/\r?\n/u);
  const html = [];
  let paragraphLines = [];
  let listType = null;
  let listItems = [];

  const flushParagraph = () => {
    if (paragraphLines.length === 0) {
      return;
    }
    html.push(`<p>${renderInlineMarkdown(paragraphLines.join(" "))}</p>`);
    paragraphLines = [];
  };
  const flushList = () => {
    if (!listType) {
      return;
    }
    html.push(`<${listType}>`);
    for (const item of listItems) {
      html.push(`  <li>${item}</li>`);
    }
    html.push(`</${listType}>`);
    listType = null;
    listItems = [];
  };

  for (const rawLine of lines) {
    const line = rawLine.trimEnd();
    if (line.trim() === "") {
      flushParagraph();
      flushList();
      continue;
    }

    const heading = /^(#{1,6})\s+(.+)$/u.exec(line);
    if (heading) {
      flushParagraph();
      flushList();
      const level = Math.min(heading[1].length, 3);
      html.push(`<h${level}>${renderInlineMarkdown(heading[2].trim())}</h${level}>`);
      continue;
    }

    const unorderedItem = /^-\s+(.+)$/u.exec(line);
    if (unorderedItem) {
      flushParagraph();
      if (listType !== "ul") {
        flushList();
        listType = "ul";
      }
      listItems.push(renderInlineMarkdown(unorderedItem[1].trim()));
      continue;
    }

    const orderedItem = /^\d+\.\s+(.+)$/u.exec(line);
    if (orderedItem) {
      flushParagraph();
      if (listType !== "ol") {
        flushList();
        listType = "ol";
      }
      listItems.push(renderInlineMarkdown(orderedItem[1].trim()));
      continue;
    }

    const listContinuation = /^\s{2,}(\S.*)$/u.exec(line);
    if (listContinuation && listType && listItems.length > 0) {
      listItems[listItems.length - 1] = `${listItems[listItems.length - 1]} ${renderInlineMarkdown(listContinuation[1].trim())}`;
      continue;
    }

    flushList();
    paragraphLines.push(line.trim());
  }

  flushParagraph();
  flushList();
  return html.map((line) => `      ${line}`).join("\n");
}

function renderInlineMarkdown(value) {
  return escapeHtml(value)
    .replace(/`([^`]+)`/gu, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/gu, "<strong>$1</strong>");
}

function browserTermsAcceptedHtml() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Terms Accepted</title>
  <style>
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f6f7f9; color: #15171a; }
    main { max-width: 720px; margin: 0 auto; padding: 64px 20px; }
    .panel { background: #fff; border: 1px solid #d8dde3; border-radius: 8px; padding: 24px; }
  </style>
</head>
<body>
  <main>
    <section class="panel">
      <h1>Terms accepted</h1>
      <p>You can return to the terminal. Installation is starting.</p>
    </section>
  </main>
</body>
</html>`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

async function requireTerminalTermsAcceptance({
  terms,
  contextLines = [],
  acceptanceSource,
  finalAcknowledgement = "Terms accepted. Continuing...",
}) {
  if (!process.stdin.isTTY || !process.stderr.isTTY) {
    throw cliError(
      CLI_ERROR_CODES.TERMS_ACCEPTANCE_REQUIRED,
      "Service Terms acceptance requires an interactive terminal.",
    );
  }
  const termsText = readPrivateStateTermsText();
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stderr,
    terminal: process.stdin.isTTY && process.stderr.isTTY,
  });
  const acceptedAt = new Date().toISOString();
  const acceptedCategories = PRIVATE_STATE_TERMS_ACCEPTANCE_CATEGORIES.map((category) => ({
    id: category.id,
    title: category.title,
    termsRefs: [...category.termsRefs],
    acceptedAt,
  }));
  try {
    const lines = [
      "SERVICE TERMS: Tonnel Service Terms",
      `Terms version: ${terms.termsVersion}`,
      ...contextLines,
      "",
      termsText.trimEnd(),
      "",
      "Acceptance required",
      "Read the Service Terms before continuing.",
      `Type exactly: ${PRIVATE_STATE_TERMS_ACCEPTANCE_CONFIRMATION}`,
      "> ",
    ];
    const answer = await rl.question(lines.join("\n"));
    if (answer !== PRIVATE_STATE_TERMS_ACCEPTANCE_CONFIRMATION) {
      throw new Error("Service Terms acceptance phrase did not match. Nothing was changed.");
    }
    process.stderr.write(`${finalAcknowledgement}\n`);
  } finally {
    rl.close();
  }
  return {
    termsVersion: terms.termsVersion,
    termsHash: terms.termsHash,
    termsHashAlgorithm: terms.termsHashAlgorithm,
    acceptedAt,
    cliPackageVersion: privateStateCliPackageJson.version,
    acceptanceSource,
    acceptedByJson: false,
    acceptedCategoryIds: acceptedCategories.map((category) => category.id),
    acceptedCategories,
  };
}

function privateStateTermsRefsForOutput() {
  return [...new Set(PRIVATE_STATE_TERMS_ACCEPTANCE_CATEGORIES.flatMap((category) => category.termsRefs))]
    .sort((left, right) => Number(left) - Number(right));
}

function commandRequiresTermsAcceptance(args) {
  if (args.command === "install") {
    return false;
  }
  if (args.command === "channel-recover-workspace") {
    return args.publishWorkspaceMirror === true;
  }
  if (args.command === "wallet-get-notes") {
    return args.exportEvidence !== undefined;
  }
  return TERMS_GATED_COMMAND_IDS.has(args.command);
}

function termsAcceptanceMatchesCurrent(record, terms) {
  return record
    && typeof record === "object"
    && record.termsVersion === terms.termsVersion
    && record.termsHash === terms.termsHash
    && record.termsHashAlgorithm === terms.termsHashAlgorithm
    && record.acceptedByJson === false;
}

async function requireCurrentTermsAcceptanceForCommand(args) {
  if (!commandRequiresTermsAcceptance(args)) {
    return null;
  }
  const terms = readPrivateStateTermsMetadata();
  let existingAcceptance = null;
  let readError = null;
  try {
    existingAcceptance = readPrivateStateCliTermsAcceptance();
  } catch (error) {
    readError = error;
  }
  if (termsAcceptanceMatchesCurrent(existingAcceptance, terms)) {
    return {
      status: "current",
      terms,
      termsAcceptance: existingAcceptance,
    };
  }

  const command = privateStateCliCommandDisplay(
    PRIVATE_STATE_CLI_COMMANDS.find((entry) => entry.id === args.command) ?? { display: args.command },
  );
  const reason = readError
    ? `Stored Service Terms acceptance could not be read: ${readError.message}`
    : existingAcceptance
      ? "Stored Service Terms acceptance is stale."
      : "No Service Terms acceptance record exists.";

  if (isJsonOutputRequested()) {
    throw cliError(
      CLI_ERROR_CODES.TERMS_ACCEPTANCE_REQUIRED,
      [
        `${command} requires current Service Terms acceptance before it can run.`,
        reason,
        "Run the command again without --json so the local browser Terms page can be displayed and accepted by the user.",
      ].join(" "),
      {
        details: {
          terms,
          existingAcceptance: existingAcceptance ?? null,
          readError: readError?.message ?? null,
        },
      },
    );
  }

  const termsAcceptance = await requireBrowserTermsAcceptance({
    terms,
    contextLines: [
      `Command: ${command}`,
      `Reason: ${reason}`,
    ],
    acceptanceSource: "interactive-renewal-browser",
    finalAcknowledgement: "Terms accepted in browser. Continuing command...",
  });
  const record = writePrivateStateCliTermsAcceptance({ termsAcceptance });
  return {
    status: "accepted",
    terms,
    termsAcceptance,
    record,
  };
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
  cliOutput.result({
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

async function requireUninstallConfirmation({ includeWalletKeys }) {
  if (!process.stdin.isTTY || !process.stderr.isTTY) {
    throw new Error("uninstall requires an interactive terminal for confirmation.");
  }
  const confirmation = includeWalletKeys
    ? PRIVATE_STATE_UNINSTALL_INCLUDE_KEYS_CONFIRMATION
    : PRIVATE_STATE_UNINSTALL_PRESERVE_KEYS_CONFIRMATION;
  const keyScope = includeWalletKeys
    ? "Wallet spending-key and viewing-key files WILL be deleted."
    : "Wallet spending-key and viewing-key files under the CLI secret root will be preserved.";
  const prompt = [
    "WARNING SUMMARY: uninstall",
    "This removes local private-state CLI workspaces, account secrets, wallet secret source files stored under the CLI root, installed private-state artifacts, the Groth16 workspace, and the Tokamak zk-EVM runtime workspace.",
    keyScope,
    "It also removes the global private-state CLI npm package when npm reports that it is globally installed.",
    "Deleted local secrets, notes, evidence, proofs, and workspace data cannot be recovered by the Provider Parties.",
    "Provider Parties do not possess your private keys, wallet secrets, spending keys, viewing keys, backups, notes, or recovery material.",
    "Do not continue unless you have independently backed up every file you may need later.",
    `Type exactly: ${confirmation}`,
    "> ",
  ].join("\n");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stderr,
    terminal: process.stdin.isTTY && process.stderr.isTTY,
  });
  try {
    const answer = await rl.question(prompt);
    if (answer !== confirmation) {
      throw new Error("Uninstall confirmation did not match. Nothing was deleted.");
    }
  } finally {
    rl.close();
  }
}

function preserveWalletKeyFilesForUninstall() {
  const entries = collectWalletKeyFilesForUninstall();
  if (entries.length === 0) {
    return {
      tempRoot: null,
      entries,
    };
  }
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-wallet-keys-"));
  for (const entry of entries) {
    const tempPath = path.join(tempRoot, entry.relativePath);
    ensureDir(path.dirname(tempPath));
    fs.copyFileSync(entry.path, tempPath);
  }
  return {
    tempRoot,
    entries: entries.map((entry) => ({
      ...entry,
      tempPath: path.join(tempRoot, entry.relativePath),
    })),
  };
}

function collectWalletKeyFilesForUninstall() {
  if (!fs.existsSync(secretRoot)) {
    return [];
  }
  const entries = [];
  const stack = [secretRoot];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const dirent of fs.readdirSync(current, { withFileTypes: true })) {
      const entryPath = path.join(current, dirent.name);
      if (dirent.isDirectory()) {
        stack.push(entryPath);
        continue;
      }
      if (!dirent.isFile() || (dirent.name !== "spending.key" && dirent.name !== "viewing.key")) {
        continue;
      }
      const relativePath = path.relative(secretRoot, entryPath);
      if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
        continue;
      }
      entries.push({
        path: entryPath,
        relativePath,
        keyKind: dirent.name === "spending.key" ? "spending" : "viewing",
      });
    }
  }
  return entries.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
}

function restorePreservedWalletKeyFiles(preservedWalletKeys) {
  const restored = [];
  try {
    for (const entry of preservedWalletKeys.entries) {
      const targetPath = path.join(secretRoot, entry.relativePath);
      ensureDir(path.dirname(targetPath));
      fs.copyFileSync(entry.tempPath, targetPath);
      protectSecretFile(targetPath, `preserved wallet ${entry.keyKind} key`);
      restored.push({
        keyKind: entry.keyKind,
        path: targetPath,
        restored: true,
      });
    }
    return restored;
  } finally {
    if (preservedWalletKeys.tempRoot) {
      fs.rmSync(preservedWalletKeys.tempRoot, { recursive: true, force: true });
    }
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
    cliOutput.result(result);
    return;
  }

  if (runningFromRepositoryCheckout) {
    cliOutput.result({
      ...result,
      reason: "running from a repository checkout; update the checkout with git/npm instead of mutating source files",
    });
    return;
  }

  if (!globalPackage.installed) {
    cliOutput.result({
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
  cliOutput.result({
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
  cliOutput.result(report);
  if (!report.ok) {
    process.exitCode = 1;
  }
}

async function handleObserver({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const channelId = deriveChannelIdFromName(channelName);
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    provider,
  );
  try {
    await bridgeCore.getChannel(channelId);
  } catch (error) {
    if (isContractError(error, bridgeCore.interface, "UnknownChannel")) {
      throw cliError(
        CLI_ERROR_CODES.UNKNOWN_CHANNEL,
        `Channel ${channelName} is not registered on ${network.name}.`,
        {
          details: {
            channelName,
            channelId: channelId.toString(),
            network: network.name,
            bridgeCore: getAddress(bridgeResources.bridgeDeployment.bridgeCore),
          },
        },
      );
    }
    throw error;
  }
  const observerUrl = (await readChannelObserver({ bridgeCore, channelId })).trim();
  if (!observerUrl) {
    throw cliError(
      CLI_ERROR_CODES.MISSING_CHANNEL_OBSERVER,
      [
        `No observer URL is registered on-chain for channel ${channelName} on ${network.name}.`,
        "The Channel Provider has not registered an observer for this Channel.",
      ].join(" "),
      {
        details: {
          channelName,
          channelId: channelId.toString(),
          network: network.name,
          bridgeCore: getAddress(bridgeResources.bridgeDeployment.bridgeCore),
        },
      },
    );
  }
  cliOutput.result({
    action: "observer",
    url: observerUrl,
    source: "on-chain channel metadata",
    network: network.name,
    chainId: network.chainId,
    channelName,
    channelId: channelId.toString(),
    bridgeCore: getAddress(bridgeResources.bridgeDeployment.bridgeCore),
    scope: "Channel-scoped public monitoring observer registered by the Channel Provider.",
    notes: [
      "Observer URLs are Channel-scoped and are read from on-chain Channel metadata.",
      "The observer does not receive wallet secrets, spending keys, viewing keys, or private note plaintext.",
    ],
  });
}

function handleInvestigator() {
  const htmlPath = resolveInvestigatorIndexPath();
  const fileUrl = pathToFileURL(htmlPath).href;
  const browser = openFileInDefaultBrowser(fileUrl);
  cliOutput.result({
    action: "investigator",
    htmlPath,
    fileUrl,
    browserOpened: browser.opened,
    browserOpenCommand: browser.command,
    browserOpenError: browser.error,
    nextSteps: [
      "Create a raw evidence ZIP with wallet get-notes --export-evidence and complete the interactive confirmation.",
      "Load the raw evidence ZIP in the browser investigator.",
      "Filter the raw bundle and export a user-consent disclosure ZIP.",
      "Do not submit the raw evidence ZIP unless full wallet-history disclosure is intended.",
      "Do not give the raw evidence ZIP to User-Controlled AI Agents, support channels, or untrusted parties.",
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
  return openUrlInDefaultBrowser(fileUrl);
}

function openUrlInDefaultBrowser(url) {
  const opener = defaultBrowserOpenCommand(url);
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

function defaultBrowserOpenCommand(url) {
  if (process.platform === "darwin") {
    return { command: "open", args: [url] };
  }
  if (process.platform === "win32") {
    return { command: "cmd", args: ["/c", "start", "", url] };
  }
  return { command: "xdg-open", args: [url] };
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

  cliOutput.result({
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

async function handleAccountGetL1Address({ args }) {
  const signer = await requireL1Signer(args);
  cliOutput.result({
    action: "account get-l1-address",
    l1Address: signer.address,
    account: args.account ?? null,
  });
}

async function handleCreatePrivateKeySource({ args }) {
  const outputPath = resolveSecretSourceOutputPath(args);
  const input = await readMaskedTerminalSecret("Enter Ethereum private key: ");
  const privateKey = normalizePrivateKey(input.trim());
  expect(input.trim().length > 0, "Private key input was empty.");
  new Wallet(privateKey);
  writeSecretSourceFile(outputPath, privateKey, "private key source file");
  cliOutput.result({
    action: "secret create-private-key-source",
    outputPath,
    secretPrinted: false,
    nextCommand: `account import --account <ACCOUNT> --network <NETWORK> --private-key-file ${shellQuotePath(outputPath)}`,
  });
}

async function handleCreateWalletSecretSource({ args }) {
  const outputPath = resolveSecretSourceOutputPath(args);
  const random = args.random === true;
  const walletSecret = random
    ? randomBytes(32).toString("hex")
    : (await readMaskedTerminalSecret("Enter wallet secret: ")).trim();
  expect(walletSecret.length > 0, "Wallet secret input was empty.");
  writeSecretSourceFile(outputPath, walletSecret, "wallet secret source file");
  cliOutput.result({
    action: "secret create-wallet-secret-source",
    outputPath,
    random,
    secretPrinted: false,
    nextCommand: `channel join --channel-name <CHANNEL> --network <NETWORK> --account <ACCOUNT> --wallet-secret-path ${shellQuotePath(outputPath)}`,
  });
}

function resolveSecretSourceOutputPath(args) {
  const outputPath = path.resolve(String(requireArg(args.output, "--output")));
  expect(!fs.existsSync(outputPath), `Secret source output already exists: ${outputPath}.`);
  return outputPath;
}

function writeSecretSourceFile(filePath, value, label) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${String(value).trim()}\n`, { mode: 0o600, flag: "wx" });
  protectSecretFile(filePath, label);
}

async function readMaskedTerminalSecret(prompt) {
  const input = process.stdin;
  const output = process.stderr;
  expect(
    input.isTTY && output.isTTY && typeof input.setRawMode === "function",
    "Masked secret input requires an interactive terminal. Run this command directly in a terminal.",
  );

  return new Promise((resolve, reject) => {
    let value = "";
    const wasRaw = input.isRaw;
    const wasPaused = input.isPaused();

    const cleanup = () => {
      input.off("data", onData);
      input.setRawMode(wasRaw);
      if (wasPaused) {
        input.pause();
      }
    };

    const finish = (callback, result) => {
      cleanup();
      output.write("\n");
      callback(result);
    };

    const onData = (chunk) => {
      for (const char of Array.from(chunk.toString("utf8"))) {
        if (char === "\u0003") {
          finish(reject, new Error("Secret input was cancelled."));
          return;
        }
        if (char === "\r" || char === "\n") {
          finish(resolve, value);
          return;
        }
        if (char === "\u007f" || char === "\b") {
          if (value.length > 0) {
            value = Array.from(value).slice(0, -1).join("");
            output.write("\b \b");
          }
          continue;
        }
        if (char >= " ") {
          value += char;
          output.write("*");
        }
      }
    };

    output.write(prompt);
    input.setRawMode(true);
    input.resume();
    input.on("data", onData);
  });
}

function shellQuotePath(filePath) {
  const value = String(filePath);
  if (/^[A-Za-z0-9_./:@%+=,-]+$/u.test(value)) {
    return value;
  }
  return `'${value.replace(/'/g, "'\\''")}'`;
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
  cliOutput.result({
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

  cliOutput.result({
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

  cliOutput.result({
    action: "wallet export backup",
    output: outputPath,
    exportMode: manifest.exportMode,
    walletCount: exportedWallets.length,
    fileCount: manifest.files.length,
    wallets: exportedWallets.map(({ network, channelName, wallet }) => ({ network, channelName, wallet })),
  });
}

async function handleWalletExportKey({ args, keyKind }) {
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
  await requireWalletKeyExportConfirmation({ keyKind });
  const payload = JSON.parse(readSecretFile(secretPath, `${keyKind} key`));
  validateWalletKeyPayload(payload, keyKind);
  fs.writeFileSync(outputPath, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
  protectSecretFile(outputPath, `${keyKind} key export`);
  cliOutput.result({
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

  cliOutput.result({
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
  cliOutput.result({
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
    agentGuidance: null,
    privacyTip: "For wallet mint-notes, wallet transfer-notes, and wallet redeem-notes, add --tx-submitter <ACCOUNT> when the user wants a separate local Ethereum account to submit executeChannelTransaction and pay gas.",
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
      command: "help guide --network mainnet",
      why: "Select mainnet for ordinary end-user setup before the guide inspects RPC, deployment artifacts, channels, accounts, or wallets.",
      candidates: [
        "help guide --network mainnet",
      ],
      agentGuidance: guideAgentGuidance("select-network", ["A.1", "D.1"]),
    });
    cliOutput.result(guide);
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
      agentGuidance: guideAgentGuidance("select-network", ["A.1", "D.1"]),
    });
    cliOutput.result(guide);
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
  cliOutput.result(guide);
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
    error = guideInspectionError(caught);
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

function guideInspectionError(error) {
  return error?.code ?? error?.message ?? String(error);
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
      const bridgeTokenVault = new Contract(
        channelInfo.bridgeTokenVault,
        bridgeResources.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
        provider,
      );
      const [joinToll, refundSchedule, workspaceMirror, channelOperation] = await Promise.all([
        channelManager.joinToll(),
        readChannelRefundSchedule(channelManager),
        readChannelWorkspaceMirror({ bridgeCore, channelId }),
        readChannelOperationAbandonmentStatus({
          workspace: {
            channelName,
            channelId: channelId.toString(),
          },
          bridgeTokenVault,
        }),
      ]);
      result.onchain.joinTollBaseUnits = joinToll.toString();
      result.onchain.refundSchedule = refundSchedule;
      result.onchain.workspaceMirror = workspaceMirror;
      try {
        const observerUrl = (await readChannelObserver({ bridgeCore, channelId })).trim();
        result.onchain.observerUrl = observerUrl || null;
        result.onchain.observerError = null;
      } catch (error) {
        result.onchain.observerUrl = null;
        result.onchain.observerError = error.message;
      }
      result.onchain.channelOperation = channelOperation;
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
    channelOperation: null,
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
      result.channelOperation = await readChannelOperationAbandonmentStatus(context);
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
  const channelOperation = guideChannelOperationStatus(guide);
  const channelAbandoned = Boolean(channelOperation?.isAbandoned);
  if (guide.state.local?.walletSelectorError && guide.selectors.network) {
    setGuideNextAction(guide, {
      command: `wallet list --network ${guide.selectors.network}`,
      why: "The selected wallet name is malformed. List local wallets and retry help guide with an existing deterministic wallet name.",
      agentGuidance: guideAgentGuidance("discover-wallet-name", ["D.9", "H.1"]),
    });
    return;
  }
  if (guide.state.network && !guide.state.network.rpcConfigured) {
    setGuideNextAction(guide, {
      command: `set rpc --network ${guide.selectors.network} --rpc-url <URL> --provider ankr`,
      why: "Configure a network RPC URL. The CLI has no default RPC URL. Ankr is recommended for users without a provider preference because its free plan is fast for this CLI's log-scanning workload.",
      agentGuidance: guideAgentGuidance("configure-rpc", ["C.1", "C.2", "C.3", "C.4", "D.3"]),
    });
    return;
  }
  if (guide.state.deploymentArtifacts && !guide.state.deploymentArtifacts.installed) {
    setGuideNextAction(guide, {
      command: "install",
      why: "The private-state deployment artifacts or proof runtime files are not installed for the selected network.",
      agentGuidance: guideAgentGuidance("install-runtime", ["D.2"]),
    });
    return;
  }
  if (guide.selectors.account && guide.state.account && !guide.state.account.exists) {
    setGuideNextAction(guide, {
      command: "secret create-private-key-source --output ./ethereum-private-key.txt",
      why: "Create a local Ethereum private-key source file in the terminal before importing it into a protected local account nickname.",
      candidates: [
        `account import --account ${guide.selectors.account} --network ${guide.selectors.network} --private-key-file ./ethereum-private-key.txt`,
        `account get-l1-address --account ${guide.selectors.account} --network ${guide.selectors.network}`,
      ],
      agentGuidance: guideAgentGuidance("create-private-key-source-and-import-account", ["B.1", "B.2", "B.3", "D.4", "I.1"]),
    });
    return;
  }
  if (guide.selectors.channelName && guide.state.channel?.onchain?.exists === false) {
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `channel create --channel-name ${guide.selectors.channelName} --join-toll <TOKENS> --network ${guide.selectors.network} --account ${account}`,
      why: "The selected channel name is not registered on-chain yet.",
      agentGuidance: guideAgentGuidance("create-channel", ["D.6", "E.1", "E.2"]),
    });
    return;
  }
  if (guide.selectors.channelName && guide.state.channel?.onchain?.exists && !guide.state.channel?.local?.workspaceExists) {
    const workspaceMirror = typeof guide.state.channel.onchain.workspaceMirror === "string"
      ? guide.state.channel.onchain.workspaceMirror.trim()
      : "";
    if (workspaceMirror) {
      setGuideNextAction(guide, {
        command: `channel recover-workspace --channel-name ${guide.selectors.channelName} --network ${guide.selectors.network} --source mirror`,
        why: "The channel has a registered workspace mirror. Use mirror recovery before considering an explicit RPC genesis rebuild.",
        agentGuidance: guideAgentGuidance("recover-channel-workspace", ["D.7", "F.1", "F.2"]),
      });
      return;
    }
    setGuideNextAction(guide, {
      command: `channel recover-workspace --channel-name ${guide.selectors.channelName} --network ${guide.selectors.network} --source rpc --from-genesis`,
      why: "The channel exists on-chain, but the local channel workspace has not been recovered yet and no workspace mirror is registered. RPC genesis rebuild is the remaining explicit bootstrap path.",
      agentGuidance: guideAgentGuidance("recover-channel-workspace", ["D.7", "F.1", "F.3"]),
    });
    return;
  }
  if (guide.selectors.wallet && guide.state.wallet && !guide.state.wallet.exists) {
    if (channelAbandoned) {
      const channelName = guide.selectors.channelName ?? guide.state.channel?.channelName ?? "<CHANNEL>";
      setGuideNextAction(guide, {
        command: `channel get-meta --channel-name ${channelName} --network ${guide.selectors.network}`,
        why: "The selected Channel is abandoned. New channel joins are disabled, so do not create a new wallet for this Channel.",
        agentGuidance: guideAgentGuidance("channel-operation-abandoned", ["D.15", "E.1", "E.2"]),
      });
      return;
    }
    const channelName = guide.selectors.channelName ?? guide.state.channel?.channelName ?? "<CHANNEL>";
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: "secret create-wallet-secret-source --output ./wallet-secret.txt",
      why: "Create a wallet secret source file before joining the channel. Prefer user-typed wallet secrets; use random generation only when the user explicitly asks for it.",
      candidates: [
        `channel join --channel-name ${channelName} --network ${guide.selectors.network} --account ${account} --wallet-secret-path ./wallet-secret.txt`,
        "secret create-wallet-secret-source --output ./wallet-secret.txt --random",
      ],
      agentGuidance: guideAgentGuidance("create-wallet-secret-source-and-join-channel", ["B.4", "B.5", "B.6", "B.7", "D.5", "D.8", "E.1", "E.2"]),
    });
    return;
  }
  if (guide.state.wallet?.registrationExists === false) {
    if (channelAbandoned) {
      const channelName = guide.state.wallet.channelName ?? guide.selectors.channelName ?? "<CHANNEL>";
      setGuideNextAction(guide, {
        command: `channel get-meta --channel-name ${channelName} --network ${guide.selectors.network}`,
        why: "The selected Channel is abandoned. New channel joins are disabled for wallets that are not already registered.",
        agentGuidance: guideAgentGuidance("channel-operation-abandoned", ["D.15", "E.1", "E.2"]),
      });
      return;
    }
    const channelName = guide.state.wallet.channelName ?? guide.selectors.channelName ?? "<CHANNEL>";
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `channel join --channel-name ${channelName} --network ${guide.selectors.network} --account ${account} --wallet-secret-path ./wallet-secret.txt`,
      why: "The local wallet exists, but the corresponding Ethereum address is not registered in the channel; joining pays any Join Toll directly from the Ethereum wallet.",
      agentGuidance: guideAgentGuidance("join-channel-with-existing-wallet-secret-source", ["B.7", "D.8", "E.1", "E.2"]),
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

  if (guide.state.wallet?.exists && channelAbandoned && channelBalance === 0n && unusedNotes === 0) {
    setGuideNextAction(guide, {
      command: `channel exit --wallet ${guide.selectors.wallet} --network ${guide.selectors.network}`,
      why: "The Channel is abandoned and the wallet has no channel balance or unused private notes. New channel deposits are disabled, so channel exit is the remaining cleanup path.",
      candidates: [
        `channel get-meta --channel-name ${guide.state.wallet.channelName ?? guide.selectors.channelName ?? "<CHANNEL>"} --network ${guide.selectors.network}`,
        `account withdraw-bridge --amount <TOKENS> --network ${guide.selectors.network} --account ${guide.selectors.account ?? "<ACCOUNT>"}`,
      ],
      agentGuidance: guideAgentGuidance("channel-operation-abandoned", ["D.15", "E.1", "E.2"]),
    });
    return;
  }

  if (!channelAbandoned && guide.state.wallet?.exists && bridgeBalance === 0n && (channelBalance === null || channelBalance === 0n) && unusedNotes === 0) {
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `account deposit-bridge --amount <TOKENS> --network ${guide.selectors.network} --account ${account}`,
      why: "The wallet is joined, but there is no bridge balance, channel balance, or local unused note to spend; bridge deposits fund channel liquidity and do not pay Join Tolls.",
      agentGuidance: guideAgentGuidance("fund-bridge", ["D.10", "E.1", "G.1"]),
    });
    return;
  }
  if (guide.state.wallet?.exists && bridgeBalance !== null && bridgeBalance > 0n && channelBalance === 0n) {
    if (channelAbandoned) {
      setGuideNextAction(guide, {
        command: `channel exit --wallet ${guide.selectors.wallet} --network ${guide.selectors.network}`,
        why: "The Channel is abandoned and wallet deposit-channel is disabled. The wallet has zero channel balance, so channel exit remains available.",
        candidates: [
          `channel get-meta --channel-name ${guide.state.wallet.channelName ?? guide.selectors.channelName ?? "<CHANNEL>"} --network ${guide.selectors.network}`,
          `account withdraw-bridge --amount <TOKENS> --network ${guide.selectors.network} --account ${guide.selectors.account ?? "<ACCOUNT>"}`,
        ],
        agentGuidance: guideAgentGuidance("channel-operation-abandoned", ["D.15", "E.1", "E.2"]),
      });
      return;
    }
    setGuideNextAction(guide, {
      command: `wallet deposit-channel --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --amount <TOKENS>`,
      why: "The account has funds in the shared bridge vault, but the wallet has no channel accounting balance.",
      agentGuidance: guideAgentGuidance("fund-channel", ["D.11", "E.1", "G.2"]),
    });
    return;
  }
  if (guide.state.wallet?.exists && channelBalance !== null && channelBalance > 0n && unusedNotes === 0) {
    setGuideNextAction(guide, {
      command: `wallet mint-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --amounts <JSON_ARRAY> [--tx-submitter <ACCOUNT>]`,
      why: "The wallet has channel balance and no unused private notes yet. Use --tx-submitter only when a separate imported local Ethereum account should submit the transaction and pay gas.",
      agentGuidance: guideAgentGuidance("mint-notes", ["D.12", "E.1", "G.3", "G.5"]),
    });
    return;
  }
  if (guide.state.wallet?.exists && unusedNotes !== null && unusedNotes > 0) {
    setGuideNextAction(guide, {
      command: `wallet transfer-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --note-ids <JSON_ARRAY> --recipients <JSON_ARRAY> --amounts <JSON_ARRAY> [--tx-submitter <ACCOUNT>]`,
      why: "The wallet has unused private notes. It can transfer or redeem those notes. Use --tx-submitter only when a separate imported local Ethereum account should submit the transaction and pay gas.",
      candidates: [
        `wallet get-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network}`,
        `wallet redeem-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --note-ids <JSON_ARRAY> [--tx-submitter <ACCOUNT>]`,
      ],
      agentGuidance: guideAgentGuidance("use-notes", ["D.13", "E.1", "G.4", "G.5"]),
    });
    return;
  }
  if (guide.state.wallet?.exists && channelBalance === 0n) {
    setGuideNextAction(guide, {
      command: `channel exit --wallet ${guide.selectors.wallet} --network ${guide.selectors.network}`,
      why: "The wallet has zero channel balance, so channel exit is allowed by both the CLI and bridge contract.",
      agentGuidance: guideAgentGuidance("exit-channel", ["D.14", "G.6"]),
    });
    return;
  }

  setGuideNextAction(guide, {
    command: "help guide --network <NAME> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET>",
    why: "Provide more selectors so the guide can choose a single next safe action.",
    agentGuidance: guideAgentGuidance("collect-selectors", ["A.1", "D.1", "H.1"]),
  });
}

function guideChannelOperationStatus(guide) {
  return guide.state.wallet?.channelOperation ?? guide.state.channel?.onchain?.channelOperation ?? null;
}

function setGuideNextAction(guide, { command, why, candidates = [], agentGuidance = null }) {
  guide.nextSafeAction = command;
  guide.why = why;
  guide.candidateCommands = candidates;
  guide.agentGuidance = agentGuidance;
}

function guideAgentGuidance(step, refs) {
  return {
    source: "agents.md",
    step,
    refs: [...new Set([...refs, "E.3"])],
    termsSource: "docs/dapps/private-state/terms.md",
    termsRefs: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "18", "20"],
  };
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

  cliOutput.result({
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
  const signer = restoreWalletSigner(walletContext, provider);
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
      "The local wallet channel-local address or storage key does not match the registered channelTokenVault state.",
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
      "Join transaction registration log does not match the current registered channel-local address.",
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

  cliOutput.result({
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
  await requireChannelOperationActive(context, "channel join");
  const signer = await requireL1Signer(args, provider);
  const walletName = walletNameForChannelAndAddress(context.workspace.channelName, signer.address);
  const existingRegistration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  expect(
    !existingRegistration.exists,
    [
      `Ethereum address ${signer.address} is already registered in channel ${context.workspace.channelName}.`,
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
  const usesLocalL1PrivateKey = typeof signer.privateKey === "string";
  let nextNonce = usesLocalL1PrivateKey ? await provider.getTransactionCount(signer.address, "pending") : null;
  const nextL1TransactionOverrides = () => usesLocalL1PrivateKey ? { nonce: nextNonce++ } : undefined;
  printImmutableChannelPolicyWarning({
    action: "channel join",
    channelName: context.workspace.channelName,
    channelId: ethers.toBigInt(context.workspace.channelId),
    channelManager: context.workspace.channelManager,
    policySnapshot: context.workspace.policySnapshot,
  });
  await printCommandWarningSummary("channel-join", args, {
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    noteReceivePubKey: JSON.stringify(noteReceiveKeyMaterial.noteReceivePubKey),
    joinToll: ethers.formatUnits(joinToll, Number(context.workspace.canonicalAssetDecimals)),
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
  });
  if (joinToll !== 0n) {
    approveReceipt = await dryRunThenSubmitTransaction({
      operationName: "channel join approve",
      call: contractTxCall(
        asset.approve,
        [context.workspace.bridgeTokenVault, joinToll],
        nextL1TransactionOverrides(),
        asset.interface,
      ),
    });
  }
  receipt = await dryRunThenSubmitTransaction({
    operationName: "channel join",
    call: contractTxCall(
      context.bridgeTokenVault.connect(signer).joinChannel,
      [
        ethers.toBigInt(context.workspace.channelId),
        l2Identity.l2Address,
        storageKey,
        leafIndex,
        noteReceiveKeyMaterial.noteReceivePubKey,
      ],
      nextL1TransactionOverrides(),
      context.bridgeTokenVault.interface,
    ),
    submittedBefore: approveReceipt ? [submittedReceiptSummary("channel join approve", approveReceipt)] : [],
  });
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

  cliOutput.result({
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
  const { context, channelFund, contextResult } = await loadWalletChannelFundState({
    walletContext,
    provider,
    progressAction: "channel exit",
  });
  const ownerSigner = await requireWalletOwnerSigner(walletContext, provider);
  const network = contextResult.network;
  await warnIfChannelOperationAbandoned(context, "channel exit");
  expect(
    channelFund === 0n,
    [
      `The current channel fund for ${ownerSigner.address} is ${channelFund.toString()}.`,
      "channel exit requires a zero channel balance.",
      "Run wallet withdraw-channel first, then retry channel exit.",
    ].join(" "),
  );
  const [refundAmount, refundBps] = await context.channelManager.getExitTollRefundQuote(ownerSigner.address);
  await printCommandWarningSummary("channel-exit", args, {
    l1Address: ownerSigner.address,
    l2Address: walletContext.wallet.l2Address,
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
    currentUserValue: channelFund.toString(),
    refundAmount: ethers.formatUnits(refundAmount, Number(context.workspace.canonicalAssetDecimals)),
    refundBps: Number(refundBps),
  });
  const receipt = await dryRunThenSubmitTransaction({
    operationName: "channel exit",
    call: contractTxCall(
      context.bridgeTokenVault.connect(ownerSigner).exitChannel,
      [ethers.toBigInt(context.workspace.channelId)],
      undefined,
      context.bridgeTokenVault.interface,
    ),
  });
  const lifecycleEpoch = await markWalletEpochExited({
    walletContext,
    receipt,
    provider,
  });

  cliOutput.result({
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
  if (direction === "deposit") {
    await requireChannelOperationActive(context, operationName);
  } else {
    await warnIfChannelOperationAbandoned(context, operationName);
  }
  expect(
    ethers.toBigInt(walletContext.wallet.channelId) === ethers.toBigInt(context.workspace.channelId),
    "The provided wallet does not belong to the selected channel.",
  );
  await assertChannelProofBackendVersionCompatibility({ context, operationName });

  const signer = await requireWalletOwnerSigner(walletContext, provider);
  const l2Identity = restoreParticipantIdentityFromWallet(walletContext.wallet);
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(context.workspace.canonicalAssetDecimals));
  await printCommandWarningSummary(args.command, args, {
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
    "The derived channel storage key does not match the registered channelTokenVault key.",
  );
  expect(
    ethers.toBigInt(getAddress(registration.l2Address)) === ethers.toBigInt(getAddress(l2Identity.l2Address)),
    "The derived channel-local address does not match the registered channel-local address.",
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
      throw new Error("Withdraw amount exceeds the current channel accounting balance.");
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
  emitProgress(operationName, "submitting");
  const receipt = await dryRunThenSubmitTransaction({
    operationName,
    context,
    walletName: walletContext.walletName,
    operationDir,
    precheck: () => precheckGrothRootUpdate({ context, transition, operationName }),
    call: contractTxCall(
      bridgeTokenVault[methodName],
      [
        ethers.toBigInt(context.workspace.channelId),
        transition.proof,
        transition.update,
      ],
      undefined,
      bridgeTokenVault.interface,
    ),
  });
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
  cliOutput.result({
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
  const signer = await requireL1Signer(args, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
  await printCommandWarningSummary("account-withdraw-bridge", args, {
    l1Address: signer.address,
    amountInput,
    bridgeTokenVault: bridgeVaultContext.bridgeTokenVaultAddress,
  });
  const bridgeTokenVault = new Contract(
    bridgeVaultContext.bridgeTokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const receipt = await dryRunThenSubmitTransaction({
    operationName: "account withdraw-bridge",
    call: contractTxCall(
      bridgeTokenVault.claimToWallet,
      [amount],
      undefined,
      bridgeTokenVault.interface,
    ),
  });

  cliOutput.result({
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
  const {
    signer,
    l2Identity,
    channelFund,
    contextResult: preparedContextResult,
  } = await loadWalletChannelFundState({
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
  const txSubmitterResolution = await resolveTxSubmitterSigner({
    args,
    ownerSigner: signer,
    provider,
  });
  const { txSubmitter } = txSubmitterResolution;
  await printCommandWarningSummary("wallet-mint-notes", args, {
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
    txSubmitterResolution,
  });

  cliOutput.result({
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
  const txSubmitterResolution = await resolveTxSubmitterSigner({
    args,
    ownerSigner: signer,
    provider,
  });
  const { txSubmitter } = txSubmitterResolution;
  await printCommandWarningSummary("wallet-redeem-notes", args, {
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
    txSubmitterResolution,
  });

  cliOutput.result({
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
    ? await (async () => {
      await requirePlaintextEvidenceExportConfirmation();
      return exportWalletGetNotesEvidenceBundle({
        args,
        provider,
        walletContext: wallet,
        walletMetadata,
        context,
        unusedTrackedNotes,
        spentTrackedNotes,
      });
    })()
    : null;

  cliOutput.result({
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

async function requirePlaintextEvidenceExportConfirmation() {
  const confirmation = "I understand this export contains plaintext note evidence";
  const lines = [
    "WARNING SUMMARY: wallet get-notes --export-evidence",
    "- This export writes plaintext note facts for locally known notes into a local raw evidence ZIP.",
    "- The export is not a key export, but it can reveal sensitive wallet history and note evidence for the selected wallet.",
    "- The raw evidence ZIP may include all locally known notes and retained exited epochs for the selected wallet.",
    "- Store it locally, share it only with parties you choose, and delete extra copies when they are no longer needed.",
    "- User-Controlled AI Agents must not type this confirmation for the user or receive the raw evidence ZIP.",
    "- Provider Parties cannot recover leaked plaintext evidence or undo third-party disclosure.",
    `Type exactly: ${confirmation}`,
    "> ",
  ];
  if (!process.stdin.isTTY || !process.stderr.isTTY) {
    throw new Error("wallet get-notes --export-evidence requires an interactive terminal for plaintext evidence export confirmation.");
  }
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stderr,
    terminal: process.stdin.isTTY && process.stderr.isTTY,
  });
  try {
    const answer = await rl.question(lines.join("\n"));
    if (answer !== confirmation) {
      throw new Error("wallet get-notes --export-evidence confirmation did not match. No evidence ZIP was written.");
    }
  } finally {
    rl.close();
  }
}

async function requireWalletKeyExportConfirmation({ keyKind }) {
  const confirmation = `I understand this export contains my ${keyKind} private key`;
  const authority = keyKind === "spending"
    ? "spend, transfer, or redeem Private Notes when other required wallet state is available"
    : "read and reconstruct note history addressed to this wallet when other required wallet state is available";
  const lines = [
    `WARNING SUMMARY: wallet export ${keyKind}-key`,
    `- This export writes the wallet ${keyKind} private key into a local .key file.`,
    `- Anyone who obtains this file may be able to ${authority}.`,
    "- Store the file offline or in a secure password manager, share it only with devices or people you intentionally trust, and delete extra copies when they are no longer needed.",
    "- Provider Parties cannot recover leaked key material, undo disclosure, reverse transactions, or restore lost files.",
    "- User-Controlled AI Agents must not type this confirmation for the user or receive the exported key file.",
    `Type exactly: ${confirmation}`,
    "> ",
  ];
  if (!process.stdin.isTTY || !process.stderr.isTTY) {
    throw new Error(`wallet export ${keyKind}-key requires an interactive terminal for secret-bearing export confirmation.`);
  }
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stderr,
    terminal: process.stdin.isTTY && process.stderr.isTTY,
  });
  try {
    const answer = await rl.question(lines.join("\n"));
    if (answer !== confirmation) {
      throw new Error(`wallet export ${keyKind}-key confirmation did not match. No key file was written.`);
    }
  } finally {
    rl.close();
  }
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
    `Cannot export evidence for note ${note.commitment}: owner does not match wallet channel-local address.`,
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

  const txSubmitterResolution = await resolveTxSubmitterSigner({
    args,
    ownerSigner: signer,
    provider,
  });
  const { txSubmitter } = txSubmitterResolution;
  await printCommandWarningSummary("wallet-transfer-notes", args, {
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
    txSubmitterResolution,
  });
  const outputNotes = buildLifecycleTrackedOutputs({
    outputNotes: templatePayload.lifecycleOutputs,
    sourceFunction: templatePayload.method,
    sourceTxHash: execution.receipt.hash,
    sourceBlockNumber: execution.receipt.blockNumber,
    counterpartyL2Addresses: templatePayload.recipientAddresses,
    counterpartyDirection: "sent",
  });

  cliOutput.result({
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
    throw new Error("Invalid --recipients. Expected a JSON array of channel-local addresses.");
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
    "The provided wallet does not match the derived private application identity.",
  );
}

async function executeWalletDirectTemplateCommand({
  args,
  wallet,
  provider,
  operationName,
  templatePayload,
  preparedContextResult,
  txSubmitterResolution = null,
}) {
  emitProgress(operationName, "loading");
  const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);
  requireWalletSpendingCapability(wallet);
  const {
    txSubmitter,
    source: txSubmitterSource,
    account: txSubmitterAccount,
  } = txSubmitterResolution ?? (await resolveTxSubmitterSigner({
    args,
    ownerSigner: signer,
    provider,
  }));
  expect(preparedContextResult?.context, "Internal error: prepared channel context is required before proof generation.");
  const contextResult = preparedContextResult;
  await warnIfChannelOperationAbandoned(contextResult.context, operationName);
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
  await assertWorkspaceAlignedWithChain(context);
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

  emitProgress(operationName, "submitting");
  const receipt = await dryRunThenSubmitTransaction({
    operationName,
    context,
    walletName: wallet.walletName,
    operationDir,
    precheck: () => precheckTokamakExecution({
      context,
      payload,
      functionProof,
      aPubBlockHash,
      operationName,
    }),
    call: contractTxCall(
      context.channelManager.connect(txSubmitter).executeChannelTransaction,
      [payload, functionProof],
      undefined,
      context.channelManager.interface,
    ),
  });
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
      `Wallet ${normalizedWalletName} is internally inconsistent: stored keys do not match the stored channel-local address.`,
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
      `Wallet ${walletName} was not created with the current channel-bound derivation rule.`,
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

async function requireWalletOwnerSigner(walletContext, provider) {
  const signer = restoreWalletSigner(walletContext, provider);
  if (typeof signer.privateKey !== "string") {
    return await requireBrowserWalletSigner({
      role: "wallet owner L1 signer",
      expectedAddress: walletContext.wallet.l1Address,
      provider,
    });
  }
  return signer;
}

function requireWalletSpendingCapability(walletContext) {
  expect(
    walletContext.wallet.l2PrivateKey,
    [
      `Wallet ${walletContext.walletName} is missing its spending key.`,
      "Import it with wallet import spending-key before commands that spend notes or change channel accounting state.",
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

function isUnexpectedCurrentRootVectorError(error, context) {
  if (isContractError(error, context.channelManager.interface, "UnexpectedCurrentRootVector")) {
    return true;
  }
  return String(error?.message ?? error).includes("UnexpectedCurrentRootVector");
}

function precheckGrothRootUpdate({ context, transition, operationName }) {
  expect(transition && typeof transition === "object", `${operationName} proof precheck failed: missing transition.`);
  expect(transition.proof && typeof transition.proof === "object", `${operationName} proof precheck failed: missing Groth16 proof.`);
  expect(transition.update && typeof transition.update === "object", `${operationName} proof precheck failed: missing root update.`);
  expect(
    Array.isArray(transition.update.currentRootVector) && transition.update.currentRootVector.length > 0,
    `${operationName} proof precheck failed: missing current root vector.`,
  );
  expect(
    normalizeBytes32Hex(hashRootVector(transition.update.currentRootVector))
      === normalizeBytes32Hex(hashRootVector(context.currentSnapshot.stateRoots)),
    `${operationName} proof precheck failed: root update does not match the local workspace snapshot.`,
  );
  normalizeBytes32Hex(transition.update.updatedRoot);
  normalizeBytes32Hex(transition.update.currentUserKey);
  normalizeBytes32Hex(transition.update.updatedUserKey);
  expect(transition.nextSnapshot?.stateRoots, `${operationName} proof precheck failed: missing next snapshot roots.`);
}

function precheckTokamakExecution({ context, payload, functionProof, aPubBlockHash, operationName }) {
  expect(payload && typeof payload === "object", `${operationName} proof precheck failed: missing Tokamak payload.`);
  for (const key of [
    "proofPart1",
    "proofPart2",
    "functionPreprocessPart1",
    "functionPreprocessPart2",
    "aPubUser",
    "aPubBlock",
  ]) {
    expect(Array.isArray(payload[key]) && payload[key].length > 0, `${operationName} proof precheck failed: payload.${key} is missing.`);
  }
  expect(functionProof?.metadata, `${operationName} proof precheck failed: missing function metadata proof.`);
  expect(Array.isArray(functionProof?.siblings), `${operationName} proof precheck failed: missing function metadata proof siblings.`);
  expect(
    ethers.toBigInt(normalizeBytes32Hex(aPubBlockHash))
      === ethers.toBigInt(normalizeBytes32Hex(context.workspace.aPubBlockHash)),
    `${operationName} proof precheck failed: generated aPubBlockHash does not match the channel aPubBlockHash.`,
  );
}

function contractInterfaceHasFunction(contract, functionName) {
  try {
    return Boolean(contract.interface.getFunction(functionName));
  } catch {
    return false;
  }
}

async function readChannelOperationAbandonmentStatus(context) {
  const channelId = ethers.toBigInt(context.workspace.channelId);
  const status = {
    supported: false,
    isAbandoned: false,
    channelName: context.workspace.channelName,
    channelId: channelId.toString(),
    abandonedAt: null,
    abandonedAtIso: null,
    error: null,
  };
  if (!contractInterfaceHasFunction(context.bridgeTokenVault, "channelOperationAbandonedAt")) {
    return status;
  }
  status.supported = true;
  let abandonedAt;
  try {
    abandonedAt = ethers.toBigInt(await context.bridgeTokenVault.channelOperationAbandonedAt(channelId));
  } catch (error) {
    status.supported = false;
    status.error = error?.shortMessage ?? error?.message ?? String(error);
    return status;
  }
  if (abandonedAt !== 0n) {
    status.isAbandoned = true;
    status.abandonedAt = abandonedAt.toString();
    status.abandonedAtIso = new Date(Number(abandonedAt) * 1000).toISOString();
  }
  return status;
}

async function requireChannelOperationActive(context, operationName) {
  const status = await readChannelOperationAbandonmentStatus(context);
  if (!status.isAbandoned) {
    return status;
  }
  throw cliError(
    CLI_ERROR_CODES.CHANNEL_OPERATION_ABANDONED,
    [
      `${operationName} cannot continue because Channel operation has been abandoned for ${status.channelName} (${status.channelId}).`,
      "New channel joins and wallet deposit-channel are disabled for this Channel.",
      "Existing users can still use note activity, wallet redeem-notes, wallet withdraw-channel, and channel exit subject to ordinary proof, balance, and secret requirements.",
    ].join(" "),
  );
}

async function warnIfChannelOperationAbandoned(context, operationName) {
  const status = await readChannelOperationAbandonmentStatus(context);
  if (!status.isAbandoned) {
    return status;
  }
  cliOutput.warning(
    "channel-operation-abandoned",
    [
      `CHANNEL OPERATION WARNING: ${status.channelName} (${status.channelId}) is abandoned.`,
      "New channel joins and wallet deposit-channel are disabled for this Channel.",
      `${operationName} is not blocked by abandonment, but users should understand that the Channel no longer accepts new joins or channel deposits.`,
    ].join("\n"),
    {
      action: operationName,
      channelName: status.channelName,
      channelId: status.channelId,
      abandonedAt: status.abandonedAt,
      abandonedAtIso: status.abandonedAtIso,
      blockedCommands: ["channel join", "wallet deposit-channel"],
      allowedCommands: [
        "note activity",
        "wallet redeem-notes",
        "wallet withdraw-channel",
        "channel exit",
      ],
    },
  );
  return status;
}

function contractTxCall(contractMethod, args = [], overrides = undefined, contractInterface = null) {
  expect(typeof contractMethod === "function", "Internal error: contract transaction method must be callable.");
  expect(
    typeof contractMethod.staticCall === "function",
    "Internal error: contract transaction method must support staticCall.",
  );
  const finalArgs = overrides === undefined ? [...args] : [...args, overrides];
  return {
    contractInterface,
    dryRun: () => contractMethod.staticCall(...finalArgs),
    submit: () => contractMethod(...finalArgs),
  };
}

async function dryRunThenSubmitTransaction({
  operationName,
  call,
  precheck = null,
  context = null,
  walletName = null,
  operationDir = null,
  submittedBefore = [],
}) {
  expect(typeof call?.dryRun === "function", "Internal error: transaction dry-run callback is required.");
  expect(typeof call?.submit === "function", "Internal error: transaction submit callback is required.");
  if (precheck) {
    await precheck();
  }
  try {
    await call.dryRun();
  } catch (error) {
    throw transactionPreflightOrSubmitError({
      phase: "dry-run",
      operationName,
      cause: error,
      context,
      walletName,
      operationDir,
      submittedBefore,
      contractInterface: call.contractInterface,
    });
  }
  try {
    return await withBrowserWalletTransactionContext(
      {
        operationName,
        channelName: context?.workspace?.channelName ?? null,
        channelId: context?.workspace?.channelId ?? null,
        walletName,
      },
      async () => await waitForReceipt(await call.submit()),
    );
  } catch (error) {
    throw transactionPreflightOrSubmitError({
      phase: "submit",
      operationName,
      cause: error,
      context,
      walletName,
      operationDir,
      submittedBefore,
      contractInterface: call.contractInterface,
    });
  }
}

function transactionPreflightOrSubmitError({
  phase,
  operationName,
  cause,
  context = null,
  walletName = null,
  operationDir = null,
  submittedBefore = [],
  contractInterface = null,
}) {
  if (context && isUnexpectedCurrentRootVectorError(cause, context)) {
    return staleChannelRootError({
      cause,
      context,
      walletName,
      operationName,
      phase,
    });
  }
  const decodedError = decodeTransactionContractError(cause, [
    contractInterface,
    context?.channelManager?.interface,
    context?.bridgeTokenVault?.interface,
  ]);
  const details = [
    phase === "dry-run"
      ? `${operationName} pre-submit dry-run failed. No ${operationName} transaction was submitted.`
      : `${operationName} transaction submission failed.`,
  ];
  const submitted = normalizeSubmittedBefore(submittedBefore);
  if (submitted.length > 0) {
    details.push(`Already submitted before this failure: ${submitted.join("; ")}.`);
  }
  if (walletName) {
    details.push(`Wallet: ${walletName}.`);
  }
  if (operationDir) {
    details.push(`Operation directory: ${operationDir}.`);
  }
  if (decodedError) {
    details.push(`Decoded contract error: ${decodedError}.`);
  }
  details.push(`Provider error: ${extractProviderErrorMessage(cause)}.`);
  const error = cliError(
    phase === "dry-run" ? CLI_ERROR_CODES.TX_DRY_RUN_FAILED : CLI_ERROR_CODES.TX_SUBMIT_FAILED,
    details.join(" "),
    { cause },
  );
  error.phase = phase;
  error.operationName = operationName;
  error.transactionSubmitted = phase !== "dry-run";
  error.submittedBefore = submitted;
  error.walletName = walletName;
  error.operationDir = operationDir;
  error.decodedContractError = decodedError;
  error.providerError = extractProviderErrorMessage(cause);
  if (context) {
    error.channelName = context.workspace?.channelName;
    error.networkName = context.workspace?.network;
  }
  return error;
}

function submittedReceiptSummary(label, receipt) {
  return `${label} tx ${receipt?.hash ?? "<unknown>"} in block ${receipt?.blockNumber ?? "<unknown>"}`;
}

function normalizeSubmittedBefore(entries) {
  return entries
    .filter(Boolean)
    .map((entry) => {
      if (typeof entry === "string") {
        return entry;
      }
      if (entry?.hash) {
        return submittedReceiptSummary(entry.label ?? "transaction", entry);
      }
      return String(entry);
    });
}

function decodeTransactionContractError(error, contractInterfaces) {
  if (error?.revert?.name) {
    return formatDecodedContractError(error.revert.name, error.revert.args ?? []);
  }
  for (const contractInterface of contractInterfaces.filter(Boolean)) {
    for (const errorData of extractContractErrorDataCandidates(error)) {
      try {
        const parsed = contractInterface.parseError(errorData);
        if (parsed) {
          return formatDecodedContractError(parsed.name, parsed.args ?? []);
        }
      } catch {
        // Keep scanning provider error payloads and interfaces.
      }
    }
  }
  return null;
}

function formatDecodedContractError(name, args) {
  const renderedArgs = Array.from(args ?? [])
    .map((value) => serializeBigInts(normalizeCliOutputValue(value, [])));
  return `${name}(${renderedArgs.map((value) => JSON.stringify(value)).join(", ")})`;
}

function extractProviderErrorMessage(error) {
  return String(
    error?.shortMessage
      ?? error?.reason
      ?? error?.info?.error?.message
      ?? error?.error?.message
      ?? error?.message
      ?? error,
  );
}

function staleChannelRootError({
  cause,
  context,
  walletName,
  operationName,
  phase = "submit",
}) {
  const message = [
    phase === "dry-run"
      ? `${operationName} pre-submit dry-run failed because the generated proof targets an older channel root. No ${operationName} transaction was submitted.`
      : `${operationName} failed because the submitted proof was generated for an older channel root.`,
    "The rejected proof cannot be reused.",
    "Do not change recipients, amounts, note counts, function arity, or split the command as recovery.",
    "Refresh the channel workspace, re-check affected wallet state when the command uses notes, then rerun the original intended command so the CLI regenerates a proof from a fresh snapshot.",
  ].join(" ");
  const error = cliError(CLI_ERROR_CODES.STALE_CHANNEL_ROOT, message, { cause });
  error.phase = phase;
  error.operationName = operationName;
  error.transactionSubmitted = phase !== "dry-run";
  error.channelName = context.workspace.channelName;
  error.networkName = context.workspace.network;
  error.walletName = walletName;
  error.providerError = extractProviderErrorMessage(cause);
  error.retryPolicy = "recover_workspace_then_regenerate_proof";
  error.semanticMutationAllowed = false;
  error.reuseProofAllowed = false;
  return error;
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
  if (isJsonOutputRequested() && value?.action === "guide") {
    const {
      why,
      privacyTip,
      mirrorTip,
      ...jsonGuide
    } = value;
    void why;
    void privacyTip;
    void mirrorTip;
    return normalizeCliOutputValue(jsonGuide, []);
  }
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
      || parsed.command === "help"
      || parsed.command === "secret")
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
  cliOutput.result({
    action: "version",
    packageName: privateStateCliPackageJson.name,
    version: privateStateCliPackageJson.version,
  });
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
  return requireAccountOptionValue(args.account, "--account");
}

async function requireL1Signer(args, provider) {
  const accountMode = resolveL1AccountMode(args);
  if (accountMode.mode === L1_SIGNER_MODES.BROWSER_WALLET) {
    return await requireBrowserWalletSigner({
      role: "L1 account",
      provider,
    });
  }
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

async function resolveTxSubmitterSigner({ args, ownerSigner, provider }) {
  if (args.txSubmitter === undefined) {
    if (ownerSigner instanceof BrowserWalletSigner) {
      return {
        txSubmitter: ownerSigner,
        source: TX_SUBMITTER_SOURCES.BROWSER_WALLET_OWNER,
        account: null,
      };
    }
    if (typeof ownerSigner.privateKey !== "string") {
      return {
        txSubmitter: await requireBrowserWalletSigner({
          role: "wallet owner L1 submitter",
          expectedAddress: ownerSigner.address,
          provider,
        }),
        source: TX_SUBMITTER_SOURCES.BROWSER_WALLET_OWNER,
        account: null,
      };
    }
    return {
      txSubmitter: ownerSigner,
      source: TX_SUBMITTER_SOURCES.WALLET_OWNER,
      account: null,
    };
  }
  if (isValueLessOption(args.txSubmitter)) {
    return {
      txSubmitter: await requireBrowserWalletSigner({
        role: "L1 transaction submitter",
        provider,
      }),
      source: TX_SUBMITTER_SOURCES.BROWSER_WALLET,
      account: null,
    };
  }
  const networkName = requireNetworkName(args);
  const account = requireAccountOptionValue(args.txSubmitter, "--tx-submitter");
  return {
    txSubmitter: new Wallet(
      normalizePrivateKey(readSecretFile(accountPrivateKeyPath(networkName, account), "--tx-submitter")),
      provider,
    ),
    source: TX_SUBMITTER_SOURCES.TX_SUBMITTER_ACCOUNT,
    account,
  };
}

function resolvePrivateKeySource(args) {
  const networkName = requireNetworkName(args);
  const account = requireAccountName(args);
  return normalizePrivateKey(readSecretFile(accountPrivateKeyPath(networkName, account), "--account"));
}

function resolveL1AccountMode(args) {
  if (args.account === undefined) {
    return {
      mode: L1_SIGNER_MODES.BROWSER_WALLET,
      account: null,
    };
  }
  return {
    mode: L1_SIGNER_MODES.LOCAL_ACCOUNT,
    account: requireAccountName(args),
  };
}

function isValueLessOption(value) {
  return value === true || (typeof value === "string" && value.trim() === "");
}

function requireAccountOptionValue(value, label) {
  if (value === undefined || value === null || value === "" || value === true) {
    throw new Error(`${label} requires a local account name.`);
  }
  const normalized = String(value).trim();
  if (normalized.length === 0) {
    throw new Error(`${label} requires a local account name.`);
  }
  return normalized;
}

async function requireBrowserWalletSigner({ role, expectedAddress = null, provider = null } = {}) {
  if (isJsonOutputRequested()) {
    throw new Error(
      [
        `Browser wallet signing for ${role} requires interactive human approval and cannot run in --json mode.`,
        "Run the same command without --json so the CLI can open the local browser signing page.",
      ].join(" "),
    );
  }
  return await BrowserWalletSigner.connect({
    role,
    expectedAddress,
    provider,
  });
}

function browserWalletSafeRejectCopy() {
  return "Approve or reject in MetaMask whenever you're ready.";
}

function browserWalletAccountRequirement(expectedAddress, fallbackAddress = null) {
  const address = expectedAddress ?? fallbackAddress;
  return address ? `Use account ${getAddress(address)}.` : "Use the MetaMask account you want for this command.";
}

function browserWalletNetworkRequirement(expectedChainId) {
  return expectedChainId ? `Use the selected network, chain ${expectedChainId}.` : "";
}

function browserWalletOperationTitle(operationName) {
  switch (operationName) {
    case "account deposit-bridge":
      return "Add funds to the bridge";
    case "account withdraw-bridge":
      return "Withdraw bridge funds";
    case "channel create":
      return "Create channel";
    case "channel set-workspace-mirror":
      return "Update channel mirror";
    case "channel abandon-operation":
      return "Stop new channel activity";
    case "channel join":
      return "Join channel";
    case "channel exit":
      return "Exit channel";
    case "wallet deposit-channel":
      return "Move funds into channel";
    case "wallet withdraw-channel":
      return "Move funds out of channel";
    case "wallet mint-notes":
      return "Create private notes";
    case "wallet transfer-notes":
      return "Send private notes";
    case "wallet redeem-notes":
      return "Redeem private note";
    default:
      return "Send transaction";
  }
}

function browserWalletOperationEffect(operationName) {
  switch (operationName) {
    case "account deposit-bridge":
      return "If you approve, MetaMask sends the bridge funding transaction you reviewed in the terminal.";
    case "account withdraw-bridge":
      return "If you approve, MetaMask sends the withdrawal transaction back to your Ethereum account.";
    case "channel create":
      return "If you approve, MetaMask creates this channel on Ethereum.";
    case "channel set-workspace-mirror":
      return "If you approve, MetaMask updates the channel mirror URL on Ethereum.";
    case "channel abandon-operation":
      return "If you approve, MetaMask stops new joins and new channel deposits for this channel.";
    case "channel join":
      return "If you approve, MetaMask registers your channel wallet on Ethereum.";
    case "channel exit":
      return "If you approve, MetaMask exits this channel wallet and the CLI marks the wallet epoch as exited.";
    case "wallet deposit-channel":
      return "If you approve, MetaMask moves bridge balance into your channel balance.";
    case "wallet withdraw-channel":
      return "If you approve, MetaMask moves channel balance back to your bridge balance.";
    case "wallet mint-notes":
      return "If you approve, MetaMask submits the private note transaction prepared by the CLI.";
    case "wallet transfer-notes":
      return "If you approve, MetaMask submits the private note transfer prepared by the CLI.";
    case "wallet redeem-notes":
      return "If you approve, MetaMask submits the note redemption prepared by the CLI.";
    default:
      return "If you approve, MetaMask sends the Ethereum transaction prepared by the CLI.";
  }
}

function browserWalletTransactionTargetSummary(params) {
  const tx = params?.[0] ?? {};
  const lines = [];
  if (tx.from) {
    lines.push(`From ${getAddress(tx.from)}.`);
  }
  if (tx.to) {
    lines.push(`To ${getAddress(tx.to)}.`);
  }
  if (tx.value && ethers.toBigInt(tx.value) > 0n) {
    lines.push(`Value ${ethers.formatEther(tx.value)} ETH.`);
  }
  return lines.join(" ");
}

function browserWalletNoteParagraphs({ purpose, result, reassurance }) {
  return [purpose, result, reassurance].filter((text) => typeof text === "string" && text.trim().length > 0);
}

function buildBrowserWalletRequestExplanation({
  role,
  action,
  method,
  params,
  expectedAddress = null,
  expectedChainId = null,
  transactionContext = null,
  diagnostics = null,
}) {
  const operationName = transactionContext?.operationName ?? null;
  const channelName = transactionContext?.channelName ?? null;
  const signerAddress = diagnostics?.signerAddress ?? params?.[0]?.from ?? null;
  if (method === "eth_requestAccounts") {
    const purpose = "MetaMask is asking which account you want to use for this command.";
    const result = "If you approve, the CLI will use that address for this run.";
    const reassurance = "Your MetaMask private key stays inside MetaMask, and this page never sees it. Approve or reject in MetaMask when you're ready.";
    return {
      title: "Connect your wallet",
      noteParagraphs: browserWalletNoteParagraphs({ purpose, result, reassurance }),
      whatThisDoes: purpose,
      approvalEffect: result,
      publicDisclosure: "No Ethereum transaction is sent by connecting.",
      privacyEffect: reassurance,
      accountRequirement: browserWalletAccountRequirement(expectedAddress),
      networkRequirement: browserWalletNetworkRequirement(expectedChainId),
      safeToReject: browserWalletSafeRejectCopy(),
    };
  }
  if (method === "eth_chainId") {
    const purpose = "MetaMask is checking that it's on the same network as the command in your terminal.";
    const result = "If the network matches, the CLI can keep going.";
    const reassurance = "This does not send a transaction. Your MetaMask private key stays inside MetaMask, and this page never sees it.";
    return {
      title: action === "recheck network" ? "Check network again" : "Check network",
      noteParagraphs: browserWalletNoteParagraphs({ purpose, result, reassurance }),
      whatThisDoes: purpose,
      approvalEffect: result,
      publicDisclosure: "No Ethereum transaction is sent by this check.",
      privacyEffect: reassurance,
      accountRequirement: browserWalletAccountRequirement(expectedAddress, signerAddress),
      networkRequirement: browserWalletNetworkRequirement(expectedChainId),
      safeToReject: browserWalletSafeRejectCopy(),
    };
  }
  if (method === "wallet_switchEthereumChain") {
    const purpose = "MetaMask is asking to switch to the network selected in your terminal.";
    const result = "If you approve, MetaMask will use that network and the CLI can keep going.";
    const reassurance = "This does not send a transaction or change your channel. Your MetaMask private key stays inside MetaMask.";
    return {
      title: "Switch network",
      noteParagraphs: browserWalletNoteParagraphs({ purpose, result, reassurance }),
      whatThisDoes: purpose,
      approvalEffect: result,
      publicDisclosure: "No Ethereum transaction is sent by switching networks.",
      privacyEffect: reassurance,
      accountRequirement: browserWalletAccountRequirement(expectedAddress, signerAddress),
      networkRequirement: browserWalletNetworkRequirement(expectedChainId),
      safeToReject: browserWalletSafeRejectCopy(),
    };
  }
  if (method === "personal_sign") {
    const purpose = "MetaMask is asking for a signature so the CLI can set up your channel wallet.";
    const result = "This does not send a transaction. It just helps the CLI set up this channel wallet on your computer.";
    const reassurance = "Your MetaMask private key stays inside MetaMask, and this page does not see your wallet secret or private note details. Approve or reject in MetaMask.";
    return {
      title: "Set up your channel wallet",
      noteParagraphs: browserWalletNoteParagraphs({ purpose, result, reassurance }),
      whatThisDoes: purpose,
      approvalEffect: result,
      publicDisclosure: "No Ethereum transaction is sent by this signature.",
      privacyEffect: reassurance,
      accountRequirement: browserWalletAccountRequirement(expectedAddress, signerAddress),
      networkRequirement: browserWalletNetworkRequirement(expectedChainId),
      safeToReject: browserWalletSafeRejectCopy(),
    };
  }
  if (method === "eth_signTypedData_v4") {
    const purpose = "MetaMask is asking for one more signature so the CLI can set up note viewing for this wallet.";
    const result = "This does not send a transaction. It helps the CLI find your notes later.";
    const reassurance = "Your MetaMask private key stays inside MetaMask, and this page does not show your note contents, wallet secret, or private keys. Approve or reject in MetaMask.";
    return {
      title: "Set up note viewing",
      noteParagraphs: browserWalletNoteParagraphs({ purpose, result, reassurance }),
      whatThisDoes: purpose,
      approvalEffect: result,
      publicDisclosure: "No Ethereum transaction is sent by this signature.",
      privacyEffect: reassurance,
      accountRequirement: browserWalletAccountRequirement(expectedAddress, signerAddress),
      networkRequirement: browserWalletNetworkRequirement(expectedChainId),
      safeToReject: browserWalletSafeRejectCopy(),
    };
  }
  if (method === "eth_sendTransaction") {
    const targetSummary = browserWalletTransactionTargetSummary(params);
    const title = browserWalletOperationTitle(operationName);
    const purpose = `${title}. MetaMask is ready to send the transaction you reviewed in the terminal.`;
    const result = browserWalletOperationEffect(operationName);
    const reassurance = "Your MetaMask private key stays inside MetaMask, and this page does not show your wallet secret, private keys, or private note details. Approve or reject in MetaMask.";
    return {
      title,
      noteParagraphs: browserWalletNoteParagraphs({ purpose, result, reassurance }),
      whatThisDoes: channelName
        ? `MetaMask will send the transaction for ${operationName ?? "this command"} on channel ${channelName}.`
        : "MetaMask will send the transaction prepared by the CLI.",
      approvalEffect: result,
      publicDisclosure: "This sends an Ethereum transaction from your selected account.",
      privacyEffect: reassurance,
      accountRequirement: browserWalletAccountRequirement(expectedAddress, signerAddress),
      networkRequirement: browserWalletNetworkRequirement(expectedChainId),
      transactionSummary: targetSummary,
      safeToReject: browserWalletSafeRejectCopy(),
    };
  }
  const purpose = "MetaMask is asking for the wallet step needed by this CLI command.";
  const result = "If you approve, the CLI command can continue.";
  const reassurance = "Your MetaMask private key stays inside MetaMask, and this page never sees it. Approve or reject in MetaMask.";
  return {
    title: action || "Wallet request",
    noteParagraphs: browserWalletNoteParagraphs({ purpose, result, reassurance }),
    whatThisDoes: purpose,
    approvalEffect: result,
    publicDisclosure: "Check MetaMask for whether this request sends a transaction.",
    privacyEffect: reassurance,
    accountRequirement: browserWalletAccountRequirement(expectedAddress, signerAddress),
    networkRequirement: browserWalletNetworkRequirement(expectedChainId),
    safeToReject: browserWalletSafeRejectCopy(),
  };
}

class BrowserWalletSigner {
  static async connect({ role, expectedAddress = null, provider = null } = {}) {
    const accounts = await requestBrowserWallet({
      role,
      action: "connect",
      method: "eth_requestAccounts",
      params: [],
      description: "Connect the browser wallet account that should approve this CLI command.",
      expectedAddress,
    });
    expect(Array.isArray(accounts) && accounts.length > 0, "Browser wallet did not return any account.");
    const address = getAddress(accounts[0]);
    if (expectedAddress) {
      expect(
        ethers.toBigInt(address) === ethers.toBigInt(getAddress(expectedAddress)),
        `Browser wallet selected ${address}, but this command requires ${getAddress(expectedAddress)}.`,
      );
    }
    if (provider) {
      const providerNetwork = await provider.getNetwork();
      const expectedChainId = Number(providerNetwork.chainId);
      const initialWalletChainIdHex = await requestBrowserWallet({
        role,
        action: "check network",
        method: "eth_chainId",
        params: [],
        description: "Verify that the browser wallet is connected to the selected network.",
        expectedChainId,
      });
      let walletChainId = Number(ethers.toBigInt(initialWalletChainIdHex));
      if (walletChainId !== expectedChainId) {
        await requestBrowserWallet({
          role,
          action: "switch network",
          method: "wallet_switchEthereumChain",
          params: [{ chainId: ethers.toQuantity(expectedChainId) }],
          description: `Switch the browser wallet to the selected network chain ${expectedChainId}.`,
          expectedChainId,
        });
        const switchedWalletChainIdHex = await requestBrowserWallet({
          role,
          action: "recheck network",
          method: "eth_chainId",
          params: [],
          description: "Verify that the browser wallet switched to the selected network.",
          expectedChainId,
        });
        walletChainId = Number(ethers.toBigInt(switchedWalletChainIdHex));
      }
      expect(
        walletChainId === expectedChainId,
        `Browser wallet chain ${walletChainId} does not match selected network chain ${expectedChainId}.`,
      );
    }
    return new BrowserWalletSigner({ address, provider, role });
  }

  constructor({ address, provider = null, role = "L1 account" }) {
    this.address = getAddress(address);
    this.provider = provider;
    this.role = role;
  }

  async getAddress() {
    return this.address;
  }

  connect(provider) {
    return new BrowserWalletSigner({ address: this.address, provider, role: this.role });
  }

  async signMessage(message) {
    return await requestBrowserWallet({
      role: "message signer",
      action: "sign message",
      method: "personal_sign",
      params: [personalSignPayload(message), this.address],
      description: "Approve the message signature required by this private-state CLI command.",
    });
  }

  async signTypedData(domain, types, value) {
    return await requestBrowserWallet({
      role: "typed-data signer",
      action: "sign typed data",
      method: "eth_signTypedData_v4",
      params: [this.address, JSON.stringify(buildEip712Payload({ domain, types, value }))],
      description: "Approve the typed-data signature required by this private-state CLI command.",
    });
  }

  async call(transaction) {
    expect(this.provider, "Browser wallet signer cannot dry-run without a provider.");
    return await this.provider.call({
      ...(await ethers.resolveProperties(transaction)),
      from: this.address,
    });
  }

  async estimateGas(transaction) {
    expect(this.provider, "Browser wallet signer cannot estimate gas without a provider.");
    return await this.provider.estimateGas({
      ...(await ethers.resolveProperties(transaction)),
      from: this.address,
    });
  }

  async resolveName(name) {
    if (this.provider?.resolveName) {
      return await this.provider.resolveName(name);
    }
    return name;
  }

  async sendTransaction(transaction) {
    expect(this.provider, "Browser wallet signer cannot submit transactions without a provider.");
    const tx = normalizeBrowserTransaction({
      ...(await ethers.resolveProperties(transaction)),
      from: this.address,
    });
    const hash = await requestBrowserWallet({
      role: this.role,
      action: "send transaction",
      method: "eth_sendTransaction",
      params: [tx],
      description: "Approve the Ethereum transaction for this private-state CLI command.",
      diagnostics: {
        signerAddress: this.address,
      },
      transactionContext: currentBrowserWalletTransactionContext,
    });
    return {
      hash,
      wait: async () => {
        const receipt = await this.provider.waitForTransaction(hash);
        expect(receipt, `Transaction ${hash} was not mined before the provider wait returned.`);
        return receipt;
      },
    };
  }
}

let browserWalletBridgeSession = null;
let currentBrowserWalletTransactionContext = null;

async function withBrowserWalletTransactionContext(context, callback) {
  const previous = currentBrowserWalletTransactionContext;
  currentBrowserWalletTransactionContext = context;
  try {
    return await callback();
  } finally {
    currentBrowserWalletTransactionContext = previous;
  }
}

function getBrowserWalletBridgeSession() {
  if (!browserWalletBridgeSession) {
    browserWalletBridgeSession = new BrowserWalletBridgeSession();
  }
  return browserWalletBridgeSession;
}

async function requestBrowserWallet(request) {
  return await getBrowserWalletBridgeSession().request(request);
}

async function closeBrowserWalletBridgeSession() {
  const session = browserWalletBridgeSession;
  browserWalletBridgeSession = null;
  if (session) {
    await session.close();
  }
}

class BrowserWalletBridgeSession {
  constructor() {
    this.token = ethers.hexlify(randomBytes(24));
    this.server = null;
    this.ready = null;
    this.pending = null;
    this.pageOpened = false;
    this.closing = false;
    this.sockets = new Set();
    this.requestWaiters = new Set();
  }

  async request({
    role,
    action,
    method,
    params,
    description,
    expectedAddress = null,
    expectedChainId = null,
    transactionContext = null,
    diagnostics = null,
  }) {
    await this.ensureStarted();
    expect(!this.closing, "Browser wallet bridge is closing.");
    expect(!this.pending, "Browser wallet bridge already has a pending request.");
    const requestId = ethers.hexlify(randomBytes(12));
    const address = this.server.address();
    if (!address || typeof address === "string") {
      throw new Error("Could not determine local browser wallet signing server address.");
    }
    const signingUrl = `http://127.0.0.1:${address.port}/sign?token=${encodeURIComponent(this.token)}`;
    const resultPromise = new Promise((resolve, reject) => {
      this.pending = {
        requestId,
        role,
        action,
        method,
        params,
        description,
        explanation: buildBrowserWalletRequestExplanation({
          role,
          action,
          method,
          params,
          expectedAddress,
          expectedChainId,
          transactionContext,
          diagnostics,
        }),
        diagnostics,
        signingUrl,
        settled: false,
        relayLoaded: false,
        providerRequestStarted: false,
        deliveredAt: null,
        pageReopenAttempted: false,
        pageLoadReminder: null,
        requestStartReminder: null,
        timeout: null,
        resolve,
        reject,
      };
    });
    this.notifyRequestWaiters();
    const pending = this.pending;
    pending.timeout = setTimeout(() => {
      this.rejectPending(new Error(`Timed out waiting for browser wallet ${action}.`));
    }, 10 * 60 * 1000);
    pending.pageLoadReminder = setTimeout(() => {
      if (!pending.settled && !pending.relayLoaded) {
        const reopened = !pending.pageReopenAttempted && openUrlInDefaultBrowser(signingUrl).opened;
        pending.pageReopenAttempted = pending.pageReopenAttempted || reopened;
        this.pageOpened = this.pageOpened || reopened;
        process.stderr.write([
          "Browser wallet relay page has not picked up the current request.",
          reopened
            ? "The CLI reopened the same Signing URL in the default browser. Approve or reject only in the wallet UI."
            : "Open or refresh the Signing URL in the MetaMask-capable browser you want to use:",
          signingUrl,
          "",
        ].join("\n"));
      }
    }, 15_000);
    this.scheduleRequestStartReminder(pending);
    const browser = this.pageOpened
      ? { opened: true }
      : openUrlInDefaultBrowser(signingUrl);
    this.pageOpened = this.pageOpened || browser.opened;
    process.stderr.write([
      `Browser wallet approval required: ${action}.`,
      `Signing URL: ${signingUrl}`,
      this.pageOpened
        ? "Browser relay page is open. Approve or reject only in the browser wallet UI."
        : "If the signing page is not already open, copy the Signing URL into a MetaMask-capable browser.",
      "The localhost page is only a wallet-request relay and has no approval button.",
      "User-Controlled AI Agents must not approve wallet requests in the wallet UI for the user.",
      "",
    ].join("\n"));
    return await resultPromise;
  }

  async ensureStarted() {
    if (this.ready) {
      return await this.ready;
    }
    this.closing = false;
    this.server = http.createServer(async (request, response) => {
      await this.handleRequest(request, response);
    });
    this.server.on("connection", (socket) => {
      this.sockets.add(socket);
      socket.on("close", () => {
        this.sockets.delete(socket);
      });
    });
    this.server.on("error", (error) => {
      this.rejectPending(error);
    });
    this.ready = new Promise((resolve, reject) => {
      this.server.listen(0, "127.0.0.1", () => {
        this.server.unref();
        resolve();
      });
      this.server.once("error", reject);
    });
    return await this.ready;
  }

  async close() {
    if (this.pending && !this.pending.settled) {
      this.rejectPending(new Error("Browser wallet bridge closed before the wallet request completed."));
    }
    this.closing = true;
    this.notifyRequestWaiters();
    await sleep(500);
    const server = this.server;
    this.server = null;
    this.ready = null;
    this.pageOpened = false;
    this.notifyRequestWaiters();
    for (const socket of this.sockets) {
      socket.destroy();
    }
    this.sockets.clear();
    if (server?.listening) {
      await new Promise((resolve) => {
        server.close(() => resolve());
      });
    }
  }

  async handleRequest(request, response) {
    try {
      const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
      if (request.method === "GET" && requestUrl.pathname === "/sign") {
        if (requestUrl.searchParams.get("token") !== this.token) {
          writeBrowserTermsResponse(response, 403, "text/plain; charset=utf-8", "Invalid browser wallet token.");
          return;
        }
        writeBrowserTermsResponse(
          response,
          200,
          "text/html; charset=utf-8",
          browserWalletSigningHtml({
            token: this.token,
          }),
        );
        return;
      }
      if (request.method === "GET" && requestUrl.pathname === "/request") {
        if (requestUrl.searchParams.get("token") !== this.token) {
          writeBrowserTermsResponse(response, 403, "text/plain; charset=utf-8", "Invalid browser wallet token.");
          return;
        }
        if (this.closing) {
          this.writeCompletionResponse(response);
          return;
        }
        if (!this.pending) {
          await this.waitForPendingRequest();
        }
        if (this.closing) {
          this.writeCompletionResponse(response);
          return;
        }
        if (!this.pending) {
          writeBrowserTermsResponse(response, 204, "application/json; charset=utf-8", "");
          return;
        }
        if (!this.canDeliverPendingRequest(this.pending)) {
          writeBrowserTermsResponse(response, 204, "application/json; charset=utf-8", "");
          return;
        }
        this.pending.deliveredAt = Date.now();
        writeBrowserTermsResponse(
          response,
          200,
          "application/json; charset=utf-8",
          JSON.stringify({
            requestId: this.pending.requestId,
            role: this.pending.role,
            action: this.pending.action,
            method: this.pending.method,
            params: this.pending.params,
            description: this.pending.description,
            explanation: this.pending.explanation,
            diagnostics: this.pending.diagnostics,
          }),
        );
        return;
      }
      if (request.method === "POST" && requestUrl.pathname === "/status") {
        const payload = JSON.parse(await readRequestBodyText(request));
        if (payload.token !== this.token) {
          writeBrowserTermsResponse(response, 400, "text/plain; charset=utf-8", "Browser wallet status was invalid.");
          return;
        }
        const pending = this.requireMatchingPendingRequest(payload.requestId);
        this.recordStatus(pending, payload.event);
        writeBrowserTermsResponse(response, 204, "text/plain; charset=utf-8", "");
        return;
      }
      if (request.method === "POST" && requestUrl.pathname === "/result") {
        const payload = JSON.parse(await readRequestBodyText(request));
        if (payload.token !== this.token) {
          writeBrowserTermsResponse(response, 400, "text/plain; charset=utf-8", "Browser wallet response was invalid.");
          return;
        }
        const pending = this.requireMatchingPendingRequest(payload.requestId);
        writeBrowserTermsResponse(
          response,
          200,
          "text/html; charset=utf-8",
          browserWalletResultHtml(Boolean(payload.ok)),
        );
        if (payload.ok) {
          this.resolvePending(pending, payload.result);
        } else {
          this.rejectPending(new Error(formatBrowserWalletFailure(pending.action, payload)));
        }
        return;
      }
      writeBrowserTermsResponse(response, 404, "text/plain; charset=utf-8", "Not found.");
    } catch (error) {
      writeBrowserTermsResponse(response, 500, "text/plain; charset=utf-8", `Browser wallet signing error: ${error.message}`);
      this.rejectPending(error);
    }
  }

  requireMatchingPendingRequest(requestId) {
    if (!this.pending || this.pending.requestId !== requestId) {
      throw new Error("No matching browser wallet request is active.");
    }
    return this.pending;
  }

  waitForPendingRequest() {
    if (this.pending || !this.server || this.closing) {
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      const waiter = {
        resolve,
        timeout: null,
      };
      waiter.timeout = setTimeout(() => {
        this.requestWaiters.delete(waiter);
        resolve();
      }, 25_000);
      this.requestWaiters.add(waiter);
    });
  }

  notifyRequestWaiters() {
    const waiters = [...this.requestWaiters];
    this.requestWaiters.clear();
    for (const waiter of waiters) {
      if (waiter.timeout) {
        clearTimeout(waiter.timeout);
      }
      waiter.resolve();
    }
  }

  canDeliverPendingRequest(pending) {
    if (pending.providerRequestStarted) {
      return false;
    }
    if (!pending.deliveredAt || pending.relayLoaded) {
      return true;
    }
    return Date.now() - pending.deliveredAt > 5_000;
  }

  writeCompletionResponse(response) {
    writeBrowserTermsResponse(
      response,
      200,
      "application/json; charset=utf-8",
      JSON.stringify({
        done: true,
        message: "Command finished. You can return to the terminal.",
      }),
    );
  }

  recordStatus(pending, event) {
    if (event === "loaded" && !pending.relayLoaded) {
      pending.relayLoaded = true;
    }
    if (event === "request-started" && !pending.providerRequestStarted) {
      pending.providerRequestStarted = true;
      this.clearRequestStartReminder(pending);
    }
  }

  scheduleRequestStartReminder(pending) {
    this.clearRequestStartReminder(pending);
    pending.requestStartReminder = setTimeout(() => {
      if (!pending.settled && pending.relayLoaded && !pending.providerRequestStarted) {
        process.stderr.write([
          "Browser wallet relay page loaded, but the provider request has not started.",
          "Refresh the signing page or open the Signing URL in a MetaMask-capable browser:",
          pending.signingUrl,
          "",
        ].join("\n"));
      }
    }, 15_000);
  }

  clearRequestStartReminder(pending) {
    if (pending.requestStartReminder) {
      clearTimeout(pending.requestStartReminder);
      pending.requestStartReminder = null;
    }
  }

  clearPendingTimers(pending) {
    if (pending.timeout) {
      clearTimeout(pending.timeout);
    }
    if (pending.pageLoadReminder) {
      clearTimeout(pending.pageLoadReminder);
    }
    this.clearRequestStartReminder(pending);
  }

  resolvePending(pending, result) {
    if (pending.settled) return;
    pending.settled = true;
    this.clearPendingTimers(pending);
    this.pending = null;
    pending.resolve(result);
  }

  rejectPending(error) {
    const pending = this.pending;
    if (!pending || pending.settled) return;
    pending.settled = true;
    this.clearPendingTimers(pending);
    this.pending = null;
    pending.reject(error);
  }
}

function formatBrowserWalletFailure(action, payload) {
  const walletError = normalizeBrowserWalletError(payload.error);
  const lines = [
    `Browser wallet ${action} failed: ${walletError.message}`,
  ];
  if (walletError.code !== null) {
    lines.push(`Wallet error code: ${walletError.code}`);
  }
  if (walletError.data !== null) {
    lines.push(`Wallet error data: ${walletError.data}`);
  }
  const diagnostics = payload.diagnostics && typeof payload.diagnostics === "object"
    ? payload.diagnostics
    : null;
  if (diagnostics) {
    lines.push("Browser wallet diagnostics:");
    if (diagnostics.provider?.isMetaMask !== undefined) {
      lines.push(`  provider.isMetaMask: ${String(Boolean(diagnostics.provider.isMetaMask))}`);
    }
    if (diagnostics.preflight?.ethAccounts !== undefined) {
      lines.push(`  eth_accounts: ${formatBrowserDiagnosticValue(diagnostics.preflight.ethAccounts)}`);
    }
    if (diagnostics.preflight?.ethChainId !== undefined) {
      lines.push(`  eth_chainId: ${formatBrowserDiagnosticValue(diagnostics.preflight.ethChainId)}`);
    }
    if (diagnostics.transaction?.from !== undefined) {
      lines.push(`  transaction.from: ${formatBrowserDiagnosticValue(diagnostics.transaction.from)}`);
    }
    if (diagnostics.transaction?.to !== undefined) {
      lines.push(`  transaction.to: ${formatBrowserDiagnosticValue(diagnostics.transaction.to)}`);
    }
    if (diagnostics.transaction?.value !== undefined) {
      lines.push(`  transaction.value: ${formatBrowserDiagnosticValue(diagnostics.transaction.value)}`);
    }
    if (diagnostics.transaction?.dataByteLength !== undefined) {
      lines.push(`  transaction.dataByteLength: ${formatBrowserDiagnosticValue(diagnostics.transaction.dataByteLength)}`);
    }
    if (diagnostics.signerAddress !== undefined) {
      lines.push(`  signerAddress: ${formatBrowserDiagnosticValue(diagnostics.signerAddress)}`);
    }
  }
  return lines.join("\n");
}

function normalizeBrowserWalletError(error) {
  if (error && typeof error === "object") {
    return {
      code: error.code ?? null,
      message: String(error.message ?? "unknown error"),
      data: error.data === undefined ? null : formatBrowserDiagnosticValue(error.data),
    };
  }
  return {
    code: null,
    message: String(error ?? "unknown error"),
    data: null,
  };
}

function formatBrowserDiagnosticValue(value) {
  if (value === null) return "null";
  if (value === undefined) return "undefined";
  if (typeof value === "string") {
    if (value.startsWith("0x") && value.length > 130) {
      return `<hex ${hexStringByteLength(value)} bytes>`;
    }
    return value.length > 320 ? `${value.slice(0, 317)}...` : value;
  }
  try {
    const json = JSON.stringify(value, (key, entry) => {
      if (
        typeof entry === "string"
        && entry.startsWith("0x")
        && entry.length > 130
        && /^(data|input|calldata|transactionData)$/iu.test(key)
      ) {
        return `<hex ${hexStringByteLength(entry)} bytes>`;
      }
      return entry;
    });
    if (json === undefined) {
      return String(value);
    }
    return json.length > 320 ? `${json.slice(0, 317)}...` : json;
  } catch {
    return String(value);
  }
}

function hexStringByteLength(value) {
  return Math.ceil(Math.max(String(value).length - 2, 0) / 2);
}

function browserWalletSigningHtml({ token }) {
  const requestJson = safeJsonForScript({ token });
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Private-State Browser Wallet Request Relay</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: Canvas; color: CanvasText; }
    main { max-width: 760px; margin: 0 auto; padding: 32px 20px; }
    .panel { border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); border-radius: 8px; padding: 20px; }
    pre { overflow: auto; padding: 12px; border-radius: 6px; background: color-mix(in srgb, CanvasText 8%, transparent); }
    .muted { color: color-mix(in srgb, CanvasText 70%, transparent); }
    .request-copy { display: grid; gap: 12px; margin: 16px 0; font-size: 1.02rem; line-height: 1.5; }
    .request-copy p { margin: 0; }
  </style>
</head>
<body>
  <main>
    <section class="panel">
      <h1>Browser Wallet Request Relay</h1>
      <p id="description">Waiting for the next CLI wallet request.</p>
      <div id="meta" class="request-copy"></div>
      <p id="status" class="muted">Keep this page open. Approve or reject only in your wallet UI.</p>
      <details>
        <summary>Request details</summary>
        <pre id="details">{}</pre>
      </details>
    </section>
  </main>
  <script>
    const request = ${requestJson};
    const status = document.getElementById("status");
    const description = document.getElementById("description");
    const meta = document.getElementById("meta");
    const details = document.getElementById("details");
    let requestReadFailureStartedAt = null;
    function clearNode(node) {
      while (node.firstChild) node.removeChild(node.firstChild);
    }
    function appendNoteParagraph(parent, value) {
      if (!value) return;
      const line = document.createElement("p");
      line.appendChild(document.createTextNode(value));
      parent.appendChild(line);
    }
    function renderRequestExplanation(activeRequest) {
      const explanation = activeRequest.explanation || {};
      description.textContent = explanation.title || activeRequest.description || "Review the MetaMask request";
      clearNode(meta);
      const paragraphs = Array.isArray(explanation.noteParagraphs) && explanation.noteParagraphs.length > 0
        ? explanation.noteParagraphs
        : [explanation.whatThisDoes, explanation.approvalEffect, explanation.privacyEffect, explanation.safeToReject];
      for (const paragraph of paragraphs) {
        appendNoteParagraph(meta, paragraph);
      }
    }
    function noteRequestReadSuccess() {
      requestReadFailureStartedAt = null;
    }
    async function post(activeRequest, payload) {
      await fetch("/result", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ token: request.token, requestId: activeRequest.requestId, ...payload }),
      });
    }
    async function postStatus(activeRequest, event) {
      await fetch("/status", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ token: request.token, requestId: activeRequest.requestId, event }),
      });
    }
    async function readNextRequest() {
      let response;
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 30_000);
      try {
        response = await fetch("/request?token=" + encodeURIComponent(request.token), {
          cache: "no-store",
          signal: controller.signal,
        });
      } catch {
        const now = Date.now();
        requestReadFailureStartedAt = requestReadFailureStartedAt ?? now;
        status.textContent = now - requestReadFailureStartedAt > 60_000
          ? "The CLI relay is not responding. Check the terminal for the command result."
          : "Waiting for the CLI relay to respond...";
        return null;
      } finally {
        clearTimeout(timeout);
      }
      noteRequestReadSuccess();
      if (response.status === 204) {
        return null;
      }
      if (!response.ok) {
        throw new Error("Unable to read the next browser wallet request.");
      }
      return await response.json();
    }
    function markComplete(message) {
      description.textContent = "Command finished.";
      clearNode(meta);
      status.textContent = message || "You can return to the terminal.";
      details.textContent = "{}";
    }
    function markRelayStopped(error) {
      description.textContent = "Browser wallet relay stopped.";
      clearNode(meta);
      status.textContent = "The relay could not contact the CLI. Check the terminal for the command result.";
      details.textContent = JSON.stringify({
        error: error && error.message ? error.message : String(error),
      }, null, 2);
    }
    async function waitForEthereumProvider() {
      const startedAt = Date.now();
      while (Date.now() - startedAt < 5000) {
        if (window.ethereum && typeof window.ethereum.request === "function") {
          return window.ethereum;
        }
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      return null;
    }
    function hexDataByteLength(value) {
      if (typeof value !== "string" || !value.startsWith("0x")) return null;
      return Math.ceil(Math.max(value.length - 2, 0) / 2);
    }
    function transactionDiagnostics(activeRequest) {
      const tx = activeRequest.params && activeRequest.params[0] ? activeRequest.params[0] : {};
      return {
        from: tx.from ?? null,
        to: tx.to ?? null,
        value: tx.value ?? null,
        dataByteLength: hexDataByteLength(tx.data),
      };
    }
    function sanitizeWalletErrorData(data) {
      if (data === undefined) return null;
      if (typeof data === "string" && data.startsWith("0x") && data.length > 130) {
        return "<hex " + hexDataByteLength(data) + " bytes>";
      }
      try {
        const json = JSON.stringify(data, (key, value) => {
          if (
            typeof value === "string"
            && value.startsWith("0x")
            && value.length > 130
            && /^(data|input|calldata|transactionData)$/iu.test(key)
          ) {
            return "<hex " + hexDataByteLength(value) + " bytes>";
          }
          return value;
        });
        return json && json.length > 1000 ? json.slice(0, 997) + "..." : JSON.parse(json);
      } catch {
        const text = String(data);
        return text.length > 1000 ? text.slice(0, 997) + "..." : text;
      }
    }
    function serializeWalletError(error) {
      return {
        code: error && error.code !== undefined ? error.code : null,
        message: error && error.message ? error.message : String(error),
        data: error ? sanitizeWalletErrorData(error.data) : null,
      };
    }
    async function safeProviderRequest(provider, method, params) {
      try {
        return { ok: true, value: await provider.request({ method, params }) };
      } catch (error) {
        return { ok: false, error: serializeWalletError(error) };
      }
    }
    async function collectTransactionFailureDiagnostics(provider, activeRequest) {
      if (activeRequest.method !== "eth_sendTransaction") {
        return null;
      }
      const accounts = await safeProviderRequest(provider, "eth_accounts", []);
      const chainId = await safeProviderRequest(provider, "eth_chainId", []);
      return {
        provider: {
          isMetaMask: Boolean(provider.isMetaMask),
        },
        preflight: {
          ethAccounts: accounts.ok ? accounts.value : { error: accounts.error },
          ethChainId: chainId.ok ? chainId.value : { error: chainId.error },
        },
        transaction: transactionDiagnostics(activeRequest),
        signerAddress: activeRequest.diagnostics ? activeRequest.diagnostics.signerAddress : null,
      };
    }
    async function requestWallet(activeRequest) {
      let failureDiagnostics = null;
      try {
        renderRequestExplanation(activeRequest);
        details.textContent = JSON.stringify({ method: activeRequest.method }, null, 2);
        await postStatus(activeRequest, "loaded");
        const provider = await waitForEthereumProvider();
        if (!provider) {
          throw new Error("No MetaMask-compatible browser wallet provider was found.");
        }
        status.textContent = "Waiting for wallet response...";
        await postStatus(activeRequest, "request-started");
        failureDiagnostics = await collectTransactionFailureDiagnostics(provider, activeRequest);
        const result = await provider.request({ method: activeRequest.method, params: activeRequest.params });
        status.textContent = "Wallet response received. Waiting for the next CLI request.";
        await post(activeRequest, { ok: true, result });
      } catch (error) {
        status.textContent = "Request failed. Waiting for the next CLI request.";
        await post(activeRequest, {
          ok: false,
          error: serializeWalletError(error),
          diagnostics: failureDiagnostics,
        });
      }
    }
    async function runRelayLoop() {
      for (;;) {
        const activeRequest = await readNextRequest();
        if (activeRequest && activeRequest.done) {
          markComplete(activeRequest.message);
          return;
        }
        if (activeRequest) {
          await requestWallet(activeRequest);
        } else {
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
      }
    }
    window.addEventListener("load", () => {
      runRelayLoop().catch((error) => {
        markRelayStopped(error);
      });
    });
  </script>
</body>
</html>`;
}

function browserWalletResultHtml(ok) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Private-State Browser Wallet Request Relay</title>
</head>
<body>
  <main>
    <h1>${ok ? "Wallet Response Received" : "Wallet Request Failed"}</h1>
    <p>You can return to the terminal.</p>
  </main>
</body>
</html>`;
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
}

function assertInstallZkEvmArgs(args) {
  assertAllowedCommandSchema(args, "install");
  assertBooleanFlag(args, "readOnly", "install option --read-only");
  assertBooleanFlag(args, "terminalTerms", "install option --terminal-terms");
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
  assertBooleanFlag(args, "includeWalletKeys", "uninstall option --include-wallet-keys");
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

function assertCreatePrivateKeySourceArgs(args) {
  assertAllowedCommandSchema(args, "secret-create-private-key-source");
}

function assertCreateWalletSecretSourceArgs(args) {
  assertAllowedCommandSchema(args, "secret-create-wallet-secret-source");
  assertBooleanFlag(args, "random", "secret create-wallet-secret-source option --random");
}

function assertObserverArgs(args) {
  requireNetworkName(args);
  requireArg(args.channelName, "--channel-name");
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
  assertTxSubmitterArg(args);
  parseAmountVector(args.amounts, {
    allowZeroEntries: true,
    requireAnyPositive: true,
  });
}

function assertRedeemNotesArgs(args) {
  assertAllowedCommandSchema(args, "wallet-redeem-notes");
  assertTxSubmitterArg(args);
  selectRedeemNotesMethod(parseNoteIdVector(args.noteIds).length);
}

function assertTransferNotesArgs(args) {
  assertAllowedCommandSchema(args, "wallet-transfer-notes");
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
  if (isValueLessOption(args.txSubmitter)) {
    return;
  }
  requireAccountOptionValue(args.txSubmitter, "--tx-submitter");
}

function assertWalletGetNotesArgs(args) {
  assertAllowedCommandSchema(args, "wallet-get-notes");
  if (args.exportEvidence !== undefined) {
    requireArg(args.exportEvidence, "--export-evidence");
  }
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

function assertAbandonChannelOperationArgs(args) {
  assertAllowedCommandSchema(args, "channel-abandon-operation");
}

function assertDepositBridgeArgs(args) {
  assertAllowedCommandSchema(args, "account-deposit-bridge");
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
  cliOutput.result(buildHelpCommandsResult());
}

function buildHelpCommandsResult() {
  return {
    action: "help commands",
    commands: PRIVATE_STATE_CLI_COMMANDS.map(buildHelpCommandEntry),
    secretSourceOptions: [
      "Use account import --private-key-file once to create a protected local account secret.",
      "Ethereum signing commands use --account <ACCOUNT> for a local account, or omit --account to use a browser wallet when supported.",
      "Proof-backed note commands use --tx-submitter <ACCOUNT> for a local submitter, or --tx-submitter without a value for browser-wallet submission.",
      "A wallet secret source file is arbitrary high-entropy secret text read once by channel join.",
      "Configure each network RPC endpoint once with set rpc.",
      "Wallet commands use separate protected viewing-key and spending-key files when those capabilities are needed.",
      "Source files passed to --private-key-file and --wallet-secret-path are not required to use 0600 permissions, but canonical CLI secret files remain protected.",
    ],
    globalOptions: [
      {
        option: "--version",
        description: "Print the private-state CLI package version and exit.",
      },
      {
        option: "--json",
        description: "Print the final success or failure result as JSON on stdout. Progress, warning, and info events are JSONL on stderr.",
      },
      {
        option: "--help",
        description: "Show this help. Equivalent to help commands.",
      },
    ],
  };
}

function buildHelpCommandEntry(command) {
  const requiredFields = privateStateCliCommandRequiredOptionKeys(command);
  const fields = command.fields ?? [];
  return {
    id: command.id,
    display: privateStateCliCommandDisplay(command),
    synopsis: privateStateCliCommandSynopsis(command),
    description: command.description,
    usage: command.usage,
    fields,
    requiredFields,
    optionalFields: fields.filter((field) => !requiredFields.includes(field)),
    installMode: privateStateCliCommandInstallMode(command),
    help: command.help ?? [],
  };
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
  doctor: printDoctorHumanReport,
  guide: printGuideHumanResult,
  "help commands": printHelpCommandsHumanResult,
  install: printInstallHumanResult,
  investigator: printInvestigatorHumanResult,
  observer: printObserverHumanResult,
  "transaction-fees": printTransactionFeesHumanResult,
  update: printUpdateHumanResult,
  version: printVersionHumanResult,
});

function normalizePrivateKey(value) {
  return value.startsWith("0x") ? value : `0x${value}`;
}

const cliOutput = Object.freeze({
  result(value) {
    const normalized = normalizeCliOutput(value);
    if (isJsonOutputRequested()) {
      console.log(JSON.stringify(buildJsonSuccessPayload(normalized), null, 2));
      return;
    }
    const renderer = HUMAN_RESULT_RENDERERS[normalized?.action];
    if (renderer) {
      renderer(normalized);
      return;
    }
    printHumanResult(normalized);
  },
  error(error, args = {}) {
    if (isJsonOutputRequested()) {
      console.log(JSON.stringify(normalizeCliOutput(buildJsonErrorPayload(error, args)), null, 2));
      return;
    }
    console.error(formatHumanError(error, args));
  },
  progress(action, phase, details = {}) {
    emitOutputEvent({
      event: "progress",
      action,
      phase,
      message: details.message ?? `[${action}] ${phase}`,
      details,
    });
  },
  warning(kind, message, details = {}) {
    emitOutputEvent({
      event: "warning",
      kind,
      message,
      details,
    });
  },
});

function buildJsonSuccessPayload(value) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return Object.hasOwn(value, "ok") ? value : { ok: true, ...value };
  }
  return {
    ok: true,
    action: "result",
    value,
  };
}

function emitOutputEvent(event) {
  const normalized = normalizeCliOutput({
    timestamp: new Date().toISOString(),
    ...event,
  });
  if (isJsonOutputRequested()) {
    console.error(JSON.stringify(normalized));
    return;
  }
  const message = event.message ?? `[${event.action ?? event.kind ?? "cli"}] ${event.phase ?? event.event}`;
  if (event.event === "warning") {
    console.error(message);
    return;
  }
  console.log(message);
}

function printVersionHumanResult(result) {
  console.log(result.version);
}

function printInstallHumanResult(result) {
  const artifactLines = Array.isArray(result.installedDeploymentArtifacts)
    ? result.installedDeploymentArtifacts.map((artifact) => {
      const parts = [
        `chain ${formatHumanValue(artifact.chainId)}`,
        artifact.source ? `source ${artifact.source}` : null,
        artifact.bridgeTimestamp ? `bridge ${artifact.bridgeTimestamp}` : null,
        artifact.dappTimestamp ? `dapp ${artifact.dappTimestamp}` : null,
      ].filter(Boolean);
      return `- ${parts.join("; ")}`;
    })
    : [];
  const lines = [
    "Install complete",
    `Mode: ${formatHumanValue(result.installMode)}`,
    `Terms version: ${formatHumanValue(result.terms?.termsVersion)}`,
    `Terms accepted at: ${formatHumanValue(result.termsAcceptance?.acceptedAt)}`,
    `Tokamak zk-EVM CLI runtime: ${formatPackageVersion(result.tokamakCliRuntime)}`,
    `Groth16 runtime: ${formatPackageVersion(result.groth16Runtime)}`,
    `Docker requested: ${formatHumanValue(Boolean(result.docker))}`,
    `Deployment artifact root: ${formatHumanValue(result.deploymentArtifactRoot)}`,
    `Install manifest: ${formatHumanValue(result.installManifestPath)}`,
  ];
  if (artifactLines.length > 0) {
    lines.push("", "Deployment artifacts", ...artifactLines);
  }
  console.log(lines.join("\n"));
}

function formatPackageVersion(runtime) {
  if (!runtime) {
    return "not installed in this mode";
  }
  const name = runtime.packageName ?? "runtime";
  const version = runtime.packageVersion ?? runtime.version ?? "unknown version";
  return `${name}@${version}`;
}

function printHelpCommandsHumanResult(help) {
  const commandHelp = (help.commands ?? []).map((command) => [
    `  ${command.synopsis}`,
    `      ${command.description}`,
    ...(command.help ?? []).map((line) => `      ${line}`),
  ].join("\n")).join("\n\n");
  const globalOptions = (help.globalOptions ?? []).map((option) => [
    `  ${option.option}`,
    `      ${option.description}`,
  ].join("\n")).join("\n\n");
  console.log(`
Commands:
${commandHelp}

Secret source options:
  Create private-key and wallet-secret source files locally with masked terminal prompts:
      private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
      private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
  Then import the Ethereum account once:
      private-state-cli account import --account <ACCOUNT> --network <NAME> --private-key-file ./ethereum-private-key.txt
  Join a channel with the wallet secret source after reading the channel policy and warning summary:
      private-state-cli channel join --channel-name <NAME> --network <NAME> --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt
  Configure each network RPC endpoint once with set rpc. The CLI has no default RPC URL; if you do not
  already prefer a provider, Ankr is the recommended provider for this workflow:
      private-state-cli set rpc --network mainnet --rpc-url <URL> --provider ankr
  The CLI reads RPC_URL, LOG_CHUNK_SIZE,
  and LOG_REQUESTS_PER_SECOND from ~/tokamak-private-channels/workspace/<network>/rpc-config.env.
  Wallet commands use separate protected viewing-key and spending-key files when those capabilities are needed.
  Source files passed to --private-key-file and --wallet-secret-path are not required to use 0600 permissions, but
  canonical CLI secret files remain protected. On macOS/Linux this means 0600; on Windows the CLI repairs ACLs when possible.

Options:
${globalOptions}
`);
}

function printGuideHumanResult(guide) {
  const selectors = guide.selectors ?? {};
  const guidance = guideHumanGuidance(guide);
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
    "Current status",
    `- ${guidance.status}`,
    "",
    "Next step",
    ...guidance.nextStep,
    "",
    "Run this command",
    guidance.command,
  ];

  if (guidance.after.length > 0) {
    lines.push(
      "",
      "After it succeeds",
      ...guidance.after,
    );
  }

  if (guidance.alternatives.length > 0) {
    lines.push(
      "",
      "If this does not match your situation",
      ...guidance.alternatives.map((alternative) => `- ${alternative}`),
    );
  }

  console.log(lines.join("\n"));
}

function guideHumanGuidance(guide) {
  return {
    status: guideHumanStatus(guide),
    nextStep: guideHumanNextStep(guide),
    command: guideHumanPrimaryCommand(guide),
    after: guideHumanAfterSuccess(guide),
    alternatives: guideHumanAlternatives(guide),
  };
}

function guideHumanStatus(guide) {
  const step = guide.agentGuidance?.step ?? "";
  const network = formatGuideSelector(guide.selectors?.network);
  const channel = formatGuideSelector(guide.selectors?.channelName);
  const account = formatGuideSelector(guide.selectors?.account);
  const wallet = formatGuideSelector(guide.selectors?.wallet);

  switch (step) {
    case "select-network":
      return "No Ethereum network has been selected yet.";
    case "configure-rpc":
      return `The ${network} network is selected, but the CLI has no Ethereum connection URL saved for it.`;
    case "install-runtime":
      return "The selected network is known, but required local CLI files are missing.";
    case "create-private-key-source-and-import-account":
      return `The local account alias ${account} is not connected to an Ethereum account on this computer yet.`;
    case "create-channel":
      return `The channel ${channel} does not exist on-chain.`;
    case "recover-channel-workspace":
      return `The channel ${channel} exists, but this computer has no local channel data for it.`;
    case "create-wallet-secret-source-and-join-channel":
      return `The wallet ${wallet} has not been created locally yet.`;
    case "join-channel-with-existing-wallet-secret-source":
      return "The wallet exists locally, but its Ethereum account is not registered in the channel.";
    case "fund-bridge":
      return "The channel wallet is joined, but it has no bridge funds, channel balance, or private notes available.";
    case "fund-channel":
      return "The Ethereum account has bridge funds, but the channel wallet has no channel balance yet.";
    case "mint-notes":
      return "The channel wallet has channel balance but no private notes to use.";
    case "use-notes":
      return "The wallet has private notes available for inspection before transfer or redemption.";
    case "exit-channel":
      return "The wallet has zero channel balance and appears eligible for channel exit.";
    case "channel-operation-abandoned":
      return `The channel ${channel} is abandoned. New joins and channel deposits are disabled.`;
    case "discover-wallet-name":
      return "The selected wallet name is malformed or not found locally.";
    case "collect-selectors":
      return "The guide needs more public selectors to choose a precise next command.";
    default:
      return formatHumanValue(guide.why);
  }
}

function guideHumanNextStep(guide) {
  const step = guide.agentGuidance?.step ?? "";
  const command = formatHumanValue(guide.nextSafeAction);
  const network = formatGuideSelector(guide.selectors?.network);
  const channel = formatGuideSelector(guide.selectors?.channelName);
  const account = formatGuideSelector(guide.selectors?.account);
  const wallet = formatGuideSelector(guide.selectors?.wallet);

  switch (step) {
    case "select-network":
      return [
        "Choose the Ethereum network first. If you are using real funds, use mainnet.",
        "Use Sepolia or anvil only if you are testing or developing.",
      ];
    case "configure-rpc":
      return [
        `The CLI needs an Ethereum ${network} connection URL before it can check Ethereum and send transactions.`,
        "If you do not already use a provider, Ankr is recommended because its free plan is fast when this CLI checks past Ethereum records.",
        "Ankr is not a default. Create or choose an Ankr URL yourself, copy only that URL, then replace <URL> below.",
      ];
    case "install-runtime":
      return [
        "The CLI runtime files are missing. Install them before trying account, channel, or wallet commands.",
        "After installation, run the doctor command shown below to check that the CLI is ready.",
      ];
    case "create-private-key-source-and-import-account":
      return [
        "First, run the command below. It will ask for your Ethereum private key in the terminal.",
        "Your typing will appear as * characters. The key will be saved to ./ethereum-private-key.txt on this computer.",
      ];
    case "create-channel":
      return [
        `The channel ${channel} is not created yet.`,
        "Stop here unless you are the person who should create this channel.",
        "Only the channel creator should run the command below, because it sets the channel policy, including Join Toll rules for future joiners.",
        "Before running it, read the warning shown by the CLI and continue only if that policy matches your intent.",
      ];
    case "recover-channel-workspace":
      if (String(command).includes("--source mirror")) {
        return [
          `The channel ${channel} exists, but this computer does not have the channel data it needs yet.`,
          "A faster registered recovery source is available. Use the recovery command below first.",
        ];
      }
      return [
        `The channel ${channel} exists, but this computer does not have the channel data it needs yet.`,
        "No faster recovery source was found. The command below rebuilds the channel data from Ethereum history and can take a long time.",
      ];
    case "create-wallet-secret-source-and-join-channel":
      return [
        "Create a wallet secret source file before joining the channel. Type a strong password or passphrase you can keep.",
        "Your typing will appear as * characters. Preserve the file because it may be needed later to recover this channel wallet.",
        "Before joining, make sure the Ethereum account can pay any channel Join Toll directly from that account, plus gas.",
        "After creating the file, read the channel policy and warning summary before running channel join.",
      ];
    case "join-channel-with-existing-wallet-secret-source":
      return [
        "This wallet is not registered in the channel yet.",
        "Before joining, make sure the Ethereum account can pay any channel Join Toll directly from that account, plus gas.",
        "Use your existing wallet secret source file, then read the channel policy and warning summary before joining.",
      ];
    case "fund-bridge":
      return [
        "Start with a public deposit from the Ethereum account into the bridge.",
        "This does not create private notes yet; it only makes funds available for the later channel-balance step.",
        "Read the warning summary before continuing; this sends a public Ethereum mainnet transaction.",
      ];
    case "fund-channel":
      return [
        "The public bridge deposit exists, but this channel wallet does not have channel balance yet.",
        "Move funds into the channel next. After that, you can mint private notes.",
        "Read the warning summary before continuing; this changes public channel accounting.",
      ];
    case "mint-notes":
      return [
        "The channel wallet has channel balance, but it has no private notes to transfer or redeem yet.",
        "Mint private notes from that channel balance before trying to transfer or redeem notes.",
        "Read the warning summary before continuing; note commitments and related public records will be created.",
      ];
    case "use-notes":
      return [
        "This wallet already has private notes.",
        "Inspect the available notes first, then transfer or redeem only notes that appear in that output.",
      ];
    case "exit-channel":
      return [
        "Exit is only for a channel wallet with no remaining channel balance.",
        "Run exit only if you are sure you no longer need this channel wallet.",
      ];
    case "channel-operation-abandoned":
      return [
        `The channel ${channel} no longer accepts new joins or channel deposits.`,
        "Existing registered users can still use private-note activity, redeem notes, withdraw channel balance, and exit when ordinary requirements are met.",
        "Use the command below to inspect the current channel status before choosing any further action.",
      ];
    case "discover-wallet-name":
      return [
        "The wallet name is not valid or not known.",
        "List local wallets and choose one of the names printed by the CLI.",
      ];
    case "collect-selectors":
      return [
        "The guide needs more public information before it can choose one safe next command.",
        "Provide the network, channel name, account alias, and wallet name if you know them.",
      ];
    default:
      return [
        formatHumanValue(guide.why),
      ];
  }
}

function guideHumanPrimaryCommand(guide) {
  const step = guide.agentGuidance?.step ?? "";
  if (step === "use-notes") {
    const getNotesCommand = findGuideCandidateCommand(guide, "wallet get-notes ");
    if (getNotesCommand) {
      return formatGuideCliCommand(getNotesCommand);
    }
  }
  return formatGuideCliCommand(guide.nextSafeAction);
}

function guideHumanAfterSuccess(guide) {
  const step = guide.agentGuidance?.step ?? "";
  const network = guideCommandSelector(guide.selectors?.network, "<NETWORK>");
  const channel = guideCommandSelector(guide.selectors?.channelName, "<CHANNEL>");
  const account = guideCommandSelector(guide.selectors?.account, "<ACCOUNT>");
  const wallet = guideCommandSelector(guide.selectors?.wallet, "<WALLET>");

  switch (step) {
    case "select-network":
      return ["Continue with the next command shown by the guide."];
    case "configure-rpc":
      return [`Rerun: ${formatGuideCliCommand(`help guide --network ${network}`)}`];
    case "install-runtime":
      return [`Run: ${formatGuideCliCommand("help doctor")}`];
    case "create-private-key-source-and-import-account": {
      const importCommand = findGuideCandidateCommand(guide, "account import ")
        ?? `account import --account ${account} --network ${network} --private-key-file ./ethereum-private-key.txt`;
      const verifyCommand = findGuideCandidateCommand(guide, "account get-l1-address ")
        ?? `account get-l1-address --account ${account} --network ${network}`;
      return [
        "Then import the key into a local account alias:",
        formatGuideCliCommand(importCommand),
        "Then confirm the imported Ethereum address:",
        formatGuideCliCommand(verifyCommand),
      ];
    }
    case "create-channel":
      return [`Rerun the guide for the channel: ${formatGuideCliCommand(`help guide --network ${network} --channel-name ${channel}`)}`];
    case "recover-channel-workspace":
      return [`Rerun the guide with the same channel selector: ${formatGuideCliCommand(`help guide --network ${network} --channel-name ${channel}`)}`];
    case "create-wallet-secret-source-and-join-channel": {
      const joinCommand = findGuideCandidateCommand(guide, "channel join ")
        ?? `channel join --channel-name ${channel} --network ${network} --account ${account} --wallet-secret-path ./wallet-secret.txt`;
      return [
        "Then join the channel:",
        formatGuideCliCommand(joinCommand),
      ];
    }
    case "join-channel-with-existing-wallet-secret-source":
      return [`Rerun the guide with the wallet selector: ${formatGuideCliCommand(`help guide --network ${network} --channel-name ${channel} --account ${account} --wallet ${wallet}`)}`];
    case "fund-bridge":
      return ["Then rerun the guide so it can show the channel funding step."];
    case "fund-channel":
      return ["Then rerun the guide so it can show the note minting step."];
    case "mint-notes":
      return [`Then inspect the notes: ${formatGuideCliCommand(`wallet get-notes --wallet ${wallet} --network ${network}`)}`];
    case "use-notes":
      return ["Use note IDs from that output for a later transfer or redeem command."];
    case "exit-channel":
      return ["Keep local wallet evidence files until you are sure no later review or dispute evidence is needed."];
    case "channel-operation-abandoned":
      return ["Do not run channel join or wallet deposit-channel for this Channel."];
    case "discover-wallet-name":
      return [`Rerun the guide with one wallet name printed by the list command: ${formatGuideCliCommand(`help guide --network ${network} --wallet <WALLET>`)}`];
    case "collect-selectors":
      return ["Rerun the guide with the public values you know. Do not include private keys, wallet secrets, or seed phrases."];
    default:
      return [];
  }
}

function guideHumanAlternatives(guide) {
  const step = guide.agentGuidance?.step ?? "";
  if (step !== "create-wallet-secret-source-and-join-channel") {
    return [];
  }
  const randomCommand = findGuideCandidateCommand(guide, "secret create-wallet-secret-source --output ./wallet-secret.txt --random");
  if (!randomCommand) {
    return [];
  }
  return [
    `Only if you explicitly want a random wallet secret and can preserve the file safely: ${formatGuideCliCommand(randomCommand)}`,
  ];
}

function findGuideCandidateCommand(guide, prefix) {
  return (guide.candidateCommands ?? [])
    .find((command) => String(command).startsWith(prefix)) ?? null;
}

function formatGuideCliCommand(command) {
  const value = formatHumanValue(command);
  if (value === "none") {
    return "No command is available yet.";
  }
  return value.startsWith("private-state-cli ") ? value : `private-state-cli ${value}`;
}

function guideCommandSelector(value, placeholder) {
  return value === null || value === undefined || value === "" ? placeholder : String(value);
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
    `Network: ${formatHumanValue(result.network)} (${formatHumanValue(result.chainId)})`,
    `Channel: ${formatHumanValue(result.channelName)}`,
    `URL: ${formatHumanValue(result.url)}`,
  ];
  if (result.source) {
    lines.push(`Source: ${formatHumanValue(result.source)}`);
  }
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
  const lines = [`${humanizeLabel(action)} result`];
  for (const [key, entry] of entries) {
    appendHumanEntry(lines, humanizeLabel(key), entry);
  }
  console.log(lines.join("\n"));
}

function appendHumanEntry(lines, label, value, depth = 0) {
  const indent = "  ".repeat(depth);
  if (isHumanScalar(value)) {
    lines.push(`${indent}${label}: ${formatHumanValue(value)}`);
    return;
  }
  if (Array.isArray(value)) {
    appendHumanArray(lines, label, value, depth);
    return;
  }
  const entries = Object.entries(value ?? {});
  if (entries.length === 0) {
    lines.push(`${indent}${label}: none`);
    return;
  }
  lines.push(`${indent}${label}:`);
  for (const [key, entry] of entries) {
    appendHumanEntry(lines, humanizeLabel(key), entry, depth + 1);
  }
}

function appendHumanArray(lines, label, values, depth) {
  const indent = "  ".repeat(depth);
  if (values.length === 0) {
    lines.push(`${indent}${label}: none`);
    return;
  }
  if (values.every(isHumanScalar)) {
    lines.push(`${indent}${label}: ${values.map(formatHumanValue).join(", ")}`);
    return;
  }
  lines.push(`${indent}${label}:`);
  for (const [index, value] of values.entries()) {
    const itemLabel = `Item ${index + 1}`;
    if (isHumanScalar(value)) {
      lines.push(`${indent}  - ${formatHumanValue(value)}`);
      continue;
    }
    if (Array.isArray(value)) {
      appendHumanArray(lines, itemLabel, value, depth + 1);
      continue;
    }
    lines.push(`${indent}  -`);
    for (const [key, entry] of Object.entries(value ?? {})) {
      appendHumanEntry(lines, humanizeLabel(key), entry, depth + 2);
    }
  }
}

function isHumanScalar(value) {
  return value === null
    || value === undefined
    || typeof value === "string"
    || typeof value === "number"
    || typeof value === "boolean"
    || typeof value === "bigint";
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
  if (Array.isArray(value)) {
    return value.length === 0 ? "none" : `${value.length} item${value.length === 1 ? "" : "s"}`;
  }
  return "see details";
}

function humanizeLabel(value) {
  return String(value)
    .replace(/-/g, " ")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^./u, (letter) => letter.toUpperCase());
}

function emitProgress(action, phase, details = {}) {
  cliOutput.progress(action, phase, details);
}

function createByteDownloadProgress({ action, label, url }) {
  const startedAtMs = Date.now();
  const estimateProgress = createProgressEstimator({ startedAtMs });
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
    const metrics = estimateProgress({
      completedUnits: downloadedBytes,
      totalUnits: totalBytes,
    });
    const percent = metrics.percent !== null
      ? `${metrics.percent.toFixed(1)}%`
      : "unknown";
    const base = [
      `${label}: ${percent}`,
      `${formatByteCount(downloadedBytes)}/${totalBytes !== null ? formatByteCount(totalBytes) : "unknown"}`,
      `${formatByteRate(metrics.ratePerSecond)}`,
      `ETA ${metrics.etaSeconds !== null ? formatDurationSeconds(metrics.etaSeconds) : "unknown"}`,
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

function createProgressEstimator({ startedAtMs = Date.now() } = {}) {
  return ({ completedUnits, totalUnits, nowMs = Date.now() }) => {
    const completed = Math.max(0, finiteNumberOrZero(completedUnits));
    const total = finiteNumberOrNull(totalUnits);
    const resolvedNowMs = Number.isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    const elapsedSeconds = Math.max(0.001, (resolvedNowMs - startedAtMs) / 1000);
    const ratePerSecond = completed / elapsedSeconds;
    const remainingUnits = total !== null ? Math.max(0, total - completed) : null;
    const etaSeconds = remainingUnits !== null && ratePerSecond > 0
      ? remainingUnits / ratePerSecond
      : null;
    const percent = total !== null && total > 0
      ? Math.min(100, (completed * 100) / total)
      : null;
    return {
      elapsedSeconds,
      ratePerSecond,
      remainingUnits,
      etaSeconds,
      percent,
    };
  };
}

function finiteNumberOrZero(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function finiteNumberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function roundedNumberOrNull(value, decimals = 2) {
  const number = Number(value);
  return Number.isFinite(number) ? Number(number.toFixed(decimals)) : null;
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
  const estimateProgress = createProgressEstimator();
  let lastBucket = -1;
  return (event) => {
    const totalBlocks = Math.max(0, finiteNumberOrZero(event.totalBlocks));
    const scannedBlocks = Math.max(0, finiteNumberOrZero(event.scannedBlocks));
    const logsFound = Math.max(0, finiteNumberOrZero(event.logsFound));
    const metrics = estimateProgress({
      completedUnits: scannedBlocks,
      totalUnits: totalBlocks,
    });
    if (event.status === "skipped") {
      emitProgress(
        action,
        `rpc-log-scan ${label}: skipped (no blocks to scan, ${logsFound} logs)`,
        buildRpcLogScanProgressDetails({ event, label, scannedBlocks, totalBlocks, logsFound, metrics }),
      );
      return;
    }
    if (event.status === "start") {
      lastBucket = 0;
      emitProgress(
        action,
        `rpc-log-scan ${label}: 0% (0/${totalBlocks} blocks, ${logsFound} logs, blocks ${event.fromBlock}-${event.toBlock})`,
        buildRpcLogScanProgressDetails({ event, label, scannedBlocks, totalBlocks, logsFound, metrics }),
      );
      return;
    }
    if (event.status === "done") {
      const doneMetrics = {
        ...metrics,
        percent: totalBlocks > 0 ? 100 : metrics.percent,
        remainingUnits: totalBlocks > 0 ? 0 : metrics.remainingUnits,
        etaSeconds: totalBlocks > 0 ? 0 : metrics.etaSeconds,
      };
      emitProgress(
        action,
        `rpc-log-scan ${label}: 100% (${totalBlocks}/${totalBlocks} blocks, ${logsFound} logs, done)`,
        buildRpcLogScanProgressDetails({
          event,
          label,
          scannedBlocks: totalBlocks,
          totalBlocks,
          logsFound,
          metrics: doneMetrics,
        }),
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
    const etaText = metrics.etaSeconds !== null ? formatDurationSeconds(metrics.etaSeconds) : "unknown";
    emitProgress(
      action,
      [
        `rpc-log-scan ${label}: ${percent}%`,
        `(${scannedBlocks}/${totalBlocks} blocks, ${logsFound} logs,`,
        `${metrics.ratePerSecond.toFixed(1)} blocks/s, ETA ${etaText})`,
      ].join(" "),
      buildRpcLogScanProgressDetails({ event, label, scannedBlocks, totalBlocks, logsFound, metrics }),
    );
  };
}

function buildRpcLogScanProgressDetails({
  event,
  label,
  scannedBlocks,
  totalBlocks,
  logsFound,
  metrics,
}) {
  return {
    kind: "rpc-log-scan",
    label,
    status: String(event.status ?? "unknown"),
    unit: "blocks",
    fromBlock: finiteNumberOrNull(event.fromBlock),
    toBlock: finiteNumberOrNull(event.toBlock),
    chunkFromBlock: finiteNumberOrNull(event.chunkFromBlock),
    chunkToBlock: finiteNumberOrNull(event.chunkToBlock),
    scannedBlocks,
    totalBlocks,
    completedUnits: scannedBlocks,
    totalUnits: totalBlocks,
    remainingBlocks: roundedNumberOrNull(metrics.remainingUnits, 0),
    remainingUnits: roundedNumberOrNull(metrics.remainingUnits, 0),
    logsFound,
    chunkLogs: finiteNumberOrNull(event.chunkLogs),
    percent: roundedNumberOrNull(metrics.percent, 2),
    ratePerSecond: roundedNumberOrNull(metrics.ratePerSecond, 2),
    etaSeconds: roundedNumberOrNull(metrics.etaSeconds, 2),
    etaFormatted: metrics.etaSeconds !== null ? formatDurationSeconds(metrics.etaSeconds) : null,
    elapsedSeconds: roundedNumberOrNull(metrics.elapsedSeconds, 2),
  };
}

function formatHumanError(error, args = {}) {
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

function buildJsonErrorPayload(error, args = {}) {
  const message = String(error?.message ?? error);
  const hints = buildRecoveryHints(error, args);
  return {
    ok: false,
    action: "error",
    error: {
      name: error?.name ?? "Error",
      code: error?.code ?? "ERROR",
      command: typeof args.command === "string" ? args.command : null,
      message,
      hints,
      phase: error?.phase ?? null,
      operationName: error?.operationName ?? null,
      transactionSubmitted: typeof error?.transactionSubmitted === "boolean"
        ? error.transactionSubmitted
        : null,
      submittedBefore: Array.isArray(error?.submittedBefore) ? error.submittedBefore : [],
      decodedContractError: error?.decodedContractError ?? null,
      providerError: error?.providerError ?? null,
      channelName: error?.channelName ?? (typeof args.channelName === "string" ? args.channelName : null),
      networkName: error?.networkName ?? (typeof args.network === "string" ? args.network : null),
      walletName: error?.walletName ?? (typeof args.wallet === "string" ? args.wallet : null),
      operationDir: error?.operationDir ?? null,
      retryPolicy: error?.retryPolicy ?? null,
      details: error?.details ?? null,
      semanticMutationAllowed: typeof error?.semanticMutationAllowed === "boolean"
        ? error.semanticMutationAllowed
        : null,
      reuseProofAllowed: typeof error?.reuseProofAllowed === "boolean"
        ? error.reuseProofAllowed
        : null,
    },
  };
}

function buildRecoveryHints(error, args = {}) {
  const message = String(error?.message ?? error);
  const hints = [];
  const networkName = typeof args.network === "string" && args.network.length > 0
    ? args.network
    : error?.networkName ?? "<NETWORK>";
  const channelName = typeof args.channelName === "string" && args.channelName.length > 0
    ? args.channelName
    : error?.channelName ?? "<CHANNEL>";
  const accountName = typeof args.account === "string" && args.account.length > 0
    ? args.account
    : "<ACCOUNT>";
  const walletName = typeof args.wallet === "string" && args.wallet.length > 0
    ? args.wallet
    : error?.walletName ?? extractUnknownWalletName(message) ?? "<WALLET>";

  if (error?.code === CLI_ERROR_CODES.TERMS_ACCEPTANCE_REQUIRED) {
    if (args.json !== undefined) {
      hints.push("run the same command again without --json and complete the local browser Terms page yourself");
    } else {
      hints.push("complete the local browser Terms page yourself");
    }
    hints.push("User-Controlled AI Agents must not click Terms acceptance controls or type fallback acceptance phrases for the user");
  }

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
    hints.push("omit --account on supported commands to use a browser wallet instead of a local account alias");
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
    hints.push(`private-state-cli channel join --channel-name ${channelName} --network ${networkName} --account ${accountName} --wallet-secret-path <PATH>`);
    hints.push(`private-state-cli help guide --network ${networkName} --channel-name ${channelName} --account ${accountName}`);
  }

  if (error?.code === CLI_ERROR_CODES.UNKNOWN_CHANNEL) {
    hints.push(`private-state-cli help guide --network ${networkName} --channel-name ${channelName}`);
    hints.push(`private-state-cli channel get-meta --channel-name ${channelName} --network ${networkName}`);
  }

  if (error?.code === CLI_ERROR_CODES.MISSING_CHANNEL_OBSERVER) {
    hints.push(`ask the Channel Provider to register an observer URL on-chain for channel ${channelName}`);
    hints.push(`private-state-cli channel get-meta --channel-name ${channelName} --network ${networkName}`);
  }

  if (error?.code === CLI_ERROR_CODES.CHANNEL_OPERATION_ABANDONED) {
    hints.push(`private-state-cli channel get-meta --channel-name ${channelName} --network ${networkName}`);
    hints.push(`existing users may still run: private-state-cli wallet redeem-notes --wallet ${walletName} --network ${networkName} --note-ids <JSON_ARRAY>`);
    hints.push(`existing users may still run: private-state-cli wallet withdraw-channel --wallet ${walletName} --network ${networkName} --amount <TOKENS>`);
    hints.push(`after channel balance is zero: private-state-cli channel exit --wallet ${walletName} --network ${networkName}`);
  }

  if (error?.code === CLI_ERROR_CODES.STALE_WORKSPACE) {
    hints.push(`private-state-cli channel get-meta --channel-name ${channelName} --network ${networkName}`);
    hints.push(`if workspaceMirror is set: private-state-cli channel recover-workspace --channel-name ${channelName} --network ${networkName} --source mirror`);
    hints.push(`otherwise use indexed RPC recovery: private-state-cli channel recover-workspace --channel-name ${channelName} --network ${networkName}`);
    hints.push(`private-state-cli help guide --network ${networkName} --channel-name ${channelName}`);
  }

  if (
    error?.code === CLI_ERROR_CODES.STALE_CHANNEL_ROOT
    || message.includes("UnexpectedCurrentRootVector")
  ) {
    hints.push(`private-state-cli channel get-meta --channel-name ${channelName} --network ${networkName}`);
    hints.push(`if workspaceMirror is set: private-state-cli channel recover-workspace --channel-name ${channelName} --network ${networkName} --source mirror`);
    hints.push(`otherwise use indexed RPC recovery: private-state-cli channel recover-workspace --channel-name ${channelName} --network ${networkName}`);
    if (walletName !== "<WALLET>") {
      hints.push(`private-state-cli wallet get-notes --wallet ${walletName} --network ${networkName}`);
    }
    hints.push("rerun the original proof-backed command unchanged so the CLI regenerates a fresh proof");
  }

  if (message.includes("Workspace recovery index is missing or unusable")) {
    hints.push(`private-state-cli channel get-meta --channel-name ${channelName} --network ${networkName}`);
    hints.push(`if workspaceMirror is set: private-state-cli channel recover-workspace --channel-name ${channelName} --network ${networkName} --source mirror`);
    hints.push(`only if no compatible workspace mirror is available: private-state-cli channel recover-workspace --channel-name ${channelName} --network ${networkName} --source rpc --from-genesis`);
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
  requireCurrentTermsAcceptanceForCommand,
  assertVersionArgs,
  printVersion,
  printHelp,
  closeBrowserWalletBridgeSession,
  assertHelpCommandsArgs,
  assertInstallZkEvmArgs,
  assertUninstallArgs,
  assertSetRpcArgs,
  assertUpdateArgs,
  assertDoctorArgs,
  assertGuideArgs,
  assertCreatePrivateKeySourceArgs,
  assertCreateWalletSecretSourceArgs,
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
  assertAbandonChannelOperationArgs,
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
  handleCreatePrivateKeySource,
  handleCreateWalletSecretSource,
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
  handleAbandonChannelOperation,
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
  cliOutput,
};
