#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const circomBinariesByPlatform = new Map([
  ["darwin-arm64", "circom-2.0-darwin-arm64"],
  ["linux-x64", "circom-2.0-linux-amd64"],
]);

function currentPlatformKey(platform = os.platform(), arch = os.arch()) {
  return `${platform}-${arch}`;
}

export function availableCircomPlatforms() {
  return Array.from(circomBinariesByPlatform.keys());
}

export function resolveCircomBinaryPath(platform = os.platform(), arch = os.arch()) {
  const platformKey = currentPlatformKey(platform, arch);
  const binaryName = circomBinariesByPlatform.get(platformKey);

  if (!binaryName) {
    throw new Error(
      `Unsupported Circom platform '${platformKey}'. Available binaries: ${availableCircomPlatforms().join(", ")}.`,
    );
  }

  const candidatePaths = [
    path.join(__dirname, binaryName),
    path.resolve(__dirname, "../../../groth16/circuits", binaryName),
  ];
  const binaryPath = candidatePaths.find((candidatePath) => fs.existsSync(candidatePath));
  if (!binaryPath) {
    throw new Error(
      `Missing Circom binary for '${platformKey}'. Checked: ${candidatePaths.join(", ")}`,
    );
  }

  return binaryPath;
}
