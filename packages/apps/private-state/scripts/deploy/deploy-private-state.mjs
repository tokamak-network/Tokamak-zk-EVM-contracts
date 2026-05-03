#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parse as parseDotenv } from "dotenv";
import { deriveRpcUrl, resolveAppNetwork } from "@tokamak-private-dapps/common-library/network-config";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../../../..");
const envFile = process.env.APPS_ENV_FILE ?? path.join(projectRoot, "packages", "apps", ".env");
const writeDeployArtifactsScriptPath = path.join(__dirname, "write-deploy-artifacts.mjs");
const inputEnv = pickInputEnv();
const options = parseCliOptions(process.argv.slice(2));

if (!fs.existsSync(envFile)) {
  console.error(`Missing ${envFile}`);
  process.exit(1);
}

Object.assign(process.env, parseDotenv(fs.readFileSync(envFile)), inputEnv);

if (process.env.APPS_DEPLOYER_PRIVATE_KEY) {
  process.env.APPS_DEPLOYER_PRIVATE_KEY = normalizePrivateKey(process.env.APPS_DEPLOYER_PRIVATE_KEY);
}

const requiredVars = ["APPS_DEPLOYER_PRIVATE_KEY"];
if (!process.env.APPS_RPC_URL_OVERRIDE && options.network !== "anvil") {
  requiredVars.push("APPS_ALCHEMY_API_KEY");
}

for (const varName of requiredVars) {
  if (!process.env[varName]) {
    console.error(`Missing required environment variable: ${varName}`);
    process.exit(1);
  }
}

if (options.verify && !process.env.APPS_ETHERSCAN_API_KEY) {
  console.error("APPS_ETHERSCAN_API_KEY is required when --verify is used");
  process.exit(1);
}

const network = resolveAppNetwork(options.network);
const rpcUrl = deriveRpcUrl({
  networkName: options.network,
  alchemyApiKey: process.env.APPS_ALCHEMY_API_KEY,
  rpcUrlOverride: process.env.APPS_RPC_URL_OVERRIDE,
});
const networkLabel = process.env.APPS_RPC_URL_OVERRIDE
  ? "<override>"
  : options.network === "anvil"
    ? "anvil-localhost"
    : network.alchemyNetwork;

const forgeArgs = [
  "script",
  "packages/apps/private-state/scripts/deploy/DeployPrivateState.s.sol:DeployPrivateStateScript",
  "--rpc-url", rpcUrl,
  "--broadcast",
];
if (options.verify) {
  forgeArgs.push("--verify", "--etherscan-api-key", process.env.APPS_ETHERSCAN_API_KEY);
}

console.log(`Deploying private-state to network ${options.network} (chain ID ${network.chainId})`);
console.log(`RPC network label: ${networkLabel}`);
console.log("Owner: <deployer>");
console.log(`Environment file: ${envFile}`);

const result = spawnSync("forge", forgeArgs, {
  cwd: projectRoot,
  env: process.env,
  stdio: "inherit",
});
if (result.error) {
  throw result.error;
}
if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

const artifactResult = spawnSync("node", [writeDeployArtifactsScriptPath, String(network.chainId)], {
  cwd: projectRoot,
  env: process.env,
  stdio: "inherit",
});
if (artifactResult.error) {
  throw artifactResult.error;
}
process.exit(artifactResult.status ?? 1);

function pickInputEnv() {
  const names = [
    "APPS_DEPLOYER_PRIVATE_KEY",
    "APPS_ALCHEMY_API_KEY",
    "APPS_RPC_URL_OVERRIDE",
    "APPS_ETHERSCAN_API_KEY",
  ];
  return Object.fromEntries(
    names
      .filter((name) => process.env[name])
      .map((name) => [name, process.env[name]]),
  );
}

function parseCliOptions(argv) {
  try {
    return parseArgs(argv);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}

function parseArgs(argv) {
  const options = {
    network: null,
    verify: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    const next = argv[index + 1];
    switch (current) {
      case "--network":
        if (!next || next.startsWith("--")) {
          throw new Error("Missing value for --network.");
        }
        options.network = next;
        index += 1;
        break;
      case "--verify":
        options.verify = true;
        break;
      case "--help":
      case "-h":
        console.log(`Usage:
  node packages/apps/private-state/scripts/deploy/deploy-private-state.mjs --network <anvil|sepolia|mainnet> [--verify]

Options:
  --network <name>  Deployment network. Supported values: anvil, sepolia, mainnet
  --verify          Verify contracts on Etherscan-compatible explorer`);
        process.exit(0);
      default:
        throw new Error(`Unknown option: ${current}`);
    }
  }

  if (!options.network) {
    throw new Error("Missing required argument: --network <anvil|sepolia|mainnet>.");
  }

  return options;
}

function normalizePrivateKey(value) {
  return String(value).startsWith("0x") ? String(value) : `0x${value}`;
}
