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

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const tokamakSubmoduleRoot = path.join(repoRoot, "submodules", "Tokamak-zk-EVM");
const tokamakCliPath = path.join(tokamakSubmoduleRoot, "tokamak-cli");
const sigmaVerifyRkyvPath = path.join(
  tokamakSubmoduleRoot,
  "dist",
  "resource",
  "setup",
  "output",
  "sigma_verify.rkyv"
);
const setupParamsPath = path.join(
  tokamakSubmoduleRoot,
  "dist",
  "resource",
  "qap-compiler",
  "library",
  "setupParams.json"
);
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
const grothVerificationKeyPath = path.join(
  repoRoot,
  "groth16",
  "trusted-setup",
  "updateTree",
  "verification_key.json"
);
const grothVerifierOutputPath = path.join(
  repoRoot,
  "groth16",
  "verifier",
  "src",
  "Groth16Verifier.sol"
);
const artifactRoot = path.join(repoRoot, "script", "zk", "artifacts");
const defaultManifestPath = path.join(artifactRoot, "reflection.latest.json");

function usage() {
  console.log(`Usage:
  node script/zk/reflect-submodule-updates.mjs --install-arg <ALCHEMY_API_KEY|ALCHEMY_RPC_URL> [options]

Options:
  --manifest-out <path>              Output manifest path
  --skip-submodule-update            Skip updating submodules/Tokamak-zk-EVM to origin/dev
  --skip-install                     Skip tokamak-cli --install
  --skip-tokamak-verifier            Skip Tokamak sigma conversion and verifier regeneration
  --skip-groth                       Skip Groth16 trusted-setup/verifier regeneration
`);
}

function parseArgs(argv) {
  const options = {
    installArg: null,
    manifestOut: defaultManifestPath,
    skipSubmoduleUpdate: false,
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
      case "--install-arg":
        options.installArg = take(current);
        break;
      case "--manifest-out":
        options.manifestOut = path.resolve(process.cwd(), take(current));
        break;
      case "--skip-submodule-update":
        options.skipSubmoduleUpdate = true;
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

  if (!options.skipInstall && !options.installArg) {
    throw new Error("--install-arg is required unless --skip-install is used.");
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

async function updateTokamakSubmodule() {
  await run("git", ["fetch", "origin", "dev"], { cwd: tokamakSubmoduleRoot });
  await run("git", ["checkout", "-B", "dev", "origin/dev"], { cwd: tokamakSubmoduleRoot });
  await run("git", ["pull", "--ff-only", "origin", "dev"], { cwd: tokamakSubmoduleRoot });
}

async function runTokamakInstall(installArg) {
  await run(tokamakCliPath, ["--install", installArg], { cwd: tokamakSubmoduleRoot });
}

async function regenerateTokamakVerifierKey() {
  assertExists(sigmaVerifyRkyvPath, "Tokamak sigma_verify.rkyv");
  assertExists(setupParamsPath, "Tokamak setupParams.json");

  await run(
    "cargo",
    [
      "run",
      "--manifest-path",
      path.join("script", "zk", "rkyv-to-json", "Cargo.toml"),
      "--",
      sigmaVerifyRkyvPath,
      sigmaVerifyJsonPath,
    ],
    { cwd: repoRoot }
  );

  await run("node", [path.join("script", "generate-tokamak-verifier-key.js")], { cwd: repoRoot });
  await run("node", [path.join("script", "generate-tokamak-verifier-params.js")], { cwd: repoRoot });

  assertExists(sigmaVerifyJsonPath, "Tokamak sigma_verify.json");
  assertExists(tokamakVerifierGeneratedPath, "Tokamak generated verification key");
  assertExists(tokamakVerifierSourcePath, "Tokamak verifier source");
}

async function regenerateGrothArtifacts() {
  await run("node", [path.join("groth16", "trusted-setup", "scripts", "generate_update_tree_setup.mjs")], {
    cwd: repoRoot,
  });
  await run(
    "python3",
    [
      path.join("groth16", "verifier", "scripts", "generate_update_tree_verifier.py"),
      grothVerificationKeyPath,
      grothVerifierOutputPath,
    ],
    { cwd: repoRoot }
  );
}

async function resolveTokamakL2JsMetadata() {
  const raw = await run("node", [path.join("bridge", "script", "resolve-latest-mt-depth.mjs")], {
    cwd: repoRoot,
    streamOutput: false,
  });
  return JSON.parse(raw);
}

async function resolveSubmoduleRevision() {
  const branch = (await run("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
    cwd: tokamakSubmoduleRoot,
    streamOutput: false,
  })).trim();
  const head = (await run("git", ["rev-parse", "HEAD"], {
    cwd: tokamakSubmoduleRoot,
    streamOutput: false,
  })).trim();
  return { branch, head };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  ensureDir(artifactRoot);

  if (!options.skipSubmoduleUpdate) {
    await updateTokamakSubmodule();
  }

  if (!options.skipInstall) {
    await runTokamakInstall(options.installArg);
  }

  if (!options.skipTokamakVerifier) {
    await regenerateTokamakVerifierKey();
  }

  if (!options.skipGroth) {
    await regenerateGrothArtifacts();
  }

  const tokamakL2Js = await resolveTokamakL2JsMetadata();
  const submodule = await resolveSubmoduleRevision();
  const grothMetadataPath = path.join(repoRoot, "groth16", "trusted-setup", "updateTree", "metadata.json");

  const manifest = {
    generatedAt: new Date().toISOString(),
    tokamakSubmodule: {
      path: tokamakSubmoduleRoot,
      branch: submodule.branch,
      head: submodule.head,
      setupParamsPath,
      sigmaVerifyRkyvPath,
    },
    tokamakL2js: tokamakL2Js,
    tokamakVerifier: {
      sigmaVerifyJsonPath,
      generatedVerifierKeyPath: tokamakVerifierGeneratedPath,
      verifierSourcePath: tokamakVerifierSourcePath,
      setupParams: readJson(setupParamsPath),
    },
    groth16: {
      verificationKeyPath: grothVerificationKeyPath,
      verifierPath: grothVerifierOutputPath,
      metadata: readJson(grothMetadataPath),
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
