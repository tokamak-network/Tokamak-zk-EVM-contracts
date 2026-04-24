import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { authenticate } from "@google-cloud/local-auth";
import { google } from "googleapis";

const DRIVE_SCOPES = ["https://www.googleapis.com/auth/drive"];
const DRIVE_FOLDER_MIME_TYPE = "application/vnd.google-apps.folder";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..", "..");

function readRequiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export function resolveDriveUploadConfig() {
  const folderId = readRequiredEnv("TOKAMAK_MPC_DRIVE_FOLDER_ID");
  const oauthClientJsonPath = path.resolve(readRequiredEnv("TOKAMAK_MPC_DRIVE_OAUTH_CLIENT_JSON_PATH"));
  const configuredTokenPath = process.env.TOKAMAK_MPC_DRIVE_OAUTH_TOKEN_PATH?.trim();
  const oauthTokenPath = configuredTokenPath
    ? path.resolve(configuredTokenPath)
    : path.join(repoRoot, "cache", "google-drive-oauth-token.json");

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

export async function createDriveClient(config = resolveDriveUploadConfig()) {
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

  return response.data.id ?? null;
}

export async function uploadFilesByRelativePath(drive, leafFolderId, files) {
  const createdFolders = new Map([["", leafFolderId]]);

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

    await uploadFile(drive, targetFolderId, localPath, fileName);
  }
}

export function createTimestampLabel(date = new Date()) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

export function writeUploadReceipt(receiptPath, receipt) {
  fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
}
