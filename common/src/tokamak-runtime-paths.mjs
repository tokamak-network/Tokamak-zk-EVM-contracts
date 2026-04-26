import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
let cachedTokamakCliRuntimeRoot = null;

function resolvePackageRoot(packageName) {
  const packageJsonPath = require.resolve(`${packageName}/package.json`);
  return path.dirname(packageJsonPath);
}

export function resolveTokamakCliPackageRoot() {
  return resolvePackageRoot("@tokamak-zk-evm/cli");
}

export function resolveTokamakCliEntryPath() {
  return path.join(resolveTokamakCliPackageRoot(), "dist", "cli.js");
}

export function buildTokamakCliInvocation(args = []) {
  return {
    command: process.execPath,
    args: [resolveTokamakCliEntryPath(), ...args],
  };
}

export function parseTokamakCliRuntimeRootFromDoctorOutput(output) {
  const plainOutput = stripAnsi(String(output ?? ""));
  const match = plainOutput.match(/^\[ ok \] Runtime workspace:\s*(.+)$/m);
  if (!match) {
    throw new Error("Unable to parse Tokamak runtime workspace from tokamak-cli --doctor output.");
  }
  return path.resolve(match[1].trim());
}

export function resolveTokamakCliRuntimeRoot() {
  if (cachedTokamakCliRuntimeRoot) {
    return cachedTokamakCliRuntimeRoot;
  }

  const invocation = buildTokamakCliInvocation(["--doctor"]);
  const result = spawnSync(invocation.command, invocation.args, {
    cwd: resolveTokamakCliPackageRoot(),
    env: process.env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;

  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(
      [
        "tokamak-cli --doctor failed while resolving the runtime workspace.",
        "Run tokamak-cli --install first.",
        output.trim(),
      ].filter(Boolean).join("\n"),
    );
  }

  cachedTokamakCliRuntimeRoot = parseTokamakCliRuntimeRootFromDoctorOutput(output);
  return cachedTokamakCliRuntimeRoot;
}

export function resolveTokamakCliResourceDir(...segments) {
  return path.join(resolveTokamakCliRuntimeRoot(), "resource", ...segments);
}

export function resolveTokamakCliSetupOutputDir() {
  return resolveTokamakCliResourceDir("setup", "output");
}

export function resolveTokamakCliSetupArtifactPath(filename) {
  return path.join(resolveTokamakCliSetupOutputDir(), filename);
}

export function resolveTokamakCliSynthOutputDir() {
  return resolveTokamakCliResourceDir("synthesizer", "output");
}

export function resolveTokamakCliPreprocessOutputDir() {
  return resolveTokamakCliResourceDir("preprocess", "output");
}

export function resolveTokamakCliProveOutputDir() {
  return resolveTokamakCliResourceDir("prove", "output");
}

export function resolveSubcircuitLibraryPackageRoot() {
  return resolvePackageRoot("@tokamak-zk-evm/subcircuit-library");
}

export function resolveSubcircuitLibraryRoot() {
  return path.join(resolveSubcircuitLibraryPackageRoot(), "subcircuits", "library");
}

export function resolveSubcircuitSetupParamsPath() {
  return path.join(resolveSubcircuitLibraryRoot(), "setupParams.json");
}

export function resolveSubcircuitFrontendCfgPath() {
  return path.join(resolveSubcircuitLibraryRoot(), "frontendCfg.json");
}

export function resolveTokamakBlockInputConfig({
  setupParamsPath = resolveSubcircuitSetupParamsPath(),
  frontendCfgPath = resolveSubcircuitFrontendCfgPath(),
} = {}) {
  const setupParams = readJson(setupParamsPath);
  const frontendCfg = readJson(frontendCfgPath);
  const lUser = Number(setupParams.l_user);
  const lFree = Number(setupParams.l_free);
  if (!Number.isInteger(lUser) || lUser < 0) {
    throw new Error(`setupParams.json l_user must be a non-negative integer. Received: ${setupParams.l_user}`);
  }
  if (!Number.isInteger(lFree) || lFree <= 0) {
    throw new Error(`setupParams.json l_free must be a positive integer. Received: ${setupParams.l_free}`);
  }
  const aPubBlockLength = lFree - lUser;
  if (!Number.isInteger(aPubBlockLength) || aPubBlockLength <= 0) {
    throw new Error(`setupParams.json must satisfy l_free - l_user > 0. Received: ${lFree} - ${lUser} = ${aPubBlockLength}`);
  }
  const previousBlockHashCount = Number(frontendCfg.nPrevBlockHashes);
  if (!Number.isInteger(previousBlockHashCount) || previousBlockHashCount < 0) {
    throw new Error(`frontendCfg.json nPrevBlockHashes must be a non-negative integer. Received: ${frontendCfg.nPrevBlockHashes}`);
  }
  return {
    setupParamsPath,
    frontendCfgPath,
    lUser,
    lFree,
    aPubBlockLength,
    previousBlockHashCount,
  };
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function stripAnsi(value) {
  return value.replace(/\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g, "");
}
