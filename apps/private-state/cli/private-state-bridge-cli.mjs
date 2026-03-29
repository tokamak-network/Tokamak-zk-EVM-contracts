#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
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
  createTokamakL2Common,
  createTokamakL2StateManagerFromStateSnapshot,
  createTokamakL2Tx,
  deriveL2KeysFromSignature,
  fromEdwardsToAddress,
  getUserStorageKey,
  poseidon,
} from "tokamak-l2js";
import { jubjub } from "@noble/curves/jubjub";
import {
  addHexPrefix,
  bytesToBigInt,
  bytesToHex,
  createAddressFromString,
  hexToBytes,
} from "@ethereumjs/util";
import { deriveRpcUrl, resolveCliNetwork } from "../../script/network-config.mjs";
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
} from "./private-state-cli-shared.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../..");
const appsRoot = path.resolve(projectRoot, "apps");
const appRoot = path.resolve(projectRoot, "apps/private-state");
const deployRoot = path.resolve(appRoot, "deploy");
const bridgeRoot = path.resolve(projectRoot, "bridge");
const workspaceRoot = path.resolve(__dirname, "workspace");
const defaultEnvFile = path.resolve(appsRoot, ".env");
const tokamakRoot = path.resolve(projectRoot, "submodules", "Tokamak-zk-EVM");
const tokamakCliPath = path.resolve(tokamakRoot, "tokamak-cli");

const abiCoder = AbiCoder.defaultAbiCoder();
const erc20MetadataAbi = [
  "function decimals() view returns (uint8)",
];
const TOKAMAK_APUB_BLOCK_LENGTH = 68;
const TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT = 4;
const WALLET_ENCRYPTION_VERSION = 1;
const WALLET_ENCRYPTION_ALGORITHM = "aes-256-gcm";
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
const NOTE_RECEIVE_FIELD_ENCRYPTION_INFO = "PRIVATE_STATE_NOTE_FIELD_ENCRYPTION_V1";
const NOTE_RECEIVE_EVENT_ABI = [
  "event NoteValueEncrypted(bytes32[3] encryptedNoteValue)",
];
const noteValueEncryptedEventInterface = new Interface(NOTE_RECEIVE_EVENT_ABI);
const NOTE_VALUE_ENCRYPTED_TOPIC = noteValueEncryptedEventInterface.getEvent("NoteValueEncrypted").topicHash;
const JUBJUB_ORDER = jubjub.CURVE.n;
const JUBJUB_FP = jubjub.CURVE.Fp;
const JUBJUB_A = jubjub.CURVE.a;
const JUBJUB_D = jubjub.CURVE.d;
const INITIAL_ZERO_ROOT =
  "0x0ce3a78a0131c84050bbe2205642f9e176ffe98488dbddb19336b987420f3bde";
const BLS12_381_SCALAR_FIELD_MODULUS =
  BigInt("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");

async function main() {
  const args = parseArgs(process.argv.slice(2));
  assertNoLegacyBridgeOverrideFlags(args);
  assertNoLegacyWalletFlags(args);
  assertNoLegacyL2IdentityFlags(args);

  if (args.help || !args.command) {
    printHelp();
    return;
  }

  if (args.command === "install-zk-evm") {
    assertInstallZkEvmArgs(args);
    await handleInstallZkEvm({ args });
    return;
  }

  if (args.command === "uninstall-zk-evm") {
    assertUninstallZkEvmArgs(args);
    await handleUninstallZkEvm();
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
    "withdraw-bridge": {
      assert: assertWithdrawBridgeArgs,
      run: ({ provider }) => handleWithdrawBridge({ args, provider }),
    },
    "deposit-channel": {
      assert: (parsedArgs) => assertWalletChannelMoveArgs(parsedArgs, "deposit-channel"),
      run: ({ provider }) => handleGrothVaultMove({ args, provider, direction: "deposit" }),
    },
    "withdraw-channel": {
      assert: (parsedArgs) => assertWalletChannelMoveArgs(parsedArgs, "withdraw-channel"),
      run: ({ provider }) => handleGrothVaultMove({ args, provider, direction: "withdraw" }),
    },
    "is-channel-registered": {
      assert: assertIsChannelRegisteredArgs,
      run: ({ provider }) => handleIsChannelRegistered({ args, provider }),
    },
    "get-wallet-address": {
      assert: assertGetWalletAddressArgs,
      run: ({ provider }) => handleGetWalletAddress({ args, provider }),
    },
    "get-channel-deposit": {
      assert: assertGetChannelDepositArgs,
      run: ({ provider }) => handleGetChannelDeposit({ args, provider }),
    },
  };
  if (walletCommandHandlers[args.command]) {
    walletCommandHandlers[args.command].assert(args);
    const { provider } = loadWalletCommandRuntime(args);
    await walletCommandHandlers[args.command].run({ provider });
    return;
  }

  const env = loadEnv(args.envFile ?? defaultEnvFile);
  const networkName = args.network ?? env.APPS_NETWORK;
  if (!networkName) {
    throw new Error("Missing --network and APPS_NETWORK.");
  }
  const network = resolveCliNetwork(networkName);
  const rpcUrl = deriveRpcUrl({
    networkName,
    alchemyApiKey: args.alchemyApiKey ?? env.APPS_ALCHEMY_API_KEY,
    rpcUrlOverride: args.rpcUrl ?? env.APPS_RPC_URL_OVERRIDE,
  });
  const provider = new JsonRpcProvider(rpcUrl);

  switch (args.command) {
    case "create-channel":
      await handleChannelCreate({ args, env, network, provider });
      return;
    case "recover-workspace":
      await handleWorkspaceInit({ args, network, provider });
      return;
    case "deposit-bridge":
      await handleRegisterAndFund({ args, env, network, provider });
      return;
    case "get-bridge-deposit":
      await handleGetBridgeDeposit({ args, env, network, provider });
      return;
    case "is-channel-registered":
      throw new Error("is-channel-registered must resolve its network from the local wallet.");
    case "get-wallet-address":
      throw new Error("get-wallet-address must resolve its network from the local wallet.");
    case "get-channel-deposit":
      throw new Error("get-channel-deposit must resolve its network from the local wallet.");
    case "mint-notes":
      throw new Error("mint-notes must resolve its network from the local wallet.");
    case "redeem-notes":
      throw new Error("redeem-notes must resolve its network from the local wallet.");
    case "get-my-notes":
      throw new Error("get-my-notes must resolve its network from the local wallet.");
    case "transfer-notes":
      throw new Error("transfer-notes must resolve its network from the local wallet.");
    case "withdraw-bridge":
      throw new Error("withdraw-bridge must resolve its network from the local wallet.");
    case "withdraw-channel":
      throw new Error("withdraw-channel must resolve its network from the local wallet.");
    case "register-channel":
      assertRegisterChannelArgs(args);
      await handleRegisterChannel({ args, env, network, provider });
      return;
    default:
      throw new Error(`Unsupported command: ${args.command}`);
  }
}

function assertNoLegacyBridgeOverrideFlags(args) {
  if (args.bridgeDeployment !== undefined) {
    throw new Error("--bridge-deployment is no longer supported. Select the bridge through --network only.");
  }
  if (args.bridgeAbiManifest !== undefined) {
    throw new Error("--bridge-abi-manifest is no longer supported. Select the bridge through --network only.");
  }
}

function assertNoLegacyWalletFlags(args) {
  if (args.userWorkspace !== undefined) {
    throw new Error("--user-workspace is no longer supported. Use --wallet instead.");
  }
}

function assertNoLegacyL2IdentityFlags(args) {
  if (args.l2KeySignature !== undefined) {
    throw new Error("--l2-key-signature is no longer supported. Use --password instead.");
  }
  if (args.l2Password !== undefined) {
    throw new Error("--l2-password is no longer supported. Use --password instead.");
  }
}

