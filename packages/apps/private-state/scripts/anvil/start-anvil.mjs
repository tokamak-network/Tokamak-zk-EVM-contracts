#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parse as parseDotenv } from "dotenv";
import { resolveAppNetwork } from "@tokamak-private-dapps/common-library/network-config";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../../../..");
const envFile = process.env.APPS_ENV_FILE ?? path.join(projectRoot, "packages", "apps", ".env");
const deployDir = path.join(projectRoot, "packages", "apps", "private-state", "deploy");
const pidFile = path.join(deployDir, "anvil.pid");
const logFile = path.join(deployDir, "anvil.log");

loadEnvFileIfExists(envFile);
fs.mkdirSync(deployDir, { recursive: true });

const rpcUrl = process.env.APPS_RPC_URL_OVERRIDE ?? "http://127.0.0.1:8545";
const network = resolveAppNetwork("anvil");
const mnemonic = process.env.APPS_ANVIL_MNEMONIC ?? "test test test test test test test test test test test junk";
const { host, port } = parseRpcHostPort(rpcUrl);

if (fs.existsSync(pidFile)) {
  const existingPid = Number(fs.readFileSync(pidFile, "utf8").trim());
  if (Number.isInteger(existingPid) && isProcessRunning(existingPid)) {
    console.log(`anvil is already running with PID ${existingPid}`);
    process.exit(0);
  }
  fs.rmSync(pidFile, { force: true });
}

const logFd = fs.openSync(logFile, "a");
const child = spawn("anvil", [
  "--host", host,
  "--port", port,
  "--chain-id", String(network.chainId),
  "--mnemonic", mnemonic,
], {
  cwd: projectRoot,
  detached: true,
  stdio: ["ignore", logFd, logFd],
});

child.unref();

try {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (await isRpcReachable(rpcUrl)) {
      fs.writeFileSync(pidFile, `${child.pid}\n`);
      console.log(`Started anvil on ${rpcUrl} with PID ${child.pid}`);
      console.log(`Log file: ${logFile}`);
      process.exit(0);
    }
    await sleep(1000);
  }
} finally {
  fs.closeSync(logFd);
}

console.error(`anvil did not start successfully. See ${logFile}`);
process.exit(1);

function loadEnvFileIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return;
  }
  Object.assign(process.env, parseDotenv(fs.readFileSync(filePath)));
}

function parseRpcHostPort(rpcUrl) {
  const parsed = new URL(rpcUrl);
  return {
    host: parsed.hostname || "127.0.0.1",
    port: parsed.port || "8545",
  };
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

function isProcessRunning(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
