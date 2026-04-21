#!/usr/bin/env node

import fs from 'fs/promises';
import path from 'path';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import { ethers } from 'ethers';
import {
  addHexPrefix,
  bytesToHex,
  createAddressFromString,
  hexToBytes,
  setLengthLeft,
  utf8ToBytes,
} from '../../../../submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/node_modules/@ethereumjs/util/dist/esm/index.js';
import { jubjub } from '../../../../submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/node_modules/@noble/curves/misc.js';
import type { EdwardsPoint } from '../../../../submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/node_modules/@noble/curves/abstract/edwards.js';
import {
  createTokamakL2Common,
  createStateManagerOptsFromChannelConfig,
  createTokamakL2StateManagerFromL1RPC,
  createTokamakL2Tx,
  deriveL2KeysFromSignature,
  type ChannelStateConfig,
  type StateSnapshot,
  type TokamakL2TxData,
} from '../../../../submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/node_modules/tokamak-l2js/dist/index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..', '..', '..', '..');
const privateStateAppDir = path.resolve(repoRoot, 'apps', 'private-state');
const generatedArtifactsRoot = path.resolve(privateStateAppDir, 'script', 'synthesizer-compat-test', 'generated');
const synthesizerRoot = path.resolve(repoRoot, 'submodules', 'Tokamak-zk-EVM', 'packages', 'frontend', 'synthesizer');
const synthesizerTsconfigPath = path.resolve(synthesizerRoot, 'tsconfig.dev.json');
const synthesizerCliPath = path.resolve(synthesizerRoot, 'src', 'interface', 'cli', 'index.ts');
const synthesizerOutputsDir = path.resolve(synthesizerRoot, 'outputs');

const mintGeneratorPath = path.resolve(synthesizerRoot, 'scripts', 'generate-private-state-mint-config.ts');
const transferGeneratorPath = path.resolve(synthesizerRoot, 'scripts', 'generate-private-state-transfer-config.ts');
const redeemGeneratorPath = path.resolve(synthesizerRoot, 'scripts', 'generate-private-state-redeem-config.ts');

const DEFAULT_ANVIL_RPC_URL = 'http://127.0.0.1:8545';
const DEFAULT_FROM_ACCOUNT_SET = [0, 1, 2, 3];
const DEFAULT_PARTICIPANT_COUNT = 4;
const FIXED_MINT_TO_ACCOUNT = 0;
const FIXED_REDEEM_TO_ACCOUNT = 0;
const FIXED_PREV_BLOCK_HASH_COUNT = 4;
const DEFAULT_RANDOM_SAMPLE_COUNT = 6;
const DEFAULT_RANDOM_SEED = 'private-state-synth-compat';
const DEFAULT_EXTRA_COMMITMENT_LIMIT = 3;
const DEFAULT_CHANNEL_ID = 4;

type ParticipantEntry = {
  addressL1: `0x${string}`;
  prvSeedL2: string;
};

type StorageConfigEntry = {
  address: `0x${string}`;
  userStorageSlots: number[];
  preAllocatedKeys: `0x${string}`[];
};

type BaseCompatConfig = {
  network: 'anvil';
  participants: ParticipantEntry[];
  storageConfigs: StorageConfigEntry[];
  callCodeAddresses: `0x${string}`[];
  blockNumber: number;
  txNonce: number;
  calldata: `0x${string}`;
  senderIndex: number;
  function: {
    selector: `0x${string}`;
    entryContractAddress: `0x${string}`;
  };
};

type DerivedParticipantKeys = {
  privateKeys: Uint8Array[];
  publicKeys: EdwardsPoint[];
};

type CliInputBundle = {
  previousState: StateSnapshot;
  blockInfo: SynthesizerBlockInfo;
  contractCodes: { address: `0x${string}`; code: `0x${string}` }[];
  transactionRlp: `0x${string}`;
};

type CliInputOverrides = {
  transactionNonce?: bigint;
  blockInfo?: SynthesizerBlockInfo;
};

