#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../../../..");
const pidFile = path.join(projectRoot, "packages", "apps", "private-state", "deploy", "anvil.pid");

const resolvedPid = resolveRunningAnvilPid();
if (!resolvedPid) {
  console.log("No anvil PID file found.");
  process.exit(0);
}

if (isProcessRunning(resolvedPid)) {
  process.kill(resolvedPid, "SIGTERM");
  console.log(`Stopped anvil PID ${resolvedPid}`);
} else {
  console.log(`anvil PID ${resolvedPid} was not running`);
}

fs.rmSync(pidFile, { force: true });

function resolveRunningAnvilPid() {
  if (fs.existsSync(pidFile)) {
    const recordedPid = Number(fs.readFileSync(pidFile, "utf8").trim());
    if (Number.isInteger(recordedPid) && isProcessRunning(recordedPid)) {
      return recordedPid;
    }
  }

  const result = spawnSync("pgrep", ["-n", "-f", "anvil.*--port 8545"], {
    encoding: "utf8",
  });
  if (result.status === 0 && result.stdout.trim()) {
    return Number(result.stdout.trim());
  }
  return null;
}

function isProcessRunning(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}
