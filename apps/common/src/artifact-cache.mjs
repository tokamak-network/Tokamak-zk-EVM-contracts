import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { createRequire } from "node:module";

export const DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID = "11nM-VT0ZJlBdZUdFPGawqxvHNpXm1sXR";
export const PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID = "1jAIBqV-KG6PxFPDFpgtg9PDIceDDqk6N";

const DRIVE_DOWNLOAD_BASE_URL = "https://drive.google.com/uc?export=download";
const DRIVE_FOLDER_BASE_URL = "https://drive.google.com/drive/folders";
const GROTH16_MPC_ARCHIVE_PREFIX = "tokamak-private-dapps-groth16";
const GROTH16_MPC_ARCHIVE_PATTERN =
  /^tokamak-private-dapps-groth16-v(\d+)\.(\d+)\.(\d+)(?:[-+][^-]+)?-(\d{8}T\d{6}Z)\.zip$/;
const TIMESTAMP_LABEL_PATTERN = /^\d{8}T\d{6}Z$/;
const require = createRequire(import.meta.url);
const yauzl = require("yauzl");
let latestGroth16MpcArchivePromise = null;

export function defaultArtifactCacheBaseRoot() {
  return path.join(os.homedir(), "tokamak-private-channels");
}

export function resolveArtifactCacheBaseRoot(cacheBaseRoot = process.env.PRIVATE_STATE_ARTIFACT_CACHE_ROOT
  ?? defaultArtifactCacheBaseRoot()) {
  return path.resolve(cacheBaseRoot);
}

export function privateStateCliArtifactRoot(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(resolveArtifactCacheBaseRoot(cacheBaseRoot), "dapps", "private-state");
}

export function privateStateCliArtifactChainDir(cacheBaseRoot = resolveArtifactCacheBaseRoot(), chainId) {
  return path.join(privateStateCliArtifactRoot(cacheBaseRoot), `chain-id-${requireChainId(chainId)}`);
}

export function privateStateCliArtifactPaths(cacheBaseRoot = resolveArtifactCacheBaseRoot(), chainId) {
  const normalizedChainId = requireChainId(chainId);
  const rootDir = privateStateCliArtifactChainDir(cacheBaseRoot, normalizedChainId);
  return {
    rootDir,
    bridgeDeploymentPath: path.join(rootDir, `bridge.${normalizedChainId}.json`),
    bridgeAbiManifestPath: path.join(rootDir, `bridge-abi-manifest.${normalizedChainId}.json`),
    grothManifestPath: path.join(rootDir, `groth16.${normalizedChainId}.latest.json`),
    grothZkeyPath: path.join(rootDir, "circuit_final.zkey"),
    dappDeploymentPath: path.join(rootDir, `deployment.${normalizedChainId}.latest.json`),
    dappStorageLayoutPath: path.join(rootDir, `storage-layout.${normalizedChainId}.latest.json`),
    privateStateControllerAbiPath: path.join(rootDir, "PrivateStateController.callable-abi.json"),
    dappRegistrationPath: path.join(rootDir, `dapp-registration.${normalizedChainId}.json`),
  };
}

export async function installPrivateStateCliArtifacts({
  dappName,
  indexFileId = process.env.PRIVATE_STATE_DRIVE_ARTIFACT_INDEX_FILE_ID
    ?? process.env.TOKAMAK_ARTIFACT_INDEX_FILE_ID
    ?? DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  cacheBaseRoot,
  localDeploymentBaseRoot,
  localChainIds = [31337],
} = {}) {
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const normalizedCacheBaseRoot = resolveArtifactCacheBaseRoot(cacheBaseRoot);
  const normalizedLocalDeploymentBaseRoot = localDeploymentBaseRoot
    ? path.resolve(localDeploymentBaseRoot)
    : null;
  const index = await fetchPublicArtifactIndex(indexFileId);
  const installed = [];

  for (const chainId of Object.keys(index.chains).sort(compareChainIds)) {
    const chain = index.chains[chainId];
    if (!chain?.bridge?.timestamp || !chain?.bridge?.files || !chain.dapps?.[normalizedDappName]) {
      continue;
    }
    installed.push(await materializePrivateStateCliDeployment({
      index,
      chainId,
      dappName: normalizedDappName,
      cacheBaseRoot: normalizedCacheBaseRoot,
      source: "drive",
    }));
  }

  if (normalizedLocalDeploymentBaseRoot) {
    for (const chainId of localChainIds) {
      installed.push(await materializeLocalPrivateStateCliDeployment({
        chainId,
        dappName: normalizedDappName,
        cacheBaseRoot: normalizedCacheBaseRoot,
        localDeploymentBaseRoot: normalizedLocalDeploymentBaseRoot,
      }));
    }
  }

  if (installed.length === 0) {
    throw new Error(`No installable artifacts found for ${normalizedDappName}.`);
  }

  return {
    cacheBaseRoot: normalizedCacheBaseRoot,
    artifactRoot: privateStateCliArtifactRoot(normalizedCacheBaseRoot),
    installed,
  };
}

