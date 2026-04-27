#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { ethers } from "ethers";
import { groth16WorkspacePaths } from "../../lib/paths.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(import.meta.url);
const grothRoot = path.resolve(__dirname, "../..");
const circuitsDir = path.join(grothRoot, "circuits");

const UNSUPPORTED_PATH_FLAGS = [
  "--metadata",
  "--wasm",
  "--zkey",
  "--witness-output",
  "--proof-output",
  "--public-output",
  "--solidity-fixture-output",
  "--output",
  "--workspace",
  "--verification-key",
];

function normalizeArgv(argv) {
  return Array.isArray(argv) ? argv : [];
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function findFlag(argv, name) {
  const index = argv.indexOf(name);
  if (index === -1 || index + 1 >= argv.length) {
    return null;
  }
  return path.resolve(process.cwd(), argv[index + 1]);
}

function hasFlag(argv, name) {
  return argv.includes(name);
}

function run(cmd, args, cwd) {
  execFileSync(cmd, args, {
    cwd,
    stdio: "inherit",
  });
}

function ensureFileExists(label, filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
}

function findSnarkjs() {
  const candidates = [
    path.join(circuitsDir, "node_modules", ".bin", "snarkjs"),
    path.join(grothRoot, "node_modules", ".bin", "snarkjs"),
  ];
  const localSnarkjs = candidates.find((candidate) => fs.existsSync(candidate));
  if (localSnarkjs) {
    return localSnarkjs;
  }
  return "snarkjs";
}

async function loadTokamakL2Js(expectedVersion) {
  const entrypoint = require.resolve("tokamak-l2js");
  const packageJsonPath = findPackageJson(path.dirname(entrypoint));
  const packageJson = readJson(packageJsonPath);
  if (packageJson.version !== expectedVersion) {
    throw new Error(`tokamak-l2js version mismatch: metadata=${expectedVersion}, installed=${packageJson.version}.`);
  }
  return import("tokamak-l2js");
}

function findPackageJson(startDir) {
  let current = startDir;
  while (current !== path.dirname(current)) {
    const candidate = path.join(current, "package.json");
    if (fs.existsSync(candidate) && readJson(candidate).name === "tokamak-l2js") {
      return candidate;
    }
    current = path.dirname(current);
  }
  throw new Error(`Cannot locate package.json above ${startDir}.`);
}

async function buildExampleInput(outputPath, metadataPath) {
  const metadata = readJson(metadataPath);
  const tokamak = await loadTokamakL2Js(metadata.tokamakL2JsVersion);
  if (tokamak.MT_DEPTH !== metadata.mtDepth) {
    throw new Error(
      `tokamak-l2js MT_DEPTH mismatch: metadata=${metadata.mtDepth}, package=${tokamak.MT_DEPTH}.`,
    );
  }

  const storageKey = 111n;
  const storageValueBefore = 0n;
  const storageValueAfter = 10n;
  const maxLeaves = ethers.toBigInt(tokamak.POSEIDON_INPUTS ** tokamak.MT_DEPTH);
  const leafIndex = storageKey % maxLeaves;
  const hashPair = (left, right) => tokamak.poseidonChainCompress([left, right]);
  const zeroSubtreeRoots = [0n];
  for (let level = 0; level < metadata.mtDepth; level += 1) {
    zeroSubtreeRoots.push(hashPair(zeroSubtreeRoots[level], zeroSubtreeRoots[level]));
  }
  const proof = zeroSubtreeRoots.slice(0, metadata.mtDepth);
  const computeRoot = (leaf, index, siblings) => {
    let current = leaf;
    for (let level = 0; level < siblings.length; level += 1) {
      const bit = (index >> ethers.toBigInt(level)) & 1n;
      current = bit === 0n ? hashPair(current, siblings[level]) : hashPair(siblings[level], current);
    }
    return current;
  };

  const leafBefore = storageValueBefore;
  const leafAfter = storageValueAfter;
  const rootBefore = computeRoot(leafBefore, leafIndex, proof);
  const rootAfter = computeRoot(leafAfter, leafIndex, proof);

  const input = {
    root_before: rootBefore.toString(),
    root_after: rootAfter.toString(),
    leaf_index: leafIndex.toString(),
    storage_key: storageKey.toString(),
    storage_value_before: storageValueBefore.toString(),
    storage_value_after: storageValueAfter.toString(),
    proof: proof.map((value) => value.toString()),
  };

  fs.writeFileSync(outputPath, JSON.stringify(input, null, 2) + "\n");
}

export async function main(argv = process.argv.slice(2), { workspaceRoot } = {}) {
  const args = normalizeArgv(argv);
  for (const flag of UNSUPPORTED_PATH_FLAGS) {
    if (hasFlag(args, flag)) {
      throw new Error(`${flag} is not supported. Groth16 proof generation writes only to the fixed workspace proof paths.`);
    }
  }
  if (hasFlag(args, "--skip-compile")) {
    throw new Error("--skip-compile is not supported. Install the Groth16 runtime before generating proofs.");
  }

  const paths = groth16WorkspacePaths(workspaceRoot);
  const inputFlagPath = findFlag(args, "--input");
  const providedInput = inputFlagPath ? fs.readFileSync(inputFlagPath, "utf8") : null;

  fs.rmSync(paths.proofDir, { recursive: true, force: true });
  fs.mkdirSync(paths.proofDir, { recursive: true });
  fs.mkdirSync(paths.tmpDir, { recursive: true });
  fs.rmSync(paths.witnessPath, { force: true });

  if (providedInput === null) {
    await buildExampleInput(paths.inputPath, paths.metadataPath);
  } else {
    fs.writeFileSync(paths.inputPath, providedInput, "utf8");
  }

  for (const [label, filePath] of [
    ["Groth16 metadata", paths.metadataPath],
    ["updateTree wasm", paths.wasmPath],
    ["updateTree proving key", paths.zkeyPath],
  ]) {
    ensureFileExists(label, filePath);
  }

  const snarkjs = findSnarkjs();
  run(snarkjs, ["wtns", "calculate", paths.wasmPath, paths.inputPath, paths.witnessPath], circuitsDir);
  run(snarkjs, ["groth16", "prove", paths.zkeyPath, paths.witnessPath, paths.proofPath, paths.publicPath], circuitsDir);

  const publicSignals = readJson(paths.publicPath);
  if (publicSignals.length !== 5) {
    throw new Error(`Expected 5 public signals for updateTree, got ${publicSignals.length}.`);
  }

  fs.rmSync(paths.witnessPath, { force: true });
  const manifest = {
    generatedAt: new Date().toISOString(),
    workspaceRoot: paths.rootDir,
    inputPath: paths.inputPath,
    proofPath: paths.proofPath,
    publicPath: paths.publicPath,
    zkeyPath: paths.zkeyPath,
    metadataPath: paths.metadataPath,
    zkeyProvenancePath: paths.provenancePath,
  };
  fs.writeFileSync(paths.proofManifestPath, JSON.stringify(manifest, null, 2) + "\n", "utf8");

  return manifest;
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
