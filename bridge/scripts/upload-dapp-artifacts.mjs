#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  createDriveClient,
  createExclusiveFolderPath,
  createTimestampLabel,
  preflightExclusiveFolderPath,
  resolveDriveUploadConfig,
  uploadFilesByRelativePath,
  writeUploadReceipt,
} from "../../scripts/drive/lib/google-drive-upload.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");

function usage() {
  console.error(
    "Usage: node bridge/scripts/upload-dapp-artifacts.mjs --dapp-name <name> --bridge-chain-id <id> --app-chain-id <id> --registration-manifest <path> --app-deployment-path <path> --storage-layout-path <path> [--timestamp <label>] [--preflight] [--receipt-out <path>]",
  );
}

function parseArgs(argv) {
  const options = {
    dappName: null,
    bridgeChainId: null,
    appChainId: null,
    registrationManifestPath: null,
    appDeploymentPath: null,
    storageLayoutPath: null,
    timestamp: null,
    preflight: false,
    receiptOut: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    const next = argv[i + 1];
    const take = (name) => {
      if (!next || next.startsWith("--")) {
        throw new Error(`Missing value for ${name}`);
      }
      i += 1;
      return next;
    };

    switch (current) {
      case "--dapp-name":
        options.dappName = take(current);
        break;
      case "--bridge-chain-id":
        options.bridgeChainId = Number.parseInt(take(current), 10);
        break;
      case "--app-chain-id":
        options.appChainId = Number.parseInt(take(current), 10);
        break;
      case "--registration-manifest":
        options.registrationManifestPath = path.resolve(process.cwd(), take(current));
        break;
      case "--app-deployment-path":
        options.appDeploymentPath = path.resolve(process.cwd(), take(current));
        break;
      case "--storage-layout-path":
        options.storageLayoutPath = path.resolve(process.cwd(), take(current));
        break;
      case "--timestamp":
        options.timestamp = take(current);
        break;
      case "--preflight":
        options.preflight = true;
        break;
      case "--receipt-out":
        options.receiptOut = path.resolve(process.cwd(), take(current));
        break;
      default:
        throw new Error(`Unknown option: ${current}`);
    }
  }

  if (!options.dappName) {
    throw new Error("--dapp-name is required");
  }
  if (!Number.isInteger(options.bridgeChainId)) {
    throw new Error("--bridge-chain-id is required");
  }
  if (!Number.isInteger(options.appChainId)) {
    throw new Error("--app-chain-id is required");
  }
  if (!options.registrationManifestPath || !options.appDeploymentPath || !options.storageLayoutPath) {
    throw new Error("registration/app manifest paths are required");
  }

  return options;
}

function shouldSkipUpload({ bridgeChainId, appChainId }) {
  return (
    process.env.BRIDGE_NETWORK === "anvil" ||
    process.env.APPS_NETWORK === "anvil" ||
    bridgeChainId === 31337 ||
    appChainId === 31337
  );
}

function requiredFile(filePath, relativePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing DApp deployment artifact: ${filePath}`);
  }
  return { localPath: filePath, relativePath };
}

function optionalFile(filePath, relativePath) {
  return fs.existsSync(filePath) ? { localPath: filePath, relativePath } : null;
}

function collectDappArtifactFiles(options) {
  return [
    requiredFile(options.registrationManifestPath, path.join("registration", path.basename(options.registrationManifestPath))),
    requiredFile(options.appDeploymentPath, path.join("deployment", path.basename(options.appDeploymentPath))),
    requiredFile(options.storageLayoutPath, path.join("deployment", path.basename(options.storageLayoutPath))),
    requiredFile(
      path.join(repoRoot, "apps", "private-state", "deploy", "PrivateStateController.callable-abi.json"),
      path.join("deployment", "PrivateStateController.callable-abi.json"),
    ),
    requiredFile(
      path.join(repoRoot, "apps", "private-state", "deploy", "L2AccountingVault.callable-abi.json"),
      path.join("deployment", "L2AccountingVault.callable-abi.json"),
    ),
    optionalFile(
      path.join(repoRoot, "apps", "private-state", "deploy", `groth16-updateTree.${options.appChainId}.latest.json`),
      path.join("deployment", `groth16-updateTree.${options.appChainId}.latest.json`),
    ),
    optionalFile(
      path.join(repoRoot, "apps", "private-state", "deploy", "groth16", String(options.appChainId), "circuit_final.zkey"),
      path.join("deployment", "groth16", String(options.appChainId), "circuit_final.zkey"),
    ),
    optionalFile(
      path.join(repoRoot, "apps", "private-state", "deploy", "groth16", String(options.appChainId), "metadata.json"),
      path.join("deployment", "groth16", String(options.appChainId), "metadata.json"),
    ),
  ].filter(Boolean);
}

async function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    usage();
    throw error;
  }

  if (shouldSkipUpload(options)) {
    console.log(`Skipping DApp artifact upload for local network bridge=${options.bridgeChainId} app=${options.appChainId}.`);
    return;
  }

  const config = resolveDriveUploadConfig();
  const drive = await createDriveClient(config);
  const timestamp = options.timestamp ?? createTimestampLabel();
  const targetSegments = [String(options.bridgeChainId), "dapps", options.dappName];

  if (options.preflight) {
    await preflightExclusiveFolderPath(drive, config.folderId, targetSegments, timestamp);
    console.log(`Drive preflight succeeded for dapps/${options.dappName}/${timestamp}.`);
    return;
  }

  const files = collectDappArtifactFiles(options);
  const { leafId, leafUrl } = await createExclusiveFolderPath(drive, config.folderId, targetSegments, timestamp);

  await uploadFilesByRelativePath(drive, leafId, files);

  if (options.receiptOut) {
    writeUploadReceipt(options.receiptOut, {
      kind: "dapp",
      dappName: options.dappName,
      bridgeChainId: options.bridgeChainId,
      appChainId: options.appChainId,
      timestamp,
      folderUrl: leafUrl,
      driveRootUrl: config.folderUrl,
      uploadedAt: new Date().toISOString(),
      files: files.map(({ relativePath }) => relativePath),
    });
  }

  console.log(`Uploaded DApp artifacts to: ${leafUrl}`);
  console.log(`Drive root: ${config.folderUrl}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
