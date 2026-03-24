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
  createTokamakL2Common,
  createTokamakL2StateManagerFromStateSnapshot,
  createTokamakL2Tx,
  deriveL2KeysFromSignature,
  fromEdwardsToAddress,
  poseidon,
} from "tokamak-l2js";
import {
  addHexPrefix,
  bytesToBigInt,
  bytesToHex,
  createAddressFromString,
  hexToBytes,
} from "@ethereumjs/util";
import { deriveRpcUrl, resolveCliNetwork } from "../../script/network-config.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../..");
const appsRoot = path.resolve(projectRoot, "apps");
const appRoot = path.resolve(projectRoot, "apps/private-state");
const deployRoot = path.resolve(appRoot, "deploy");
const bridgeRoot = path.resolve(projectRoot, "bridge");
const functionsRoot = path.resolve(__dirname, "functions");
const channelWorkspacesRoot = path.resolve(__dirname, "workspaces");
const walletsRoot = path.resolve(__dirname, "wallets");
const defaultEnvFile = path.resolve(appsRoot, ".env");
const tokamakRoot = path.resolve(projectRoot, "submodules", "Tokamak-zk-EVM");
const tokamakCliPath = path.resolve(tokamakRoot, "tokamak-cli");

const abiCoder = AbiCoder.defaultAbiCoder();
const erc20MetadataAbi = [
  "function decimals() view returns (uint8)",
];
const TOKAMAK_APUB_BLOCK_LENGTH = 78;
const TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT = 4;
const WALLET_ENCRYPTION_VERSION = 1;
const WALLET_ENCRYPTION_ALGORITHM = "aes-256-gcm";
const L2_PASSWORD_SIGNING_DOMAIN = "Tokamak private-state L2 password binding";
const INITIAL_ZERO_ROOT =
  "0x0ce3a78a0131c84050bbe2205642f9e176ffe98488dbddb19336b987420f3bde";
const BLS12_381_SCALAR_FIELD_MODULUS =
  BigInt("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");

