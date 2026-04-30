#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  findLatestPublicGroth16MpcArchiveMetadata,
  normalizeGroth16PackageVersionToCompatibleBackendVersion,
  readGroth16CompatibleBackendVersionFromPackageJson,
  requireCanonicalGroth16CompatibleBackendVersion,
} from "../lib/public-drive-crs.mjs";
import {
  fetchLatestNpmPackageVersion,
} from "@tokamak-private-dapps/common-library/npm-registry";

const GROTH16_NPM_PACKAGE_NAME = "@tokamak-private-dapps/groth16";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const groth16Root = path.resolve(__dirname, "..");
const packageJsonPath = path.join(groth16Root, "package.json");

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function usage() {
  console.log(`Usage:
  node packages/groth16/scripts/check_public_crs_version.mjs [--package] [--npm-latest]

Options:
  --package      Require the latest public Groth16 CRS archive compatibility version to match packages/groth16/package.json
  --npm-latest   Require the latest public Groth16 CRS archive compatibility version to match the npm latest dist-tag major.minor

If no option is provided, --package is used.
`);
}

async function main(argv = process.argv.slice(2)) {
  const modes = new Set();
  for (const arg of argv) {
    switch (arg) {
      case "--package":
        modes.add("package");
        break;
      case "--npm-latest":
        modes.add("npm-latest");
        break;
      case "--help":
      case "-h":
        usage();
        return;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }
  if (modes.size === 0) {
    modes.add("package");
  }

  const packageJson = readJson(packageJsonPath);
  const archive = await findLatestPublicGroth16MpcArchiveMetadata();
  const packageCompatibleVersion = readGroth16CompatibleBackendVersionFromPackageJson(packageJson, packageJson.name);
  console.log(`Latest public Groth16 CRS archive: ${archive.archiveName}`);
  console.log(`Latest public Groth16 CRS compatibility version: ${archive.version}`);

  if (modes.has("package")) {
    assertArchiveVersionMatches(archive, packageCompatibleVersion, `${packageJson.name} compatible backend version`);
    console.log(
      `${packageJson.name} compatible backend version matches latest public Groth16 CRS: `
        + `${packageCompatibleVersion}`,
    );
  }

  if (modes.has("npm-latest")) {
    const npmLatest = await fetchLatestNpmPackageVersion(GROTH16_NPM_PACKAGE_NAME);
    const npmLatestCompatibleVersion = normalizeGroth16PackageVersionToCompatibleBackendVersion(
      npmLatest,
      `${GROTH16_NPM_PACKAGE_NAME} npm latest version`,
    );
    assertArchiveVersionMatches(
      archive,
      npmLatestCompatibleVersion,
      `${GROTH16_NPM_PACKAGE_NAME} npm latest compatible backend version`,
    );
    console.log(
      `${GROTH16_NPM_PACKAGE_NAME} npm latest compatible backend version matches latest public Groth16 CRS: `
        + `${npmLatestCompatibleVersion} (package ${npmLatest})`,
    );
  }
}

function assertArchiveVersionMatches(archive, expectedVersion, expectedVersionLabel) {
  const normalizedExpectedVersion = requireCanonicalGroth16CompatibleBackendVersion(expectedVersion, expectedVersionLabel);
  if (archive.version !== normalizedExpectedVersion) {
    throw new Error(
      `Latest public Groth16 MPC CRS compatibility version ${archive.version} does not match `
        + `${expectedVersionLabel} ${normalizedExpectedVersion}: ${archive.archiveName}`,
    );
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
