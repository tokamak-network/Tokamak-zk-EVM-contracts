#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import readline from "node:readline/promises";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import {
  createCipheriv,
  createDecipheriv,
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
  workspaceWalletsDir,
  walletDirForName,
  walletMetadataPathForDir,
  walletNameForChannelAndAddress,
} from "./lib/private-state-cli-shared.mjs";
import {
  buildDoctorReport,
  installGroth16RuntimeForPrivateState,
  installPrivateStateCliArtifacts,
  installTokamakCliRuntimeForPrivateState,
  inspectGroth16Runtime,
  printDoctorHumanReport,
  privateStateCliArtifactPaths,
  readTokamakCliPackageReport,
  requireActiveTokamakCliRuntimeRoot,
  resolveActiveGroth16ProverRuntime,
  resolveArtifactCacheBaseRoot,
  resolvePrivateStateInstallRuntimeVersions,
  resolveTokamakCliResourceDirForRuntimeRoot,
  writePrivateStateCliInstallManifest,
} from "./lib/private-state-runtime-management.mjs";
import {
  PRIVATE_STATE_CLI_COMMANDS,
  PRIVATE_STATE_CLI_FIELD_CATALOG,
  privateStateCliCommandDisplay,
  privateStateCliCommandOptionKeys,
  privateStateCliCommandRequiredOptionKeys,
  privateStateCliCommandSynopsis,
} from "./lib/private-state-cli-command-registry.mjs";
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
} from "./lib/private-state-note-delivery.mjs";
import {
  bigintToHex32,
  buildStateManager,
  buildTokamakTxSnapshot,
  bytes32FromHex,
  currentStorageBigInt,
  deriveChannelTokenVaultLeafIndex,
  deriveLiquidBalanceStorageKey,
  fetchContractCodes,
  normalizeBytesHex,
  normalizeBytes32Hex,
  serializeBigInts,
} from "./lib/private-state-tokamak-helpers.mjs";

const require = createRequire(import.meta.url);
const defaultCommandCwd = process.cwd();
const privateStateCliPackageRoot = path.dirname(require.resolve("./package.json"));
const workspaceRoot = path.resolve(os.homedir(), "tokamak-private-channels", "workspace");
const secretRoot = path.resolve(os.homedir(), "tokamak-private-channels", "secrets");
const flatDeploymentArtifactPathsByChainId = new Map();
const PRIVATE_STATE_UNINSTALL_CONFIRMATION =
  "I understand that the wallet secrets deleted due to this decision cannot be recovered";
const GROTH16_PACKAGE_NAME = "@tokamak-private-dapps/groth16";
const TOKAMAK_ZKEVM_CLI_PACKAGE_NAME = "@tokamak-zk-evm/cli";
let jsonOutputRequested = false;
let activeCliArgs = {};

