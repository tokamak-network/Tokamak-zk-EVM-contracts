#!/usr/bin/env node

import path from "node:path";
import { fileURLToPath } from "node:url";
import { downloadLatestPublicGroth16MpcArtifacts } from "@tokamak-private-dapps/common-library/artifact-cache";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const defaultOutputDir = path.join(repoRoot, "groth16", "mpc-setup", "crs");

function usage() {
  console.log(`Usage:
  node scripts/groth16/download-public-mpc-artifacts.mjs [options]

Options:
  --output <path>             Directory to write artifacts into
  --files <a,b,c>             Comma-separated archive files to extract
  --help, -h                  Show this help
`);
}

function parseArgs(argv) {
  const options = {
    outputDir: defaultOutputDir,
    files: [
      "circuit_final.zkey",
      "verification_key.json",
      "metadata.json",
      "zkey_provenance.json",
    ],
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
      case "--output":
        options.outputDir = path.resolve(process.cwd(), take(current));
        break;
      case "--files":
        options.files = take(current).split(",").map((entry) => entry.trim()).filter(Boolean);
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

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const result = await downloadLatestPublicGroth16MpcArtifacts({
    outputDir: options.outputDir,
    selectedFiles: options.files,
  });

  console.log(`Downloaded Groth16 MPC archive: ${result.archiveName}`);
  console.log(`Drive folder: ${result.folderUrl}`);
  for (const file of result.installedFiles) {
    console.log(`${file.archivePath} -> ${file.targetPath}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
