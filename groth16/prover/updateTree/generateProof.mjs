#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { ethers } from "ethers";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(import.meta.url);
const grothRoot = path.resolve(__dirname, "../..");
const circuitsDir = path.join(grothRoot, "circuits");
const trustedSetupDir = path.join(grothRoot, "trusted-setup", "crs");
const proverDataDir = path.join(grothRoot, "prover", "updateTree");
const metadataPath = path.join(trustedSetupDir, "metadata.json");
const circuitEntrypointPath = path.join(circuitsDir, "src", "circuit_updateTree.circom");
const circuitBuildDir = path.join(circuitsDir, "build");
const wasmPath = path.join(circuitBuildDir, "circuit_updateTree_js", "circuit_updateTree.wasm");
const zkeyPath = path.join(trustedSetupDir, "circuit_final.zkey");
const verificationKeyPath = path.join(trustedSetupDir, "verification_key.json");
const defaultInputPath = path.join(proverDataDir, "input_example.json");
const defaultProofPath = path.join(proverDataDir, "proof.json");
const defaultPublicPath = path.join(proverDataDir, "public.json");
const witnessPath = path.join(proverDataDir, "witness.wtns");
const fixturePath = path.join(proverDataDir, "solidity_fixture.json");
const tmpDir = path.join(proverDataDir, ".tmp");

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

function ensureCleanDir(dirPath) {
  fs.rmSync(dirPath, { recursive: true, force: true });
  fs.mkdirSync(dirPath, { recursive: true });
}

function ensureFileExists(label, filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
}

