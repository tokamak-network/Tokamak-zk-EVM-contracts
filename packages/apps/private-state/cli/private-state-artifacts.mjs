import fs from "node:fs";
import path from "node:path";

import {
  DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  defaultArtifactCacheBaseRoot,
  fetchPublicArtifactIndex,
  materializeSelectedDriveFiles,
  materializeSelectedLocalFiles,
  requireChainId,
  requireLatestTimestampLabel,
  requireNonEmptyString,
  resolveArtifactCacheBaseRoot as resolveGenericArtifactCacheBaseRoot,
} from "@tokamak-private-dapps/common-library/artifact-cache";
import {
  PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID,
  downloadLatestPublicGroth16MpcArtifacts,
} from "@tokamak-private-dapps/groth16/public-drive-crs";

export function resolveArtifactCacheBaseRoot(
  cacheBaseRoot = process.env.PRIVATE_STATE_ARTIFACT_CACHE_ROOT
    ?? process.env.TOKAMAK_PRIVATE_CHANNELS_ROOT
    ?? defaultArtifactCacheBaseRoot(),
) {
  return resolveGenericArtifactCacheBaseRoot(cacheBaseRoot);
}

export function privateStateCliArtifactRoot(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(resolveArtifactCacheBaseRoot(cacheBaseRoot), "dapps", "private-state");
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

export async function installPrivateStateCliArtifacts({
  dappName,
  indexFileId = process.env.PRIVATE_STATE_DRIVE_ARTIFACT_INDEX_FILE_ID
    ?? process.env.TOKAMAK_ARTIFACT_INDEX_FILE_ID
    ?? DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  cacheBaseRoot,
  localDeploymentBaseRoot,
  localChainIds = [31337],
} = {}) {
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const normalizedCacheBaseRoot = resolveArtifactCacheBaseRoot(cacheBaseRoot);
  const normalizedLocalDeploymentBaseRoot = localDeploymentBaseRoot
    ? path.resolve(localDeploymentBaseRoot)
    : null;
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
      source: "drive",
    }));
  }

  if (normalizedLocalDeploymentBaseRoot) {
    for (const chainId of localChainIds) {
      installed.push(await materializeLocalPrivateStateCliDeployment({
        chainId,
        dappName: normalizedDappName,
        cacheBaseRoot: normalizedCacheBaseRoot,
        localDeploymentBaseRoot: normalizedLocalDeploymentBaseRoot,
      }));
    }
  }

  if (installed.length === 0) {
    throw new Error(`No installable artifacts found for ${normalizedDappName}.`);
  }

  return {
    cacheBaseRoot: normalizedCacheBaseRoot,
    artifactRoot: privateStateCliArtifactRoot(normalizedCacheBaseRoot),
    installed,
  };
}

async function materializePrivateStateCliDeployment({
  index,
  chainId,
  dappName,
  cacheBaseRoot,
  source,
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
    ],
  });
  await downloadLatestPublicGroth16MpcArtifacts({
    outputDir: paths.rootDir,
    selectedFiles: [
      ["circuit_final.zkey", path.basename(paths.grothZkeyPath)],
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
    source,
    artifactDir: paths.rootDir,
    bridgeTimestamp: chain.bridge.timestamp,
    dappTimestamp: dapp.timestamp,
  };
}

async function materializeLocalPrivateStateCliDeployment({
  chainId,
  dappName,
  cacheBaseRoot,
  localDeploymentBaseRoot,
}) {
  const normalizedChainId = String(requireChainId(chainId));
  const normalizedDappName = requireNonEmptyString(dappName, "dappName");
  const bridgeRoot = path.join(
    localDeploymentBaseRoot,
    "deployment",
    `chain-id-${normalizedChainId}`,
    "bridge",
  );
  const dappRoot = path.join(
    localDeploymentBaseRoot,
    "deployment",
    `chain-id-${normalizedChainId}`,
    "dapps",
    normalizedDappName,
  );
  const bridgeTimestamp = requireLatestTimestampLabel(bridgeRoot, `bridge artifacts for chain ${normalizedChainId}`);
  const dappTimestamp = requireLatestTimestampLabel(dappRoot, `${normalizedDappName} artifacts for chain ${normalizedChainId}`);
  const bridgeDir = path.join(bridgeRoot, bridgeTimestamp);
  const dappDir = path.join(dappRoot, dappTimestamp);
  const paths = privateStateCliArtifactPaths(cacheBaseRoot, normalizedChainId);
  fs.rmSync(paths.rootDir, { recursive: true, force: true });
  fs.mkdirSync(paths.rootDir, { recursive: true });

  materializeSelectedLocalFiles({
    targetDir: paths.rootDir,
    selectedFiles: [
      [path.join(bridgeDir, `bridge.${normalizedChainId}.json`), path.basename(paths.bridgeDeploymentPath)],
      [path.join(bridgeDir, `bridge-abi-manifest.${normalizedChainId}.json`), path.basename(paths.bridgeAbiManifestPath)],
      [path.join(bridgeDir, `groth16.${normalizedChainId}.latest.json`), path.basename(paths.grothManifestPath)],
      [path.join(dappDir, `deployment.${normalizedChainId}.latest.json`), path.basename(paths.dappDeploymentPath)],
      [path.join(dappDir, `storage-layout.${normalizedChainId}.latest.json`), path.basename(paths.dappStorageLayoutPath)],
      [path.join(dappDir, "PrivateStateController.callable-abi.json"), path.basename(paths.privateStateControllerAbiPath)],
      [path.join(dappDir, `dapp-registration.${normalizedChainId}.json`), path.basename(paths.dappRegistrationPath)],
    ],
  });
  await downloadLatestPublicGroth16MpcArtifacts({
    outputDir: paths.rootDir,
    selectedFiles: [
      ["circuit_final.zkey", path.basename(paths.grothZkeyPath)],
    ],
  });
  rewriteFlatGroth16Manifest(paths.grothManifestPath, paths.grothZkeyPath);

  return {
    chainId: Number(normalizedChainId),
    source: "local",
    artifactDir: paths.rootDir,
    bridgeTimestamp,
    dappTimestamp,
  };
}

function rewriteFlatGroth16Manifest(manifestPath, zkeyPath) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.artifactDir = ".";
  manifest.grothArtifactSource = "public-drive-mpc";
  manifest.publicGroth16MpcDriveFolderId = PUBLIC_GROTH16_MPC_DRIVE_FOLDER_ID;
  manifest.artifacts = {
    ...manifest.artifacts,
    zkeyPath: path.basename(zkeyPath),
    metadataPath: null,
    verificationKeyPath: null,
    zkeyProvenancePath: null,
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
}

function compareChainIds(left, right) {
  return Number(left) - Number(right);
}
