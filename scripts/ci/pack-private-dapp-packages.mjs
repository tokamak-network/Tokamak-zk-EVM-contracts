#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");

const packages = [
  {
    name: "@tokamak-private-dapps/common-library",
    root: "packages/common",
  },
  {
    name: "@tokamak-private-dapps/groth16",
    root: "packages/groth16",
  },
  {
    name: "@tokamak-private-dapps/private-state-cli",
    root: "packages/apps/private-state/cli",
  },
];

function usage() {
  console.error("Usage: node scripts/ci/pack-private-dapp-packages.mjs [--out <directory>]");
}

function parseArgs(argv) {
  const options = {
    out: path.resolve(repoRoot, "package-tarballs"),
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    switch (current) {
      case "--out":
        index += 1;
        if (!argv[index]) {
          usage();
          process.exit(2);
        }
        options.out = path.resolve(repoRoot, argv[index]);
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        console.error(`Unknown option: ${current}`);
        usage();
        process.exit(2);
    }
  }

  return options;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function runNpmPack(packageRoot, outputRoot) {
  const stdout = execFileSync(
    "npm",
    ["pack", packageRoot, "--pack-destination", outputRoot, "--json"],
    {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "inherit"],
    },
  );
  const result = JSON.parse(stdout);
  if (!Array.isArray(result) || result.length !== 1) {
    throw new Error(`Unexpected npm pack output for ${packageRoot}: ${stdout}`);
  }
  return result[0];
}

function main(argv = process.argv.slice(2)) {
  const { out } = parseArgs(argv);
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(out, { recursive: true });

  const manifestPackages = packages.map((entry) => {
    const packageRoot = path.resolve(repoRoot, entry.root);
    const packageJsonPath = path.join(packageRoot, "package.json");
    const packageJson = readJson(packageJsonPath);
    if (packageJson.name !== entry.name) {
      throw new Error(`${packageJsonPath} declares ${packageJson.name}, expected ${entry.name}.`);
    }

    const packResult = runNpmPack(packageRoot, out);
    const tarballPath = path.resolve(out, packResult.filename);
    if (!fs.existsSync(tarballPath)) {
      throw new Error(`npm pack did not create expected tarball: ${tarballPath}`);
    }

    return {
      name: packageJson.name,
      version: packageJson.version,
      packageRoot: path.relative(repoRoot, packageRoot),
      filename: packResult.filename,
      path: path.relative(repoRoot, tarballPath),
      integrity: packResult.integrity,
      shasum: packResult.shasum,
    };
  });

  const manifest = {
    generatedAt: new Date().toISOString(),
    packages: manifestPackages,
  };
  const manifestPath = path.join(out, "manifest.json");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  for (const entry of manifestPackages) {
    console.log(`${entry.name}@${entry.version} ${entry.path}`);
  }
  console.log(`manifest=${path.relative(repoRoot, manifestPath)}`);
}

main();
