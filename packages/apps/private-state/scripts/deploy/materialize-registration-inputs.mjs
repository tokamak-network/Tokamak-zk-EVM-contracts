#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  HDNodeWallet,
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
} from "tokamak-l2js";
import {
  addHexPrefix,
  bytesToBigInt,
  bytesToHex,
  createAddressFromString,
  hexToBigInt,
  hexToBytes,
} from "@ethereumjs/util";
import {
  buildTokamakCliInvocation,
  resolveTokamakBlockInputConfig,
  resolveTokamakCliSynthOutputDir,
} from "@tokamak-private-dapps/common-library/tokamak-runtime-paths";
import {
  computeEncryptedNoteSalt,
  deriveNoteReceiveKeyMaterial,
  encryptMintNoteValueForOwner,
  encryptNoteValueForRecipient,
} from "../e2e/private-state-note-delivery.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..", "..");
const amountUnit = 10n ** 18n;
const depositAmountBaseUnits = 3n * amountUnit;
const defaultMnemonic = "test test test test test test test test test test test junk";
const defaultChannelName = "private-state-registration";
const l2PasswordSigningDomain = "Tokamak private-state L2 password binding";
const { previousBlockHashCount: tokamakPrevBlockHashCount } = resolveTokamakBlockInputConfig();
const tokamakCliInvocation = buildTokamakCliInvocation();

function usage() {
  console.log(`Usage:
  node packages/apps/private-state/scripts/deploy/materialize-registration-inputs.mjs --rpc-url <url> --app-deployment-path <path> --storage-layout-path <path> --out <dir> [options]

Options:
  --channel-name <name>              Synthetic channel name used to derive deterministic registration inputs
  --mnemonic <phrase>                Deterministic L1 mnemonic for synthetic participants
  --help                             Show this help

The output root is compatible with bridge/scripts/admin-add-dapp.mjs --example-root.
`);
}

function parseArgs(argv) {
  const options = {
    rpcUrl: null,
    appDeploymentPath: null,
    storageLayoutPath: null,
    out: null,
    channelName: defaultChannelName,
    mnemonic: defaultMnemonic,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    const next = argv[index + 1];
    const take = (name) => {
      if (!next || next.startsWith("--")) {
        throw new Error(`Missing value for ${name}.`);
      }
      index += 1;
      return next;
    };

    switch (current) {
      case "--rpc-url":
        options.rpcUrl = take(current);
        break;
      case "--app-deployment-path":
        options.appDeploymentPath = path.resolve(process.cwd(), take(current));
        break;
      case "--storage-layout-path":
        options.storageLayoutPath = path.resolve(process.cwd(), take(current));
        break;
      case "--out":
        options.out = path.resolve(process.cwd(), take(current));
        break;
      case "--channel-name":
        options.channelName = take(current);
        break;
      case "--mnemonic":
        options.mnemonic = take(current);
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        throw new Error(`Unknown option: ${current}`);
    }
  }

  for (const key of ["rpcUrl", "appDeploymentPath", "storageLayoutPath", "out"]) {
    if (!options[key]) {
      throw new Error(`--${key.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)} is required.`);
    }
  }

  return options;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(
    filePath,
    `${JSON.stringify(value, (_key, current) => (
      typeof current === "bigint" ? current.toString() : current
    ), 2)}\n`,
  );
}

function run(command, args, { cwd = repoRoot, quiet = false, label = command } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env: process.env,
    encoding: "utf8",
    stdio: quiet ? ["ignore", "pipe", "pipe"] : "inherit",
  });
  if (result.status !== 0) {
    throw new Error(
      [
        `${label} failed with exit code ${result.status ?? "unknown"}.`,
        result.stdout?.trim(),
        result.stderr?.trim(),
      ].filter(Boolean).join("\n"),
    );
  }
  return result.stdout ?? "";
}

function bytes32FromHex(hexValue) {
  return ethers.zeroPadValue(
    ethers.toBeHex(hexToBigInt(addHexPrefix(String(hexValue ?? "").replace(/^0x/i, "")))),
    32,
  );
}

function normalizeBytes32Hex(hexValue) {
  return bytes32FromHex(hexValue).toLowerCase();
}

