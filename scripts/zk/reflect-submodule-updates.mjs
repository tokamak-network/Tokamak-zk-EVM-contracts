#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  assertExists,
  ensureDir,
  readJson,
  writeJson,
} from "./lib/tokamak-artifacts.mjs";
import {
  buildTokamakCliInvocation,
  resolveSubcircuitSetupParamsPath,
  resolveTokamakCliCacheRoot,
  resolveTokamakCliPackageRoot,
  resolveTokamakCliSetupArtifactPath,
  resolveTokamakCliRuntimeRoot,
} from "./lib/tokamak-runtime-paths.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const tokamakCliPackageRoot = resolveTokamakCliPackageRoot();
const tokamakCliCacheRoot = resolveTokamakCliCacheRoot();
const tokamakRuntimeRoot = resolveTokamakCliRuntimeRoot();
const setupParamsPath = resolveSubcircuitSetupParamsPath();
const installedSigmaVerifyJsonPath = resolveTokamakCliSetupArtifactPath("sigma_verify.json");
const sigmaVerifyJsonPath = path.join(
  repoRoot,
  "tokamak-zkp",
  "TokamakVerifierKey",
  "sigma_verify.json"
);
const tokamakVerifierGeneratedPath = path.join(
  repoRoot,
  "tokamak-zkp",
  "TokamakVerifierKey",
  "TokamakVerifierKey.generated.sol"
);
const tokamakVerifierSourcePath = path.join(repoRoot, "tokamak-zkp", "TokamakVerifier.sol");
const grothVerifierOutputPath = path.join(
  repoRoot,
  "groth16",
  "verifier",
  "src",
  "Groth16Verifier.sol"
);
const artifactRoot = path.join(repoRoot, "scripts", "zk", "artifacts");
const defaultManifestPath = path.join(artifactRoot, "reflection.latest.json");

function usage() {
  console.log(`Usage:
  node scripts/zk/reflect-submodule-updates.mjs [options]

Options:
  --manifest-out <path>              Output manifest path
  --groth-source <trusted|mpc>       Groth16 artifact source to refresh
  --skip-install                     Skip tokamak-cli --install
  --skip-tokamak-verifier            Skip Tokamak sigma copy and verifier regeneration
  --skip-groth                       Skip Groth16 artifact/verifier regeneration
`);
}

function normalizeGrothSource(value) {
  if (value === "trusted" || value === "mpc") {
    return value;
  }
  throw new Error(`Unsupported --groth-source=${value}. Expected trusted or mpc.`);
}

function resolveGrothPaths(source) {
  if (source === "trusted") {
    return {
      source,
      generatorScriptPath: path.join("scripts", "groth16", "trusted-setup", "generate_update_tree_setup.mjs"),
      verificationKeyPath: path.join(repoRoot, "groth16", "trusted-setup", "crs", "verification_key.json"),
      metadataPath: path.join(repoRoot, "groth16", "trusted-setup", "crs", "metadata.json"),
    };
  }

  return {
    source,
    generatorScriptPath: path.join("groth16", "mpc-setup", "generate_update_tree_setup_from_dusk.mjs"),
    verificationKeyPath: path.join(repoRoot, "groth16", "mpc-setup", "crs", "verification_key.json"),
    metadataPath: path.join(repoRoot, "groth16", "mpc-setup", "crs", "metadata.json"),
  };
}

function parseArgs(argv) {
  const options = {
    manifestOut: defaultManifestPath,
    grothSource: "trusted",
    skipInstall: false,
    skipTokamakVerifier: false,
    skipGroth: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    const next = argv[i + 1];

    const take = (name) => {
      if (!next || next.startsWith("--")) {
        throw new Error(`Missing value for ${name}.`);
      }
      i += 1;
      return next;
    };

    switch (current) {
      case "--manifest-out":
        options.manifestOut = path.resolve(process.cwd(), take(current));
        break;
      case "--groth-source":
        options.grothSource = normalizeGrothSource(take(current));
        break;
      case "--skip-install":
        options.skipInstall = true;
        break;
      case "--skip-tokamak-verifier":
        options.skipTokamakVerifier = true;
        break;
      case "--skip-groth":
        options.skipGroth = true;
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        throw new Error(`Unknown option: ${current}`);
    }
  }

  return options;
}

