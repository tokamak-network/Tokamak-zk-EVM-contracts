import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import {
  bridgeArtifactDir,
  bridgeArtifactRoot,
  deploymentRoot,
  dappArtifactDir,
  dappArtifactRoot,
} from "./deployment-layout.mjs";

export const DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID = "11nM-VT0ZJlBdZUdFPGawqxvHNpXm1sXR";

const DRIVE_DOWNLOAD_BASE_URL = "https://drive.google.com/uc?export=download";
const TIMESTAMP_LABEL_PATTERN = /^\d{8}T\d{6}Z$/;

export function defaultArtifactCacheBaseRoot() {
  return path.join(os.homedir(), ".tokamak-private-state");
}

export async function ensureDriveDeploymentArtifacts({
  chainId,
  dappName,
  indexFileId = process.env.PRIVATE_STATE_DRIVE_ARTIFACT_INDEX_FILE_ID
    ?? process.env.TOKAMAK_ARTIFACT_INDEX_FILE_ID
    ?? DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  cacheBaseRoot = process.env.PRIVATE_STATE_ARTIFACT_CACHE_ROOT
    ?? process.env.TOKAMAK_ARTIFACT_CACHE_ROOT
    ?? defaultArtifactCacheBaseRoot(),
} = {}) {
  const normalizedChainId = String(requireChainId(chainId));
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const normalizedCacheBaseRoot = path.resolve(cacheBaseRoot);
  const index = await fetchPublicArtifactIndex(indexFileId);
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

  const bridgeDir = bridgeArtifactDir(normalizedCacheBaseRoot, normalizedChainId, chain.bridge.timestamp);
  const dappDir = dappArtifactDir(normalizedCacheBaseRoot, normalizedChainId, normalizedDappName, dapp.timestamp);

  pruneTimestampSiblings(bridgeArtifactRoot(normalizedCacheBaseRoot, normalizedChainId), chain.bridge.timestamp);
  pruneTimestampSiblings(
    dappArtifactRoot(normalizedCacheBaseRoot, normalizedChainId, normalizedDappName),
    dapp.timestamp,
  );

  await materializeDriveFiles({
    artifactDir: bridgeDir,
    files: chain.bridge.files,
  });
  await materializeDriveFiles({
    artifactDir: dappDir,
    files: dapp.files,
  });

  fs.mkdirSync(deploymentRoot(normalizedCacheBaseRoot), { recursive: true });
  fs.writeFileSync(
    path.join(deploymentRoot(normalizedCacheBaseRoot), "artifact-index.json"),
    `${JSON.stringify(index, null, 2)}\n`,
    "utf8",
  );

  return {
    cacheBaseRoot: normalizedCacheBaseRoot,
    index,
    bridgeDir,
    dappDir,
    bridgeTimestamp: chain.bridge.timestamp,
    dappTimestamp: dapp.timestamp,
  };
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

async function materializeDriveFiles({ artifactDir, files }) {
  for (const [relativePath, metadata] of Object.entries(files)) {
    validateDriveFileMetadata(relativePath, metadata);
    const targetPath = resolveArtifactTargetPath(artifactDir, relativePath);
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

function resolveArtifactTargetPath(artifactDir, relativePath) {
  const targetPath = path.resolve(artifactDir, relativePath);
  const rootPath = path.resolve(artifactDir);
  if (!(targetPath === rootPath || targetPath.startsWith(`${rootPath}${path.sep}`))) {
    throw new Error(`Drive artifact index path escapes the artifact root: ${relativePath}`);
  }
  return targetPath;
}

function pruneTimestampSiblings(rootDir, keepTimestamp) {
  if (!fs.existsSync(rootDir)) {
    return;
  }
  for (const entry of fs.readdirSync(rootDir, { withFileTypes: true })) {
    if (entry.isDirectory() && TIMESTAMP_LABEL_PATTERN.test(entry.name) && entry.name !== keepTimestamp) {
      fs.rmSync(path.join(rootDir, entry.name), { recursive: true, force: true });
    }
  }
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