async function main() {
  const args = parseArgs(process.argv.slice(2));
  assertNoLegacyBridgeOverrideFlags(args);
  assertNoLegacyWalletFlags(args);
  assertNoLegacyL2IdentityFlags(args);
  assertNoLegacyCommandNames(args);

  if (args.help || !args.command) {
    printHelp();
    return;
  }

  if (args.command === "list-functions") {
    printJson(readJson(path.resolve(functionsRoot, "index.json")));
    return;
  }

  if (args.command === "show-template") {
    requireFunctionName(args);
    printJson(loadTemplate(args.functionName));
    return;
  }

  if (args.command === "workspace-list") {
    printJson(listChannelWorkspaces());
    return;
  }

  if (args.command === "channel-workspace-list") {
    printJson(listChannelWorkspaces());
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
    case "channel-create":
      await handleChannelCreate({ args, env, network, provider });
      return;
    case "recover-workspace":
      await handleWorkspaceInit({ args, network, provider });
      return;
    case "workspace-show":
    case "channel-workspace-show":
      handleWorkspaceShow(args);
      return;
    case "wallet-show":
      await handleWalletShow({ args, env, provider });
      return;
    case "deposit-bridge":
      await handleRegisterAndFund({ args, env, network, provider });
      return;
    case "fund-l1":
      await handleFundL1({ args, env, network, provider });
      return;
    case "deposit-channel":
      await handleGrothVaultMove({ args, env, network, provider, direction: "deposit" });
      return;
    case "withdraw":
      await handleGrothVaultMove({ args, env, network, provider, direction: "withdraw" });
      return;
    case "claim":
      await handleClaim({ args, env, network, provider });
      return;
    case "bridge-send":
      await handleBridgeSend({ args, env, network, provider });
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
  if (args.command === "user-workspace-list" || args.command === "user-workspace-show") {
    throw new Error("Legacy user-workspace commands are no longer supported.");
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

function assertNoLegacyCommandNames(args) {
  if (args.command === "register-and-fund") {
    throw new Error("register-and-fund is no longer supported. Use deposit-bridge instead.");
  }
  if (args.command === "deposit") {
    throw new Error("deposit is no longer supported. Use deposit-channel instead.");
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
    action: "channel-create",
    channelName,
    channelId: channelId.toString(),
    dappId,
    leader,
    asset: channelInfo.asset,
    manager: channelInfo.manager,
    tokenVault: channelInfo.vault,
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
    tokenVault: workspace.tokenVault,
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

  if (persist && fs.existsSync(workspaceDir)) {
    if (!force) {
      throw new Error(`Workspace already exists: ${workspaceDir}. Use --force to overwrite.`);
    }
    fs.rmSync(workspaceDir, { recursive: true, force: true });
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
    channelId: Number(channelId),
    channelName,
    dappId: Number(channelInfo.dappId),
    genesisBlockNumber,
    bridgeCore: getAddress(bridgeDeployment.bridgeCore),
    channelManager: getAddress(channelInfo.manager),
    tokenVault: getAddress(channelInfo.vault),
    canonicalAsset,
    canonicalAssetDecimals,
    controller: controllerAddress,
    l2AccountingVault: l2AccountingVaultAddress,
    aPubBlockHash: normalizeBytes32Hex(channelInfo.aPubBlockHash),
    managedStorageAddresses,
    liquidBalancesSlot: liquidBalancesSlot.toString(),
  };

  if (persist) {
    ensureDir(workspaceDir);
    ensureDir(path.join(workspaceDir, "current"));
    ensureDir(path.join(workspaceDir, "operations"));

    writeJson(path.join(workspaceDir, "workspace.json"), workspace);
    writeJson(path.join(workspaceDir, "current", "state_snapshot.json"), currentSnapshot);
    writeJson(path.join(workspaceDir, "current", "state_snapshot.normalized.json"), normalizeStateSnapshot(currentSnapshot));
    writeJson(path.join(workspaceDir, "current", "block_info.json"), blockInfo);
    writeJson(path.join(workspaceDir, "current", "contract_codes.json"), contractCodes);
  }

  return {
    workspaceDir,
    workspace,
    currentSnapshot,
    blockInfo,
    contractCodes,
  };
}

function handleWorkspaceShow(args) {
  const workspaceName = requireWorkspaceName(args);
  const workspaceDir = channelWorkspacePath(workspaceName);
  printJson({
    workspace: readJson(path.join(workspaceDir, "workspace.json")),
    currentSnapshot: readJson(path.join(workspaceDir, "current", "state_snapshot.json")),
  });
}

async function handleWalletShow({ args, env, provider }) {
  const walletName = requireWalletName(args);
  const walletContext = loadWallet(walletName, requireL2Password(args));
  const canonicalAssetDecimals = Number(walletContext.wallet.canonicalAssetDecimals);
  const spendSelection = args.amount
    ? selectSpendableNotes(walletContext.wallet, parseTokenAmount(args.amount, canonicalAssetDecimals))
    : null;
  printJson({
    wallet: sanitizeWalletForOutput(walletContext.wallet),
    spendSelection,
  });
}

async function handleRegisterAndFund({ args, env, network, provider }) {
  if (args.wallet !== undefined) {
    throw new Error(
      "--wallet is not supported by deposit-bridge. Channel wallets are created or refreshed by deposit-channel and bridge-send.",
    );
  }
  const signer = requireL1Signer(args, env, provider);
  const l2Identity = await deriveParticipantIdentity({
    password: requireL2Password(args),
    signer,
  });
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId: network.chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
  const storageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, bridgeVaultContext.liquidBalancesSlot);
  const tokenVault = new Contract(
    bridgeVaultContext.tokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.tokenVault.abi,
    signer,
  );
  const asset = new Contract(
    bridgeVaultContext.canonicalAsset,
    bridgeVaultContext.bridgeAbiManifest.contracts.erc20.abi,
    signer,
  );
  const approveReceipt = await waitForReceipt(await asset.approve(bridgeVaultContext.tokenVaultAddress, amount));
  const registrationReceipt = await waitForReceipt(await tokenVault.registerAndFund(storageKey, amount));
  const registration = await tokenVault.getRegistration(signer.address);

  printJson({
    action: "deposit-bridge",
    amountInput,
    amountBaseUnits: amount.toString(),
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    leafIndex: registration.leafIndex.toString(),
    tokenVault: bridgeVaultContext.tokenVaultAddress,
    approveReceipt: sanitizeReceipt(approveReceipt),
    registrationReceipt: sanitizeReceipt(registrationReceipt),
  });
}

async function handleFundL1({ args, env, network, provider }) {
  const wallet = args.wallet ? loadWallet(requireWalletName(args), requireL2Password(args)) : null;
  const signer = resolveWalletBackedSigner({ args, env, provider, walletContext: wallet });
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId: network.chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
  const tokenVault = new Contract(
    bridgeVaultContext.tokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.tokenVault.abi,
    signer,
  );
  const asset = new Contract(
    bridgeVaultContext.canonicalAsset,
    bridgeVaultContext.bridgeAbiManifest.contracts.erc20.abi,
    signer,
  );
  const approveReceipt = await waitForReceipt(await asset.approve(bridgeVaultContext.tokenVaultAddress, amount));
  const fundReceipt = await waitForReceipt(await tokenVault.fund(amount));

  printJson({
    action: "fund-l1",
    wallet: wallet?.walletName ?? null,
    amountInput,
    amountBaseUnits: amount.toString(),
    tokenVault: bridgeVaultContext.tokenVaultAddress,
    approveReceipt: sanitizeReceipt(approveReceipt),
    fundReceipt: sanitizeReceipt(fundReceipt),
  });
}

async function handleGrothVaultMove({ args, env, network, provider, direction }) {
  const password = requireL2Password(args);
  const walletFromFlag = args.wallet ? loadWallet(requireWalletName(args), password) : null;
  const context = await loadChannelContext({
    args,
    networkName: network.name,
    provider,
    walletContext: walletFromFlag,
  });
  if (walletFromFlag) {
    expect(
      Number(walletFromFlag.wallet.channelId) === Number(context.workspace.channelId),
      "The provided wallet does not belong to the selected channel.",
    );
  }
  await assertWorkspaceAlignedWithChain(context, provider);

  const signer = resolveWalletBackedSigner({ args, env, provider, walletContext: walletFromFlag });
  const l2Identity = walletFromFlag
    ? restoreParticipantIdentityFromWallet(walletFromFlag.wallet)
    : await deriveParticipantIdentity({
      password,
      signer,
    });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(context.workspace.canonicalAssetDecimals));
  const storageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  const tokenVault = new Contract(context.workspace.tokenVault, context.bridgeAbiManifest.contracts.tokenVault.abi, signer);
  const registration = await tokenVault.getRegistration(signer.address);

  expect(registration.exists, `No token-vault registration exists for ${signer.address}.`);
  expect(
    normalizeBytes32Hex(registration.l2TokenVaultKey) === normalizeBytes32Hex(storageKey),
    "The derived L2 storage key does not match the registered token-vault key.",
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

  const operationName = direction === "deposit" ? "deposit-channel" : "withdraw";
  const walletContext = ensureWallet({
    args,
    channelContext: context,
    signerAddress: signer.address,
    signerPrivateKey: signer.privateKey,
    l2Identity,
    walletPassword: password,
    storageKey,
    leafIndex: registration.leafIndex,
  });
  const operationDir =
    createWalletOperationDir(walletContext.walletName, `${operationName}-${shortAddress(signer.address)}`);

  const transition = await buildGrothTransition({
    operationDir,
    workspace: context.workspace,
    stateManager,
    vaultAddress: context.workspace.l2AccountingVault,
    keyHex,
    nextValue,
  });

  const receipt = await waitForReceipt(
    await tokenVault[direction](BigInt(context.workspace.channelId), transition.proof, transition.update),
  );
  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  expect(
    onchainRootVectorHash === normalizeBytes32Hex(hashRootVector(transition.nextSnapshot.stateRoots)),
    `On-chain roots do not match the ${direction} post-state roots.`,
  );

  writeJson(path.join(operationDir, `${operationName}-receipt.json`), sanitizeReceipt(receipt));
  writeJson(path.join(operationDir, "state_snapshot.json"), transition.nextSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), normalizeStateSnapshot(transition.nextSnapshot));
  writeJson(path.join(operationDir, "wallet.json"), walletContext.wallet);
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

async function handleClaim({ args, env, provider }) {
  const wallet = args.wallet ? loadWallet(requireWalletName(args), requireL2Password(args)) : null;
  const signer = resolveWalletBackedSigner({ args, env, provider, walletContext: wallet });
  const chainId = Number((await provider.getNetwork()).chainId);
  const bridgeVaultContext = await loadBridgeVaultContext({ provider, chainId });
  const amountInput = requireArg(args.amount, "--amount");
  const amount = parseTokenAmount(amountInput, Number(bridgeVaultContext.canonicalAssetDecimals));
  const tokenVault = new Contract(
    bridgeVaultContext.tokenVaultAddress,
    bridgeVaultContext.bridgeAbiManifest.contracts.tokenVault.abi,
    signer,
  );
  const receipt = await waitForReceipt(await tokenVault.claimToWallet(amount));

  printJson({
    action: "claim",
    wallet: wallet?.walletName ?? null,
    amountInput,
    amountBaseUnits: amount.toString(),
    tokenVault: bridgeVaultContext.tokenVaultAddress,
    receipt: sanitizeReceipt(receipt),
  });
}

async function handleBridgeSend({ args, env, provider }) {
  requireFunctionName(args);
  const wallet = loadWallet(requireWalletName(args), requireL2Password(args));
  const signer = resolveWalletBackedSigner({ args, env, provider, walletContext: wallet });
  const l2Identity = restoreParticipantIdentityFromWallet(wallet.wallet);
  const context = await loadChannelContext({
    args,
    networkName: null,
    provider,
    walletContext: wallet,
  });
  await assertWorkspaceAlignedWithChain(context, provider);
  expect(
    Number(wallet.wallet.channelId) === Number(context.workspace.channelId),
    "The provided wallet does not belong to the selected channel.",
  );
  expect(
    wallet.wallet.l2Address === l2Identity.l2Address,
    "The provided wallet does not match the derived L2 identity.",
  );
  const templatePayload = buildPayload(args.functionName, args);
  const controllerAbi = readJson(path.resolve(deployRoot, templatePayload.abiFile.replace("../deploy/", "")));
  const fragment = findFunctionFragment(controllerAbi, templatePayload.method);
  const formattedArgs = formatArguments(fragment.inputs ?? [], templatePayload.args ?? []);
  const inputSignature = buildInputSignature(fragment);
  const calldata = runCast(["calldata", inputSignature, ...formattedArgs]).trim();
  const nonce = Number(wallet.wallet.l2Nonce ?? 0);
  const operationDir = createWalletOperationDir(wallet.walletName, `${args.functionName}-${shortAddress(l2Identity.l2Address)}`);
  ensureDir(operationDir);

  if (args.installArg) {
    run(tokamakCliPath, ["--install", args.installArg], { cwd: tokamakRoot });
  }

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

  run(tokamakCliPath, ["--synthesize", "--tokamak-ch-tx", operationDir], { cwd: tokamakRoot });
  run(tokamakCliPath, ["--preprocess"], { cwd: tokamakRoot });
  run(tokamakCliPath, ["--prove"], { cwd: tokamakRoot });
  const bundlePath = path.join(operationDir, `${args.functionName}.zip`);
  run(tokamakCliPath, ["--extract-proof", bundlePath], { cwd: tokamakRoot });
  run(tokamakCliPath, ["--verify", bundlePath], { cwd: tokamakRoot });
  copyTokamakArtifacts(operationDir);

  const rawNextSnapshot = readJson(path.join(operationDir, "resource", "synthesizer", "output", "state_snapshot.json"));
  const nextSnapshot = normalizeStateSnapshot(rawNextSnapshot);
  writeJson(path.join(operationDir, "resource", "synthesizer", "output", "state_snapshot.normalized.json"), nextSnapshot);

  const payload = loadTokamakPayloadFromStep(operationDir);
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
    `On-chain roots do not match the Tokamak post-state roots for ${args.functionName}.`,
  );

  writeJson(path.join(operationDir, "bridge-submit-receipt.json"), sanitizeReceipt(receipt));
  writeJson(path.join(operationDir, "state_snapshot.json"), nextSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), nextSnapshot);

  wallet.wallet.l2Nonce = nonce + 1;
  applyNoteLifecycleToWallet(wallet, extractNoteLifecycle(args.functionName, templatePayload), args.functionName, receipt.hash);
  context.currentSnapshot = nextSnapshot;
  persistWallet(wallet);
  persistCurrentState(context);
  sealWalletOperationDir(operationDir, wallet.walletPassword);

  printJson({
    action: "bridge-send",
    workspace: context.workspaceName,
    wallet: wallet.walletName,
    functionName: args.functionName,
    operationDir,
    l1Submitter: signer.address,
    l2Address: l2Identity.l2Address,
    nonce,
    updatedRoots: context.currentSnapshot.stateRoots,
  });
}

function defaultWalletName(channelName, l2Address) {
  return `${channelName}-${l2Address}`;
}

function ensureWallet({
  args,
  channelContext,
  signerAddress,
  signerPrivateKey,
  l2Identity,
  walletPassword,
  storageKey,
  leafIndex,
}) {
  const walletName = args.wallet ?? defaultWalletName(channelContext.workspace.channelName, l2Identity.l2Address);
  const walletDir = walletPath(walletName);
  let wallet;
  if (walletConfigExists(walletDir)) {
    wallet = normalizeWallet(readEncryptedWalletJson(walletConfigPath(walletDir), walletPassword));
    expect(
      Number(wallet.channelId) === Number(channelContext.workspace.channelId),
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
      tokenVault: channelContext.workspace.tokenVault,
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
      l2StorageKey: storageKey,
      leafIndex: leafIndex?.toString() ?? null,
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
  wallet.tokenVault = channelContext.workspace.tokenVault;
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
  wallet.l2StorageKey = storageKey;
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
  };
}

function compareNotesByValueDesc(left, right) {
  const leftValue = BigInt(left.value);
  const rightValue = BigInt(right.value);
  if (leftValue === rightValue) {
    return left.commitment.localeCompare(right.commitment);
  }
  return leftValue > rightValue ? -1 : 1;
}

function buildTrackedNote(note, sourceFunction, sourceTxHash) {
  const normalizedNote = normalizePlaintextNote(note);
  return {
    ...normalizedNote,
    commitment: normalizeBytes32Hex(computeNoteCommitment(normalizedNote)),
    nullifier: normalizeBytes32Hex(computeNullifier(normalizedNote)),
    status: "unused",
    sourceFunction,
    sourceTxHash,
  };
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

function extractNoteLifecycle(functionName, templatePayload) {
  if (functionName.startsWith("mintNotes")) {
    return {
      inputs: [],
      outputs: templatePayload.args[0] ?? [],
    };
  }
  if (functionName.startsWith("transferNotes")) {
    return {
      inputs: templatePayload.args[0] ?? [],
      outputs: templatePayload.args[1] ?? [],
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

function applyNoteLifecycleToWallet(walletContext, lifecycle, sourceFunction, sourceTxHash) {
  for (const inputNote of lifecycle.inputs) {
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
    };
  }

  for (const outputNote of lifecycle.outputs) {
    const trackedOutput = buildTrackedNote(outputNote, sourceFunction, sourceTxHash);
    if (trackedOutput.owner !== walletContext.wallet.l2Address) {
      continue;
    }
    walletContext.wallet.notes.unused[trackedOutput.commitment] = trackedOutput;
  }

  walletContext.wallet = normalizeWallet(walletContext.wallet);
  persistWallet(walletContext);
}

function selectSpendableNotes(workspace, requestedAmount) {
  const target = BigInt(requestedAmount);
  if (target <= 0n) {
    return {
      requestedAmount: target.toString(),
      selectedAmount: "0",
      noteCommitments: [],
      sufficient: true,
    };
  }

  const selectedCommitments = [];
  let selectedAmount = 0n;
  for (const commitment of workspace.notes.unusedOrder) {
    const note = workspace.notes.unused[commitment];
    if (!note) {
      continue;
    }
    selectedCommitments.push(commitment);
    selectedAmount += BigInt(note.value);
    if (selectedAmount >= target) {
      break;
    }
  }

  return {
    requestedAmount: target.toString(),
    selectedAmount: selectedAmount.toString(),
    noteCommitments: selectedCommitments,
    sufficient: selectedAmount >= target,
  };
}

async function loadWorkspaceContext(workspaceName, provider) {
  const normalizedWorkspaceName = requireWorkspaceName({ workspace: workspaceName });
  const workspaceDir = channelWorkspacePath(normalizedWorkspaceName);
  const workspace = readJson(path.join(workspaceDir, "workspace.json"));
  const bridgeDeploymentPath = defaultBridgeDeploymentPath(workspace.chainId);
  const bridgeAbiManifestPath = defaultBridgeAbiManifestPath(workspace.chainId);
  const bridgeDeployment = readJson(bridgeDeploymentPath);
  const bridgeAbiManifest = loadBridgeAbiManifest(bridgeAbiManifestPath);
  const currentSnapshot = normalizeStateSnapshot(readJson(path.join(workspaceDir, "current", "state_snapshot.json")));
  const blockInfo = readJson(path.join(workspaceDir, "current", "block_info.json"));
  const contractCodes = readJson(path.join(workspaceDir, "current", "contract_codes.json"));
  const channelManager = new Contract(workspace.channelManager, bridgeAbiManifest.contracts.channelManager.abi, provider);
  const tokenVault = new Contract(workspace.tokenVault, bridgeAbiManifest.contracts.tokenVault.abi, provider);

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
    tokenVault,
  };
}

async function loadChannelContext({ args, networkName, provider, walletContext = null }) {
  const explicitWorkspaceName = args.workspace ? requireWorkspaceName(args) : null;
  if (explicitWorkspaceName) {
    const explicitWorkspaceDir = channelWorkspacePath(explicitWorkspaceName);
    if (fs.existsSync(path.join(explicitWorkspaceDir, "workspace.json"))) {
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
    tokenVault: new Contract(
      initialized.workspace.tokenVault,
      bridgeResources.bridgeAbiManifest.contracts.tokenVault.abi,
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
  const wallet = normalizeWallet(readEncryptedWalletJson(walletConfigPath(walletDir), walletPassword));
  const restoredIdentity = restoreParticipantIdentityFromWallet(wallet);
  expect(
    wallet.l2Address === restoredIdentity.l2Address,
    `Wallet ${normalizedWalletName} is internally inconsistent: stored keys do not match the stored L2 address.`,
  );
  return {
    walletName: normalizedWalletName,
    walletDir,
    wallet,
    walletPassword,
  };
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

function resolveWalletBackedSigner({ args, env, provider, walletContext }) {
  if (args.privateKey !== undefined || env.APPS_DEPLOYER_PRIVATE_KEY) {
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
    return new Wallet(normalizePrivateKey(walletContext.wallet.l1PrivateKey), provider);
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

async function loadBridgeVaultContext({ provider, chainId }) {
  const bridgeResources = loadBridgeResources({ chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    provider,
  );
  const tokenVaultAddress = getAddress(
    bridgeResources.bridgeDeployment.tokenVault ?? await bridgeCore.tokenVault(),
  );
  const canonicalAsset = getAddress(await bridgeCore.canonicalAsset());
  const canonicalAssetDecimals = await fetchTokenDecimals(provider, canonicalAsset);
  const storageLayoutManifestPath = path.resolve(deployRoot, `storage-layout.${chainId}.latest.json`);
  const storageLayoutManifest = readJson(storageLayoutManifestPath);
  const liquidBalancesSlot = BigInt(findStorageSlot(storageLayoutManifest, "L2AccountingVault", "liquidBalances"));

  return {
    ...bridgeResources,
    bridgeCore,
    tokenVaultAddress,
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

  await stateManager.putStorage(vaultAddressObj, hexToBytes(keyHex), hexToBytes(bigintToHex32(nextValue)));
  const updatedRoot = stateManager.merkleTrees.getRoot(vaultAddressObj);

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
      currentRootVector: normalizeStateSnapshot(await stateManager.captureStateSnapshot()).stateRoots,
      updatedRoot: bytes32FromBigInt(updatedRoot),
      currentUserKey: bytes32FromHex(keyHex),
      currentUserValue: currentValue,
      updatedUserKey: bytes32FromHex(keyHex),
      updatedUserValue: nextValue,
    },
    nextSnapshot: normalizeStateSnapshot(await stateManager.captureStateSnapshot()),
  };
}

function buildPayload(functionName, args) {
  requireFunctionName(args);
  const template = args.templateFile
    ? readJson(resolveInputPath(args.templateFile))
    : loadTemplate(functionName);

  if (args.argsFile) {
    template.args = readJson(resolveInputPath(args.argsFile));
  }
  return template;
}

function loadTemplate(functionName) {
  return readJson(path.resolve(functionsRoot, functionName, "calldata.json"));
}

function findFunctionFragment(abi, methodName) {
  const fragment = abi.find((entry) => entry.type === "function" && entry.name === methodName);
  if (!fragment) {
    throw new Error(`Method ${methodName} was not found in the callable ABI.`);
  }
  return fragment;
}

function buildInputSignature(fragment) {
  const inputTypes = (fragment.inputs ?? []).map(formatCanonicalType).join(",");
  return `${fragment.name}(${inputTypes})`;
}

function formatCanonicalType(parameter) {
  const type = parameter.type;
  if (!type.startsWith("tuple")) {
    return type;
  }

  const suffix = type.slice("tuple".length);
  const componentTypes = (parameter.components ?? []).map(formatCanonicalType).join(",");
  return `(${componentTypes})${suffix}`;
}

function formatArguments(inputs, values) {
  if (inputs.length !== values.length) {
    throw new Error(`Expected ${inputs.length} arguments but received ${values.length}.`);
  }

  return inputs.map((input, index) => formatArgument(input, values[index]));
}

function formatArgument(parameter, value) {
  const { baseType, arraySuffix } = splitType(parameter.type);

  if (arraySuffix.length > 0) {
    if (!Array.isArray(value)) {
      throw new Error(`Expected array for ${parameter.name || parameter.type}.`);
    }

    const nestedParameter = {
      ...parameter,
      type: `${baseType}${arraySuffix.slice(1).join("")}`,
    };
    return `[${value.map((item) => formatArgument(nestedParameter, item)).join(",")}]`;
  }

  if (baseType === "tuple") {
    if (Array.isArray(value)) {
      return `(${value.map((item, index) => formatArgument(parameter.components[index], item)).join(",")})`;
    }

    if (!value || typeof value !== "object") {
      throw new Error(`Expected object or array for tuple ${parameter.name || parameter.type}.`);
    }

    return `(${(parameter.components ?? [])
      .map((component, index) => formatArgument(component, value[component.name] ?? value[index]))
      .join(",")})`;
  }

  return formatScalar(baseType, value);
}

function splitType(type) {
  const parts = type.match(/\[[^\]]*\]/g) ?? [];
  return {
    baseType: type.replace(/\[[^\]]*\]/g, ""),
    arraySuffix: parts,
  };
}

function formatScalar(type, value) {
  if (value === null || value === undefined) {
    throw new Error(`Missing value for ${type}.`);
  }

  if (type === "bool") {
    return value ? "true" : "false";
  }

  if (type === "string") {
    return String(value);
  }

  return String(value);
}

function run(command, args, { cwd = projectRoot, env = process.env } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}.`);
  }
}

function runCast(args) {
  const result = spawnSync("cast", args, {
    cwd: projectRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(`cast ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}.`);
  }
  return result.stdout;
}

function copyTokamakArtifacts(operationDir) {
  const resourceRoot = path.join(operationDir, "resource");
  fs.rmSync(resourceRoot, { recursive: true, force: true });
  fs.cpSync(path.join(tokamakRoot, "dist", "resource"), resourceRoot, { recursive: true });
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
    aPubBlock: instanceJson.a_pub_block.map((value) => BigInt(value)),
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

async function deriveParticipantIdentity({ password, signer }) {
  const seedSignature = await signer.signMessage(buildL2PasswordSigningMessage(password));
  const keySet = deriveL2KeysFromSignature(seedSignature);
  const l2Address = getAddress(fromEdwardsToAddress(keySet.publicKey).toString());
  return {
    seedSignature,
    l2PrivateKey: keySet.privateKey,
    l2PublicKey: keySet.publicKey,
    l2Address,
  };
}

function buildL2PasswordSigningMessage(password) {
  return `${L2_PASSWORD_SIGNING_DOMAIN}\n${String(password)}`;
}

function deriveLiquidBalanceStorageKey(l2Address, slot) {
  const encoded = abiCoder.encode(["address", "uint256"], [l2Address, BigInt(slot)]);
  return bytesToHex(poseidon(hexToBytes(encoded)));
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

function deriveChannelIdFromName(channelName) {
  return BigInt(keccak256(ethers.toUtf8Bytes(channelName)));
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
    prevRanDao: block.prevRandao ?? block.difficulty ?? "0x0",
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
    channelId: Number(channelId),
    stateRoots: managedStorageAddresses.map(() => normalizeBytes32Hex(INITIAL_ZERO_ROOT)),
    storageAddresses: managedStorageAddresses,
    storageEntries: managedStorageAddresses.map(() => []),
  };

  const tokenVault = new Contract(channelInfo.vault, bridgeAbiManifest.contracts.tokenVault.abi, provider);
  const rootEvents = await channelManager.queryFilter(channelManager.filters.CurrentRootVectorObserved(), genesisBlockNumber);
  const channelStorageWriteEvents =
    await channelManager.queryFilter(channelManager.filters.StorageWriteObserved(), genesisBlockNumber);
  const vaultStorageWriteEvents =
    await tokenVault.queryFilter(tokenVault.filters.StorageWriteObserved(), genesisBlockNumber);

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
    expect(
      normalizeBytes32Hex(hashRootVector(currentSnapshot.stateRoots)) === emittedRootVectorHash,
      `CurrentRootVectorObserved hash mismatch at tx ${rootEvent.transactionHash}.`,
    );
    expect(
      JSON.stringify(currentSnapshot.stateRoots) === JSON.stringify(emittedRootVector),
      `CurrentRootVectorObserved root vector mismatch at tx ${rootEvent.transactionHash}.`,
    );

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
  const requiredContracts = ["bridgeCore", "channelManager", "tokenVault", "erc20"];
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
  if (parsed.command === "show-template") {
    parsed.functionName = parsed.positional[1];
  } else if (parsed.command === "bridge-send") {
    parsed.functionName = parsed.positional[1];
  }
  return parsed;
}

function toCamelCase(value) {
  return value.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
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

function toBigIntStrict(value) {
  try {
    return BigInt(value);
  } catch {
    throw new Error(`Invalid integer value: ${value}`);
  }
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

function requireFunctionName(args) {
  if (!args.functionName) {
    throw new Error("Missing function name.");
  }
}

function requireL1Signer(args, env, provider) {
  const privateKey = args.privateKey ?? env.APPS_DEPLOYER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("Missing --private-key and APPS_DEPLOYER_PRIVATE_KEY.");
  }
  return new Wallet(normalizePrivateKey(privateKey), provider);
}

function channelWorkspacePath(name) {
  return path.join(channelWorkspacesRoot, slugify(name));
}

function walletPath(name) {
  return path.join(walletsRoot, slugify(name));
}

function walletConfigPath(walletDir) {
  return path.join(walletDir, "wallet.json");
}

function walletConfigExists(walletDir) {
  return fs.existsSync(walletConfigPath(walletDir));
}

function listChannelWorkspaces() {
  if (!fs.existsSync(channelWorkspacesRoot)) {
    return [];
  }
  return fs.readdirSync(channelWorkspacesRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const configPath = path.join(channelWorkspacesRoot, entry.name, "workspace.json");
      return fs.existsSync(configPath)
        ? readJson(configPath)
        : { name: entry.name };
    });
}

function slugify(value) {
  return String(value)
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}

function createOperationDir(workspaceName, suffix) {
  const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const operationDir = path.join(channelWorkspacePath(workspaceName), "operations", `${timestamp}-${slugify(suffix)}`);
  ensureDir(operationDir);
  return operationDir;
}

function createWalletOperationDir(walletName, suffix) {
  const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const operationDir = path.join(walletPath(walletName), "operations", `${timestamp}-${slugify(suffix)}`);
  ensureDir(operationDir);
  return operationDir;
}

function persistWorkspace(context) {
  writeJson(path.join(context.workspaceDir, "workspace.json"), context.workspace);
}

function persistWallet(context) {
  writeEncryptedWalletJson(path.join(context.walletDir, "wallet.json"), context.wallet, context.walletPassword);
}

function persistCurrentState(context) {
  if (!context.persistChannelWorkspace || !context.workspaceDir) {
    return;
  }
  writeJson(path.join(context.workspaceDir, "current", "state_snapshot.json"), context.currentSnapshot);
  writeJson(
    path.join(context.workspaceDir, "current", "state_snapshot.normalized.json"),
    normalizeStateSnapshot(context.currentSnapshot),
  );
}

function printHelp() {
  console.log(`private-state bridge CLI

Usage:
  node apps/private-state/cli/private-state-bridge-cli.mjs list-functions
  node apps/private-state/cli/private-state-bridge-cli.mjs show-template <function-name>
  node apps/private-state/cli/private-state-bridge-cli.mjs channel-create --channel-name <name> --dapp-label <label> --private-key <hex> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs channel-workspace-list
  node apps/private-state/cli/private-state-bridge-cli.mjs recover-workspace --channel-name <name> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs channel-workspace-show --workspace <name>
  node apps/private-state/cli/private-state-bridge-cli.mjs wallet-show --wallet <name> --password <string> [--amount <tokens>]
  node apps/private-state/cli/private-state-bridge-cli.mjs deposit-bridge --private-key <hex> --password <string> --amount <tokens> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs fund-l1 [--private-key <hex>] --password <string> --amount <tokens> [--wallet <name>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs deposit-channel (--channel-name <name> | --workspace <channel-workspace>) [--private-key <hex>] --password <string> --amount <tokens> [--wallet <name>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs withdraw (--channel-name <name> | --workspace <channel-workspace> | --wallet <name>) [--private-key <hex>] --password <string> --amount <tokens> [--wallet <name>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs claim [--private-key <hex>] --password <string> --amount <tokens> [--wallet <name>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs bridge-send <function-name> (--channel-name <name> | --workspace <channel-workspace> | --wallet <name>) --wallet <name> [--private-key <hex>] --password <string> [--args-file <path>] [--template-file <path>] [options]

Common flags:
  --network <name>         Override APPS_NETWORK from apps/.env. Allowed: mainnet, sepolia
  --rpc-url <url>          Explicit RPC endpoint override
  --alchemy-api-key <key>  Explicit Alchemy key override
  --env-file <path>        Alternate apps/.env location

channel-create options:
  --dapp-label <label>          Registered bridge DApp label to bind to the new channel
  --leader <address>           Optional channel leader. Default: the signing EOA
  --create-workspace           Also initialize a channel workspace after creation using the channel name

recover-workspace options:
  --channel-name <name>        User-provided channel name; channelId is derived as keccak256(bytes(name))
  --block-info-file <path>     Optional block_info.json override; must match the channel genesis block context
  --state-snapshot-file <path> Import an existing non-genesis snapshot
  --force                      Overwrite an existing workspace

bridge-send options:
  --install-arg <value>    Optional tokamak-cli --install input before synthesis/proving
  --args-file <path>       JSON file whose value replaces template.args
  --template-file <path>   Full JSON template override

Notes:
  - recover-workspace derives block_info.json from the channel genesis block and reconstructs the latest channel state from bridge events.
  - recover-workspace always writes into apps/private-state/cli/workspaces/<channel-name>/.
  - Channel workspaces are optional caches for channel snapshots.
  - Wallets are the mandatory local state for note-carrying users. They track L2 identity, nonce, and used/unused notes.
  - deposit-bridge signs a domain-separated password message with the provided L1 private key and uses that signature as the seed for L2 key derivation.
  - deposit-bridge registers and funds the shared bridge-level L1 token vault. It does not create or refresh a channel wallet.
  - deposit-channel is the first command that creates or refreshes a channel wallet from --private-key plus --password.
  - Once a wallet exists, wallet-show, fund-l1, claim, and bridge-send can recover the stored signer and L2 identity from the encrypted wallet using --password alone.
  - deposit-channel and withdraw can also use --password alone when a matching --wallet is present. Without a wallet, they still need --private-key to derive a fresh L2 identity.
  - The CLI only updates the active wallet. It does not auto-refresh other wallets because their encrypted data cannot be decrypted without their own --password.
  - Every --amount value is interpreted as a human token amount using the canonical Tokamak Network Token decimals.
  - The CLI auto-selects bridge deployment and ABI files from the chosen network's chain ID.
  - wallet-show requires an existing --wallet plus the matching --password.
  - Channel workspace operations are stored under:
      apps/private-state/cli/workspaces/<workspace>/operations/
  - Wallet operations are stored under:
      apps/private-state/cli/wallets/<wallet>/operations/
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

function sanitizeWalletForOutput(wallet) {
  const { l1PrivateKey: _l1PrivateKey, l2PrivateKey: _l2PrivateKey, l2PublicKey: _l2PublicKey, ...rest } = wallet;
  return rest;
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
  console.log(JSON.stringify(value, null, 2));
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
