import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

export const DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID = "11nM-VT0ZJlBdZUdFPGawqxvHNpXm1sXR";

const DRIVE_DOWNLOAD_BASE_URL = "https://drive.google.com/uc?export=download";
const TIMESTAMP_LABEL_PATTERN = /^\d{8}T\d{6}Z$/;

export function defaultArtifactCacheBaseRoot() {
  return path.join(os.homedir(), "tokamak-private-channels");
}

export function resolveArtifactCacheBaseRoot(
  cacheBaseRoot = process.env.TOKAMAK_PRIVATE_CHANNELS_ROOT ?? defaultArtifactCacheBaseRoot(),
) {
  return path.resolve(cacheBaseRoot);
}

export async function fetchPublicArtifactIndex(indexFileId = DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID) {
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

export async function materializeSelectedDriveFiles({ targetDir, files, selectedFiles }) {
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

export function materializeSelectedLocalFiles({ targetDir, selectedFiles }) {
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

export function latestTimestampLabel(rootDir) {
  if (!fs.existsSync(rootDir)) {
    return null;
  }
  return fs.readdirSync(rootDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && TIMESTAMP_LABEL_PATTERN.test(entry.name))
    .map((entry) => entry.name)
    .sort()
    .at(-1) ?? null;
}

export function requireLatestTimestampLabel(rootDir, label) {
  const timestamp = latestTimestampLabel(rootDir);
  if (!timestamp) {
    throw new Error(`No local ${label} snapshot exists under ${rootDir}.`);
  }
  return timestamp;
}

export function validateArtifactIndex(index) {
  if (index?.schemaVersion !== 1) {
    throw new Error(`Unsupported Drive artifact index schemaVersion: ${index?.schemaVersion}`);
  }
  if (!index.chains || typeof index.chains !== "object" || Array.isArray(index.chains)) {
    throw new Error("Drive artifact index is missing a valid chains object.");
  }
}

export function validateDriveFileMetadata(relativePath, metadata) {
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

export async function cachedFileMatches(filePath, metadata) {
  if (!fs.existsSync(filePath)) {
    return false;
  }
  const stat = fs.statSync(filePath);
  if (stat.size !== Number(metadata.size)) {
    return false;
  }
  return (await sha256File(filePath)) === metadata.sha256;
}

export async function downloadPublicDriveFileToBuffer(fileId) {
  const response = await openPublicDriveDownload(fileId);
  return responseBodyToBuffer(response);
}

export async function downloadPublicDriveFileToPath(fileId, targetPath) {
  const response = await openPublicDriveDownload(fileId);
  if (!response.body) {
    throw new Error(`Drive file ${fileId} returned an empty response body.`);
  }
  await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(targetPath));
}

export async function openPublicDriveDownload(fileId) {
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

export function decodeHtmlEntities(value) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

export async function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("error", reject);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

export function sha256Buffer(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

export function requireChainId(chainId) {
  const normalized = Number(chainId);
  if (!Number.isSafeInteger(normalized) || normalized <= 0) {
    throw new Error(`Invalid chainId: ${chainId}`);
  }
  return normalized;
}

export function requireNonEmptyString(value, label) {
  const normalized = String(value ?? "").trim();
  if (!normalized) {
    throw new Error(`${label} must be a non-empty string.`);
  }
  return normalized;
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
