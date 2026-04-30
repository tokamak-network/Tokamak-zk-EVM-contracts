#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");

const expectedInstallOrder = [
  "@tokamak-private-dapps/common-library",
  "@tokamak-private-dapps/groth16",
  "@tokamak-private-dapps/private-state-cli",
];

function usage() {
  console.error(
    "Usage: node scripts/ci/smoke-test-private-dapp-packages.mjs <manifest.json> [--install-root <directory>]",
  );
}

function parseArgs(argv) {
  const options = {
    manifestPath: null,
    installRoot: path.join(os.tmpdir(), "private-dapp-package-consumer"),
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    switch (current) {
      case "--install-root":
        index += 1;
        if (!argv[index]) {
          usage();
          process.exit(2);
        }
        options.installRoot = path.resolve(repoRoot, argv[index]);
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
        break;
      default:
        if (options.manifestPath !== null) {
          console.error(`Unexpected argument: ${current}`);
          usage();
          process.exit(2);
        }
        options.manifestPath = path.resolve(repoRoot, current);
    }
  }

  if (options.manifestPath === null) {
    usage();
    process.exit(2);
  }

  return options;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function run(command, args, options = {}) {
  console.log(`$ ${command} ${args.join(" ")}`);
  execFileSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    env: {
      ...process.env,
      ...(options.env ?? {}),
    },
    stdio: "inherit",
  });
}

function findManifestEntry(manifest, packageName) {
  const entry = manifest.packages.find((candidate) => candidate.name === packageName);
  if (!entry) {
    throw new Error(`Package tarball manifest is missing ${packageName}.`);
  }
  return entry;
}

function resolveTarballPath(entry) {
  const tarballPath = path.resolve(repoRoot, entry.path);
  if (!fs.existsSync(tarballPath)) {
    throw new Error(`Package tarball does not exist: ${tarballPath}`);
  }
  return tarballPath;
}

function readInstalledPackage(installRoot, packageName) {
  return readJson(path.join(installRoot, "node_modules", ...packageName.split("/"), "package.json"));
}

function runNode(installRoot, source) {
  run("node", ["--input-type=module", "--eval", source], { cwd: installRoot });
}

function main(argv = process.argv.slice(2)) {
  const { manifestPath, installRoot } = parseArgs(argv);
  const manifest = readJson(manifestPath);

  const entries = expectedInstallOrder.map((packageName) => findManifestEntry(manifest, packageName));
  const tarballPaths = entries.map(resolveTarballPath);

  fs.rmSync(installRoot, { recursive: true, force: true });
  fs.mkdirSync(installRoot, { recursive: true });
  fs.writeFileSync(
    path.join(installRoot, "package.json"),
    `${JSON.stringify({ private: true, type: "module" }, null, 2)}\n`,
  );

  run("npm", ["install", "--package-lock=false", "--no-audit", "--no-fund", ...tarballPaths], { cwd: installRoot });

  for (const entry of entries) {
    const installedPackage = readInstalledPackage(installRoot, entry.name);
    if (installedPackage.version !== entry.version) {
      throw new Error(
        `${entry.name} installed version ${installedPackage.version}, expected tarball version ${entry.version}.`,
      );
    }
  }

  runNode(
    installRoot,
    [
      "import '@tokamak-private-dapps/common-library/network-config';",
      "import '@tokamak-private-dapps/common-library/npm-registry';",
      "import '@tokamak-private-dapps/common-library/proof-backend-versioning';",
      "import '@tokamak-private-dapps/groth16/public-drive-crs';",
    ].join("\n"),
  );

  const binRoot = path.join(installRoot, "node_modules", ".bin");
  run(path.join(binRoot, process.platform === "win32" ? "private-state-cli.cmd" : "private-state-cli"), ["--help"], {
    cwd: installRoot,
  });
  run(path.join(binRoot, process.platform === "win32" ? "tokamak-groth16.cmd" : "tokamak-groth16"), ["--help"], {
    cwd: installRoot,
  });

  console.log(`Smoke test passed for ${entries.map((entry) => `${entry.name}@${entry.version}`).join(", ")}.`);
}

main();