function ensureCircuitDependencies() {
  const poseidonCircuit = path.join(
    circuitsDir,
    "node_modules",
    "poseidon-bls12381-circom",
    "circuits",
    "poseidon255.circom",
  );
  if (fs.existsSync(poseidonCircuit)) {
    return;
  }
  run("npm", ["install", "--ignore-scripts"], circuitsDir);
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

function splitFieldElement(value) {
  const normalized = ethers.toBigInt(value);
  const hex = normalized.toString(16).padStart(96, "0");
  return {
    part1: `0x${"0".repeat(32)}${hex.slice(0, 32)}`,
    part2: `0x${hex.slice(32)}`,
  };
}

function buildSolidityFixture(proof, publicSignals) {
  const pA = [
    splitFieldElement(proof.pi_a[0]).part1,
    splitFieldElement(proof.pi_a[0]).part2,
    splitFieldElement(proof.pi_a[1]).part1,
    splitFieldElement(proof.pi_a[1]).part2,
  ];
  const pB = [
    splitFieldElement(proof.pi_b[0][1]).part1,
    splitFieldElement(proof.pi_b[0][1]).part2,
    splitFieldElement(proof.pi_b[0][0]).part1,
    splitFieldElement(proof.pi_b[0][0]).part2,
    splitFieldElement(proof.pi_b[1][1]).part1,
    splitFieldElement(proof.pi_b[1][1]).part2,
    splitFieldElement(proof.pi_b[1][0]).part1,
    splitFieldElement(proof.pi_b[1][0]).part2,
  ];
  const pC = [
    splitFieldElement(proof.pi_c[0]).part1,
    splitFieldElement(proof.pi_c[0]).part2,
    splitFieldElement(proof.pi_c[1]).part1,
    splitFieldElement(proof.pi_c[1]).part2,
  ];
  return {
    pA,
    pB,
    pC,
    pubSignals: publicSignals.map((value) => value.toString()),
  };
}

function assertCircuitDepth(mtDepth) {
  const entrypoint = fs.readFileSync(circuitEntrypointPath, "utf8");
  const expectedSnippet = `updateTree(${mtDepth})`;
  if (!entrypoint.includes(expectedSnippet)) {
    throw new Error(
      `Circuit entrypoint depth mismatch. Expected ${expectedSnippet} in ${circuitEntrypointPath}.`,
    );
  }
}

async function buildExampleInput(outputPath, argv) {
  const resolvedMetadataPath = findFlag(argv, "--metadata") ?? metadataPath;
  const metadata = readJson(resolvedMetadataPath);
  const tokamak = await loadTokamakL2Js(metadata.tokamakL2JsVersion);
  if (tokamak.MT_DEPTH !== metadata.mtDepth) {
    throw new Error(
      `tokamak-l2js MT_DEPTH mismatch: metadata=${metadata.mtDepth}, package=${tokamak.MT_DEPTH}.`,
    );
  }
  assertCircuitDepth(metadata.mtDepth);

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

export async function main(argv = process.argv.slice(2)) {
  const args = normalizeArgv(argv);
  const inputPath = findFlag(args, "--input") ?? defaultInputPath;
  const resolvedMetadataPath = findFlag(args, "--metadata") ?? metadataPath;
  const resolvedWasmPath = findFlag(args, "--wasm") ?? wasmPath;
  const resolvedZkeyPath = findFlag(args, "--zkey") ?? zkeyPath;
  const requestedVerificationKeyPath = findFlag(args, "--verification-key");
  const resolvedWitnessPath = findFlag(args, "--witness-output") ?? witnessPath;
  const proofPath = findFlag(args, "--proof-output") ?? defaultProofPath;
  const publicPath = findFlag(args, "--public-output") ?? defaultPublicPath;
  const resolvedFixturePath = findFlag(args, "--solidity-fixture-output") ?? fixturePath;
  const skipCompile = hasFlag(args, "--skip-compile");

  if (inputPath === defaultInputPath || !fs.existsSync(inputPath)) {
    const metadata = readJson(resolvedMetadataPath);
    assertCircuitDepth(metadata.mtDepth);
    await buildExampleInput(defaultInputPath, args);
  }

  if (!skipCompile) {
    ensureCircuitDependencies();
    run("npm", ["run", "compile"], circuitsDir);
  }

  for (const [label, filePath] of [
    ["updateTree wasm", resolvedWasmPath],
    ["updateTree proving key", resolvedZkeyPath],
  ]) {
    ensureFileExists(label, filePath);
  }

  const snarkjs = findSnarkjs();
  let resolvedVerificationKeyPath = requestedVerificationKeyPath;
  if (resolvedVerificationKeyPath) {
    ensureFileExists("updateTree verification key", resolvedVerificationKeyPath);
  } else if (resolvedZkeyPath === zkeyPath && fs.existsSync(verificationKeyPath)) {
    resolvedVerificationKeyPath = verificationKeyPath;
  } else {
    fs.mkdirSync(tmpDir, { recursive: true });
    resolvedVerificationKeyPath = path.join(tmpDir, "updateTree.verification_key.json");
    run(snarkjs, ["zkey", "export", "verificationkey", resolvedZkeyPath, resolvedVerificationKeyPath], circuitsDir);
  }

  fs.mkdirSync(path.dirname(resolvedWitnessPath), { recursive: true });
  fs.mkdirSync(path.dirname(proofPath), { recursive: true });
  fs.mkdirSync(path.dirname(publicPath), { recursive: true });
  run(snarkjs, ["wtns", "calculate", resolvedWasmPath, inputPath, resolvedWitnessPath], circuitsDir);
  run(snarkjs, ["groth16", "prove", resolvedZkeyPath, resolvedWitnessPath, proofPath, publicPath], circuitsDir);
  run(snarkjs, ["groth16", "verify", resolvedVerificationKeyPath, publicPath, proofPath], circuitsDir);

  const proof = readJson(proofPath);
  const publicSignals = readJson(publicPath);
  if (publicSignals.length !== 5) {
    throw new Error(`Expected 5 public signals for updateTree, got ${publicSignals.length}.`);
  }
  const fixture = buildSolidityFixture(proof, publicSignals);
  fs.mkdirSync(path.dirname(resolvedFixturePath), { recursive: true });
  fs.writeFileSync(resolvedFixturePath, JSON.stringify(fixture, null, 2) + "\n");

  return {
    inputPath,
    witnessPath: resolvedWitnessPath,
    proofPath,
    publicPath,
    verificationKeyPath: resolvedVerificationKeyPath,
    solidityFixturePath: resolvedFixturePath,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