async function materializePrivateStateCliDeployment({
  index,
  chainId,
  dappName,
  cacheBaseRoot,
  source,
}) {
  const normalizedChainId = String(requireChainId(chainId));
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const chain = index.chains[normalizedChainId];
  if (!chain) {
    throw new Error(`Drive artifact index does not contain chain ${normalizedChainId}.`);
  }
  if (!chain.bridge?.timestamp || !chain.bridge?.files) {
    throw new Error(`Drive artifact index is missing bridge artifacts for chain ${normalizedChainId}.`);
  }

  const dapp = chain.dapps?.[normalizedDappName];
  if (!dapp?.timestamp || !dapp?.files) {
    throw new Error(
      `Drive artifact index is missing ${normalizedDappName} artifacts for chain ${normalizedChainId}.`,
    );
  }

  const paths = privateStateCliArtifactPaths(cacheBaseRoot, normalizedChainId);
  fs.rmSync(paths.rootDir, { recursive: true, force: true });
  fs.mkdirSync(paths.rootDir, { recursive: true });

  await materializeSelectedDriveFiles({
    targetDir: paths.rootDir,
    files: chain.bridge.files,
    selectedFiles: [
      [`bridge.${normalizedChainId}.json`, path.basename(paths.bridgeDeploymentPath)],
      [`bridge-abi-manifest.${normalizedChainId}.json`, path.basename(paths.bridgeAbiManifestPath)],
      [`groth16.${normalizedChainId}.latest.json`, path.basename(paths.grothManifestPath)],
    ],
  });
  await downloadLatestPublicGroth16MpcArtifacts({
    outputDir: paths.rootDir,
    selectedFiles: [
      ["circuit_final.zkey", path.basename(paths.grothZkeyPath)],
    ],
  });
  await materializeSelectedDriveFiles({
    targetDir: paths.rootDir,
    files: dapp.files,
    selectedFiles: [
      [`deployment.${normalizedChainId}.latest.json`, path.basename(paths.dappDeploymentPath)],
      [`storage-layout.${normalizedChainId}.latest.json`, path.basename(paths.dappStorageLayoutPath)],
      ["PrivateStateController.callable-abi.json", path.basename(paths.privateStateControllerAbiPath)],
      [`dapp-registration.${normalizedChainId}.json`, path.basename(paths.dappRegistrationPath)],
    ],
  });
  rewriteFlatGroth16Manifest(paths.grothManifestPath, paths.grothZkeyPath);

  return {
    chainId: Number(normalizedChainId),
    source,
    artifactDir: paths.rootDir,
    bridgeTimestamp: chain.bridge.timestamp,
    dappTimestamp: dapp.timestamp,
  };
}

