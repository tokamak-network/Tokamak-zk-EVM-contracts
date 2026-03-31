#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
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
} from "../script/utils/private-state-cli-shared.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../..");
const appRoot = path.resolve(projectRoot, "apps/private-state");
const deployRoot = path.resolve(appRoot, "deploy");
const bridgeRoot = path.resolve(projectRoot, "bridge");
const workspaceRoot = path.resolve(os.homedir(), "tokamak-private-channels", "workspace");
const gitmodulesPath = path.resolve(projectRoot, ".gitmodules");
const tokamakSubmodulePath = "submodules/Tokamak-zk-EVM";
const tokamakRoot = path.resolve(projectRoot, "submodules", "Tokamak-zk-EVM");
const tokamakCliPath = path.resolve(tokamakRoot, "tokamak-cli");

const abiCoder = AbiCoder.defaultAbiCoder();
const erc20MetadataAbi = [
  "function decimals() view returns (uint8)",
];
const TOKAMAK_APUB_BLOCK_LENGTH = 63;
const TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT = 4;
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
const ZERO_TOPIC = normalizeBytes32Hex(ethers.ZeroHash);
const JUBJUB_ORDER = jubjub.CURVE.n;
const JUBJUB_FP = jubjub.CURVE.Fp;
const JUBJUB_A = jubjub.CURVE.a;
const JUBJUB_D = jubjub.CURVE.d;
const INITIAL_ZERO_ROOT =
  "0x0ce3a78a0131c84050bbe2205642f9e176ffe98488dbddb19336b987420f3bde";
const BLS12_381_SCALAR_FIELD_MODULUS =
  BigInt("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");
