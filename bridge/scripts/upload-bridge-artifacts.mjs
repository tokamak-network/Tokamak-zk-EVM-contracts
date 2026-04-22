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
    "Usage: node bridge/scripts/upload-bridge-artifacts.mjs <chain-id> [--deployment-path <path>] [--abi-manifest-path <path>] [--timestamp <label>] [--preflight] [--receipt-out <path>]",
  );
}

function parseArgs(argv) {
  const options = {
    chainId: null,
    deploymentPath: null,
    abiManifestPath: null,
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
      case "--deployment-path":
        options.deploymentPath = path.resolve(process.cwd(), take(current));
        break;
      case "--abi-manifest-path":
        options.abiManifestPath = path.resolve(process.cwd(), take(current));
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
        if (current.startsWith("--")) {
          throw new Error(`Unknown option: ${current}`);
        }
        if (options.chainId !== null) {
          throw new Error(`Unexpected extra argument: ${current}`);
        }
        options.chainId = current;
        break;
    }
  }

  if (!options.chainId) {
    throw new Error("Missing <chain-id>");
  }

  return options;
}

function shouldSkipUpload(chainId) {
  return process.env.BRIDGE_NETWORK === "anvil" || String(chainId) === "31337";
}

function requiredFile(relativePath) {
  const localPath = path.join(repoRoot, relativePath);
  if (!fs.existsSync(localPath)) {
    throw new Error(`Missing bridge deployment artifact: ${localPath}`);
  }
  return { localPath, relativePath };
}

function optionalFile(relativePath) {
  const localPath = path.join(repoRoot, relativePath);
  return fs.existsSync(localPath) ? { localPath, relativePath } : null;
}

function collectBridgeArtifactFiles({ chainId, deploymentPath, abiManifestPath }) {
  return [
    deploymentPath
      ? { localPath: deploymentPath, relativePath: `bridge/deployments/${path.basename(deploymentPath)}` }
      : requiredFile(`bridge/deployments/bridge.${chainId}.json`),
    abiManifestPath
      ? { localPath: abiManifestPath, relativePath: `bridge/deployments/${path.basename(abiManifestPath)}` }
      : requiredFile(`bridge/deployments/bridge-abi-manifest.${chainId}.json`),
    requiredFile(`bridge/deployments/groth16.${chainId}.latest.json`),
    requiredFile(`bridge/deployments/groth16/${chainId}/circuit_final.zkey`),
    requiredFile(`bridge/deployments/groth16/${chainId}/verification_key.json`),
    requiredFile(`bridge/deployments/groth16/${chainId}/metadata.json`),
    optionalFile(`bridge/deployments/groth16/${chainId}/zkey_provenance.json`),
    requiredFile(`bridge/deployments/tokamak-zkp.${chainId}.latest.json`),
    optionalFile(`bridge/deployments/tokamak-zkp/${chainId}/build-metadata-mpc-setup.json`),
    optionalFile(`bridge/deployments/tokamak-zkp/${chainId}/crs_provenance.json`),
    requiredFile("scripts/zk/artifacts/reflection.latest.json"),
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
  const chainId = options.chainId;

  if (shouldSkipUpload(chainId)) {
    console.log(`Skipping bridge artifact upload for local network ${chainId}.`);
    return;
  }

  const config = resolveDriveUploadConfig();
  const drive = await createDriveClient(config);
  const timestamp = options.timestamp ?? createTimestampLabel();
  const targetSegments = [String(chainId), "bridge"];

  if (options.preflight) {
    await preflightExclusiveFolderPath(drive, config.folderId, targetSegments, timestamp);
    console.log(`Drive preflight succeeded for bridge/${chainId}/${timestamp}.`);
    return;
  }

  const files = collectBridgeArtifactFiles(options);
  const { leafId, leafUrl } = await createExclusiveFolderPath(drive, config.folderId, targetSegments, timestamp);

  await uploadFilesByRelativePath(drive, leafId, files);

  if (options.receiptOut) {
    writeUploadReceipt(options.receiptOut, {
      kind: "bridge",
      chainId: Number(chainId),
      timestamp,
      folderUrl: leafUrl,
      driveRootUrl: config.folderUrl,
      uploadedAt: new Date().toISOString(),
      files: files.map(({ relativePath }) => relativePath),
    });
  }

  console.log(`Uploaded bridge artifacts to: ${leafUrl}`);
  console.log(`Drive root: ${config.folderUrl}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
