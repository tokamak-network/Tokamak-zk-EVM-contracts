import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import {
  decodeHtmlEntities,
  downloadPublicDriveFileToBuffer,
  requireNonEmptyString,
  sha256Buffer,
} from "@tokamak-private-dapps/common-library/artifact-cache";
import {
  normalizeGroth16PackageVersionToCompatibleBackendVersion,
  parseGroth16CompatibleBackendVersionParts,
  readGroth16CompatibleBackendVersionFromPackageJson,
  readGroth16CompatibleBackendVersionFromPackageJsonPath,
  requireCanonicalGroth16CompatibleBackendVersion,
} from "./versioning.mjs";

export {
  normalizeGroth16PackageVersionToCompatibleBackendVersion,
  readGroth16CompatibleBackendVersionFromPackageJson,
  readGroth16CompatibleBackendVersionFromPackageJsonPath,
  requireCanonicalGroth16CompatibleBackendVersion,
};

export const PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID = "1jAIBqV-KG6PxFPDFpgtg9PDIceDDqk6N";

const DRIVE_FOLDER_BASE_URL = "https://drive.google.com/drive/folders";
const GROTH16_MPC_ARCHIVE_PREFIX = "tokamak-private-dapps-groth16";
const GROTH16_MPC_ARCHIVE_PATTERN =
  /^tokamak-private-dapps-groth16-v(\d+\.\d+)-(\d{8}T\d{6}Z)\.zip$/;
const require = createRequire(import.meta.url);
const yauzl = require("yauzl");

let latestGroth16MpcArchivePromise = null;
const groth16MpcArchivePromisesByVersion = new Map();

export async function downloadLatestPublicGroth16MpcArtifacts({
  outputDir,
  selectedFiles = [
    "circuit_final.zkey",
    "verification_key.json",
    "metadata.json",
    "zkey_provenance.json",
  ],
  expectedVersion = null,
  expectedVersionLabel = "expected version",
} = {}) {
  const archive = await loadLatestPublicGroth16MpcArchive();
  return downloadPublicGroth16MpcArtifactsFromArchive({
    archive,
    outputDir,
    selectedFiles,
    expectedVersion,
    expectedVersionLabel,
  });
}

export async function downloadPublicGroth16MpcArtifactsByVersion({
  version,
  outputDir,
  selectedFiles = [
    "circuit_final.zkey",
    "verification_key.json",
    "metadata.json",
    "zkey_provenance.json",
  ],
} = {}) {
  const normalizedVersion = requireCanonicalGroth16CompatibleBackendVersion(version, "Groth16 MPC CRS version");
  const archive = await loadPublicGroth16MpcArchiveByVersion(normalizedVersion);
  return downloadPublicGroth16MpcArtifactsFromArchive({
    archive,
    outputDir,
    selectedFiles,
    expectedVersion: normalizedVersion,
    expectedVersionLabel: "requested Groth16 MPC CRS version",
  });
}

async function downloadPublicGroth16MpcArtifactsFromArchive({
  archive,
  outputDir,
  selectedFiles,
  expectedVersion = null,
  expectedVersionLabel = "expected version",
}) {
  const normalizedOutputDir = path.resolve(requireNonEmptyString(outputDir, "outputDir"));
  const normalizedSelection = normalizeGroth16MpcArtifactSelection(selectedFiles);
  const archiveFileNames = [...new Set([
    ...normalizedSelection.map((entry) => entry.archivePath),
    "zkey_provenance.json",
  ])];
  const extracted = await extractZipEntriesFromBuffer(archive.buffer, archiveFileNames);
  const provenance = parseGroth16MpcProvenance(extracted.get("zkey_provenance.json"));
  validateGroth16MpcArchiveVersion({ archive, provenance, expectedVersion, expectedVersionLabel });
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
    version: archive.version,
    installedFiles,
  };
}

export async function findLatestPublicGroth16MpcArchiveMetadata() {
  return serializeGroth16MpcArchiveMetadata(await findLatestPublicGroth16MpcArchive());
}

export async function assertLatestPublicGroth16MpcArchiveVersion(
  expectedVersion,
  { expectedVersionLabel = "expected version" } = {},
) {
  const archive = await findLatestPublicGroth16MpcArchive();
  const normalizedExpectedVersion = requireCanonicalGroth16CompatibleBackendVersion(expectedVersion, expectedVersionLabel);
  if (archive.version !== normalizedExpectedVersion) {
    throw new Error(
      `Latest public Groth16 MPC CRS compatibility version ${archive.version} does not match `
        + `${expectedVersionLabel} ${normalizedExpectedVersion}: ${archive.archiveName}`,
    );
  }
  return serializeGroth16MpcArchiveMetadata(archive);
}

async function loadLatestPublicGroth16MpcArchive() {
  if (!latestGroth16MpcArchivePromise) {
    latestGroth16MpcArchivePromise = (async () => {
      const archive = await findLatestPublicGroth16MpcArchive();
      const buffer = archive.buffer ?? await downloadPublicDriveFileToBuffer(archive.fileId);
      return { ...archive, buffer };
    })();
  }
  return latestGroth16MpcArchivePromise;
}