function poseidonHexFromBytes(bytesLike) {
  return ethers.hexlify(poseidon(ethers.getBytes(bytesLike))).toLowerCase();
}

function bigintToHex32(value) {
  return ethers.zeroPadValue(ethers.toBeHex(value), 32);
}

function deriveChannelIdFromName(channelName) {
  return ethers.toBigInt(keccak256(ethers.toUtf8Bytes(channelName)));
}

function buildL2PasswordSigningMessage({ channelName, password }) {
  return [
    l2PasswordSigningDomain,
    `channel:${channelName}`,
    `password:${String(password)}`,
  ].join("\n");
}

async function deriveParticipantIdentityFromSigner({ channelName, password, signer }) {
  const seedSignature = await signer.signMessage(buildL2PasswordSigningMessage({ channelName, password }));
  const keySet = deriveL2KeysFromSignature(seedSignature);
  return {
    l2PrivateKey: keySet.privateKey,
    l2PublicKey: keySet.publicKey,
    l2Address: getAddress(fromEdwardsToAddress(keySet.publicKey).toString()),
  };
}

function buildMintInterface(outputCount) {
  return new Interface([
    `function mintNotes${outputCount}((uint256 value,bytes32[3] encryptedNoteValue)[${outputCount}] outputs)`,
  ]);
}

function buildTransferInterface(inputCount, outputCount) {
  return new Interface([
    `function transferNotes${inputCount}To${outputCount}((address owner,uint256 value,bytes32[3] encryptedNoteValue)[${outputCount}] outputs,(address owner,uint256 value,bytes32 salt)[${inputCount}] inputNotes)`,
  ]);
}

function buildRedeemInterface(inputCount) {
  return new Interface([
    `function redeemNotes${inputCount}((address owner,uint256 value,bytes32 salt)[${inputCount}] inputNotes,address receiver)`,
  ]);
}

function serializeBigInts(value) {
  return JSON.parse(JSON.stringify(value, (_key, current) => (
    typeof current === "bigint" ? current.toString() : current
  )));
}

function buildTokamakTxSnapshot({ signerPrivateKey, senderPubKey, to, data, nonce }) {
  return serializeBigInts(
    createTokamakL2Tx(
      {
        nonce: ethers.toBigInt(nonce),
        to: createAddressFromString(to),
        data: hexToBytes(addHexPrefix(String(data ?? "").replace(/^0x/i, ""))),
        senderPubKey,
      },
      { common: createTokamakL2Common() },
    )
      .sign(signerPrivateKey)
      .captureTxSnapshot(),
  );
}

async function getBlockInfoAt(provider, blockNumber) {
  const blockTag = ethers.toQuantity(blockNumber);
  const block = await provider.send("eth_getBlockByNumber", [blockTag, false]);
  const prevBlockHashes = [];
  for (let offset = 1; offset <= tokamakPrevBlockHashCount; offset += 1) {
    if (blockNumber <= offset) {
      prevBlockHashes.push("0x0");
      continue;
    }
    const previousBlock = await provider.send("eth_getBlockByNumber", [ethers.toQuantity(blockNumber - offset), false]);
    prevBlockHashes.push(previousBlock.hash);
  }
  const chainId = await provider.send("eth_chainId", []);
  return {
    coinBase: block.miner,
    timeStamp: block.timestamp,
    blockNumber: block.number,
    prevRanDao: block.prevRandao ?? block.mixHash ?? block.difficulty ?? "0x0",
    gasLimit: block.gasLimit,
    chainId,
    selfBalance: "0x0",
    baseFee: block.baseFeePerGas ?? "0x0",
    prevBlockHashes,
  };
}

async function getFixedBlockInfo(provider) {
  const latestNumberHex = await provider.send("eth_blockNumber", []);
  return getBlockInfoAt(provider, Number(hexToBigInt(addHexPrefix(String(latestNumberHex ?? "").replace(/^0x/i, "")))));
}

