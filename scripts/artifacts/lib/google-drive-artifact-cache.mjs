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
const PRIVATE_STATE_CLI_ARTIFACT_ROOT_DIR = "private-state-cli-artifacts";

export function defaultArtifactCacheBaseRoot() {
  return path.join(os.homedir(), ".tokamak-private-state");
}

export function resolveArtifactCacheBaseRoot(cacheBaseRoot = process.env.PRIVATE_STATE_ARTIFACT_CACHE_ROOT
  ?? process.env.TOKAMAK_ARTIFACT_CACHE_ROOT
  ?? defaultArtifactCacheBaseRoot()) {
  return path.resolve(cacheBaseRoot);
}

export function privateStateCliArtifactRoot(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(resolveArtifactCacheBaseRoot(cacheBaseRoot), PRIVATE_STATE_CLI_ARTIFACT_ROOT_DIR);
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

export async function installDriveDeploymentArtifacts({
  dappName,
  indexFileId = process.env.PRIVATE_STATE_DRIVE_ARTIFACT_INDEX_FILE_ID
    ?? process.env.TOKAMAK_ARTIFACT_INDEX_FILE_ID
    ?? DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  cacheBaseRoot,
} = {}) {
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const normalizedCacheBaseRoot = resolveArtifactCacheBaseRoot(cacheBaseRoot);
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
    }));
  }

  if (installed.length === 0) {
    throw new Error(`Drive artifact index does not contain installable artifacts for ${normalizedDappName}.`);
  }

  return {
    cacheBaseRoot: normalizedCacheBaseRoot,
    artifactRoot: privateStateCliArtifactRoot(normalizedCacheBaseRoot),
    index,
    installed,
  };
}

export async function ensureDriveDeploymentArtifacts({
  chainId,
  dappName,
  indexFileId = process.env.PRIVATE_STATE_DRIVE_ARTIFACT_INDEX_FILE_ID
    ?? process.env.TOKAMAK_ARTIFACT_INDEX_FILE_ID
    ?? DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  cacheBaseRoot,
} = {}) {
  const normalizedChainId = String(requireChainId(chainId));
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const normalizedCacheBaseRoot = resolveArtifactCacheBaseRoot(cacheBaseRoot);
  const index = await fetchPublicArtifactIndex(indexFileId);
  const result = await materializeIndexedDeployment({
    index,
    chainId: normalizedChainId,
    dappName: normalizedDappName,
    cacheBaseRoot: normalizedCacheBaseRoot,
  });
  writeCachedArtifactIndex(normalizedCacheBaseRoot, index);
  return {
    cacheBaseRoot: normalizedCacheBaseRoot,
    index,
    ...result,
  };
}

async function materializePrivateStateCliDeployment({
  index,
  chainId,
  dappName,
  cacheBaseRoot,
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
      ["groth16/circuit_final.zkey", path.basename(paths.grothZkeyPath)],
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
    artifactDir: paths.rootDir,
    bridgeDir: paths.rootDir,
    dappDir: paths.rootDir,
    bridgeTimestamp: chain.bridge.timestamp,
    dappTimestamp: dapp.timestamp,
  };
}

async function materializeIndexedDeployment({
  index,
  chainId,
  dappName,
  cacheBaseRoot,
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

  const bridgeDir = bridgeArtifactDir(cacheBaseRoot, normalizedChainId, chain.bridge.timestamp);
  const dappDir = dappArtifactDir(cacheBaseRoot, normalizedChainId, normalizedDappName, dapp.timestamp);

  pruneTimestampSiblings(bridgeArtifactRoot(cacheBaseRoot, normalizedChainId), chain.bridge.timestamp);
  pruneTimestampSiblings(
    dappArtifactRoot(cacheBaseRoot, normalizedChainId, normalizedDappName),
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

  return {
    chainId: Number(normalizedChainId),
    bridgeDir,
    dappDir,
    bridgeTimestamp: chain.bridge.timestamp,
    dappTimestamp: dapp.timestamp,
  };
}

async function materializeSelectedDriveFiles({ targetDir, files, selectedFiles }) {
  for (const [relativePath, targetName] of selectedFiles) {
    const metadata = files[relativePath];
    if (!metadata) {
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

function rewriteFlatGroth16Manifest(manifestPath, zkeyPath) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.artifactDir = ".";
  manifest.artifacts = {
    ...manifest.artifacts,
    zkeyPath: path.basename(zkeyPath),
    metadataPath: null,
    verificationKeyPath: null,
    zkeyProvenancePath: null,
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
}

function writeCachedArtifactIndex(cacheBaseRoot, index) {
  fs.mkdirSync(deploymentRoot(cacheBaseRoot), { recursive: true });
  fs.writeFileSync(
    path.join(deploymentRoot(cacheBaseRoot), "artifact-index.json"),
    `${JSON.stringify(index, null, 2)}\n`,
    "utf8",
  );
}

function compareChainIds(left, right) {
  return Number(left) - Number(right);
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
