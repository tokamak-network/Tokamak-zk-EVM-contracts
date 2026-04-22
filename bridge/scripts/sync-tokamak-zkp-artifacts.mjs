#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  ensureDir,
  readJson,
  writeJson,
} from "../../scripts/zk/lib/tokamak-artifacts.mjs";
import {
  resolveTokamakCliPackageRoot,
  resolveTokamakCliSetupOutputDir,
} from "../../scripts/zk/lib/tokamak-runtime-paths.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const deployDir = path.join(repoRoot, "bridge", "deployments");
const tokamakCliPackageRoot = resolveTokamakCliPackageRoot();
const tokamakSetupOutputDir = resolveTokamakCliSetupOutputDir();

function usage() {
  console.error("Usage: node bridge/scripts/sync-tokamak-zkp-artifacts.mjs <chain-id>");
}

function assertFileExists(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing required Tokamak zk proof artifact: ${label}: ${filePath}`);
  }
}

function copyFile(sourcePath, targetPath) {
  ensureDir(path.dirname(targetPath));
  fs.copyFileSync(sourcePath, targetPath);
}

function readCliVersion() {
  const packageJsonPath = path.join(tokamakCliPackageRoot, "package.json");
  const packageJson = readJson(packageJsonPath);
  if (typeof packageJson.version !== "string" || packageJson.version.length === 0) {
    throw new Error(`Tokamak CLI package has no version: ${packageJsonPath}`);
  }
  return packageJson.version;
}

function readSetupVersion(buildMetadataPath, fallbackVersion) {
  if (!fs.existsSync(buildMetadataPath)) {
    return fallbackVersion;
  }

  const metadata = readJson(buildMetadataPath);
  if (typeof metadata.packageVersion === "string" && metadata.packageVersion.length > 0) {
    return metadata.packageVersion;
  }
  return fallbackVersion;
}

function main() {
  const chainId = process.argv[2];
  if (!chainId || process.argv.length !== 3) {
    usage();
    process.exit(1);
  }

  const artifactDir = path.join(deployDir, "tokamak-zkp", chainId);
  const manifestPath = path.join(deployDir, `tokamak-zkp.${chainId}.latest.json`);
  const combinedSigmaPath = path.join(tokamakSetupOutputDir, "combined_sigma.rkyv");
  const sigmaPreprocessPath = path.join(tokamakSetupOutputDir, "sigma_preprocess.rkyv");
  const sigmaVerifyPath = path.join(tokamakSetupOutputDir, "sigma_verify.json");
  const buildMetadataPath = path.join(tokamakSetupOutputDir, "build-metadata-mpc-setup.json");
  const crsProvenancePath = path.join(tokamakSetupOutputDir, "crs_provenance.json");

  assertFileExists(combinedSigmaPath, "combined_sigma.rkyv");
  assertFileExists(sigmaPreprocessPath, "sigma_preprocess.rkyv");
  assertFileExists(sigmaVerifyPath, "sigma_verify.json");

  fs.rmSync(artifactDir, { recursive: true, force: true });

  let relativeBuildMetadataPath = null;
  if (fs.existsSync(buildMetadataPath)) {
    ensureDir(artifactDir);
    copyFile(buildMetadataPath, path.join(artifactDir, "build-metadata-mpc-setup.json"));
    relativeBuildMetadataPath = `tokamak-zkp/${chainId}/build-metadata-mpc-setup.json`;
  }

  let relativeCrsProvenancePath = null;
  if (fs.existsSync(crsProvenancePath)) {
    ensureDir(artifactDir);
    copyFile(crsProvenancePath, path.join(artifactDir, "crs_provenance.json"));
    relativeCrsProvenancePath = `tokamak-zkp/${chainId}/crs_provenance.json`;
  }

  const cliVersion = readCliVersion();
  const artifactVersion = readSetupVersion(buildMetadataPath, cliVersion);

  writeJson(manifestPath, {
    generatedAtUtc: new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z"),
    chainId: Number(chainId),
    tokamakZkpArtifactSource: "cli-runtime-cache",
    artifactDir: `tokamak-zkp/${chainId}`,
    artifacts: {
      version: artifactVersion,
      buildMetadataPath: relativeBuildMetadataPath,
      crsProvenancePath: relativeCrsProvenancePath,
    },
  });

  console.log(`Updated bridge Tokamak zk proof manifest: ${manifestPath}`);
  console.log(`Tokamak setup output directory: ${tokamakSetupOutputDir}`);
}

main();