async function materializeLocalPrivateStateCliDeployment({
  chainId,
  dappName,
  cacheBaseRoot,
  localDeploymentBaseRoot,
}) {
  const normalizedChainId = String(requireChainId(chainId));
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const bridgeRoot = path.join(
    localDeploymentBaseRoot,
    "deployment",
    `chain-id-${normalizedChainId}`,
    "bridge",
  );
  const dappRoot = path.join(
    localDeploymentBaseRoot,
    "deployment",
    `chain-id-${normalizedChainId}`,
    "dapps",
    normalizedDappName,
  );
  const bridgeTimestamp = requireLatestTimestampLabel(bridgeRoot, `bridge artifacts for chain ${normalizedChainId}`);
  const dappTimestamp = requireLatestTimestampLabel(dappRoot, `${normalizedDappName} artifacts for chain ${normalizedChainId}`);
  const bridgeDir = path.join(bridgeRoot, bridgeTimestamp);
  const dappDir = path.join(dappRoot, dappTimestamp);
  const paths = privateStateCliArtifactPaths(cacheBaseRoot, normalizedChainId);
  fs.rmSync(paths.rootDir, { recursive: true, force: true });
  fs.mkdirSync(paths.rootDir, { recursive: true });

  materializeSelectedLocalFiles({
    targetDir: paths.rootDir,
    selectedFiles: [
      [path.join(bridgeDir, `bridge.${normalizedChainId}.json`), path.basename(paths.bridgeDeploymentPath)],
      [path.join(bridgeDir, `bridge-abi-manifest.${normalizedChainId}.json`), path.basename(paths.bridgeAbiManifestPath)],
      [path.join(bridgeDir, `groth16.${normalizedChainId}.latest.json`), path.basename(paths.grothManifestPath)],
      [path.join(dappDir, `deployment.${normalizedChainId}.latest.json`), path.basename(paths.dappDeploymentPath)],
      [path.join(dappDir, `storage-layout.${normalizedChainId}.latest.json`), path.basename(paths.dappStorageLayoutPath)],
      [path.join(dappDir, "PrivateStateController.callable-abi.json"), path.basename(paths.privateStateControllerAbiPath)],
      [path.join(dappDir, `dapp-registration.${normalizedChainId}.json`), path.basename(paths.dappRegistrationPath)],
    ],
  });
  await downloadLatestPublicGroth16MpcArtifacts({
    outputDir: paths.rootDir,
    selectedFiles: [
      ["circuit_final.zkey", path.basename(paths.grothZkeyPath)],
    ],
  });
  rewriteFlatGroth16Manifest(paths.grothManifestPath, paths.grothZkeyPath);

  return {
    chainId: Number(normalizedChainId),
    source: "local",
    artifactDir: paths.rootDir,
    bridgeTimestamp,
    dappTimestamp,
  };
}

async function materializeSelectedDriveFiles({ targetDir, files, selectedFiles }) {
  for (const [relativePath, targetName, options = {}] of selectedFiles) {
    const metadata = files[relativePath];
    if (!metadata) {
      if (options.optional) {
        continue;
      }
      throw new Error(`Drive artifact index is missing required file ${relativePath}.`);
    }
    validateDriveFileMetadata(relativePath, metadata);
    const targetPath = path.join(targetDir, targetName);
    if (await cachedFileMatches(targetPath, metadata)) {
      continue;
    }

    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    const tempPath = `${targetPath}.tmp-${process.pid}-${Date.now()}`;
    try {
      await downloadPublicDriveFileToPath(metadata.fileId, tempPath);
      const downloaded = fs.statSync(tempPath);
      if (downloaded.size !== Number(metadata.size)) {
        throw new Error(
          `Downloaded ${relativePath} size mismatch: expected ${metadata.size}, received ${downloaded.size}.`,
        );
      }
      const downloadedSha256 = await sha256File(tempPath);
      if (downloadedSha256 !== metadata.sha256) {
        throw new Error(
          `Downloaded ${relativePath} sha256 mismatch: expected ${metadata.sha256}, received ${downloadedSha256}.`,
        );
      }
      fs.renameSync(tempPath, targetPath);
    } finally {
      fs.rmSync(tempPath, { force: true });
    }
  }
}

function materializeSelectedLocalFiles({ targetDir, selectedFiles }) {
  for (const [sourcePath, targetName, options = {}] of selectedFiles) {
    if (!fs.existsSync(sourcePath)) {
      if (options.optional) {
        continue;
      }
      throw new Error(`Missing local deployment artifact: ${sourcePath}`);
    }
    const targetPath = path.join(targetDir, targetName);
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.copyFileSync(sourcePath, targetPath);
  }
}

