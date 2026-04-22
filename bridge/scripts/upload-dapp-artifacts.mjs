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

function collectDappArtifactFiles(options) {
  return [
    requiredFile(options.registrationManifestPath, path.basename(options.registrationManifestPath)),
    requiredFile(options.appDeploymentPath, path.basename(options.appDeploymentPath)),
    requiredFile(options.storageLayoutPath, path.basename(options.storageLayoutPath)),
    requiredFile(
      path.join(path.dirname(options.appDeploymentPath), "PrivateStateController.callable-abi.json"),
      "PrivateStateController.callable-abi.json",
    ),
    requiredFile(
      path.join(path.dirname(options.appDeploymentPath), "L2AccountingVault.callable-abi.json"),
      "L2AccountingVault.callable-abi.json",
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
  const targetSegments = [`chain-id-${options.bridgeChainId}`, "dapps", options.dappName];

  if (options.preflight) {
    await preflightExclusiveFolderPath(drive, config.folderId, targetSegments, timestamp);
    console.log(`Drive preflight succeeded for chain-id-${options.bridgeChainId}/dapps/${options.dappName}/${timestamp}.`);
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