function run(command, args, { cwd = repoRoot, streamOutput = true } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let combined = "";

    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      combined += text;
      if (streamOutput) {
        process.stdout.write(text);
      }
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      combined += text;
      if (streamOutput) {
        process.stderr.write(text);
      }
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve(combined);
      } else {
        const error = new Error(`${command} ${args.join(" ")} exited with code ${code ?? "unknown"}.`);
        error.output = combined;
        reject(error);
      }
    });
  });
}

async function runTokamakInstall() {
  const invocation = buildTokamakCliInvocation(["--install"]);
  await run(invocation.command, invocation.args, { cwd: repoRoot });
}

async function regenerateTokamakVerifierKey() {
  assertExists(installedSigmaVerifyJsonPath, "Tokamak sigma_verify.json");
  assertExists(setupParamsPath, "Tokamak setupParams.json");
  ensureDir(path.dirname(sigmaVerifyJsonPath));
  fs.copyFileSync(installedSigmaVerifyJsonPath, sigmaVerifyJsonPath);

  await run("node", [path.join("scripts", "generate-tokamak-verifier-key.js")], { cwd: repoRoot });
  await run("node", [path.join("scripts", "generate-tokamak-verifier-params.js")], { cwd: repoRoot });

  assertExists(sigmaVerifyJsonPath, "Tokamak sigma_verify.json");
  assertExists(tokamakVerifierGeneratedPath, "Tokamak generated verification key");
  assertExists(tokamakVerifierSourcePath, "Tokamak verifier source");
}

async function refreshSharedTokamakConstants() {
  await run("node", [path.join("scripts", "generate-tokamak-shared-constants.js"), setupParamsPath], { cwd: repoRoot });
  await run("node", [path.join("scripts", "groth16", "render-update-tree-circuit.mjs")], { cwd: repoRoot });
}

async function regenerateGrothArtifacts(grothPaths) {
  await run("node", [grothPaths.generatorScriptPath], {
    cwd: repoRoot,
  });
  await run(
    "python3",
    [
      path.join("scripts", "groth16", "verifier", "generate_update_tree_verifier.py"),
      grothPaths.verificationKeyPath,
      grothVerifierOutputPath,
    ],
    { cwd: repoRoot }
  );
}

async function resolveTokamakL2JsMetadata() {
  const raw = await run("node", [path.join("bridge", "scripts", "resolve-latest-mt-depth.mjs")], {
    cwd: repoRoot,
    streamOutput: false,
  });
  return JSON.parse(raw);
}

async function resolveTokamakRuntimeMetadata() {
  const packageJson = readJson(path.join(tokamakCliPackageRoot, "package.json"));
  return {
    packageRoot: tokamakCliPackageRoot,
    version: packageJson.version,
    cacheRoot: tokamakCliCacheRoot,
    runtimeRoot: tokamakRuntimeRoot,
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const grothPaths = resolveGrothPaths(options.grothSource);
  ensureDir(artifactRoot);

  if (!options.skipInstall) {
    await runTokamakInstall();
  }

  if (!options.skipTokamakVerifier) {
    await regenerateTokamakVerifierKey();
  }

  await refreshSharedTokamakConstants();

  if (!options.skipGroth) {
    await regenerateGrothArtifacts(grothPaths);
  }

  const tokamakL2Js = await resolveTokamakL2JsMetadata();
  const runtime = await resolveTokamakRuntimeMetadata();
  const manifest = {
    generatedAt: new Date().toISOString(),
    tokamakRuntime: {
      cliPackageRoot: runtime.packageRoot,
      cliVersion: runtime.version,
      cacheRoot: runtime.cacheRoot,
      runtimeRoot: runtime.runtimeRoot,
      setupParamsPath,
      installedSigmaVerifyJsonPath,
    },
    tokamakL2js: tokamakL2Js,
    tokamakVerifier: {
      sigmaVerifyJsonPath,
      generatedVerifierKeyPath: tokamakVerifierGeneratedPath,
      verifierSourcePath: tokamakVerifierSourcePath,
      setupParams: readJson(setupParamsPath),
    },
    groth16: {
      source: grothPaths.source,
      verificationKeyPath: grothPaths.verificationKeyPath,
      verifierPath: grothVerifierOutputPath,
      metadata: readJson(grothPaths.metadataPath),
    },
    bridge: {
      recommendedMerkleTreeLevels: tokamakL2Js.mtDepth,
    },
  };

  writeJson(options.manifestOut, manifest);
  console.log(`Wrote reflection manifest: ${options.manifestOut}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