export async function downloadLatestPublicGroth16MpcArtifacts({
  outputDir,
  selectedFiles = [
    "circuit_final.zkey",
    "verification_key.json",
    "metadata.json",
    "zkey_provenance.json",
  ],
} = {}) {
  const normalizedOutputDir = path.resolve(requireNonEmptyString(outputDir, "outputDir"));
  const normalizedSelection = normalizeGroth16MpcArtifactSelection(selectedFiles);
  const archive = await loadLatestPublicGroth16MpcArchive();
  const archiveFileNames = [...new Set([
    ...normalizedSelection.map((entry) => entry.archivePath),
    "zkey_provenance.json",
  ])];
  const extracted = await extractZipEntriesFromBuffer(archive.buffer, archiveFileNames);
  const provenance = parseGroth16MpcProvenance(extracted.get("zkey_provenance.json"));
  const installedFiles = [];

  fs.mkdirSync(normalizedOutputDir, { recursive: true });

  for (const { archivePath, targetName } of normalizedSelection) {
    let content = extracted.get(archivePath);
    if (!content) {
      throw new Error(`Groth16 MPC archive ${archive.archiveName} is missing ${archivePath}.`);
    }
    if (archivePath === "zkey_provenance.json") {
      content = rewriteDownloadedGroth16MpcProvenance(content, archive);
    }

    validateGroth16MpcArtifactHash({ archiveName: archive.archiveName, archivePath, content, provenance });

    const targetPath = resolveSafeOutputPath(normalizedOutputDir, targetName);
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    const tempPath = `${targetPath}.tmp-${process.pid}-${Date.now()}`;
    try {
      fs.writeFileSync(tempPath, content);
      fs.renameSync(tempPath, targetPath);
    } finally {
      fs.rmSync(tempPath, { force: true });
    }
    installedFiles.push({ archivePath, targetPath });
  }

  return {
    source: "drive",
    folderId: PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID,
    folderUrl: `${DRIVE_FOLDER_BASE_URL}/${PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID}`,
    archiveName: archive.archiveName,
    archiveFileId: archive.fileId,
    installedFiles,
  };
}

async function loadLatestPublicGroth16MpcArchive() {
  if (!latestGroth16MpcArchivePromise) {
    latestGroth16MpcArchivePromise = (async () => {
      const archive = await findLatestPublicGroth16MpcArchive();
      const buffer = await downloadPublicDriveFileToBuffer(archive.fileId);
      return { ...archive, buffer };
    })();
  }
  return latestGroth16MpcArchivePromise;
}

async function findLatestPublicGroth16MpcArchive() {
  const folderUrl = `${DRIVE_FOLDER_BASE_URL}/${PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID}`;
  const response = await fetch(folderUrl, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`Failed to read public Groth16 MPC Drive folder: HTTP ${response.status}.`);
  }

  const html = await response.text();
  const archives = parsePublicGroth16MpcArchiveListing(html);
  if (archives.length === 0) {
    throw new Error(`No ${GROTH16_MPC_ARCHIVE_PREFIX} archive found in ${folderUrl}.`);
  }
  return archives.sort(compareGroth16MpcArchives).at(-1);
}

function parsePublicGroth16MpcArchiveListing(html) {
  const normalizedHtml = decodeHtmlEntities(html)
    .replace(/\\u003d/g, "=")
    .replace(/\\u0026/g, "&")
    .replace(/\\u003c/g, "<")
    .replace(/\\u003e/g, ">");
  const archiveEntryPattern =
    /\[null,"([A-Za-z0-9_-]{20,})"\][\s\S]{0,1600}?"(tokamak-private-dapps-groth16-v[^"]+?\.zip)"/g;
  const archivesByKey = new Map();
  let match;

  while ((match = archiveEntryPattern.exec(normalizedHtml))) {
    const [, fileId, archiveName] = match;
    const archiveVersion = parseGroth16MpcArchiveName(archiveName);
    if (!archiveVersion) {
      continue;
    }
    archivesByKey.set(`${fileId}:${archiveName}`, {
      fileId,
      archiveName,
      ...archiveVersion,
    });
  }

  return [...archivesByKey.values()];
}

function parseGroth16MpcArchiveName(archiveName) {
  const match = GROTH16_MPC_ARCHIVE_PATTERN.exec(archiveName);
  if (!match) {
    return null;
  }
  const [, major, minor, patch, timestamp] = match;
  return {
    version: [Number(major), Number(minor), Number(patch)],
    timestamp,
  };
}

