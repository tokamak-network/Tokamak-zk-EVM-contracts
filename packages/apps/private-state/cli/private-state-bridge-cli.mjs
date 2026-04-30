#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
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
  MAX_MT_LEAVES,
  TokamakL2StateManager,
  createTokamakL2Common,
  createTokamakL2StateManagerFromStateSnapshot,
  createTokamakL2Tx,
  deriveL2KeysFromSignature,
  fromEdwardsToAddress,
  getUserStorageKey,
  poseidon,
  readStorageValueFromStateSnapshot,
} from "tokamak-l2js";
import { jubjub } from "@noble/curves/jubjub";
import {
  addHexPrefix,
  bytesToBigInt,
  bytesToHex,
  createAddressFromString,
  hexToBigInt,
  hexToBytes,
} from "@ethereumjs/util";
import { deriveRpcUrl, resolveCliNetwork } from "@tokamak-private-dapps/common-library/network-config";
import {
  resolveTokamakBlockInputConfig,
  resolveTokamakCliEntryPath,
  resolveTokamakCliPackageRoot as resolveBundledTokamakCliPackageRoot,
} from "@tokamak-private-dapps/common-library/tokamak-runtime-paths";
import {
  DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  defaultArtifactCacheBaseRoot,
  fetchPublicArtifactIndex,
  materializeSelectedDriveFiles,
  materializeSelectedLocalFiles,
  requireChainId,
  requireLatestTimestampLabel,
  requireNonEmptyString,
  resolveArtifactCacheBaseRoot as resolveGenericArtifactCacheBaseRoot,
} from "@tokamak-private-dapps/common-library/artifact-cache";
import { toGroth16SolidityProof } from "@tokamak-private-dapps/common-library/groth16-solidity-proof";
import {
  PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID,
  downloadLatestPublicGroth16MpcArtifacts,
  downloadPublicGroth16MpcArtifactsByVersion,
  normalizeGroth16PackageVersionToCompatibleBackendVersion,
  readGroth16CompatibleBackendVersionFromPackageJson,
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

const require = createRequire(import.meta.url);
const defaultCommandCwd = process.cwd();
const privateStateCliPackageRoot = path.dirname(require.resolve("./package.json"));
const workspaceRoot = path.resolve(os.homedir(), "tokamak-private-channels", "workspace");
const flatDeploymentArtifactPathsByChainId = new Map();
const DOCKER_CUDA_PROBE_IMAGE = "nvidia/cuda:12.2.0-base-ubuntu22.04";
const DOCTOR_GPU_PROBE_TIMEOUT_MS = 120000;
const GROTH16_PACKAGE_NAME = "@tokamak-private-dapps/groth16";
const TOKAMAK_ZKEVM_CLI_PACKAGE_NAME = "@tokamak-zk-evm/cli";
const COMPATIBLE_BACKEND_VERSION_PATTERN = /^(\d+)\.(\d+)$/;
const EXACT_SEMVER_PATTERN = /^(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.]+)?(?:\+[0-9A-Za-z.]+)?$/;

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
const NOTE_RECEIVE_TYPED_DATA_METHOD = "eth_signTypedData_v4";
const NOTE_RECEIVE_KEY_DERIVATION_VERSION = 2;
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
const ENCRYPTED_NOTE_SCHEME_TRANSFER = 0;
const ENCRYPTED_NOTE_SCHEME_SELF_MINT = 1;
const NOTE_COMMITMENT_DOMAIN = ethers.keccak256(ethers.toUtf8Bytes("PRIVATE_STATE_NOTE_COMMITMENT"));
const NULLIFIER_DOMAIN = ethers.keccak256(ethers.toUtf8Bytes("PRIVATE_STATE_NULLIFIER"));
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
const JUBJUB_ORDER = jubjub.CURVE.n;
const JUBJUB_FP = jubjub.CURVE.Fp;
const JUBJUB_A = jubjub.CURVE.a;
const JUBJUB_D = jubjub.CURVE.d;
const BLS12_381_SCALAR_FIELD_MODULUS =
  hexToBigInt(addHexPrefix("73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"));
const DEFAULT_LOG_CHUNK_SIZE = 2000;
const DEFAULT_LOG_REQUESTS_PER_SECOND = 5;
const LOG_REQUEST_INTERVAL_MS = Math.ceil(1000 / DEFAULT_LOG_REQUESTS_PER_SECOND);
let lastLogRequestStartedAtMs = 0;

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
    throw new Error(
      [
        `Missing installed deployment artifacts for chain ${chainId} under ${artifactPaths.rootDir}.`,
        "Run --install before running private-state CLI commands for this network.",
        `Original error: ${error.message}`,
      ].join(" "),
    );
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help || !args.command) {
    printHelp();
    return;
  }

  if (args.command === "--install") {
    assertInstallZkEvmArgs(args);
    await handleInstallZkEvm({ args });
    return;
  }

  if (args.command === "uninstall-zk-evm") {
    assertUninstallZkEvmArgs(args);
    await handleUninstallZkEvm();
    return;
  }

  if (args.command === "--doctor") {
    assertDoctorArgs(args);
    await handleDoctor({ args });
    return;
  }

  if (args.command === "get-my-l1-address") {
    assertGetMyL1AddressArgs(args);
    handleGetMyL1Address({ args });
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
    case "deposit-bridge": {
      assertDepositBridgeArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await prepareDeploymentArtifacts(network.chainId);
      await handleRegisterAndFund({ args, network, provider });
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
  const joinFeeInput = requireArg(args.joinFee, "--join-fee");
  const joinFee = parseTokenAmount(joinFeeInput, canonicalAssetDecimals);
  const channelId = deriveChannelIdFromName(channelName);
  const dappId = await resolveDAppIdByLabel({
    provider,
    bridgeResources,
    dappLabel: PRIVATE_STATE_DAPP_LABEL,
  });

  const receipt = await waitForReceipt(await bridgeCore.createChannel(channelId, dappId, leader, joinFee));
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
    leader,
    joinFeeBaseUnits: joinFee.toString(),
    joinFeeTokens: ethers.formatUnits(joinFee, canonicalAssetDecimals),
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

  expect(manifestLabel === dappLabel, `DApp registration manifest label mismatch in ${manifestPath}.`);
  expect(Number.isInteger(manifestDappId), `DApp registration manifest is missing an integer dappId: ${manifestPath}.`);
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
  return Number(manifestDappId);
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
  const managedStorageAddresses = normalizedAddressVector(await channelManager.getManagedStorageAddresses());
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
  const localSnapshotReusable = canReuseLocalWorkspaceSnapshot({
    existingArtifacts,
    currentRootVectorHash,
    managedStorageAddresses,
  });
  const currentSnapshot = localSnapshotReusable
    ? existingArtifacts.stateSnapshot
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
    });

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
    managedStorageAddresses,
    liquidBalancesSlot: liquidBalancesSlot.toString(),
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

