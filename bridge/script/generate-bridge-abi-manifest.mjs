#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const bridgeRoot = path.resolve(__dirname, "..");
const projectRoot = path.resolve(bridgeRoot, "..");

const artifactMap = {
  bridgeAdminManager: "out/BridgeAdminManager.sol/BridgeAdminManager.json",
  bridgeCore: "out/BridgeCore.sol/BridgeCore.json",
  dAppManager: "out/DAppManager.sol/DAppManager.json",
  channelManager: "out/ChannelManager.sol/ChannelManager.json",
  tokenVault: "out/L1TokenVault.sol/L1TokenVault.json",
  erc20: "out/IERC20.sol/IERC20.json",
};

function parseArgs(argv) {
  const parsed = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      continue;
    }
    const key = token.slice(2);
    const value = argv[i + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`Missing value for --${key}`);
    }
    parsed[key] = value;
    i += 1;
  }
  return parsed;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function resolveBridgePath(inputPath) {
  if (path.isAbsolute(inputPath)) {
    return inputPath;
  }

  const projectRelativePath = path.resolve(projectRoot, inputPath);
  if (fs.existsSync(projectRelativePath) || inputPath.startsWith("bridge/")) {
    return projectRelativePath;
  }

  return path.resolve(bridgeRoot, inputPath);
}

function loadArtifactAbi(relativeArtifactPath) {
  const artifactPath = path.resolve(bridgeRoot, relativeArtifactPath);
  const artifact = readJson(artifactPath);
  if (!Array.isArray(artifact.abi)) {
    throw new Error(`Artifact has no ABI array: ${artifactPath}`);
  }
  return {
    artifactPath: path.relative(bridgeRoot, artifactPath),
    abi: artifact.abi,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const chainId = args["chain-id"] ? Number(args["chain-id"]) : null;
  const defaultOutputPath = chainId === null
    ? "deployments/bridge-abi-manifest.json"
    : `deployments/bridge-abi-manifest.${chainId}.json`;
  const outputPath = resolveBridgePath(args.output ?? defaultOutputPath);
  const deploymentPath = args["deployment-path"] ? resolveBridgePath(args["deployment-path"]) : null;

  const contracts = {};
  for (const [name, relativeArtifactPath] of Object.entries(artifactMap)) {
    contracts[name] = loadArtifactAbi(relativeArtifactPath);
  }

  const manifest = {
    generatedAt: new Date().toISOString(),
    chainId,
    contracts,
  };
  writeJson(outputPath, manifest);

  if (deploymentPath) {
    const deployment = readJson(deploymentPath);
    deployment.chainId = chainId;
    deployment.abiManifestPath = path.relative(bridgeRoot, outputPath);
    writeJson(deploymentPath, deployment);
  }

  process.stdout.write(
    JSON.stringify(
      {
        outputPath,
        chainId,
        deploymentPath,
      },
      null,
      2,
    ),
  );
}

main();