function compareGroth16MpcArchives(left, right) {
  for (let i = 0; i < 3; i += 1) {
    const diff = left.version[i] - right.version[i];
    if (diff !== 0) {
      return diff;
    }
  }
  return left.timestamp.localeCompare(right.timestamp)
    || left.archiveName.localeCompare(right.archiveName)
    || left.fileId.localeCompare(right.fileId);
}

function normalizeGroth16MpcArtifactSelection(selectedFiles) {
  if (!Array.isArray(selectedFiles) || selectedFiles.length === 0) {
    throw new Error("selectedFiles must contain at least one Groth16 MPC artifact.");
  }

  return selectedFiles.map((entry) => {
    if (Array.isArray(entry)) {
      const [archivePath, targetName = archivePath] = entry;
      return {
        archivePath: requireSafeZipEntryPath(archivePath),
        targetName: requireSafeRelativeOutputPath(targetName),
      };
    }
    return {
      archivePath: requireSafeZipEntryPath(entry),
      targetName: requireSafeRelativeOutputPath(entry),
    };
  });
}

function requireSafeZipEntryPath(value) {
  const normalized = requireNonEmptyString(value, "archivePath").replace(/\\/g, "/");
  if (normalized.startsWith("/") || normalized.split("/").includes("..")) {
    throw new Error(`Unsafe Groth16 MPC archive path: ${value}`);
  }
  return normalized;
}

function requireSafeRelativeOutputPath(value) {
  const normalized = requireNonEmptyString(value, "targetName");
  if (path.isAbsolute(normalized) || normalized.split(/[\\/]/).includes("..")) {
    throw new Error(`Unsafe Groth16 MPC output path: ${value}`);
  }
  return normalized;
}

function resolveSafeOutputPath(outputDir, relativePath) {
  const resolved = path.resolve(outputDir, relativePath);
  if (resolved !== outputDir && !resolved.startsWith(`${outputDir}${path.sep}`)) {
    throw new Error(`Groth16 MPC output path escapes ${outputDir}: ${relativePath}`);
  }
  return resolved;
}

function extractZipEntriesFromBuffer(buffer, fileNames) {
  const wanted = new Set(fileNames.map(requireSafeZipEntryPath));
  const extracted = new Map();

  return new Promise((resolve, reject) => {
    yauzl.fromBuffer(buffer, { lazyEntries: true }, (openError, zipFile) => {
      if (openError) {
        reject(openError);
        return;
      }

      zipFile.on("entry", (entry) => {
        if (!wanted.has(entry.fileName)) {
          zipFile.readEntry();
          return;
        }

        zipFile.openReadStream(entry, (streamError, stream) => {
          if (streamError) {
            reject(streamError);
            return;
          }

          const chunks = [];
          stream.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
          stream.on("error", reject);
          stream.on("end", () => {
            extracted.set(entry.fileName, Buffer.concat(chunks));
            zipFile.readEntry();
          });
        });
      });
      zipFile.on("end", () => resolve(extracted));
      zipFile.on("error", reject);
      zipFile.readEntry();
    });
  });
}

function parseGroth16MpcProvenance(buffer) {
  if (!buffer) {
    return null;
  }
  try {
    return JSON.parse(buffer.toString("utf8"));
  } catch (error) {
    throw new Error(`Groth16 MPC archive contains invalid zkey_provenance.json: ${error.message}`);
  }
}

function validateGroth16MpcArtifactHash({ archiveName, archivePath, content, provenance }) {
  if (!provenance) {
    return;
  }

  const hashFields = {
    "circuit_final.zkey": "zkey_sha256",
    "verification_key.json": "verification_key_sha256",
    "metadata.json": "metadata_sha256",
  };
  const hashField = hashFields[archivePath];
  if (!hashField) {
    return;
  }

  const expected = provenance[hashField];
  if (typeof expected !== "string" || !/^[0-9a-f]{64}$/i.test(expected)) {
    throw new Error(`Groth16 MPC archive ${archiveName} provenance is missing ${hashField}.`);
  }
  const actual = sha256Buffer(content);
  if (actual !== expected) {
    throw new Error(
      `Groth16 MPC archive ${archiveName} ${archivePath} sha256 mismatch: expected=${expected} actual=${actual}`,
    );
  }
}

