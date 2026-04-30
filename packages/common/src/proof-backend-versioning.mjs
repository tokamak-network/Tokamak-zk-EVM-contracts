const COMPATIBLE_BACKEND_VERSION_PATTERN = /^(\d+)\.(\d+)$/;
const EXACT_SEMVER_PATTERN = /^(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.]+)?(?:\+[0-9A-Za-z.]+)?$/;

export function isExactSemverVersion(value) {
  return EXACT_SEMVER_PATTERN.test(String(value ?? "").trim());
}

export function requireExactSemverVersion(value, label = "package version") {
  const version = String(value ?? "").trim();
  if (!EXACT_SEMVER_PATTERN.test(version)) {
    throw new Error(`${label} must be an exact semantic version. Received: ${String(value)}`);
  }
  return version;
}

export function normalizePackageVersionToCompatibleBackendVersion(value, label = "package version") {
  const version = requireExactSemverVersion(value, label);
  const [, major, minor] = EXACT_SEMVER_PATTERN.exec(version);
  return `${Number(major)}.${Number(minor)}`;
}

export function requireCanonicalCompatibleBackendVersion(
  value,
  label = "compatible backend version",
) {
  const version = String(value ?? "").trim();
  const match = COMPATIBLE_BACKEND_VERSION_PATTERN.exec(version);
  if (!match) {
    throw new Error(`${label} must be a canonical major.minor compatibility version. Received: ${String(value)}`);
  }

  const [, major, minor] = match;
  const canonicalVersion = `${Number(major)}.${Number(minor)}`;
  if (version !== canonicalVersion) {
    throw new Error(`${label} must be canonical ${canonicalVersion}. Received: ${version}`);
  }
  return canonicalVersion;
}

export function readTokamakZkEvmCompatibleBackendVersionFromPackageJson(
  packageJson,
  label = "Tokamak zk-EVM CLI package",
) {
  const packageVersion = normalizePackageVersionToCompatibleBackendVersion(
    packageJson?.version,
    `${label} version`,
  );
  const configuredVersion = packageJson?.tokamakZkEvm?.compatibleBackendVersion;
  if (configuredVersion === undefined || configuredVersion === null) {
    throw new Error(`${label} tokamakZkEvm.compatibleBackendVersion is missing.`);
  }

  const compatibleVersion = requireCanonicalCompatibleBackendVersion(
    configuredVersion,
    `${label} tokamakZkEvm.compatibleBackendVersion`,
  );
  if (compatibleVersion !== packageVersion) {
    throw new Error(
      `${label} compatible backend version ${compatibleVersion} must match package major.minor ${packageVersion}.`,
    );
  }
  return compatibleVersion;
}