const CLI_ERROR_CODES = Object.freeze({
  MISSING_RPC_URL: "MISSING_RPC_URL",
  UNKNOWN_WALLET: "UNKNOWN_WALLET",
  MISSING_WALLET_SECRET: "MISSING_WALLET_SECRET",
  WALLET_DECRYPT_FAILED: "WALLET_DECRYPT_FAILED",
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
const DEFAULT_LOG_CHUNK_SIZE = 2000;
const DEFAULT_LOG_REQUESTS_PER_SECOND = 5;
const LOG_REQUEST_INTERVAL_MS = Math.ceil(1000 / DEFAULT_LOG_REQUESTS_PER_SECOND);
let lastLogRequestStartedAtMs = 0;

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

async function prepareDeploymentArtifacts(chainId) {
  const normalizedChainId = Number(chainId);
  const existingPaths = flatDeploymentArtifactPathsByChainId.get(normalizedChainId);
  if (existingPaths) {
    return existingPaths.rootDir;
  }

  const cacheBaseRoot = resolveArtifactCacheBaseRoot();
  const artifactPaths = privateStateCliArtifactPaths(cacheBaseRoot, normalizedChainId);
  requireInstalledDeploymentArtifacts(artifactPaths, normalizedChainId);
  flatDeploymentArtifactPathsByChainId.set(normalizedChainId, artifactPaths);
  return artifactPaths.rootDir;
}

function flatDeploymentArtifactPathsForChainId(chainId) {
  return flatDeploymentArtifactPathsByChainId.get(Number(chainId)) ?? null;
}

function requireFlatDeploymentArtifactPathsForChainId(chainId) {
  const paths = flatDeploymentArtifactPathsForChainId(chainId);
  if (!paths) {
    throw new Error(`Deployment artifacts for chain ${Number(chainId)} were not prepared.`);
  }
  return paths;
}

function requireInstalledDeploymentArtifacts(artifactPaths, chainId) {
  const requiredFiles = [
    artifactPaths.bridgeDeploymentPath,
    artifactPaths.bridgeAbiManifestPath,
    artifactPaths.grothManifestPath,
    artifactPaths.grothZkeyPath,
    artifactPaths.dappDeploymentPath,
    artifactPaths.dappStorageLayoutPath,
    artifactPaths.privateStateControllerAbiPath,
    artifactPaths.dappRegistrationPath,
  ];
  try {
    for (const filePath of requiredFiles) {
      if (!fs.existsSync(filePath)) {
        throw new Error(`Missing ${filePath}.`);
      }
    }
  } catch (error) {
    throw cliError(
      CLI_ERROR_CODES.MISSING_DEPLOYMENT_ARTIFACTS,
      [
        `Missing installed deployment artifacts for chain ${chainId} under ${artifactPaths.rootDir}.`,
        "Run install before running private-state CLI commands for this network.",
        `Original error: ${error.message}`,
      ].join(" "),
    );
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  activeCliArgs = args;
  configureOutput(args);

  if (args.help || !args.command) {
    printHelp();
    return;
  }

  if (args.command === "install") {
    assertInstallZkEvmArgs(args);
    await handleInstallZkEvm({ args });
    return;
  }

  if (args.command === "uninstall") {
    assertUninstallArgs(args);
    await handleUninstall();
    return;
  }

  if (args.command === "doctor") {
    assertDoctorArgs(args);
    await handleDoctor({ args });
    return;
  }

  if (args.command === "guide") {
    assertGuideArgs(args);
    await handleGuide({ args });
    return;
  }

  if (args.command === "get-my-l1-address") {
    assertGetMyL1AddressArgs(args);
    handleGetMyL1Address({ args });
    return;
  }

  if (args.command === "account-import") {
    assertAccountImportArgs(args);
    handleAccountImport({ args });
    return;
  }

  if (args.command === "list-local-wallets") {
    assertListLocalWalletsArgs(args);
    handleListLocalWallets({ args });
    return;
  }

  const walletCommandHandlers = {
    "mint-notes": {
      assert: assertMintNotesArgs,
      run: ({ provider }) => handleMintNotes({ args, provider }),
    },
    "redeem-notes": {
      assert: assertRedeemNotesArgs,
      run: ({ provider }) => handleRedeemNotes({ args, provider }),
    },
    "get-my-notes": {
      assert: assertGetMyNotesArgs,
      run: ({ provider }) => handleGetMyNotes({ args, provider }),
    },
    "transfer-notes": {
      assert: assertTransferNotesArgs,
      run: ({ provider }) => handleTransferNotes({ args, provider }),
    },
    "deposit-channel": {
      assert: (parsedArgs) => assertWalletChannelMoveArgs(parsedArgs, "deposit-channel"),
      run: ({ provider }) => handleGrothVaultMove({ args, provider, direction: "deposit" }),
    },
    "withdraw-channel": {
      assert: (parsedArgs) => assertWalletChannelMoveArgs(parsedArgs, "withdraw-channel"),
      run: ({ provider }) => handleGrothVaultMove({ args, provider, direction: "withdraw" }),
    },
    "get-my-wallet-meta": {
      assert: assertGetMyWalletMetaArgs,
      run: ({ provider }) => handleGetMyWalletMeta({ args, provider }),
    },
    "get-my-channel-fund": {
      assert: assertGetMyChannelFundArgs,
      run: ({ provider }) => handleGetMyChannelFund({ args, provider }),
    },
    "exit-channel": {
      assert: assertExitChannelArgs,
      run: ({ provider }) => handleExitChannel({ args, provider }),
    },
  };
  if (walletCommandHandlers[args.command]) {
    walletCommandHandlers[args.command].assert(args);
    const { network, provider } = loadWalletCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await walletCommandHandlers[args.command].run({ network, provider });
    return;
  }

  switch (args.command) {
    case "create-channel": {
      assertCreateChannelArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleChannelCreate({ args, network, provider });
      return;
    }
    case "recover-workspace": {
      assertRecoverWorkspaceArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleWorkspaceInit({ args, network, provider });
      return;
    }
    case "get-channel": {
      assertGetChannelArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleGetChannel({ args, network, provider });
      return;
    }
    case "deposit-bridge": {
      assertDepositBridgeArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleDepositBridge({ args, network, provider });
      return;
    }
    case "withdraw-bridge": {
      assertWithdrawBridgeArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleWithdrawBridge({ args, network, provider });
      return;
    }
    case "get-my-bridge-fund": {
      assertGetMyBridgeFundArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleGetMyBridgeFund({ args, provider });
      return;
    }
    case "recover-wallet": {
      assertRecoverWalletArgs(args);
      const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleRecoverWallet({ args, network, provider, rpcUrl });
      return;
    }
    case "join-channel": {
      assertJoinChannelArgs(args);
      const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleJoinChannel({ args, network, provider, rpcUrl });
      return;
    }
    default:
      throw new Error(`Unsupported command: ${args.command}`);
  }
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
    action: "create-channel",
    channelName,
    channelId,
    policySnapshot,
  });
  const receipt =
    await waitForReceipt(await bridgeCore.createChannel(channelId, dappId, joinToll, dapp.metadataDigest));
  const channelInfo = await bridgeCore.getChannel(channelId);

  const workspaceResult = await initializeChannelWorkspace({
    workspaceName,
    channelName,
    network,
    provider,
    bridgeResources,
    persist: true,
  });

  printJson({
    action: "create-channel",
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

  const { workspaceDir, workspace, currentSnapshot } = await initializeChannelWorkspace({
    workspaceName,
    channelName,
    network,
    provider,
    bridgeResources,
    persist: true,
    allowExistingWorkspaceSync: true,
    useWorkspaceRecoveryIndex: true,
    fromGenesis: args.fromGenesis === true,
  });

  printJson({
    action: "recover-workspace",
    workspace: workspaceName,
    workspaceDir,
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
        action: "get-channel",
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
    action: "get-channel",
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
  });
}

async function initializeChannelWorkspace({
  workspaceName,
  channelName,
  network,
  provider,
  bridgeResources,
  persist,
  allowExistingWorkspaceSync = false,
  useWorkspaceRecoveryIndex = false,
  fromGenesis = false,
}) {
  const workspaceDir = channelWorkspacePath(networkNameFromChainId(network.chainId), workspaceName);
  const channelDir = channelDataPath(workspaceDir);
  const hasPersistedChannelData = fs.existsSync(channelWorkspaceConfigPath(workspaceDir))
    || fs.existsSync(channelWorkspaceCurrentPath(workspaceDir))
    || fs.existsSync(channelWorkspaceOperationsPath(workspaceDir));

  if (persist && hasPersistedChannelData && !allowExistingWorkspaceSync) {
    throw new Error(`Workspace already exists: ${workspaceDir}.`);
  }

  const existingArtifacts = persist && hasPersistedChannelData
    ? loadExistingWorkspaceArtifacts(workspaceDir)
    : null;

  const { bridgeDeployment, bridgeAbiManifest } = bridgeResources;
  const bridgeCore = new Contract(bridgeDeployment.bridgeCore, bridgeAbiManifest.contracts.bridgeCore.abi, provider);
  const channelId = deriveChannelIdFromName(channelName);
  const channelInfo = await bridgeCore.getChannel(channelId);
  if (!channelInfo.exists) {
    throw new Error(`Unknown channel ${channelId.toString()} in bridge core ${bridgeDeployment.bridgeCore}.`);
  }

  const channelManager = new Contract(
    channelInfo.manager,
    bridgeAbiManifest.contracts.channelManager.abi,
    provider,
  );
  const canonicalAsset = getAddress(channelInfo.asset);
  const canonicalAssetDecimals = await fetchTokenDecimals(provider, canonicalAsset);
  const currentRootVectorHash = normalizeBytes32Hex(await channelManager.currentRootVectorHash());
  const genesisBlockNumber = Number(await channelManager.genesisBlockNumber());
  const latestBlock = await provider.getBlockNumber();
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

  const contractCodes = await fetchContractCodes(provider, managedStorageAddresses);
  const blockInfo = await fetchChannelBlockInfo(provider, genesisBlockNumber);
  const derivedAPubBlockHash = normalizeBytes32Hex(hashTokamakPublicInputs(encodeTokamakBlockInfo(blockInfo)));
  expect(
    ethers.toBigInt(derivedAPubBlockHash) === ethers.toBigInt(normalizeBytes32Hex(channelInfo.aPubBlockHash)),
    `Derived channel block-info hash ${derivedAPubBlockHash} does not match onchain ${channelInfo.aPubBlockHash}.`,
  );
  const localSnapshotReusable = !fromGenesis && canReuseLocalWorkspaceSnapshot({
    existingArtifacts,
    currentRootVectorHash,
    managedStorageAddresses,
  });
  const recoveryIndex = useWorkspaceRecoveryIndex && !fromGenesis
    ? getUsableWorkspaceRecoveryIndex({
      existingArtifacts,
      genesisBlockNumber,
      latestBlock,
      managedStorageAddresses,
    })
    : null;
  const reconstruction = localSnapshotReusable
    ? {
      currentSnapshot: existingArtifacts.stateSnapshot,
      scanRange: {
        fromBlock: latestBlock + 1,
        toBlock: latestBlock,
        mode: "reused-current-snapshot",
      },
    }
    : await reconstructChannelSnapshot({
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
      baseSnapshot: recoveryIndex?.stateSnapshot ?? null,
      fromBlock: recoveryIndex?.nextBlock ?? genesisBlockNumber,
      toBlock: latestBlock,
    });
  const currentSnapshot = reconstruction.currentSnapshot;
  const recoveryRootVectorHash = normalizeBytes32Hex(hashRootVector(currentSnapshot.stateRoots));
  const recoveryLastScannedBlock = Number(reconstruction.scanRange.toBlock) + 1;

  const workspace = {
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
    recoveryLastScannedBlock,
    recoveryRootVectorHash,
    recoveryScanRange: reconstruction.scanRange,
  };

  if (persist) {
    ensureDir(channelDir);
    ensureDir(channelWorkspaceCurrentPath(workspaceDir));
    ensureDir(channelWorkspaceOperationsPath(workspaceDir));
    ensureDir(workspaceWalletsDir(workspaceDir));

    writeJsonIfChanged(channelWorkspaceConfigPath(workspaceDir), workspace);
    writeJsonIfChanged(path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.json"), currentSnapshot);
    writeJsonIfChanged(
      path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.normalized.json"),
      currentSnapshot,
    );
    writeJsonIfChanged(path.join(channelWorkspaceCurrentPath(workspaceDir), "block_info.json"), blockInfo);
    writeJsonIfChanged(path.join(channelWorkspaceCurrentPath(workspaceDir), "contract_codes.json"), contractCodes);
  }

  return {
    workspaceDir,
    workspace,
    currentSnapshot,
    blockInfo,
    contractCodes,
  };
}

async function handleDepositBridge({ args, network, provider }) {
  if (args.wallet !== undefined) {
    throw new Error(
      "--wallet is not supported by deposit-bridge. Channel wallet keys are set up only by join-channel.",
    );
  }
  const signer = requireL1Signer(args, provider);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId: network.chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
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
    action: "deposit-bridge",
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

async function handleGetMyBridgeFund({ args, provider }) {
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
    action: "get-my-bridge-fund",
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
  const walletSecret = resolveWalletSecretForName({
    networkName: network.name,
    walletName,
  });
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const initialized = await initializeChannelWorkspace({
    workspaceName: channelName,
    channelName,
    network,
    provider,
    bridgeResources,
    persist: true,
    allowExistingWorkspaceSync: true,
  });
  const context = {
    workspaceName: channelName,
    workspaceDir: initialized.workspaceDir,
    persistChannelWorkspace: true,
    workspace: initialized.workspace,
    bridgeAbiManifest: bridgeResources.bridgeAbiManifest,
    currentSnapshot: initialized.currentSnapshot,
    blockInfo: initialized.blockInfo,
    contractCodes: initialized.contractCodes,
    channelManager: new Contract(
      initialized.workspace.channelManager,
      bridgeResources.bridgeAbiManifest.contracts.channelManager.abi,
      provider,
    ),
    bridgeTokenVault: new Contract(
      initialized.workspace.bridgeTokenVault,
      bridgeResources.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
      provider,
    ),
  };
  const l2Identity = await deriveParticipantIdentityFromSigner({
    channelName,
    walletSecret,
    signer,
  });
  const noteReceiveKeyMaterial = await deriveNoteReceiveKeyMaterial({
    signer,
    chainId: network.chainId,
    channelId: context.workspace.channelId,
    channelName,
    account: signer.address,
  });
  const storageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  const leafIndex = deriveChannelTokenVaultLeafIndex(storageKey);
  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);

  expect(
    registration.exists,
    cliError(
      CLI_ERROR_CODES.MISSING_CHANNEL_REGISTRATION,
      `No channelTokenVault registration exists for ${signer.address}. Run join-channel first.`,
    ),
  );
  expect(
    ethers.toBigInt(getAddress(registration.l2Address)) === ethers.toBigInt(getAddress(l2Identity.l2Address)),
    "The existing channel registration L2 address does not match the derived L2 address.",
  );
  expect(
    ethers.toBigInt(normalizeBytes32Hex(registration.channelTokenVaultKey))
      === ethers.toBigInt(normalizeBytes32Hex(storageKey)),
    "The existing channel registration key does not match the derived channelTokenVault key.",
  );
  expect(
    ethers.toBigInt(registration.leafIndex) === ethers.toBigInt(leafIndex),
    "The existing channel registration leaf index does not match the derived leaf index.",
  );
  expect(
    ethers.toBigInt(normalizeBytes32Hex(registration.noteReceivePubKey.x))
      === ethers.toBigInt(normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x)),
    "The existing note-receive public key X does not match the derived note-receive public key.",
  );
  expect(
    Number(registration.noteReceivePubKey.yParity) === Number(noteReceiveKeyMaterial.noteReceivePubKey.yParity),
    "The existing note-receive public key parity does not match the derived note-receive public key.",
  );

  const existingWallet = tryLoadRecoverableWallet({
    walletName,
    walletSecret,
    signerAddress: signer.address,
    signerPrivateKey: signer.privateKey,
    l2Identity,
    storageKey,
    leafIndex,
    rpcUrl,
    channelContext: context,
    noteReceiveKeyMaterial,
  });

  if (existingWallet) {
    printJson({
      action: "recover-wallet",
      status: "already-recovered",
      wallet: walletName,
      walletDir: existingWallet.walletDir,
      walletSecretSource: resolvedWalletSecretSource(args),
      walletSecretFile: resolvedWalletSecretFile(network.name, walletName),
      workspace: context.workspaceName,
      channelName: context.workspace.channelName,
      channelId: context.workspace.channelId,
      l1Address: signer.address,
      l2Address: l2Identity.l2Address,
      l2StorageKey: storageKey,
      leafIndex: registration.leafIndex.toString(),
      noteReceivePubKey: noteReceiveKeyMaterial.noteReceivePubKey,
    });
    return;
  }

  clearWalletRecoveryArtifacts(walletPath(walletName, context.workspace.network));

  const walletContext = ensureWallet({
    channelContext: context,
    signerAddress: signer.address,
    signerPrivateKey: signer.privateKey,
    l2Identity,
    walletSecret,
    storageKey,
    leafIndex: registration.leafIndex,
    noteReceiveKeyMaterial,
    rpcUrl,
  });
  walletContext.wallet.l2Nonce = 0;
  persistWallet(walletContext);

  const recoveredDeliveryState = await recoverDeliveredNotesFromEventLogs({
    walletContext,
    context,
    provider,
    noteReceivePrivateKey: noteReceiveKeyMaterial.privateKey,
  });

  printJson({
    action: "recover-wallet",
    status: "recovered",
    wallet: walletName,
    walletDir: walletContext.walletDir,
    walletSecretSource: resolvedWalletSecretSource(args),
    walletSecretFile: resolvedWalletSecretFile(network.name, walletName),
    workspace: context.workspaceName,
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    leafIndex: registration.leafIndex.toString(),
    noteReceivePubKey: noteReceiveKeyMaterial.noteReceivePubKey,
    l2Nonce: walletContext.wallet.l2Nonce,
    recoveredFromLogs: recoveredDeliveryState.importedNotes,
    scannedDeliveryLogs: recoveredDeliveryState.scannedLogs,
    noteReceiveScanRange: recoveredDeliveryState.scanRange,
  });
}

function tryLoadRecoverableWallet({
  walletName,
  walletSecret,
  signerAddress,
  signerPrivateKey,
  l2Identity,
  storageKey,
  leafIndex,
  rpcUrl,
  channelContext,
  noteReceiveKeyMaterial,
}) {
  const walletDir = walletPath(walletName, channelContext.workspace.network);
  if (!walletConfigExists(walletDir)) {
    return null;
  }

  try {
    const walletMetadata = loadWalletMetadata(walletName, channelContext.workspace.network);
    const walletContext = loadWallet(walletName, walletSecret, channelContext.workspace.network);
    assertWalletMatchesMetadata(walletContext, walletMetadata);
    assertExistingRecoverableWallet({
      walletContext,
      walletMetadata,
      signerAddress,
      signerPrivateKey,
      l2Identity,
      storageKey,
      leafIndex,
      rpcUrl,
      channelContext,
      noteReceiveKeyMaterial,
    });
    return walletContext;
  } catch {
    return null;
  }
}

function assertExistingRecoverableWallet({
  walletContext,
  walletMetadata,
  signerAddress,
  signerPrivateKey,
  l2Identity,
  storageKey,
  leafIndex,
  rpcUrl,
  channelContext,
  noteReceiveKeyMaterial,
}) {
  const wallet = walletContext.wallet;
  expect(
    walletMetadata.network === channelContext.workspace.network,
    `Wallet ${walletContext.walletName} metadata network does not match the requested network.`,
  );
  expect(
    walletMetadata.channelName === channelContext.workspace.channelName,
    `Wallet ${walletContext.walletName} metadata channel does not match the requested channel.`,
  );
  expect(
    walletMetadata.rpcUrl === rpcUrl,
    `Wallet ${walletContext.walletName} metadata rpcUrl does not match the requested runtime RPC URL.`,
  );
  expect(
    normalizePrivateKey(wallet.l1PrivateKey) === normalizePrivateKey(signerPrivateKey),
    `Wallet ${walletContext.walletName} does not decrypt to the requested L1 private key.`,
  );
  expect(
    ethers.toBigInt(getAddress(wallet.l1Address)) === ethers.toBigInt(getAddress(signerAddress)),
    `Wallet ${walletContext.walletName} L1 address does not match the requested signer.`,
  );
  expect(
    ethers.toBigInt(getAddress(wallet.l2Address)) === ethers.toBigInt(getAddress(l2Identity.l2Address)),
    `Wallet ${walletContext.walletName} L2 address does not match the derived channel identity.`,
  );
  expect(
    ethers.toBigInt(normalizeBytes32Hex(wallet.l2StorageKey))
      === ethers.toBigInt(normalizeBytes32Hex(storageKey)),
    `Wallet ${walletContext.walletName} storage key does not match the derived registration key.`,
  );
  expect(
    ethers.toBigInt(wallet.leafIndex) === ethers.toBigInt(leafIndex),
    `Wallet ${walletContext.walletName} leaf index does not match the derived registration leaf index.`,
  );
  expect(
    ethers.toBigInt(wallet.channelId) === ethers.toBigInt(channelContext.workspace.channelId),
    `Wallet ${walletContext.walletName} channel ID does not match the requested channel.`,
  );
  expect(
    wallet.channelName === channelContext.workspace.channelName,
    `Wallet ${walletContext.walletName} channel name does not match the requested channel.`,
  );
  expect(
    wallet.network === channelContext.workspace.network,
    `Wallet ${walletContext.walletName} network does not match the requested network.`,
  );
  expect(
    wallet.rpcUrl === rpcUrl,
    `Wallet ${walletContext.walletName} rpcUrl does not match the requested runtime RPC URL.`,
  );
  expect(
    ethers.toBigInt(getAddress(wallet.channelManager)) === ethers.toBigInt(getAddress(channelContext.workspace.channelManager)),
    `Wallet ${walletContext.walletName} channel manager does not match the recovered workspace.`,
  );
  expect(
    ethers.toBigInt(getAddress(wallet.bridgeTokenVault)) === ethers.toBigInt(getAddress(channelContext.workspace.bridgeTokenVault)),
    `Wallet ${walletContext.walletName} bridge token vault does not match the recovered workspace.`,
  );
  expect(
    ethers.toBigInt(getAddress(wallet.controller)) === ethers.toBigInt(getAddress(channelContext.workspace.controller)),
    `Wallet ${walletContext.walletName} controller does not match the recovered workspace.`,
  );
  expect(
    ethers.toBigInt(getAddress(wallet.l2AccountingVault))
      === ethers.toBigInt(getAddress(channelContext.workspace.l2AccountingVault)),
    `Wallet ${walletContext.walletName} L2 accounting vault does not match the recovered workspace.`,
  );
  expect(
    ethers.toBigInt(normalizeBytes32Hex(wallet.noteReceivePubKeyX))
      === ethers.toBigInt(normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x)),
    `Wallet ${walletContext.walletName} note-receive public key X does not match the derived key.`,
  );
  expect(
    Number(wallet.noteReceivePubKeyYParity) === Number(noteReceiveKeyMaterial.noteReceivePubKey.yParity),
    `Wallet ${walletContext.walletName} note-receive public key parity does not match the derived key.`,
  );
}

function clearWalletRecoveryArtifacts(walletDir) {
  fs.rmSync(walletDir, { recursive: true, force: true });
}

async function handleInstallZkEvm({ args }) {
  const selectedVersions = await resolvePrivateStateInstallRuntimeVersions(args);
  const tokamakCliRuntime = await installTokamakCliRuntimeForPrivateState({
    version: selectedVersions.tokamak,
    docker: Boolean(args.docker),
  });
  const groth16Runtime = await installGroth16RuntimeForPrivateState({
    version: selectedVersions.groth16,
    docker: Boolean(args.docker),
  });
  const localDeploymentBaseRoot = args.includeLocalArtifacts ? process.cwd() : null;
  const deploymentArtifacts = await installPrivateStateCliArtifacts({
    dappName: PRIVATE_STATE_DAPP_LABEL,
    localDeploymentBaseRoot,
    groth16CrsVersion: groth16Runtime.compatibleBackendVersion,
  });
  const installManifest = writePrivateStateCliInstallManifest({
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
    selectedVersions,
    tokamakCli: tokamakCliRuntime.entryPath,
    runtimeRoot: tokamakCliRuntime.runtimeRoot,
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

function uninstallGlobalPrivateStateCliPackage() {
  const npmCommand = process.platform === "win32" ? "npm.cmd" : "npm";
  const list = runCaptured(npmCommand, ["ls", "-g", "@tokamak-private-dapps/private-state-cli", "--depth=0", "--json"]);
  if (list.status !== 0) {
    const listReport = parseJsonReport(list.stdout);
    const missing = /empty|missing|not found|not installed/iu.test(`${list.stdout}\n${list.stderr}`);
    return {
      attempted: false,
      installed: false,
      reason: missing || listReport ? "global package is not installed" : "unable to inspect global npm package",
      status: list.status,
      stderr: stripAnsi(list.stderr).trim(),
    };
  }
  const report = parseJsonReport(list.stdout);
  const installed = Boolean(report?.dependencies?.["@tokamak-private-dapps/private-state-cli"]);
  if (!installed) {
    return {
      attempted: false,
      installed: false,
      reason: "global package is not installed",
      status: list.status,
    };
  }
  const uninstall = runCaptured(npmCommand, ["uninstall", "-g", "@tokamak-private-dapps/private-state-cli"]);
  return {
    attempted: true,
    installed: true,
    removed: uninstall.status === 0,
    status: uninstall.status,
    stdout: stripAnsi(uninstall.stdout).trim(),
    stderr: stripAnsi(uninstall.stderr).trim(),
  };
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

function handleGetMyL1Address({ args }) {
  const signer = requireL1Signer(args);
  printJson({
    action: "get-my-l1-address",
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
    action: "account-import",
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
    action: "list-local-wallets",
    workspaceRoot,
    filters: {
      network: networkFilter,
      channelName: args.channelName ?? null,
    },
    wallets,
  });
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
      command: "guide --network <NAME>",
      why: "Select a network before the guide can inspect RPC, deployment artifacts, channels, accounts, or wallets.",
      candidates: [
        "guide --network mainnet",
        "guide --network sepolia",
        "guide --network anvil",
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
      command: "guide --network <NAME>",
      why: `The requested network ${networkName} is not supported by the CLI network config.`,
    });
    printJson(guide);
    return;
  }

  const artifactState = inspectGuideDeploymentArtifacts(networkRuntime.network.chainId);
  guide.state.deploymentArtifacts = artifactState;
  guide.checks.push(guideCheck(
    "installed deployment artifacts",
    artifactState.installed ? "ok" : "missing",
    {
      chainId: networkRuntime.network.chainId,
      rootDir: artifactState.rootDir,
      missingFiles: artifactState.missingFiles,
    },
  ));
  if (artifactState.installed) {
    flatDeploymentArtifactPathsByChainId.set(Number(networkRuntime.network.chainId), artifactState.paths);
  }

  const provider = networkRuntime.provider;
  if (args.channelName) {
    guide.state.channel = await inspectGuideChannel({
      channelName: String(args.channelName),
      network: networkRuntime.network,
      provider,
      artifactsInstalled: artifactState.installed,
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
      artifactsInstalled: artifactState.installed,
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
      artifactsInstalled: artifactState.installed,
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
    const savedRpcUrl = readNetworkSecretEnv(networkName).RPC_URL?.trim();
    if (savedRpcUrl) {
      validateRpcUrl(savedRpcUrl, `${networkSecretEnvPath(networkName)} RPC_URL`);
      rpcUrl = savedRpcUrl;
      rpcSource = networkSecretEnvPath(networkName);
    } else if (network.defaultRpcUrl) {
      rpcUrl = network.defaultRpcUrl;
      rpcSource = "network-default";
    } else {
      throw new Error(
        `Missing RPC_URL for ${networkName}. Create ${networkSecretEnvPath(networkName)} with RPC_URL=<URL>, or run a bridge-facing command once with --rpc-url <URL>.`,
      );
    }
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
      networkSecretEnvPath: networkSecretEnvPath(networkName),
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
  const requiredFiles = [
    paths.bridgeDeploymentPath,
    paths.bridgeAbiManifestPath,
    paths.grothManifestPath,
    paths.grothZkeyPath,
    paths.dappDeploymentPath,
    paths.dappStorageLayoutPath,
    paths.privateStateControllerAbiPath,
    paths.dappRegistrationPath,
  ];
  const missingFiles = requiredFiles.filter((filePath) => !fs.existsSync(filePath));
  return {
    installed: missingFiles.length === 0,
    rootDir: paths.rootDir,
    missingFiles,
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
  const walletDir = walletPath(walletName, networkName);
  const result = {
    wallet: walletName,
    network: networkName,
    walletDir,
    exists: walletConfigExists(walletDir),
    metadataExists: fs.existsSync(walletMetadataPath(walletDir)),
    secretFile: walletSecretPath(networkName, walletName),
    secretFileExists: fs.existsSync(walletSecretPath(networkName, walletName)),
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
    error: null,
  };
  if (!result.exists) {
    return result;
  }

  try {
    const walletContext = loadWallet(walletName, resolveWalletDefaultSecret(networkName, walletName), networkName);
    const walletMetadata = loadWalletMetadata(walletName, networkName);
    assertWalletMatchesMetadata(walletContext, walletMetadata);
    result.channelName = walletContext.wallet.channelName;
    result.l1Address = getAddress(walletContext.wallet.l1Address);
    result.l2Address = getAddress(walletContext.wallet.l2Address);
    result.unusedNoteCount = Object.keys(walletContext.wallet.notes.unused).length;
    result.spentNoteCount = Object.keys(walletContext.wallet.notes.spent).length;
    const unusedNoteBalance = Object.values(walletContext.wallet.notes.unused)
      .reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n);
    result.unusedNoteBalanceBaseUnits = unusedNoteBalance.toString();
    result.unusedNoteBalanceTokens = ethers.formatUnits(unusedNoteBalance, Number(walletContext.wallet.canonicalAssetDecimals));

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
      command: `list-local-wallets --network ${guide.selectors.network}`,
      why: "The selected wallet name is malformed. List local wallets and retry guide with an existing deterministic wallet name.",
    });
    return;
  }
  if (guide.state.network && !guide.state.network.rpcConfigured) {
    setGuideNextAction(guide, {
      command: null,
      why: `Configure RPC_URL in ${guide.state.network.networkSecretEnvPath}, or run a bridge-facing command once with --rpc-url <URL>.`,
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
      command: `create-channel --channel-name ${guide.selectors.channelName} --join-toll <TOKENS> --network ${guide.selectors.network} --account ${account}`,
      why: "The selected channel name is not registered on-chain yet.",
    });
    return;
  }
  if (guide.selectors.channelName && guide.state.channel?.onchain?.exists && !guide.state.channel?.local?.workspaceExists) {
    setGuideNextAction(guide, {
      command: `recover-workspace --channel-name ${guide.selectors.channelName} --network ${guide.selectors.network}`,
      why: "The channel exists on-chain, but the local channel workspace has not been recovered yet.",
    });
    return;
  }
  if (guide.selectors.wallet && guide.state.wallet && !guide.state.wallet.exists) {
    const channelName = guide.selectors.channelName ?? guide.state.channel?.channelName ?? "<CHANNEL>";
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `join-channel --channel-name ${channelName} --network ${guide.selectors.network} --account ${account} --wallet-secret-path <PATH>`,
      why: "The selected local wallet does not exist. Join the channel to create the wallet and register the channel L2 identity.",
    });
    return;
  }
  if (guide.state.wallet?.registrationExists === false) {
    const channelName = guide.state.wallet.channelName ?? guide.selectors.channelName ?? "<CHANNEL>";
    const account = guide.selectors.account ?? "<ACCOUNT>";
    setGuideNextAction(guide, {
      command: `join-channel --channel-name ${channelName} --network ${guide.selectors.network} --account ${account} --wallet-secret-path <PATH>`,
      why: "The local wallet exists, but the corresponding L1 address is not registered in the channel.",
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
      command: `deposit-bridge --amount <TOKENS> --network ${guide.selectors.network} --account ${account}`,
      why: "The wallet is joined, but there is no bridge balance, channel balance, or local unused note to spend.",
    });
    return;
  }
  if (guide.state.wallet?.exists && bridgeBalance !== null && bridgeBalance > 0n && channelBalance === 0n) {
    setGuideNextAction(guide, {
      command: `deposit-channel --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --amount <TOKENS>`,
      why: "The account has funds in the shared bridge vault, but the wallet has no channel L2 accounting balance.",
    });
    return;
  }
  if (guide.state.wallet?.exists && channelBalance !== null && channelBalance > 0n && unusedNotes === 0) {
    setGuideNextAction(guide, {
      command: `mint-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --amounts <A,B>`,
      why: "The wallet has channel L2 balance and no unused private notes yet.",
    });
    return;
  }
  if (guide.state.wallet?.exists && unusedNotes !== null && unusedNotes > 0) {
    setGuideNextAction(guide, {
      command: `transfer-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --note-ids <ID,ID> --recipients <ADDR,ADDR> --amounts <A,B>`,
      why: "The wallet has unused private notes. It can transfer or redeem those notes.",
      candidates: [
        `get-my-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network}`,
        `redeem-notes --wallet ${guide.selectors.wallet} --network ${guide.selectors.network} --note-ids <ID>`,
      ],
    });
    return;
  }
  if (guide.state.wallet?.exists && channelBalance === 0n) {
    setGuideNextAction(guide, {
      command: `exit-channel --wallet ${guide.selectors.wallet} --network ${guide.selectors.network}`,
      why: "The wallet has zero channel balance, so channel exit is allowed by both the CLI and bridge contract.",
    });
    return;
  }

  setGuideNextAction(guide, {
    command: "guide --network <NAME> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET>",
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

async function handleGetMyWalletMeta({ args, provider }) {
  const { wallet, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);
  const context = await loadChannelContext({
    args,
    networkName: walletMetadata.network,
    provider,
    walletContext: wallet,
  });

  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  const expectedStorageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  const matchesWallet = registration.exists
    && ethers.toBigInt(getAddress(registration.l2Address)) === ethers.toBigInt(getAddress(l2Identity.l2Address))
    && ethers.toBigInt(normalizeBytes32Hex(registration.channelTokenVaultKey))
      === ethers.toBigInt(normalizeBytes32Hex(expectedStorageKey));

  printJson({
    action: "get-my-wallet-meta",
    wallet: wallet.walletName,
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
  });
}

async function loadWalletChannelFundState({ walletContext, provider }) {
  const { signer, l2Identity } = restoreWalletParticipant(walletContext, provider);
  const contextResult = await loadPreferredWalletChannelContext({ walletContext, provider });
  const context = contextResult.context;
  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  expect(
    registration.exists,
    cliError(
      CLI_ERROR_CODES.MISSING_CHANNEL_REGISTRATION,
      `No channelTokenVault registration exists for ${signer.address}. Run join-channel first.`,
    ),
  );
  const expectedStorageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  expect(
    ethers.toBigInt(getAddress(registration.l2Address)) === ethers.toBigInt(getAddress(l2Identity.l2Address)),
    "The local wallet L2 address does not match the registered channel L2 address.",
  );
  expect(
    ethers.toBigInt(normalizeBytes32Hex(registration.channelTokenVaultKey))
      === ethers.toBigInt(normalizeBytes32Hex(expectedStorageKey)),
    "The local wallet L2 storage key does not match the registered channelTokenVault key.",
  );

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

async function handleGetMyChannelFund({ args, provider }) {
  const { wallet, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  const {
    signer,
    l2Identity,
    context,
    registration,
    expectedStorageKey,
    channelFund,
  } = await loadWalletChannelFundState({ walletContext: wallet, provider });

  printJson({
    action: "get-my-channel-fund",
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
  const context = await loadChannelContext({
    args,
    networkName: network.name,
    provider,
  });
  const signer = requireL1Signer(args, provider);
  const walletName = walletNameForChannelAndAddress(context.workspace.channelName, signer.address);
  const existingRegistration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  expect(
    !existingRegistration.exists,
    [
      `L1 address ${signer.address} is already registered in channel ${context.workspace.channelName}.`,
      "Use recover-wallet or normal wallet commands for an existing channel registration.",
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

  const resolvedLeafIndex = leafIndex;
  let approveReceipt = null;
  let receipt = null;
  let joinToll = 0n;
  let status = null;

  joinToll = ethers.toBigInt(await context.channelManager.joinToll());
  const asset = new Contract(
    context.workspace.canonicalAsset,
    context.bridgeAbiManifest.contracts.erc20.abi,
    signer,
  );
  let nextNonce = await provider.getTransactionCount(signer.address, "pending");
  printImmutableChannelPolicyWarning({
    action: "join-channel",
    channelName: context.workspace.channelName,
    channelId: ethers.toBigInt(context.workspace.channelId),
    channelManager: context.workspace.channelManager,
    policySnapshot: context.workspace.policySnapshot,
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
  status = "joined";

  const walletContext = ensureWallet({
    channelContext: context,
    signerAddress: signer.address,
    signerPrivateKey: signer.privateKey,
    l2Identity,
    walletSecret,
    storageKey,
    leafIndex: resolvedLeafIndex,
    noteReceiveKeyMaterial,
    rpcUrl,
  });

  printJson({
    action: "join-channel",
    workspace: context.workspaceName,
    wallet: walletContext.walletName,
    walletSecretSource: resolvedWalletSecretSource(args),
    walletSecretFile: resolvedWalletSecretFile(network.name, walletContext.walletName),
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    leafIndex: resolvedLeafIndex.toString(),
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
    status,
  });
}

async function handleExitChannel({ args, provider }) {
  const { wallet: walletContext, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  const { signer, context, channelFund, contextResult } = await loadWalletChannelFundState({
    walletContext,
    provider,
  });
  const network = contextResult.network;
  expect(
    channelFund === 0n,
    [
      `The current channel fund for ${signer.address} is ${channelFund.toString()}.`,
      "exit-channel requires a zero channel balance.",
      "Run withdraw-channel first, then retry exit-channel.",
    ].join(" "),
  );
  const [refundAmount, refundBps] = await context.channelManager.getExitTollRefundQuote(signer.address);
  const receipt = await waitForReceipt(
    await context.bridgeTokenVault.connect(signer).exitChannel(ethers.toBigInt(context.workspace.channelId)),
  );

  printJson({
    action: "exit-channel",
    wallet: walletContext.walletName,
    network: walletMetadata.network,
    channelName: walletMetadata.channelName,
    channelId: context.workspace.channelId,
    l1Address: signer.address,
    currentUserValue: channelFund.toString(),
    refundAmountBaseUnits: refundAmount.toString(),
    refundAmountTokens: ethers.formatUnits(refundAmount, Number(context.workspace.canonicalAssetDecimals)),
    refundBps: Number(refundBps),
    canonicalAsset: context.workspace.canonicalAsset,
    canonicalAssetDecimals: Number(context.workspace.canonicalAssetDecimals),
    gasUsed: receiptGasUsed(receipt),
    txUrl: explorerTxUrl(network, receipt.hash),
    receipt: sanitizeReceipt(receipt),
  });
}

async function handleGrothVaultMove({ args, provider, direction }) {
  const operationName = args.command === "withdraw-channel"
    ? "withdraw-channel"
    : direction === "deposit"
      ? "deposit-channel"
      : "withdraw";
  emitProgress(operationName, "loading");
  const { wallet: walletContext } = loadUnlockedWalletWithMetadata(args);
  const contextResult = await loadPreferredWalletChannelContext({ walletContext, provider });
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
        `${availableBalance.toString()} for ${signer.address}. Run deposit-bridge first.`,
      ].join(" "),
    );
  }
  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  expect(
    registration.exists,
    cliError(
      CLI_ERROR_CODES.MISSING_CHANNEL_REGISTRATION,
      `No channelTokenVault registration exists for ${signer.address}. Run join-channel first.`,
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
  sealWalletOperationDir(operationDir, walletContext.walletSecret);

  context.currentSnapshot = transition.nextSnapshot;
  persistCurrentState(context);

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
  });
}

async function handleWithdrawBridge({ args, network, provider }) {
  const signer = requireL1Signer(args, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
  const bridgeTokenVault = new Contract(
    bridgeVaultContext.bridgeTokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const receipt = await waitForReceipt(await bridgeTokenVault.claimToWallet(amount));

  printJson({
    action: "withdraw-bridge",
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
  const { channelFund } = await loadWalletChannelFundState({
    walletContext: wallet,
    provider,
  });
  expect(
    totalMintAmount <= channelFund,
    [
      `Mint amount total ${totalMintAmount.toString()} exceeds the current channel fund`,
      `${channelFund.toString()}. Run get-my-channel-fund to inspect the available balance.`,
    ].join(" "),
  );
  const templatePayload = buildMintNotesTemplatePayload({
    wallet,
    baseUnitAmounts: baseUnitAmounts.map(({ amountBaseUnits }) => amountBaseUnits),
  });
  const { execution, contextResult, recoveredWorkspace } = await executeWalletDirectTemplateCommand({
    wallet,
    provider,
    operationName: "mint-notes",
    templatePayload,
  });

  printJson({
    action: "mint-notes",
    wallet: wallet.walletName,
    workspace: execution.context.workspaceName,
    operationDir: execution.operationDir,
    l1Submitter: execution.signer.address,
    l2Address: execution.l2Identity.l2Address,
    underlyingMethod: templatePayload.method,
    nonce: execution.nonce,
    amountInputs: baseUnitAmounts.map(({ amountInput }) => amountInput),
    amountBaseUnits: baseUnitAmounts.map(({ amountBaseUnits }) => amountBaseUnits.toString()),
    outputNotes: buildLifecycleTrackedOutputs({
      outputNotes: templatePayload.lifecycleOutputs,
      sourceFunction: templatePayload.method,
      sourceTxHash: execution.receipt.hash,
      bridgeCommitmentKeys: execution.noteLifecycle.outputCommitmentKeys,
    }),
    gasUsed: receiptGasUsed(execution.receipt),
    txUrl: explorerTxUrl(contextResult.network, execution.receipt.hash),
    usedWorkspaceCache: contextResult.usingWorkspaceCache,
    recoveredWorkspace,
    updatedRoots: execution.context.currentSnapshot.stateRoots,
  });
}

async function handleRedeemNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  const noteIds = parseNoteIdVector(requireArg(args.noteIds, "--note-ids"));
  const inputNotes = loadWalletUnusedInputNotes(wallet, noteIds);
  const templatePayload = buildRedeemNotesTemplatePayload({
    wallet,
    inputNotes,
  });
  const { execution, contextResult, recoveredWorkspace } = await executeWalletDirectTemplateCommand({
    wallet,
    provider,
    operationName: "redeem-notes",
    templatePayload,
  });

  printJson({
    action: "redeem-notes",
    wallet: wallet.walletName,
    workspace: execution.context.workspaceName,
    operationDir: execution.operationDir,
    l1Submitter: execution.signer.address,
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
    recoveredWorkspace,
    updatedRoots: execution.context.currentSnapshot.stateRoots,
  });
}

async function handleGetMyNotes({ args, provider }) {
  const { wallet, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  expect(
    typeof wallet.wallet.controller === "string" && wallet.wallet.controller.length > 0,
    `Wallet ${wallet.walletName} is missing the stored controller address.`,
  );
  const canonicalAssetDecimals = Number(wallet.wallet.canonicalAssetDecimals);
  const { context } = await loadPreferredWalletChannelContext({ walletContext: wallet, provider });
  const signer = restoreWalletSigner(wallet, provider);
  const noteReceiveKeyMaterial = await deriveNoteReceiveKeyMaterial({
    signer,
    chainId: context.workspace.chainId,
    channelId: context.workspace.channelId,
    channelName: context.workspace.channelName,
    account: signer.address,
  });
  const recoveredDeliveryState = await recoverDeliveredNotesFromEventLogs({
    walletContext: wallet,
    context,
    provider,
    noteReceivePrivateKey: noteReceiveKeyMaterial.privateKey,
  });

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

  const unusedTotal = unusedTrackedNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n);
  const spentTotal = spentTrackedNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n);

  printJson({
    action: "get-my-notes",
    wallet: wallet.walletName,
    network: walletMetadata.network,
    channelName: walletMetadata.channelName,
    controller: wallet.wallet.controller,
    unusedNotes,
    spentNotes,
    unusedTotalBaseUnits: unusedTotal.toString(),
    unusedTotalTokens: ethers.formatUnits(unusedTotal, canonicalAssetDecimals),
    spentTotalBaseUnits: spentTotal.toString(),
    spentTotalTokens: ethers.formatUnits(spentTotal, canonicalAssetDecimals),
    bridgeStatusMismatches: [...unusedNotes, ...spentNotes].filter((note) => !note.walletStatusMatchesBridge).length,
    recoveredFromLogs: recoveredDeliveryState.importedNotes,
    scannedDeliveryLogs: recoveredDeliveryState.scannedLogs,
    noteReceiveScanRange: recoveredDeliveryState.scanRange,
  });
}

async function handleTransferNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  const { signer } = restoreWalletParticipant(wallet, provider);
  const preparedContextResult = await loadPreferredWalletChannelContext({ walletContext: wallet, provider });
  const context = preparedContextResult.context;
  const canonicalAssetDecimals = Number(wallet.wallet.canonicalAssetDecimals);
  const noteIds = parseNoteIdVector(requireArg(args.noteIds, "--note-ids"));
  const recipients = parseRecipientVector(requireArg(args.recipients, "--recipients"));
  const amountInputs = parseAmountVector(requireArg(args.amounts, "--amounts"));
  expect(
    recipients.length === amountInputs.length,
    "--amounts length must match --recipients length.",
  );

  const inputNotes = loadWalletUnusedInputNotes(wallet, noteIds);
  const outputAmounts = amountInputs.map((value, index) => {
    const parsed = parseTokenAmount(value, canonicalAssetDecimals);
    expect(parsed > 0n, `Invalid --amounts[${index}]. Each amount must be greater than zero.`);
    return parsed;
  });
  const totalInput = inputNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n);
  const totalOutput = outputAmounts.reduce((sum, value) => sum + value, 0n);
  expect(
    totalInput === totalOutput,
    "The sum of --amounts must equal the sum of the selected input note values.",
  );

  const templatePayload = await buildTransferNotesTemplatePayload({
    context,
    signer,
    inputNotes,
    recipients,
    outputAmounts,
  });
  const { execution, contextResult, recoveredWorkspace } = await executeWalletDirectTemplateCommand({
    wallet,
    provider,
    operationName: "transfer-notes",
    templatePayload,
  });
  const outputNotes = buildLifecycleTrackedOutputs({
    outputNotes: templatePayload.lifecycleOutputs,
    sourceFunction: templatePayload.method,
    sourceTxHash: execution.receipt.hash,
    bridgeCommitmentKeys: execution.noteLifecycle.outputCommitmentKeys,
  });

  printJson({
    action: "transfer-notes",
    wallet: wallet.walletName,
    workspace: execution.context.workspaceName,
    operationDir: execution.operationDir,
    l1Submitter: execution.signer.address,
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
    recoveredWorkspace,
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
  rpcUrl,
}) {
  const walletName = walletNameForChannelAndAddress(channelContext.workspace.channelName, signerAddress);
  const walletDir = walletPath(walletName, channelContext.workspace.network);
  expect(!walletConfigExists(walletDir), `Wallet ${walletName} already exists on ${channelContext.workspace.network}.`);
  ensureDir(walletDir);
  ensureDir(path.join(walletDir, "operations"));

  const wallet = normalizeWallet({
    name: walletName,
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
    l1PrivateKey: normalizePrivateKey(signerPrivateKey),
    l2Address: l2Identity.l2Address,
    l2PrivateKey: ethers.hexlify(l2Identity.l2PrivateKey),
    l2PublicKey: ethers.hexlify(l2Identity.l2PublicKey),
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

  const context = {
    walletName,
    walletDir,
    wallet,
    walletSecret,
  };
  persistWallet(context);
  persistWalletMetadata(context);
  return context;
}

function normalizeWallet(wallet) {
  assertWalletHasCurrentFormat(wallet, wallet.name ?? "unknown");
  const unusedNotes = Object.values(wallet.notes.unused).map(normalizeTrackedNote);
  unusedNotes.sort(compareNotesByValueDesc);
  const spentNotes = Object.values(wallet.notes.spent).map(normalizeTrackedNote);

  return {
    ...wallet,
    canonicalAssetDecimals: Number(wallet.canonicalAssetDecimals),
    l2Nonce: Number(wallet.l2Nonce),
    l1PrivateKey: normalizePrivateKey(wallet.l1PrivateKey),
    l2PrivateKey: ethers.hexlify(wallet.l2PrivateKey),
    l2PublicKey: ethers.hexlify(wallet.l2PublicKey),
    noteReceiveDerivationVersion: Number(wallet.noteReceiveDerivationVersion),
    noteReceiveTypedDataMethod: wallet.noteReceiveTypedDataMethod,
    noteReceivePubKeyX: normalizeBytes32Hex(wallet.noteReceivePubKeyX),
    noteReceivePubKeyYParity: Number(wallet.noteReceivePubKeyYParity),
    noteReceiveLastScannedBlock: Number(wallet.noteReceiveLastScannedBlock),
    notes: {
      unused: Object.fromEntries(unusedNotes.map((note) => [note.commitment, note])),
      spent: Object.fromEntries(spentNotes.map((note) => [note.nullifier, note])),
      unusedOrder: unusedNotes.map((note) => note.commitment),
      unusedBalance: unusedNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n).toString(),
    },
  };
}

function assertWalletHasCurrentFormat(wallet, walletName) {
  const requiredKeys = [
    "canonicalAssetDecimals",
    "l2Nonce",
    "l1PrivateKey",
    "l2PrivateKey",
    "l2PublicKey",
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
}

function normalizeTrackedNote(note) {
  return {
    owner: getAddress(note.owner),
    value: ethers.toBigInt(note.value).toString(),
    salt: normalizeBytes32Hex(note.salt),
    commitment: normalizeBytes32Hex(note.commitment),
    nullifier: normalizeBytes32Hex(note.nullifier),
    status: note.status,
    sourceFunction: note.sourceFunction ?? null,
    sourceTxHash: note.sourceTxHash ?? null,
    bridgeCommitmentKey: note.bridgeCommitmentKey ? normalizeBytes32Hex(note.bridgeCommitmentKey) : null,
    bridgeNullifierKey: note.bridgeNullifierKey ? normalizeBytes32Hex(note.bridgeNullifierKey) : null,
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
    valueTokens: ethers.formatUnits(ethers.toBigInt(note.value), canonicalAssetDecimals),
    commitment: note.commitment,
    nullifier: note.nullifier,
    walletStatus: note.status,
    bridgeCommitmentExists: commitmentExists,
    bridgeNullifierUsed: nullifierUsed,
    walletStatusMatchesBridge: commitmentExists && nullifierUsed === expectedNullifierUsed,
    sourceFunction: note.sourceFunction ?? null,
    sourceTxHash: note.sourceTxHash ?? null,
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
  const leftValue = ethers.toBigInt(left.value);
  const rightValue = ethers.toBigInt(right.value);
  if (leftValue === rightValue) {
    return left.commitment.localeCompare(right.commitment);
  }
  return leftValue > rightValue ? -1 : 1;
}

function buildTrackedNote(note, sourceFunction, sourceTxHash, bridgeKeys = {}) {
  const normalizedNote = normalizePlaintextNote(note);
  return {
    ...normalizedNote,
    commitment: normalizeBytes32Hex(computeNoteCommitment(normalizedNote)),
    nullifier: normalizeBytes32Hex(computeNullifier(normalizedNote)),
    status: "unused",
    sourceFunction,
    sourceTxHash,
    bridgeCommitmentKey: bridgeKeys.bridgeCommitmentKey
      ? normalizeBytes32Hex(bridgeKeys.bridgeCommitmentKey)
      : null,
    bridgeNullifierKey: bridgeKeys.bridgeNullifierKey
      ? normalizeBytes32Hex(bridgeKeys.bridgeNullifierKey)
      : null,
  };
}

function buildLifecycleTrackedOutputs({
  outputNotes,
  sourceFunction,
  sourceTxHash,
  bridgeCommitmentKeys,
}) {
  return (outputNotes ?? []).map((note, index) => buildTrackedNote(note, sourceFunction, sourceTxHash, {
    bridgeCommitmentKey: bridgeCommitmentKeys?.[index] ?? null,
  }));
}

async function recoverDeliveredNotesFromEventLogs({
  walletContext,
  context,
  provider,
  noteReceivePrivateKey,
}) {
  const scanStartBlock = Math.max(
    Number(walletContext.wallet.noteReceiveLastScannedBlock),
    Number(context.workspace.genesisBlockNumber),
  );
  const latestBlock = await provider.getBlockNumber();
  const scanRange = {
    fromBlock: scanStartBlock,
    toBlock: latestBlock,
  };

  if (scanStartBlock > latestBlock) {
    walletContext.wallet.noteReceiveLastScannedBlock = latestBlock + 1;
    persistWallet(walletContext);
    return {
      importedNotes: [],
      scannedLogs: 0,
      scanRange,
    };
  }

  const storageLayoutManifest = readJson(
    walletContext.wallet.storageLayoutPath ?? context.workspace.storageLayoutPath,
  );
  const commitmentExistsSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "commitmentExists"));
  const nullifierUsedSlot = ethers.toBigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "nullifierUsed"));
  const observedLogs = await fetchLogsChunked(provider, {
    address: context.workspace.channelManager,
    topics: [NOTE_VALUE_ENCRYPTED_TOPIC],
    fromBlock: scanStartBlock,
    toBlock: latestBlock,
  });

  const importedCandidates = [];
  for (const log of observedLogs) {
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
    });
    const commitment = normalizeBytes32Hex(computeNoteCommitment(plaintextNote));
    const nullifier = normalizeBytes32Hex(computeNullifier(plaintextNote));
    const trackedNote = buildTrackedNote(plaintextNote, sourceFunction, log.transactionHash, {
      bridgeCommitmentKey: derivePrivateStateControllerMappingStorageKey(commitment, commitmentExistsSlot),
      bridgeNullifierKey: derivePrivateStateControllerMappingStorageKey(nullifier, nullifierUsedSlot),
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

  const importedNotes = mergeTrackedNotesIntoWallet(walletContext, importedCandidates);
  const reconciledState = await reconcileWalletNotesWithBridgeState({
    walletContext,
    currentSnapshot: context.currentSnapshot,
    controllerAddress: context.workspace.controller,
  });
  walletContext.wallet.noteReceiveLastScannedBlock = latestBlock + 1;
  persistWallet(walletContext);
  return {
    importedNotes,
    reconciledState,
    scannedLogs: observedLogs.length,
    scanRange,
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

function extractNoteLifecycle(functionName, templatePayload) {
  if (functionName.startsWith("mintNotes")) {
    return {
      inputs: [],
      outputs: templatePayload.lifecycleOutputs ?? [],
    };
  }
  if (functionName.startsWith("transferNotes")) {
    return {
      inputs: templatePayload.lifecycleInputs ?? [],
      outputs: templatePayload.lifecycleOutputs ?? [],
    };
  }
  if (functionName.startsWith("redeemNotes")) {
    return {
      inputs: templatePayload.args[0] ?? [],
      outputs: [],
    };
  }
  return {
    inputs: [],
    outputs: [],
  };
}

function extractControllerStorageDelta({ previousSnapshot, nextSnapshot, controllerAddress, lifecycle }) {
  const normalizedControllerAddress = getAddress(controllerAddress);
  const previousStorageAddressIndex = previousSnapshot.storageAddresses.findIndex(
    (entry) => ethers.toBigInt(getAddress(entry)) === ethers.toBigInt(normalizedControllerAddress),
  );
  const nextStorageAddressIndex = nextSnapshot.storageAddresses.findIndex(
    (entry) => ethers.toBigInt(getAddress(entry)) === ethers.toBigInt(normalizedControllerAddress),
  );
  expect(previousStorageAddressIndex !== -1, `Storage snapshot does not include ${normalizedControllerAddress}.`);
  expect(nextStorageAddressIndex !== -1, `Storage snapshot does not include ${normalizedControllerAddress}.`);
  const previousKeysForAddress = previousSnapshot.storageKeys[previousStorageAddressIndex] ?? [];
  const nextKeysForAddress = nextSnapshot.storageKeys[nextStorageAddressIndex] ?? [];
  const previousKeys = new Set(previousKeysForAddress.map((key) => ethers.toBigInt(normalizeBytes32Hex(key)).toString()));
  const newKeys = nextKeysForAddress
    .map((key) => normalizeBytes32Hex(key))
    .filter((key) => !previousKeys.has(ethers.toBigInt(key).toString()));
  const inputCount = lifecycle.inputs.length;
  const outputCount = lifecycle.outputs.length;
  const expectedNewKeyCount = inputCount + outputCount;
  expect(
    newKeys.length >= expectedNewKeyCount,
    buildControllerStorageDeltaError({
      previousSnapshot,
      nextSnapshot,
      controllerAddress,
      previousKeysForAddress,
      nextKeysForAddress,
      inputCount,
      outputCount,
      newKeyCount: newKeys.length,
    }),
  );
  return {
    ...lifecycle,
    inputNullifierKeys: newKeys.slice(0, inputCount),
    outputCommitmentKeys: newKeys.slice(inputCount, inputCount + outputCount),
  };
}

function buildControllerStorageDeltaError({
  previousSnapshot,
  nextSnapshot,
  controllerAddress,
  previousKeysForAddress,
  nextKeysForAddress,
  inputCount,
  outputCount,
  newKeyCount,
}) {
  const normalizedAddress = getAddress(controllerAddress);
  const previousRoot = snapshotRootForAddress(previousSnapshot, normalizedAddress);
  const nextRoot = snapshotRootForAddress(nextSnapshot, normalizedAddress);
  const headline = [
    "The generated channel snapshot does not include enough private-state note records",
    `to track ${inputCount} spent note(s) and ${outputCount} new note(s).`,
  ].join(" ");
  const details = [
    `Controller: ${normalizedAddress}.`,
    `Tracked controller slots before: ${previousKeysForAddress.length}.`,
    `Tracked controller slots after: ${nextKeysForAddress.length}.`,
    `New controller slots discovered: ${newKeyCount}.`,
  ];
  if (previousKeysForAddress.length === 0 && nextKeysForAddress.length === 0) {
    details.push(
      "The local workspace snapshot already had no tracked controller storage slots, and the proof pipeline produced another snapshot with no tracked controller storage slots.",
    );
  }
  if (ethers.toBigInt(normalizeBytes32Hex(previousRoot)) === ethers.toBigInt(normalizeBytes32Hex(nextRoot))) {
    details.push(
      "The controller root also stayed unchanged in the generated snapshot, so the pipeline did not expose any controller state change that the CLI could map to note IDs.",
    );
  }
  details.push(
    "The CLI cannot save minted or transferred notes into the wallet unless the generated snapshot identifies the controller storage slots for those notes.",
  );
  details.push(
    "Regenerate the local workspace state first. If the workspace snapshot still has zero tracked controller slots, this channel snapshot is incomplete for note-tracking operations.",
  );
  return `${headline} ${details.join(" ")}`;
}

function snapshotRootForAddress(snapshot, storageAddress) {
  const normalizedAddress = getAddress(storageAddress);
  const addressIndex = snapshot.storageAddresses.findIndex(
    (entry) => ethers.toBigInt(getAddress(entry)) === ethers.toBigInt(normalizedAddress),
  );
  expect(addressIndex >= 0, `Storage snapshot does not include ${normalizedAddress}.`);
  return snapshot.stateRoots[addressIndex];
}

function applyNoteLifecycleToWallet(walletContext, lifecycle, sourceFunction, sourceTxHash) {
  for (const [index, inputNote] of lifecycle.inputs.entries()) {
    const trackedInput = buildTrackedNote(inputNote, sourceFunction, sourceTxHash);
    const existingUnusedNote = walletContext.wallet.notes.unused[trackedInput.commitment];
    if (!existingUnusedNote) {
      continue;
    }
    delete walletContext.wallet.notes.unused[trackedInput.commitment];
    walletContext.wallet.notes.spent[trackedInput.nullifier] = {
      ...existingUnusedNote,
      status: "spent",
      sourceFunction,
      sourceTxHash,
      bridgeNullifierKey: lifecycle.inputNullifierKeys?.[index] ?? existingUnusedNote.bridgeNullifierKey ?? null,
    };
  }

  for (const [index, outputNote] of lifecycle.outputs.entries()) {
    const trackedOutput = buildTrackedNote(outputNote, sourceFunction, sourceTxHash, {
      bridgeCommitmentKey: lifecycle.outputCommitmentKeys?.[index] ?? null,
    });
    if (trackedOutput.owner !== walletContext.wallet.l2Address) {
      continue;
    }
    walletContext.wallet.notes.unused[trackedOutput.commitment] = trackedOutput;
  }

  walletContext.wallet = normalizeWallet(walletContext.wallet);
  persistWallet(walletContext);
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
  expect(noteCount >= 1, "mint-notes requires at least one output amount.");
  expect(
    noteCount <= 2,
    "mint-notes supports only one or two output amounts with the currently registered DApp.",
  );
  return `mintNotes${noteCount}`;
}

function selectRedeemNotesMethod(noteCount) {
  expect(noteCount === 1, "redeem-notes supports exactly one input note with the currently registered DApp.");
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
    });
  }
  return {
    abiFile: "PrivateStateController.callable-abi.json",
    method,
    args: [transferOutputs, inputNotes],
    lifecycleInputs: inputNotes,
    lifecycleOutputs,
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
  throw new Error("transfer-notes supports only 1->1, 1->2, and 2->1 note transfers.");
}

function loadWalletUnusedInputNotes(walletContext, noteIds) {
  return noteIds.map((noteId) => {
    const trackedNote = walletContext.wallet.notes.unused[noteId];
    expect(trackedNote, `Unknown unused note commitment: ${noteId}.`);
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

async function loadPreferredWalletChannelContext({ walletContext, provider, forceRecover = false }) {
  let recoveredWorkspace = false;
  if (forceRecover || !walletChannelWorkspaceIsReady(walletContext)) {
    await recoverWalletChannelWorkspace({ walletContext, provider });
    recoveredWorkspace = true;
  }
  let context = await loadWorkspaceContext(walletContext.wallet.channelName, walletContext.wallet.network, provider);
  try {
    await assertWorkspaceAlignedWithChain(context);
  } catch (error) {
    if (!isRecoverableWalletWorkspaceFailure(error)) {
      throw error;
    }
    await recoverWalletChannelWorkspace({ walletContext, provider });
    recoveredWorkspace = true;
    context = await loadWorkspaceContext(walletContext.wallet.channelName, walletContext.wallet.network, provider);
    await assertWorkspaceAlignedWithChain(context);
  }
  return {
    context,
    network: resolveCliNetwork(context.workspace.network),
    usingWorkspaceCache: !recoveredWorkspace,
    recoveredWorkspace,
  };
}

async function recoverWalletChannelWorkspace({ walletContext, provider }) {
  const networkName = walletContext.wallet.network ?? networkNameFromChainId(Number(walletContext.wallet.chainId));
  const network = resolveCliNetwork(networkName);
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  await initializeChannelWorkspace({
    workspaceName: walletContext.wallet.channelName,
    channelName: walletContext.wallet.channelName,
    network,
    provider,
    bridgeResources,
    persist: true,
    allowExistingWorkspaceSync: true,
  });
}

function isRecoverableWalletWorkspaceFailure(error) {
  const message = String(error?.message ?? error);
  return (message.includes("--verify") && message.includes("failed with exit code"))
    || message.includes("The workspace snapshot is stale relative to the bridge channel state.");
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
  wallet,
  provider,
  operationName,
  templatePayload,
}) {
  emitProgress(operationName, "loading");
  const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);
  let contextResult = await loadPreferredWalletChannelContext({ walletContext: wallet, provider });
  let recoveredWorkspace = contextResult.recoveredWorkspace;

  try {
    const execution = await executeWalletTemplateSend({
      wallet,
      signer,
      l2Identity,
      context: contextResult.context,
      operationName,
      functionName: templatePayload.method,
      templatePayload,
    });
    emitProgress(operationName, "done");
    return {
      execution,
      contextResult,
      recoveredWorkspace,
    };
  } catch (error) {
    if (!isRecoverableWalletWorkspaceFailure(error)) {
      throw error;
    }
  }

  contextResult = await loadPreferredWalletChannelContext({
    walletContext: wallet,
    provider,
    forceRecover: true,
  });
  recoveredWorkspace = contextResult.recoveredWorkspace;
  const execution = await executeWalletTemplateSend({
    wallet,
    signer,
    l2Identity,
    context: contextResult.context,
    operationName,
    functionName: templatePayload.method,
    templatePayload,
  });
  emitProgress(operationName, "done");
  return {
    execution,
    contextResult,
    recoveredWorkspace,
  };
}

async function executeWalletTemplateSend({
  wallet,
  signer,
  l2Identity,
  context,
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
  const noteLifecycle = extractControllerStorageDelta({
    previousSnapshot: context.currentSnapshot,
    nextSnapshot,
    controllerAddress: context.workspace.controller,
    lifecycle: extractNoteLifecycle(functionName, templatePayload),
  });
  const aPubBlockHash = hashTokamakPublicInputs(payload.aPubBlock);
  expect(
    ethers.toBigInt(normalizeBytes32Hex(aPubBlockHash))
      === ethers.toBigInt(normalizeBytes32Hex(context.workspace.aPubBlockHash)),
    "Generated Tokamak proof does not match the channel aPubBlockHash. Check the workspace block_info.json context.",
  );

  emitProgress(operationName, "submitting");
  const receipt =
    await waitForReceipt(
      await context.channelManager.connect(signer).executeChannelTransaction(payload, functionProof),
    );

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
  applyNoteLifecycleToWallet(wallet, noteLifecycle, functionName, receipt.hash);
  context.currentSnapshot = nextSnapshot;
  persistWallet(wallet);
  persistCurrentState(context);
  sealWalletOperationDir(operationDir, wallet.walletSecret);

  return {
    wallet,
    signer,
    l2Identity,
    context,
    noteLifecycle,
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

async function loadChannelContext({ args, networkName, provider, walletContext = null }) {
  const chainId = Number((await provider.getNetwork()).chainId);
  const resolvedNetworkName = networkName ?? networkNameFromChainId(chainId);
  const channelName = args.channelName ?? walletContext?.wallet.channelName;
  if (args.channelName && walletContext) {
    expect(
      args.channelName === walletContext.wallet.channelName,
      [
        `The provided --channel-name (${args.channelName}) does not match the wallet channel`,
        `(${walletContext.wallet.channelName}).`,
      ].join(" "),
    );
  }
  if (!channelName) {
    throw new Error(
      "Missing channel selector. Provide either --channel-name or --wallet bound to a channel.",
    );
  }

  const bridgeResources = loadBridgeResources({ chainId });
  const initialized = await initializeChannelWorkspace({
    workspaceName: channelName,
    channelName,
    network: { chainId, name: resolvedNetworkName },
    provider,
    bridgeResources,
    persist: false,
  });

  return {
    workspaceName: channelName,
    workspaceDir: null,
    persistChannelWorkspace: false,
    workspace: initialized.workspace,
    bridgeAbiManifest: bridgeResources.bridgeAbiManifest,
    currentSnapshot: initialized.currentSnapshot,
    blockInfo: initialized.blockInfo,
    contractCodes: initialized.contractCodes,
    channelManager: new Contract(
      initialized.workspace.channelManager,
      bridgeResources.bridgeAbiManifest.contracts.channelManager.abi,
      provider,
    ),
    bridgeTokenVault: new Contract(
      initialized.workspace.bridgeTokenVault,
      bridgeResources.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
      provider,
    ),
  };
}

function loadWallet(walletName, walletSecret, networkName) {
  const normalizedWalletName = requireWalletName({ wallet: walletName });
  const normalizedNetworkName = requireNetworkName({ network: networkName });
  const walletDir = walletPath(normalizedWalletName, normalizedNetworkName);
  if (!walletConfigExists(walletDir)) {
    throw cliError(CLI_ERROR_CODES.UNKNOWN_WALLET, `Unknown wallet: ${normalizedWalletName} on ${normalizedNetworkName}.`);
  }
  const rawWallet = readEncryptedWalletJson(walletConfigPath(walletDir), walletSecret);
  assertWalletHasRequiredKeys(rawWallet, normalizedWalletName);
  const wallet = normalizeWallet(rawWallet);
  assertWalletUsesChannelBoundDerivation(wallet, normalizedWalletName);
  const restoredIdentity = restoreParticipantIdentityFromWallet(wallet);
  expect(
    wallet.l2Address === restoredIdentity.l2Address,
    `Wallet ${normalizedWalletName} is internally inconsistent: stored keys do not match the stored L2 address.`,
  );
  const context = {
    walletName: normalizedWalletName,
    walletDir,
    wallet,
    walletSecret,
  };
  return context;
}

function loadUnlockedWalletWithMetadata(args) {
  const networkName = requireNetworkName(args);
  const wallet = loadWallet(requireWalletName(args), requireWalletSecret(args), networkName);
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

function assertWalletHasRequiredKeys(wallet, walletName) {
  expect(
    typeof wallet.l1PrivateKey === "string" && wallet.l1PrivateKey.length > 0,
    `Wallet ${walletName} is missing the stored L1 private key.`,
  );
  expect(
    typeof wallet.l2PrivateKey === "string" && wallet.l2PrivateKey.length > 0,
    `Wallet ${walletName} is missing the stored L2 private key.`,
  );
  expect(
    typeof wallet.l2PublicKey === "string" && wallet.l2PublicKey.length > 0,
    `Wallet ${walletName} is missing the stored L2 public key.`,
  );
}

function assertWalletUsesChannelBoundDerivation(wallet, walletName) {
  expect(
    wallet.l2DerivationMode === CHANNEL_BOUND_L2_DERIVATION_MODE,
    [
      `Wallet ${walletName} was not created with the current channel-bound L2 derivation rule.`,
      "Create a fresh wallet with join-channel.",
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
  return new Wallet(normalizePrivateKey(walletContext.wallet.l1PrivateKey), provider);
}

function restoreWalletParticipant(walletContext, provider) {
  return {
    signer: restoreWalletSigner(walletContext, provider),
    l2Identity: restoreParticipantIdentityFromWallet(walletContext.wallet),
  };
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
  const walletDir = walletPath(normalizedWalletName, normalizedNetworkName);
  if (!walletConfigExists(walletDir)) {
    throw cliError(CLI_ERROR_CODES.UNKNOWN_WALLET, `Unknown wallet: ${normalizedWalletName} on ${normalizedNetworkName}.`);
  }
  const metadataPath = walletMetadataPath(walletDir);
  if (!fs.existsSync(metadataPath)) {
    throw new Error(`Wallet ${normalizedWalletName} is missing unencrypted metadata at ${metadataPath}.`);
  }
  const metadata = readJson(metadataPath);
  expect(
    typeof metadata.network === "string" && metadata.network.length > 0,
    `Wallet ${normalizedWalletName} metadata is missing network.`,
  );
  expect(
    typeof metadata.rpcUrl === "string" && metadata.rpcUrl.length > 0,
    `Wallet ${normalizedWalletName} metadata is missing rpcUrl.`,
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
      `the encrypted wallet network (${walletContext.wallet.network}).`,
    ].join(" "),
  );
  expect(
    walletContext.wallet.channelName === walletMetadata.channelName,
    [
      `Wallet ${walletContext.walletName} metadata channelName (${walletMetadata.channelName}) does not match`,
      `the encrypted wallet channel (${walletContext.wallet.channelName}).`,
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
      currentUserKey: bytes32FromHex(keyHex),
      currentUserValue: currentValue,
      updatedUserKey: bytes32FromHex(keyHex),
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
  run(process.execPath, [entryPath, "--prove", inputPath], { cwd: packageRoot });
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
  const invocation = buildTokamakCliInvocationForPackageRoot();
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

function normalizeBytes16Hex(value) {
  return normalizeBytesHex(value, 16);
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

async function fetchChannelBlockInfo(provider, blockNumber) {
  const blockTag = ethers.toQuantity(blockNumber);
  const block = await provider.send("eth_getBlockByNumber", [blockTag, false]);
  if (!block) {
    throw new Error(`Unable to fetch channel genesis block ${blockNumber}.`);
  }

  const prevBlockHashes = [];
  for (let offset = 1; offset <= TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT; offset += 1) {
    if (blockNumber <= offset) {
      prevBlockHashes.push("0x0");
      continue;
    }
    const previousBlock = await provider.send("eth_getBlockByNumber", [ethers.toQuantity(blockNumber - offset), false]);
    if (!previousBlock) {
      throw new Error(`Unable to fetch previous block hash for block ${blockNumber - offset}.`);
    }
    prevBlockHashes.push(previousBlock.hash);
  }

  return {
    coinBase: block.miner,
    timeStamp: block.timestamp,
    blockNumber: block.number,
    prevRanDao: block.prevRandao ?? block.mixHash ?? block.difficulty ?? "0x0",
    gasLimit: block.gasLimit,
    chainId: await provider.send("eth_chainId", []),
    selfBalance: "0x0",
    baseFee: block.baseFeePerGas ?? "0x0",
    prevBlockHashes,
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

  const bridgeTokenVault = new Contract(
    channelInfo.bridgeTokenVault,
    bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    provider,
  );
  const latestBlock = toBlock === null ? await provider.getBlockNumber() : Number(toBlock);
  const scanFromBlock = Math.max(Number(genesisBlockNumber), Number(fromBlock));
  const currentRootVectorObservedTopic =
    normalizeBytes32Hex(channelManager.interface.getEvent("CurrentRootVectorObserved").topicHash);
  const channelManagerLogs = await fetchLogsChunked(provider, {
    address: channelInfo.manager,
    topics: [[
      currentRootVectorObservedTopic,
      CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC,
      VAULT_STORAGE_WRITE_OBSERVED_TOPIC,
    ]],
    fromBlock: scanFromBlock,
    toBlock: latestBlock,
  });
  const channelManagerEvents = channelManagerLogs.map((log) => {
    const topic0 = log.topics[0] ? normalizeBytes32Hex(log.topics[0]) : null;
    if (topic0 !== null && ethers.toBigInt(topic0) === ethers.toBigInt(currentRootVectorObservedTopic)) {
      const parsed = channelManager.interface.parseLog(log);
      return {
        ...log,
        args: parsed.args,
        fragment: parsed.fragment,
      };
    }
    return log;
  });
  const vaultStorageWriteEvents = await queryContractEventsChunked({
    contract: bridgeTokenVault,
    eventName: "StorageWriteObserved",
    fromBlock: scanFromBlock,
    toBlock: latestBlock,
  });

  const groupedEvents = new Map();
  for (const event of [...channelManagerEvents, ...vaultStorageWriteEvents]) {
    const key = event.transactionHash;
    const group = groupedEvents.get(key) ?? [];
    group.push(event);
    groupedEvents.set(key, group);
  }

  const groupedValues = [...groupedEvents.values()].sort((left, right) => compareLogsByPosition(left[0], right[0]));
  let currentSnapshot = startingSnapshot;
  let stateManager = await buildStateManager(currentSnapshot, contractCodes);

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
  initialChunkSize = DEFAULT_LOG_CHUNK_SIZE,
}) {
  const normalizedFromBlock = Number(fromBlock);
  const resolvedToBlock = toBlock === "latest" ? await provider.getBlockNumber() : Number(toBlock);
  const aggregatedLogs = [];

  if (normalizedFromBlock > resolvedToBlock) {
    return aggregatedLogs;
  }

  let chunkSize = Math.max(1, Number(initialChunkSize));
  let cursor = normalizedFromBlock;
  while (cursor <= resolvedToBlock) {
    const chunkToBlock = Math.min(resolvedToBlock, cursor + chunkSize - 1);
    try {
      await throttleLogRequest();
      const logs = await provider.getLogs({
        address,
        topics,
        fromBlock: cursor,
        toBlock: chunkToBlock,
      });
      aggregatedLogs.push(...logs);
      cursor = chunkToBlock + 1;
    } catch (error) {
      if (isRateLimitError(error)) {
        throw new Error(
          `RPC log query rate limit exceeded. Log chunk requests are paced at ${DEFAULT_LOG_REQUESTS_PER_SECOND} requests per second.`,
          { cause: error },
        );
      }
      const suggestedChunkSize = deriveRecommendedLogChunkSize(error, chunkSize);
      if (suggestedChunkSize >= chunkSize) {
        throw error;
      }
      chunkSize = suggestedChunkSize;
    }
  }

  return aggregatedLogs;
}

async function throttleLogRequest() {
  const elapsedMs = Date.now() - lastLogRequestStartedAtMs;
  if (elapsedMs < LOG_REQUEST_INTERVAL_MS) {
    await sleep(LOG_REQUEST_INTERVAL_MS - elapsedMs);
  }
  lastLogRequestStartedAtMs = Date.now();
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

function deriveRecommendedLogChunkSize(error, currentChunkSize) {
  const serializedError = [
    error?.message,
    error?.shortMessage,
    error?.info?.responseBody,
  ].filter((value) => typeof value === "string" && value.length > 0).join("\n");

  const boundedRangeMatch = /up to a (\d+) block range/i.exec(serializedError);
  if (boundedRangeMatch) {
    return Math.max(1, Number(boundedRangeMatch[1]));
  }

  const recommendedWindowMatch = /\[(0x[0-9a-f]+),\s*(0x[0-9a-f]+)\]/i.exec(serializedError);
  if (recommendedWindowMatch) {
    const lower = Number(ethers.toBigInt(recommendedWindowMatch[1]));
    const upper = Number(ethers.toBigInt(recommendedWindowMatch[2]));
    if (Number.isFinite(lower) && Number.isFinite(upper) && upper >= lower) {
      return Math.max(1, upper - lower + 1);
    }
  }

  return Math.max(1, Math.floor(currentChunkSize / 2));
}

async function queryContractEventsChunked({
  contract,
  eventName,
  fromBlock,
  toBlock,
}) {
  const eventFragment = contract.interface.getEvent(eventName);
  const eventTopic = contract.interface.getEvent(eventName).topicHash;
  const contractAddress = getAddress(await contract.getAddress());
  const provider = contract.runner?.provider ?? contract.runner;
  expect(provider, `Contract runner is missing a provider for event ${eventName}.`);
  const logs = await fetchLogsChunked(provider, {
    address: contractAddress,
    topics: [eventTopic],
    fromBlock,
    toBlock,
  });

  return logs.map((log) => {
    const parsed = contract.interface.parseLog(log);
    return {
      ...log,
      args: parsed.args,
      fragment: parsed.fragment,
    };
  }).filter((event) => event.fragment?.name === eventFragment.name);
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
  if ((parsed.command === "account" || parsed.command === "wallet") && parsed.positional[1]) {
    parsed.command = `${parsed.command}-${parsed.positional[1]}`;
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

function requireWalletSecret(args) {
  if (args.wallet !== undefined && args.network !== undefined) {
    return resolveWalletSecretForName({
      networkName: requireNetworkName(args),
      walletName: requireWalletName(args),
    });
  }
  throw new Error(
    "Missing --wallet and --network. Wallet commands use the wallet-local default secret file.",
  );
}

function requireArg(value, label) {
  if (value === undefined || value === null || value === "") {
    throw new Error(`Missing ${label}.`);
  }
  return value;
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

function resolveWalletSecretForName({ networkName, walletName }) {
  return resolveWalletDefaultSecret(networkName, walletName);
}

function resolvedWalletSecretSource(args) {
  if (args.walletSecretPath !== undefined) return "wallet-secret-path";
  return "wallet-default";
}

function resolvedWalletSecretFile(networkName, walletName) {
  return walletSecretPath(networkName, walletName);
}

function resolveWalletDefaultSecret(networkName, walletName) {
  const secretPath = walletSecretPath(networkName, walletName);
  if (!fs.existsSync(secretPath)) {
    throw cliError(
      CLI_ERROR_CODES.MISSING_WALLET_SECRET,
      [
        `Missing wallet default secret file: ${secretPath}.`,
        "Run join-channel with --wallet-secret-path before wallet commands.",
      ].join(" "),
    );
  }
  return readSecretFile(secretPath, "wallet default secret file");
}

function prepareJoinWalletSecretForName({
  args,
  networkName,
  walletName,
}) {
  const secretPath = walletSecretPath(networkName, walletName);
  expect(
    !walletConfigExists(walletPath(walletName, networkName)),
    [
      `Wallet ${walletName} already exists on ${networkName}.`,
      "join-channel always creates a new local wallet.",
      "Use recover-wallet or normal wallet commands for an existing local wallet.",
    ].join(" "),
  );
  const sourcePath = path.resolve(String(requireArg(args.walletSecretPath, "--wallet-secret-path")));
  const canonicalPath = path.resolve(secretPath);
  const walletSecret = sourcePath === canonicalPath
    ? readSecretFile(sourcePath, "--wallet-secret-path")
    : readImportSecretSourceFile(sourcePath, "--wallet-secret-path");
  if (sourcePath !== canonicalPath) {
    expect(
      !fs.existsSync(canonicalPath),
      [
        `Wallet default secret file already exists: ${canonicalPath}.`,
        "Remove it before joining with a different --wallet-secret-path.",
      ].join(" "),
    );
    writeSecretFile(canonicalPath, walletSecret);
  }
  return walletSecret;
}

function channelWorkspacePath(networkName, name) {
  return workspaceDirForName(workspaceRoot, networkName, name);
}

function walletPath(name, networkName) {
  const walletName = String(name);
  const { channelName } = parseWalletName(walletName);
  const normalizedNetworkName = requireNetworkName({ network: networkName });
  const workspaceDir = channelWorkspacePath(normalizedNetworkName, channelName);
  return walletDirForName(workspaceWalletsDir(workspaceDir), walletName);
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

function networkSecretEnvPath(networkName) {
  return path.join(secretRoot, requireNetworkName({ network: networkName }), ".env");
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
    if (walletConfigExists(candidate)) {
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
        const walletDir = path.join(walletsDir, walletEntry.name);
        wallets.push({
          wallet: walletEntry.name,
          network: networkEntry.name,
          channelName: channelEntry.name,
          walletDir,
          metadataPath: walletMetadataPath(walletDir),
          hasMetadata: fs.existsSync(walletMetadataPath(walletDir)),
          hasEncryptedWallet: walletConfigExists(walletDir),
        });
      }
    }
  }
  return wallets.sort((left, right) =>
    [left.network, left.channelName, left.wallet].join("\0")
      .localeCompare([right.network, right.channelName, right.wallet].join("\0")),
  );
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

function walletConfigPath(walletDir) {
  return path.join(walletDir, "wallet.json");
}

function walletMetadataPath(walletDir) {
  return walletMetadataPathForDir(walletDir);
}

function walletConfigExists(walletDir) {
  return fs.existsSync(walletConfigPath(walletDir));
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
  if (args.json !== undefined && args.json !== true) {
    throw new Error(`${commandName} option --json does not accept a value.`);
  }
  expect(
    (args.positional ?? []).length === 1,
    `${commandName} does not accept positional arguments beyond the command name.`,
  );
}

function assertWalletSecretArgs(args, commandName, extraOptionKeys = [], acceptedUsage = "--wallet and --network") {
  if (COMMAND_ARG_SCHEMAS[commandName]) {
    assertAllowedCommandSchema(args, commandName);
    return;
  }
  assertAllowedCommandKeys(
    args,
    commandName,
    new Set(["command", "positional", "wallet", "network", ...extraOptionKeys]),
    acceptedUsage,
  );
}

function assertWalletChannelMoveArgs(args, commandName) {
  assertWalletSecretArgs(args, commandName, ["amount"], "--wallet, --network, and --amount");
}

function assertInstallZkEvmArgs(args) {
  assertAllowedCommandSchema(args, "install");
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

function assertDoctorArgs(args) {
  assertAllowedCommandSchema(args, "doctor");
  if (args.gpu !== undefined && args.gpu !== true) {
    throw new Error("doctor option --gpu does not accept a value.");
  }
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
  assertAllowedCommandSchema(args, "guide");
}

function assertAccountImportArgs(args) {
  assertAllowedCommandSchema(args, "account-import");
}

function assertMintNotesArgs(args) {
  assertAllowedCommandSchema(args, "mint-notes");
  parseAmountVector(args.amounts, {
    allowZeroEntries: true,
    requireAnyPositive: true,
  });
}

function assertRedeemNotesArgs(args) {
  assertAllowedCommandSchema(args, "redeem-notes");
  selectRedeemNotesMethod(parseNoteIdVector(args.noteIds).length);
}

function assertTransferNotesArgs(args) {
  assertAllowedCommandSchema(args, "transfer-notes");
  const noteIds = parseNoteIdVector(args.noteIds);
  const recipients = parseRecipientVector(args.recipients);
  const amounts = parseAmountVector(args.amounts);
  expect(
    recipients.length === amounts.length,
    "--amounts length must match --recipients length.",
  );
  selectTransferNotesMethod(noteIds.length, recipients.length);
}

function assertGetMyNotesArgs(args) {
  assertWalletSecretArgs(args, "get-my-notes");
}

function assertCreateChannelArgs(args) {
  assertAllowedCommandSchema(args, "create-channel");
}

function assertRecoverWorkspaceArgs(args) {
  assertAllowedCommandSchema(args, "recover-workspace");
}

function assertGetChannelArgs(args) {
  assertAllowedCommandSchema(args, "get-channel");
}

function assertDepositBridgeArgs(args) {
  assertAllowedCommandSchema(args, "deposit-bridge");
}

function assertGetMyBridgeFundArgs(args) {
  assertAllowedCommandSchema(args, "get-my-bridge-fund");
}

function assertExplicitSignerCommandArgs(args, commandName) {
  assertAllowedCommandSchema(args, commandName);
}

function assertRecoverWalletArgs(args) {
  assertExplicitSignerCommandArgs(args, "recover-wallet");
}

function assertJoinChannelArgs(args) {
  assertAllowedCommandSchema(args, "join-channel");
}

function assertGetMyWalletMetaArgs(args) {
  assertWalletSecretArgs(args, "get-my-wallet-meta");
}

function assertGetMyL1AddressArgs(args) {
  assertAllowedCommandSchema(args, "get-my-l1-address");
}

function assertListLocalWalletsArgs(args) {
  if (args.network !== undefined) {
    requireNetworkName(args);
  }
  if (args.channelName !== undefined) {
    requireArg(args.channelName, "--channel-name");
  }
  assertAllowedCommandSchema(args, "list-local-wallets");
}

function assertWithdrawBridgeArgs(args) {
  assertAllowedCommandSchema(args, "withdraw-bridge");
}

function assertGetMyChannelFundArgs(args) {
  assertWalletSecretArgs(args, "get-my-channel-fund");
}

function assertExitChannelArgs(args) {
  assertWalletSecretArgs(args, "exit-channel");
}

function createWalletOperationDir(walletName, networkName, suffix) {
  const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const operationDir = path.join(
    walletPath(walletName, networkName),
    "operations",
    `${timestamp}-${slugifyPathComponent(suffix)}`,
  );
  ensureDir(operationDir);
  return operationDir;
}

function persistWallet(context) {
  writeEncryptedWalletJson(path.join(context.walletDir, "wallet.json"), context.wallet, context.walletSecret);
}

function persistWalletMetadata(context) {
  writeJson(walletMetadataPath(context.walletDir), {
    network: context.wallet.network,
    rpcUrl: context.wallet.rpcUrl,
    channelName: context.wallet.channelName,
  });
}

function persistCurrentState(context) {
  if (!context.persistChannelWorkspace || !context.workspaceDir) {
    return;
  }
  writeJson(path.join(channelWorkspaceCurrentPath(context.workspaceDir), "state_snapshot.json"), context.currentSnapshot);
  writeJson(
    path.join(channelWorkspaceCurrentPath(context.workspaceDir), "state_snapshot.normalized.json"),
    context.currentSnapshot,
  );
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
  A wallet secret source file is arbitrary high-entropy secret text read once by join-channel.
  Create one before joining a channel, for example:
      openssl rand -hex 32 > ./wallet-secret.txt
      private-state-cli join-channel --channel-name <NAME> --network <NAME> --account <NAME> --wallet-secret-path ./wallet-secret.txt
  Bridge-facing commands accept optional --rpc-url. When provided, it is saved to
  ~/tokamak-private-channels/secrets/<network>/.env as RPC_URL. When omitted, the CLI reads RPC_URL from that file.
  Wallet commands use wallet-local default secret files only.
  Source files passed to --private-key-file and --wallet-secret-path are not required to use 0600 permissions, but
  canonical CLI secret files remain protected. On macOS/Linux this means 0600; on Windows the CLI repairs ACLs when possible.

Options:
  --json
      Print the command result as JSON. Without --json, commands print human-readable output.

  --help
      Show this help
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

function readNetworkSecretEnv(networkName) {
  const envPath = networkSecretEnvPath(networkName);
  if (!fs.existsSync(envPath)) {
    return {};
  }
  assertSecretFilePermissions(envPath, `${networkName} network secret env file`);
  const result = {};
  for (const line of fs.readFileSync(envPath, "utf8").split(/\r?\n/u)) {
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

function writeNetworkSecretEnv(networkName, updates) {
  const envPath = networkSecretEnvPath(networkName);
  if (fs.existsSync(envPath)) {
    protectSecretFile(envPath, `${networkName} network secret env file`);
  }
  const existing = readNetworkSecretEnv(networkName);
  const next = {
    ...existing,
    ...Object.fromEntries(
      Object.entries(updates)
        .filter(([_key, value]) => value !== undefined && value !== null && String(value).trim() !== "")
        .map(([key, value]) => [key, String(value).trim()]),
    ),
  };
  const lines = Object.entries(next)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}=${formatEnvValue(value)}`);
  writeSecretFile(envPath, lines.join("\n"));
}

function formatEnvValue(value) {
  if (/^[^\s#"'`$\\]+$/u.test(value)) {
    return value;
  }
  return JSON.stringify(value);
}

function resolveCommandRpcUrl(args) {
  const networkName = requireNetworkName(args);
  const network = resolveCliNetwork(networkName);
  if (args.rpcUrl === true) {
    throw new Error("--rpc-url requires a URL value.");
  }
  const explicitRpcUrl = typeof args.rpcUrl === "string" ? args.rpcUrl.trim() : "";
  if (explicitRpcUrl) {
    validateRpcUrl(explicitRpcUrl, "--rpc-url");
    writeNetworkSecretEnv(networkName, { RPC_URL: explicitRpcUrl });
    return explicitRpcUrl;
  }

  const savedRpcUrl = readNetworkSecretEnv(networkName).RPC_URL?.trim();
  if (savedRpcUrl) {
    validateRpcUrl(savedRpcUrl, `${networkSecretEnvPath(networkName)} RPC_URL`);
    return savedRpcUrl;
  }

  if (network.defaultRpcUrl) {
    return network.defaultRpcUrl;
  }

  throw cliError(
    CLI_ERROR_CODES.MISSING_RPC_URL,
    [
      `Missing RPC_URL for ${networkName}.`,
      `Pass --rpc-url <URL> once to save it to ${networkSecretEnvPath(networkName)},`,
      "or create that protected canonical secret file with RPC_URL=<URL>.",
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
  if (!Number.isInteger(nextBlock) || nextBlock < Number(genesisBlockNumber) || nextBlock > Number(latestBlock) + 1) {
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

function writeEncryptedWalletJson(filePath, value, walletSecret) {
  const normalizedValue = normalizeCliOutput(value);
  writeEncryptedWalletFile(filePath, Buffer.from(`${JSON.stringify(normalizedValue, null, 2)}\n`, "utf8"), walletSecret);
}

function readEncryptedWalletJson(filePath, walletSecret) {
  try {
    return JSON.parse(readEncryptedWalletFile(filePath, walletSecret).toString("utf8"));
  } catch (error) {
    throw cliError(
      CLI_ERROR_CODES.WALLET_DECRYPT_FAILED,
      `Unable to decrypt wallet data at ${filePath}. Check the wallet-local default secret file.`,
      { cause: error },
    );
  }
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
    salt: normalizeBytes16Hex(salt),
    iv: normalizeBytes12Hex(iv),
    tag: normalizeBytes16Hex(tag),
    ciphertext: ethers.hexlify(ciphertext),
  };
  fs.writeFileSync(filePath, `${JSON.stringify(envelope, null, 2)}\n`);
}

function readEncryptedWalletFile(filePath, walletSecret) {
  const envelope = readJson(filePath);
  expect(
    envelope.version === WALLET_ENCRYPTION_VERSION
      && envelope.algorithm === WALLET_ENCRYPTION_ALGORITHM
      && envelope.kdf === "scrypt",
    `Unsupported wallet encryption envelope at ${filePath}.`,
  );
  const encryptionKey = deriveWalletEncryptionKey(walletSecret, Buffer.from(ethers.getBytes(envelope.salt)));
  const decipher = createDecipheriv("aes-256-gcm", encryptionKey, Buffer.from(ethers.getBytes(envelope.iv)));
  decipher.setAuthTag(Buffer.from(ethers.getBytes(envelope.tag)));
  return Buffer.concat([
    decipher.update(Buffer.from(ethers.getBytes(envelope.ciphertext))),
    decipher.final(),
  ]);
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

function loadExplicitCommandRuntime(args) {
  const networkName = requireNetworkName(args);
  const network = {
    ...resolveCliNetwork(networkName),
    name: networkName,
  };
  const rpcUrl = resolveCommandRpcUrl(args);
  return {
    network,
    rpcUrl,
    provider: new JsonRpcProvider(rpcUrl),
  };
}

function loadWalletCommandRuntime(args) {
  const networkName = requireNetworkName(args);
  const walletMetadata = loadWalletMetadata(requireWalletName(args), networkName);
  return {
    network: {
      ...resolveCliNetwork(networkName),
      name: networkName,
    },
    provider: new JsonRpcProvider(walletMetadata.rpcUrl),
  };
}

const HUMAN_RESULT_RENDERERS = Object.freeze({
  guide: printGuideHumanResult,
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
  console.log(lines.join("\n"));
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

  if (error?.code === CLI_ERROR_CODES.MISSING_RPC_URL || message.includes("Missing RPC_URL")) {
    hints.push("rerun the same bridge-facing command once with --rpc-url <URL>.");
    if (networkName !== "<NETWORK>") {
      hints.push(`create ${networkSecretEnvPath(networkName)} with RPC_URL=<URL>.`);
    }
  }

  if (
    error?.code === CLI_ERROR_CODES.UNKNOWN_WALLET
    || message.includes("Unable to derive the channel name from wallet")
    || message.includes("Missing --wallet")
    || message.includes("does not match the wallet channel")
    || message.includes("The provided wallet does not belong to the selected channel")
  ) {
    hints.push(`private-state-cli list-local-wallets --network ${networkName}`);
    hints.push(`private-state-cli guide --network ${networkName} --wallet ${walletName}`);
  }

  if (error?.code === CLI_ERROR_CODES.MISSING_WALLET_SECRET) {
    hints.push("restore the wallet-local default secret file from backup before running wallet commands.");
    hints.push(`private-state-cli guide --network ${networkName} --wallet ${walletName}`);
  }

  if (error?.code === CLI_ERROR_CODES.WALLET_DECRYPT_FAILED) {
    hints.push("verify that the wallet-local default secret file is the same secret used when the wallet was created.");
    hints.push("if the encrypted wallet file is corrupted but the wallet secret and L1 account secret still exist, rerun recover-wallet.");
    hints.push("if the wallet secret was lost, the local L2 key cannot be recovered from the encrypted wallet file.");
  }

  if (
    message.startsWith("Missing --account:")
    || message.includes("Missing --account.")
  ) {
    hints.push(`private-state-cli account import --account ${accountName} --network ${networkName} --private-key-file <PATH>`);
    hints.push(`private-state-cli guide --network ${networkName} --account ${accountName}`);
  }

  if (
    error?.code === CLI_ERROR_CODES.MISSING_DEPLOYMENT_ARTIFACTS
    || message.includes("DApp deployment artifact")
  ) {
    hints.push("private-state-cli install");
    hints.push("private-state-cli doctor --json");
  }

  if (error?.code === CLI_ERROR_CODES.MISSING_CHANNEL_REGISTRATION) {
    hints.push(`private-state-cli join-channel --channel-name ${channelName} --network ${networkName} --account ${accountName} --wallet-secret-path <PATH>`);
    hints.push(`private-state-cli guide --network ${networkName} --channel-name ${channelName} --account ${accountName}`);
  }

  if (error?.code === CLI_ERROR_CODES.STALE_WORKSPACE) {
    hints.push(`private-state-cli recover-workspace --channel-name ${channelName} --network ${networkName}`);
    hints.push(`private-state-cli guide --network ${networkName} --channel-name ${channelName}`);
  }

  if (message.includes("Missing channel selector")) {
    hints.push(`private-state-cli list-local-wallets --network ${networkName}`);
    hints.push(`private-state-cli guide --network ${networkName} --channel-name <CHANNEL> --wallet <WALLET>`);
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

main().catch((error) => {
  console.error(formatCliErrorForDisplay(error, activeCliArgs));
  process.exitCode = 1;
});