const DEFAULT_LOG_CHUNK_SIZE = 2000;

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
    "deposit-channel": {
      assert: (parsedArgs) => assertWalletChannelMoveArgs(parsedArgs, "deposit-channel"),
      run: ({ provider }) => handleGrothVaultMove({ args, provider, direction: "deposit" }),
    },
    "withdraw-channel": {
      assert: (parsedArgs) => assertWalletChannelMoveArgs(parsedArgs, "withdraw-channel"),
      run: ({ provider }) => handleGrothVaultMove({ args, provider, direction: "withdraw" }),
    },
    "get-my-address": {
      assert: assertGetMyAddressArgs,
      run: ({ provider }) => handleGetMyAddress({ args, provider }),
    },
    "get-my-channel-fund": {
      assert: assertGetMyChannelFundArgs,
      run: ({ provider }) => handleGetMyChannelFund({ args, provider }),
    },
  };
  if (walletCommandHandlers[args.command]) {
    walletCommandHandlers[args.command].assert(args);
    const { provider } = loadWalletCommandRuntime(args);
    await walletCommandHandlers[args.command].run({ provider });
    return;
  }

  switch (args.command) {
    case "create-channel": {
      assertCreateChannelArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await handleChannelCreate({ args, network, provider });
      return;
    }
    case "recover-workspace": {
      assertRecoverWorkspaceArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await handleWorkspaceInit({ args, network, provider });
      return;
    }
    case "deposit-bridge": {
      assertDepositBridgeArgs(args);
      const { network, provider } = loadExplicitCommandRuntime(args);
      await handleRegisterAndFund({ args, network, provider });
      return;
    }
    case "withdraw-bridge": {
      assertWithdrawBridgeArgs(args);
      const { provider } = loadExplicitCommandRuntime(args);
      await handleWithdrawBridge({ args, provider });
      return;
    }
    case "get-my-bridge-fund": {
      assertGetMyBridgeFundArgs(args);
      const { provider } = loadExplicitCommandRuntime(args);
      await handleGetMyBridgeFund({ args, provider });
      return;
    }
    case "recover-wallet": {
      assertRecoverWalletArgs(args);
      const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args);
      await handleRecoverWallet({ args, network, provider, rpcUrl });
      return;
    }
    case "join-channel": {
      assertJoinChannelArgs(args);
      const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args);
      await handleJoinChannel({ args, network, provider, rpcUrl });
      return;
    }
    case "get-my-address":
      throw new Error("get-my-address requires explicit --network.");
    case "get-my-channel-fund":
      throw new Error("get-my-channel-fund requires explicit --network.");
    case "mint-notes":
      throw new Error("mint-notes requires explicit --network.");
    case "redeem-notes":
      throw new Error("redeem-notes requires explicit --network.");
    case "get-my-notes":
      throw new Error("get-my-notes requires explicit --network.");
    case "transfer-notes":
      throw new Error("transfer-notes requires explicit --network.");
    case "withdraw-channel":
      throw new Error("withdraw-channel requires explicit --network.");
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
  const channelId = deriveChannelIdFromName(channelName);
  const dappId = await resolveDAppIdByLabel({
    provider,
    bridgeResources,
    dappLabel: PRIVATE_STATE_DAPP_LABEL,
  });

  const receipt = await waitForReceipt(await bridgeCore.createChannel(channelId, dappId, leader));
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
  const manifestPath = path.resolve(
    projectRoot,
    "bridge",
    "deployments",
    `dapp-registration.${bridgeResources.chainId}.json`,
  );
  const manifest = readJsonIfExists(manifestPath);
  if (manifest !== null) {
    const manifestLabel = typeof manifest.dappLabel === "string" ? manifest.dappLabel : null;
    const manifestDappId = manifest.dappId;
    const manifestManager = typeof manifest.dAppManager === "string" ? getAddress(manifest.dAppManager) : null;
    if (
      manifestLabel === dappLabel
      && Number.isInteger(manifestDappId)
      && manifestManager !== null
      && manifestManager === getAddress(bridgeResources.bridgeDeployment.dAppManager)
    ) {
      const info = await dAppManager.getDAppInfo(manifestDappId);
      if (info.exists && normalizeBytes32Hex(info.labelHash) === expectedLabelHash) {
        return Number(manifestDappId);
      }
    }
  }

  const events = await queryContractEventsChunked({
    contract: dAppManager,
    eventName: "DAppRegistered",
    fromBlock: 0,
    toBlock: "latest",
  });
  const matchingIds = [];

  for (const event of events) {
    const eventLabelHash = normalizeBytes32Hex(event.args?.labelHash);
    if (eventLabelHash === expectedLabelHash) {
      matchingIds.push(Number(event.args.dappId));
    }
  }

  if (matchingIds.length === 0) {
    throw new Error(`No registered DApp matches the hardcoded label ${dappLabel}.`);
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
      normalizeStateSnapshot(currentSnapshot),
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
    getAddress(registration.l2Address) === getAddress(l2Identity.l2Address),
    "The existing channel registration L2 address does not match the derived L2 address.",
  );
  expect(
    normalizeBytes32Hex(registration.channelTokenVaultKey) === normalizeBytes32Hex(storageKey),
    "The existing channel registration key does not match the derived channelTokenVault key.",
  );
  expect(
    BigInt(registration.leafIndex) === BigInt(leafIndex),
    "The existing channel registration leaf index does not match the derived leaf index.",
  );
  expect(
    normalizeBytes32Hex(registration.noteReceivePubKey.x) === normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x),
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
    l2PrivateKey: walletContext.wallet.l2PrivateKey,
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
    getAddress(wallet.l1Address) === getAddress(signerAddress),
    `Wallet ${walletContext.walletName} L1 address does not match the requested signer.`,
  );
  expect(
    getAddress(wallet.l2Address) === getAddress(l2Identity.l2Address),
    `Wallet ${walletContext.walletName} L2 address does not match the derived channel identity.`,
  );
  expect(
    normalizeBytes32Hex(wallet.l2StorageKey) === normalizeBytes32Hex(storageKey),
    `Wallet ${walletContext.walletName} storage key does not match the derived registration key.`,
  );
  expect(
    BigInt(wallet.leafIndex) === BigInt(leafIndex),
    `Wallet ${walletContext.walletName} leaf index does not match the derived registration leaf index.`,
  );
  expect(
    BigInt(wallet.channelId) === BigInt(channelContext.workspace.channelId),
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
    getAddress(wallet.channelManager) === getAddress(channelContext.workspace.channelManager),
    `Wallet ${walletContext.walletName} channel manager does not match the recovered workspace.`,
  );
  expect(
    getAddress(wallet.bridgeTokenVault) === getAddress(channelContext.workspace.bridgeTokenVault),
    `Wallet ${walletContext.walletName} bridge token vault does not match the recovered workspace.`,
  );
  expect(
    getAddress(wallet.controller) === getAddress(channelContext.workspace.controller),
    `Wallet ${walletContext.walletName} controller does not match the recovered workspace.`,
  );
  expect(
    getAddress(wallet.l2AccountingVault) === getAddress(channelContext.workspace.l2AccountingVault),
    `Wallet ${walletContext.walletName} L2 accounting vault does not match the recovered workspace.`,
  );
  expect(
    normalizeBytes32Hex(wallet.noteReceivePubKeyX) === normalizeBytes32Hex(noteReceiveKeyMaterial.noteReceivePubKey.x),
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
  const syncedDevCommit = syncTokamakSubmoduleToLatestDev();
  run(tokamakCliPath, ["--install"], { cwd: tokamakRoot });
  run("node", [path.join("script", "generate-tokamak-shared-constants.js")], { cwd: projectRoot });
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
  ensureTokamakSubmoduleWorktree();
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

function ensureTokamakSubmoduleWorktree() {
  expect(
    fs.existsSync(gitmodulesPath),
    `Repository gitmodules file does not exist: ${gitmodulesPath}.`,
  );

  const configuredPaths = runGitInProjectRoot([
    "config",
    "-f",
    gitmodulesPath,
    "--get-regexp",
    "^submodule\\..*\\.path$",
  ])
    .trim()
    .split("\n")
    .map((line) => line.trim().split(/\s+/, 2)[1])
    .filter(Boolean);

  expect(
    configuredPaths.includes(tokamakSubmodulePath),
    `.gitmodules does not declare the Tokamak zk-EVM submodule path ${tokamakSubmodulePath}.`,
  );

  runGitInProjectRoot(["submodule", "sync", "--", tokamakSubmodulePath]);
  runGitInProjectRoot(["submodule", "update", "--init", "--recursive", tokamakSubmodulePath]);
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

async function handleGetMyAddress({ args, provider }) {
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
    action: "get-my-address",
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
    leafIndex: existingRegistration.leafIndex.toString(),
    noteReceivePubKey: noteReceiveKeyMaterial.noteReceivePubKey,
    status: "already-registered",
  });
}