function rewriteDownloadedGroth16MpcProvenance(content, archive) {
  let provenance;
  try {
    provenance = JSON.parse(content.toString("utf8"));
  } catch (error) {
    throw new Error(`Groth16 MPC archive contains invalid zkey_provenance.json: ${error.message}`);
  }
  provenance.published_folder_url = `${DRIVE_FOLDER_BASE_URL}/${PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID}`;
  provenance.published_archive_name = archive.archiveName;
  provenance.zkey_download_url = `https://drive.google.com/uc?id=${encodeURIComponent(archive.fileId)}&export=download`;
  return Buffer.from(`${JSON.stringify(provenance, null, 2)}\n`, "utf8");
}

function rewriteFlatGroth16Manifest(manifestPath, zkeyPath) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.artifactDir = ".";
  manifest.grothArtifactSource = "public-drive-mpc";
  manifest.publicGroth16MpcDriveFolderId = PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID;
  manifest.artifacts = {
    ...manifest.artifacts,
    zkeyPath: path.basename(zkeyPath),
    metadataPath: null,
    verificationKeyPath: null,
    zkeyProvenancePath: null,
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
}

function compareChainIds(left, right) {
  return Number(left) - Number(right);
}

function latestTimestampLabel(rootDir) {
  if (!fs.existsSync(rootDir)) {
    return null;
  }
  return fs.readdirSync(rootDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && TIMESTAMP_LABEL_PATTERN.test(entry.name))
    .map((entry) => entry.name)
    .sort()
    .at(-1) ?? null;
}

function requireLatestTimestampLabel(rootDir, label) {
  const timestamp = latestTimestampLabel(rootDir);
  if (!timestamp) {
    throw new Error(`No local ${label} snapshot exists under ${rootDir}.`);
  }
  return timestamp;
}

async function fetchPublicArtifactIndex(indexFileId) {
  const payload = await downloadPublicDriveFileToBuffer(indexFileId);
  let index;
  try {
    index = JSON.parse(payload.toString("utf8"));
  } catch (error) {
    throw new Error(`Downloaded Drive artifact index is not valid JSON: ${error.message}`);
  }

  validateArtifactIndex(index);
  return index;
}

function validateArtifactIndex(index) {
  if (index?.schemaVersion !== 1) {
    throw new Error(`Unsupported Drive artifact index schemaVersion: ${index?.schemaVersion}`);
  }
  if (!index.chains || typeof index.chains !== "object" || Array.isArray(index.chains)) {
    throw new Error("Drive artifact index is missing a valid chains object.");
  }
}

function validateDriveFileMetadata(relativePath, metadata) {
  if (typeof relativePath !== "string" || relativePath.length === 0) {
    throw new Error("Drive artifact index contains an invalid relative path.");
  }
  if (!metadata || typeof metadata !== "object") {
    throw new Error(`Drive artifact index contains invalid metadata for ${relativePath}.`);
  }
  if (typeof metadata.fileId !== "string" || metadata.fileId.length === 0) {
    throw new Error(`Drive artifact index is missing fileId for ${relativePath}.`);
  }
  if (typeof metadata.sha256 !== "string" || !/^[0-9a-f]{64}$/i.test(metadata.sha256)) {
    throw new Error(`Drive artifact index contains an invalid sha256 for ${relativePath}.`);
  }
  if (!Number.isSafeInteger(Number(metadata.size)) || Number(metadata.size) < 0) {
    throw new Error(`Drive artifact index contains an invalid size for ${relativePath}.`);
  }
}

async function cachedFileMatches(filePath, metadata) {
  if (!fs.existsSync(filePath)) {
    return false;
  }
  const stat = fs.statSync(filePath);
  if (stat.size !== Number(metadata.size)) {
    return false;
  }
  return (await sha256File(filePath)) === metadata.sha256;
}

async function downloadPublicDriveFileToBuffer(fileId) {
  const response = await openPublicDriveDownload(fileId);
  return responseBodyToBuffer(response);
}

