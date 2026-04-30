#!/usr/bin/env node

import path from "node:path";
import { createRequire } from "node:module";
import { fetchLatestNpmPackageVersion } from "@tokamak-private-dapps/common-library/npm-registry";
import { requireExactSemverVersion } from "@tokamak-private-dapps/common-library/proof-backend-versioning";

const require = createRequire(import.meta.url);

function usage() {
  console.error("Usage: node scripts/npm-publish-version-decision.mjs <package-json-path>");
}

function compareSemver(left, right) {
  const leftParts = parseSemver(left, "local package version");
  const rightParts = parseSemver(right, "published package version");

  for (let index = 0; index < 3; index += 1) {
    if (leftParts[index] > rightParts[index]) return 1;
    if (leftParts[index] < rightParts[index]) return -1;
  }

  return 0;
}

function parseSemver(value, label) {
  const version = requireExactSemverVersion(value, label);
  const [, major, minor, patch] = /^(\d+)\.(\d+)\.(\d+)/.exec(version);
  return [major, minor, patch].map((part) => Number(part));
}

function readPackageJson(packageJsonPath) {
  return require(path.resolve(packageJsonPath));
}

async function readPublishedVersion(packageName) {
  try {
    return await fetchLatestNpmPackageVersion(packageName);
  } catch (error) {
    return null;
  }
}

async function main(argv = process.argv.slice(2)) {
  const [packageJsonPath] = argv;
  if (!packageJsonPath || argv.length !== 1) {
    usage();
    process.exit(2);
  }

  const pkg = readPackageJson(packageJsonPath);
  if (pkg.private === true) {
    throw new Error(`${pkg.name} is marked private and cannot be published.`);
  }

  const publishedVersion = await readPublishedVersion(pkg.name);
  const comparison = publishedVersion === null ? 1 : compareSemver(pkg.version, publishedVersion);
  if (comparison < 0) {
    throw new Error(`Local version ${pkg.version} is behind npm version ${publishedVersion} for ${pkg.name}.`);
  }

  const shouldPublish = publishedVersion === null || comparison > 0;
  console.log(`package_name=${pkg.name}`);
  console.log(`local_version=${pkg.version}`);
  console.log(`published_version=${publishedVersion ?? "none"}`);
  console.log(`should_publish=${shouldPublish}`);
}

try {
  await main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