type SynthesizerBlockInfo = {
  coinBase: `0x${string}`;
  timeStamp: `0x${string}`;
  blockNumber: `0x${string}`;
  prevRanDao: `0x${string}`;
  gasLimit: `0x${string}`;
  chainId: `0x${string}`;
  selfBalance: `0x${string}`;
  baseFee: `0x${string}`;
  prevBlockHashes: `0x${string}`[];
};

type TestResultSnapshot = {
  aPubFunction: unknown;
  permutation: unknown;
};

type TestSpec = {
  functionName: string;
  family: 'mint' | 'transfer' | 'redeem';
  buildVariants: (fromAccountIndex: number, sampleCount: number, seedLabel: string) => Array<{
    variantName: string;
    generatorArgs: string[];
  }>;
};

const buildUniqueAccountSet = (values: number[]): number[] => Array.from(new Set(values));

const hashStringToUint32 = (value: string): number => {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
};

const createPrng = (seedLabel: string): (() => number) => {
  let state = hashStringToUint32(seedLabel) || 1;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 0x100000000;
  };
};

const randomInteger = (prng: () => number, maxExclusive: number): number => Math.floor(prng() * maxExclusive);

const randomHexWord = (prng: () => number): `0x${string}` => {
  let hex = '0x';
  for (let index = 0; index < 8; index += 1) {
    hex += randomInteger(prng, 0x100000000).toString(16).padStart(8, '0');
  }
  return hex as `0x${string}`;
};

const randomPermutation = (prng: () => number, values: number[]): number[] => {
  const next = [...values];
  for (let index = next.length - 1; index > 0; index -= 1) {
    const swapIndex = randomInteger(prng, index + 1);
    [next[index], next[swapIndex]] = [next[swapIndex]!, next[index]!];
  }
  return next;
};

const randomSubset = (
  prng: () => number,
  values: number[],
  maxSize: number,
): number[] => randomPermutation(prng, values).slice(0, randomInteger(prng, Math.min(maxSize, values.length) + 1));

const mintSpec = (outputs: 1 | 2 | 3 | 4 | 5 | 6): TestSpec => ({
  functionName: `mintNotes${outputs}`,
  family: 'mint',
  buildVariants: (fromAccountIndex, sampleCount, seedLabel) => {
    const baseArgs = [
      '--participants',
      String(DEFAULT_PARTICIPANT_COUNT),
      '--sender',
      String(fromAccountIndex),
      '--outputs',
      String(outputs),
    ];
    const variants: Array<{ variantName: string; generatorArgs: string[] }> = [
      {
        variantName: 'baseline',
        generatorArgs: [...baseArgs, '--note-owner', String(FIXED_MINT_TO_ACCOUNT)],
      },
    ];
    const accountIndices = Array.from({ length: DEFAULT_PARTICIPANT_COUNT }, (_, index) => index);
    for (let sampleIndex = 0; sampleIndex < sampleCount; sampleIndex += 1) {
      const prng = createPrng(`${seedLabel}:${outputs}:mint:${fromAccountIndex}:${sampleIndex}`);
      const toAccount = accountIndices[randomInteger(prng, accountIndices.length)] ?? FIXED_MINT_TO_ACCOUNT;
      const extraBalanceAccounts = randomSubset(
        prng,
        accountIndices.filter((accountIndex) => accountIndex !== toAccount),
        Math.max(0, accountIndices.length - 1),
      );
      const generatorArgs = [...baseArgs, '--note-owner', String(toAccount)];
      if (extraBalanceAccounts.length > 0) {
        generatorArgs.push('--extra-balance-accounts', buildUniqueAccountSet(extraBalanceAccounts).join(','));
      }
      variants.push({
        variantName: `sample-${String(sampleIndex).padStart(2, '0')}`,
        generatorArgs,
      });
    }
    return variants;
  },
});

