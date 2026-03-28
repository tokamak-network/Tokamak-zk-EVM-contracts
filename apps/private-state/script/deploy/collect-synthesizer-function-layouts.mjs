#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
const appRoot = path.resolve(repoRoot, "apps", "private-state");
const synthRoot = path.resolve(repoRoot, "submodules", "Tokamak-zk-EVM", "packages", "frontend", "synthesizer");
const synthCliEntry = path.resolve(synthRoot, "src", "interface", "cli", "index.ts");
const synthOutputsDir = path.resolve(synthRoot, "outputs");
const archiveRoot = path.resolve(appRoot, "deploy", "synthesizer-layouts");
const summaryPath = path.resolve(archiveRoot, "summary.json");
const manifests = [
  {
    groupName: "private-state-mint",
    manifestPath: path.resolve(synthRoot, "examples", "privateStateMint", "cli-launch-manifest.json"),
  },
  {
    groupName: "private-state-transfer",
    manifestPath: path.resolve(synthRoot, "examples", "privateStateTransfer", "cli-launch-manifest.json"),
  },
  {
    groupName: "private-state-redeem",
    manifestPath: path.resolve(synthRoot, "examples", "privateStateRedeem", "cli-launch-manifest.json"),
  },
];

function expect(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function cleanDir(targetDir) {
  fs.rmSync(targetDir, { recursive: true, force: true });
  fs.mkdirSync(targetDir, { recursive: true });
}

function copyDir(sourceDir, targetDir) {
  fs.rmSync(targetDir, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(targetDir), { recursive: true });
  fs.cpSync(sourceDir, targetDir, { recursive: true });
}

function parseExampleName(entryName) {
  const suffix = " on anvil";
  expect(
    typeof entryName === "string" && entryName.endsWith(suffix),
    `Unexpected manifest entry name: ${String(entryName)}`,
  );
  return entryName.slice(0, -suffix.length).replace(/^Private-state\s+/, "");
}

function run(command, args, { cwd = repoRoot } = {}) {
  const printable = [command, ...args].join(" ");
  console.log(`[collect-synth-layouts] ${printable}`);
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`${printable} failed with exit code ${result.status ?? "unknown"}.`);
  }
}

function buildCliArgs(entry) {
  return [
    "--tsconfig",
    path.resolve(synthRoot, "tsconfig.dev.json"),
    synthCliEntry,
    "tokamak-ch-tx",
    "--previous-state",
    path.resolve(synthRoot, entry.files.previousState),
    "--transaction",
    path.resolve(synthRoot, entry.files.transaction),
    "--block-info",
    path.resolve(synthRoot, entry.files.blockInfo),
    "--contract-code",
    path.resolve(synthRoot, entry.files.contractCode),
  ];
}

function buildSummaryEntry({ groupName, exampleName, outputDir }) {
  const instance = readJson(path.join(outputDir, "instance.json"));
  const description = readJson(path.join(outputDir, "instance_description.json"));

  return {
    groupName,
    exampleName,
    outputDir,
    aPubUserLength: instance.a_pub_user.length,
    aPubFunctionLength: instance.a_pub_function.length,
    aPubUserDescription: description.a_pub_user_description,
  };
}

function main() {
  cleanDir(archiveRoot);

  const summary = [];
  for (const manifestInfo of manifests) {
    const manifest = readJson(manifestInfo.manifestPath);
    expect(Array.isArray(manifest), `Expected array manifest: ${manifestInfo.manifestPath}`);

    for (const entry of manifest) {
      const exampleName = parseExampleName(entry.name);
      run("tsx", buildCliArgs(entry), { cwd: synthRoot });

      const exampleArchiveDir = path.resolve(archiveRoot, exampleName);
      copyDir(synthOutputsDir, exampleArchiveDir);
      summary.push(
        buildSummaryEntry({
          groupName: manifestInfo.groupName,
          exampleName,
          outputDir: exampleArchiveDir,
        }),
      );
    }
  }

  writeJson(summaryPath, {
    generatedAt: new Date().toISOString(),
    archiveRoot,
    entries: summary,
  });
}

try {
  main();
} catch (error) {
  console.error(error);
  process.exit(1);
}