async function loadPublicGroth16MpcArchiveByVersion(version) {
  const normalizedVersion = requireCanonicalGroth16CompatibleBackendVersion(version, "Groth16 MPC CRS version");
  if (!groth16MpcArchivePromisesByVersion.has(normalizedVersion)) {
    groth16MpcArchivePromisesByVersion.set(normalizedVersion, (async () => {
      const archive = await findPublicGroth16MpcArchiveByVersion(normalizedVersion);
      const buffer = archive.buffer ?? await downloadPublicDriveFileToBuffer(archive.fileId);
      return { ...archive, buffer };
    })());
  }
  return groth16MpcArchivePromisesByVersion.get(normalizedVersion);
}

async function findLatestPublicGroth16MpcArchive() {
  const archives = await listPublicGroth16MpcArchives();
  return findNewestVerifiedPublicGroth16MpcArchive(archives);
}

async function findPublicGroth16MpcArchiveByVersion(version) {
  const normalizedVersion = requireCanonicalGroth16CompatibleBackendVersion(version, "Groth16 MPC CRS version");
  const archives = (await listPublicGroth16MpcArchives())
    .filter((archive) => archive.version === normalizedVersion);
  if (archives.length === 0) {
    throw new Error(`No ${GROTH16_MPC_ARCHIVE_PREFIX} archive found for compatibility version ${normalizedVersion}.`);
  }
  return findNewestVerifiedPublicGroth16MpcArchive(archives);
}

async function findNewestVerifiedPublicGroth16MpcArchive(archives) {
  const candidates = [...archives].sort(compareGroth16MpcArchives).reverse();
  const rejected = [];

  for (const archive of candidates) {
    try {
      const buffer = await downloadPublicDriveFileToBuffer(archive.fileId);
      const extracted = await extractZipEntriesFromBuffer(buffer, ["zkey_provenance.json"]);
      const provenance = parseGroth16MpcProvenance(extracted.get("zkey_provenance.json"));
      validateGroth16MpcArchiveVersion({
        archive,
        provenance,
        expectedVersion: null,
        expectedVersionLabel: "Groth16 MPC CRS version",
      });
      return { ...archive, buffer };
    } catch (error) {
      rejected.push(`${archive.archiveName} (${archive.fileId}): ${error.message}`);
    }
  }

  throw new Error(
    [
      "No verified public Groth16 MPC archive could be selected.",
      ...rejected.map((reason) => `- ${reason}`),
    ].join("\n"),
  );
}

async function listPublicGroth16MpcArchives() {
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
  return archives;
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
  const [, version, timestamp] = match;
  const compatibleVersion = requireCanonicalGroth16CompatibleBackendVersion(
    version,
    `${archiveName} archive version`,
  );
  return {
    version: compatibleVersion,
    versionParts: parseGroth16CompatibleBackendVersionParts(compatibleVersion),
    timestamp,
  };
}

function compareGroth16MpcArchives(left, right) {
  for (let i = 0; i < left.versionParts.length; i += 1) {
    const leftValue = left.versionParts[i];
    const rightValue = right.versionParts[i];
    const diff = typeof leftValue === "number"
      ? leftValue - rightValue
      : String(leftValue).localeCompare(String(rightValue));
    if (diff !== 0) {
      return diff;
    }
  }
  return left.timestamp.localeCompare(right.timestamp)
    || left.archiveName.localeCompare(right.archiveName)
    || left.fileId.localeCompare(right.fileId);
}

function validateGroth16MpcArchiveVersion({
  archive,
  provenance,
  expectedVersion,
  expectedVersionLabel,
}) {
  if (provenance) {
    const provenanceVersion = requireCanonicalGroth16CompatibleBackendVersion(
      provenance.backend_version,
      `${archive.archiveName} provenance backend_version`,
    );
    if (provenanceVersion !== archive.version) {
      throw new Error(
        `Groth16 MPC archive ${archive.archiveName} compatibility version ${archive.version} does not match `
          + `provenance backend_version ${provenanceVersion}.`,
      );
    }
  }

  if (expectedVersion !== null && expectedVersion !== undefined) {
    const normalizedExpectedVersion = requireCanonicalGroth16CompatibleBackendVersion(
      expectedVersion,
      expectedVersionLabel,
    );
    if (archive.version !== normalizedExpectedVersion) {
      throw new Error(
        `Public Groth16 MPC CRS compatibility version ${archive.version} does not match `
          + `${expectedVersionLabel} ${normalizedExpectedVersion}: ${archive.archiveName}`,
      );
    }
  }
}

function serializeGroth16MpcArchiveMetadata(archive) {
  return {
    source: "drive",
    folderId: PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID,
    folderUrl: `${DRIVE_FOLDER_BASE_URL}/${PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID}`,
    archiveName: archive.archiveName,
    archiveFileId: archive.fileId,
    version: archive.version,
    timestamp: archive.timestamp,
  };
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

export function extractZipEntriesFromBuffer(buffer, fileNames) {
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
