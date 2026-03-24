#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
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
const userWorkspacesRoot = path.resolve(__dirname, "user-workspaces");
const defaultEnvFile = path.resolve(appsRoot, ".env");
const tokamakRoot = path.resolve(projectRoot, "submodules", "Tokamak-zk-EVM");
const tokamakCliPath = path.resolve(tokamakRoot, "tokamak-cli");

const abiCoder = AbiCoder.defaultAbiCoder();
const TOKAMAK_APUB_BLOCK_LENGTH = 78;
const TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT = 4;
const INITIAL_ZERO_ROOT =
  "0x0ce3a78a0131c84050bbe2205642f9e176ffe98488dbddb19336b987420f3bde";
const BLS12_381_SCALAR_FIELD_MODULUS =
  BigInt("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");

async function main() {
  const args = parseArgs(process.argv.slice(2));
  assertNoLegacyBridgeOverrideFlags(args);

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

  if (args.command === "user-workspace-list") {
    printJson(listUserWorkspaces());
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
    case "workspace-init":
    case "channel-workspace-init":
      await handleWorkspaceInit({ args, network, provider });
      return;
    case "workspace-show":
    case "channel-workspace-show":
      handleWorkspaceShow(args);
      return;
    case "user-workspace-show":
      handleUserWorkspaceShow(args);
      return;
    case "register-and-fund":
      await handleRegisterAndFund({ args, env, network, provider });
      return;
    case "fund-l1":
      await handleFundL1({ args, env, network, provider });
      return;
    case "deposit":
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

async function handleChannelCreate({ args, env, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const dappId = Number(requireArg(args.dappId, "--dapp-id"));
  const asset = getAddress(requireArg(args.asset, "--asset"));
  const signer = requireL1Signer(args, env, provider);
  const leader = getAddress(args.leader ?? signer.address);
  const createWorkspace = parseBooleanFlag(args.createWorkspace);
  const workspaceName = args.workspace ? requireWorkspaceName(args) : channelName;

  const bridgeResources = loadBridgeResources({ chainId: network.chainId });
  const bridgeCore = new Contract(
    bridgeResources.bridgeDeployment.bridgeCore,
    bridgeResources.bridgeAbiManifest.contracts.bridgeCore.abi,
    signer,
  );

  const receipt = await waitForReceipt(await bridgeCore.createChannel(channelName, dappId, leader, asset));
  const channelId = BigInt(await bridgeCore.deriveChannelId(channelName));
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
    asset,
    manager: channelInfo.manager,
    tokenVault: channelInfo.vault,
    receipt: sanitizeReceipt(receipt),
    workspace: workspaceResult?.workspaceDir ?? null,
  });
}

async function handleWorkspaceInit({ args, network, provider }) {
  const channelName = requireArg(args.channelName, "--channel-name");
  const workspaceName = args.workspace ? requireWorkspaceName(args) : channelName;
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
    action: "channel-workspace-init",
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
  const channelId = BigInt(await bridgeCore.deriveChannelId(channelName));
  const channelInfo = await bridgeCore.getChannel(channelId);
  if (!channelInfo.exists) {
    throw new Error(`Unknown channel ${channelId.toString()} in bridge core ${bridgeDeployment.bridgeCore}.`);
  }

  const channelManager = new Contract(
    channelInfo.manager,
    bridgeAbiManifest.contracts.channelManager.abi,
    provider,
  );
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
    canonicalAsset: getAddress(channelInfo.asset),
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

function handleUserWorkspaceShow(args) {
  const workspaceName = requireUserWorkspaceName(args);
  const workspaceContext = loadUserWorkspace(workspaceName);
  const spendSelection = args.amount
    ? selectSpendableNotes(workspaceContext.workspace, parseAmountArg(args.amount))
    : null;
  printJson({
    workspace: workspaceContext.workspace,
    spendSelection,
  });
}

async function handleRegisterAndFund({ args, env, network, provider }) {
  const signer = requireL1Signer(args, env, provider);
  const amount = parseAmountArg(requireArg(args.amount, "--amount"));
  const l2Identity = deriveParticipantIdentity(requireArg(args.l2KeySignature, "--l2-key-signature"));
  const context = await loadChannelContext({
    args,
    networkName: network.name,
    provider,
  });
  const storageKey = deriveLiquidBalanceStorageKey(l2Identity.l2Address, context.workspace.liquidBalancesSlot);
  const tokenVault = new Contract(context.workspace.tokenVault, context.bridgeAbiManifest.contracts.tokenVault.abi, signer);
  const asset = new Contract(context.workspace.canonicalAsset, context.bridgeAbiManifest.contracts.erc20.abi, signer);
  const approveReceipt = await waitForReceipt(await asset.approve(context.workspace.tokenVault, amount));
  const registrationReceipt = await waitForReceipt(await tokenVault.registerAndFund(storageKey, amount));
  const registration = await tokenVault.getRegistration(signer.address);
  const userWorkspaceContext = ensureUserWorkspace({
    args,
    channelContext: context,
    signerAddress: signer.address,
    l2Identity,
    storageKey,
    leafIndex: registration.leafIndex,
  });
  const operationDir =
    createUserOperationDir(userWorkspaceContext.workspaceName, `register-and-fund-${shortAddress(signer.address)}`);

  writeJson(path.join(operationDir, "state_snapshot.json"), context.currentSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), normalizeStateSnapshot(context.currentSnapshot));
  writeJson(path.join(operationDir, "approve-receipt.json"), sanitizeReceipt(approveReceipt));
  writeJson(path.join(operationDir, "registration-receipt.json"), sanitizeReceipt(registrationReceipt));
  writeJson(path.join(operationDir, "registration.json"), serializeBigInts(registration));
  writeJson(path.join(operationDir, "user-workspace.json"), userWorkspaceContext.workspace);
  writeJson(path.join(operationDir, "operation.json"), {
    operationName: "register-and-fund",
    actorLabel: signer.address,
    amount: amount.toString(),
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    result: {
      l1Address: signer.address,
      l2Address: l2Identity.l2Address,
      l2StorageKey: storageKey,
      leafIndex: registration.leafIndex.toString(),
    },
  });

  printJson({
    action: "register-and-fund",
    channelName: context.workspace.channelName,
    userWorkspace: userWorkspaceContext.workspaceName,
    operationDir,
    amount: amount.toString(),
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    l2StorageKey: storageKey,
    leafIndex: registration.leafIndex.toString(),
  });
}

async function handleFundL1({ args, env, network, provider }) {
  const signer = requireL1Signer(args, env, provider);
  const amount = parseAmountArg(requireArg(args.amount, "--amount"));
  const userWorkspace = loadUserWorkspace(requireUserWorkspaceName(args));
  const context = await loadChannelContext({
    args,
    networkName: network.name,
    provider,
    userWorkspaceContext: userWorkspace,
  });
  expect(
    Number(userWorkspace.workspace.channelId) === Number(context.workspace.channelId),
    "The provided user workspace does not belong to the selected channel.",
  );
  const tokenVault = new Contract(context.workspace.tokenVault, context.bridgeAbiManifest.contracts.tokenVault.abi, signer);
  const asset = new Contract(context.workspace.canonicalAsset, context.bridgeAbiManifest.contracts.erc20.abi, signer);

  await saveNoStateChangeOperation({
    context,
    operationName: "fund-l1",
    actorLabel: signer.address,
    operationDir: createUserOperationDir(userWorkspace.workspaceName, `fund-l1-${shortAddress(signer.address)}`),
    workspaceLabel: userWorkspace.workspaceName,
    extraMetadata: {
      amount: amount.toString(),
    },
    execute: async (operationDir) => {
      const approveReceipt = await waitForReceipt(
        await asset.approve(context.workspace.tokenVault, amount),
      );
      const fundReceipt = await waitForReceipt(await tokenVault.fund(amount));
      writeJson(path.join(operationDir, "approve-receipt.json"), sanitizeReceipt(approveReceipt));
      writeJson(path.join(operationDir, "fund-receipt.json"), sanitizeReceipt(fundReceipt));
      return { amount: amount.toString() };
    },
  });
}

async function handleGrothVaultMove({ args, env, network, provider, direction }) {
  const userWorkspaceFromFlag = args.userWorkspace ? loadUserWorkspace(requireUserWorkspaceName(args)) : null;
  const context = await loadChannelContext({
    args,
    networkName: network.name,
    provider,
    userWorkspaceContext: userWorkspaceFromFlag,
  });
  if (userWorkspaceFromFlag) {
    expect(
      Number(userWorkspaceFromFlag.workspace.channelId) === Number(context.workspace.channelId),
      "The provided user workspace does not belong to the selected channel.",
    );
  }
  await assertWorkspaceAlignedWithChain(context, provider);

  const signer = requireL1Signer(args, env, provider);
  const amount = parseAmountArg(requireArg(args.amount, "--amount"));
  const l2Identity = deriveParticipantIdentity(requireArg(args.l2KeySignature, "--l2-key-signature"));
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

  const operationName = direction === "deposit" ? "deposit" : "withdraw";
  const userWorkspaceContext = ensureUserWorkspace({
    args,
    channelContext: context,
    signerAddress: signer.address,
    l2Identity,
    storageKey,
    leafIndex: registration.leafIndex,
  });
  const operationDir =
    createUserOperationDir(userWorkspaceContext.workspaceName, `${operationName}-${shortAddress(signer.address)}`);

  const transition = await buildGrothTransition({
    operationDir,
    workspace: context.workspace,
    stateManager,
    vaultAddress: context.workspace.l2AccountingVault,
    keyHex,
    nextValue,
  });

  const receipt = await waitForReceipt(
    await tokenVault[direction](transition.proof, transition.update),
  );
  const onchainRootVectorHash = normalizeBytes32Hex(await context.channelManager.currentRootVectorHash());
  expect(
    onchainRootVectorHash === normalizeBytes32Hex(hashRootVector(transition.nextSnapshot.stateRoots)),
    `On-chain roots do not match the ${direction} post-state roots.`,
  );

  writeJson(path.join(operationDir, `${operationName}-receipt.json`), sanitizeReceipt(receipt));
  writeJson(path.join(operationDir, "state_snapshot.json"), transition.nextSnapshot);
  writeJson(path.join(operationDir, "state_snapshot.normalized.json"), normalizeStateSnapshot(transition.nextSnapshot));
  writeJson(path.join(operationDir, "user-workspace.json"), userWorkspaceContext.workspace);

  context.currentSnapshot = normalizeStateSnapshot(transition.nextSnapshot);
  persistCurrentState(context);

  printJson({
    action: operationName,
    workspace: context.workspaceName,
    userWorkspace: userWorkspaceContext.workspaceName,
    operationDir,
    l1Address: signer.address,
    l2Address: l2Identity.l2Address,
    amount: amount.toString(),
    currentRootVector: transition.update.currentRootVector,
    updatedRoot: transition.update.updatedRoot,
  });
}

async function handleClaim({ args, env, provider }) {
  const userWorkspace = loadUserWorkspace(requireUserWorkspaceName(args));
  const context = await loadChannelContext({
    args,
    networkName: null,
    provider,
    userWorkspaceContext: userWorkspace,
  });
  expect(
    Number(userWorkspace.workspace.channelId) === Number(context.workspace.channelId),
    "The provided user workspace does not belong to the selected channel.",
  );
  const signer = requireL1Signer(args, env, provider);
  const amount = parseAmountArg(requireArg(args.amount, "--amount"));
  const tokenVault = new Contract(context.workspace.tokenVault, context.bridgeAbiManifest.contracts.tokenVault.abi, signer);

  await saveNoStateChangeOperation({
    context,
    operationName: "claim",
    actorLabel: signer.address,
    operationDir: createUserOperationDir(userWorkspace.workspaceName, `claim-${shortAddress(signer.address)}`),
    workspaceLabel: userWorkspace.workspaceName,
    extraMetadata: {
      amount: amount.toString(),
    },
    execute: async (operationDir) => {
      const receipt = await waitForReceipt(await tokenVault.claimToWallet(amount));
      writeJson(path.join(operationDir, "claim-receipt.json"), sanitizeReceipt(receipt));
      return { amount: amount.toString() };
    },
  });
}

async function handleBridgeSend({ args, env, provider }) {
  requireFunctionName(args);
  const signer = requireL1Signer(args, env, provider);
  const l2Identity = deriveParticipantIdentity(requireArg(args.l2KeySignature, "--l2-key-signature"));
  const userWorkspace = loadUserWorkspace(requireUserWorkspaceName(args));
  const context = await loadChannelContext({
    args,
    networkName: null,
    provider,
    userWorkspaceContext: userWorkspace,
  });
  await assertWorkspaceAlignedWithChain(context, provider);
  expect(
    Number(userWorkspace.workspace.channelId) === Number(context.workspace.channelId),
    "The provided user workspace does not belong to the selected channel.",
  );
  expect(
    userWorkspace.workspace.l2Address === l2Identity.l2Address,
    "The provided user workspace does not match the derived L2 identity.",
  );
  const templatePayload = buildPayload(args.functionName, args);
  const controllerAbi = readJson(path.resolve(deployRoot, templatePayload.abiFile.replace("../deploy/", "")));
  const fragment = findFunctionFragment(controllerAbi, templatePayload.method);
  const formattedArgs = formatArguments(fragment.inputs ?? [], templatePayload.args ?? []);
  const inputSignature = buildInputSignature(fragment);
  const calldata = runCast(["calldata", inputSignature, ...formattedArgs]).trim();
  const nonce = Number(userWorkspace.workspace.l2Nonce ?? 0);
  const operationDir = createUserOperationDir(userWorkspace.workspaceName, `${args.functionName}-${shortAddress(l2Identity.l2Address)}`);
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

  userWorkspace.workspace.l2Nonce = nonce + 1;
  applyNoteLifecycleAcrossKnownUserWorkspaces(
    userWorkspace,
    extractNoteLifecycle(args.functionName, templatePayload),
    args.functionName,
    receipt.hash,
  );
  context.currentSnapshot = nextSnapshot;
  persistUserWorkspace(userWorkspace);
  persistCurrentState(context);

  printJson({
    action: "bridge-send",
    workspace: context.workspaceName,
    userWorkspace: userWorkspace.workspaceName,
    functionName: args.functionName,
    operationDir,
    l1Submitter: signer.address,
    l2Address: l2Identity.l2Address,
    nonce,
    updatedRoots: context.currentSnapshot.stateRoots,
  });
}

function defaultUserWorkspaceName(channelName, l2Address) {
  return `${channelName}-${l2Address}`;
}

function ensureUserWorkspace({
  args,
  channelContext,
  signerAddress,
  l2Identity,
  storageKey,
  leafIndex,
}) {
  const workspaceName = args.userWorkspace ?? defaultUserWorkspaceName(channelContext.workspace.channelName, l2Identity.l2Address);
  const workspaceDir = userWorkspacePath(workspaceName);
  let workspace;
  if (fs.existsSync(path.join(workspaceDir, "workspace.json"))) {
    workspace = normalizeUserWorkspace(readJson(path.join(workspaceDir, "workspace.json")));
    expect(
      Number(workspace.channelId) === Number(channelContext.workspace.channelId),
      `User workspace ${workspaceName} belongs to channel ${workspace.channelId}, not ${channelContext.workspace.channelId}.`,
    );
    expect(
      workspace.l2Address === l2Identity.l2Address,
      `User workspace ${workspaceName} belongs to L2 address ${workspace.l2Address}, not ${l2Identity.l2Address}.`,
    );
  } else {
    ensureDir(workspaceDir);
    ensureDir(path.join(workspaceDir, "operations"));
    workspace = normalizeUserWorkspace({
      name: workspaceName,
      network: channelContext.workspace.network,
      chainId: channelContext.workspace.chainId,
      appDeploymentPath: channelContext.workspace.appDeploymentPath,
      storageLayoutPath: channelContext.workspace.storageLayoutPath,
      channelName: channelContext.workspace.channelName,
      channelId: channelContext.workspace.channelId,
      channelManager: channelContext.workspace.channelManager,
      tokenVault: channelContext.workspace.tokenVault,
      canonicalAsset: channelContext.workspace.canonicalAsset,
      controller: channelContext.workspace.controller,
      l2AccountingVault: channelContext.workspace.l2AccountingVault,
      liquidBalancesSlot: channelContext.workspace.liquidBalancesSlot,
      l1Address: signerAddress,
      l2Address: l2Identity.l2Address,
      l2StorageKey: storageKey,
      leafIndex: leafIndex?.toString() ?? null,
      l2Nonce: 0,
      notes: {},
    });
  }

  workspace.appDeploymentPath = channelContext.workspace.appDeploymentPath;
  workspace.storageLayoutPath = channelContext.workspace.storageLayoutPath;
  workspace.channelName = channelContext.workspace.channelName;
  workspace.channelId = channelContext.workspace.channelId;
  workspace.channelManager = channelContext.workspace.channelManager;
  workspace.tokenVault = channelContext.workspace.tokenVault;
  workspace.canonicalAsset = channelContext.workspace.canonicalAsset;
  workspace.controller = channelContext.workspace.controller;
  workspace.l2AccountingVault = channelContext.workspace.l2AccountingVault;
  workspace.liquidBalancesSlot = channelContext.workspace.liquidBalancesSlot;
  workspace.l1Address = signerAddress;
  workspace.l2Address = l2Identity.l2Address;
  workspace.l2StorageKey = storageKey;
  if (leafIndex !== undefined && leafIndex !== null) {
    workspace.leafIndex = leafIndex.toString();
  }

  const context = {
    workspaceName,
    workspaceDir,
    workspace,
  };
  persistUserWorkspace(context);
  return context;
}

function normalizeUserWorkspace(workspace) {
  const unusedNotes = Object.values(workspace.notes?.unused ?? {}).map(normalizeTrackedNote);
  unusedNotes.sort(compareNotesByValueDesc);
  const spentNotes = Object.values(workspace.notes?.spent ?? {}).map(normalizeTrackedNote);

  return {
    ...workspace,
    l2Nonce: Number(workspace.l2Nonce ?? 0),
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

function applyNoteLifecycleToUserWorkspace(userWorkspaceContext, lifecycle, sourceFunction, sourceTxHash) {
  for (const inputNote of lifecycle.inputs) {
    const trackedInput = buildTrackedNote(inputNote, sourceFunction, sourceTxHash);
    const existingUnusedNote = userWorkspaceContext.workspace.notes.unused[trackedInput.commitment];
    if (!existingUnusedNote) {
      continue;
    }
    delete userWorkspaceContext.workspace.notes.unused[trackedInput.commitment];
    userWorkspaceContext.workspace.notes.spent[trackedInput.nullifier] = {
      ...existingUnusedNote,
      status: "spent",
      sourceFunction,
      sourceTxHash,
    };
  }

  for (const outputNote of lifecycle.outputs) {
    const trackedOutput = buildTrackedNote(outputNote, sourceFunction, sourceTxHash);
    if (trackedOutput.owner !== userWorkspaceContext.workspace.l2Address) {
      continue;
    }
    userWorkspaceContext.workspace.notes.unused[trackedOutput.commitment] = trackedOutput;
  }

  userWorkspaceContext.workspace = normalizeUserWorkspace(userWorkspaceContext.workspace);
  persistUserWorkspace(userWorkspaceContext);
}

function applyNoteLifecycleAcrossKnownUserWorkspaces(primaryUserWorkspaceContext, lifecycle, sourceFunction, sourceTxHash) {
  const knownWorkspaces = new Map([[primaryUserWorkspaceContext.workspaceName, primaryUserWorkspaceContext]]);
  for (const descriptor of listUserWorkspaces()) {
    if (!descriptor.name || knownWorkspaces.has(descriptor.name)) {
      continue;
    }
    const workspaceContext = loadUserWorkspace(descriptor.name);
    if (workspaceContext.workspace.channelId !== primaryUserWorkspaceContext.workspace.channelId) {
      continue;
    }
    knownWorkspaces.set(workspaceContext.workspaceName, workspaceContext);
  }

  for (const workspaceContext of knownWorkspaces.values()) {
    applyNoteLifecycleToUserWorkspace(workspaceContext, lifecycle, sourceFunction, sourceTxHash);
  }
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

async function loadChannelContext({ args, networkName, provider, userWorkspaceContext = null }) {
  const explicitWorkspaceName = args.workspace ? requireWorkspaceName(args) : null;
  if (explicitWorkspaceName) {
    const explicitWorkspaceDir = channelWorkspacePath(explicitWorkspaceName);
    if (fs.existsSync(path.join(explicitWorkspaceDir, "workspace.json"))) {
      return loadWorkspaceContext(explicitWorkspaceName, provider);
    }
  }

  const chainId = Number((await provider.getNetwork()).chainId);
  const resolvedNetworkName = networkName ?? networkNameFromChainId(chainId);
  const channelName = args.channelName ?? userWorkspaceContext?.workspace.channelName;
  if (args.channelName && userWorkspaceContext) {
    expect(
      args.channelName === userWorkspaceContext.workspace.channelName,
      [
        `The provided --channel-name (${args.channelName}) does not match the user workspace channel`,
        `(${userWorkspaceContext.workspace.channelName}).`,
      ].join(" "),
    );
  }
  if (!channelName) {
    throw new Error(
      "Missing channel selector. Provide either --workspace, --channel-name, or --user-workspace bound to a channel.",
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

function loadUserWorkspace(workspaceName) {
  const normalizedWorkspaceName = requireUserWorkspaceName({ userWorkspace: workspaceName });
  const workspaceDir = userWorkspacePath(normalizedWorkspaceName);
  const workspace = readJson(path.join(workspaceDir, "workspace.json"));
  return {
    workspaceName: normalizedWorkspaceName,
    workspaceDir,
    workspace: normalizeUserWorkspace(workspace),
  };
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

async function saveNoStateChangeOperation({
  context,
  operationName,
  actorLabel,
  extraMetadata,
  execute,
  operationDir,
  workspaceLabel,
}) {
  const resolvedOperationDir =
    operationDir ?? createOperationDir(context.workspaceName, `${operationName}-${shortAddress(actorLabel)}`);
  ensureDir(resolvedOperationDir);
  writeJson(path.join(resolvedOperationDir, "state_snapshot.json"), context.currentSnapshot);
  writeJson(
    path.join(resolvedOperationDir, "state_snapshot.normalized.json"),
    normalizeStateSnapshot(context.currentSnapshot),
  );

  const result = await execute(resolvedOperationDir);
  writeJson(path.join(resolvedOperationDir, "operation.json"), {
    operationName,
    actorLabel,
    ...extraMetadata,
    result,
  });
  printJson({
    action: operationName,
    workspace: workspaceLabel ?? context.workspaceName,
    channelName: context.workspace.channelName,
    operationDir: resolvedOperationDir,
    ...extraMetadata,
    result,
  });
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

function deriveParticipantIdentity(signatureSeed) {
  const keySet = deriveL2KeysFromSignature(signatureSeed);
  const l2Address = getAddress(fromEdwardsToAddress(keySet.publicKey).toString());
  return {
    l2PrivateKey: keySet.privateKey,
    l2PublicKey: keySet.publicKey,
    l2Address,
  };
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

function parseAmountArg(value) {
  return toBigIntStrict(value);
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

function requireUserWorkspaceName(args) {
  const value = typeof args === "string" ? args : args.userWorkspace;
  if (!value) {
    throw new Error("Missing --user-workspace.");
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

function userWorkspacePath(name) {
  return path.join(userWorkspacesRoot, slugify(name));
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

function listUserWorkspaces() {
  if (!fs.existsSync(userWorkspacesRoot)) {
    return [];
  }
  return fs.readdirSync(userWorkspacesRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const configPath = path.join(userWorkspacesRoot, entry.name, "workspace.json");
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

function createUserOperationDir(workspaceName, suffix) {
  const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const operationDir = path.join(userWorkspacePath(workspaceName), "operations", `${timestamp}-${slugify(suffix)}`);
  ensureDir(operationDir);
  return operationDir;
}

function persistWorkspace(context) {
  writeJson(path.join(context.workspaceDir, "workspace.json"), context.workspace);
}

function persistUserWorkspace(context) {
  writeJson(path.join(context.workspaceDir, "workspace.json"), context.workspace);
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
  node apps/private-state/cli/private-state-bridge-cli.mjs channel-create --channel-name <name> --dapp-id <id> --asset <address> --private-key <hex> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs channel-workspace-list
  node apps/private-state/cli/private-state-bridge-cli.mjs channel-workspace-init --channel-name <name> [--workspace <name>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs channel-workspace-show --workspace <name>
  node apps/private-state/cli/private-state-bridge-cli.mjs user-workspace-list
  node apps/private-state/cli/private-state-bridge-cli.mjs user-workspace-show --user-workspace <name> [--amount <wei>]
  node apps/private-state/cli/private-state-bridge-cli.mjs register-and-fund (--channel-name <name> | --workspace <channel-workspace>) --private-key <hex> --l2-key-signature <seed> --amount <wei> [--user-workspace <name>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs fund-l1 (--channel-name <name> | --workspace <channel-workspace> | --user-workspace <name>) --private-key <hex> --amount <wei> --user-workspace <name> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs deposit (--channel-name <name> | --workspace <channel-workspace>) --private-key <hex> --l2-key-signature <seed> --amount <wei> [--user-workspace <name>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs withdraw (--channel-name <name> | --workspace <channel-workspace> | --user-workspace <name>) --private-key <hex> --l2-key-signature <seed> --amount <wei> [--user-workspace <name>] [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs claim (--channel-name <name> | --workspace <channel-workspace> | --user-workspace <name>) --private-key <hex> --amount <wei> --user-workspace <name> [options]
  node apps/private-state/cli/private-state-bridge-cli.mjs bridge-send <function-name> (--channel-name <name> | --workspace <channel-workspace> | --user-workspace <name>) --user-workspace <name> --private-key <hex> --l2-key-signature <seed> [--args-file <path>] [--template-file <path>] [options]

Common flags:
  --network <name>         Override APPS_NETWORK from apps/.env. Allowed: mainnet, sepolia
  --rpc-url <url>          Explicit RPC endpoint override
  --alchemy-api-key <key>  Explicit Alchemy key override
  --env-file <path>        Alternate apps/.env location

channel-create options:
  --leader <address>           Optional channel leader. Default: the signing EOA
  --create-workspace           Also initialize a channel workspace after creation
  --workspace <name>           Channel workspace name to use with --create-workspace. Default: channel name

channel-workspace-init options:
  --channel-name <name>        User-provided channel name; channelId is derived as keccak256(bytes(name))
  --workspace <name>           Optional cache name. Default: channel name
  --block-info-file <path>     Optional block_info.json override; must match the channel genesis block context
  --state-snapshot-file <path> Import an existing non-genesis snapshot
  --force                      Overwrite an existing workspace

bridge-send options:
  --install-arg <value>    Optional tokamak-cli --install input before synthesis/proving
  --args-file <path>       JSON file whose value replaces template.args
  --template-file <path>   Full JSON template override

Notes:
  - channel-workspace-init derives block_info.json from the channel genesis block and reconstructs the latest channel state from bridge events.
  - Channel workspaces are optional caches for channel snapshots.
  - User workspaces are the mandatory local state for note-carrying users. They track L2 identity, nonce, and used/unused notes.
  - The CLI auto-selects bridge deployment and ABI files from the chosen network's chain ID.
  - register-and-fund, deposit, and withdraw can allocate or refresh a user workspace automatically from --l2-key-signature.
  - fund-l1, claim, and bridge-send require an existing --user-workspace.
  - Channel workspace operations are stored under:
      apps/private-state/cli/workspaces/<workspace>/operations/
  - User workspace operations are stored under:
      apps/private-state/cli/user-workspaces/<workspace>/operations/
`);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
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
