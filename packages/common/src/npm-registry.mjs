import { requireNonEmptyString } from "./artifact-cache.mjs";
import { isExactSemverVersion } from "./proof-backend-versioning.mjs";

export async function fetchNpmPackageMetadata(packageName) {
  const normalizedPackageName = requireNonEmptyString(packageName, "packageName");
  const registryUrl = `https://registry.npmjs.org/${encodeURIComponent(normalizedPackageName)}`;
  const response = await fetch(registryUrl, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`Failed to read npm package metadata for ${normalizedPackageName}: HTTP ${response.status}.`);
  }

  try {
    return await response.json();
  } catch (error) {
    throw new Error(`npm package metadata for ${normalizedPackageName} is not valid JSON: ${error.message}`);
  }
}

export async function fetchLatestNpmPackageVersion(packageName) {
  const metadata = await fetchNpmPackageMetadata(packageName);
  const latest = metadata?.["dist-tags"]?.latest;
  if (typeof latest !== "string" || !isExactSemverVersion(latest)) {
    throw new Error(`npm package ${packageName} has no valid latest dist-tag.`);
  }
  return latest;
}

export async function fetchLatestNpmPackageManifest(packageName) {
  const metadata = await fetchNpmPackageMetadata(packageName);
  const latest = metadata?.["dist-tags"]?.latest;
  if (typeof latest !== "string" || !isExactSemverVersion(latest)) {
    throw new Error(`npm package ${packageName} has no valid latest dist-tag.`);
  }

  const manifest = metadata?.versions?.[latest];
  if (!manifest || typeof manifest !== "object") {
    throw new Error(`npm package ${packageName} is missing manifest data for latest version ${latest}.`);
  }
  return manifest;
}
