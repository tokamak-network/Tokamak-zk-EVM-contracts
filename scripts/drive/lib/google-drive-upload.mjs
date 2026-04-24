import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { Readable } from "node:stream";
import { authenticate } from "@google-cloud/local-auth";
import { google } from "googleapis";
import dotenv from "dotenv";

dotenv.config();

const DRIVE_SCOPES = ["https://www.googleapis.com/auth/drive"];
const DRIVE_FOLDER_MIME_TYPE = "application/vnd.google-apps.folder";
const ARTIFACT_INDEX_FILE_NAME = "artifact-index.json";

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

export function resolveDriveUploadConfig() {
  const folderId = readRequiredEnv("TOKAMAK_MPC_DRIVE_FOLDER_ID");
  const oauthClientJsonPath = path.resolve(readRequiredEnv("GOOGLE_DRIVE_OAUTH_CLIENT_JSON_PATH"));
  const configuredTokenPath = readOptionalEnv("GOOGLE_DRIVE_OAUTH_TOKEN_PATH");
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

async function loadSavedCredentialsIfExist(tokenPath) {
  if (!tokenPath) {
    return null;
  }
  if (!fs.existsSync(tokenPath)) {
    return null;
  }

  const credentials = JSON.parse(fs.readFileSync(tokenPath, "utf8"));
  return google.auth.fromJSON(credentials);
}

async function saveCredentials(client, clientJsonPath, tokenPath) {
  if (!tokenPath) {
    return;
  }
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

async function assertAuthenticatedClient(authClient) {
  const headers = await authClient.getRequestHeaders("https://www.googleapis.com/drive/v3/files");
  const authorization = typeof headers.get === "function"
    ? headers.get("authorization")
    : headers.Authorization ?? headers.authorization;

  if (!authorization) {
    throw new Error(
      "Google OAuth did not produce an Authorization header. Re-run the command and complete the browser OAuth flow.",
    );
  }
}

export async function createDriveClient(config = resolveDriveUploadConfig()) {
  let authClient = await loadSavedCredentialsIfExist(config.oauthTokenPath);
  if (!authClient) {
    authClient = await authenticate({
      scopes: DRIVE_SCOPES,
      keyfilePath: config.oauthClientJsonPath,
    });
    await saveCredentials(authClient, config.oauthClientJsonPath, config.oauthTokenPath);
  }

  await assertAuthenticatedClient(authClient);

  return google.drive({ version: "v3", auth: authClient });
}

function escapeDriveQueryValue(value) {
  return value.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
}

async function findChildFolderId(drive, parentId, name) {
  const response = await drive.files.list({
    q: [
      `mimeType = '${DRIVE_FOLDER_MIME_TYPE}'`,
      `trashed = false`,
      `'${parentId}' in parents`,
      `name = '${escapeDriveQueryValue(name)}'`,
    ].join(" and "),
    fields: "files(id, name)",
    pageSize: 10,
    includeItemsFromAllDrives: true,
    supportsAllDrives: true,
  });

  return response.data.files?.[0]?.id ?? null;
}

async function findChildFileMetadata(drive, parentId, name) {
  const response = await drive.files.list({
    q: [
      `mimeType != '${DRIVE_FOLDER_MIME_TYPE}'`,
      `trashed = false`,
      `'${parentId}' in parents`,
      `name = '${escapeDriveQueryValue(name)}'`,
    ].join(" and "),
    fields: "files(id, name, size, md5Checksum, modifiedTime, webViewLink)",
    pageSize: 10,
    includeItemsFromAllDrives: true,
    supportsAllDrives: true,
  });

  const files = response.data.files ?? [];
  if (files.length > 1) {
    throw new Error(`Drive folder ${parentId} contains multiple files named ${name}.`);
  }
  return files[0] ?? null;
}

async function createFolder(drive, parentId, name) {
  const response = await drive.files.create({
    requestBody: {
      name,
      parents: [parentId],
      mimeType: DRIVE_FOLDER_MIME_TYPE,
    },
    fields: "id, webViewLink",
    supportsAllDrives: true,
  });

  const folderId = response.data.id;
  if (!folderId) {
    throw new Error(`Failed to create Drive folder: ${name}`);
  }
  return folderId;
}

async function ensureFolder(drive, parentId, name) {
  const existingId = await findChildFolderId(drive, parentId, name);
  if (existingId) {
    return existingId;
  }
  return createFolder(drive, parentId, name);
}

export async function ensureFolderPath(drive, rootFolderId, segments) {
  let currentId = rootFolderId;
  for (const segment of segments) {
    currentId = await ensureFolder(drive, currentId, segment);
  }
  return currentId;
}

export async function createExclusiveFolderPath(drive, rootFolderId, parentSegments, leafName) {
  const parentId = await ensureFolderPath(drive, rootFolderId, parentSegments);
  const existingLeafId = await findChildFolderId(drive, parentId, leafName);
  if (existingLeafId) {
    throw new Error(`Drive target already exists: ${[...parentSegments, leafName].join("/")}`);
  }
  const leafId = await createFolder(drive, parentId, leafName);
  return {
    parentId,
    leafId,
    leafUrl: `https://drive.google.com/drive/folders/${leafId}`,
  };
}

export async function preflightExclusiveFolderPath(drive, rootFolderId, parentSegments, leafName) {
  const parentId = await ensureFolderPath(drive, rootFolderId, parentSegments);
  const existingLeafId = await findChildFolderId(drive, parentId, leafName);
  if (existingLeafId) {
    throw new Error(`Drive target already exists: ${[...parentSegments, leafName].join("/")}`);
  }

  const probeName = `.upload-probe-${leafName}-${Date.now()}`;
  const probeId = await createFolder(drive, parentId, probeName);
  await drive.files.delete({
    fileId: probeId,
    supportsAllDrives: true,
  });

  return {
    parentId,
    parentUrl: `https://drive.google.com/drive/folders/${parentId}`,
    leafUrl: `https://drive.google.com/drive/folders/<pending:${leafName}>`,
  };
}

function guessMimeType(filePath) {
  if (filePath.endsWith(".json")) {
    return "application/json";
  }
  if (filePath.endsWith(".zkey") || filePath.endsWith(".rkyv") || filePath.endsWith(".ptau")) {
    return "application/octet-stream";
  }
  return "application/octet-stream";
}

async function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("error", reject);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

export async function uploadFile(drive, parentId, localPath, remoteName = path.basename(localPath)) {
  const response = await drive.files.create({
    requestBody: {
      name: remoteName,
      parents: [parentId],
    },
    media: {
      mimeType: guessMimeType(localPath),
      body: fs.createReadStream(localPath),
    },
    fields: "id, webViewLink",
    supportsAllDrives: true,
  });

  const fileId = response.data.id ?? null;
  if (!fileId) {
    throw new Error(`Failed to upload Drive file: ${localPath}`);
  }
  return {
    fileId,
    webViewLink: response.data.webViewLink ?? null,
  };
}

export async function uploadFilesByRelativePath(drive, leafFolderId, files) {
  const createdFolders = new Map([["", leafFolderId]]);
  const uploadedFiles = [];

  for (const { localPath, relativePath } of files) {
    const normalizedRelativePath = relativePath.split(path.sep).join("/");
    const rawDirectory = path.posix.dirname(normalizedRelativePath);
    const directory = rawDirectory === "." ? "" : rawDirectory;
    const fileName = path.posix.basename(normalizedRelativePath);

    let targetFolderId = createdFolders.get(directory);
    if (!targetFolderId) {
      const segments = directory.split("/").filter(Boolean);
      let currentPath = "";
      let currentFolderId = leafFolderId;
      for (const segment of segments) {
        currentPath = currentPath ? `${currentPath}/${segment}` : segment;
        const cachedId = createdFolders.get(currentPath);
        if (cachedId) {
          currentFolderId = cachedId;
          continue;
        }
        currentFolderId = await ensureFolder(drive, currentFolderId, segment);
        createdFolders.set(currentPath, currentFolderId);
      }
      targetFolderId = currentFolderId;
      createdFolders.set(directory, targetFolderId);
    }

    const stat = fs.statSync(localPath);
    const sha256 = await sha256File(localPath);
    const upload = await uploadFile(drive, targetFolderId, localPath, fileName);
    uploadedFiles.push({
      relativePath: normalizedRelativePath,
      fileId: upload.fileId,
      webViewLink: upload.webViewLink,
      sha256,
      size: stat.size,
    });
  }

  return uploadedFiles;
}

async function readJsonDriveFile(drive, fileId) {
  const response = await drive.files.get(
    {
      fileId,
      alt: "media",
      supportsAllDrives: true,
    },
    {
      responseType: "text",
    },
  );
  const text = typeof response.data === "string" ? response.data : JSON.stringify(response.data);
  return JSON.parse(text);
}

async function writeJsonDriveFile(drive, parentId, fileName, payload) {
  const content = `${JSON.stringify(payload, null, 2)}\n`;
  const existing = await findChildFileMetadata(drive, parentId, fileName);
  const media = {
    mimeType: "application/json",
    body: Readable.from([content]),
  };

  if (existing) {
    const response = await drive.files.update({
      fileId: existing.id,
      media,
      fields: "id, webViewLink, modifiedTime",
      supportsAllDrives: true,
    });
    return response.data;
  }

  const response = await drive.files.create({
    requestBody: {
      name: fileName,
      parents: [parentId],
    },
    media,
    fields: "id, webViewLink, modifiedTime",
    supportsAllDrives: true,
  });
  return response.data;
}

function createEmptyArtifactIndex(config) {
  return {
    schemaVersion: 1,
    updatedAt: null,
    driveRootFolderId: config.folderId,
    driveRootUrl: config.folderUrl,
    chains: {},
  };
}

async function loadArtifactIndex(drive, config) {
  const indexFile = await findChildFileMetadata(drive, config.folderId, ARTIFACT_INDEX_FILE_NAME);
  if (!indexFile) {
    return createEmptyArtifactIndex(config);
  }

  const index = await readJsonDriveFile(drive, indexFile.id);
  if (index.schemaVersion !== 1) {
    throw new Error(`Unsupported Drive artifact index schemaVersion: ${index.schemaVersion}`);
  }
  if (!index.chains || typeof index.chains !== "object" || Array.isArray(index.chains)) {
    throw new Error("Drive artifact index is missing a valid chains object.");
  }
  return index;
}

function uploadedFileIndex(uploadedFiles) {
  return Object.fromEntries(
    uploadedFiles.map((file) => [
      file.relativePath,
      {
        fileId: file.fileId,
        sha256: file.sha256,
        size: file.size,
      },
    ]),
  );
}

function chainEntry(index, chainId) {
  const key = String(chainId);
  index.chains[key] ??= {};
  return index.chains[key];
}

async function saveArtifactIndex(drive, config, index) {
  index.updatedAt = new Date().toISOString();
  index.driveRootFolderId = config.folderId;
  index.driveRootUrl = config.folderUrl;
  return writeJsonDriveFile(drive, config.folderId, ARTIFACT_INDEX_FILE_NAME, index);
}

export async function updateBridgeArtifactIndex({
  drive,
  config,
  chainId,
  timestamp,
  folderId,
  folderUrl,
  uploadedFiles,
}) {
  const index = await loadArtifactIndex(drive, config);
  const chain = chainEntry(index, chainId);
  chain.bridge = {
    timestamp,
    folderId,
    folderUrl,
    files: uploadedFileIndex(uploadedFiles),
  };
  await saveArtifactIndex(drive, config, index);
  return index;
}

export async function updateDappArtifactIndex({
  drive,
  config,
  dappName,
  bridgeChainId,
  appChainId,
  timestamp,
  folderId,
  folderUrl,
  uploadedFiles,
}) {
  const index = await loadArtifactIndex(drive, config);
  const chain = chainEntry(index, bridgeChainId);
  chain.dapps ??= {};
  chain.dapps[dappName] = {
    timestamp,
    folderId,
    folderUrl,
    appChainId,
    files: uploadedFileIndex(uploadedFiles),
  };
  await saveArtifactIndex(drive, config, index);
  return index;
}

export function createTimestampLabel(date = new Date()) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

export function writeUploadReceipt(receiptPath, receipt) {
  fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
}