async function handleGrothVaultMove({ args, provider, direction }) {
  const { wallet: walletContext } = loadUnlockedWalletWithMetadata(args);
  const contextResult = await loadPreferredWalletChannelContext({ walletContext, provider });
  const context = contextResult.context;
  expect(
    BigInt(walletContext.wallet.channelId) === BigInt(context.workspace.channelId),
    "The provided wallet does not belong to the selected channel.",
  );

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
  sealWalletOperationDir(operationDir, walletContext.walletPassword);

  context.currentSnapshot = normalizeStateSnapshot(transition.nextSnapshot);
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
  });
}

async function handleWithdrawBridge({ args, provider }) {
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
    receipt: sanitizeReceipt(receipt),
  });
}

async function handleMintNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  const canonicalAssetDecimals = Number(wallet.wallet.canonicalAssetDecimals);
  const amountInputs = parseMintTokenAmountVector(requireArg(args.amounts, "--amounts"));
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
    usedWorkspaceCache: contextResult.usingWorkspaceCache,
    recoveredWorkspace,
    updatedRoots: execution.context.currentSnapshot.stateRoots,
  });
}

async function handleRedeemNotes({ args, provider }) {
  const { wallet } = loadUnlockedWalletWithMetadata(args);
  const noteIds = parseNoteIdVector(requireArg(args.noteIds, "--note-ids"));
  const inputNotes = loadRedeemInputNotes(wallet, noteIds);
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
    redeemedAmountBaseUnits: inputNotes.reduce((sum, note) => sum + BigInt(note.value), 0n).toString(),
    redeemedAmountTokens: ethers.formatUnits(
      inputNotes.reduce((sum, note) => sum + BigInt(note.value), 0n),
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
    l2PrivateKey: wallet.wallet.l2PrivateKey,
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

function reconcileWalletNotesWithBridgeState({
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
    const commitmentExists = readBooleanStorageValueFromSnapshot({
      snapshot: currentSnapshot,
      storageAddress: controllerAddress,
      storageKey: normalizedNote.bridgeCommitmentKey,
    });
    if (!commitmentExists) {
      continue;
    }

    const nullifierUsed = readBooleanStorageValueFromSnapshot({
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
      .reduce((sum, note) => sum + BigInt(note.value), 0n)
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
  l2PrivateKey,
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
  const observedLogs = await fetchLogsChunked(provider, {
    address: context.workspace.channelManager,
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
          l2PrivateKey,
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
  const reconciledState = reconcileWalletNotesWithBridgeState({
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
  const data = ethers.getBytes(ethers.concat([
    NOTE_COMMITMENT_DOMAIN,
    ethers.zeroPadValue(getAddress(note.owner), 32),
    ethers.toBeHex(BigInt(note.value), 32),
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
    ethers.toBeHex(BigInt(note.value), 32),
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

function pointFromL2PublicKey(l2PublicKey) {
  return jubjub.ExtendedPoint.fromHex(ethers.getBytes(l2PublicKey));
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
  const encoded = abiCoder.encode(["bytes32", "uint256"], [normalizeBytes32Hex(keyHex), BigInt(slot)]);
  return normalizeBytes32Hex(bytesToHex(poseidon(hexToBytes(encoded))));
}

function computeEncryptedNoteSalt(encryptedValue) {
  const normalized = normalizeEncryptedNoteValueWords(encryptedValue);
  return normalizeBytes32Hex(
    ethers.hexlify(poseidon(ethers.getBytes(ethers.concat(normalized)))),
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

function deriveFieldMask({ sharedSecretPoint, chainId, channelId, owner, nonce, encryptionInfo }) {
  const affine = sharedSecretPoint.toAffine();
  return BigInt(
    bytesToHex(
      poseidon(
        ethers.getBytes(
          abiCoder.encode(
            ["string", "uint256", "uint256", "address", "uint256", "uint256", "bytes12"],
            [
              encryptionInfo,
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

function encryptMintNoteValueForOwner({ value, ownerL2PublicKey, chainId, channelId, owner }) {
  return encryptFieldNoteValue({
    value,
    recipientPoint: pointFromL2PublicKey(ownerL2PublicKey),
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

function decryptMintEncryptedNoteValue({ encryptedValue, l2PrivateKey, chainId, channelId, owner }) {
  return decryptFieldEncryptedNoteValue({
    encryptedValue,
    privateKey: l2PrivateKey,
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
  const previousEntries = snapshotStorageEntriesForAddress(previousSnapshot, controllerAddress);
  const nextEntries = snapshotStorageEntriesForAddress(nextSnapshot, controllerAddress);
  const previousKeys = new Set(previousEntries.map((entry) => normalizeBytes32Hex(entry.key)));
  const newKeys = nextEntries
    .map((entry) => normalizeBytes32Hex(entry.key))
    .filter((key) => !previousKeys.has(key));
  const inputCount = lifecycle.inputs.length;
  const outputCount = lifecycle.outputs.length;
  const expectedNewKeyCount = inputCount + outputCount;
  expect(
    newKeys.length >= expectedNewKeyCount,
    buildControllerStorageDeltaError({
      previousSnapshot,
      nextSnapshot,
      controllerAddress,
      previousEntries,
      nextEntries,
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
  previousEntries,
  nextEntries,
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
    `Tracked controller slots before: ${previousEntries.length}.`,
    `Tracked controller slots after: ${nextEntries.length}.`,
    `New controller slots discovered: ${newKeyCount}.`,
  ];
  if (previousEntries.length === 0 && nextEntries.length === 0) {
    details.push(
      "The local workspace snapshot already had no tracked controller storage slots, and the proof pipeline produced another snapshot with no tracked controller storage slots.",
    );
  }
  if (normalizeBytes32Hex(previousRoot) === normalizeBytes32Hex(nextRoot)) {
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

function snapshotStorageEntriesForAddress(snapshot, storageAddress) {
  const normalizedAddress = getAddress(storageAddress);
  const addressIndex = snapshot.storageAddresses.findIndex(
    (entry) => getAddress(entry) === normalizedAddress,
  );
  expect(addressIndex >= 0, `Storage snapshot does not include ${normalizedAddress}.`);
  return snapshot.storageEntries[addressIndex] ?? [];
}

function snapshotRootForAddress(snapshot, storageAddress) {
  const normalizedAddress = getAddress(storageAddress);
  const addressIndex = snapshot.storageAddresses.findIndex(
    (entry) => getAddress(entry) === normalizedAddress,
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
    abiFile: "../deploy/PrivateStateController.callable-abi.json",
    method,
    args: [mintOutputs],
    lifecycleOutputs,
  };
}

function buildRedeemNotesTemplatePayload({ wallet, inputNotes }) {
  return {
    abiFile: "../deploy/PrivateStateController.callable-abi.json",
    method: selectRedeemNotesMethod(inputNotes.length),
    args: [inputNotes, wallet.wallet.l2Address],
  };
}

function selectMintNotesMethod(noteCount) {
  expect(noteCount >= 1, "mint-notes requires at least one output amount.");
  expect(noteCount <= 6, "mint-notes supports at most six output amounts.");
  return `mintNotes${noteCount}`;
}

function selectRedeemNotesMethod(noteCount) {
  expect(noteCount >= 1, "redeem-notes requires at least one input note.");
  expect(noteCount <= 2, "redeem-notes supports at most two input notes.");
  return `redeemNotes${noteCount}`;
}

function buildMintEncryptedOutputs({ wallet, values }) {
  const mintOutputs = [];
  const lifecycleOutputs = [];
  for (const value of values) {
    const encryptedNoteValue = encryptMintNoteValueForOwner({
      value,
      ownerL2PublicKey: wallet.wallet.l2PublicKey,
      chainId: wallet.wallet.chainId,
      channelId: wallet.wallet.channelId,
      owner: wallet.wallet.l2Address,
    });
    mintOutputs.push({
      value: BigInt(value).toString(),
      encryptedNoteValue,
    });
    lifecycleOutputs.push({
      owner: wallet.wallet.l2Address,
      value: BigInt(value).toString(),
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

function loadRedeemInputNotes(walletContext, noteIds) {
  return noteIds.map((noteId) => {
    const trackedNote = walletContext.wallet.notes.unused[noteId];
    expect(trackedNote, `Unknown unused note commitment: ${noteId}.`);
    return normalizePlaintextNote(trackedNote);
  });
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

function parseMintTokenAmountVector(value) {
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
    expect(
      !normalized.startsWith("-"),
      `Invalid --amounts[${index}]. Each amount must be zero or greater.`,
    );
    return normalized;
  });
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

async function loadPreferredWalletChannelContext({ walletContext, provider }) {
  let recoveredWorkspace = false;
  if (!walletChannelWorkspaceIsReady(walletContext)) {
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

async function loadWorkspaceContext(workspaceName, networkName, provider) {
  const normalizedWorkspaceName = requireWorkspaceName({ workspace: workspaceName });
  const workspaceDir = channelWorkspacePath(networkName, normalizedWorkspaceName);
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
  const grothArtifacts = loadGroth16UpdateTreeArtifacts(Number(workspace.chainId));
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
  run(
    "node",
    [
      "groth16/prover/updateTree/generateProof.mjs",
      "--input",
      path.join(operationDir, "input.json"),
      "--zkey",
      grothArtifacts.zkeyPath,
    ],
    {
      cwd: projectRoot,
    },
  );

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
    encoding: "utf8",
    stdio: quiet ? ["ignore", "ignore", "ignore"] : "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}.`);
  }
}

function runCaptured(command, args, { cwd = projectRoot, env = process.env } = {}) {
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

function runGitInProjectRoot(args) {
  const result = spawnSync("git", args, {
    cwd: projectRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    const stderr = result.stderr?.trim();
    const stdout = result.stdout?.trim();
    const detail = stderr || stdout || `exit code ${result.status ?? "unknown"}`;
    throw new Error(`git ${args.join(" ")} failed in ${projectRoot}: ${detail}`);
  }
  return result.stdout ?? "";
}

function runTokamakProofPipeline({ operationDir, bundlePath }) {
  runTokamakCliStage({
    operationDir,
    stageName: "synthesize",
    args: ["--synthesize", "--tokamak-ch-tx", operationDir],
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
  const result = runCaptured(tokamakCliPath, args, { cwd: tokamakRoot });
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
  const latestBlock = await provider.getBlockNumber();
  const rootEvents = await queryContractEventsChunked({
    contract: channelManager,
    eventName: "CurrentRootVectorObserved",
    fromBlock: genesisBlockNumber,
    toBlock: latestBlock,
  });
  const channelStorageWriteEvents = await queryContractEventsChunked({
    contract: channelManager,
    eventName: "StorageWriteObserved",
    fromBlock: genesisBlockNumber,
    toBlock: latestBlock,
  });
  const vaultStorageWriteEvents = await queryContractEventsChunked({
    contract: bridgeTokenVault,
    eventName: "StorageWriteObserved",
    fromBlock: genesisBlockNumber,
    toBlock: latestBlock,
  });

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
      const logs = await provider.getLogs({
        address,
        topics,
        fromBlock: cursor,
        toBlock: chunkToBlock,
      });
      aggregatedLogs.push(...logs);
      cursor = chunkToBlock + 1;
    } catch (error) {
      const suggestedChunkSize = deriveRecommendedLogChunkSize(error, chunkSize);
      if (suggestedChunkSize >= chunkSize) {
        throw error;
      }
      chunkSize = suggestedChunkSize;
    }
  }

  return aggregatedLogs;
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
    const lower = Number(BigInt(recommendedWindowMatch[1]));
    const upper = Number(BigInt(recommendedWindowMatch[2]));
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

function groth16UpdateTreeManifestPath(chainId) {
  return path.resolve(deployRoot, `groth16-updateTree.${chainId}.latest.json`);
}

function resolveDeployManifestArtifactPath(manifestPath, artifactPath) {
  expect(
    typeof artifactPath === "string" && artifactPath.length > 0,
    `Invalid artifact path entry in ${manifestPath}.`,
  );
  return path.isAbsolute(artifactPath)
    ? artifactPath
    : path.resolve(path.dirname(manifestPath), artifactPath);
}

function loadGroth16UpdateTreeArtifacts(chainId) {
  const manifestPath = groth16UpdateTreeManifestPath(chainId);
  expect(
    fs.existsSync(manifestPath),
    `Missing Groth16 updateTree manifest for chain ${chainId}: ${manifestPath}.`,
  );

  const manifest = readJson(manifestPath);
  const zkeyPath = resolveDeployManifestArtifactPath(manifestPath, manifest.artifacts?.zkeyPath);

  for (const [label, artifactPath] of [
    ["Groth16 updateTree proving key", zkeyPath],
  ]) {
    expect(fs.existsSync(artifactPath), `Missing ${label} for chain ${chainId}: ${artifactPath}.`);
  }

  return {
    manifestPath,
    zkeyPath,
  };
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
  assertAllowedCommandKeys(args, "install-zk-evm", new Set(["command", "positional"]), "no options");
}

function assertUninstallZkEvmArgs(args) {
  assertAllowedCommandKeys(args, "uninstall-zk-evm", new Set(["command", "positional"]), "no options");
}

function assertMintNotesArgs(args) {
  requireArg(args.amounts, "--amounts");
  assertWalletPasswordArgs(args, "mint-notes", ["amounts"], "--wallet, --password, --network, and --amounts");
  parseMintTokenAmountVector(args.amounts);
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
  const amounts = parseTokenAmountVector(args.amounts);
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
  requireNetworkName(args);
  requireAlchemyApiKeyForPublicNetwork(args, "create-channel");
  requireArg(args.privateKey, "--private-key");
  assertAllowedCommandKeys(
    args,
    "create-channel",
    new Set(["command", "positional", "channelName", "network", "alchemyApiKey", "privateKey"]),
    "--channel-name, --network, --private-key, and --alchemy-api-key on public networks",
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

function assertGetMyAddressArgs(args) {
  assertWalletPasswordArgs(args, "get-my-address", [], "--wallet, --password, and --network");
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
    normalizeStateSnapshot(context.currentSnapshot),
  );
}

function printHelp() {
  console.log(`
Commands:
  install-zk-evm
      Install the local Tokamak zk-EVM toolchain

  uninstall-zk-evm
      Remove the checked-out Tokamak zk-EVM worktree contents

  create-channel --channel-name <NAME> --network <NAME> --private-key <HEX> --alchemy-api-key <KEY>
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
      Bind a wallet to a channel-specific L2 identity

  get-my-address --wallet <NAME> --password <PASSWORD> --network <NAME>
      Check whether a wallet matches the on-chain channel registration

  deposit-channel --wallet <NAME> --password <PASSWORD> --network <NAME> --amount <TOKENS>
      Move bridged funds into the channel L2 accounting balance

  withdraw-channel --wallet <NAME> --password <PASSWORD> --network <NAME> --amount <TOKENS>
      Move channel L2 balance back into the shared bridge vault

  get-my-channel-fund --wallet <NAME> --password <PASSWORD> --network <NAME>
      Read the current channel L2 accounting balance

  mint-notes --wallet <NAME> --password <PASSWORD> --network <NAME> --amounts <A,B,...>
      Mint private-state notes from the wallet's channel balance

  transfer-notes --wallet <NAME> --password <PASSWORD> --network <NAME> --note-ids <ID,ID,...> --recipients <ADDR,ADDR,...> --amounts <A,B,...>
      Spend input notes into supported private transfer outputs

  redeem-notes --wallet <NAME> --password <PASSWORD> --network <NAME> --note-ids <ID,ID,...>
      Redeem one or two tracked notes back into the wallet's channel balance

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
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
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
      JSON.stringify(canonicalizeJsonValue(serializeBigInts(value))),
    ),
  );
}

function writeJsonIfChanged(filePath, value) {
  const nextHash = hashJsonValue(value);
  if (fs.existsSync(filePath) && hashJsonValue(readJson(filePath)) === nextHash) {
    return false;
  }
  writeJson(filePath, value);
  return true;
}

function loadExistingWorkspaceArtifacts(workspaceDir) {
  const currentDir = channelWorkspaceCurrentPath(workspaceDir);
  const stateSnapshot = readJsonIfExists(path.join(currentDir, "state_snapshot.json"));
  return {
    workspace: readJsonIfExists(channelWorkspaceConfigPath(workspaceDir)),
    stateSnapshot: stateSnapshot ? normalizeStateSnapshot(stateSnapshot) : null,
    blockInfo: readJsonIfExists(path.join(currentDir, "block_info.json")),
    contractCodes: readJsonIfExists(path.join(currentDir, "contract_codes.json")),
  };
}

function canReuseLocalWorkspaceSnapshot({ existingArtifacts, currentRootVectorHash, managedStorageAddresses }) {
  const localSnapshot = existingArtifacts?.stateSnapshot;
  if (!localSnapshot) {
    return false;
  }
  return normalizeBytes32Hex(hashRootVector(localSnapshot.stateRoots)) === normalizeBytes32Hex(currentRootVectorHash)
    && hashJsonValue(normalizedAddressVector(localSnapshot.storageAddresses))
      === hashJsonValue(normalizedAddressVector(managedStorageAddresses));
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
  const walletMetadata = loadWalletMetadata(requireWalletName(args), requireNetworkName(args));
  return {
    provider: new JsonRpcProvider(walletMetadata.rpcUrl),
  };
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
