import fs from "node:fs";
import {
  normalizePackageVersionToCompatibleBackendVersion,
  requireCanonicalCompatibleBackendVersion,
} from "@tokamak-private-dapps/common-library/proof-backend-versioning";

const COMPATIBLE_BACKEND_CONFIG_KEY = "groth16CompatibleBackendVersion";

export const normalizeGroth16PackageVersionToCompatibleBackendVersion =
  normalizePackageVersionToCompatibleBackendVersion;

export const requireCanonicalGroth16CompatibleBackendVersion = requireCanonicalCompatibleBackendVersion;

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