async function fetchContractCodes(provider, addresses) {
  const codes = [];
  for (const address of addresses) {
    const normalizedAddress = getAddress(address);
    const code = await provider.getCode(normalizedAddress);
    if (code === "0x") {
      throw new Error(`No deployed bytecode found at ${normalizedAddress}.`);
    }
    codes.push({ address: normalizedAddress, code });
  }
  return codes;
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

async function putStorageAndCapture(stateManager, address, keyHex, nextValue) {
  await currentStorageBigInt(stateManager, address, keyHex);
  await stateManager.putStorage(
    createAddressFromString(address),
    hexToBytes(addHexPrefix(String(keyHex ?? "").replace(/^0x/i, ""))),
    hexToBytes(addHexPrefix(String(bigintToHex32(nextValue) ?? "").replace(/^0x/i, ""))),
  );
  return stateManager.captureStateSnapshot();
}

function deriveLiquidBalanceStorageKey(l2Address, slot) {
  return normalizeBytes32Hex(bytesToHex(getUserStorageKey([l2Address, ethers.toBigInt(slot)], "TokamakL2")));
}

function buildEncryptedMintOutput({ owner, ownerNoteReceivePubKey, value, label, chainId, channelId }) {
  const nonce = ethers.dataSlice(poseidonHexFromBytes(ethers.toUtf8Bytes(`${label}:nonce`)), 0, 12);
  const encryptedNoteValue = encryptMintNoteValueForOwner({
    value,
    ownerNoteReceivePubKey,
    chainId,
    channelId,
    owner,
    nonce,
  });
  return {
    output: { value, encryptedNoteValue },
    note: {
      owner: getAddress(owner),
      value,
      salt: computeEncryptedNoteSalt(encryptedNoteValue),
    },
  };
}

function buildEncryptedTransferOutput({ owner, value, label, recipientNoteReceivePubKey, chainId, channelId }) {
  const nonce = ethers.dataSlice(poseidonHexFromBytes(ethers.toUtf8Bytes(`${label}:nonce`)), 0, 12);
  const encryptedNoteValue = encryptNoteValueForRecipient({
    value,
    recipientNoteReceivePubKey,
    chainId,
    channelId,
    owner,
    nonce,
  });
  return {
    output: {
      owner: getAddress(owner),
      value,
      encryptedNoteValue,
    },
    note: {
      owner: getAddress(owner),
      value,
      salt: computeEncryptedNoteSalt(encryptedNoteValue),
    },
  };
}

function deriveChannelTokenVaultLeafIndex(storageKey) {
  return hexToBigInt(addHexPrefix(String(storageKey ?? "").replace(/^0x/i, ""))) % ethers.toBigInt(MAX_MT_LEAVES);
}

async function deriveParticipant({ index, alias, mnemonic, provider, channelName, channelId, chainId, liquidBalancesSlot }) {
  const wallet = HDNodeWallet.fromPhrase(mnemonic, undefined, `m/44'/60'/0'/0/${index}`);
  const signer = new Wallet(wallet.privateKey, provider);
  const l2Identity = await deriveParticipantIdentityFromSigner({
    channelName,
    password: alias,
    signer,
  });
  const noteReceive = await deriveNoteReceiveKeyMaterial({
    signer,
    chainId,
    channelId,
    channelName,
    account: wallet.address,
  });
  const storageKey = normalizeBytes32Hex(deriveLiquidBalanceStorageKey(l2Identity.l2Address, liquidBalancesSlot));
  return {
    alias,
    l1Address: getAddress(wallet.address),
    l2Identity,
    noteReceive,
    storageKey,
    leafIndex: deriveChannelTokenVaultLeafIndex(storageKey),
  };
}

async function initialSnapshotFor({ controllerAddress, vaultAddress, channelId }) {
  const stateManager = new TokamakL2StateManager({ common: createTokamakL2Common() });
  const addresses = [controllerAddress, vaultAddress].map((address) => createAddressFromString(address));
  await stateManager._initializeForAddresses(addresses);
  stateManager._channelId = channelId;
  for (const address of addresses) {
    stateManager._commitResolvedStorageEntries(address, []);
  }
  return stateManager.captureStateSnapshot();
}

function writeBundle(outputRoot, groupName, exampleName, snapshot, transaction, blockInfo, contractCodes) {
  const bundleDir = path.join(outputRoot, groupName, exampleName);
  fs.rmSync(bundleDir, { recursive: true, force: true });
  writeJson(path.join(bundleDir, "previous_state_snapshot.json"), snapshot);
  writeJson(path.join(bundleDir, "transaction.json"), transaction);
  writeJson(path.join(bundleDir, "block_info.json"), blockInfo);
  writeJson(path.join(bundleDir, "contract_codes.json"), contractCodes);
  return bundleDir;
}

async function synthesizeNextSnapshot(bundleDir, metadataRoot, exampleName) {
  run(
    tokamakCliInvocation.command,
    [
      ...tokamakCliInvocation.args,
      "--synthesize",
      "--previous-state", path.join(bundleDir, "previous_state_snapshot.json"),
      "--transaction", path.join(bundleDir, "transaction.json"),
      "--block-info", path.join(bundleDir, "block_info.json"),
      "--contract-code", path.join(bundleDir, "contract_codes.json"),
    ],
    { quiet: true, label: `synthesize:${exampleName}` },
  );
  const synthOutputDir = resolveTokamakCliSynthOutputDir();
  const stepDir = path.join(metadataRoot, exampleName);
  fs.rmSync(stepDir, { recursive: true, force: true });
  fs.mkdirSync(stepDir, { recursive: true });
  fs.cpSync(synthOutputDir, path.join(stepDir, "synthesizer-output"), { recursive: true });
  const nextSnapshot = readJson(path.join(synthOutputDir, "state_snapshot.json"));
  if (Array.isArray(nextSnapshot.storageAddresses)) {
    nextSnapshot.storageAddresses = nextSnapshot.storageAddresses
      .map((address) => createAddressFromString(address).toString());
  }
  return nextSnapshot;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const provider = new JsonRpcProvider(options.rpcUrl);
  const chainId = Number((await provider.getNetwork()).chainId);
  const deployment = readJson(options.appDeploymentPath);
  const storageLayout = readJson(options.storageLayoutPath);
  const controllerAddress = getAddress(deployment.contracts?.controller);
  const vaultAddress = getAddress(deployment.contracts?.l2AccountingVault);
  const liquidBalancesSlot = ethers.toBigInt(
    storageLayout.contracts.L2AccountingVault.storageLayout.storage.find((entry) => entry.label === "liquidBalances").slot,
  );
  const commitmentExistsSlot = ethers.toBigInt(
    storageLayout.contracts.PrivateStateController.storageLayout.storage.find(
      (entry) => entry.label === "commitmentExists",
    ).slot,
  );
  const nullifierUsedSlot = ethers.toBigInt(
    storageLayout.contracts.PrivateStateController.storageLayout.storage.find(
      (entry) => entry.label === "nullifierUsed",
    ).slot,
  );

  const channelId = deriveChannelIdFromName(options.channelName);
  const blockInfo = await getFixedBlockInfo(provider);
  const contractCodes = await fetchContractCodes(provider, [controllerAddress, vaultAddress]);
  const metadataRoot = path.join(options.out, ".metadata");
  fs.rmSync(options.out, { recursive: true, force: true });

  const participants = [
    await deriveParticipant({
      index: 1,
      alias: "participant-a",
      mnemonic: options.mnemonic,
      provider,
      channelName: options.channelName,
      channelId,
      chainId,
      liquidBalancesSlot,
    }),
    await deriveParticipant({
      index: 2,
      alias: "participant-b",
      mnemonic: options.mnemonic,
      provider,
      channelName: options.channelName,
      channelId,
      chainId,
      liquidBalancesSlot,
    }),
    await deriveParticipant({
      index: 3,
      alias: "participant-c",
      mnemonic: options.mnemonic,
      provider,
      channelName: options.channelName,
      channelId,
      chainId,
      liquidBalancesSlot,
    }),
  ];
  const [participantA, participantB, participantC] = participants;

  let postDepositSnapshot = await initialSnapshotFor({ controllerAddress, vaultAddress, channelId });
  const depositStateManager = await buildStateManager(postDepositSnapshot, contractCodes);
  for (const participant of participants) {
    postDepositSnapshot = await putStorageAndCapture(
      depositStateManager,
      vaultAddress,
      participant.storageKey,
      depositAmountBaseUnits,
    );
  }

  const encryptedMints = {
    aMint: buildEncryptedMintOutput({
      owner: participantA.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantA.noteReceive.noteReceivePubKey,
      value: depositAmountBaseUnits,
      label: "registration:a-mint",
      chainId,
      channelId,
    }),
    bMint: buildEncryptedMintOutput({
      owner: participantB.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantB.noteReceive.noteReceivePubKey,
      value: depositAmountBaseUnits,
      label: "registration:b-mint",
      chainId,
      channelId,
    }),
    cMint: buildEncryptedMintOutput({
      owner: participantC.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantC.noteReceive.noteReceivePubKey,
      value: depositAmountBaseUnits,
      label: "registration:c-mint",
      chainId,
      channelId,
    }),
    aMintSplit1: buildEncryptedMintOutput({
      owner: participantA.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantA.noteReceive.noteReceivePubKey,
      value: 1n * amountUnit,
      label: "registration:a-mint-split-1",
      chainId,
      channelId,
    }),
    aMintSplit2: buildEncryptedMintOutput({
      owner: participantA.l2Identity.l2Address,
      ownerNoteReceivePubKey: participantA.noteReceive.noteReceivePubKey,
      value: 2n * amountUnit,
      label: "registration:a-mint-split-2",
      chainId,
      channelId,
    }),
  };

  const encryptedTransfers = {
    aToBOne: buildEncryptedTransferOutput({
      owner: participantB.l2Identity.l2Address,
      value: 1n * amountUnit,
      label: "registration:a-to-b-1",
      recipientNoteReceivePubKey: participantB.noteReceive.noteReceivePubKey,
      chainId,
      channelId,
    }),
    aToBThree: buildEncryptedTransferOutput({
      owner: participantB.l2Identity.l2Address,
      value: 3n * amountUnit,
      label: "registration:a-to-b-3",
      recipientNoteReceivePubKey: participantB.noteReceive.noteReceivePubKey,
      chainId,
      channelId,
    }),
    aToC: buildEncryptedTransferOutput({
      owner: participantC.l2Identity.l2Address,
      value: 2n * amountUnit,
      label: "registration:a-to-c",
      recipientNoteReceivePubKey: participantC.noteReceive.noteReceivePubKey,
      chainId,
      channelId,
    }),
    bToC: buildEncryptedTransferOutput({
      owner: participantC.l2Identity.l2Address,
      value: 4n * amountUnit,
      label: "registration:b-to-c",
      recipientNoteReceivePubKey: participantC.noteReceive.noteReceivePubKey,
      chainId,
      channelId,
    }),
  };

  const notes = {
    aMint: encryptedMints.aMint.note,
    bMint: encryptedMints.bMint.note,
    cMint: encryptedMints.cMint.note,
    aToBOne: encryptedTransfers.aToBOne.note,
    aToC: encryptedTransfers.aToC.note,
    bToC: encryptedTransfers.bToC.note,
  };

  async function materialize({ groupName, exampleName, previousSnapshot, sender, calldata, register = true }) {
    const transaction = buildTokamakTxSnapshot({
      signerPrivateKey: sender.l2Identity.l2PrivateKey,
      senderPubKey: sender.l2Identity.l2PublicKey,
      to: controllerAddress,
      data: calldata,
      nonce: 0,
    });
    const targetGroup = register ? groupName : "_internal";
    const bundleDir = writeBundle(options.out, targetGroup, exampleName, previousSnapshot, transaction, blockInfo, contractCodes);
    return synthesizeNextSnapshot(bundleDir, metadataRoot, exampleName);
  }

  const mintNotes1 = await materialize({
    groupName: "mintNotes",
    exampleName: "mintNotes1",
    previousSnapshot: postDepositSnapshot,
    sender: participantA,
    calldata: buildMintInterface(1).encodeFunctionData("mintNotes1", [[[
      encryptedMints.aMint.output.value,
      encryptedMints.aMint.output.encryptedNoteValue,
    ]]]),
  });

  await materialize({
    groupName: "mintNotes",
    exampleName: "mintNotes2",
    previousSnapshot: postDepositSnapshot,
    sender: participantA,
    calldata: buildMintInterface(2).encodeFunctionData("mintNotes2", [[
      [encryptedMints.aMintSplit1.output.value, encryptedMints.aMintSplit1.output.encryptedNoteValue],
      [encryptedMints.aMintSplit2.output.value, encryptedMints.aMintSplit2.output.encryptedNoteValue],
    ]]),
  });

  const transferNotes1To1 = await materialize({
    groupName: "transferNotes",
    exampleName: "transferNotes1To1",
    previousSnapshot: mintNotes1,
    sender: participantA,
    calldata: buildTransferInterface(1, 1).encodeFunctionData("transferNotes1To1", [[
      [
        encryptedTransfers.aToBThree.output.owner,
        encryptedTransfers.aToBThree.output.value,
        encryptedTransfers.aToBThree.output.encryptedNoteValue,
      ],
    ], [[notes.aMint.owner, notes.aMint.value, notes.aMint.salt]]]),
  });

  const internalMintB = await materialize({
    groupName: "mintNotes",
    exampleName: "internalMintB",
    previousSnapshot: mintNotes1,
    sender: participantB,
    register: false,
    calldata: buildMintInterface(1).encodeFunctionData("mintNotes1", [[[
      encryptedMints.bMint.output.value,
      encryptedMints.bMint.output.encryptedNoteValue,
    ]]]),
  });

  const internalMintC = await materialize({
    groupName: "mintNotes",
    exampleName: "internalMintC",
    previousSnapshot: internalMintB,
    sender: participantC,
    register: false,
    calldata: buildMintInterface(1).encodeFunctionData("mintNotes1", [[[
      encryptedMints.cMint.output.value,
      encryptedMints.cMint.output.encryptedNoteValue,
    ]]]),
  });

  const transferNotes1To2 = await materialize({
    groupName: "transferNotes",
    exampleName: "transferNotes1To2",
    previousSnapshot: internalMintC,
    sender: participantA,
    calldata: buildTransferInterface(1, 2).encodeFunctionData("transferNotes1To2", [[
      [
        encryptedTransfers.aToBOne.output.owner,
        encryptedTransfers.aToBOne.output.value,
        encryptedTransfers.aToBOne.output.encryptedNoteValue,
      ],
      [
        encryptedTransfers.aToC.output.owner,
        encryptedTransfers.aToC.output.value,
        encryptedTransfers.aToC.output.encryptedNoteValue,
      ],
    ], [[notes.aMint.owner, notes.aMint.value, notes.aMint.salt]]]),
  });

  const transferNotes2To1 = await materialize({
    groupName: "transferNotes",
    exampleName: "transferNotes2To1",
    previousSnapshot: transferNotes1To2,
    sender: participantB,
    calldata: buildTransferInterface(2, 1).encodeFunctionData("transferNotes2To1", [[
      [
        encryptedTransfers.bToC.output.owner,
        encryptedTransfers.bToC.output.value,
        encryptedTransfers.bToC.output.encryptedNoteValue,
      ],
    ], [
      [notes.bMint.owner, notes.bMint.value, notes.bMint.salt],
      [notes.aToBOne.owner, notes.aToBOne.value, notes.aToBOne.salt],
    ]]),
  });

  await materialize({
    groupName: "redeemNotes",
    exampleName: "redeemNotes1",
    previousSnapshot: transferNotes2To1,
    sender: participantC,
    calldata: buildRedeemInterface(1).encodeFunctionData("redeemNotes1", [[[
      notes.aToC.owner,
      notes.aToC.value,
      notes.aToC.salt,
    ]], participantC.l2Identity.l2Address]),
  });

  writeJson(path.join(options.out, "manifest.json"), {
    generatedAt: new Date().toISOString(),
    chainId,
    channelName: options.channelName,
    channelId: channelId.toString(),
    controllerAddress,
    vaultAddress,
    examples: {
      mintNotes: ["mintNotes1", "mintNotes2"],
      transferNotes: ["transferNotes1To1", "transferNotes1To2", "transferNotes2To1"],
      redeemNotes: ["redeemNotes1"],
    },
    participants: participants.map((participant) => ({
      alias: participant.alias,
      l1Address: participant.l1Address,
      l2Address: participant.l2Identity.l2Address,
      storageKey: participant.storageKey,
      leafIndex: participant.leafIndex.toString(),
    })),
    replaySlots: {
      liquidBalances: liquidBalancesSlot.toString(),
      commitmentExists: commitmentExistsSlot.toString(),
      nullifierUsed: nullifierUsedSlot.toString(),
    },
  });

  console.log(`Materialized private-state registration inputs under ${options.out}`);
}

main().catch((error) => {
  console.error(error?.message ?? error);
  process.exit(1);
});
