#!/usr/bin/env node

const { execFileSync } = require("node:child_process");
const path = require("node:path");

function usage() {
  console.error("Usage: node scripts/npm-publish-version-decision.cjs <package-json-path>");
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
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(String(value));
  if (!match) {
    throw new Error(`${label} must be a canonical x.y.z semver: ${value}`);
  }
  return match.slice(1).map((part) => Number(part));
}

function readPackageJson(packageJsonPath) {
  return require(path.resolve(packageJsonPath));
}

function readPublishedVersion(packageName) {
  try {
    return execFileSync("npm", ["view", packageName, "version"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    return null;
  }
}

function main(argv = process.argv.slice(2)) {
  const [packageJsonPath] = argv;
  if (!packageJsonPath || argv.length !== 1) {
    usage();
    process.exit(2);
  }

  const pkg = readPackageJson(packageJsonPath);
  if (pkg.private === true) {
    throw new Error(`${pkg.name} is marked private and cannot be published.`);
  }

  const publishedVersion = readPublishedVersion(pkg.name);
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
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
