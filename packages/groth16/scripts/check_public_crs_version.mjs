#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  assertLatestPublicGroth16MpcArchiveVersion,
  findLatestPublicGroth16MpcArchiveMetadata,
} from "../lib/public-drive-crs.mjs";
import {
  fetchLatestNpmPackageVersion,
  GROTH16_NPM_PACKAGE_NAME,
} from "../lib/npm-registry.mjs";

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
  --package      Require the latest public Groth16 CRS archive version to match packages/groth16/package.json
  --npm-latest   Require the latest public Groth16 CRS archive version to match the npm latest dist-tag

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
  console.log(`Latest public Groth16 CRS archive: ${archive.archiveName}`);
  console.log(`Latest public Groth16 CRS version: ${archive.version}`);

  if (modes.has("package")) {
    await assertLatestPublicGroth16MpcArchiveVersion(packageJson.version, {
      expectedVersionLabel: `${packageJson.name} package version`,
    });
    console.log(`${packageJson.name} package version matches latest public Groth16 CRS: ${packageJson.version}`);
  }

  if (modes.has("npm-latest")) {
    const npmLatest = await fetchLatestNpmPackageVersion(GROTH16_NPM_PACKAGE_NAME);
    await assertLatestPublicGroth16MpcArchiveVersion(npmLatest, {
      expectedVersionLabel: `${GROTH16_NPM_PACKAGE_NAME} npm latest version`,
    });
    console.log(`${GROTH16_NPM_PACKAGE_NAME} npm latest version matches latest public Groth16 CRS: ${npmLatest}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
