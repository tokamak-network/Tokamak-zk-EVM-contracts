#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import { authenticate } from "@google-cloud/local-auth";
import { google } from "googleapis";
import yazl from "yazl";

dotenv.config();

const DRIVE_SCOPES = ["https://www.googleapis.com/auth/drive"];
const DRIVE_FOLDER_MIME_TYPE = "application/vnd.google-apps.folder";
const ARCHIVE_MIME_TYPE = "application/zip";
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
const outputDir = path.join(__dirname, "crs");
const tempDir = path.join(__dirname, ".tmp");
const provenancePath = path.join(outputDir, "zkey_provenance.json");

function readRequiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function readDriveUploadConfig() {
  const folderId = readRequiredEnv(DRIVE_FOLDER_ID_ENV);
  const oauthClientJsonPath = path.resolve(readRequiredEnv(DRIVE_OAUTH_CLIENT_PATH_ENV));
  const oauthTokenPath = path.resolve(readRequiredEnv(DRIVE_OAUTH_TOKEN_PATH_ENV));

  if (!fs.existsSync(oauthClientJsonPath)) {
    throw new Error(`Missing OAuth client JSON file: ${oauthClientJsonPath}`);
  }

  fs.mkdirSync(path.dirname(oauthTokenPath), { recursive: true });

  return {
    folderId,
    oauthClientJsonPath,
    oauthTokenPath,
    folderUrl: `https://drive.google.com/drive/folders/${folderId}`,
  };
}

async function loadSavedCredentialsIfExist(tokenPath) {
  if (!fs.existsSync(tokenPath)) {
    return null;
  }

  const credentials = JSON.parse(fs.readFileSync(tokenPath, "utf8"));
  return google.auth.fromJSON(credentials);
}

async function saveCredentials(client, clientJsonPath, tokenPath) {
  const keys = JSON.parse(fs.readFileSync(clientJsonPath, "utf8"));
  const key = keys.installed ?? keys.web;
  if (!key) {
    throw new Error(`OAuth client JSON is missing installed/web credentials: ${clientJsonPath}`);
  }
  if (!client.credentials.refresh_token) {
    throw new Error("Google OAuth flow did not return a refresh token.");
  }

  const payload = {
    type: "authorized_user",
    client_id: key.client_id,
    client_secret: key.client_secret,
    refresh_token: client.credentials.refresh_token,
  };
  fs.writeFileSync(tokenPath, `${JSON.stringify(payload, null, 2)}\n`);
}

async function createDriveClient(config) {
  let authClient = await loadSavedCredentialsIfExist(config.oauthTokenPath);
  if (!authClient) {
    authClient = await authenticate({
      scopes: DRIVE_SCOPES,
      keyfilePath: config.oauthClientJsonPath,
    });
    await saveCredentials(authClient, config.oauthClientJsonPath, config.oauthTokenPath);
  }

  return google.drive({ version: "v3", auth: authClient });
}

function escapeDriveQueryValue(value) {
  return value.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
}

async function validateDriveFolder(drive, config, archivePrefix) {
  const folderResponse = await drive.files.get({
    fileId: config.folderId,
    fields: "id,mimeType,capabilities(canAddChildren)",
    supportsAllDrives: true,
  });
  const folder = folderResponse.data;
  if (folder.mimeType !== DRIVE_FOLDER_MIME_TYPE) {
    throw new Error(`Drive folder id ${config.folderId} does not resolve to a Google Drive folder.`);
  }
  if (!folder.capabilities?.canAddChildren) {
    throw new Error(`Authenticated Google Drive user cannot upload into drive folder ${config.folderId}.`);
  }

  const query = [
    `'${escapeDriveQueryValue(config.folderId)}' in parents`,
    "trashed = false",
    `mimeType = '${ARCHIVE_MIME_TYPE}'`,
  ].join(" and ");
  const listing = await drive.files.list({
    q: query,
    fields: "files(id,name)",
    pageSize: 100,
    supportsAllDrives: true,
    includeItemsFromAllDrives: true,
  });
  const existingNames = (listing.data.files ?? [])
    .map((file) => file.name)
    .filter((name) => typeof name === "string" && name.startsWith(archivePrefix));

  if (existingNames.length > 0) {
    throw new Error(
      `Drive folder ${config.folderId} already contains Groth16 zkey archive(s) for this package version: ${existingNames.join(", ")}. Bump the package version before publishing again.`,
    );
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, payload) {
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`);
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

async function uploadArchive(drive, config, archivePath, archiveName) {
  const response = await drive.files.create({
    requestBody: {
      name: archiveName,
      parents: [config.folderId],
      mimeType: ARCHIVE_MIME_TYPE,
    },
    media: {
      mimeType: ARCHIVE_MIME_TYPE,
      body: fs.createReadStream(archivePath),
    },
    fields: "id,name,webViewLink",
    supportsAllDrives: true,
  });

  const fileId = response.data.id;
  if (!fileId) {
    throw new Error(`Drive upload for ${archiveName} succeeded without returning a file id.`);
  }

  await drive.permissions.create({
    fileId,
    requestBody: {
      type: "anyone",
      role: "reader",
      allowFileDiscovery: false,
    },
    supportsAllDrives: true,
  });
  await drive.files.update({
    fileId,
    requestBody: {
      copyRequiresWriterPermission: false,
    },
    fields: "id",
    supportsAllDrives: true,
  });

  return `https://drive.google.com/uc?id=${fileId}&export=download`;
}

export async function publishUpdateTreeSetup() {
  assertOutputFiles();
  const config = readDriveUploadConfig();
  const drive = await createDriveClient(config);
  const provenance = readJson(provenancePath);
  const originalProvenance = structuredClone(provenance);

  await validateProvenanceHashes(provenance);

  const archiveName = buildArchiveName(provenance);
  const archiveVersionPrefix = archiveName.replace(/-\d{8}T\d{6}Z\.zip$/, "-");
  await validateDriveFolder(drive, config, archiveVersionPrefix);

  provenance.published_folder_url = config.folderUrl;
  provenance.published_archive_name = archiveName;
  provenance.zkey_download_url = null;
  writeJson(provenancePath, provenance);

  const archivePath = path.join(tempDir, archiveName);
  try {
    await createArchive(archivePath);
    const downloadUrl = await uploadArchive(drive, config, archivePath, archiveName);
    provenance.zkey_download_url = downloadUrl;
    writeJson(provenancePath, provenance);
    console.log(`Uploaded Groth16 zkey archive ${archiveName} to ${config.folderUrl}`);
  } catch (error) {
    writeJson(provenancePath, originalProvenance);
    throw error;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  publishUpdateTreeSetup().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
