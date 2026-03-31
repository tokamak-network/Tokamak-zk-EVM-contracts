#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const grothRoot = path.join(repoRoot, "groth16");
const circuitsDir = path.join(grothRoot, "circuits");
const trustedSetupDir = path.join(grothRoot, "trusted-setup", "updateTree");
const metadataPath = path.join(trustedSetupDir, "metadata.json");
const circuitEntrypointPath = path.join(circuitsDir, "src", "circuit_updateTree.circom");
const circuitBuildDir = path.join(circuitsDir, "build");
const wasmPath = path.join(circuitBuildDir, "circuit_updateTree_js", "circuit_updateTree.wasm");
const zkeyPath = path.join(trustedSetupDir, "circuit_final.zkey");
const verificationKeyPath = path.join(trustedSetupDir, "verification_key.json");
const defaultInputPath = path.join(__dirname, "input_example.json");
const proofPath = path.join(__dirname, "proof.json");
const publicPath = path.join(__dirname, "public.json");
const witnessPath = path.join(__dirname, "witness.wtns");
const fixturePath = path.join(__dirname, "solidity_fixture.json");
const tmpDir = path.join(__dirname, ".tmp");

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function findFlag(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    return null;
  }
  return path.resolve(process.cwd(), process.argv[index + 1]);
}

function hasFlag(name) {
  return process.argv.includes(name);
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

function findSnarkjs() {
  const localSnarkjs = path.join(circuitsDir, "node_modules", ".bin", "snarkjs");
  if (fs.existsSync(localSnarkjs)) {
    return localSnarkjs;
  }
  return "snarkjs";
}

async function loadTokamakL2Js(expectedVersion) {
  fs.mkdirSync(tmpDir, { recursive: true });
  const installRoot = path.join(tmpDir, `tokamak-l2js-${expectedVersion}`);
  if (!fs.existsSync(path.join(installRoot, "node_modules", "tokamak-l2js", "dist", "index.js"))) {
    ensureCleanDir(installRoot);
    run("npm", ["init", "-y"], installRoot);
    run("npm", ["install", `tokamak-l2js@${expectedVersion}`], installRoot);
  }
  const entrypoint = path.join(installRoot, "node_modules", "tokamak-l2js", "dist", "index.js");
  return import(pathToFileURL(entrypoint).href);
}

function splitFieldElement(value) {
  const normalized = BigInt(value);
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

async function buildExampleInput(outputPath) {
  const resolvedMetadataPath = findFlag("--metadata") ?? metadataPath;
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
  const maxLeaves = BigInt(tokamak.POSEIDON_INPUTS ** tokamak.MT_DEPTH);
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
      const bit = (index >> BigInt(level)) & 1n;
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

async function main() {
  const inputPath = findFlag("--input") ?? defaultInputPath;
  const resolvedMetadataPath = findFlag("--metadata") ?? metadataPath;
  const resolvedWasmPath = findFlag("--wasm") ?? wasmPath;
  const resolvedZkeyPath = findFlag("--zkey") ?? zkeyPath;
  const resolvedVerificationKeyPath = findFlag("--verification-key") ?? verificationKeyPath;
  const skipCompile = hasFlag("--skip-compile");
  const metadata = readJson(resolvedMetadataPath);

  if (inputPath === defaultInputPath || !fs.existsSync(inputPath)) {
    assertCircuitDepth(metadata.mtDepth);
    await buildExampleInput(defaultInputPath);
  }

  if (!skipCompile) {
    assertCircuitDepth(metadata.mtDepth);
    run("npm", ["run", "compile"], circuitsDir);
  }

  for (const [label, filePath] of [
    ["updateTree wasm", resolvedWasmPath],
    ["updateTree proving key", resolvedZkeyPath],
    ["updateTree verification key", resolvedVerificationKeyPath],
  ]) {
    if (!fs.existsSync(filePath)) {
      throw new Error(`Missing ${label}: ${filePath}`);
    }
  }

  const snarkjs = findSnarkjs();
  run(snarkjs, ["wtns", "calculate", resolvedWasmPath, inputPath, witnessPath], circuitsDir);
  run(snarkjs, ["groth16", "prove", resolvedZkeyPath, witnessPath, proofPath, publicPath], circuitsDir);
  run(snarkjs, ["groth16", "verify", resolvedVerificationKeyPath, publicPath, proofPath], circuitsDir);

  const proof = readJson(proofPath);
  const publicSignals = readJson(publicPath);
  if (publicSignals.length !== 5) {
    throw new Error(`Expected 5 public signals for updateTree, got ${publicSignals.length}.`);
  }
  const fixture = buildSolidityFixture(proof, publicSignals);
  fs.writeFileSync(fixturePath, JSON.stringify(fixture, null, 2) + "\n");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
