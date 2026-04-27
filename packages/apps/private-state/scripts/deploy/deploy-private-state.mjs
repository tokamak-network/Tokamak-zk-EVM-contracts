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
const inputEnv = pickInputEnv();

if (!fs.existsSync(envFile)) {
  console.error(`Missing ${envFile}`);
  process.exit(1);
}

Object.assign(process.env, parseDotenv(fs.readFileSync(envFile)), inputEnv);

if (process.env.APPS_DEPLOYER_PRIVATE_KEY) {
  process.env.APPS_DEPLOYER_PRIVATE_KEY = normalizePrivateKey(process.env.APPS_DEPLOYER_PRIVATE_KEY);
}

const verify = process.argv.slice(2).includes("--verify");
const requiredVars = ["APPS_DEPLOYER_PRIVATE_KEY", "APPS_NETWORK"];
if (!process.env.APPS_RPC_URL_OVERRIDE && process.env.APPS_NETWORK !== "anvil") {
  requiredVars.push("APPS_ALCHEMY_API_KEY");
}

for (const varName of requiredVars) {
  if (!process.env[varName]) {
    console.error(`Missing required environment variable: ${varName}`);
    process.exit(1);
  }
}

if (verify && !process.env.APPS_ETHERSCAN_API_KEY) {
  console.error("APPS_ETHERSCAN_API_KEY is required when --verify is used");
  process.exit(1);
}

const network = resolveAppNetwork(process.env.APPS_NETWORK);
const rpcUrl = deriveRpcUrl({
  networkName: process.env.APPS_NETWORK,
  alchemyApiKey: process.env.APPS_ALCHEMY_API_KEY,
  rpcUrlOverride: process.env.APPS_RPC_URL_OVERRIDE,
});
const networkLabel = process.env.APPS_RPC_URL_OVERRIDE
  ? "<override>"
  : process.env.APPS_NETWORK === "anvil"
    ? "anvil-localhost"
    : network.alchemyNetwork;

const forgeArgs = [
  "script",
  "packages/apps/private-state/scripts/deploy/DeployPrivateState.s.sol:DeployPrivateStateScript",
  "--rpc-url", rpcUrl,
  "--broadcast",
];
if (verify) {
  forgeArgs.push("--verify", "--etherscan-api-key", process.env.APPS_ETHERSCAN_API_KEY);
}

console.log(`Deploying private-state to network ${process.env.APPS_NETWORK} (chain ID ${network.chainId})`);
console.log(`RPC network label: ${networkLabel}`);
console.log("Owner: <deployer>");
console.log(`Environment file: ${envFile}`);

const result = spawnSync("forge", forgeArgs, {
  cwd: projectRoot,
  env: process.env,
  stdio: "inherit",
});
process.exit(result.status ?? 1);

function pickInputEnv() {
  const names = [
    "APPS_DEPLOYER_PRIVATE_KEY",
    "APPS_NETWORK",
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

function normalizePrivateKey(value) {
  return String(value).startsWith("0x") ? String(value) : `0x${value}`;
}