async function handleRegisterAndFund({ args, network, provider }) {
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
  const password = requireL2Password(args);
  const channelName = requireArg(args.channelName, "--channel-name");
  const signer = requireL1Signer(args, provider);
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
    password,
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
    `No channelTokenVault registration exists for ${signer.address}. Run join-channel first.`,
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

  const walletName = walletNameForChannelAndAddress(channelName, signer.address);
  const existingWallet = tryLoadRecoverableWallet({
    walletName,
    walletPassword: password,
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
    walletPassword: password,
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
  walletPassword,
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
    const walletContext = loadWallet(walletName, walletPassword, channelContext.workspace.network);
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

async function handleUninstallZkEvm() {
  let runtimeRoot = null;
  const invocation = buildTokamakCliInvocationForPackageRoot();
  try {
    runtimeRoot = inspectTokamakCliRuntime({ packageRoot: invocation.packageRoot }).runtimeRoot;
  } catch {
    runtimeRoot = null;
  }
  run(invocation.command, [...invocation.args, "--uninstall"], { cwd: invocation.packageRoot });

  printJson({
    action: "uninstall-zk-evm",
    runtimeRoot,
    existed: runtimeRoot !== null,
  });
}

async function handleDoctor() {
  const report = buildDoctorReport();
  printJson(report);
  if (!report.ok) {
    process.exitCode = 1;
  }
}

function handleGetMyL1Address({ args }) {
  const privateKey = normalizePrivateKey(requireArg(args.privateKey, "--private-key"));
  const signer = new Wallet(privateKey);
  printJson({
    action: "get-my-l1-address",
    l1Address: signer.address,
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
    `No channelTokenVault registration exists for ${signer.address}. Run join-channel first.`,
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
  const password = requireL2Password(args);
  const context = await loadChannelContext({
    args,
    networkName: network.name,
    provider,
  });
  const signer = requireL1Signer(args, provider);
  const l2Identity = await deriveParticipantIdentityFromSigner({
    channelName: context.workspace.channelName,
    password,
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

  const existingRegistration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  let resolvedLeafIndex = leafIndex;
  let approveReceipt = null;
  let receipt = null;
  let joinFee = 0n;
  let status = null;

  if (!existingRegistration.exists) {
    joinFee = ethers.toBigInt(await context.channelManager.joinFee());
    const asset = new Contract(
      context.workspace.canonicalAsset,
      context.bridgeAbiManifest.contracts.erc20.abi,
      signer,
    );
    let nextNonce = await provider.getTransactionCount(signer.address, "pending");
    if (joinFee !== 0n) {
      approveReceipt = await waitForReceipt(
        await asset.approve(context.workspace.bridgeTokenVault, joinFee, { nonce: nextNonce++ }),
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
  } else {
    expect(
      ethers.toBigInt(normalizeBytes32Hex(existingRegistration.channelTokenVaultKey))
        === ethers.toBigInt(normalizeBytes32Hex(storageKey)),
      "The existing channel registration key does not match the derived channelTokenVault key.",
    );
    expect(
      ethers.toBigInt(getAddress(existingRegistration.l2Address)) === ethers.toBigInt(getAddress(l2Identity.l2Address)),
      "The existing channel registration L2 address does not match the derived L2 address.",
    );
    expect(
      ethers.toBigInt(normalizeBytes32Hex(existingRegistration.noteReceivePubKey.x))
        === ethers.toBigInt(normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x)),
      "The existing note-receive public key X does not match the derived note-receive public key.",
    );
    expect(
      Number(existingRegistration.noteReceivePubKey.yParity) === Number(noteReceiveKeyMaterial.noteReceivePubKey.yParity),
      "The existing note-receive public key parity does not match the derived note-receive public key.",
    );
    resolvedLeafIndex = existingRegistration.leafIndex;
    joinFee = ethers.toBigInt(existingRegistration.joinFeePaid);
    status = "already-registered";
  }

  const walletContext = ensureWallet({
    channelContext: context,
    signerAddress: signer.address,
    signerPrivateKey: signer.privateKey,
    l2Identity,
    walletPassword: password,
    storageKey,
    leafIndex: resolvedLeafIndex,
    noteReceiveKeyMaterial,
    rpcUrl,
  });

  printJson({
    action: "join-channel",
    workspace: context.workspaceName,
    wallet: walletContext.walletName,
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    leafIndex: resolvedLeafIndex.toString(),
    joinFeeBaseUnits: joinFee.toString(),
    joinFeeTokens: ethers.formatUnits(joinFee, Number(context.workspace.canonicalAssetDecimals)),
    noteReceivePubKey: noteReceiveKeyMaterial.noteReceivePubKey,
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
  const bypassZeroBalanceGuard = args.force === true;
  expect(
    bypassZeroBalanceGuard || channelFund === 0n,
    [
      `The current channel fund for ${signer.address} is ${channelFund.toString()}.`,
      "exit-channel requires a zero channel balance unless --force is provided.",
      "Run withdraw-channel first, or rerun exit-channel with --force to bypass this CLI check.",
    ].join(" "),
  );
  const [refundAmount, refundBps] = await context.channelManager.getExitFeeRefundQuote(signer.address);
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
    forced: bypassZeroBalanceGuard,
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
  const { wallet: walletContext } = loadUnlockedWalletWithMetadata(args);
  const contextResult = await loadPreferredWalletChannelContext({ walletContext, provider });
  const context = contextResult.context;
  const network = contextResult.network;
  const operationName = args.command === "withdraw-channel"
    ? "withdraw-channel"
    : direction === "deposit"
      ? "deposit-channel"
      : "withdraw";
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
    `No channelTokenVault registration exists for ${signer.address}. Run join-channel first.`,
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

  const transition = await buildGrothTransition({
    operationDir,
    workspace: context.workspace,
    stateManager,
    vaultAddress: context.workspace.l2AccountingVault,
    keyHex,
    nextValue,
  });

  const receipt = await waitForReceipt(
    await bridgeTokenVault[direction](ethers.toBigInt(context.workspace.channelId), transition.proof, transition.update),
  );
  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  expect(
    onchainRootVectorHash === normalizeBytes32Hex(hashRootVector(transition.nextSnapshot.stateRoots)),
    `On-chain roots do not match the ${direction} post-state roots.`,
  );

  writeJson(path.join(operationDir, `${operationName}-receipt.json`), sanitizeReceipt(receipt));
  writeJson(path.join(operationDir, "state_snapshot.json"), transition.nextSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), transition.nextSnapshot);
  sealWalletOperationDir(operationDir, walletContext.walletPassword);

  context.currentSnapshot = transition.nextSnapshot;
  persistCurrentState(context);

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
  const spentTrackedNotes = Object.values(wallet.wallet.notes.spent ?? {}).sort(compareNotesByValueDesc);

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
    ...Object.values(walletContext.wallet.notes.unused ?? {}),
    ...Object.values(walletContext.wallet.notes.spent ?? {}),
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
  walletPassword,
  storageKey,
  leafIndex,
  noteReceiveKeyMaterial,
  rpcUrl,
}) {
  const walletName = walletNameForChannelAndAddress(channelContext.workspace.channelName, signerAddress);
  const walletDir = walletPath(walletName, channelContext.workspace.network);
  let wallet;
  if (walletConfigExists(walletDir)) {
    wallet = normalizeWallet(readEncryptedWalletJson(walletConfigPath(walletDir), walletPassword));
    expect(
      ethers.toBigInt(wallet.channelId) === ethers.toBigInt(channelContext.workspace.channelId),
      `Wallet ${walletName} belongs to channel ${wallet.channelId}, not ${channelContext.workspace.channelId}.`,
    );
    expect(
      wallet.l2Address === l2Identity.l2Address,
      `Wallet ${walletName} belongs to L2 address ${wallet.l2Address}, not ${l2Identity.l2Address}.`,
    );
  } else {
    ensureDir(walletDir);
    ensureDir(path.join(walletDir, "operations"));
    wallet = normalizeWallet({
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
      noteReceivePubKeyX: noteReceiveKeyMaterial.noteReceivePubKey.x,
      noteReceivePubKeyYParity: noteReceiveKeyMaterial.noteReceivePubKey.yParity,
      noteReceiveLastScannedBlock: Number(channelContext.workspace.genesisBlockNumber),
      l2Nonce: 0,
      notes: {},
    });
  }

  ensureDir(walletDir);
  ensureDir(path.join(walletDir, "operations"));

  wallet.appDeploymentPath = channelContext.workspace.appDeploymentPath;
  wallet.storageLayoutPath = channelContext.workspace.storageLayoutPath;
  wallet.rpcUrl = rpcUrl;
  wallet.channelName = channelContext.workspace.channelName;
  wallet.channelId = channelContext.workspace.channelId;
  wallet.channelManager = channelContext.workspace.channelManager;
  wallet.bridgeTokenVault = channelContext.workspace.bridgeTokenVault;
  wallet.canonicalAsset = channelContext.workspace.canonicalAsset;
  wallet.canonicalAssetDecimals = channelContext.workspace.canonicalAssetDecimals;
  wallet.controller = channelContext.workspace.controller;
  wallet.l2AccountingVault = channelContext.workspace.l2AccountingVault;
  wallet.liquidBalancesSlot = channelContext.workspace.liquidBalancesSlot;
  wallet.l1Address = signerAddress;
  wallet.l1PrivateKey = normalizePrivateKey(signerPrivateKey);
  wallet.l2Address = l2Identity.l2Address;
  wallet.l2PrivateKey = ethers.hexlify(l2Identity.l2PrivateKey);
  wallet.l2PublicKey = ethers.hexlify(l2Identity.l2PublicKey);
  wallet.l2DerivationMode = CHANNEL_BOUND_L2_DERIVATION_MODE;
  wallet.l2DerivationChannelName = channelContext.workspace.channelName;
  wallet.l2StorageKey = storageKey;
  wallet.noteReceiveDerivationVersion = NOTE_RECEIVE_KEY_DERIVATION_VERSION;
  wallet.noteReceiveTypedDataMethod = NOTE_RECEIVE_TYPED_DATA_METHOD;
  wallet.noteReceivePubKeyX = normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x);
  wallet.noteReceivePubKeyYParity = Number(noteReceiveKeyMaterial.noteReceivePubKey.yParity);
  wallet.noteReceiveLastScannedBlock = Number(
    wallet.noteReceiveLastScannedBlock ?? channelContext.workspace.genesisBlockNumber,
  );
  if (leafIndex !== undefined && leafIndex !== null) {
    wallet.leafIndex = leafIndex.toString();
  }

  const context = {
    walletName,
    walletDir,
    wallet,
    walletPassword,
  };
  persistWallet(context);
  persistWalletMetadata(context);
  return context;
}

function normalizeWallet(wallet) {
  const unusedNotes = Object.values(wallet.notes?.unused ?? {}).map(normalizeTrackedNote);
  unusedNotes.sort(compareNotesByValueDesc);
  const spentNotes = Object.values(wallet.notes?.spent ?? {}).map(normalizeTrackedNote);

  return {
    ...wallet,
    canonicalAssetDecimals: Number(wallet.canonicalAssetDecimals),
    l2Nonce: Number(wallet.l2Nonce ?? 0),
    l1PrivateKey: normalizePrivateKey(wallet.l1PrivateKey),
    l2PrivateKey: ethers.hexlify(wallet.l2PrivateKey),
    l2PublicKey: ethers.hexlify(wallet.l2PublicKey),
    noteReceiveDerivationVersion: Number(wallet.noteReceiveDerivationVersion ?? NOTE_RECEIVE_KEY_DERIVATION_VERSION),
    noteReceiveTypedDataMethod: wallet.noteReceiveTypedDataMethod ?? NOTE_RECEIVE_TYPED_DATA_METHOD,
    noteReceivePubKeyX: wallet.noteReceivePubKeyX ? normalizeBytes32Hex(wallet.noteReceivePubKeyX) : null,
    noteReceivePubKeyYParity: wallet.noteReceivePubKeyYParity === undefined
      ? null
      : Number(wallet.noteReceivePubKeyYParity),
    noteReceiveLastScannedBlock: Number(wallet.noteReceiveLastScannedBlock ?? 0),
    notes: {
      unused: Object.fromEntries(unusedNotes.map((note) => [note.commitment, note])),
      spent: Object.fromEntries(spentNotes.map((note) => [note.nullifier, note])),
      unusedOrder: unusedNotes.map((note) => note.commitment),
      unusedBalance: unusedNotes.reduce((sum, note) => sum + ethers.toBigInt(note.value), 0n).toString(),
    },
  };
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
    Number(walletContext.wallet.noteReceiveLastScannedBlock ?? 0),
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

function computeNoteCommitment(note) {
  const data = ethers.getBytes(ethers.concat([
    NOTE_COMMITMENT_DOMAIN,
    ethers.zeroPadValue(getAddress(note.owner), 32),
    ethers.toBeHex(ethers.toBigInt(note.value), 32),
    normalizeBytes32Hex(note.salt),
  ]));
  return normalizeBytes32Hex(
    bytesToHex(
      poseidon(data),
    ),
  );
}

function computeNullifier(note) {
  const data = ethers.getBytes(ethers.concat([
    NULLIFIER_DOMAIN,
    ethers.zeroPadValue(getAddress(note.owner), 32),
    ethers.toBeHex(ethers.toBigInt(note.value), 32),
    normalizeBytes32Hex(note.salt),
  ]));
  return normalizeBytes32Hex(
    bytesToHex(
      poseidon(data),
    ),
  );
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
      account: getAddress(account),
    },
  };
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

function normalizeEncryptedNoteValueWords(encryptedNoteValue) {
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

function unpackEncryptedNoteValue(encryptedNoteValue) {
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

function derivePrivateStateControllerMappingStorageKey(keyHex, slot) {
  const encoded = abiCoder.encode(["bytes32", "uint256"], [normalizeBytes32Hex(keyHex), ethers.toBigInt(slot)]);
  return normalizeBytes32Hex(bytesToHex(poseidon(hexToBytes(addHexPrefix(String(encoded ?? "").replace(/^0x/i, ""))))));
}

function computeEncryptedNoteSalt(encryptedValue) {
  const normalized = normalizeEncryptedNoteValueWords(encryptedValue);
  return normalizeBytes32Hex(
    ethers.hexlify(poseidon(ethers.getBytes(ethers.concat(normalized)))),
  );
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

function normalizeTagHex(value) {
  return normalizeBytes16Hex(value);
}

function deriveFieldMask({ sharedSecretPoint, chainId, channelId, owner, nonce, encryptionInfo }) {
  const affine = sharedSecretPoint.toAffine();
  return ethers.toBigInt(
    bytesToHex(
      poseidon(
        ethers.getBytes(
          abiCoder.encode(
            ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12"],
            [
              encryptionInfo,
              ethers.toBigInt(chainId),
              ethers.toBigInt(channelId),
              getAddress(owner),
              affine.x,
              affine.y,
              ethers.zeroPadValue(nonce, 12),
            ],
          ),
        ),
      ),
    ),
  );
}

function deriveCipherTag({ sharedSecretPoint, chainId, channelId, owner, nonce, ciphertextValue, encryptionInfo }) {
  const affine = sharedSecretPoint.toAffine();
  return ethers.dataSlice(
    bytesToHex(
      poseidon(
        ethers.getBytes(
          abiCoder.encode(
            ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12", "bytes32"],
            [
              `${encryptionInfo}:tag`,
              ethers.toBigInt(chainId),
              ethers.toBigInt(channelId),
              getAddress(owner),
              affine.x,
              affine.y,
              ethers.zeroPadValue(nonce, 12),
              fieldElementHex(ciphertextValue),
            ],
          ),
        ),
      ),
    ),
    0,
    16,
  );
}

async function deriveNoteReceiveKeyMaterial({ signer, chainId, channelId, channelName, account }) {
  const typedData = buildNoteReceiveTypedData({
    chainId,
    channelId,
    channelName,
    account,
  });
  const signature = await signer.signTypedData(typedData.domain, typedData.types, typedData.value);
  const derivedKeys = deriveL2KeysFromSignature(signature);
  const derivedPrivateKey = ethers.hexlify(derivedKeys.privateKey);
  const noteReceivePoint = jubjub.ExtendedPoint.fromHex(derivedKeys.publicKey);
  return {
    typedData,
    signature,
    privateKey: derivedPrivateKey,
    noteReceivePubKey: noteReceivePubKeyFromPoint(noteReceivePoint),
  };
}

function encryptFieldNoteValue({
  value,
  recipientPoint,
  chainId,
  channelId,
  owner,
  encryptionInfo,
  scheme,
}) {
  const ephemeralPrivateScalar = deriveEphemeralJubjubScalar();
  const ephemeralPoint = jubjub.ExtendedPoint.BASE.multiply(ephemeralPrivateScalar);
  const sharedSecretPoint = recipientPoint.multiply(ephemeralPrivateScalar);
  const nonce = ethers.hexlify(randomBytes(12));
  const plaintextValue = encodeNoteValuePlaintext(value);
  const fieldMask = deriveFieldMask({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce,
    encryptionInfo,
  });
  const ciphertextValue = (plaintextValue + fieldMask) % BLS12_381_SCALAR_FIELD_MODULUS;
  const tag = deriveCipherTag({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce,
    ciphertextValue,
    encryptionInfo,
  });
  const parsedEphemeralPubKey = noteReceivePubKeyFromPoint(ephemeralPoint);

  return packEncryptedNoteValue({
    ephemeralPubKeyX: parsedEphemeralPubKey.x,
    ephemeralPubKeyYParity: parsedEphemeralPubKey.yParity,
    nonce,
    ciphertextValue: fieldElementHex(ciphertextValue),
    tag,
    scheme,
  });
}

function encryptNoteValueForRecipient({ value, recipientNoteReceivePubKey, chainId, channelId, owner }) {
  return encryptFieldNoteValue({
    value,
    recipientPoint: pointFromNoteReceivePubKey(recipientNoteReceivePubKey),
    chainId,
    channelId,
    owner,
    encryptionInfo: TRANSFER_NOTE_FIELD_ENCRYPTION_INFO,
    scheme: ENCRYPTED_NOTE_SCHEME_TRANSFER,
  });
}

function encryptMintNoteValueForOwner({ value, ownerNoteReceivePubKey, chainId, channelId, owner }) {
  return encryptFieldNoteValue({
    value,
    recipientPoint: pointFromNoteReceivePubKey(ownerNoteReceivePubKey),
    chainId,
    channelId,
    owner,
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
  expect(normalizeTagHex(expectedTag) === normalizeTagHex(normalized.tag), "Encrypted note value integrity tag mismatch.");
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

function decryptEncryptedNoteValue({ encryptedValue, noteReceivePrivateKey, chainId, channelId, owner }) {
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

function decryptMintEncryptedNoteValue({ encryptedValue, noteReceivePrivateKey, chainId, channelId, owner }) {
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
  const nonce = Number(wallet.wallet.l2Nonce ?? 0);
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
  printLocalProofGenerationNotice(operationName);
  runTokamakProofPipeline({ operationDir, bundlePath });

  const rawNextSnapshot = readJson(path.join(operationDir, "resource", "synthesizer", "output", "state_snapshot.json"));
  if (Array.isArray(rawNextSnapshot.storageAddresses)) {
    rawNextSnapshot.storageAddresses = rawNextSnapshot.storageAddresses
      .map((address) => createAddressFromString(address).toString());
  }
  const nextSnapshot = rawNextSnapshot;
  writeJson(path.join(operationDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"), nextSnapshot);

  const payload = loadTokamakPayloadFromStep(operationDir);
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

  const receipt =
    await waitForReceipt(await context.channelManager.connect(signer).executeChannelTransaction(payload));

  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  expect(
    ethers.toBigInt(onchainRootVectorHash) === ethers.toBigInt(normalizeBytes32Hex(hashRootVector(nextSnapshot.stateRoots))),
    `On-chain roots do not match the Tokamak post-state roots for ${functionName}.`,
  );

  writeJson(path.join(operationDir, "bridge-submit-receipt.json"), sanitizeReceipt(receipt));
  writeJson(path.join(operationDir, "state_snapshot.json"), nextSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), nextSnapshot);

  wallet.wallet.l2Nonce = nonce + 1;
  applyNoteLifecycleToWallet(wallet, noteLifecycle, functionName, receipt.hash);
  context.currentSnapshot = nextSnapshot;
  persistWallet(wallet);
  persistCurrentState(context);
  sealWalletOperationDir(operationDir, wallet.walletPassword);

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

function loadWallet(walletName, walletPassword, networkName) {
  const normalizedWalletName = requireWalletName({ wallet: walletName });
  const normalizedNetworkName = requireNetworkName({ network: networkName });
  const walletDir = walletPath(normalizedWalletName, normalizedNetworkName);
  if (!walletConfigExists(walletDir)) {
    throw new Error(`Unknown wallet: ${normalizedWalletName} on ${normalizedNetworkName}.`);
  }
  const rawWallet = readEncryptedWalletJson(walletConfigPath(walletDir), walletPassword);
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
    walletPassword,
  };
  return context;
}

function loadUnlockedWalletWithMetadata(args) {
  const networkName = requireNetworkName(args);
  const wallet = loadWallet(requireWalletName(args), requireL2Password(args), networkName);
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
    throw new Error(`Unknown wallet: ${normalizedWalletName} on ${normalizedNetworkName}.`);
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
    [
      "The workspace snapshot is stale relative to the bridge channel state.",
      `Workspace: ${context.workspaceDir}`,
    ].join(" "),
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
      channelVersion: requireCanonicalTokamakCompatibleBackendVersion(
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

function readTokamakCliPackageReport(packageRoot = null) {
  try {
    const resolvedPackageRoot = packageRoot ?? resolveActiveTokamakCliPackageRoot();
    const packageJsonPath = path.join(resolvedPackageRoot, "package.json");
    const packageJson = readJson(packageJsonPath);
    const report = readPackageReport({
      name: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      packageJsonPath,
      packageJson,
    });
    return {
      ...report,
      compatibleBackendVersion: readTokamakCliCompatibleBackendVersionFromPackageJson(
        packageJson,
        TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      ),
    };
  } catch (error) {
    return {
      name: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      version: null,
      packageRoot: null,
      compatibleBackendVersion: null,
      error: error.message,
      ok: false,
    };
  }
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
      updatedRoot: bytes32FromBigInt(updatedRoot),
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
  const packageRoot = resolveActiveGroth16PackageRoot();
  const entryPath = resolveGroth16CliEntryPath(packageRoot);
  run(process.execPath, [entryPath, "--prove", inputPath], { cwd: packageRoot });
  const manifestPath = groth16ProofManifestPath();
  const manifest = readJson(manifestPath);
  expect(typeof manifest.proofPath === "string" && manifest.proofPath.length > 0, "Groth16 proof manifest is missing proofPath.");
  expect(typeof manifest.publicPath === "string" && manifest.publicPath.length > 0, "Groth16 proof manifest is missing publicPath.");
  return manifest;
}

function groth16ProofManifestPath() {
  return path.join(os.homedir(), "tokamak-private-channels", "groth16", "proof", "proof-manifest.json");
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

function printLocalProofGenerationNotice(operationName) {
  console.error(
    [
      `Starting local zero-knowledge proof generation for ${operationName}.`,
      "This runs on your machine and may take a few minutes.",
    ].join(" "),
  );
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

function buildTokamakTxSnapshot({ signerPrivateKey, senderPubKey, to, data, nonce }) {
  const tx = createTokamakL2Tx(
    {
      nonce: ethers.toBigInt(nonce),
      to: createAddressFromString(to),
      data: hexToBytes(addHexPrefix(String(data ?? "").replace(/^0x/i, ""))),
      senderPubKey,
    },
    { common: createTokamakL2Common() },
  ).sign(signerPrivateKey);

  return serializeBigInts(tx.captureTxSnapshot());
}

async function buildStateManager(snapshot, contractCodes) {
  return createTokamakL2StateManagerFromStateSnapshot(snapshot, {
    contractCodes: contractCodes.map((entry) => ({
      address: createAddressFromString(entry.address),
      code: addHexPrefix(entry.code),
    })),
  });
}

async function currentStorageBigInt(stateManager, address, keyHex) {
  const valueBytes = await stateManager.getStorage(
    createAddressFromString(address),
    hexToBytes(addHexPrefix(String(keyHex ?? "").replace(/^0x/i, ""))),
  );
  if (valueBytes.length === 0) {
    return 0n;
  }
  return bytesToBigInt(valueBytes);
}

function deriveLiquidBalanceStorageKey(l2Address, slot) {
  return bytesToHex(getUserStorageKey([l2Address, ethers.toBigInt(slot)], "TokamakL2"));
}

function deriveChannelTokenVaultLeafIndex(storageKey) {
  return hexToBigInt(addHexPrefix(String(storageKey ?? "").replace(/^0x/i, ""))) % ethers.toBigInt(MAX_MT_LEAVES);
}

async function fetchContractCodes(provider, addresses) {
  const codes = [];
  for (const address of addresses) {
    const code = await provider.getCode(address);
    codes.push({
      address: getAddress(address),
      code,
    });
  }
  return codes;
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

function normalizeBytesHex(value, byteLength) {
  expect(Number.isInteger(byteLength) && byteLength > 0, "normalizeBytesHex requires a positive byte length.");
  const targetHexLength = byteLength * 2;
  let hex;
  if (typeof value === "string") {
    const trimmed = value.trim();
    expect(/^0x[0-9a-fA-F]*$/.test(trimmed), `Expected a hex string, received ${value}.`);
    hex = trimmed.replace(/^0x/i, "");
    if (hex.length % 2 !== 0) {
      hex = `0${hex}`;
    }
  } else {
    hex = ethers.hexlify(value).replace(/^0x/i, "");
  }
  expect(
    hex.length <= targetHexLength,
    `Expected at most ${byteLength} bytes, received ${Math.ceil(hex.length / 2)} bytes.`,
  );
  return `0x${hex.padStart(targetHexLength, "0").toLowerCase()}`;
}

function normalizeBytes12Hex(value) {
  return normalizeBytesHex(value, 12);
}

function normalizeBytes16Hex(value) {
  return normalizeBytesHex(value, 16);
}

function normalizeBytes32Hex(hexValue) {
  return normalizeBytesHex(hexValue, 32);
}

function bytes32FromHex(hexValue) {
  return normalizeBytes32Hex(hexValue);
}

function bytes32FromBigInt(value) {
  return normalizeBytes32Hex(ethers.toBeHex(value));
}

function bigintToHex32(value) {
  return normalizeBytes32Hex(ethers.toBeHex(value));
}

function hashTokamakPublicInputs(values) {
  return keccak256(abiCoder.encode(["uint256[]"], [values]));
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
}) {
  const genesisStateManager = new TokamakL2StateManager({ common: createTokamakL2Common() });
  const managedAddressObjects = managedStorageAddresses.map((address) => createAddressFromString(address));
  await genesisStateManager._initializeForAddresses(managedAddressObjects);
  genesisStateManager._channelId = channelId.toString();
  for (const address of managedAddressObjects) {
    genesisStateManager._commitResolvedStorageEntries(address, []);
  }
  const genesisSnapshot = await genesisStateManager.captureStateSnapshot();

  const bridgeTokenVault = new Contract(
    channelInfo.bridgeTokenVault,
    bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    provider,
  );
  const latestBlock = await provider.getBlockNumber();
  const currentRootVectorObservedTopic =
    normalizeBytes32Hex(channelManager.interface.getEvent("CurrentRootVectorObserved").topicHash);
  const channelManagerLogs = await fetchLogsChunked(provider, {
    address: channelInfo.manager,
    topics: [[
      currentRootVectorObservedTopic,
      CONTROLLER_STORAGE_KEY_OBSERVED_TOPIC,
      VAULT_STORAGE_WRITE_OBSERVED_TOPIC,
    ]],
    fromBlock: genesisBlockNumber,
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
    fromBlock: genesisBlockNumber,
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
  let currentSnapshot = genesisSnapshot;
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
        const storageKey = bytes32FromBigInt(ethers.toBigInt(event.args.storageKey));
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

  return currentSnapshot;
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

function serializeBigInts(value) {
  return JSON.parse(JSON.stringify(value, (_key, current) => (
    typeof current === "bigint" ? current.toString() : current
  )));
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
  if (!parsed.command && parsed.install === true) {
    parsed.command = "--install";
    parsed.positional = ["--install"];
  }
  if (!parsed.command && parsed.doctor === true) {
    parsed.command = "--doctor";
    parsed.positional = ["--doctor"];
  }
  return parsed;
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

function requireL2Password(args) {
  return requireArg(args.password, "--password");
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

function requireAlchemyApiKeyForPublicNetwork(args, commandName) {
  const networkName = requireNetworkName(args);
  if (networkName !== "anvil") {
    requireArg(
      args.alchemyApiKey,
      `--alchemy-api-key (required for ${commandName} on ${networkName})`,
    );
  }
}

function requireL1Signer(args, provider) {
  const privateKey = requireArg(args.privateKey, "--private-key");
  return new Wallet(normalizePrivateKey(privateKey), provider);
}

function channelWorkspacePath(networkName, name) {
  return workspaceDirForName(workspaceRoot, networkName, name);
}

function walletPath(name, networkName = null) {
  const walletName = String(name);
  const { channelName } = parseWalletName(walletName);
  if (networkName) {
    const workspaceDir = channelWorkspacePath(networkName, channelName);
    return walletDirForName(workspaceWalletsDir(workspaceDir), walletName);
  }

  const candidates = resolveWalletPathCandidates(walletName);
  if (candidates.length === 1) {
    return candidates[0];
  }
  if (candidates.length > 1) {
    throw new Error(
      `Wallet ${walletName} exists under multiple networks. Remove duplicates or disambiguate the local workspace layout.`,
    );
  }

  const networkDirs = fs.existsSync(workspaceRoot)
    ? fs.readdirSync(workspaceRoot, { withFileTypes: true }).filter((entry) => entry.isDirectory())
    : [];
  if (networkDirs.length === 0) {
    return walletDirForName(
      workspaceWalletsDir(channelWorkspacePath("unknown-network", channelName)),
      walletName,
    );
  }
  return walletDirForName(
    workspaceWalletsDir(channelWorkspacePath(networkDirs[0].name, channelName)),
    walletName,
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

function assertAllowedCommandKeys(args, commandName, allowedKeys, acceptedUsage) {
  const unsupported = Object.keys(args)
    .filter((key) => !allowedKeys.has(key))
    .map((key) => `--${toKebabCase(key)}`);
  if (unsupported.length > 0) {
    throw new Error(
      `${commandName} only accepts ${acceptedUsage}. Unsupported option(s): ${unsupported.join(", ")}.`,
    );
  }
  expect(
    (args.positional ?? []).length === 1,
    `${commandName} does not accept positional arguments beyond the command name.`,
  );
}

function assertWalletPasswordArgs(args, commandName, extraOptionKeys = [], acceptedUsage = "--wallet, --password, and --network") {
  requireWalletName(args);
  requireL2Password(args);
  requireNetworkName(args);
  assertAllowedCommandKeys(
    args,
    commandName,
    new Set(["command", "positional", "wallet", "password", "network", ...extraOptionKeys]),
    acceptedUsage,
  );
}

function assertWalletChannelMoveArgs(args, commandName) {
  requireArg(args.amount, "--amount");
  assertWalletPasswordArgs(args, commandName, ["amount"], "--wallet, --password, --network, and --amount");
}

function assertInstallZkEvmArgs(args) {
  assertAllowedCommandKeys(
    args,
    "--install",
    new Set([
      "command",
      "positional",
      "install",
      "docker",
      "includeLocalArtifacts",
      "groth16CliVersion",
      "tokamakZkEvmCliVersion",
    ]),
    "optional --docker, --include-local-artifacts, --groth16-cli-version, and --tokamak-zk-evm-cli-version",
  );
  if (args.groth16CliVersion !== undefined) {
    requireSemverVersion(args.groth16CliVersion, "--groth16-cli-version");
  }
  if (args.tokamakZkEvmCliVersion !== undefined) {
    requireSemverVersion(args.tokamakZkEvmCliVersion, "--tokamak-zk-evm-cli-version");
  }
}

function assertUninstallZkEvmArgs(args) {
  assertAllowedCommandKeys(args, "uninstall-zk-evm", new Set(["command", "positional"]), "no options");
}

function assertDoctorArgs(args) {
  assertAllowedCommandKeys(args, "--doctor", new Set(["command", "positional", "doctor"]), "no options");
}

function assertMintNotesArgs(args) {
  requireArg(args.amounts, "--amounts");
  assertWalletPasswordArgs(args, "mint-notes", ["amounts"], "--wallet, --password, --network, and --amounts");
  parseAmountVector(args.amounts, {
    allowZeroEntries: true,
    requireAnyPositive: true,
  });
}

function assertRedeemNotesArgs(args) {
  requireArg(args.noteIds, "--note-ids");
  assertWalletPasswordArgs(args, "redeem-notes", ["noteIds"], "--wallet, --password, --network, and --note-ids");
  selectRedeemNotesMethod(parseNoteIdVector(args.noteIds).length);
}

function assertTransferNotesArgs(args) {
  requireArg(args.noteIds, "--note-ids");
  requireArg(args.recipients, "--recipients");
  requireArg(args.amounts, "--amounts");
  assertWalletPasswordArgs(
    args,
    "transfer-notes",
    ["noteIds", "recipients", "amounts"],
    "--wallet, --password, --network, --note-ids, --recipients, and --amounts",
  );
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
  assertWalletPasswordArgs(args, "get-my-notes", [], "--wallet, --password, and --network");
}

function assertCreateChannelArgs(args) {
  requireArg(args.channelName, "--channel-name");
  requireArg(args.joinFee, "--join-fee");
  requireNetworkName(args);
  requireAlchemyApiKeyForPublicNetwork(args, "create-channel");
  requireArg(args.privateKey, "--private-key");
  assertAllowedCommandKeys(
    args,
    "create-channel",
    new Set(["command", "positional", "channelName", "joinFee", "network", "alchemyApiKey", "privateKey"]),
    "--channel-name, --join-fee, --network, --private-key, and --alchemy-api-key on public networks",
  );
}

function assertRecoverWorkspaceArgs(args) {
  requireArg(args.channelName, "--channel-name");
  requireNetworkName(args);
  requireAlchemyApiKeyForPublicNetwork(args, "recover-workspace");
  assertAllowedCommandKeys(
    args,
    "recover-workspace",
    new Set(["command", "positional", "channelName", "network", "alchemyApiKey"]),
    "--channel-name, --network, and --alchemy-api-key on public networks",
  );
}

function assertDepositBridgeArgs(args) {
  requireArg(args.amount, "--amount");
  requireNetworkName(args);
  requireAlchemyApiKeyForPublicNetwork(args, "deposit-bridge");
  requireArg(args.privateKey, "--private-key");
  assertAllowedCommandKeys(
    args,
    "deposit-bridge",
    new Set(["command", "positional", "amount", "network", "alchemyApiKey", "privateKey"]),
    "--amount, --network, --private-key, and --alchemy-api-key on public networks",
  );
}

function assertGetMyBridgeFundArgs(args) {
  requireNetworkName(args);
  requireAlchemyApiKeyForPublicNetwork(args, "get-my-bridge-fund");
  requireArg(args.privateKey, "--private-key");
  assertAllowedCommandKeys(
    args,
    "get-my-bridge-fund",
    new Set(["command", "positional", "network", "alchemyApiKey", "privateKey"]),
    "--network, --private-key, and --alchemy-api-key on public networks",
  );
}

function assertExplicitSignerPasswordCommandArgs(args, commandName) {
  requireL2Password(args);
  requireArg(args.channelName, "--channel-name");
  requireNetworkName(args);
  requireAlchemyApiKeyForPublicNetwork(args, commandName);
  requireArg(args.privateKey, "--private-key");
  assertAllowedCommandKeys(
    args,
    commandName,
    new Set(["command", "positional", "channelName", "network", "privateKey", "password", "alchemyApiKey"]),
    "--channel-name, --password, --network, --private-key, and --alchemy-api-key on public networks",
  );
}

function assertRecoverWalletArgs(args) {
  assertExplicitSignerPasswordCommandArgs(args, "recover-wallet");
}

function assertJoinChannelArgs(args) {
  assertExplicitSignerPasswordCommandArgs(args, "join-channel");
}

function assertGetMyWalletMetaArgs(args) {
  assertWalletPasswordArgs(args, "get-my-wallet-meta", [], "--wallet, --password, and --network");
}

function assertGetMyL1AddressArgs(args) {
  requireArg(args.privateKey, "--private-key");
  assertAllowedCommandKeys(
    args,
    "get-my-l1-address",
    new Set(["command", "positional", "privateKey"]),
    "--private-key",
  );
}

function assertListLocalWalletsArgs(args) {
  if (args.network !== undefined) {
    requireNetworkName(args);
  }
  if (args.channelName !== undefined) {
    requireArg(args.channelName, "--channel-name");
  }
  assertAllowedCommandKeys(
    args,
    "list-local-wallets",
    new Set(["command", "positional", "network", "channelName"]),
    "optional --network and --channel-name",
  );
}

function assertWithdrawBridgeArgs(args) {
  requireArg(args.amount, "--amount");
  requireNetworkName(args);
  requireAlchemyApiKeyForPublicNetwork(args, "withdraw-bridge");
  requireArg(args.privateKey, "--private-key");
  assertAllowedCommandKeys(
    args,
    "withdraw-bridge",
    new Set(["command", "positional", "amount", "network", "alchemyApiKey", "privateKey"]),
    "--amount, --network, --private-key, and --alchemy-api-key on public networks",
  );
}

function assertGetMyChannelFundArgs(args) {
  assertWalletPasswordArgs(args, "get-my-channel-fund", [], "--wallet, --password, and --network");
}

function assertExitChannelArgs(args) {
  assertWalletPasswordArgs(args, "exit-channel", ["force"], "--wallet, --password, --network, and optional --force");
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
  writeEncryptedWalletJson(path.join(context.walletDir, "wallet.json"), context.wallet, context.walletPassword);
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
  console.log(`
Commands:
  --install [--docker] [--include-local-artifacts] [--groth16-cli-version <VERSION>] [--tokamak-zk-evm-cli-version <VERSION>]
      Install the Tokamak zk-EVM CLI runtime, Groth16 runtime, and private-state deployment artifacts
      Version options install exact CLI package versions; omitted versions resolve to npm registry latest
      Use --docker on Linux to forward Docker mode to the Tokamak zk-EVM and Groth16 runtimes
      Use --include-local-artifacts to also install local deployment/ artifacts from the current working directory

  uninstall-zk-evm
      Remove the Tokamak zk-EVM CLI runtime workspace

  --doctor
      Check private-state CLI package versions, runtime install state, Docker mode, CUDA mode, and deployment artifacts

  create-channel --channel-name <NAME> --join-fee <TOKENS> --network <NAME> --private-key <HEX> --alchemy-api-key <KEY>
      Create a bridge channel and initialize its workspace

  recover-workspace --channel-name <NAME> --network <NAME> --alchemy-api-key <KEY>
      Rebuild the local channel workspace from bridge state

  deposit-bridge --amount <TOKENS> --network <NAME> --private-key <HEX> --alchemy-api-key <KEY>
      Deposit canonical tokens into the shared bridge vault

  withdraw-bridge --amount <TOKENS> --network <NAME> --private-key <HEX> --alchemy-api-key <KEY>
      Withdraw tokens from the shared bridge vault back to the wallet

  get-my-bridge-fund --network <NAME> --private-key <HEX> --alchemy-api-key <KEY>
      Read the current shared bridge vault balance

  recover-wallet --channel-name <NAME> --password <PASSWORD> --network <NAME> --private-key <HEX> --alchemy-api-key <KEY>
      Rebuild a recoverable local wallet from on-chain channel state

  join-channel --channel-name <NAME> --password <PASSWORD> --network <NAME> --private-key <HEX> --alchemy-api-key <KEY>
      Pay the channel join fee and bind a wallet to a channel-specific L2 identity

  get-my-wallet-meta --wallet <NAME> --password <PASSWORD> --network <NAME>
      Check whether a wallet matches the on-chain channel registration

  get-my-l1-address --private-key <HEX>
      Derive the L1 address for a private key

  list-local-wallets [--network <NAME>] [--channel-name <NAME>]
      List saved local wallet names that can be reused with --wallet

  deposit-channel --wallet <NAME> --password <PASSWORD> --network <NAME> --amount <TOKENS>
      Move bridged funds into the channel L2 accounting balance

  withdraw-channel --wallet <NAME> --password <PASSWORD> --network <NAME> --amount <TOKENS>
      Move channel L2 balance back into the shared bridge vault

  get-my-channel-fund --wallet <NAME> --password <PASSWORD> --network <NAME>
      Read the current channel L2 accounting balance

  exit-channel --wallet <NAME> --password <PASSWORD> --network <NAME> [--force]
      Exit a channel. The CLI requires a zero channel balance unless --force is provided

  mint-notes --wallet <NAME> --password <PASSWORD> --network <NAME> --amounts <A,B,...>
      Mint one or two private-state notes from the wallet's channel balance

  transfer-notes --wallet <NAME> --password <PASSWORD> --network <NAME> --note-ids <ID,ID,...> --recipients <ADDR,ADDR,...> --amounts <A,B,...>
      Spend input notes into the registered 1->1, 1->2, or 2->1 private transfer shapes

  redeem-notes --wallet <NAME> --password <PASSWORD> --network <NAME> --note-ids <ID,ID,...>
      Redeem one tracked note back into the wallet's channel balance

  get-my-notes --wallet <NAME> --password <PASSWORD> --network <NAME>
      Show the wallet's tracked note state and refresh received notes

Options:
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

function writeEncryptedWalletJson(filePath, value, walletPassword) {
  const normalizedValue = normalizeCliOutput(value);
  writeEncryptedWalletFile(filePath, Buffer.from(`${JSON.stringify(normalizedValue, null, 2)}\n`, "utf8"), walletPassword);
}

function readEncryptedWalletJson(filePath, walletPassword) {
  try {
    return JSON.parse(readEncryptedWalletFile(filePath, walletPassword).toString("utf8"));
  } catch (error) {
    throw new Error(`Unable to decrypt wallet data at ${filePath}. Check --password.`, { cause: error });
  }
}

function writeEncryptedWalletFile(filePath, plaintextBytes, walletPassword) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const salt = randomBytes(16);
  const encryptionKey = deriveWalletEncryptionKey(walletPassword, salt);
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

function readEncryptedWalletFile(filePath, walletPassword) {
  const envelope = readJson(filePath);
  expect(
    envelope.version === WALLET_ENCRYPTION_VERSION
      && envelope.algorithm === WALLET_ENCRYPTION_ALGORITHM
      && envelope.kdf === "scrypt",
    `Unsupported wallet encryption envelope at ${filePath}.`,
  );
  const encryptionKey = deriveWalletEncryptionKey(walletPassword, Buffer.from(ethers.getBytes(envelope.salt)));
  const decipher = createDecipheriv("aes-256-gcm", encryptionKey, Buffer.from(ethers.getBytes(envelope.iv)));
  decipher.setAuthTag(Buffer.from(ethers.getBytes(envelope.tag)));
  return Buffer.concat([
    decipher.update(Buffer.from(ethers.getBytes(envelope.ciphertext))),
    decipher.final(),
  ]);
}

function deriveWalletEncryptionKey(walletPassword, salt) {
  return scryptSync(String(walletPassword), salt, 32);
}

function sealWalletOperationDir(operationDir, walletPassword) {
  for (const entry of fs.readdirSync(operationDir, { withFileTypes: true })) {
    const targetPath = path.join(operationDir, entry.name);
    if (entry.isDirectory()) {
      sealWalletOperationDir(targetPath, walletPassword);
      continue;
    }
    const plaintextBytes = fs.readFileSync(targetPath);
    writeEncryptedWalletFile(targetPath, plaintextBytes, walletPassword);
  }
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function loadExplicitCommandRuntime(args) {
  const networkName = requireNetworkName(args);
  const network = resolveCliNetwork(networkName);
  const rpcUrl = deriveRpcUrl({
    networkName,
    alchemyApiKey: args.alchemyApiKey,
  });
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
    network: resolveCliNetwork(networkName),
    provider: new JsonRpcProvider(walletMetadata.rpcUrl),
  };
}

function normalizePrivateKey(value) {
  return value.startsWith("0x") ? value : `0x${value}`;
}

function printJson(value) {
  const output = `${JSON.stringify(normalizeCliOutput(value), null, 2)}\n`;
  const outputPath = process.env.PRIVATE_STATE_CLI_JSON_OUTPUT?.trim();
  if (outputPath) {
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, output);
    return;
  }
  console.log(output.trimEnd());
}

function shortAddress(address) {
  return getAddress(address).slice(2, 10).toLowerCase();
}

function expect(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function requireSemverVersion(value, label) {
  const normalized = requireNonEmptyString(value, label);
  if (!EXACT_SEMVER_PATTERN.test(normalized)) {
    throw new Error(`${label} must be an exact semantic version. Received: ${normalized}`);
  }
  return normalized;
}

function normalizeTokamakPackageVersionToCompatibleBackendVersion(value, label = "Tokamak package version") {
  const version = String(value ?? "").trim();
  const match = EXACT_SEMVER_PATTERN.exec(version);
  if (!match) {
    throw new Error(`${label} must be an exact semantic version. Received: ${String(value)}`);
  }
  const [, major, minor] = match;
  return `${Number(major)}.${Number(minor)}`;
}

function requireCanonicalTokamakCompatibleBackendVersion(
  value,
  label = "Tokamak compatible backend version",
) {
  const version = String(value ?? "").trim();
  const match = COMPATIBLE_BACKEND_VERSION_PATTERN.exec(version);
  if (!match) {
    throw new Error(
      `${label} must be a canonical major.minor compatibility version. Received: ${String(value)}`,
    );
  }
  const [, major, minor] = match;
  const canonicalVersion = `${Number(major)}.${Number(minor)}`;
  if (version !== canonicalVersion) {
    throw new Error(`${label} must be canonical ${canonicalVersion}. Received: ${version}`);
  }
  return canonicalVersion;
}

function resolveArtifactCacheBaseRoot(
  cacheBaseRoot = process.env.PRIVATE_STATE_ARTIFACT_CACHE_ROOT
    ?? process.env.TOKAMAK_PRIVATE_CHANNELS_ROOT
    ?? defaultArtifactCacheBaseRoot(),
) {
  return resolveGenericArtifactCacheBaseRoot(cacheBaseRoot);
}

function privateStateCliArtifactRoot(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(resolveArtifactCacheBaseRoot(cacheBaseRoot), "dapps", "private-state");
}

function privateStateCliRuntimeRoot(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(privateStateCliArtifactRoot(cacheBaseRoot), "runtimes");
}

function privateStateCliArtifactChainDir(cacheBaseRoot = resolveArtifactCacheBaseRoot(), chainId) {
  return path.join(privateStateCliArtifactRoot(cacheBaseRoot), `chain-id-${requireChainId(chainId)}`);
}

function privateStateCliArtifactPaths(cacheBaseRoot = resolveArtifactCacheBaseRoot(), chainId) {
  const normalizedChainId = requireChainId(chainId);
  const rootDir = privateStateCliArtifactChainDir(cacheBaseRoot, normalizedChainId);
  return {
    rootDir,
    bridgeDeploymentPath: path.join(rootDir, `bridge.${normalizedChainId}.json`),
    bridgeAbiManifestPath: path.join(rootDir, `bridge-abi-manifest.${normalizedChainId}.json`),
    grothManifestPath: path.join(rootDir, `groth16.${normalizedChainId}.latest.json`),
    grothZkeyPath: path.join(rootDir, "circuit_final.zkey"),
    dappDeploymentPath: path.join(rootDir, `deployment.${normalizedChainId}.latest.json`),
    dappStorageLayoutPath: path.join(rootDir, `storage-layout.${normalizedChainId}.latest.json`),
    privateStateControllerAbiPath: path.join(rootDir, "PrivateStateController.callable-abi.json"),
    dappRegistrationPath: path.join(rootDir, `dapp-registration.${normalizedChainId}.json`),
  };
}

function privateStateCliInstallManifestPath(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(privateStateCliArtifactRoot(cacheBaseRoot), "install-manifest.json");
}

function readPrivateStateCliInstallManifest(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return readJsonIfExists(privateStateCliInstallManifestPath(cacheBaseRoot));
}

function writePrivateStateCliInstallManifest({
  dockerRequested,
  includeLocalArtifacts,
  localDeploymentBaseRoot,
  deploymentArtifacts,
  selectedVersions,
  tokamakCliRuntime,
  groth16Runtime,
}) {
  const manifestPath = privateStateCliInstallManifestPath(deploymentArtifacts.cacheBaseRoot);
  const manifest = {
    installedAt: new Date().toISOString(),
    package: summarizePackageReport(readPackageReport({
      name: "@tokamak-private-dapps/private-state-cli",
      packageJsonPath: path.join(privateStateCliPackageRoot, "package.json"),
    })),
    dependencies: collectDependencyPackageReports().map(summarizePackageReport),
    install: {
      dockerRequested,
      includeLocalArtifacts,
      localDeploymentBaseRoot,
      artifactCacheRoot: deploymentArtifacts.cacheBaseRoot,
      selectedVersions,
      tokamakCliRuntime,
      groth16Runtime,
      installedDeploymentArtifacts: deploymentArtifacts.installed.map((entry) => ({
        chainId: entry.chainId,
        source: entry.source,
        bridgeTimestamp: entry.bridgeTimestamp,
        dappTimestamp: entry.dappTimestamp,
      })),
    },
  };
  writeJson(manifestPath, manifest);
  return { manifestPath, manifest };
}

function summarizePackageReport(report) {
  return {
    name: report.name,
    version: report.version,
  };
}

function buildDoctorReport() {
  const cacheBaseRoot = resolveArtifactCacheBaseRoot();
  const installManifestPath = privateStateCliInstallManifestPath(cacheBaseRoot);
  const installManifest = readJsonIfExists(installManifestPath);
  const dependencyReports = collectDependencyPackageReports(installManifest);
  const tokamakCli = inspectTokamakCliRuntime();
  const groth16Runtime = inspectGroth16Runtime();
  const gpuDockerReadiness = inspectGpuDockerReadiness(tokamakCli);
  const selectedRuntimeVersionCheck = buildSelectedRuntimeVersionCheck({
    installManifest,
    tokamakCli,
    groth16Runtime,
  });
  const checks = [
    {
      name: "dependency package versions",
      ok: dependencyReports.every((entry) => entry.ok),
      details: dependencyReports.map((entry) => ({
        name: entry.name,
        currentVersion: entry.version,
        installVersion: entry.installVersion,
        ok: entry.ok,
        error: entry.error,
      })),
    },
    selectedRuntimeVersionCheck,
    {
      name: "tokamak zk-evm runtime",
      ok: tokamakCli.installed,
      details: {
        doctorStatus: tokamakCli.doctor.status,
        runtimeRoot: tokamakCli.runtimeRoot,
        installations: tokamakCli.installations.map(({ platform, installMode, packageVersion, docker }) => ({
          platform,
          installMode,
          packageVersion,
          dockerEnvironment: docker?.dockerEnvironment ?? null,
          useGpus: docker?.useGpus ?? null,
        })),
      },
    },
    {
      name: "tokamak docker gpu readiness",
      ok: gpuDockerReadiness.ok,
      details: {
        expectedUseGpus: gpuDockerReadiness.expectedUseGpus,
        liveUseGpus: gpuDockerReadiness.liveUseGpus,
        mismatch: gpuDockerReadiness.mismatch,
        mismatchError: gpuDockerReadiness.mismatchError,
        hostNvidiaSmi: summarizeProbeResult(gpuDockerReadiness.hostNvidiaSmi),
        dockerNvidiaSmi: summarizeProbeResult(gpuDockerReadiness.dockerNvidiaSmi),
      },
    },
    {
      name: "groth16 runtime",
      ok: groth16Runtime.installed,
      details: {
        packageRoot: groth16Runtime.packageRoot,
        workspaceRoot: groth16Runtime.workspaceRoot,
        doctorStatus: groth16Runtime.doctor.status,
        checks: groth16Runtime.checks,
      },
    },
  ];

  return {
    action: "doctor",
    ok: checks.every((check) => check.ok),
    generatedAt: new Date().toISOString(),
    package: readPackageReport({
      name: "@tokamak-private-dapps/private-state-cli",
      packageJsonPath: path.join(privateStateCliPackageRoot, "package.json"),
    }),
    installManifest: {
      path: installManifestPath,
      exists: Boolean(installManifest),
      installedAt: installManifest?.installedAt ?? null,
      dockerRequested: installManifest?.install?.dockerRequested ?? null,
      includeLocalArtifacts: installManifest?.install?.includeLocalArtifacts ?? null,
      selectedVersions: installManifest?.install?.selectedVersions ?? null,
      tokamakCliRuntime: installManifest?.install?.tokamakCliRuntime ?? null,
      groth16Runtime: installManifest?.install?.groth16Runtime ?? null,
    },
    dependencies: dependencyReports,
    tokamakCli,
    groth16Runtime,
    gpuDockerReadiness,
    checks,
  };
}

function buildSelectedRuntimeVersionCheck({ installManifest, tokamakCli, groth16Runtime }) {
  const selectedVersions = installManifest?.install?.selectedVersions ?? null;
  const selectedTokamakCompatibleBackendVersion = selectedVersions?.tokamak
    ? normalizeTokamakPackageVersionToCompatibleBackendVersion(
      selectedVersions.tokamak,
      "selected Tokamak zk-EVM CLI version",
    )
    : null;
  const selectedGroth16CompatibleBackendVersion = selectedVersions?.groth16
    ? normalizeGroth16PackageVersionToCompatibleBackendVersion(selectedVersions.groth16, "selected Groth16 CLI version")
    : null;
  const details = [
    {
      name: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      selectedVersion: selectedVersions?.tokamak ?? null,
      selectedCompatibleBackendVersion: selectedTokamakCompatibleBackendVersion,
      installedVersion: tokamakCli.packageVersion ?? null,
      compatibleBackendVersion: tokamakCli.compatibleBackendVersion ?? null,
      ok: !selectedVersions?.tokamak
        || (
          selectedVersions.tokamak === tokamakCli.packageVersion
          && selectedTokamakCompatibleBackendVersion === tokamakCli.compatibleBackendVersion
        ),
    },
    {
      name: GROTH16_PACKAGE_NAME,
      selectedVersion: selectedVersions?.groth16 ?? null,
      selectedCompatibleBackendVersion: selectedGroth16CompatibleBackendVersion,
      installedVersion: groth16Runtime.packageVersion ?? null,
      compatibleBackendVersion: groth16Runtime.compatibleBackendVersion ?? null,
      crsVersion: groth16Runtime.crsVersion ?? null,
      crsCompatibleBackendVersion: groth16Runtime.crsCompatibleBackendVersion ?? null,
      ok: !selectedVersions?.groth16
        || (
          selectedVersions.groth16 === groth16Runtime.packageVersion
          && selectedGroth16CompatibleBackendVersion === groth16Runtime.compatibleBackendVersion
          && selectedGroth16CompatibleBackendVersion === groth16Runtime.crsCompatibleBackendVersion
        ),
    },
  ];
  return {
    name: "selected proof backend runtime versions",
    ok: details.every((entry) => entry.ok),
    details,
  };
}

async function resolvePrivateStateInstallRuntimeVersions(args) {
  const [groth16, tokamak] = await Promise.all([
    resolveRequestedNpmPackageVersion({
      packageName: GROTH16_PACKAGE_NAME,
      requestedVersion: args.groth16CliVersion,
      optionName: "--groth16-cli-version",
    }),
    resolveRequestedNpmPackageVersion({
      packageName: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      requestedVersion: args.tokamakZkEvmCliVersion,
      optionName: "--tokamak-zk-evm-cli-version",
    }),
  ]);
  return { groth16, tokamak };
}

async function resolveRequestedNpmPackageVersion({ packageName, requestedVersion, optionName }) {
  const metadata = await fetchNpmPackageMetadata(packageName);
  if (requestedVersion === undefined || requestedVersion === null) {
    return requireSemverVersion(metadata?.["dist-tags"]?.latest, `${packageName} npm latest version`);
  }

  const normalizedVersion = requireSemverVersion(requestedVersion, optionName);
  if (!metadata.versions?.[normalizedVersion]) {
    throw new Error(`npm package ${packageName} does not contain version ${normalizedVersion}.`);
  }
  return normalizedVersion;
}

async function fetchNpmPackageMetadata(packageName) {
  const normalizedPackageName = requireNonEmptyString(packageName, "packageName");
  const registryUrl = `https://registry.npmjs.org/${encodeURIComponent(normalizedPackageName)}`;
  const response = await fetch(registryUrl, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`Failed to read npm package metadata for ${normalizedPackageName}: HTTP ${response.status}.`);
  }
  try {
    return await response.json();
  } catch (error) {
    throw new Error(`npm package metadata for ${normalizedPackageName} is not valid JSON: ${error.message}`);
  }
}

async function installTokamakCliRuntimeForPrivateState({ version, docker }) {
  const packageInstall = installManagedNpmPackage({
    packageName: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
    version,
  });
  const invocation = buildTokamakCliInvocationForPackageRoot(packageInstall.packageRoot);
  const installArgs = [...invocation.args, "--install"];
  if (docker) {
    installArgs.push("--docker");
  }
  run(invocation.command, installArgs, { cwd: packageInstall.packageRoot });
  const doctor = runCaptured(invocation.command, [...invocation.args, "--doctor"], {
    cwd: packageInstall.packageRoot,
  });
  const doctorOutput = stripAnsi(`${doctor.stdout}${doctor.stderr}`);
  const runtimeRoot = parseRuntimeRootFromTokamakDoctorOutput(doctorOutput);
  const compatibleBackendVersion = readTokamakCliPackageCompatibleBackendVersion(packageInstall.packageRoot);
  expect(
    doctor.status === 0 && runtimeRoot,
    [
      "Tokamak zk-EVM CLI install completed, but tokamak-cli --doctor did not report a healthy runtime.",
      doctorOutput.trim(),
    ].filter(Boolean).join(" "),
  );
  return {
    packageName: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
    packageVersion: version,
    compatibleBackendVersion,
    packageRoot: packageInstall.packageRoot,
    entryPath: invocation.entryPath,
    installPrefix: packageInstall.installPrefix,
    runtimeRoot,
    dockerRequested: Boolean(docker),
  };
}

async function installGroth16RuntimeForPrivateState({ version, docker }) {
  const packageInstall = installManagedNpmPackage({
    packageName: GROTH16_PACKAGE_NAME,
    version,
  });
  const packageRoot = packageInstall.packageRoot;
  const entryPath = resolveGroth16CliEntryPath(packageRoot);
  const args = [entryPath, "--install", "--no-setup"];
  if (docker) {
    args.push("--docker");
  }
  run(process.execPath, args, { cwd: packageRoot });
  const compatibleBackendVersion = readGroth16PackageCompatibleBackendVersion(packageRoot);
  const crsInstall = await installGroth16CrsForPrivateStateVersion(compatibleBackendVersion);
  const runtime = inspectGroth16Runtime({ packageRoot });
  expect(runtime.installed, "Groth16 runtime install completed, but tokamak-groth16 --doctor still reports an unhealthy runtime.");
  return {
    ...runtime,
    packageName: GROTH16_PACKAGE_NAME,
    packageVersion: version,
    compatibleBackendVersion,
    packageRoot,
    entryPath,
    installPrefix: packageInstall.installPrefix,
    crsVersion: crsInstall.version,
    crs: crsInstall,
    dockerRequested: Boolean(docker),
  };
}

async function installGroth16CrsForPrivateStateVersion(version) {
  const workspaceRoot = defaultGroth16WorkspaceRoot();
  const crsDir = path.join(workspaceRoot, "crs");
  const crsInstall = await downloadPublicGroth16MpcArtifactsByVersion({
    version,
    outputDir: crsDir,
    selectedFiles: [
      "circuit_final.zkey",
      "verification_key.json",
      "metadata.json",
      "zkey_provenance.json",
    ],
  });
  const manifestPath = path.join(workspaceRoot, "install-manifest.json");
  const manifest = readJsonIfExists(manifestPath) ?? {};
  writeJson(manifestPath, {
    ...manifest,
    workspaceRoot,
    crsSource: "public-drive-mpc",
    crs: crsInstall,
  });
  return crsInstall;
}

function installManagedNpmPackage({ packageName, version, cacheBaseRoot = resolveArtifactCacheBaseRoot() }) {
  const normalizedPackageName = requireNonEmptyString(packageName, "packageName");
  const normalizedVersion = requireSemverVersion(version, `${normalizedPackageName} version`);
  const installPrefix = managedNpmPackageInstallPrefix({
    packageName: normalizedPackageName,
    version: normalizedVersion,
    cacheBaseRoot,
  });
  fs.mkdirSync(installPrefix, { recursive: true });
  run("npm", [
    "install",
    "--prefix",
    installPrefix,
    "--omit=dev",
    "--no-audit",
    "--fund=false",
    `${normalizedPackageName}@${normalizedVersion}`,
  ]);
  const packageRoot = path.join(installPrefix, "node_modules", ...normalizedPackageName.split("/"));
  const packageJsonPath = path.join(packageRoot, "package.json");
  const packageJson = readJson(packageJsonPath);
  expect(
    packageJson.name === normalizedPackageName && packageJson.version === normalizedVersion,
    `Installed package ${packageJsonPath} does not match ${normalizedPackageName}@${normalizedVersion}.`,
  );
  return {
    packageName: normalizedPackageName,
    version: normalizedVersion,
    installPrefix,
    packageRoot,
  };
}

function managedNpmPackageInstallPrefix({ packageName, version, cacheBaseRoot = resolveArtifactCacheBaseRoot() }) {
  const safePackageName = requireNonEmptyString(packageName, "packageName")
    .replace(/^@/, "")
    .replace(/[^A-Za-z0-9._-]+/g, "__");
  return path.join(privateStateCliRuntimeRoot(cacheBaseRoot), "npm", safePackageName, requireSemverVersion(version, "version"));
}

async function downloadGroth16CrsArtifactsForPrivateState({
  version,
  outputDir,
  selectedFiles,
}) {
  if (version === undefined || version === null) {
    return downloadLatestPublicGroth16MpcArtifacts({ outputDir, selectedFiles });
  }
  return downloadPublicGroth16MpcArtifactsByVersion({ version, outputDir, selectedFiles });
}

function collectDependencyPackageReports(installManifest = null) {
  const installVersions = new Map(
    Array.isArray(installManifest?.dependencies)
      ? installManifest.dependencies.map((entry) => [entry.name, entry.version])
      : [],
  );
  const targets = [
    {
      name: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      packageJsonPath: path.join(resolveBundledTokamakCliPackageRoot(), "package.json"),
    },
    {
      name: GROTH16_PACKAGE_NAME,
      resolveTarget: "@tokamak-private-dapps/groth16/public-drive-crs",
    },
    {
      name: "@tokamak-private-dapps/common-library",
      resolveTarget: "@tokamak-private-dapps/common-library/artifact-cache",
    },
    { name: "tokamak-l2js", resolveTarget: "tokamak-l2js" },
  ];

  return targets.map((target) => {
    const report = readPackageReport(target);
    const installVersion = installVersions.get(report.name) ?? null;
    return {
      ...report,
      installVersion,
      ok: Boolean(report.version) && (installVersion === null || installVersion === report.version),
    };
  });
}

function readPackageReport({ name, packageJsonPath = null, packageJson = null, resolveTarget = null }) {
  try {
    const resolvedPackageJsonPath = packageJsonPath
      ? path.resolve(packageJsonPath)
      : findPackageJsonForName(path.dirname(require.resolve(resolveTarget ?? name)), name);
    const resolvedPackageJson = packageJson ?? readJson(resolvedPackageJsonPath);
    return {
      name: resolvedPackageJson.name ?? name,
      version: resolvedPackageJson.version ?? null,
      packageRoot: path.dirname(resolvedPackageJsonPath),
      error: null,
    };
  } catch (error) {
    return {
      name,
      version: null,
      packageRoot: null,
      error: error.message,
      ok: false,
    };
  }
}

function findPackageJsonForName(startDir, expectedName) {
  let current = path.resolve(startDir);
  while (current !== path.dirname(current)) {
    const candidate = path.join(current, "package.json");
    if (fs.existsSync(candidate)) {
      const packageJson = readJson(candidate);
      if (packageJson.name === expectedName) {
        return candidate;
      }
    }
    current = path.dirname(current);
  }
  throw new Error(`Cannot locate package.json for ${expectedName} above ${startDir}.`);
}

function resolveGroth16PackageRoot() {
  const publicDriveCrsPath = require.resolve("@tokamak-private-dapps/groth16/public-drive-crs");
  return path.dirname(findPackageJsonForName(path.dirname(publicDriveCrsPath), "@tokamak-private-dapps/groth16"));
}

function readGroth16PackageCompatibleBackendVersion(packageRoot = resolveActiveGroth16PackageRoot()) {
  return readGroth16CompatibleBackendVersionFromPackageJson(
    readJson(path.join(packageRoot, "package.json")),
    GROTH16_PACKAGE_NAME,
  );
}

function readTokamakCliPackageCompatibleBackendVersion(packageRoot = resolveActiveTokamakCliPackageRoot()) {
  return readTokamakCliCompatibleBackendVersionFromPackageJson(
    readJson(path.join(packageRoot, "package.json")),
    TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
  );
}

function readTokamakCliCompatibleBackendVersionFromPackageJson(packageJson, label = "Tokamak zk-EVM CLI package") {
  const packageVersion = normalizeTokamakPackageVersionToCompatibleBackendVersion(
    packageJson?.version,
    `${label} version`,
  );
  const configuredVersion = packageJson?.tokamakZkEvm?.compatibleBackendVersion;
  if (configuredVersion === undefined || configuredVersion === null) {
    throw new Error(`${label} tokamakZkEvm.compatibleBackendVersion is missing.`);
  }

  const compatibleVersion = requireCanonicalTokamakCompatibleBackendVersion(
    configuredVersion,
    `${label} tokamakZkEvm.compatibleBackendVersion`,
  );
  if (compatibleVersion !== packageVersion) {
    throw new Error(
      `${label} compatible backend version ${compatibleVersion} must match package major.minor ${packageVersion}.`,
    );
  }
  return compatibleVersion;
}

function resolveActiveGroth16PackageRoot() {
  const manifestPackageRoot = readPrivateStateCliInstallManifest()?.install?.groth16Runtime?.packageRoot;
  if (manifestPackageRoot && fs.existsSync(path.join(manifestPackageRoot, "package.json"))) {
    return manifestPackageRoot;
  }
  return resolveGroth16PackageRoot();
}

function resolveGroth16CliEntryPath(packageRoot = resolveGroth16PackageRoot()) {
  return path.join(packageRoot, "cli", "tokamak-groth16-cli.mjs");
}

function defaultGroth16WorkspaceRoot() {
  return path.join(os.homedir(), "tokamak-private-channels", "groth16");
}

function inspectGroth16Runtime({ packageRoot = resolveActiveGroth16PackageRoot() } = {}) {
  const entryPath = resolveGroth16CliEntryPath(packageRoot);
  const doctor = runCaptured(process.execPath, [entryPath, "--doctor", "--verbose"], { cwd: packageRoot });
  const stdout = stripAnsi(doctor.stdout).trim();
  const stderr = stripAnsi(doctor.stderr).trim();
  const report = parseJsonReport(stdout);
  const workspaceRoot = report?.workspaceRoot ?? defaultGroth16WorkspaceRoot();
  const workspaceManifest = readJsonIfExists(path.join(workspaceRoot, "install-manifest.json"));
  const crsVersion = workspaceManifest?.crs?.version ?? null;
  const packageReport = readPackageReport({
    name: GROTH16_PACKAGE_NAME,
    packageJsonPath: path.join(packageRoot, "package.json"),
  });
  const compatibleBackendVersion = readGroth16PackageCompatibleBackendVersion(packageRoot);
  const crsCompatibleBackendVersion = crsVersion
    ? requireCanonicalGroth16CompatibleBackendVersion(crsVersion, "installed Groth16 CRS version")
    : null;
  return {
    installed: doctor.status === 0 && report?.ok === true,
    packageVersion: packageReport.version,
    compatibleBackendVersion,
    packageRoot,
    entryPath,
    workspaceRoot: report?.workspaceRoot ?? null,
    crsVersion,
    crsCompatibleBackendVersion,
    crs: workspaceManifest?.crs ?? null,
    checks: report?.checks ?? [],
    doctor: {
      status: doctor.status,
      stdout,
      stderr,
    },
  };
}

function resolveActiveTokamakCliPackageRoot() {
  const manifestPackageRoot = readPrivateStateCliInstallManifest()?.install?.tokamakCliRuntime?.packageRoot;
  if (manifestPackageRoot && fs.existsSync(path.join(manifestPackageRoot, "package.json"))) {
    return manifestPackageRoot;
  }
  return resolveBundledTokamakCliPackageRoot();
}

function buildTokamakCliInvocationForPackageRoot(packageRoot = resolveActiveTokamakCliPackageRoot()) {
  const resolvedPackageRoot = path.resolve(packageRoot);
  const entryPath = resolvedPackageRoot === resolveBundledTokamakCliPackageRoot()
    ? resolveTokamakCliEntryPath()
    : path.join(resolvedPackageRoot, "dist", "cli.js");
  return {
    command: process.execPath,
    args: [entryPath],
    entryPath,
    packageRoot: resolvedPackageRoot,
  };
}

function resolveTokamakCliResourceDirForRuntimeRoot(runtimeRoot, ...segments) {
  return path.join(runtimeRoot, "resource", ...segments);
}

function requireActiveTokamakCliRuntimeRoot() {
  const runtime = inspectTokamakCliRuntime();
  expect(runtime.runtimeRoot, "Unable to resolve the installed Tokamak zk-EVM runtime root. Run --install first.");
  return runtime.runtimeRoot;
}

function inspectTokamakCliRuntime({ packageRoot = resolveActiveTokamakCliPackageRoot() } = {}) {
  const invocation = buildTokamakCliInvocationForPackageRoot(packageRoot);
  const packageReport = readTokamakCliPackageReport(invocation.packageRoot);
  const doctor = runCaptured(invocation.command, [...invocation.args, "--doctor"], {
    cwd: invocation.packageRoot,
  });
  const doctorOutput = stripAnsi(`${doctor.stdout}${doctor.stderr}`);
  const runtimeRoot = parseRuntimeRootFromTokamakDoctorOutput(doctorOutput);
  const cacheRoot = resolveTokamakCliCacheRoot();
  const installations = readTokamakCliInstallations(cacheRoot);
  const dockerModeInstalled = installations.some((entry) => entry.installMode === "docker" || entry.docker);
  const cudaCompatible = installations.some((entry) => entry.docker?.useGpus === true);

  return {
    installed: doctor.status === 0 || installations.length > 0,
    packageRoot: invocation.packageRoot,
    entryPath: invocation.entryPath,
    cacheRoot,
    runtimeRoot,
    packageVersion: packageReport.version,
    compatibleBackendVersion: packageReport.compatibleBackendVersion,
    packageError: packageReport.error,
    dockerModeInstalled,
    cudaCompatible,
    doctor: {
      status: doctor.status,
      stdout: stripAnsi(doctor.stdout).trim(),
      stderr: stripAnsi(doctor.stderr).trim(),
    },
    installations,
  };
}

function inspectGpuDockerReadiness(tokamakCli) {
  const hostNvidiaSmi = runProbe("nvidia-smi", ["--query-gpu=name,driver_version", "--format=csv,noheader"]);
  const dockerNvidiaSmi = runProbe("docker", [
    "run",
    "--rm",
    "--gpus",
    "all",
    DOCKER_CUDA_PROBE_IMAGE,
    "nvidia-smi",
  ]);
  const expectedUseGpus = Boolean(tokamakCli.cudaCompatible);
  const liveUseGpus = hostNvidiaSmi.ok && dockerNvidiaSmi.ok;
  const mismatch = expectedUseGpus !== liveUseGpus;
  return {
    ok: !mismatch,
    expectedUseGpus,
    liveUseGpus,
    mismatch,
    mismatchError: mismatch
      ? [
        "Tokamak CLI Docker GPU metadata does not match live NVIDIA/Docker GPU probes.",
        `metadata useGpus=${expectedUseGpus}; live useGpus=${liveUseGpus}.`,
      ].join(" ")
      : null,
    probeImage: DOCKER_CUDA_PROBE_IMAGE,
    hostNvidiaSmi,
    dockerNvidiaSmi,
  };
}

function runProbe(command, args) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    timeout: DOCTOR_GPU_PROBE_TIMEOUT_MS,
    stdio: ["ignore", "pipe", "pipe"],
  });
  return {
    command,
    args,
    ok: !result.error && result.status === 0,
    status: result.status,
    signal: result.signal,
    error: result.error ? result.error.message : null,
    stdout: stripAnsi(result.stdout ?? "").trim(),
    stderr: stripAnsi(result.stderr ?? "").trim(),
    timedOut: result.error?.code === "ETIMEDOUT",
  };
}

function summarizeProbeResult(result) {
  return {
    command: [result.command, ...result.args].join(" "),
    ok: result.ok,
    status: result.status,
    signal: result.signal,
    error: result.error,
    timedOut: result.timedOut,
    stdout: truncateText(result.stdout, 2000),
    stderr: truncateText(result.stderr, 2000),
  };
}

function truncateText(value, maxLength) {
  const text = String(value ?? "");
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, maxLength)}...`;
}

function parseJsonReport(value) {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function resolveTokamakCliCacheRoot() {
  return path.resolve(process.env.TOKAMAK_ZKEVM_CLI_CACHE_DIR ?? path.join(os.homedir(), ".tokamak-zk-evm"));
}

function readTokamakCliInstallations(cacheRoot) {
  if (!fs.existsSync(cacheRoot)) {
    return [];
  }
  return fs.readdirSync(cacheRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const platformDir = path.join(cacheRoot, entry.name);
      const statePath = path.join(platformDir, "installation.json");
      if (!fs.existsSync(statePath)) {
        return null;
      }
      const state = readJsonIfExists(statePath);
      const dockerBootstrapPath = path.join(platformDir, "docker", "bootstrap.json");
      const docker = readJsonIfExists(dockerBootstrapPath);
      return {
        platform: entry.name,
        statePath,
        runtimeRoot: path.join(platformDir, "runtime"),
        installMode: state?.installMode ?? (docker ? "docker" : null),
        packageVersion: state?.packageVersion ?? docker?.packageVersion ?? null,
        installedAt: state?.installedAt ?? null,
        dockerBootstrapPath,
        docker,
      };
    })
    .filter(Boolean);
}

function parseRuntimeRootFromTokamakDoctorOutput(output) {
  const match = String(output ?? "").match(/^\[ ok \] Runtime workspace:\s*(.+)$/m);
  return match ? path.resolve(match[1].trim()) : null;
}

function stripAnsi(value) {
  return String(value ?? "").replace(/\u001b\[[0-9;]*m/g, "");
}

async function installPrivateStateCliArtifacts({
  dappName,
  indexFileId = process.env.PRIVATE_STATE_DRIVE_ARTIFACT_INDEX_FILE_ID
    ?? process.env.TOKAMAK_ARTIFACT_INDEX_FILE_ID
    ?? DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  cacheBaseRoot,
  localDeploymentBaseRoot,
  localChainIds = [31337],
  groth16CrsVersion,
} = {}) {
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const normalizedCacheBaseRoot = resolveArtifactCacheBaseRoot(cacheBaseRoot);
  const normalizedLocalDeploymentBaseRoot = localDeploymentBaseRoot
    ? path.resolve(localDeploymentBaseRoot)
    : null;
  const index = await fetchPublicArtifactIndex(indexFileId);
  const installed = [];

  for (const chainId of Object.keys(index.chains).sort(compareChainIds)) {
    const chain = index.chains[chainId];
    if (!chain?.bridge?.timestamp || !chain?.bridge?.files || !chain.dapps?.[normalizedDappName]) {
      continue;
    }
    installed.push(await materializePrivateStateCliDeployment({
      index,
      chainId,
      dappName: normalizedDappName,
      cacheBaseRoot: normalizedCacheBaseRoot,
      source: "drive",
      groth16CrsVersion,
    }));
  }

  if (normalizedLocalDeploymentBaseRoot) {
    for (const chainId of localChainIds) {
      installed.push(await materializeLocalPrivateStateCliDeployment({
        chainId,
        dappName: normalizedDappName,
        cacheBaseRoot: normalizedCacheBaseRoot,
        localDeploymentBaseRoot: normalizedLocalDeploymentBaseRoot,
        groth16CrsVersion,
      }));
    }
  }

  if (installed.length === 0) {
    throw new Error(`No installable artifacts found for ${normalizedDappName}.`);
  }

  return {
    cacheBaseRoot: normalizedCacheBaseRoot,
    artifactRoot: privateStateCliArtifactRoot(normalizedCacheBaseRoot),
    installed,
  };
}

async function materializePrivateStateCliDeployment({
  index,
  chainId,
  dappName,
  cacheBaseRoot,
  source,
  groth16CrsVersion,
}) {
  const normalizedChainId = String(requireChainId(chainId));
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const chain = index.chains[normalizedChainId];
  if (!chain) {
    throw new Error(`Drive artifact index does not contain chain ${normalizedChainId}.`);
  }
  if (!chain.bridge?.timestamp || !chain.bridge?.files) {
    throw new Error(`Drive artifact index is missing bridge artifacts for chain ${normalizedChainId}.`);
  }

  const dapp = chain.dapps?.[normalizedDappName];
  if (!dapp?.timestamp || !dapp?.files) {
    throw new Error(
      `Drive artifact index is missing ${normalizedDappName} artifacts for chain ${normalizedChainId}.`,
    );
  }

  const paths = privateStateCliArtifactPaths(cacheBaseRoot, normalizedChainId);
  fs.rmSync(paths.rootDir, { recursive: true, force: true });
  fs.mkdirSync(paths.rootDir, { recursive: true });

  await materializeSelectedDriveFiles({
    targetDir: paths.rootDir,
    files: chain.bridge.files,
    selectedFiles: [
      [`bridge.${normalizedChainId}.json`, path.basename(paths.bridgeDeploymentPath)],
      [`bridge-abi-manifest.${normalizedChainId}.json`, path.basename(paths.bridgeAbiManifestPath)],
      [`groth16.${normalizedChainId}.latest.json`, path.basename(paths.grothManifestPath)],
    ],
  });
  await downloadGroth16CrsArtifactsForPrivateState({
    version: groth16CrsVersion,
    outputDir: paths.rootDir,
    selectedFiles: [
      ["circuit_final.zkey", path.basename(paths.grothZkeyPath)],
    ],
  });
  await materializeSelectedDriveFiles({
    targetDir: paths.rootDir,
    files: dapp.files,
    selectedFiles: [
      [`deployment.${normalizedChainId}.latest.json`, path.basename(paths.dappDeploymentPath)],
      [`storage-layout.${normalizedChainId}.latest.json`, path.basename(paths.dappStorageLayoutPath)],
      ["PrivateStateController.callable-abi.json", path.basename(paths.privateStateControllerAbiPath)],
      [`dapp-registration.${normalizedChainId}.json`, path.basename(paths.dappRegistrationPath)],
    ],
  });
  rewriteFlatGroth16Manifest(paths.grothManifestPath, paths.grothZkeyPath);

  return {
    chainId: Number(normalizedChainId),
    source,
    artifactDir: paths.rootDir,
    bridgeTimestamp: chain.bridge.timestamp,
    dappTimestamp: dapp.timestamp,
  };
}

async function materializeLocalPrivateStateCliDeployment({
  chainId,
  dappName,
  cacheBaseRoot,
  localDeploymentBaseRoot,
  groth16CrsVersion,
}) {
  const normalizedChainId = String(requireChainId(chainId));
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const bridgeRoot = path.join(
    localDeploymentBaseRoot,
    "deployment",
    `chain-id-${normalizedChainId}`,
    "bridge",
  );
  const dappRoot = path.join(
    localDeploymentBaseRoot,
    "deployment",
    `chain-id-${normalizedChainId}`,
    "dapps",
    normalizedDappName,
  );
  const bridgeTimestamp = requireLatestTimestampLabel(bridgeRoot, `bridge artifacts for chain ${normalizedChainId}`);
  const dappTimestamp = requireLatestTimestampLabel(dappRoot, `${normalizedDappName} artifacts for chain ${normalizedChainId}`);
  const bridgeDir = path.join(bridgeRoot, bridgeTimestamp);
  const dappDir = path.join(dappRoot, dappTimestamp);
  const paths = privateStateCliArtifactPaths(cacheBaseRoot, normalizedChainId);
  fs.rmSync(paths.rootDir, { recursive: true, force: true });
  fs.mkdirSync(paths.rootDir, { recursive: true });

  materializeSelectedLocalFiles({
    targetDir: paths.rootDir,
    selectedFiles: [
      [path.join(bridgeDir, `bridge.${normalizedChainId}.json`), path.basename(paths.bridgeDeploymentPath)],
      [path.join(bridgeDir, `bridge-abi-manifest.${normalizedChainId}.json`), path.basename(paths.bridgeAbiManifestPath)],
      [path.join(bridgeDir, `groth16.${normalizedChainId}.latest.json`), path.basename(paths.grothManifestPath)],
      [path.join(dappDir, `deployment.${normalizedChainId}.latest.json`), path.basename(paths.dappDeploymentPath)],
      [path.join(dappDir, `storage-layout.${normalizedChainId}.latest.json`), path.basename(paths.dappStorageLayoutPath)],
      [path.join(dappDir, "PrivateStateController.callable-abi.json"), path.basename(paths.privateStateControllerAbiPath)],
      [path.join(dappDir, `dapp-registration.${normalizedChainId}.json`), path.basename(paths.dappRegistrationPath)],
    ],
  });
  await downloadGroth16CrsArtifactsForPrivateState({
    version: groth16CrsVersion,
    outputDir: paths.rootDir,
    selectedFiles: [
      ["circuit_final.zkey", path.basename(paths.grothZkeyPath)],
    ],
  });
  rewriteFlatGroth16Manifest(paths.grothManifestPath, paths.grothZkeyPath);

  return {
    chainId: Number(normalizedChainId),
    source: "local",
    artifactDir: paths.rootDir,
    bridgeTimestamp,
    dappTimestamp,
  };
}

function rewriteFlatGroth16Manifest(manifestPath, zkeyPath) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.artifactDir = ".";
  manifest.grothArtifactSource = "public-drive-mpc";
  manifest.publicGroth16MpcDriveFolderId = PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID;
  manifest.artifacts = {
    ...manifest.artifacts,
    zkeyPath: path.basename(zkeyPath),
    metadataPath: null,
    verificationKeyPath: null,
    zkeyProvenancePath: null,
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
}

function compareChainIds(left, right) {
  return Number(left) - Number(right);
}

main().catch((error) => {
  console.error(error.message ?? String(error));
  process.exitCode = 1;
});
