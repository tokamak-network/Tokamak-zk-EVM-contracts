#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import yazl from "yazl";

dotenv.config();

const DRIVE_FOLDER_ID_ENV = "GROTH16_MPC_DRIVE_FOLDER_ID";
const DRIVE_OAUTH_CLIENT_PATH_ENV = "GOOGLE_DRIVE_OAUTH_CLIENT_JSON_PATH";
const DRIVE_OAUTH_TOKEN_PATH_ENV = "GOOGLE_DRIVE_OAUTH_TOKEN_PATH";
const ARCHIVE_PREFIX = "tokamak-private-dapps-groth16";
const FINAL_OUTPUT_FILES = [
  "circuit_final.zkey",
  "verification_key.json",
  "metadata.json",
  "zkey_provenance.json",
];

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const groth16Root = path.resolve(__dirname, "..");
const outputDir = path.join(__dirname, "crs");
const tempDir = path.join(__dirname, ".tmp");
const packageJsonPath = path.join(groth16Root, "package.json");
const rustManifestPath = path.join(__dirname, "Cargo.toml");
const provenancePath = path.join(outputDir, "zkey_provenance.json");

function readRequiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function readOptionalEnv(name) {
  const value = process.env[name]?.trim();
  return value ? value : null;
}

function readDriveUploadConfig() {
  const folderId = readRequiredEnv(DRIVE_FOLDER_ID_ENV);
  const oauthClientJsonPath = path.resolve(readRequiredEnv(DRIVE_OAUTH_CLIENT_PATH_ENV));
  const configuredTokenPath = readOptionalEnv(DRIVE_OAUTH_TOKEN_PATH_ENV);
  const oauthTokenPath = configuredTokenPath ? path.resolve(configuredTokenPath) : null;

  if (!fs.existsSync(oauthClientJsonPath)) {
    throw new Error(`Missing OAuth client JSON file: ${oauthClientJsonPath}`);
  }

  if (oauthTokenPath) {
    fs.mkdirSync(path.dirname(oauthTokenPath), { recursive: true });
  }

  return {
    folderId,
    oauthClientJsonPath,
    oauthTokenPath,
    folderUrl: `https://drive.google.com/drive/folders/${folderId}`,
  };
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, payload) {
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`);
}

function readPackageVersion() {
  const packageJson = readJson(packageJsonPath);
  const version = packageJson.version;
  if (typeof version !== "string" || version.length === 0) {
    throw new Error(`${packageJsonPath} is missing a package version.`);
  }
  return version;
}

function assertOutputFiles() {
  for (const fileName of FINAL_OUTPUT_FILES) {
    const filePath = path.join(outputDir, fileName);
    if (!fs.existsSync(filePath)) {
      throw new Error(`Missing Groth16 MPC output file: ${filePath}`);
    }
  }
}

function buildArchiveTimestamp(provenance) {
  const generatedAt = new Date(provenance.generated_at_utc);
  if (Number.isNaN(generatedAt.getTime())) {
    throw new Error(`Invalid generated_at_utc in zkey provenance: ${provenance.generated_at_utc}`);
  }
  return generatedAt.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function buildArchiveName(provenance) {
  const version = provenance.backend_version;
  if (typeof version !== "string" || version.length === 0) {
    throw new Error("zkey_provenance.json is missing backend_version.");
  }
  return `${ARCHIVE_PREFIX}-v${version}-${buildArchiveTimestamp(provenance)}.zip`;
}

function buildArchiveVersionPrefix(version = readPackageVersion()) {
  return `${ARCHIVE_PREFIX}-v${version}-`;
}

async function hashFile(filePath) {
  return new Promise((resolve, reject) => {
    const hasher = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hasher.update(chunk));
    stream.on("end", () => resolve(hasher.digest("hex")));
    stream.on("error", reject);
  });
}

async function validateProvenanceHashes(provenance) {
  const checks = [
    ["zkey_sha256", "circuit_final.zkey"],
    ["metadata_sha256", "metadata.json"],
    ["verification_key_sha256", "verification_key.json"],
  ];

  if (provenance.phase1_final_ptau_file && provenance.phase1_final_ptau_sha256) {
    checks.push(["phase1_final_ptau_sha256", provenance.phase1_final_ptau_file]);
  }

  for (const [field, fileName] of checks) {
    const expected = provenance[field];
    if (typeof expected !== "string" || expected.length === 0) {
      throw new Error(`zkey_provenance.json is missing ${field}.`);
    }
    const actual = await hashFile(path.join(outputDir, fileName));
    if (actual !== expected) {
      throw new Error(`${fileName} sha256 mismatch. expected=${expected} actual=${actual}`);
    }
  }
}

async function createArchive(archivePath) {
  fs.mkdirSync(path.dirname(archivePath), { recursive: true });

  const zipFile = new yazl.ZipFile();
  for (const fileName of FINAL_OUTPUT_FILES) {
    zipFile.addFile(path.join(outputDir, fileName), fileName);
  }
  zipFile.end();

  await pipeline(zipFile.outputStream, fs.createWriteStream(archivePath));
}

function buildRustDriveArgs(config) {
  const args = [
    "--drive-folder-id",
    config.folderId,
    "--oauth-client-json",
    config.oauthClientJsonPath,
  ];
  if (config.oauthTokenPath) {
    args.push("--oauth-token-path", config.oauthTokenPath);
  }
  return args;
}

function runRustDriveCommand(args) {
  execFileSync(
    "cargo",
    [
      "run",
      "--manifest-path",
      rustManifestPath,
      "--release",
      "--",
      ...args,
    ],
    {
      cwd: groth16Root,
      stdio: "inherit",
    },
  );
}

function preflightDriveUpload(config, archivePrefix) {
  runRustDriveCommand([
    "drive-preflight",
    ...buildRustDriveArgs(config),
    "--archive-prefix",
    archivePrefix,
  ]);
}

function uploadArchive(config, archivePath, archiveName) {
  const resultPath = path.join(tempDir, `${archiveName}.upload-result.json`);
  fs.rmSync(resultPath, { force: true });
  runRustDriveCommand([
    "drive-upload-archive",
    ...buildRustDriveArgs(config),
    "--archive-path",
    archivePath,
    "--archive-name",
    archiveName,
    "--result-json",
    resultPath,
  ]);
  return readJson(resultPath).zkey_download_url;
}

export async function publishUpdateTreeSetup() {
  assertOutputFiles();
  const config = readDriveUploadConfig();
  const provenance = readJson(provenancePath);
  const originalProvenance = structuredClone(provenance);

  await validateProvenanceHashes(provenance);

  const archiveName = buildArchiveName(provenance);

  provenance.published_folder_url = config.folderUrl;
  provenance.published_archive_name = archiveName;
  provenance.zkey_download_url = null;
  writeJson(provenancePath, provenance);

  const archivePath = path.join(tempDir, archiveName);
  try {
    await createArchive(archivePath);
    const downloadUrl = uploadArchive(config, archivePath, archiveName);
    provenance.zkey_download_url = downloadUrl;
    writeJson(provenancePath, provenance);
    console.log(`Uploaded Groth16 zkey archive ${archiveName} to ${config.folderUrl}`);
  } catch (error) {
    writeJson(provenancePath, originalProvenance);
    throw error;
  }
}

export async function preflightUpdateTreeSetupPublish() {
  const config = readDriveUploadConfig();
  const version = readPackageVersion();
  preflightDriveUpload(config, buildArchiveVersionPrefix(version));
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  const command = process.argv.includes("--preflight")
    ? preflightUpdateTreeSetupPublish
    : publishUpdateTreeSetup;

  command().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
