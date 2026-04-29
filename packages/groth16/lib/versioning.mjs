import fs from "node:fs";

const COMPATIBLE_BACKEND_CONFIG_KEY = "groth16CompatibleBackendVersion";

export function normalizeGroth16CompatibleBackendVersion(value, label = "Groth16 compatible backend version") {
  const version = String(value ?? "").trim();
  const match = /^(\d+)\.(\d+)(?:\.(\d+)(?:-[0-9A-Za-z.]+)?(?:\+[0-9A-Za-z.]+)?)?$/.exec(version);
  if (!match) {
    throw new Error(
      `${label} must be a major.minor compatibility version or an exact semantic version. `
        + `Received: ${String(value)}`,
    );
  }
  const [, major, minor] = match;
  return `${Number(major)}.${Number(minor)}`;
}

export function parseGroth16CompatibleBackendVersionParts(value, label = "Groth16 compatible backend version") {
  return normalizeGroth16CompatibleBackendVersion(value, label)
    .split(".")
    .map((part) => Number(part));
}

export function readGroth16CompatibleBackendVersionFromPackageJson(packageJson, label = "Groth16 package") {
  const packageVersion = normalizeGroth16CompatibleBackendVersion(
    packageJson?.version,
    `${label} version`,
  );
  const configuredVersion = packageJson?.tokamakPrivateDapps?.[COMPATIBLE_BACKEND_CONFIG_KEY];
  if (configuredVersion === undefined || configuredVersion === null) {
    return packageVersion;
  }

  const compatibleVersion = normalizeGroth16CompatibleBackendVersion(
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
