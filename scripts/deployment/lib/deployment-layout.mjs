import fs from "node:fs";
import path from "node:path";

const TIMESTAMP_LABEL_PATTERN = /^\d{8}T\d{6}Z$/;

function normalizeDappName(dappName) {
  const trimmed = String(dappName ?? "").trim();
  if (trimmed.length === 0) {
    throw new Error("DApp name must be a non-empty string.");
  }
  return trimmed;
}

function listTimestampLabels(rootDir) {
  if (!fs.existsSync(rootDir)) {
    return [];
  }

  return fs.readdirSync(rootDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && TIMESTAMP_LABEL_PATTERN.test(entry.name))
    .map((entry) => entry.name)
    .sort();
}

export function deploymentRoot(repoRoot) {
  return path.join(repoRoot, "deployment");
}

export function chainArtifactRoot(repoRoot, chainId) {
  return path.join(deploymentRoot(repoRoot), `chain-id-${chainId}`);
}

export function bridgeArtifactRoot(repoRoot, chainId) {
  return path.join(chainArtifactRoot(repoRoot, chainId), "bridge");
}

export function bridgeArtifactDir(repoRoot, chainId, timestampLabel) {
  return path.join(bridgeArtifactRoot(repoRoot, chainId), timestampLabel);
}

export function dappArtifactRoot(repoRoot, chainId, dappName) {
  return path.join(chainArtifactRoot(repoRoot, chainId), "dapps", normalizeDappName(dappName));
}

export function dappArtifactDir(repoRoot, chainId, dappName, timestampLabel) {
  return path.join(dappArtifactRoot(repoRoot, chainId, dappName), timestampLabel);
}

export function latestBridgeTimestampLabel(repoRoot, chainId) {
  const labels = listTimestampLabels(bridgeArtifactRoot(repoRoot, chainId));
  return labels.at(-1) ?? null;
}

export function latestDappTimestampLabel(repoRoot, chainId, dappName) {
  const labels = listTimestampLabels(dappArtifactRoot(repoRoot, chainId, dappName));
  return labels.at(-1) ?? null;
}

export function latestBridgeArtifactDir(repoRoot, chainId) {
  const label = latestBridgeTimestampLabel(repoRoot, chainId);
  return label ? bridgeArtifactDir(repoRoot, chainId, label) : null;
}

export function latestDappArtifactDir(repoRoot, chainId, dappName) {
  const label = latestDappTimestampLabel(repoRoot, chainId, dappName);
  return label ? dappArtifactDir(repoRoot, chainId, dappName, label) : null;
}

export function requireLatestBridgeArtifactDir(repoRoot, chainId) {
  const artifactDir = latestBridgeArtifactDir(repoRoot, chainId);
  if (!artifactDir) {
    throw new Error(`No bridge deployment snapshot exists for chain ${chainId}.`);
  }
  return artifactDir;
}

export function requireLatestDappArtifactDir(repoRoot, chainId, dappName) {
  const artifactDir = latestDappArtifactDir(repoRoot, chainId, dappName);
  if (!artifactDir) {
    throw new Error(`No DApp deployment snapshot exists for ${dappName} on chain ${chainId}.`);
  }
  return artifactDir;
}

export function bridgeArtifactPaths(repoRoot, chainId, timestampLabel) {
  const rootDir = bridgeArtifactDir(repoRoot, chainId, timestampLabel);
  return {
    rootDir,
    deploymentPath: path.join(rootDir, `bridge.${chainId}.json`),
    abiManifestPath: path.join(rootDir, `bridge-abi-manifest.${chainId}.json`),
    grothManifestPath: path.join(rootDir, `groth16.${chainId}.latest.json`),
    grothDir: path.join(rootDir, "groth16"),
    grothZkeyPath: path.join(rootDir, "groth16", "circuit_final.zkey"),
    grothVerificationKeyPath: path.join(rootDir, "groth16", "verification_key.json"),
    grothMetadataPath: path.join(rootDir, "groth16", "metadata.json"),
    grothZkeyProvenancePath: path.join(rootDir, "groth16", "zkey_provenance.json"),
    tokamakZkpManifestPath: path.join(rootDir, `tokamak-zkp.${chainId}.latest.json`),
    tokamakZkpDir: path.join(rootDir, "tokamak-zkp"),
    tokamakBuildMetadataPath: path.join(rootDir, "tokamak-zkp", "build-metadata-mpc-setup.json"),
    tokamakCrsProvenancePath: path.join(rootDir, "tokamak-zkp", "crs_provenance.json"),
    reflectionManifestPath: path.join(rootDir, "zk-reflection.latest.json"),
  };
}

export function dappArtifactPaths(repoRoot, chainId, dappName, timestampLabel) {
  const rootDir = dappArtifactDir(repoRoot, chainId, dappName, timestampLabel);
  return {
    rootDir,
    deploymentPath: path.join(rootDir, `deployment.${chainId}.latest.json`),
    storageLayoutPath: path.join(rootDir, `storage-layout.${chainId}.latest.json`),
    privateStateControllerAbiPath: path.join(rootDir, "PrivateStateController.callable-abi.json"),
    l2AccountingVaultAbiPath: path.join(rootDir, "L2AccountingVault.callable-abi.json"),
    sourceDir: path.join(rootDir, "source"),
    registrationManifestPath: path.join(rootDir, `dapp-registration.${chainId}.json`),
  };
}

export function toPortableRelativePath(fromDir, targetPath) {
  return path.relative(fromDir, targetPath).split(path.sep).join("/");
}
