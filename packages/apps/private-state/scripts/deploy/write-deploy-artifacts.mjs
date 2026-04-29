#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createTimestampLabel, dappArtifactPaths } from "../../../../../scripts/deployment/lib/deployment-layout.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../../../..");
const dappName = process.env.PRIVATE_STATE_DAPP_NAME ?? "private-state";

if (process.argv.length !== 3) {
  console.error("Usage: node packages/apps/private-state/scripts/deploy/write-deploy-artifacts.mjs <chain-id>");
  process.exit(1);
}

const chainId = process.argv[2];
const runFile = path.join(projectRoot, "broadcast", "DeployPrivateState.s.sol", chainId, "run-latest.json");
if (!fs.existsSync(runFile)) {
  console.error(`Missing deployment broadcast file: ${runFile}`);
  process.exit(1);
}

const timestampUtc = process.env.PRIVATE_STATE_ARTIFACT_TIMESTAMP ?? createTimestampLabel();
const artifactPaths = dappArtifactPaths(projectRoot, chainId, dappName, timestampUtc);
const deployDir = artifactPaths.rootDir;
const deploymentLatestPath = artifactPaths.deploymentPath;
const storageLayoutLatestPath = artifactPaths.storageLayoutPath;

fs.mkdirSync(deployDir, { recursive: true });

const run = readJson(runFile);
const transactions = Array.isArray(run.transactions) ? run.transactions : [];
const deployer = transactions.find((entry) => entry?.transaction?.from)?.transaction?.from ?? "";
const deploymentFactory = transactions.find(
  (entry) => entry?.transactionType === "CREATE" && entry?.contractName === "PrivateStateDeploymentFactory",
)?.contractAddress ?? "";
const controller = findAdditionalContractAddress(transactions, "PrivateStateController");
const l2AccountingVault = findAdditionalContractAddress(transactions, "L2AccountingVault");

writeJson(deploymentLatestPath, {
  generatedAtUtc: timestampUtc,
  chainId: Number(chainId),
  deployer,
  contracts: {
    deploymentFactory,
    controller,
    l2AccountingVault,
  },
});

const controllerLayout = runJsonCommand("forge", ["inspect", "--json", "PrivateStateController", "storage-layout"]);
const l2AccountingVaultLayout = runJsonCommand("forge", ["inspect", "--json", "L2AccountingVault", "storage-layout"]);

writeJson(storageLayoutLatestPath, {
  generatedAtUtc: timestampUtc,
  chainId: Number(chainId),
  contracts: {
    PrivateStateController: {
      address: controller,
      sourceName: "packages/apps/private-state/src/PrivateStateController.sol",
      contractName: "PrivateStateController",
      storageLayout: controllerLayout,
    },
    L2AccountingVault: {
      address: l2AccountingVault,
      sourceName: "packages/apps/private-state/src/L2AccountingVault.sol",
      contractName: "L2AccountingVault",
      storageLayout: l2AccountingVaultLayout,
    },
  },
});

writeCallableAbi({
  artifactPath: path.join(projectRoot, "out", "PrivateStateController.sol", "PrivateStateController.json"),
  outputPath: artifactPaths.privateStateControllerAbiPath,
  names: [
    "computeNoteCommitment",
    "computeNullifier",
    "commitmentExists",
    "l2AccountingVault",
    "mintNotes1",
    "mintNotes2",
    "mintNotes3",
    "mintNotes4",
    "mintNotes5",
    "mintNotes6",
    "redeemNotes1",
    "redeemNotes2",
    "redeemNotes3",
    "redeemNotes4",
    "nullifierUsed",
    "transferNotes1To1",
    "transferNotes1To2",
    "transferNotes1To3",
    "transferNotes2To1",
    "transferNotes2To2",
    "transferNotes3To1",
    "transferNotes3To2",
    "transferNotes4To1",
  ],
});

writeCallableAbi({
  artifactPath: path.join(projectRoot, "out", "L2AccountingVault.sol", "L2AccountingVault.json"),
  outputPath: artifactPaths.l2AccountingVaultAbiPath,
  names: [
    "controller",
    "liquidBalances",
  ],
});

console.log(`Updated chain deployment manifest: ${deploymentLatestPath}`);
console.log(`Updated storage layout manifest: ${storageLayoutLatestPath}`);
console.log(`Wrote callable ABI files under: ${deployDir}`);

function findAdditionalContractAddress(transactionsValue, contractName) {
  for (const tx of transactionsValue) {
    for (const contract of tx?.additionalContracts ?? []) {
      if (contract?.contractName === contractName && contract?.address) {
        return contract.address;
      }
    }
  }
  return "";
}

function writeCallableAbi({ artifactPath, outputPath, names }) {
  const artifact = readJson(artifactPath);
  const allowed = new Set(names);
  const abi = (artifact.abi ?? []).filter((entry) => entry.type === "function" && allowed.has(entry.name));
  writeJson(outputPath, abi);
}

function runJsonCommand(command, args) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.status !== 0) {
    throw new Error(
      [
        `${command} ${args.join(" ")} exited with code ${result.status ?? "unknown"}.`,
        result.stdout.trim(),
        result.stderr.trim(),
      ].filter(Boolean).join("\n"),
    );
  }
  return JSON.parse(result.stdout);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}