async function downloadPublicDriveFileToPath(fileId, targetPath) {
  const response = await openPublicDriveDownload(fileId);
  if (!response.body) {
    throw new Error(`Drive file ${fileId} returned an empty response body.`);
  }
  await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(targetPath));
}

async function openPublicDriveDownload(fileId) {
  const firstUrl = `${DRIVE_DOWNLOAD_BASE_URL}&id=${encodeURIComponent(requireNonEmptyString(fileId, "fileId"))}`;
  const firstResponse = await fetch(firstUrl, { redirect: "follow" });
  assertSuccessfulDriveResponse(firstResponse, fileId);

  const contentType = firstResponse.headers.get("content-type") ?? "";
  if (!contentType.includes("text/html")) {
    return firstResponse;
  }

  const html = await firstResponse.text();
  const confirmation = extractDriveConfirmation(html, firstResponse);
  if (!confirmation) {
    throw new Error(
      `Google Drive returned an HTML page instead of file content for ${fileId}. `
        + "Confirm that the file is public and downloadable.",
    );
  }

  const confirmedResponse = await fetch(confirmation.url, {
    redirect: "follow",
    headers: confirmation.cookie ? { Cookie: confirmation.cookie } : {},
  });
  assertSuccessfulDriveResponse(confirmedResponse, fileId);
  const confirmedContentType = confirmedResponse.headers.get("content-type") ?? "";
  if (confirmedContentType.includes("text/html")) {
    throw new Error(`Google Drive did not return downloadable file content for ${fileId}.`);
  }
  return confirmedResponse;
}

function extractDriveConfirmation(html, response) {
  const cookie = driveCookieHeader(response);
  const cookieToken = /download_warning[^=]*=([^;,\s]+)/.exec(cookie)?.[1] ?? null;
  const formToken = /name=["']confirm["']\s+value=["']([^"']+)["']/i.exec(html)?.[1] ?? null;
  const href = extractDriveDownloadHref(html);
  const hrefToken = href ? new URL(href).searchParams.get("confirm") : null;
  const token = cookieToken ?? formToken ?? hrefToken;

  if (href) {
    return {
      url: href,
      cookie,
    };
  }
  if (!token) {
    return null;
  }

  const originalUrl = new URL(response.url);
  originalUrl.searchParams.set("confirm", token);
  return {
    url: originalUrl.toString(),
    cookie,
  };
}

function extractDriveDownloadHref(html) {
  const hrefMatch = /href=["']([^"']*(?:uc\?export=download|download_url)[^"']*)["']/i.exec(html);
  if (!hrefMatch) {
    return null;
  }
  const decoded = decodeHtmlEntities(hrefMatch[1]);
  if (decoded.startsWith("http://") || decoded.startsWith("https://")) {
    return decoded;
  }
  return new URL(decoded, "https://drive.google.com").toString();
}

function decodeHtmlEntities(value) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function driveCookieHeader(response) {
  const getSetCookie = response.headers.getSetCookie?.bind(response.headers);
  const cookies = getSetCookie ? getSetCookie() : [];
  if (cookies.length > 0) {
    return cookies.map((entry) => entry.split(";")[0]).join("; ");
  }
  const cookie = response.headers.get("set-cookie");
  return cookie ? cookie.split(",").map((entry) => entry.split(";")[0]).join("; ") : "";
}

function assertSuccessfulDriveResponse(response, fileId) {
  if (!response.ok) {
    throw new Error(`Failed to download public Drive file ${fileId}: HTTP ${response.status}.`);
  }
}

async function responseBodyToBuffer(response) {
  if (!response.body) {
    throw new Error("Drive response did not include a body.");
  }
  const chunks = [];
  for await (const chunk of response.body) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
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

function sha256Buffer(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function requireChainId(chainId) {
  const normalized = Number(chainId);
  if (!Number.isSafeInteger(normalized) || normalized <= 0) {
    throw new Error(`Invalid chainId: ${chainId}`);
  }
  return normalized;
}

function requireNonEmptyString(value, label) {
  const normalized = String(value ?? "").trim();
  if (!normalized) {
    throw new Error(`${label} must be a non-empty string.`);
  }
  return normalized;
}