const transferSpec = (inputs: 1 | 2 | 3 | 4, outputs: 1 | 2 | 3): TestSpec => ({
  functionName: `transferNotes${inputs}To${outputs}`,
  family: 'transfer',
  buildVariants: (fromAccountIndex, sampleCount, seedLabel) => {
    const baseArgs = [
      '--participants',
      String(DEFAULT_PARTICIPANT_COUNT),
      '--sender',
      String(fromAccountIndex),
      '--inputs',
      String(inputs),
      '--outputs',
      String(outputs),
    ];
    const variants: Array<{ variantName: string; generatorArgs: string[] }> = [
      {
        variantName: 'baseline',
        generatorArgs: baseArgs,
      },
    ];
    const accountIndices = Array.from({ length: DEFAULT_PARTICIPANT_COUNT }, (_, index) => index);
    for (let sampleIndex = 0; sampleIndex < sampleCount; sampleIndex += 1) {
      const prng = createPrng(`${seedLabel}:${inputs}:${outputs}:transfer:${fromAccountIndex}:${sampleIndex}`);
      const isSelfTargetSample = sampleIndex === 0;
      const toAccounts = isSelfTargetSample
        ? Array.from({ length: outputs }, () => fromAccountIndex)
        : randomPermutation(prng, accountIndices).slice(0, outputs);
      const extraCommitments = randomInteger(prng, DEFAULT_EXTRA_COMMITMENT_LIMIT + 1);
      const generatorArgs = [
        ...baseArgs,
        '--to-accounts',
        toAccounts.join(','),
        '--extra-commitments',
        String(extraCommitments),
        '--salt-label',
        isSelfTargetSample
          ? `self-${fromAccountIndex}-${sampleIndex}`
          : `sample-${fromAccountIndex}-${sampleIndex}-${randomInteger(prng, 1_000_000)}`,
      ];
      variants.push({
        variantName: isSelfTargetSample
          ? `sample-${String(sampleIndex).padStart(2, '0')}-self-transfer`
          : `sample-${String(sampleIndex).padStart(2, '0')}`,
        generatorArgs,
      });
    }
    return variants;
  },
});

const redeemSpec = (inputs: 1 | 2 | 3 | 4): TestSpec => ({
  functionName: `redeemNotes${inputs}`,
  family: 'redeem',
  buildVariants: (fromAccountIndex, sampleCount, seedLabel) => {
    const baseArgs = [
      '--participants',
      String(DEFAULT_PARTICIPANT_COUNT),
      '--sender',
      String(fromAccountIndex),
      '--inputs',
      String(inputs),
    ];
    const variants: Array<{ variantName: string; generatorArgs: string[] }> = [
      {
        variantName: 'baseline',
        generatorArgs: [...baseArgs, '--receiver', String(FIXED_REDEEM_TO_ACCOUNT)],
      },
    ];
    const accountIndices = Array.from({ length: DEFAULT_PARTICIPANT_COUNT }, (_, index) => index);
    for (let sampleIndex = 0; sampleIndex < sampleCount; sampleIndex += 1) {
      const prng = createPrng(`${seedLabel}:${inputs}:redeem:${fromAccountIndex}:${sampleIndex}`);
      const toAccount = accountIndices[randomInteger(prng, accountIndices.length)] ?? FIXED_REDEEM_TO_ACCOUNT;
      const extraCommitments = randomInteger(prng, DEFAULT_EXTRA_COMMITMENT_LIMIT + 1);
      const generatorArgs = [...baseArgs, '--receiver', String(toAccount)];
      if (extraCommitments > 0) {
        generatorArgs.push('--extra-commitments', String(extraCommitments));
      }
      variants.push({
        variantName: `sample-${String(sampleIndex).padStart(2, '0')}`,
        generatorArgs,
      });
    }
    return variants;
  },
});

