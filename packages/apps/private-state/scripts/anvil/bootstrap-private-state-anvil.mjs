#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parse as parseDotenv } from "dotenv";
import { resolveAppNetwork } from "@tokamak-private-dapps/common-library/network-config";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../../../..");
const envFile = process.env.APPS_ENV_FILE ?? path.join(projectRoot, "packages", "apps", ".env");
const tempEnvFile = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-anvil-"));
const tempEnvPath = path.join(tempEnvFile, "apps.env");
const defaultAnvilDeployerPrivateKey =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

try {
  loadEnvFileIfExists(envFile);

  const rpcUrl = process.env.APPS_RPC_URL_OVERRIDE ?? "http://127.0.0.1:8545";
  const network = resolveAppNetwork("anvil");
  const deployerPrivateKey = normalizePrivateKey(
    process.env.APPS_ANVIL_DEPLOYER_PRIVATE_KEY ?? defaultAnvilDeployerPrivateKey,
  );

  if (!(await isRpcReachable(rpcUrl))) {
    throw new Error(`anvil is not reachable at ${rpcUrl}`);
  }

  fs.writeFileSync(tempEnvPath, [
    "APPS_NETWORK=anvil",
    `APPS_DEPLOYER_PRIVATE_KEY=${deployerPrivateKey}`,
    "",
  ].join("\n"));

  const childEnv = {
    ...process.env,
    APPS_ENV_FILE: tempEnvPath,
    APPS_RPC_URL_OVERRIDE: rpcUrl,
    APPS_DEPLOYER_PRIVATE_KEY: deployerPrivateKey,
  };

  run("node", [
    path.join(projectRoot, "packages", "apps", "private-state", "scripts", "deploy", "deploy-private-state.mjs"),
  ], { env: childEnv });
  run("node", [
    path.join(projectRoot, "packages", "apps", "private-state", "scripts", "deploy", "write-deploy-artifacts.mjs"),
    String(network.chainId),
  ], { env: childEnv });

  const deployerAddress = runCapture("cast", ["wallet", "address", "--private-key", deployerPrivateKey], {
    env: childEnv,
  }).trim();

  console.log("Bootstrapped private-state on anvil");
  console.log(`RPC URL: ${rpcUrl}`);
  console.log(`Anvil deployer: ${deployerAddress}`);
  console.log(`Deployment snapshots root: ${path.join(projectRoot, "deployment", `chain-id-${network.chainId}`, "dapps", "private-state")}/`);
} finally {
  fs.rmSync(tempEnvFile, { recursive: true, force: true });
}

function loadEnvFileIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return;
  }
  Object.assign(process.env, parseDotenv(fs.readFileSync(filePath)));
}

async function isRpcReachable(rpcUrl) {
  try {
    const response = await fetch(rpcUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", method: "eth_chainId", params: [], id: 1 }),
    });
    return response.ok;
  } catch {
    return false;
  }
}

function normalizePrivateKey(value) {
  return String(value).startsWith("0x") ? String(value) : `0x${value}`;
}

function run(command, args, { env = process.env } = {}) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    env,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} exited with code ${result.status ?? "unknown"}.`);
  }
}

function runCapture(command, args, { env = process.env } = {}) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    env,
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
  return result.stdout;
}