async function handleChannelCreate({ args, env, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const dappLabel = requireArg(args.dappLabel, "--dapp-label");
  const signer = requireL1Signer(args, env, provider);
  const leader = getAddress(args.leader ?? signer.address);
  const createWorkspace = parseBooleanFlag(args.createWorkspace);
  const workspaceName = channelName;

  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    signer,
  );
  const channelId = deriveChannelIdFromName(channelName);
  const dappId = await resolveDAppIdByLabel({
    provider,
    bridgeResources,
    dappLabel,
  });

  const receipt = await waitForReceipt(await bridgeCore.createChannel(channelId, dappId, leader));
  const channelInfo = await bridgeCore.getChannel(channelId);

  let workspaceResult = null;
  if (createWorkspace) {
    workspaceResult = await initializeChannelWorkspace({
      workspaceName,
      channelName,
      network,
      provider,
      bridgeResources,
      blockInfoFile: null,
      importedSnapshotFile: null,
      force: parseBooleanFlag(args.force),
      persist: true,
    });
  }

  printJson({
    action: "create-channel",
    channelName,
    channelId: channelId.toString(),
    dappId,
    leader,
    asset: channelInfo.asset,
    manager: channelInfo.manager,
    bridgeTokenVault: channelInfo.bridgeTokenVault,
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
  const events = await dAppManager.queryFilter(dAppManager.filters.DAppRegistered(), 0, "latest");
  const matchingIds = [];

  for (const event of events) {
    const eventLabelHash = normalizeBytes32Hex(event.args?.labelHash);
    if (eventLabelHash === expectedLabelHash) {
      matchingIds.push(Number(event.args.dappId));
    }
  }

  if (matchingIds.length === 0) {
    throw new Error(`No registered DApp matches --dapp-label ${dappLabel}.`);
  }

  const uniqueIds = [...new Set(matchingIds)];
  if (uniqueIds.length > 1) {
    throw new Error(
      `DApp label ${dappLabel} is ambiguous on-chain; matching dappIds: ${uniqueIds.join(", ")}.`,
    );
  }

  return uniqueIds[0];
}

async function handleWorkspaceInit({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  if (args.workspace !== undefined) {
    throw new Error("--workspace is not supported by recover-workspace. The workspace name is always the channel name.");
  }
  const workspaceName = channelName;
  const blockInfoFile = args.blockInfoFile ? resolveInputPath(args.blockInfoFile) : null;
  const importedSnapshotFile = args.stateSnapshotFile ? resolveInputPath(args.stateSnapshotFile) : null;
  const force = parseBooleanFlag(args.force);
  const bridgeResources = loadBridgeResources({ chainId: network.chainId });

  const { workspaceDir, workspace, currentSnapshot } = await initializeChannelWorkspace({
    workspaceName,
    channelName,
    network,
    provider,
    bridgeResources,
    blockInfoFile,
    importedSnapshotFile,
    force,
    persist: true,
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
  blockInfoFile,
  importedSnapshotFile,
  force,
  persist,
}) {
  const workspaceDir = channelWorkspacePath(workspaceName);
  const channelDir = channelDataPath(workspaceDir);
  const hasPersistedChannelData = fs.existsSync(channelWorkspaceConfigPath(workspaceDir))
    || fs.existsSync(channelWorkspaceCurrentPath(workspaceDir))
    || fs.existsSync(channelWorkspaceOperationsPath(workspaceDir));

  if (persist && hasPersistedChannelData) {
    if (!force) {
      throw new Error(`Workspace already exists: ${workspaceDir}. Use --force to overwrite.`);
    }
    fs.rmSync(channelDir, { recursive: true, force: true });
  }

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
  const deploymentManifestPath = path.resolve(deployRoot, `deployment.${network.chainId}.latest.json`);
  const storageLayoutManifestPath = path.resolve(deployRoot, `storage-layout.${network.chainId}.latest.json`);
  const deploymentManifest = readJson(deploymentManifestPath);
  const storageLayoutManifest = readJson(storageLayoutManifestPath);
  const controllerAddress = getAddress(deploymentManifest.contracts.controller);
  const l2AccountingVaultAddress = getAddress(deploymentManifest.contracts.l2AccountingVault);
  const liquidBalancesSlot = BigInt(findStorageSlot(storageLayoutManifest, "L2AccountingVault", "liquidBalances"));

  expect(
    managedStorageAddresses.includes(controllerAddress),
    `Managed storage vector does not include controller ${controllerAddress}.`,
  );
  expect(
    managedStorageAddresses.includes(l2AccountingVaultAddress),
    `Managed storage vector does not include L2 accounting vault ${l2AccountingVaultAddress}.`,
  );

  const contractCodes = await fetchContractCodes(provider, managedStorageAddresses);
  const blockInfo = await fetchChannelBlockInfo(provider, genesisBlockNumber);
  const derivedAPubBlockHash = normalizeBytes32Hex(hashTokamakPublicInputs(encodeTokamakBlockInfo(blockInfo)));
  expect(
    derivedAPubBlockHash === normalizeBytes32Hex(channelInfo.aPubBlockHash),
    `Derived channel block-info hash ${derivedAPubBlockHash} does not match onchain ${channelInfo.aPubBlockHash}.`,
  );
  if (blockInfoFile) {
    const suppliedBlockInfo = readJson(blockInfoFile);
    const suppliedBlockHash = normalizeBytes32Hex(hashTokamakPublicInputs(encodeTokamakBlockInfo(suppliedBlockInfo)));
    expect(
      suppliedBlockHash === derivedAPubBlockHash,
      [
        `Supplied block_info.json hash ${suppliedBlockHash} does not match the channel block context.`,
        `Expected ${derivedAPubBlockHash} from genesis block ${genesisBlockNumber}.`,
      ].join(" "),
    );
  }

  let currentSnapshot;
  if (importedSnapshotFile) {
    currentSnapshot = normalizeStateSnapshot(readJson(importedSnapshotFile));
    assertSnapshotMatchesChannel(currentSnapshot, currentRootVectorHash, managedStorageAddresses);
  } else {
    currentSnapshot = await reconstructChannelSnapshot({
      provider,
      bridgeAbiManifest,
      channelInfo,
      channelManager,
      currentRootVectorHash,
      managedStorageAddresses,
      contractCodes,
      genesisBlockNumber,
      channelId,
    });
  }

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

    writeJson(channelWorkspaceConfigPath(workspaceDir), workspace);
    writeJson(path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.json"), currentSnapshot);
    writeJson(path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.normalized.json"), normalizeStateSnapshot(currentSnapshot));
    writeJson(path.join(channelWorkspaceCurrentPath(workspaceDir), "block_info.json"), blockInfo);
    writeJson(path.join(channelWorkspaceCurrentPath(workspaceDir), "contract_codes.json"), contractCodes);
  }

  return {
    workspaceDir,
    workspace,
    currentSnapshot,
    blockInfo,
    contractCodes,
  };
}

async function handleRegisterAndFund({ args, env, network, provider }) {
  if (args.wallet !== undefined) {
    throw new Error(
      "--wallet is not supported by deposit-bridge. Channel wallet keys are set up only by register-channel.",
    );
  }
  const signer = requireL1Signer(args, env, provider);
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
    approveReceipt: sanitizeReceipt(approveReceipt),
    fundReceipt: sanitizeReceipt(fundReceipt),
  });
}

async function handleGetBridgeDeposit({ args, env, network, provider }) {
  const wallet = args.wallet ? loadWallet(requireWalletName(args), requireL2Password(args)) : null;
  const signer = resolveWalletBackedSigner({ args, env, provider, walletContext: wallet });
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId: network.chainId });
  const bridgeTokenVault = new Contract(
    bridgeVaultContext.bridgeTokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const availableBalance = await bridgeTokenVault.availableBalanceOf(signer.address);

  printJson({
    action: "get-bridge-deposit",
    wallet: wallet?.walletName ?? null,
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

async function handleInstallZkEvm({ args }) {
  const syncedDevCommit = syncTokamakSubmoduleToLatestDev();
  run(tokamakCliPath, ["--install"], { cwd: tokamakRoot });
  printJson({
    action: "install-zk-evm",
    tokamakCli: tokamakCliPath,
    syncedBranch: "dev",
    syncedCommit: syncedDevCommit,
  });
}

async function handleUninstallZkEvm() {
  expect(fs.existsSync(tokamakRoot), `Tokamak zk-EVM submodule path does not exist: ${tokamakRoot}.`);
  const submoduleGitPath = path.join(tokamakRoot, ".git");
  expect(
    fs.existsSync(submoduleGitPath),
    `Tokamak zk-EVM submodule metadata is missing at ${submoduleGitPath}. Refusing to remove the directory.`,
  );

  const removedEntries = [];
  for (const entry of fs.readdirSync(tokamakRoot, { withFileTypes: true })) {
    if (entry.name === ".git") {
      continue;
    }
    const entryPath = path.join(tokamakRoot, entry.name);
    fs.rmSync(entryPath, { recursive: true, force: true });
    removedEntries.push(entry.name);
  }

  printJson({
    action: "uninstall-zk-evm",
    tokamakRoot,
    preservedEntries: [".git"],
    removedEntriesCount: removedEntries.length,
    removedEntries,
  });
}

function syncTokamakSubmoduleToLatestDev() {
  expect(fs.existsSync(tokamakRoot), `Tokamak zk-EVM submodule path does not exist: ${tokamakRoot}.`);
  expect(
    fs.existsSync(path.join(tokamakRoot, ".git")),
    `Tokamak zk-EVM submodule metadata is missing at ${path.join(tokamakRoot, ".git")}.`,
  );

  const porcelainStatus = runGitInTokamak(["status", "--porcelain"]).trim();
  const canRestoreClearedWorktree = porcelainStatus.length > 0 && isTokamakWorktreeDeletionOnly(porcelainStatus);
  expect(
    porcelainStatus.length === 0 || canRestoreClearedWorktree,
    [
      "Tokamak zk-EVM submodule has uncommitted changes.",
      "Clean submodules/Tokamak-zk-EVM before install-zk-evm so the CLI can fast-forward dev safely.",
    ].join(" "),
  );

  runGitInTokamak(["fetch", "origin", "dev"]);

  try {
    runGitInTokamak(["switch", "dev"]);
  } catch {
    runGitInTokamak(["switch", "--track", "origin/dev"]);
  }

  if (canRestoreClearedWorktree) {
    runGitInTokamak(["restore", "--source", "origin/dev", "--staged", "--worktree", "."]);
  }

  runGitInTokamak(["pull", "--ff-only", "origin", "dev"]);
  return runGitInTokamak(["rev-parse", "HEAD"]).trim();
}

function isTokamakWorktreeDeletionOnly(porcelainStatus) {
  return porcelainStatus
    .split("\n")
    .filter((line) => line.length > 0)
    .every((line) => {
      const x = line[0];
      const y = line[1];
      return (x === " " || x === "D") && (y === " " || y === "D") && (x === "D" || y === "D");
    });
}

async function handleIsChannelRegistered({ args, provider }) {
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
    && getAddress(registration.l2Address) === getAddress(l2Identity.l2Address)
    && normalizeBytes32Hex(registration.channelTokenVaultKey) === normalizeBytes32Hex(expectedStorageKey);

  printJson({
    action: "is-channel-registered",
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

async function handleGetWalletAddress({ args, provider }) {
  const { wallet, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  const signer = restoreWalletSigner(wallet, provider);
  const context = await loadChannelContext({
    args,
    networkName: walletMetadata.network,
    provider,
    walletContext: wallet,
  });

  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  expect(
    registration.exists,
    `No channelTokenVault registration exists for ${signer.address}. Run register-channel first.`,
  );

  printJson({
    action: "get-wallet-address",
    wallet: wallet.walletName,
    network: walletMetadata.network,
    channelName: walletMetadata.channelName,
    l1Address: signer.address,
    l2Address: getAddress(registration.l2Address),
    registeredLeafIndex: registration.leafIndex.toString(),
  });
}

async function handleGetChannelDeposit({ args, provider }) {
  const { wallet, walletMetadata } = loadUnlockedWalletWithMetadata(args);
  const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);
  const contextResult = await loadPreferredWalletChannelContext({ walletContext: wallet, provider });
  const context = contextResult.context;

  const registration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  expect(
    registration.exists,
    `No channelTokenVault registration exists for ${signer.address}. Run register-channel first.`,
  );
  const expectedStorageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  expect(
    getAddress(registration.l2Address) === getAddress(l2Identity.l2Address),
    "The local wallet L2 address does not match the registered channel L2 address.",
  );
  expect(
    normalizeBytes32Hex(registration.channelTokenVaultKey) === normalizeBytes32Hex(expectedStorageKey),
    "The local wallet L2 storage key does not match the registered channelTokenVault key.",
  );

  const stateManager = await buildStateManager(context.currentSnapshot, context.contractCodes);
  const channelDeposit = await currentStorageBigInt(
    stateManager,
    context.workspace.l2AccountingVault,
    normalizeBytes32Hex(registration.channelTokenVaultKey),
  );

  printJson({
    action: "get-channel-deposit",
    wallet: wallet.walletName,
    network: walletMetadata.network,
    channelName: walletMetadata.channelName,
    l1Address: signer.address,
    walletL2Address: l2Identity.l2Address,
    walletL2StorageKey: expectedStorageKey,
    registeredLeafIndex: registration.leafIndex.toString(),
    channelDepositBaseUnits: channelDeposit.toString(),
    channelDepositTokens: ethers.formatUnits(
      channelDeposit,
      Number(context.workspace.canonicalAssetDecimals),
    ),
    canonicalAsset: context.workspace.canonicalAsset,
    canonicalAssetDecimals: Number(context.workspace.canonicalAssetDecimals),
    l2AccountingVault: context.workspace.l2AccountingVault,
  });
}

async function handleRegisterChannel({ args, env, network, provider }) {
  const password = requireL2Password(args);
  const context = await loadChannelContext({
    args,
    networkName: network.name,
    provider,
  });
  const signer = resolveWalletBackedSigner({ args, env, provider });
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
  const bridgeTokenVault = new Contract(
    context.workspace.bridgeTokenVault,
    context.bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    signer,
  );
  const availableBalance = await bridgeTokenVault.availableBalanceOf(signer.address);
  expect(availableBalance > 0n, `No shared bridge-vault balance exists for ${signer.address}. Run deposit-bridge first.`);

  const existingRegistration = await context.channelManager.getChannelTokenVaultRegistration(signer.address);
  if (!existingRegistration.exists) {
    const receipt = await waitForReceipt(
      await context.channelManager.connect(signer).registerChannelTokenVaultIdentity(
        l2Identity.l2Address,
        storageKey,
        leafIndex,
        noteReceiveKeyMaterial.noteReceivePubKey,
      ),
    );

    const walletContext = ensureWallet({
      channelContext: context,
      signerAddress: signer.address,
      signerPrivateKey: signer.privateKey,
      l2Identity,
      walletPassword: password,
      storageKey,
      leafIndex,
      noteReceiveKeyMaterial,
    });

    printJson({
      action: "register-channel",
      workspace: context.workspaceName,
      wallet: walletContext.walletName,
      channelName: context.workspace.channelName,
      channelId: context.workspace.channelId,
      l1Address: signer.address,
      l2Address: l2Identity.l2Address,
      l2StorageKey: storageKey,
      leafIndex: leafIndex.toString(),
      noteReceivePubKey: noteReceiveKeyMaterial.noteReceivePubKey,
      receipt: sanitizeReceipt(receipt),
    });
    return;
  }

  expect(
    normalizeBytes32Hex(existingRegistration.channelTokenVaultKey) === normalizeBytes32Hex(storageKey),
    "The existing channel registration key does not match the derived channelTokenVault key.",
  );
  expect(
    getAddress(existingRegistration.l2Address) === getAddress(l2Identity.l2Address),
    "The existing channel registration L2 address does not match the derived L2 address.",
  );
  expect(
    normalizeBytes32Hex(existingRegistration.noteReceivePubKey.x) === normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x),
    "The existing note-receive public key X does not match the derived note-receive public key.",
  );
  expect(
    Number(existingRegistration.noteReceivePubKey.yParity) === Number(noteReceiveKeyMaterial.noteReceivePubKey.yParity),
    "The existing note-receive public key parity does not match the derived note-receive public key.",
  );

  const walletContext = ensureWallet({
    channelContext: context,
    signerAddress: signer.address,
    signerPrivateKey: signer.privateKey,
    l2Identity,
    walletPassword: password,
    storageKey,
    leafIndex: existingRegistration.leafIndex,
    noteReceiveKeyMaterial,
  });

  printJson({
    action: "register-channel",
    workspace: context.workspaceName,
    wallet: walletContext.walletName,
    channelName: context.workspace.channelName,
    channelId: context.workspace.channelId,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    leafIndex: existingRegistration.leafIndex.toString(),
    noteReceivePubKey: noteReceiveKeyMaterial.noteReceivePubKey,
    status: "already-registered",
  });
}

async function handleGrothVaultMove({ args, provider, direction }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  const contextResult = await loadPreferredWalletChannelContext({ walletContext: wallet, provider });
  const context = contextResult.context;
  expect(
    BigInt(wallet.wallet.channelId) === BigInt(context.workspace.channelId),
    "The provided wallet does not belong to the selected channel.",
  );

  const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);
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
    `No channelTokenVault registration exists for ${signer.address}. Run register-channel first.`,
  );
  expect(
    normalizeBytes32Hex(registration.channelTokenVaultKey) === normalizeBytes32Hex(storageKey),
    "The derived L2 storage key does not match the registered channelTokenVault key.",
  );
  expect(
    getAddress(registration.l2Address) === getAddress(l2Identity.l2Address),
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

  const operationName = args.command === "withdraw-channel"
    ? "withdraw-channel"
    : direction === "deposit"
      ? "deposit-channel"
      : "withdraw";
  const operationDir = createWalletOperationDir(wallet.walletName, `${operationName}-${shortAddress(signer.address)}`);

  const transition = await buildGrothTransition({
    operationDir,
    workspace: context.workspace,
    stateManager,
    vaultAddress: context.workspace.l2AccountingVault,
    keyHex,
    nextValue,
  });

  const receipt = await waitForReceipt(
    await bridgeTokenVault[direction](BigInt(context.workspace.channelId), transition.proof, transition.update),
  );
  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  expect(
    onchainRootVectorHash === normalizeBytes32Hex(hashRootVector(transition.nextSnapshot.stateRoots)),
    `On-chain roots do not match the ${direction} post-state roots.`,
  );

  writeJson(path.join(operationDir, `${operationName}-receipt.json`), sanitizeReceipt(receipt));
  writeJson(path.join(operationDir, "state_snapshot.json"), transition.nextSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), normalizeStateSnapshot(transition.nextSnapshot));
  sealWalletOperationDir(operationDir, wallet.walletPassword);

  context.currentSnapshot = normalizeStateSnapshot(transition.nextSnapshot);
  persistCurrentState(context);

  printJson({
    action: operationName,
    workspace: context.workspaceName,
    wallet: wallet.walletName,
    operationDir,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    amountInput,
    amountBaseUnits: amount.toString(),
    currentRootVector: transition.update.currentRootVector,
    updatedRoot: transition.update.updatedRoot,
  });
}

async function handleWithdrawBridge({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  const signer = restoreWalletSigner(wallet, provider);
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
    wallet: wallet.walletName,
    l1Address: signer.address,
    amountInput,
    amountBaseUnits: amount.toString(),
    bridgeTokenVault: bridgeVaultContext.bridgeTokenVaultAddress,
    canonicalAsset: bridgeVaultContext.canonicalAsset,
    canonicalAssetDecimals: Number(bridgeVaultContext.canonicalAssetDecimals),
    receipt: sanitizeReceipt(receipt),
  });
}

async function handleMintNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  const canonicalAssetDecimals = Number(wallet.wallet.canonicalAssetDecimals);
  const amountInputs = parseTokenAmountVector(requireArg(args.amounts, "--amounts"));
  const baseUnitAmounts = amountInputs.map((value) => parseTokenAmount(value, canonicalAssetDecimals));
  for (const [index, amount] of baseUnitAmounts.entries()) {
    expect(amount > 0n, `Invalid --amounts[${index}]. Each amount must be greater than zero.`);
  }
  const templatePayload = buildMintNotesTemplatePayload({
    wallet,
    baseUnitAmounts,
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
    amountInputs,
    amountBaseUnits: baseUnitAmounts.map((value) => value.toString()),
    outputNotes: templatePayload.args[0].map((note) => buildTrackedNote(note, templatePayload.method, execution.receipt.hash)),
    usedWorkspaceCache: contextResult.usingWorkspaceCache,
    recoveredWorkspace,
    updatedRoots: execution.context.currentSnapshot.stateRoots,
  });
}

async function handleRedeemNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  const noteId = parseNoteId(requireArg(args.noteId, "--note-id"));
  const inputNote = loadRedeemInputNote(wallet, noteId);
  const templatePayload = buildRedeemNotesTemplatePayload({
    wallet,
    inputNote,
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
    noteId,
    redeemedNote: buildTrackedNote(inputNote, templatePayload.method, execution.receipt.hash),
    redeemedAmountBaseUnits: inputNote.value,
    redeemedAmountTokens: ethers.formatUnits(
      BigInt(inputNote.value),
      Number(wallet.wallet.canonicalAssetDecimals),
    ),
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

  const unusedNotes = unusedTrackedNotes.map((note) => buildWalletNoteBridgeStatus({
    note,
    currentSnapshot: context.currentSnapshot,
    controllerAddress: wallet.wallet.controller,
    canonicalAssetDecimals,
  }));
  const spentNotes = spentTrackedNotes.map((note) => buildWalletNoteBridgeStatus({
    note,
    currentSnapshot: context.currentSnapshot,
    controllerAddress: wallet.wallet.controller,
    canonicalAssetDecimals,
  }));

  const unusedTotal = unusedTrackedNotes.reduce((sum, note) => sum + BigInt(note.value), 0n);
  const spentTotal = spentTrackedNotes.reduce((sum, note) => sum + BigInt(note.value), 0n);

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
  const amountInputs = parseTokenAmountVector(requireArg(args.amounts, "--amounts"));
  expect(
    recipients.length === amountInputs.length,
    "--amounts length must match --recipients length.",
  );

  const inputNotes = loadTransferInputNotes(wallet, noteIds);
  const outputAmounts = amountInputs.map((value, index) => {
    const parsed = parseTokenAmount(value, canonicalAssetDecimals);
    expect(parsed > 0n, `Invalid --amounts[${index}]. Each amount must be greater than zero.`);
    return parsed;
  });
  const totalInput = inputNotes.reduce((sum, note) => sum + BigInt(note.value), 0n);
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

function ensureWallet({
  channelContext,
  signerAddress,
  signerPrivateKey,
  l2Identity,
  walletPassword,
  storageKey,
  leafIndex,
  noteReceiveKeyMaterial,
}) {
  const walletName = walletNameForChannelAndAddress(channelContext.workspace.channelName, l2Identity.l2Address);
  const walletDir = walletPath(walletName);
  let wallet;
  if (walletConfigExists(walletDir)) {
    wallet = normalizeWallet(readEncryptedWalletJson(walletConfigPath(walletDir), walletPassword));
    expect(
      BigInt(wallet.channelId) === BigInt(channelContext.workspace.channelId),
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
      unusedBalance: unusedNotes.reduce((sum, note) => sum + BigInt(note.value), 0n).toString(),
    },
  };
}

function normalizeTrackedNote(note) {
  return {
    owner: getAddress(note.owner),
    value: BigInt(note.value).toString(),
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

function buildWalletNoteBridgeStatus({
  note,
  currentSnapshot,
  controllerAddress,
  canonicalAssetDecimals,
}) {
  const commitmentExists = readBooleanStorageValueFromSnapshot({
    snapshot: currentSnapshot,
    storageAddress: controllerAddress,
    storageKey: note.bridgeCommitmentKey,
  });
  const nullifierUsed = readBooleanStorageValueFromSnapshot({
    snapshot: currentSnapshot,
    storageAddress: controllerAddress,
    storageKey: note.bridgeNullifierKey,
  });
  const expectedNullifierUsed = note.status === "spent";
  return {
    owner: note.owner,
    valueBaseUnits: note.value,
    valueTokens: ethers.formatUnits(BigInt(note.value), canonicalAssetDecimals),
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

function readBooleanStorageValueFromSnapshot({ snapshot, storageAddress, storageKey }) {
  if (!storageKey) {
    return false;
  }
  const normalizedAddress = getAddress(storageAddress);
  const addressIndex = snapshot.storageAddresses.findIndex(
    (entry) => getAddress(entry) === normalizedAddress,
  );
  expect(addressIndex >= 0, `Storage snapshot does not include ${normalizedAddress}.`);

  const entry = snapshot.storageEntries[addressIndex]?.find(
    (item) => normalizeBytes32Hex(item.key) === normalizeBytes32Hex(storageKey),
  );
  if (!entry) {
    return false;
  }
  return BigInt(entry.value) !== 0n;
}

function compareNotesByValueDesc(left, right) {
  const leftValue = BigInt(left.value);
  const rightValue = BigInt(right.value);
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
  const commitmentExistsSlot = BigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "commitmentExists"));
  const nullifierUsedSlot = BigInt(findStorageSlot(storageLayoutManifest, "PrivateStateController", "nullifierUsed"));
  const observedLogs = await provider.getLogs({
    address: context.workspace.channelManager,
    fromBlock: scanStartBlock,
    toBlock: latestBlock,
    topics: [NOTE_VALUE_ENCRYPTED_TOPIC],
  });

  const importedCandidates = [];
  for (const log of observedLogs) {
    let parsedLog;
    try {
      parsedLog = noteValueEncryptedEventInterface.parseLog(log);
    } catch {
      continue;
    }

    const encryptedNoteValue = normalizeEncryptedNoteValueWords(parsedLog.args.encryptedNoteValue);
    let recoveredValue;
    try {
      recoveredValue = decryptEncryptedNoteValue({
        encryptedValue: encryptedNoteValue,
        noteReceivePrivateKey,
        chainId: context.workspace.chainId,
        channelId: context.workspace.channelId,
        owner: walletContext.wallet.l2Address,
      });
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
    const trackedNote = buildTrackedNote(plaintextNote, "transferNotes", log.transactionHash, {
      bridgeCommitmentKey: derivePrivateStateControllerMappingStorageKey(commitment, commitmentExistsSlot),
      bridgeNullifierKey: derivePrivateStateControllerMappingStorageKey(nullifier, nullifierUsedSlot),
    });
    const commitmentExists = readBooleanStorageValueFromSnapshot({
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
  walletContext.wallet.noteReceiveLastScannedBlock = latestBlock + 1;
  persistWallet(walletContext);
  return {
    importedNotes,
    scannedLogs: observedLogs.length,
    scanRange,
  };
}

function buildImportedTrackedNote(note) {
  const trackedNote = buildTrackedNote(note, note.sourceFunction ?? null, note.sourceTxHash ?? null, {
    bridgeCommitmentKey: note.bridgeCommitmentKey ?? null,
    bridgeNullifierKey: note.bridgeNullifierKey ?? null,
  });
  if (note.commitment !== undefined) {
    expect(
      normalizeBytes32Hex(note.commitment) === trackedNote.commitment,
      `Imported note commitment mismatch for ${trackedNote.commitment}.`,
    );
  }
  if (note.nullifier !== undefined) {
    expect(
      normalizeBytes32Hex(note.nullifier) === trackedNote.nullifier,
      `Imported note nullifier mismatch for ${trackedNote.commitment}.`,
    );
  }
  return trackedNote;
}

function normalizePlaintextNote(note) {
  return {
    owner: getAddress(note.owner),
    value: BigInt(note.value).toString(),
    salt: normalizeBytes32Hex(note.salt),
  };
}

function computeNoteCommitment(note) {
  return keccak256(
    abiCoder.encode(
      ["bytes32", "address", "uint256", "bytes32"],
      [ethers.id("PRIVATE_STATE_NOTE_COMMITMENT"), note.owner, BigInt(note.value), note.salt],
    ),
  );
}

function computeNullifier(note) {
  return keccak256(
    abiCoder.encode(
      ["bytes32", "address", "uint256", "bytes32"],
      [ethers.id("PRIVATE_STATE_NULLIFIER"), note.owner, BigInt(note.value), note.salt],
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
      channelId: BigInt(channelId).toString(),
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
}) {
  const parity = Number(ephemeralPubKeyYParity);
  expect(parity === 0 || parity === 1, "Encrypted note value y parity must be 0 or 1.");
  return normalizeEncryptedNoteValueWords([
    normalizeBytes32Hex(ephemeralPubKeyX),
    ethers.hexlify(ethers.concat([
      Uint8Array.from([parity]),
      ethers.getBytes(ethers.zeroPadValue(nonce, 12)),
      ethers.getBytes(ethers.zeroPadValue(tag, 16)),
      new Uint8Array(3),
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
  };
}

function derivePrivateStateControllerMappingStorageKey(keyHex, slot) {
  const encoded = abiCoder.encode(["bytes32", "uint256"], [normalizeBytes32Hex(keyHex), BigInt(slot)]);
  return normalizeBytes32Hex(bytesToHex(poseidon(hexToBytes(encoded))));
}

function computeEncryptedNoteSalt(encryptedValue) {
  const normalized = normalizeEncryptedNoteValueWords(encryptedValue);
  return normalizeBytes32Hex(
    ethers.hexlify(poseidon(ethers.getBytes(abiCoder.encode(["bytes32[3]"], [normalized])))),
  );
}

function encodeNoteValuePlaintext(value) {
  const scalar = BigInt(value);
  expect(
    scalar >= 0n && scalar < BLS12_381_SCALAR_FIELD_MODULUS,
    "Encrypted note plaintext value must fit within the BLS12-381 scalar field.",
  );
  return scalar;
}

function decodeNoteValuePlaintext(valueBytes) {
  return BigInt(valueBytes).toString();
}

function fieldElementHex(value) {
  return normalizeBytes32Hex(ethers.toBeHex(value));
}

function normalizeTagHex(value) {
  return ethers.hexlify(ethers.zeroPadValue(value, 16)).toLowerCase();
}

function deriveFieldMask({ sharedSecretPoint, chainId, channelId, owner, nonce }) {
  const affine = sharedSecretPoint.toAffine();
  return BigInt(
    bytesToHex(
      poseidon(
        ethers.getBytes(
          abiCoder.encode(
            ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12"],
            [
              NOTE_RECEIVE_FIELD_ENCRYPTION_INFO,
              BigInt(chainId),
              BigInt(channelId),
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

function deriveCipherTag({ sharedSecretPoint, chainId, channelId, owner, nonce, ciphertextValue }) {
  const affine = sharedSecretPoint.toAffine();
  return ethers.dataSlice(
    bytesToHex(
      poseidon(
        ethers.getBytes(
          abiCoder.encode(
            ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12", "bytes32"],
            [
              `${NOTE_RECEIVE_FIELD_ENCRYPTION_INFO}:tag`,
              BigInt(chainId),
              BigInt(channelId),
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

function encryptNoteValueForRecipient({ value, recipientNoteReceivePubKey, chainId, channelId, owner }) {
  const recipientPoint = pointFromNoteReceivePubKey(recipientNoteReceivePubKey);
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
  });
  const ciphertextValue = (plaintextValue + fieldMask) % BLS12_381_SCALAR_FIELD_MODULUS;
  const tag = deriveCipherTag({
    sharedSecretPoint,
    chainId,
    channelId,
    owner,
    nonce,
    ciphertextValue,
  });
  const parsedEphemeralPubKey = noteReceivePubKeyFromPoint(ephemeralPoint);

  return packEncryptedNoteValue({
    ephemeralPubKeyX: parsedEphemeralPubKey.x,
    ephemeralPubKeyYParity: parsedEphemeralPubKey.yParity,
    nonce,
    ciphertextValue: fieldElementHex(ciphertextValue),
    tag,
  });
}

function decryptEncryptedNoteValue({ encryptedValue, noteReceivePrivateKey, chainId, channelId, owner }) {
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
  expect(normalizeTagHex(expectedTag) === normalizeTagHex(normalized.tag), "Encrypted note value integrity tag mismatch.");
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

function extractNoteLifecycle(functionName, templatePayload) {
  if (functionName.startsWith("mintNotes")) {
    return {
      inputs: [],
      outputs: templatePayload.args[0] ?? [],
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
  const previousEntries = snapshotStorageEntriesForAddress(previousSnapshot, controllerAddress);
  const previousKeys = new Set(previousEntries.map((entry) => normalizeBytes32Hex(entry.key)));
  const newKeys = snapshotStorageEntriesForAddress(nextSnapshot, controllerAddress)
    .map((entry) => normalizeBytes32Hex(entry.key))
    .filter((key) => !previousKeys.has(key));
  const inputCount = lifecycle.inputs.length;
  const outputCount = lifecycle.outputs.length;
  const expectedNewKeyCount = inputCount + outputCount;
  expect(
    newKeys.length >= expectedNewKeyCount,
    [
      "The controller snapshot delta did not expose enough new storage keys",
      `for ${inputCount} input note(s) and ${outputCount} output note(s).`,
    ].join(" "),
  );
  return {
    ...lifecycle,
    inputNullifierKeys: newKeys.slice(0, inputCount),
    outputCommitmentKeys: newKeys.slice(inputCount, inputCount + outputCount),
  };
}

function snapshotStorageEntriesForAddress(snapshot, storageAddress) {
  const normalizedAddress = getAddress(storageAddress);
  const addressIndex = snapshot.storageAddresses.findIndex(
    (entry) => getAddress(entry) === normalizedAddress,
  );
  expect(addressIndex >= 0, `Storage snapshot does not include ${normalizedAddress}.`);
  return snapshot.storageEntries[addressIndex] ?? [];
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
  const outputs = buildMintOutputNotes({
    owner: wallet.wallet.l2Address,
    values: baseUnitAmounts,
  });
  return {
    abiFile: "../deploy/PrivateStateController.callable-abi.json",
    method,
    args: [outputs],
  };
}

function buildRedeemNotesTemplatePayload({ wallet, inputNote }) {
  return {
    abiFile: "../deploy/PrivateStateController.callable-abi.json",
    method: "redeemNotes1",
    args: [[inputNote], wallet.wallet.l2Address],
  };
}

function selectMintNotesMethod(noteCount) {
  expect(noteCount >= 1, "mint-notes requires at least one output amount.");
  expect(noteCount <= 6, "mint-notes supports at most six output amounts.");
  return `mintNotes${noteCount}`;
}

function buildMintOutputNotes({ owner, values }) {
  return values.map((value) => ({
    owner: getAddress(owner),
    value: BigInt(value).toString(),
    salt: generateNoteSalt(),
  }));
}

function assertRegisteredNoteReceivePubKey(noteReceivePubKey, recipient) {
  expect(noteReceivePubKey, `Missing note-receive public key for ${recipient}.`);
  expect(
    noteReceivePubKey.x && normalizeBytes32Hex(noteReceivePubKey.x) !== normalizeBytes32Hex("0x0"),
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
  for (let index = 0; index < recipients.length; index += 1) {
    const recipient = getAddress(recipients[index]);
    const noteReceivePubKey = await context.channelManager.getNoteReceivePubKeyByL2Address(recipient);
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
      value: BigInt(outputAmounts[index]).toString(),
      encryptedNoteValue,
    });
    lifecycleOutputs.push({
      owner: recipient,
      value: BigInt(outputAmounts[index]).toString(),
      salt,
    });
  }
  return {
    abiFile: "../deploy/PrivateStateController.callable-abi.json",
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

function generateNoteSalt() {
  const raw = BigInt(ethers.hexlify(randomBytes(32)));
  const normalized = (raw % (BLS12_381_SCALAR_FIELD_MODULUS - 1n)) + 1n;
  return bytes32FromHex(ethers.toBeHex(normalized));
}

function loadTransferInputNotes(walletContext, noteIds) {
  return noteIds.map((noteId) => {
    const trackedNote = walletContext.wallet.notes.unused[noteId];
    expect(trackedNote, `Unknown unused note commitment: ${noteId}.`);
    return normalizePlaintextNote(trackedNote);
  });
}

function loadRedeemInputNote(walletContext, noteId) {
  const trackedNote = walletContext.wallet.notes.unused[noteId];
  expect(trackedNote, `Unknown unused note commitment: ${noteId}.`);
  return normalizePlaintextNote(trackedNote);
}

function parseTokenAmountVector(value) {
  let parsed;
  try {
    parsed = JSON.parse(String(value));
  } catch {
    throw new Error("Invalid --amounts. Expected a JSON array such as [1,2,3].");
  }
  expect(Array.isArray(parsed), "Invalid --amounts. Expected a JSON array.");
  expect(parsed.length > 0, "Invalid --amounts. The array must not be empty.");
  return parsed.map((entry, index) => {
    const normalized = typeof entry === "string" || typeof entry === "number" ? String(entry) : null;
    expect(
      normalized !== null && normalized.length > 0,
      `Invalid --amounts[${index}]. Each amount must be a string or number.`,
    );
    expect(
      !normalized.startsWith("-") && normalized !== "0" && normalized !== "0.0",
      `Invalid --amounts[${index}]. Each amount must be greater than zero.`,
    );
    return normalized;
  });
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

function parseNoteId(value) {
  expect(
    typeof value === "string" && value.length > 0,
    "Invalid --note-id. Expected a note commitment string.",
  );
  return normalizeBytes32Hex(value);
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
  const workspaceDir = channelWorkspacePath(walletContext.wallet.channelName);
  return fs.existsSync(channelWorkspaceConfigPath(workspaceDir))
    && fs.existsSync(path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.json"))
    && fs.existsSync(path.join(channelWorkspaceCurrentPath(workspaceDir), "block_info.json"))
    && fs.existsSync(path.join(channelWorkspaceCurrentPath(workspaceDir), "contract_codes.json"));
}

async function loadPreferredWalletChannelContext({ walletContext, provider }) {
  let recoveredWorkspace = false;
  if (!walletChannelWorkspaceIsReady(walletContext)) {
    await recoverWalletChannelWorkspace({ walletContext, provider });
    recoveredWorkspace = true;
  }
  let context = await loadWorkspaceContext(walletContext.wallet.channelName, provider);
  try {
    await assertWorkspaceAlignedWithChain(context);
  } catch (error) {
    if (!isRecoverableWalletWorkspaceFailure(error)) {
      throw error;
    }
    await recoverWalletChannelWorkspace({ walletContext, provider });
    recoveredWorkspace = true;
    context = await loadWorkspaceContext(walletContext.wallet.channelName, provider);
    await assertWorkspaceAlignedWithChain(context);
  }
  return {
    context,
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
    blockInfoFile: null,
    importedSnapshotFile: null,
    force: true,
    persist: true,
  });
}

function isRecoverableWalletWorkspaceFailure(error) {
  const message = String(error?.message ?? error);
  return (message.includes("--verify") && message.includes("failed with exit code"))
    || message.includes("The workspace snapshot is stale relative to the bridge channel state.");
}

function assertWalletMatchesChannelContext(walletContext, l2Identity, context) {
  expect(
    BigInt(walletContext.wallet.channelId) === BigInt(context.workspace.channelId),
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

  await recoverWalletChannelWorkspace({ walletContext: wallet, provider });
  contextResult = await loadPreferredWalletChannelContext({ walletContext: wallet, provider });
  recoveredWorkspace = true;
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

  const controllerAbi = readJson(path.resolve(deployRoot, templatePayload.abiFile.replace("../deploy/", "")));
  const calldata = new Interface(controllerAbi).encodeFunctionData(
    templatePayload.method,
    templatePayload.args ?? [],
  );
  const nonce = Number(wallet.wallet.l2Nonce ?? 0);
  const operationDir = createWalletOperationDir(wallet.walletName, `${operationName}-${shortAddress(l2Identity.l2Address)}`);
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
  runTokamakProofPipeline({ operationDir, bundlePath });

  const rawNextSnapshot = readJson(path.join(operationDir, "resource", "synthesizer", "output", "state_snapshot.json"));
  const nextSnapshot = normalizeStateSnapshot(rawNextSnapshot);
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
    normalizeBytes32Hex(aPubBlockHash) === normalizeBytes32Hex(context.workspace.aPubBlockHash),
    "Generated Tokamak proof does not match the channel aPubBlockHash. Check the workspace block_info.json context.",
  );

  const receipt =
    await waitForReceipt(await context.channelManager.connect(signer).executeChannelTransaction(payload));

  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  expect(
    onchainRootVectorHash === normalizeBytes32Hex(hashRootVector(nextSnapshot.stateRoots)),
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

async function loadWorkspaceContext(workspaceName, provider) {
  const normalizedWorkspaceName = requireWorkspaceName({ workspace: workspaceName });
  const workspaceDir = channelWorkspacePath(normalizedWorkspaceName);
  const workspace = readJson(channelWorkspaceConfigPath(workspaceDir));
  const bridgeDeploymentPath = defaultBridgeDeploymentPath(workspace.chainId);
  const bridgeAbiManifestPath = defaultBridgeAbiManifestPath(workspace.chainId);
  const bridgeDeployment = readJson(bridgeDeploymentPath);
  const bridgeAbiManifest = loadBridgeAbiManifest(bridgeAbiManifestPath);
  const currentSnapshot = normalizeStateSnapshot(readJson(path.join(channelWorkspaceCurrentPath(workspaceDir), "state_snapshot.json")));
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
  const explicitWorkspaceName = args.workspace ? requireWorkspaceName(args) : null;
  if (explicitWorkspaceName) {
    const explicitWorkspaceDir = channelWorkspacePath(explicitWorkspaceName);
    if (fs.existsSync(channelWorkspaceConfigPath(explicitWorkspaceDir))) {
      return loadWorkspaceContext(explicitWorkspaceName, provider);
    }
  }

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
      "Missing channel selector. Provide either --workspace, --channel-name, or --wallet bound to a channel.",
    );
  }

  const bridgeResources = loadBridgeResources({ chainId });
  const blockInfoFile = args.blockInfoFile ? resolveInputPath(args.blockInfoFile) : null;
  const importedSnapshotFile = args.stateSnapshotFile ? resolveInputPath(args.stateSnapshotFile) : null;
  const initialized = await initializeChannelWorkspace({
    workspaceName: explicitWorkspaceName ?? channelName,
    channelName,
    network: { chainId, name: resolvedNetworkName },
    provider,
    bridgeResources,
    blockInfoFile,
    importedSnapshotFile,
    force: false,
    persist: false,
  });

  return {
    workspaceName: explicitWorkspaceName ?? channelName,
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

function loadWallet(walletName, walletPassword) {
  const normalizedWalletName = requireWalletName({ wallet: walletName });
  const walletDir = walletPath(normalizedWalletName);
  if (!walletConfigExists(walletDir)) {
    throw new Error(`Unknown wallet: ${normalizedWalletName}.`);
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
  const wallet = loadWallet(requireWalletName(args), requireL2Password(args));
  const walletMetadata = loadWalletMetadata(wallet.walletName);
  assertWalletMatchesMetadata(wallet, walletMetadata);
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
      "Create a fresh wallet with register-channel.",
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

function resolveWalletBackedSigner({ args, env, provider, walletContext }) {
  if (args.privateKey !== undefined) {
    const signer = requireL1Signer(args, env, provider);
    if (walletContext?.wallet?.l1Address) {
      expect(
        getAddress(walletContext.wallet.l1Address) === getAddress(signer.address),
        "The provided --private-key does not match the encrypted wallet's stored L1 address.",
      );
    }
    return signer;
  }
  if (walletContext?.wallet?.l1PrivateKey) {
    return restoreWalletSigner(walletContext, provider);
  }
  if (env.APPS_DEPLOYER_PRIVATE_KEY) {
    return requireL1Signer(args, env, provider);
  }
  throw new Error("Missing --private-key and no encrypted L1 private key is available in the selected wallet.");
}

function loadBridgeResources({ chainId }) {
  const bridgeDeploymentPath = defaultBridgeDeploymentPath(chainId);
  const bridgeDeployment = readJson(bridgeDeploymentPath);
  const bridgeAbiManifestPath = defaultBridgeAbiManifestPath(chainId);
  const bridgeAbiManifest = loadBridgeAbiManifest(bridgeAbiManifestPath);
  return {
    bridgeDeploymentPath,
    bridgeDeployment,
    bridgeAbiManifestPath,
    bridgeAbiManifest,
  };
}

function loadWalletMetadata(walletName) {
  const normalizedWalletName = requireWalletName({ wallet: walletName });
  const walletDir = walletPath(normalizedWalletName);
  if (!walletConfigExists(walletDir)) {
    throw new Error(`Unknown wallet: ${normalizedWalletName}.`);
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
    typeof metadata.channelName === "string" && metadata.channelName.length > 0,
    `Wallet ${normalizedWalletName} metadata is missing channelName.`,
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
  const storageLayoutManifestPath = path.resolve(deployRoot, `storage-layout.${chainId}.latest.json`);
  const storageLayoutManifest = readJson(storageLayoutManifestPath);
  const liquidBalancesSlot = BigInt(findStorageSlot(storageLayoutManifest, "L2AccountingVault", "liquidBalances"));

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

async function buildGrothTransition({ operationDir, workspace, stateManager, vaultAddress, keyHex, nextValue }) {
  const vaultAddressObj = createAddressFromString(vaultAddress);
  const keyBigInt = BigInt(keyHex);
  const proof = stateManager.merkleTrees.getProof(vaultAddressObj, keyBigInt);
  const currentRoot = stateManager.merkleTrees.getRoot(vaultAddressObj);
  const currentValue = await currentStorageBigInt(stateManager, vaultAddress, keyHex);
  const currentSnapshot = normalizeStateSnapshot(await stateManager.captureStateSnapshot());

  await stateManager.putStorage(vaultAddressObj, hexToBytes(keyHex), hexToBytes(bigintToHex32(nextValue)));
  const updatedRoot = stateManager.merkleTrees.getRoot(vaultAddressObj);
  const nextSnapshot = normalizeStateSnapshot(await stateManager.captureStateSnapshot());

  const input = {
    root_before: currentRoot.toString(),
    root_after: updatedRoot.toString(),
    leaf_index: BigInt(proof.leafIndex).toString(),
    storage_key: keyBigInt.toString(),
    storage_value_before: currentValue.toString(),
    storage_value_after: nextValue.toString(),
    proof: proof.siblings.map((siblings) => BigInt(siblings[0] ?? 0n).toString()),
  };

  writeJson(path.join(operationDir, "input.json"), input);
  run("node", ["groth16/prover/updateTree/generateProof.mjs", "--input", path.join(operationDir, "input.json")], {
    cwd: projectRoot,
  });

  const proofJson = readJson(path.join(projectRoot, "groth16", "prover", "updateTree", "proof.json"));
  const publicSignals = readJson(path.join(projectRoot, "groth16", "prover", "updateTree", "public.json"));
  writeJson(path.join(operationDir, "proof.json"), proofJson);
  writeJson(path.join(operationDir, "public.json"), publicSignals);

  return {
    input,
    proofJson,
    publicSignals,
    proof: toGrothSolidityProof(proofJson),
    update: {
      currentRootVector: currentSnapshot.stateRoots,
      updatedRoot: bytes32FromBigInt(updatedRoot),
      currentUserKey: bytes32FromHex(keyHex),
      currentUserValue: currentValue,
      updatedUserKey: bytes32FromHex(keyHex),
      updatedUserValue: nextValue,
    },
    nextSnapshot,
  };
}

function run(command, args, { cwd = projectRoot, env = process.env, quiet = false } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    stdio: quiet ? ["ignore", "ignore", "ignore"] : "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}.`);
  }
}

function runGitInTokamak(args) {
  const result = spawnSync("git", args, {
    cwd: tokamakRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    const stderr = result.stderr?.trim();
    const stdout = result.stdout?.trim();
    const detail = stderr || stdout || `exit code ${result.status ?? "unknown"}`;
    throw new Error(`git ${args.join(" ")} failed in ${tokamakRoot}: ${detail}`);
  }
  return result.stdout ?? "";
}

function runTokamakProofPipeline({ operationDir, bundlePath }) {
  run(tokamakCliPath, ["--synthesize", "--tokamak-ch-tx", operationDir], { cwd: tokamakRoot, quiet: true });
  run(tokamakCliPath, ["--preprocess"], { cwd: tokamakRoot, quiet: true });
  run(tokamakCliPath, ["--prove"], { cwd: tokamakRoot, quiet: true });
  run(tokamakCliPath, ["--extract-proof", bundlePath], { cwd: tokamakRoot, quiet: true });
  run(tokamakCliPath, ["--verify", bundlePath], { cwd: tokamakRoot, quiet: true });
  copyTokamakOperationArtifacts(operationDir);
}

function copyTokamakOperationArtifacts(operationDir) {
  const resourceRoot = path.join(operationDir, "resource");
  fs.rmSync(resourceRoot, { recursive: true, force: true });

  const requiredFiles = [
    ["preprocess", "output", "preprocess.json"],
    ["prove", "output", "proof.json"],
    ["synthesizer", "output", "instance.json"],
    ["synthesizer", "output", "state_snapshot.json"],
  ];

  for (const segments of requiredFiles) {
    const sourcePath = path.join(tokamakRoot, "dist", "resource", ...segments);
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
    proofPart1: proofJson.proof_entries_part1.map((value) => BigInt(value)),
    proofPart2: proofJson.proof_entries_part2.map((value) => BigInt(value)),
    functionPreprocessPart1: preprocessJson.preprocess_entries_part1.map((value) => BigInt(value)),
    functionPreprocessPart2: preprocessJson.preprocess_entries_part2.map((value) => BigInt(value)),
    aPubUser: instanceJson.a_pub_user.map((value) => BigInt(value)),
    aPubBlock: normalizeTokamakAPubBlock(instanceJson.a_pub_block.map((value) => BigInt(value))),
  };
}

function buildTokamakTxSnapshot({ signerPrivateKey, senderPubKey, to, data, nonce }) {
  const tx = createTokamakL2Tx(
    {
      nonce: BigInt(nonce),
      to: createAddressFromString(to),
      data: hexToBytes(data),
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
  const valueBytes = await stateManager.getStorage(createAddressFromString(address), hexToBytes(keyHex));
  if (valueBytes.length === 0) {
    return 0n;
  }
  return bytesToBigInt(valueBytes);
}

function deriveLiquidBalanceStorageKey(l2Address, slot) {
  return bytesToHex(getUserStorageKey([l2Address, BigInt(slot)], "TokamakL2"));
}

function deriveChannelTokenVaultLeafIndex(storageKey) {
  return BigInt(storageKey) % BigInt(MAX_MT_LEAVES);
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

function assertSnapshotMatchesChannel(snapshot, currentRootVectorHash, managedStorageAddresses) {
  const normalizedSnapshot = normalizeStateSnapshot(snapshot);
  expect(
    normalizeBytes32Hex(hashRootVector(normalizedSnapshot.stateRoots)) === normalizeBytes32Hex(currentRootVectorHash),
    "Imported snapshot roots do not match the current on-chain channel roots.",
  );
  expect(
    JSON.stringify(normalizedAddressVector(normalizedSnapshot.storageAddresses))
      === JSON.stringify(normalizedAddressVector(managedStorageAddresses)),
    "Imported snapshot storage-address vector does not match the channel-managed storage vector.",
  );
}

function normalizeStateSnapshot(snapshot) {
  return {
    ...snapshot,
    stateRoots: normalizedRootVector(snapshot.stateRoots),
    storageAddresses: normalizedAddressVector(snapshot.storageAddresses),
    storageEntries: snapshot.storageEntries.map((entries) => entries
      .filter((entry) => !isZeroLikeStorageValue(entry.value))
      .map((entry) => ({
        key: entry.key.toLowerCase(),
        value: entry.value.toLowerCase(),
      }))),
  };
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

function normalizeBytes32Hex(hexValue) {
  return ethers.zeroPadValue(ethers.toBeHex(BigInt(hexValue)), 32).toLowerCase();
}

function bytes32FromHex(hexValue) {
  return ethers.zeroPadValue(ethers.toBeHex(BigInt(hexValue)), 32);
}

function bytes32FromBigInt(value) {
  return ethers.zeroPadValue(ethers.toBeHex(value), 32);
}

function bigintToHex32(value) {
  return ethers.zeroPadValue(ethers.toBeHex(value), 32);
}

function hashTokamakPublicInputs(values) {
  return keccak256(abiCoder.encode(["uint256[]"], [values]));
}

function encodeTokamakBlockInfo(blockInfo) {
  const values = new Array(TOKAMAK_APUB_BLOCK_LENGTH).fill(0n);
  appendSplitWord(values, 0, BigInt(blockInfo.coinBase));
  appendSplitWord(values, 2, BigInt(blockInfo.timeStamp));
  appendSplitWord(values, 4, BigInt(blockInfo.blockNumber));
  appendSplitWord(values, 6, BigInt(blockInfo.prevRanDao));
  appendSplitWord(values, 8, BigInt(blockInfo.gasLimit));
  appendSplitWord(values, 10, BigInt(blockInfo.chainId));
  appendSplitWord(values, 12, BigInt(blockInfo.selfBalance));
  appendSplitWord(values, 14, BigInt(blockInfo.baseFee));
  for (let index = 0; index < TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT; index += 1) {
    appendSplitWord(values, 16 + index * 2, BigInt(blockInfo.prevBlockHashes[index] ?? 0n));
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
  const normalized = BigInt(value);
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
}) {
  const genesisSnapshot = {
    channelId: channelId.toString(),
    stateRoots: managedStorageAddresses.map(() => normalizeBytes32Hex(INITIAL_ZERO_ROOT)),
    storageAddresses: managedStorageAddresses,
    storageEntries: managedStorageAddresses.map(() => []),
  };

  const bridgeTokenVault = new Contract(
    channelInfo.bridgeTokenVault,
    bridgeAbiManifest.contracts.bridgeTokenVault.abi,
    provider,
  );
  const rootEvents = await channelManager.queryFilter(channelManager.filters.CurrentRootVectorObserved(), genesisBlockNumber);
  const channelStorageWriteEvents =
    await channelManager.queryFilter(channelManager.filters.StorageWriteObserved(), genesisBlockNumber);
  const vaultStorageWriteEvents =
    await bridgeTokenVault.queryFilter(bridgeTokenVault.filters.StorageWriteObserved(), genesisBlockNumber);

  const groupedEvents = new Map();
  for (const event of [...rootEvents, ...channelStorageWriteEvents, ...vaultStorageWriteEvents]) {
    const key = event.transactionHash;
    const group = groupedEvents.get(key) ?? [];
    group.push(event);
    groupedEvents.set(key, group);
  }

  const groupedValues = [...groupedEvents.values()].sort((left, right) => compareLogsByPosition(left[0], right[0]));
  let currentSnapshot = normalizeStateSnapshot(genesisSnapshot);
  let stateManager = await buildStateManager(currentSnapshot, contractCodes);

  for (const group of groupedValues) {
    const orderedGroup = [...group].sort(compareLogsByPosition);
    const rootEvent = orderedGroup.find(
      (event) => event.address.toLowerCase() === channelInfo.manager.toLowerCase()
        && event.fragment?.name === "CurrentRootVectorObserved",
    );
    if (!rootEvent) {
      continue;
    }

    const emittedRootVector = normalizedRootVector(rootEvent.args.rootVector);
    const emittedRootVectorHash = normalizeBytes32Hex(rootEvent.args.rootVectorHash);

    for (const event of orderedGroup) {
      if (event.fragment?.name !== "StorageWriteObserved") {
        continue;
      }
      const storageAddr = getAddress(event.args.storageAddr);
      const storageKey = bytes32FromBigInt(BigInt(event.args.storageKey));
      const storageValue = bigintToHex32(BigInt(event.args.value));
      await stateManager.putStorage(
        createAddressFromString(storageAddr),
        hexToBytes(storageKey),
        hexToBytes(storageValue),
      );
    }

    currentSnapshot = normalizeStateSnapshot(await stateManager.captureStateSnapshot());
    expect(
      normalizeBytes32Hex(hashRootVector(currentSnapshot.stateRoots)) === emittedRootVectorHash,
      `CurrentRootVectorObserved hash mismatch at tx ${rootEvent.transactionHash}.`,
    );
    expect(
      JSON.stringify(currentSnapshot.stateRoots) === JSON.stringify(emittedRootVector),
      `CurrentRootVectorObserved root vector mismatch at tx ${rootEvent.transactionHash}.`,
    );
  }

  expect(
    normalizeBytes32Hex(hashRootVector(currentSnapshot.stateRoots)) === normalizeBytes32Hex(currentRootVectorHash),
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

function toGrothSolidityProof(proof) {
  return {
    pA: [
      ...splitFieldElement(proof.pi_a[0]),
      ...splitFieldElement(proof.pi_a[1]),
    ],
    pB: [
      ...splitFieldElement(proof.pi_b[0][1]),
      ...splitFieldElement(proof.pi_b[0][0]),
      ...splitFieldElement(proof.pi_b[1][1]),
      ...splitFieldElement(proof.pi_b[1][0]),
    ],
    pC: [
      ...splitFieldElement(proof.pi_c[0]),
      ...splitFieldElement(proof.pi_c[1]),
    ],
  };
}

function splitFieldElement(value) {
  const hexValue = BigInt(value).toString(16).padStart(96, "0");
  return [
    BigInt(`0x${"0".repeat(32)}${hexValue.slice(0, 32)}`),
    BigInt(`0x${hexValue.slice(32)}`),
  ];
}

function serializeBigInts(value) {
  return JSON.parse(JSON.stringify(value, (_key, current) => (
    typeof current === "bigint" ? current.toString() : current
  )));
}

function sanitizeReceipt(receipt) {
  return serializeBigInts({
    hash: receipt.hash,
    blockHash: receipt.blockHash,
    blockNumber: receipt.blockNumber,
    gasUsed: receipt.gasUsed,
    from: receipt.from,
    to: receipt.to,
    status: receipt.status,
    logs: receipt.logs,
  });
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
    throw new Error(`Missing ${contractName} storage layout in ${JSON.stringify(storageLayoutManifest)}`);
  }

  const entry = contract.storageLayout.storage.find((item) => item.label === label);
  if (!entry) {
    throw new Error(`Missing storage slot ${label} in ${contractName}.`);
  }
  return entry.slot;
}

function defaultBridgeDeploymentPath(chainId) {
  return path.resolve(bridgeRoot, "deployments", `bridge.${chainId}.json`);
}

function defaultBridgeAbiManifestPath(chainId) {
  return path.resolve(bridgeRoot, "deployments", `bridge-abi-manifest.${chainId}.json`);
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
  return parsed;
}

function toCamelCase(value) {
  return value.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
}

function toKebabCase(value) {
  return value.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
}

function parseBooleanFlag(value) {
  if (value === undefined) return false;
  if (value === true) return true;
  if (typeof value === "string") {
    return value === "true" || value === "1";
  }
  return Boolean(value);
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

function requireL1Signer(args, env, provider) {
  const privateKey = args.privateKey ?? env.APPS_DEPLOYER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("Missing --private-key and APPS_DEPLOYER_PRIVATE_KEY.");
  }
  return new Wallet(normalizePrivateKey(privateKey), provider);
}

function channelWorkspacePath(name) {
  return workspaceDirForName(workspaceRoot, name);
}

function walletPath(name) {
  const walletName = String(name);
  const { channelName } = parseWalletName(walletName);
  const workspaceDir = channelWorkspacePath(channelName);
  return walletDirForName(workspaceWalletsDir(workspaceDir), walletName);
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

function assertWalletPasswordArgs(args, commandName, extraOptionKeys = [], acceptedUsage = "--wallet and --password") {
  requireWalletName(args);
  requireL2Password(args);
  assertAllowedCommandKeys(
    args,
    commandName,
    new Set(["command", "positional", "wallet", "password", ...extraOptionKeys]),
    acceptedUsage,
  );
}

function assertWalletChannelMoveArgs(args, commandName) {
  requireArg(args.amount, "--amount");
  assertWalletPasswordArgs(args, commandName, ["amount"], "--wallet, --password, and --amount");
}

function assertRegisterChannelArgs(args) {
  requireL2Password(args);
  expect(
    args.channelName !== undefined || args.workspace !== undefined,
    "register-channel requires either --channel-name or --workspace.",
  );
  const allowedKeys = new Set([
    "command",
    "positional",
    "channelName",
    "workspace",
    "network",
    "privateKey",
    "password",
    "envFile",
    "rpcUrl",
    "alchemyApiKey",
  ]);
  const unsupported = Object.keys(args)
    .filter((key) => !allowedKeys.has(key))
    .map((key) => `--${toKebabCase(key)}`);
  if (unsupported.length > 0) {
    throw new Error(
      [
        "register-channel only accepts --channel-name or --workspace, plus",
        "--network, --rpc-url, --alchemy-api-key, --private-key, --password, and --env-file.",
        `Unsupported option(s): ${unsupported.join(", ")}.`,
      ].join(" "),
    );
  }
  expect(
    (args.positional ?? []).length === 1,
    "register-channel does not accept positional arguments beyond the command name.",
  );
}

function assertIsChannelRegisteredArgs(args) {
  assertWalletPasswordArgs(args, "is-channel-registered");
}

function assertGetWalletAddressArgs(args) {
  assertWalletPasswordArgs(args, "get-wallet-address");
}

function assertInstallZkEvmArgs(args) {
  assertAllowedCommandKeys(args, "install-zk-evm", new Set(["command", "positional"]), "no options");
}

function assertUninstallZkEvmArgs(args) {
  assertAllowedCommandKeys(args, "uninstall-zk-evm", new Set(["command", "positional"]), "no options");
}

function assertWithdrawBridgeArgs(args) {
  requireArg(args.amount, "--amount");
  assertWalletPasswordArgs(args, "withdraw-bridge", ["amount"], "--wallet, --password, and --amount");
}

function assertMintNotesArgs(args) {
  requireArg(args.amounts, "--amounts");
  assertWalletPasswordArgs(args, "mint-notes", ["amounts"], "--wallet, --password, and --amounts");
  parseTokenAmountVector(args.amounts);
}

function assertRedeemNotesArgs(args) {
  requireArg(args.noteId, "--note-id");
  assertWalletPasswordArgs(args, "redeem-notes", ["noteId"], "--wallet, --password, and --note-id");
  parseNoteId(args.noteId);
}

function assertTransferNotesArgs(args) {
  requireArg(args.noteIds, "--note-ids");
  requireArg(args.recipients, "--recipients");
  requireArg(args.amounts, "--amounts");
  assertWalletPasswordArgs(
    args,
    "transfer-notes",
    ["noteIds", "recipients", "amounts"],
    "--wallet, --password, --note-ids, --recipients, and --amounts",
  );
  const noteIds = parseNoteIdVector(args.noteIds);
  const recipients = parseRecipientVector(args.recipients);
  const amounts = parseTokenAmountVector(args.amounts);
  expect(
    recipients.length === amounts.length,
    "--amounts length must match --recipients length.",
  );
  selectTransferNotesMethod(noteIds.length, recipients.length);
}

function assertGetMyNotesArgs(args) {
  assertWalletPasswordArgs(args, "get-my-notes");
}

function assertGetChannelDepositArgs(args) {
  assertWalletPasswordArgs(args, "get-channel-deposit");
}

function createWalletOperationDir(walletName, suffix) {
  const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const operationDir = path.join(
    walletPath(walletName),
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
    normalizeStateSnapshot(context.currentSnapshot),
  );
}

function printHelp() {
  console.log(`private-state bridge CLI

Usage:
  node apps/private-state/cli/private-state-bridge-cli.mjs install-zk-evm
  node apps/private-state/cli/private-state-bridge-cli.mjs uninstall-zk-evm
  node apps/private-state/cli/private-state-bridge-cli.mjs create-channel --channel-name <name> --dapp-label <label> --private-key <hex> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs mint-notes --wallet <name> --password <string> --amounts '[1,2,3]'
  node apps/private-state/cli/private-state-bridge-cli.mjs redeem-notes --wallet <name> --password <string> --note-id <commitment>
  node apps/private-state/cli/private-state-bridge-cli.mjs transfer-notes --wallet <name> --password <string> --note-ids '["0x..."]' --recipients '["0x..."]' --amounts '[1]'
  node apps/private-state/cli/private-state-bridge-cli.mjs get-my-notes --wallet <name> --password <string>
  node apps/private-state/cli/private-state-bridge-cli.mjs recover-workspace --channel-name <name> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs deposit-bridge --private-key <hex> --amount <tokens> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs withdraw-bridge --wallet <name> --password <string> --amount <tokens>
  node apps/private-state/cli/private-state-bridge-cli.mjs get-bridge-deposit [--private-key <hex>] [--wallet <name> --password <string>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs is-channel-registered --wallet <name> --password <string>
  node apps/private-state/cli/private-state-bridge-cli.mjs get-wallet-address --wallet <name> --password <string>
  node apps/private-state/cli/private-state-bridge-cli.mjs get-channel-deposit --wallet <name> --password <string>
  node apps/private-state/cli/private-state-bridge-cli.mjs register-channel (--channel-name <name> | --workspace <channel-workspace>) [--private-key <hex>] --password <string> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs deposit-channel --wallet <name> --password <string> --amount <tokens>
  node apps/private-state/cli/private-state-bridge-cli.mjs withdraw-channel --wallet <name> --password <string> --amount <tokens>

Common flags:
  --network <name>         Override APPS_NETWORK from apps/.env. Allowed: mainnet, sepolia, anvil
  --rpc-url <url>          Explicit RPC endpoint override
  --alchemy-api-key <key>  Explicit Alchemy key override
  --env-file <path>        Alternate apps/.env location

create-channel options:
  --dapp-label <label>          Registered bridge DApp label to bind to the new channel
  --leader <address>           Optional channel leader. Default: the signing EOA
  --create-workspace           Also initialize a channel workspace after creation using the channel name

recover-workspace options:
  --channel-name <name>        User-provided channel name; channelId is derived as keccak256(bytes(name))
  --block-info-file <path>     Optional block_info.json override; must match the channel genesis block context
  --state-snapshot-file <path> Import an existing non-genesis snapshot
  --force                      Overwrite an existing workspace

Notes:
  - install-zk-evm accepts no options. Before running tokamak-cli --install, it fetches origin/dev in submodules/Tokamak-zk-EVM, switches to the local dev branch, fast-forwards it, and then runs the installer.
  - uninstall-zk-evm accepts no options and removes every file and directory inside submodules/Tokamak-zk-EVM except the submodule's .git pointer file.
  - anvil is allowed as a CLI network only for command-driven end-to-end testing. It is not the intended network for user-facing real-world operation.
  - mint-notes requires --wallet, --password, and --amounts only. It derives the network and channel from the local wallet, maps the amount-vector length to the underlying fixed-arity mintNotes<N> call, and stores minted notes back into the encrypted wallet.
  - redeem-notes requires --wallet, --password, and --note-id only. It uses a note commitment from get-my-notes, redeems through redeemNotes1, and credits the wallet owner's L2 liquid balance.
  - transfer-notes requires --wallet, --password, --note-ids, --recipients, and --amounts only. It uses note commitments from get-my-notes as note IDs, enforces --amounts.length === --recipients.length, and supports only 1->1, 1->2, and 2->1 transfer shapes.
  - get-my-notes requires --wallet and --password only. It scans bridge-propagated private-state transfer events from Ethereum, decrypts the caller's incoming note payloads, merges any newly discovered notes into the encrypted wallet, and then verifies each tracked note against the current controller commitment/nullifier state accepted by the bridge.
  - mint-notes, redeem-notes, and transfer-notes always run from the saved channel workspace under apps/private-state/cli/workspace/<channel-name>/channel/. If that workspace is missing or stale, the CLI rebuilds it through recover-workspace semantics, reloads it from disk, and then continues. A tokamak-cli --verify failure is also treated as recoverable once.
  - redeem-notes updates both the encrypted wallet note sets and the saved channel workspace snapshot after success.
  - transfer-notes updates both the encrypted wallet note sets and the saved channel workspace snapshot after success.
  - transfer-notes updates the sender wallet and relies on Ethereum event logs for recipient note discovery. It does not rewrite recipient wallet files.
  - recover-workspace derives block_info.json from the channel genesis block and reconstructs the latest channel state from bridge events.
  - recover-workspace always writes into apps/private-state/cli/workspace/<channel-name>/channel/.
  - Channel workspaces remain optional as user-managed files, but wallet-backed snapshot commands now create or refresh them automatically before execution.
  - Wallets are the mandatory local state for note-carrying users. They track L2 identity, nonce, and used/unused notes.
  - deposit-bridge only funds the shared bridge-level bridgeTokenVault.
  - withdraw-bridge requires --wallet, --password, and --amount only. It derives the network and signer keys from the local wallet and calls claimToWallet to move value from the shared bridge-level bridgeTokenVault back into Tokamak Network Token in the caller wallet.
  - get-bridge-deposit reads the caller's shared bridge-level bridgeTokenVault balance.
  - is-channel-registered requires --wallet and --password only. It derives the network and channel from the local wallet, then checks whether the wallet's L2 identity matches the on-chain channel registration.
  - get-wallet-address requires --wallet and --password only. It derives the network and channel from the local wallet, then reads the caller's registered L2 address from the bridge channel registration.
  - get-channel-deposit requires --wallet and --password only. It derives the network and channel from the local wallet, requires the wallet's L2 identity to match the on-chain channel registration, and then reads the current channel L2 accounting balance bound to that registration.
  - register-channel is the channel-specific identity binding step. It stores the caller's L2 address, channelTokenVault key, channelTokenVault leaf index, and local wallet keys for the selected channel.
  - register-channel always creates or reuses the deterministic wallet folder name <channelName>-<l2Address>. It does not accept --wallet.
  - register-channel is the only command that sets up wallet keys in the active wallet.
  - mint-notes, redeem-notes, and transfer-notes update nonce and note state inside an existing wallet, but they do not set up wallet keys.
  - Once a wallet exists, get-bridge-deposit, withdraw-bridge, mint-notes, redeem-notes, and transfer-notes can recover the stored signer and L2 identity from the encrypted wallet using --password alone.
  - deposit-channel requires --wallet, --password, and --amount only. It derives the network, channel, and signer keys from the local wallet and fails if wallet metadata or keys are missing.
  - withdraw-channel requires --wallet, --password, and --amount only. It derives the network, channel, and signer keys from the local wallet and calls the bridge withdraw path to move value from the channel L2 accounting vault back into the shared L1 bridgeTokenVault.
  - Every wallet-backed command that depends on a channel StateSnapshot first ensures apps/private-state/cli/workspace/<channel-name>/channel/ exists on disk. If the workspace is missing or stale, the CLI rebuilds it through recover-workspace semantics, saves it, reloads it from disk, and only then runs the command.
  - Recipients discover incoming notes by running get-my-notes, which decrypts NoteValueEncrypted event logs emitted through the bridge execution path and caches the last scanned block in the local wallet.
  - Every --amount value is interpreted as a human token amount using the canonical Tokamak Network Token decimals.
  - The CLI auto-selects bridge deployment and ABI files from the chosen network's chain ID.
  - Channel workspace operations are stored under:
      apps/private-state/cli/workspace/<workspace>/channel/operations/
  - Wallet operations are stored under:
      apps/private-state/cli/workspace/<channel-name>/wallets/<wallet>/operations/
`);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writeEncryptedWalletJson(filePath, value, walletPassword) {
  writeEncryptedWalletFile(filePath, Buffer.from(`${JSON.stringify(value, null, 2)}\n`, "utf8"), walletPassword);
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
    salt: ethers.hexlify(salt),
    iv: ethers.hexlify(iv),
    tag: ethers.hexlify(tag),
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

function resolveInputPath(inputPath) {
  return path.isAbsolute(inputPath) ? inputPath : path.resolve(projectRoot, inputPath);
}

function loadEnv(envFile) {
  if (!fs.existsSync(envFile)) {
    return {};
  }

  const env = {};
  const lines = fs.readFileSync(envFile, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    const separator = trimmed.indexOf("=");
    if (separator === -1) {
      continue;
    }
    const key = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim();
    env[key] = stripQuotes(value);
  }
  return env;
}

function loadWalletCommandRuntime(args) {
  const env = loadEnv(defaultEnvFile);
  const walletMetadata = loadWalletMetadata(requireWalletName(args));
  const rpcUrl = deriveRpcUrl({
    networkName: walletMetadata.network,
    alchemyApiKey: env.APPS_ALCHEMY_API_KEY,
    rpcUrlOverride: env.APPS_RPC_URL_OVERRIDE,
  });
  return {
    provider: new JsonRpcProvider(rpcUrl),
  };
}

function stripQuotes(value) {
  if (
    (value.startsWith("\"") && value.endsWith("\""))
    || (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function normalizePrivateKey(value) {
  return value.startsWith("0x") ? value : `0x${value}`;
}

function printJson(value) {
  const output = `${JSON.stringify(value, null, 2)}\n`;
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

function isZeroLikeStorageValue(value) {
  if (typeof value !== "string") {
    return false;
  }
  const normalized = value.trim().toLowerCase();
  return normalized === "0x" || normalized === "0x0" || normalized === "0x00";
}

main().catch((error) => {
  console.error(error.message ?? String(error));
  process.exitCode = 1;
});
