#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  createDriveClient,
  createExclusiveFolderPath,
  preflightExclusiveFolderPath,
  resolveDriveUploadConfigWithFolderId,
  updateBridgeArtifactIndex,
  uploadFilesByRelativePath,
  writeUploadReceipt,
} from "../../scripts/drive/lib/google-drive-upload.mjs";
import {
  bridgeArtifactPaths,
  bridgeArtifactPathsFromDir,
  createTimestampLabel,
  latestBridgeTimestampLabel,
} from "../../scripts/deployment/lib/deployment-layout.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const DEFAULT_BRIDGE_DEPLOYMENT_DRIVE_FOLDER_ID = "12HuHeR8vCWfkeGdjTAFKhv0FU-AG4aUJ";

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

function resolveBridgeDriveUploadConfig() {
  const folderId =
    process.env.BRIDGE_DEPLOYMENT_DRIVE_FOLDER_ID?.trim()
    || DEFAULT_BRIDGE_DEPLOYMENT_DRIVE_FOLDER_ID;
  return resolveDriveUploadConfigWithFolderId(folderId);
}

function collectBridgeArtifactFiles({ chainId, deploymentPath, abiManifestPath }) {
  const explicitSnapshotDir = deploymentPath || abiManifestPath
    ? path.dirname(deploymentPath ?? abiManifestPath)
    : null;
  let snapshot;
  if (explicitSnapshotDir) {
    snapshot = bridgeArtifactPathsFromDir(explicitSnapshotDir, chainId);
  } else {
    const latestTimestampLabel = latestBridgeTimestampLabel(repoRoot, chainId);
    if (!latestTimestampLabel) {
      throw new Error(`No bridge artifact snapshot exists for chain ${chainId}.`);
    }
    snapshot = bridgeArtifactPaths(repoRoot, chainId, latestTimestampLabel);
  }

  return [
    deploymentPath
      ? { localPath: deploymentPath, relativePath: path.basename(deploymentPath) }
      : { localPath: snapshot.deploymentPath, relativePath: path.basename(snapshot.deploymentPath) },
    abiManifestPath
      ? { localPath: abiManifestPath, relativePath: path.basename(abiManifestPath) }
      : { localPath: snapshot.abiManifestPath, relativePath: path.basename(snapshot.abiManifestPath) },
    { localPath: snapshot.grothManifestPath, relativePath: path.basename(snapshot.grothManifestPath) },
    { localPath: snapshot.grothZkeyPath, relativePath: "groth16/circuit_final.zkey" },
    { localPath: snapshot.grothVerificationKeyPath, relativePath: "groth16/verification_key.json" },
    { localPath: snapshot.grothMetadataPath, relativePath: "groth16/metadata.json" },
    fs.existsSync(snapshot.grothZkeyProvenancePath)
      ? { localPath: snapshot.grothZkeyProvenancePath, relativePath: "groth16/zkey_provenance.json" }
      : null,
    { localPath: snapshot.tokamakZkpManifestPath, relativePath: path.basename(snapshot.tokamakZkpManifestPath) },
    fs.existsSync(snapshot.tokamakBuildMetadataPath)
      ? { localPath: snapshot.tokamakBuildMetadataPath, relativePath: "tokamak-zkp/build-metadata-mpc-setup.json" }
      : null,
    fs.existsSync(snapshot.tokamakCrsProvenancePath)
      ? { localPath: snapshot.tokamakCrsProvenancePath, relativePath: "tokamak-zkp/crs_provenance.json" }
      : null,
    { localPath: snapshot.reflectionManifestPath, relativePath: path.basename(snapshot.reflectionManifestPath) },
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

  const config = resolveBridgeDriveUploadConfig();
  const drive = await createDriveClient(config);
  const timestamp = options.timestamp ?? createTimestampLabel();
  const targetSegments = [`chain-id-${chainId}`, "bridge"];

  if (options.preflight) {
    await preflightExclusiveFolderPath(drive, config.folderId, targetSegments, timestamp);
    console.log(`Drive preflight succeeded for chain-id-${chainId}/bridge/${timestamp}.`);
    return;
  }

  const files = collectBridgeArtifactFiles(options);
  const { leafId, leafUrl } = await createExclusiveFolderPath(drive, config.folderId, targetSegments, timestamp);

  const uploadedFiles = await uploadFilesByRelativePath(drive, leafId, files);
  await updateBridgeArtifactIndex({
    drive,
    config,
    chainId: Number(chainId),
    timestamp,
    folderId: leafId,
    folderUrl: leafUrl,
    uploadedFiles,
  });

  if (options.receiptOut) {
    writeUploadReceipt(options.receiptOut, {
      kind: "bridge",
      chainId: Number(chainId),
      timestamp,
      folderUrl: leafUrl,
      driveRootUrl: config.folderUrl,
      uploadedAt: new Date().toISOString(),
      files: files.map(({ relativePath }) => relativePath),
      artifactIndex: "artifact-index.json",
    });
  }

  console.log(`Uploaded bridge artifacts to: ${leafUrl}`);
  console.log(`Drive root: ${config.folderUrl}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