const TEST_SPECS: Record<string, TestSpec> = {
  mintNotes1: mintSpec(1),
  mintNotes2: mintSpec(2),
  mintNotes3: mintSpec(3),
  mintNotes4: mintSpec(4),
  mintNotes5: mintSpec(5),
  mintNotes6: mintSpec(6),
  transferNotes1To1: transferSpec(1, 1),
  transferNotes1To2: transferSpec(1, 2),
  transferNotes1To3: transferSpec(1, 3),
  transferNotes2To1: transferSpec(2, 1),
  transferNotes2To2: transferSpec(2, 2),
  transferNotes3To1: transferSpec(3, 1),
  transferNotes3To2: transferSpec(3, 2),
  transferNotes4To1: transferSpec(4, 1),
  redeemNotes1: redeemSpec(1),
  redeemNotes2: redeemSpec(2),
  redeemNotes3: redeemSpec(3),
  redeemNotes4: redeemSpec(4),
};

const runCommand = (
  command: string,
  args: string[],
  cwd: string,
  env: NodeJS.ProcessEnv = process.env,
): Promise<void> =>
  new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env,
      stdio: 'inherit',
    });

    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code ?? 'unknown'}`));
      }
    });
  });

const writeJson = async (filePath: string, value: unknown) => {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
};

const writeText = async (filePath: string, value: string) => {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, `${value}\n`, 'utf8');
};

const deriveParticipantKeys = (participants: ParticipantEntry[]): DerivedParticipantKeys => {
  const privateKeys: Uint8Array[] = [];
  const publicKeys: EdwardsPoint[] = [];

  for (const participant of participants) {
    const signature = addHexPrefix(
      bytesToHex(jubjub.utils.randomPrivateKey(setLengthLeft(utf8ToBytes(participant.prvSeedL2), 32))),
    ) as `0x${string}`;
    const keySet = deriveL2KeysFromSignature(signature);
    privateKeys.push(keySet.privateKey);
    publicKeys.push(jubjub.Point.fromBytes(keySet.publicKey));
  }

  return { privateKeys, publicKeys };
};

const assignChannelId = (
  stateManager: Awaited<ReturnType<typeof createTokamakL2StateManagerFromL1RPC>>,
  channelId: number,
) => {
  (
    stateManager as Awaited<ReturnType<typeof createTokamakL2StateManagerFromL1RPC>> & {
      _channelId?: number;
    }
  )._channelId = channelId;
};

const buildStateSnapshot = async (
  stateManager: Awaited<ReturnType<typeof createTokamakL2StateManagerFromL1RPC>>,
): Promise<StateSnapshot> => {
  assignChannelId(stateManager, DEFAULT_CHANNEL_ID);
  return stateManager.captureStateSnapshot();
};

const loadJson = async <T>(filePath: string): Promise<T> =>
  JSON.parse(await fs.readFile(filePath, 'utf8')) as T;

const toRpcHex = (value: number): `0x${string}` => ethers.toQuantity(ethers.toBigInt(value));

const rpcCall = async <T>(rpcUrl: string, method: string, params: unknown[]): Promise<T> => {
  const response = await fetch(rpcUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method,
      params,
    }),
  });
  const payload = await response.json() as { result?: T; error?: { message?: string } };
  if (!response.ok || payload.error !== undefined || payload.result === undefined) {
    throw new Error(`RPC ${method} failed: ${payload.error?.message ?? response.statusText}`);
  }
  return payload.result;
};

type RpcBlock = {
  number: `0x${string}`;
  timestamp: `0x${string}`;
  miner: `0x${string}`;
  prevRandao?: `0x${string}`;
  difficulty?: `0x${string}`;
  gasLimit: `0x${string}`;
  baseFeePerGas?: `0x${string}`;
  hash: `0x${string}`;
};

const getBlockInfoFromRpc = async (
  rpcUrl: string,
  blockNumber: number,
  prevHashCount: number,
): Promise<SynthesizerBlockInfo> => {
  const blockTag = toRpcHex(blockNumber);
  const block = await rpcCall<RpcBlock | null>(rpcUrl, 'eth_getBlockByNumber', [blockTag, false]);
  if (block === null) {
    throw new Error(`Unable to fetch block ${blockNumber}`);
  }

  const prevBlockHashes: `0x${string}`[] = [];
  for (let offset = 1; offset <= prevHashCount; offset += 1) {
    const previousBlock = await rpcCall<RpcBlock | null>(rpcUrl, 'eth_getBlockByNumber', [toRpcHex(blockNumber - offset), false]);
    if (previousBlock?.hash === undefined) {
      throw new Error(`Unable to fetch previous block hash for block ${blockNumber - offset}`);
    }
    prevBlockHashes.push(previousBlock.hash);
  }

  const chainId = await rpcCall<`0x${string}`>(rpcUrl, 'eth_chainId', []);
  return {
    coinBase: block.miner,
    timeStamp: block.timestamp,
    blockNumber: block.number,
    prevRanDao: block.prevRandao ?? block.difficulty ?? '0x0',
    gasLimit: block.gasLimit,
    chainId,
    selfBalance: '0x0',
    baseFee: block.baseFeePerGas ?? '0x0',
    prevBlockHashes,
  };
};

const buildStateManagerAndConfig = async (configPath: string) => {
  const config = await loadJson<BaseCompatConfig>(configPath);
  const rpcUrl = process.env.ANVIL_RPC_URL?.trim() || DEFAULT_ANVIL_RPC_URL;
  const stateManagerOpts = createStateManagerOptsFromChannelConfig({
    network: config.network,
    participants: config.participants,
    storageConfigs: config.storageConfigs,
    callCodeAddresses: config.callCodeAddresses,
    blockNumber: config.blockNumber,
  } satisfies ChannelStateConfig);
  const stateManager = await createTokamakL2StateManagerFromL1RPC(rpcUrl, stateManagerOpts);
  return { config, rpcUrl, stateManagerOpts, stateManager };
};

const buildTransactionRlp = (
  config: BaseCompatConfig,
  transactionNonceOverride?: bigint,
): `0x${string}` => {
  const keyMaterial = deriveParticipantKeys(config.participants);
  const fromAccountIndex = config.senderIndex;
  const fromAccountPrivateKey = keyMaterial.privateKeys[fromAccountIndex];
  const fromAccountPublicKey = keyMaterial.publicKeys[fromAccountIndex];
  if (fromAccountPrivateKey === undefined || fromAccountPublicKey === undefined) {
    throw new Error(`fromAccountIndex must point to an existing participant; got ${fromAccountIndex}`);
  }

  const txData: TokamakL2TxData = {
    nonce: transactionNonceOverride ?? ethers.toBigInt(config.txNonce),
    to: createAddressFromString(config.function.entryContractAddress),
    data: hexToBytes(addHexPrefix(config.calldata)),
    senderPubKey: fromAccountPublicKey.toBytes(),
  };
  const transaction = createTokamakL2Tx(txData, { common: createTokamakL2Common() }).sign(fromAccountPrivateKey);
  return addHexPrefix(bytesToHex(transaction.serialize())) as `0x${string}`;
};

const fetchContractCodes = async (
  rpcUrl: string,
  callCodeAddresses: `0x${string}`[],
  blockNumber: number,
) => Promise.all(
    callCodeAddresses.map(async (address) => ({
      address,
      code: await rpcCall<`0x${string}`>(rpcUrl, 'eth_getCode', [address, toRpcHex(blockNumber)]),
    })),
  );

const createCliInputBundle = async (
  configPath: string,
  overrides: CliInputOverrides = {},
): Promise<CliInputBundle> => {
  const { config, rpcUrl, stateManagerOpts, stateManager } = await buildStateManagerAndConfig(configPath);
  const blockInfo = overrides.blockInfo ?? await getBlockInfoFromRpc(rpcUrl, config.blockNumber, FIXED_PREV_BLOCK_HASH_COUNT);
  const contractCodes = await fetchContractCodes(rpcUrl, config.callCodeAddresses, config.blockNumber);
  const transactionRlp = buildTransactionRlp(config, overrides.transactionNonce);

  return {
    previousState: await buildStateSnapshot(stateManager),
    blockInfo,
    contractCodes,
    transactionRlp,
  };
};

const buildMutatedBlockInfo = (
  baseBlockInfo: SynthesizerBlockInfo,
  seedLabel: string,
  fromAccountIndex: number,
  sampleIndex: number,
): SynthesizerBlockInfo => {
  const prng = createPrng(`${seedLabel}:block-info:${fromAccountIndex}:${sampleIndex}`);
  const nextBlockNumber = ethers.toBigInt(baseBlockInfo.blockNumber) + ethers.toBigInt(sampleIndex + 1);
  const nextTimestamp = ethers.toBigInt(baseBlockInfo.timeStamp) + ethers.toBigInt((sampleIndex + 1) * 17);
  const nextBaseFee = ethers.toBigInt(baseBlockInfo.baseFee) + ethers.toBigInt(sampleIndex + 1);
  return {
    ...baseBlockInfo,
    blockNumber: `0x${nextBlockNumber.toString(16)}`,
    timeStamp: `0x${nextTimestamp.toString(16)}`,
    baseFee: `0x${nextBaseFee.toString(16)}`,
    prevRanDao: randomHexWord(prng),
    prevBlockHashes: Array.from({ length: FIXED_PREV_BLOCK_HASH_COUNT }, () => randomHexWord(prng)),
  };
};

const readResultSnapshot = async (): Promise<TestResultSnapshot> => {
  const instancePath = path.resolve(synthesizerOutputsDir, 'instance.json');
  const permutationPath = path.resolve(synthesizerOutputsDir, 'permutation.json');
  const instance = await loadJson<{ a_pub_function: unknown }>(instancePath);
  const permutation = await loadJson<unknown>(permutationPath);
  return {
    aPubFunction: instance.a_pub_function,
    permutation,
  };
};

const compareStableOutputs = (
  functionName: string,
  fromAccountIndex: number,
  variantName: string,
  baseline: TestResultSnapshot,
  candidate: TestResultSnapshot,
) => {
  if (JSON.stringify(baseline.aPubFunction) !== JSON.stringify(candidate.aPubFunction)) {
    throw new Error(`${functionName}: a_pub_function changed for fromAccount ${fromAccountIndex} variant ${variantName}`);
  }
  if (JSON.stringify(baseline.permutation) !== JSON.stringify(candidate.permutation)) {
    throw new Error(`${functionName}: permutation changed for fromAccount ${fromAccountIndex} variant ${variantName}`);
  }
};

const bootstrapAnvil = async () => {
  await runCommand('make', ['-C', privateStateAppDir, 'anvil-stop'], repoRoot);
  await runCommand('make', ['-C', privateStateAppDir, 'anvil-start'], repoRoot);
  await runCommand('make', ['-C', privateStateAppDir, 'anvil-bootstrap'], repoRoot);
};

const parseOptions = (argv: string[]) => {
  const options = {
    skipBootstrap: false,
    fromAccounts: [...DEFAULT_FROM_ACCOUNT_SET],
    samples: DEFAULT_RANDOM_SAMPLE_COUNT,
    seed: DEFAULT_RANDOM_SEED,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    const next = argv[index + 1];
    const consumeValue = (label: string) => {
      if (!next) {
        throw new Error(`Missing value for ${label}`);
      }
      index += 1;
      return next;
    };
    switch (current) {
      case '--skip-bootstrap':
        options.skipBootstrap = true;
        break;
      case '--from-accounts': {
        options.fromAccounts = consumeValue('--from-accounts').split(',').map((value) => {
          const parsed = Number(value.trim());
          if (!Number.isInteger(parsed)) {
            throw new Error(`Invalid fromAccount index: ${value}`);
          }
          return parsed;
        });
        break;
      }
      case '--samples': {
        const parsed = Number(consumeValue('--samples'));
        if (!Number.isInteger(parsed) || parsed < 0) {
          throw new Error('--samples must be a non-negative integer');
        }
        options.samples = parsed;
        break;
      }
      case '--seed':
        options.seed = consumeValue('--seed');
        break;
      default:
        throw new Error(`Unknown argument: ${current}`);
    }
  }

  if (options.fromAccounts.length === 0) {
    throw new Error('At least one fromAccount index must be provided');
  }

  return options;
};

const executeSynthesizerCli = async (
  previousStatePath: string,
  transactionRlp: `0x${string}`,
  blockInfoPath: string,
  contractCodesPath: string,
) => {
  await runCommand(
    'npx',
    [
      'tsx',
      '--tsconfig',
      synthesizerTsconfigPath,
      synthesizerCliPath,
      'tokamak-ch-tx',
      '--previous-state',
      previousStatePath,
      '--transaction',
      transactionRlp,
      '--block-info',
      blockInfoPath,
      '--contract-code',
      contractCodesPath,
    ],
    synthesizerRoot,
  );
};

export const runPrivateStateSynthesizerCompatTest = async (
  functionName: string,
  argv: string[] = process.argv.slice(2),
) => {
  const spec = TEST_SPECS[functionName];
  if (!spec) {
    throw new Error(`Unsupported private-state function: ${functionName}`);
  }

  const options = parseOptions(argv);
  if (!options.skipBootstrap) {
    await bootstrapAnvil();
  }

  const workDir = path.join(generatedArtifactsRoot, functionName);
  await fs.rm(workDir, { recursive: true, force: true });
  await fs.mkdir(workDir, { recursive: true });
  const fixedDir = path.join(workDir, 'fixed');

  const buildCaseFiles = async (fromAccountIndex: number, variantName: string, generatorArgs: string[]) => {
    const caseDir = path.join(workDir, `from-account-${fromAccountIndex}`, variantName);
    const configPath = path.join(caseDir, 'config.json');
    const previousStatePath = path.join(caseDir, 'previous_state_snapshot.json');
    const transactionPath = path.join(caseDir, 'transaction_rlp.txt');
    await fs.mkdir(caseDir, { recursive: true });

    const generatorPath =
      spec.family === 'mint'
        ? mintGeneratorPath
        : spec.family === 'transfer'
          ? transferGeneratorPath
          : redeemGeneratorPath;

    await runCommand(
      'npx',
      ['tsx', '--tsconfig', synthesizerTsconfigPath, generatorPath, '--output', configPath, ...generatorArgs],
      repoRoot,
    );

    const cliInput = await createCliInputBundle(configPath);
    await writeJson(previousStatePath, cliInput.previousState);
    await writeText(transactionPath, cliInput.transactionRlp);

    return {
      fromAccountIndex,
      variantName,
      previousStatePath,
      cliInput,
    };
  };
  await fs.mkdir(fixedDir, { recursive: true });

  let baseline: TestResultSnapshot | null = null;
  let fixedBlockInfoPath = path.join(fixedDir, 'block_info.json');
  let fixedContractCodesPath = path.join(fixedDir, 'contract_codes.json');
  for (const fromAccountIndex of options.fromAccounts) {
    const variants = spec.buildVariants(fromAccountIndex, options.samples, options.seed);
    for (const variant of variants) {
      const testCase = await buildCaseFiles(fromAccountIndex, variant.variantName, variant.generatorArgs);
      if (baseline === null) {
        await writeJson(fixedBlockInfoPath, testCase.cliInput.blockInfo);
        await writeJson(fixedContractCodesPath, testCase.cliInput.contractCodes);
      }
      await executeSynthesizerCli(
        testCase.previousStatePath,
        testCase.cliInput.transactionRlp,
        fixedBlockInfoPath,
        fixedContractCodesPath,
      );

      const snapshot = await readResultSnapshot();
      if (baseline === null) {
        baseline = snapshot;
        console.log(`${functionName}: established baseline with fromAccount ${fromAccountIndex} variant ${variant.variantName}`);
        continue;
      }
      compareStableOutputs(functionName, fromAccountIndex, variant.variantName, baseline, snapshot);
      console.log(`${functionName}: fromAccount ${fromAccountIndex} variant ${variant.variantName} matched baseline`);
    }
  }

  console.log(`${functionName}: compatibility check passed for fromAccounts ${options.fromAccounts.join(', ')}`);
};

export const runPrivateStateSynthesizerBlockNonceCompatTest = async (
  functionName: string,
  argv: string[] = process.argv.slice(2),
) => {
  const spec = TEST_SPECS[functionName];
  if (!spec) {
    throw new Error(`Unsupported private-state function: ${functionName}`);
  }

  const options = parseOptions(argv);
  if (!options.skipBootstrap) {
    await bootstrapAnvil();
  }

  const workDir = path.join(generatedArtifactsRoot, `${functionName}-block-nonce`);
  await fs.rm(workDir, { recursive: true, force: true });
  await fs.mkdir(workDir, { recursive: true });
  const fixedDir = path.join(workDir, 'fixed');
  await fs.mkdir(fixedDir, { recursive: true });
  const previousStatePath = path.join(fixedDir, 'previous_state_snapshot.json');
  const contractCodesPath = path.join(fixedDir, 'contract_codes.json');

  const generatorPath =
    spec.family === 'mint'
      ? mintGeneratorPath
      : spec.family === 'transfer'
        ? transferGeneratorPath
        : redeemGeneratorPath;

  let baseline: TestResultSnapshot | null = null;
  for (const fromAccountIndex of options.fromAccounts) {
    const baselineVariant = spec.buildVariants(fromAccountIndex, 0, options.seed)[0];
    if (!baselineVariant) {
      throw new Error(`Missing baseline variant for ${functionName}`);
    }

    const caseDir = path.join(workDir, `from-account-${fromAccountIndex}`);
    const configPath = path.join(caseDir, 'config.json');
    await fs.mkdir(caseDir, { recursive: true });

    await runCommand(
      'npx',
      ['tsx', '--tsconfig', synthesizerTsconfigPath, generatorPath, '--output', configPath, ...baselineVariant.generatorArgs],
      repoRoot,
    );

    const baseCliInput = await createCliInputBundle(configPath);
    if (baseline === null) {
      await writeJson(previousStatePath, baseCliInput.previousState);
      await writeJson(contractCodesPath, baseCliInput.contractCodes);
    }

    for (let sampleIndex = 0; sampleIndex <= options.samples; sampleIndex += 1) {
      const variantName = sampleIndex === 0 ? 'baseline' : `sample-${String(sampleIndex - 1).padStart(2, '0')}`;
      const blockInfo = sampleIndex === 0
        ? baseCliInput.blockInfo
        : buildMutatedBlockInfo(baseCliInput.blockInfo, options.seed, fromAccountIndex, sampleIndex);
      const transactionRlp = baseCliInput.transactionRlp;
      const blockInfoPath = path.join(caseDir, `${variantName}-block_info.json`);
      const transactionPath = path.join(caseDir, `${variantName}-transaction_rlp.txt`);

      await writeJson(blockInfoPath, blockInfo);
      await writeText(transactionPath, transactionRlp);
      await executeSynthesizerCli(previousStatePath, transactionRlp, blockInfoPath, contractCodesPath);

      const snapshot = await readResultSnapshot();
      if (baseline === null) {
        baseline = snapshot;
        console.log(`${functionName}: established block/nonce baseline with fromAccount ${fromAccountIndex}`);
        continue;
      }
      compareStableOutputs(functionName, fromAccountIndex, `block-nonce-${variantName}`, baseline, snapshot);
      console.log(`${functionName}: fromAccount ${fromAccountIndex} block/nonce variant ${variantName} matched baseline`);
    }
  }

  console.log(`${functionName}: block/nonce compatibility check passed for fromAccounts ${options.fromAccounts.join(', ')}`);
};

export const PRIVATE_STATE_SYNTH_COMPAT_FUNCTIONS = Object.keys(TEST_SPECS);
