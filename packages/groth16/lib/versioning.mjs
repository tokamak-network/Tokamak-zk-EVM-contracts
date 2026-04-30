import fs from "node:fs";

const COMPATIBLE_BACKEND_CONFIG_KEY = "groth16CompatibleBackendVersion";
const COMPATIBLE_BACKEND_VERSION_PATTERN = /^(\d+)\.(\d+)$/;
const EXACT_SEMVER_PATTERN = /^(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.]+)?(?:\+[0-9A-Za-z.]+)?$/;

export function normalizeGroth16PackageVersionToCompatibleBackendVersion(value, label = "Groth16 package version") {
  const version = String(value ?? "").trim();
  const match = EXACT_SEMVER_PATTERN.exec(version);
  if (!match) {
    throw new Error(`${label} must be an exact semantic version. Received: ${String(value)}`);
  }
  const [, major, minor] = match;
  return `${Number(major)}.${Number(minor)}`;
}

export function requireCanonicalGroth16CompatibleBackendVersion(
  value,
  label = "Groth16 compatible backend version",
) {
  const version = String(value ?? "").trim();
  const match = COMPATIBLE_BACKEND_VERSION_PATTERN.exec(version);
  if (!match) {
    throw new Error(
      `${label} must be a canonical major.minor compatibility version. Received: ${String(value)}`,
    );
  }
  const [, major, minor] = match;
  const canonicalVersion = `${Number(major)}.${Number(minor)}`;
  if (version !== canonicalVersion) {
    throw new Error(`${label} must be canonical ${canonicalVersion}. Received: ${version}`);
  }
  return canonicalVersion;
}

export function parseGroth16CompatibleBackendVersionParts(value, label = "Groth16 compatible backend version") {
  return requireCanonicalGroth16CompatibleBackendVersion(value, label)
    .split(".")
    .map((part) => Number(part));
}

export function readGroth16CompatibleBackendVersionFromPackageJson(packageJson, label = "Groth16 package") {
  const packageVersion = normalizeGroth16PackageVersionToCompatibleBackendVersion(
    packageJson?.version,
    `${label} version`,
  );
  const configuredVersion = packageJson?.tokamakPrivateDapps?.[COMPATIBLE_BACKEND_CONFIG_KEY];
  if (configuredVersion === undefined || configuredVersion === null) {
    throw new Error(`${label} tokamakPrivateDapps.${COMPATIBLE_BACKEND_CONFIG_KEY} is missing.`);
  }

  const compatibleVersion = requireCanonicalGroth16CompatibleBackendVersion(
    configuredVersion,
    `${label} tokamakPrivateDapps.${COMPATIBLE_BACKEND_CONFIG_KEY}`,
  );
  if (compatibleVersion !== packageVersion) {
    throw new Error(
      `${label} compatible backend version ${compatibleVersion} must match package major.minor ${packageVersion}.`,
    );
  }
  return compatibleVersion;
}

export function readGroth16CompatibleBackendVersionFromPackageJsonPath(packageJsonPath, label = packageJsonPath) {
  return readGroth16CompatibleBackendVersionFromPackageJson(
    JSON.parse(fs.readFileSync(packageJsonPath, "utf8")),
    label,
  );
}
