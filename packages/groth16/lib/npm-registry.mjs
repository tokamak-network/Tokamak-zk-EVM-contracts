export const GROTH16_NPM_PACKAGE_NAME = "@tokamak-private-dapps/groth16";

export async function fetchLatestNpmPackageVersion(packageName) {
  const normalizedPackageName = requireNonEmptyString(packageName, "packageName");
  const registryUrl = `https://registry.npmjs.org/${encodeURIComponent(normalizedPackageName)}`;
  const response = await fetch(registryUrl, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`Failed to read npm package metadata for ${normalizedPackageName}: HTTP ${response.status}.`);
  }

  let metadata;
  try {
    metadata = await response.json();
  } catch (error) {
    throw new Error(`npm package metadata for ${normalizedPackageName} is not valid JSON: ${error.message}`);
  }

  const latest = metadata?.["dist-tags"]?.latest;
  if (typeof latest !== "string" || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?(?:\+[0-9A-Za-z.]+)?$/.test(latest)) {
    throw new Error(`npm package ${normalizedPackageName} has no valid latest dist-tag.`);
  }
  return latest;
}

function requireNonEmptyString(value, label) {
  const normalized = String(value ?? "").trim();
  if (!normalized) {
    throw new Error(`${label} must be a non-empty string.`);
  }
  return normalized;
}
