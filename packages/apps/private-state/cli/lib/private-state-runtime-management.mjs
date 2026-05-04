import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { fetchNpmPackageMetadata } from "@tokamak-private-dapps/common-library/npm-registry";
import {
  normalizePackageVersionToCompatibleBackendVersion,
  readTokamakZkEvmCompatibleBackendVersionFromPackageJson,
  requireCanonicalCompatibleBackendVersion,
  requireExactSemverVersion,
} from "@tokamak-private-dapps/common-library/proof-backend-versioning";
import {
  resolveTokamakCliEntryPath,
  resolveTokamakCliPackageRoot as resolveBundledTokamakCliPackageRoot,
} from "@tokamak-private-dapps/common-library/tokamak-runtime-paths";
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
  downloadPublicGroth16MpcArtifactsByVersion,
  readGroth16CompatibleBackendVersionFromPackageJson,
  requireCanonicalGroth16CompatibleBackendVersion,
} from "@tokamak-private-dapps/groth16/public-drive-crs";

const require = createRequire(import.meta.url);
const privateStateCliPackageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultCommandCwd = process.cwd();
const PRIVATE_STATE_DAPP_LABEL = "private-state";
const DOCKER_CUDA_PROBE_IMAGE = "nvidia/cuda:12.2.0-base-ubuntu22.04";
const DOCTOR_GPU_PROBE_TIMEOUT_MS = 120000;
const GROTH16_PACKAGE_NAME = "@tokamak-private-dapps/groth16";
const TOKAMAK_ZKEVM_CLI_PACKAGE_NAME = "@tokamak-zk-evm/cli";

function expect(condition, message) {
  if (!condition) {
    throw message instanceof Error ? message : new Error(message);
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJsonIfExists(filePath) {
  return fs.existsSync(filePath) ? readJson(filePath) : null;
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function run(command, args, { cwd = defaultCommandCwd, env = process.env, quiet = false } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: quiet ? ["ignore", "pipe", "pipe"] : "inherit",
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error([
      `${command} ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}.`,
      quiet && result.stdout?.trim() ? `stdout:\n${result.stdout}` : null,
      quiet && result.stderr?.trim() ? `stderr:\n${result.stderr}` : null,
    ].filter(Boolean).join("\n"));
  }
  return result;
}

function runCaptured(command, args, { cwd = defaultCommandCwd, env = process.env } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error) {
    throw result.error;
  }
  return {
    status: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

function requireSemverVersion(value, label) {
  return requireExactSemverVersion(value, label);
}

function readTokamakCliPackageReport(packageRoot = null) {
  try {
    const resolvedPackageRoot = packageRoot ?? resolveActiveTokamakCliPackageRoot();
    const packageJsonPath = path.join(resolvedPackageRoot, "package.json");
    const packageJson = readJson(packageJsonPath);
    const report = readPackageReport({
      name: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      packageJsonPath,
      packageJson,
    });
    return {
      ...report,
      compatibleBackendVersion: readTokamakZkEvmCompatibleBackendVersionFromPackageJson(
        packageJson,
        TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      ),
    };
  } catch (error) {
    return {
      name: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      version: null,
      packageRoot: null,
      compatibleBackendVersion: null,
      error: error.message,
      ok: false,
    };
  }
}
function printDoctorHumanReport(report) {
  const rows = buildDoctorHumanRows(report);
  const lines = [
    "Private-state CLI doctor",
    `Status: ${report.ok ? "OK" : "FAIL"}`,
    `Generated: ${report.generatedAt}`,
    `Package: ${report.package.name}@${report.package.version ?? "unknown"}`,
    `Install manifest: ${report.installManifest.exists ? "found" : "missing"} (${report.installManifest.path})`,
    "",
    formatDoctorTable(rows),
    "",
    "Run `doctor --json` for the full machine-readable report.",
  ];
  console.log(lines.join("\n"));
}

function buildDoctorHumanRows(report) {
  const dependencySummary = report.dependencies
    .map((entry) => `${entry.name}@${entry.version ?? "unknown"}${entry.installVersion ? ` install=${entry.installVersion}` : ""}`)
    .join("; ");
  const selectedVersionDetails = report.checks
    .find((check) => check.name === "selected proof backend runtime versions")
    ?.details ?? [];
  const selectedVersionSummary = selectedVersionDetails
    .map((entry) => [
      `${entry.name}:`,
      `selected=${entry.selectedVersion ?? "none"}`,
      `installed=${entry.installedVersion ?? "missing"}`,
      `cbv=${entry.compatibleBackendVersion ?? "missing"}`,
      entry.crsCompatibleBackendVersion ? `crs=${entry.crsCompatibleBackendVersion}` : null,
    ].filter(Boolean).join(" "))
    .join("; ");

  return [
    {
      check: "dependency packages",
      status: doctorStatus(report.checks.find((check) => check.name === "dependency package versions")?.ok),
      detail: dependencySummary || "no dependency report",
    },
    {
      check: "selected backend versions",
      status: doctorStatus(report.checks.find((check) => check.name === "selected proof backend runtime versions")?.ok),
      detail: selectedVersionSummary || "no selected runtime version pin",
    },
    {
      check: "tokamak zk-evm runtime",
      status: doctorStatus(report.tokamakCli.installed),
      detail: [
        `package=${report.tokamakCli.packageVersion ?? "missing"}`,
        `cbv=${report.tokamakCli.compatibleBackendVersion ?? "missing"}`,
        `runtime=${report.tokamakCli.runtimeRoot ?? "missing"}`,
        `doctorStatus=${report.tokamakCli.doctor.status}`,
      ].join(" "),
    },
    {
      check: "docker gpu readiness",
      status: report.gpuDockerReadiness.skipped ? "SKIP" : doctorStatus(report.gpuDockerReadiness.ok),
      detail: report.gpuDockerReadiness.skipped
        ? "live GPU probe skipped; run `doctor --gpu` to check host NVIDIA and Docker GPU access"
        : [
          `expectedUseGpus=${formatDoctorBool(report.gpuDockerReadiness.expectedUseGpus)}`,
          `liveUseGpus=${formatDoctorBool(report.gpuDockerReadiness.liveUseGpus)}`,
          report.gpuDockerReadiness.mismatchError,
        ].filter(Boolean).join(" "),
    },
    {
      check: "groth16 runtime",
      status: doctorStatus(report.groth16Runtime.installed),
      detail: [
        `package=${report.groth16Runtime.packageVersion ?? "missing"}`,
        `cbv=${report.groth16Runtime.compatibleBackendVersion ?? "missing"}`,
        `crs=${report.groth16Runtime.crsCompatibleBackendVersion ?? "missing"}`,
        `workspace=${report.groth16Runtime.workspaceRoot ?? "missing"}`,
        `doctorStatus=${report.groth16Runtime.doctor.status}`,
      ].join(" "),
    },
  ];
}

function formatDoctorTable(rows) {
  const headers = ["Check", "Status", "Detail"];
  const checkWidth = Math.max(headers[0].length, ...rows.map((row) => row.check.length));
  const statusWidth = Math.max(headers[1].length, ...rows.map((row) => row.status.length));
  const header = [
    headers[0].padEnd(checkWidth),
    headers[1].padEnd(statusWidth),
    headers[2],
  ].join("  ");
  const separator = [
    "-".repeat(checkWidth),
    "-".repeat(statusWidth),
    "-".repeat(headers[2].length),
  ].join("  ");
  return [
    header,
    separator,
    ...rows.map((row) => [
      row.check.padEnd(checkWidth),
      row.status.padEnd(statusWidth),
      row.detail,
    ].join("  ")),
  ].join("\n");
}

function doctorStatus(ok) {
  if (ok === true) return "OK";
  if (ok === false) return "FAIL";
  return "UNKNOWN";
}

function formatDoctorBool(value) {
  return value === true ? "true" : "false";
}

function resolveArtifactCacheBaseRoot(
  cacheBaseRoot = process.env.PRIVATE_STATE_ARTIFACT_CACHE_ROOT
    ?? process.env.TOKAMAK_PRIVATE_CHANNELS_ROOT
    ?? defaultArtifactCacheBaseRoot(),
) {
  return resolveGenericArtifactCacheBaseRoot(cacheBaseRoot);
}

function privateStateCliArtifactRoot(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(resolveArtifactCacheBaseRoot(cacheBaseRoot), "dapps", "private-state");
}

function privateStateCliRuntimeRoot(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(privateStateCliArtifactRoot(cacheBaseRoot), "runtimes");
}

function privateStateCliArtifactChainDir(cacheBaseRoot = resolveArtifactCacheBaseRoot(), chainId) {
  return path.join(privateStateCliArtifactRoot(cacheBaseRoot), `chain-id-${requireChainId(chainId)}`);
}

function privateStateCliArtifactPaths(cacheBaseRoot = resolveArtifactCacheBaseRoot(), chainId) {
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

function privateStateCliInstallManifestPath(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return path.join(privateStateCliArtifactRoot(cacheBaseRoot), "install-manifest.json");
}

function readPrivateStateCliInstallManifest(cacheBaseRoot = resolveArtifactCacheBaseRoot()) {
  return readJsonIfExists(privateStateCliInstallManifestPath(cacheBaseRoot));
}

function writePrivateStateCliInstallManifest({
  dockerRequested,
  includeLocalArtifacts,
  localDeploymentBaseRoot,
  deploymentArtifacts,
  selectedVersions,
  tokamakCliRuntime,
  groth16Runtime,
}) {
  const manifestPath = privateStateCliInstallManifestPath(deploymentArtifacts.cacheBaseRoot);
  const manifest = {
    installedAt: new Date().toISOString(),
    package: summarizePackageReport(readPackageReport({
      name: "@tokamak-private-dapps/private-state-cli",
      packageJsonPath: path.join(privateStateCliPackageRoot, "package.json"),
    })),
    dependencies: collectDependencyPackageReports().map(summarizePackageReport),
    install: {
      dockerRequested,
      includeLocalArtifacts,
      localDeploymentBaseRoot,
      artifactCacheRoot: deploymentArtifacts.cacheBaseRoot,
      selectedVersions,
      tokamakCliRuntime,
      groth16Runtime,
      installedDeploymentArtifacts: deploymentArtifacts.installed.map((entry) => ({
        chainId: entry.chainId,
        source: entry.source,
        bridgeTimestamp: entry.bridgeTimestamp,
        dappTimestamp: entry.dappTimestamp,
      })),
    },
  };
  writeJson(manifestPath, manifest);
  return { manifestPath, manifest };
}

function summarizePackageReport(report) {
  return {
    name: report.name,
    version: report.version,
  };
}

function buildDoctorReport({ probeGpu = false } = {}) {
  const cacheBaseRoot = resolveArtifactCacheBaseRoot();
  const installManifestPath = privateStateCliInstallManifestPath(cacheBaseRoot);
  const installManifest = readJsonIfExists(installManifestPath);
  const dependencyReports = collectDependencyPackageReports(installManifest);
  const tokamakCli = inspectTokamakCliRuntime();
  const groth16Runtime = inspectGroth16Runtime();
  const gpuDockerReadiness = probeGpu
    ? inspectGpuDockerReadiness(tokamakCli)
    : buildSkippedGpuDockerReadiness(tokamakCli);
  const selectedRuntimeVersionCheck = buildSelectedRuntimeVersionCheck({
    installManifest,
    tokamakCli,
    groth16Runtime,
  });
  const checks = [
    {
      name: "dependency package versions",
      ok: dependencyReports.every((entry) => entry.ok),
      details: dependencyReports.map((entry) => ({
        name: entry.name,
        currentVersion: entry.version,
        installVersion: entry.installVersion,
        ok: entry.ok,
        error: entry.error,
      })),
    },
    selectedRuntimeVersionCheck,
    {
      name: "tokamak zk-evm runtime",
      ok: tokamakCli.installed,
      details: {
        doctorStatus: tokamakCli.doctor.status,
        runtimeRoot: tokamakCli.runtimeRoot,
        installations: tokamakCli.installations.map(({ platform, installMode, packageVersion, docker }) => ({
          platform,
          installMode,
          packageVersion,
          dockerEnvironment: docker?.dockerEnvironment ?? null,
          useGpus: docker?.useGpus ?? null,
        })),
      },
    },
    {
      name: "tokamak docker gpu readiness",
      ok: gpuDockerReadiness.ok,
      details: {
        expectedUseGpus: gpuDockerReadiness.expectedUseGpus,
        liveUseGpus: gpuDockerReadiness.liveUseGpus,
        skipped: gpuDockerReadiness.skipped,
        mismatch: gpuDockerReadiness.mismatch,
        mismatchError: gpuDockerReadiness.mismatchError,
        hostNvidiaSmi: gpuDockerReadiness.hostNvidiaSmi
          ? summarizeProbeResult(gpuDockerReadiness.hostNvidiaSmi)
          : null,
        dockerNvidiaSmi: gpuDockerReadiness.dockerNvidiaSmi
          ? summarizeProbeResult(gpuDockerReadiness.dockerNvidiaSmi)
          : null,
      },
    },
    {
      name: "groth16 runtime",
      ok: groth16Runtime.installed,
      details: {
        packageRoot: groth16Runtime.packageRoot,
        workspaceRoot: groth16Runtime.workspaceRoot,
        doctorStatus: groth16Runtime.doctor.status,
        checks: groth16Runtime.checks,
      },
    },
  ];

  return {
    action: "doctor",
    ok: checks.every((check) => check.ok),
    generatedAt: new Date().toISOString(),
    package: readPackageReport({
      name: "@tokamak-private-dapps/private-state-cli",
      packageJsonPath: path.join(privateStateCliPackageRoot, "package.json"),
    }),
    installManifest: {
      path: installManifestPath,
      exists: Boolean(installManifest),
      installedAt: installManifest?.installedAt ?? null,
      dockerRequested: installManifest?.install?.dockerRequested ?? null,
      includeLocalArtifacts: installManifest?.install?.includeLocalArtifacts ?? null,
      selectedVersions: installManifest?.install?.selectedVersions ?? null,
      tokamakCliRuntime: installManifest?.install?.tokamakCliRuntime ?? null,
      groth16Runtime: installManifest?.install?.groth16Runtime ?? null,
    },
    dependencies: dependencyReports,
    tokamakCli,
    groth16Runtime,
    gpuDockerReadiness,
    checks,
  };
}

function buildSkippedGpuDockerReadiness(tokamakCli) {
  return {
    ok: true,
    skipped: true,
    expectedUseGpus: Boolean(tokamakCli.cudaCompatible),
    liveUseGpus: null,
    mismatch: false,
    mismatchError: null,
    probeImage: DOCKER_CUDA_PROBE_IMAGE,
    hostNvidiaSmi: null,
    dockerNvidiaSmi: null,
  };
}

function buildSelectedRuntimeVersionCheck({ installManifest, tokamakCli, groth16Runtime }) {
  const selectedVersions = installManifest?.install?.selectedVersions ?? null;
  const selectedTokamakCompatibleBackendVersion = selectedVersions?.tokamak
    ? normalizePackageVersionToCompatibleBackendVersion(
      selectedVersions.tokamak,
      "selected Tokamak zk-EVM CLI version",
    )
    : null;
  const selectedGroth16CompatibleBackendVersion = selectedVersions?.groth16
    ? normalizePackageVersionToCompatibleBackendVersion(selectedVersions.groth16, "selected Groth16 CLI version")
    : null;
  const details = [
    {
      name: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      selectedVersion: selectedVersions?.tokamak ?? null,
      selectedCompatibleBackendVersion: selectedTokamakCompatibleBackendVersion,
      installedVersion: tokamakCli.packageVersion ?? null,
      compatibleBackendVersion: tokamakCli.compatibleBackendVersion ?? null,
      ok: !selectedVersions?.tokamak
        || (
          selectedVersions.tokamak === tokamakCli.packageVersion
          && selectedTokamakCompatibleBackendVersion === tokamakCli.compatibleBackendVersion
        ),
    },
    {
      name: GROTH16_PACKAGE_NAME,
      selectedVersion: selectedVersions?.groth16 ?? null,
      selectedCompatibleBackendVersion: selectedGroth16CompatibleBackendVersion,
      installedVersion: groth16Runtime.packageVersion ?? null,
      compatibleBackendVersion: groth16Runtime.compatibleBackendVersion ?? null,
      crsVersion: groth16Runtime.crsVersion ?? null,
      crsCompatibleBackendVersion: groth16Runtime.crsCompatibleBackendVersion ?? null,
      ok: !selectedVersions?.groth16
        || (
          selectedVersions.groth16 === groth16Runtime.packageVersion
          && selectedGroth16CompatibleBackendVersion === groth16Runtime.compatibleBackendVersion
          && selectedGroth16CompatibleBackendVersion === groth16Runtime.crsCompatibleBackendVersion
        ),
    },
  ];
  return {
    name: "selected proof backend runtime versions",
    ok: details.every((entry) => entry.ok),
    details,
  };
}

async function resolvePrivateStateInstallRuntimeVersions(args) {
  const [groth16, tokamak] = await Promise.all([
    resolveRequestedGroth16PackageVersion(args.groth16CliVersion),
    resolveRequestedNpmPackageVersion({
      packageName: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      requestedVersion: args.tokamakZkEvmCliVersion,
      optionName: "--tokamak-zk-evm-cli-version",
    }),
  ]);
  return { groth16, tokamak };
}

async function resolveRequestedGroth16PackageVersion(requestedVersion) {
  if (requestedVersion !== undefined && requestedVersion !== null) {
    return resolveRequestedNpmPackageVersion({
      packageName: GROTH16_PACKAGE_NAME,
      requestedVersion,
      optionName: "--groth16-cli-version",
    });
  }

  const bundledPackageJson = readJson(path.join(resolveGroth16PackageRoot(), "package.json"));
  return requireSemverVersion(bundledPackageJson.version, `${GROTH16_PACKAGE_NAME} bundled package version`);
}

async function resolveRequestedNpmPackageVersion({ packageName, requestedVersion, optionName }) {
  const metadata = await fetchNpmPackageMetadata(packageName);
  if (requestedVersion === undefined || requestedVersion === null) {
    return requireSemverVersion(metadata?.["dist-tags"]?.latest, `${packageName} npm latest version`);
  }

  const normalizedVersion = requireSemverVersion(requestedVersion, optionName);
  if (!metadata.versions?.[normalizedVersion]) {
    throw new Error(`npm package ${packageName} does not contain version ${normalizedVersion}.`);
  }
  return normalizedVersion;
}

async function installTokamakCliRuntimeForPrivateState({ version, docker }) {
  const packageInstall = installManagedNpmPackage({
    packageName: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
    version,
  });
  const invocation = buildTokamakCliInvocationForPackageRoot(packageInstall.packageRoot);
  const installArgs = [...invocation.args, "--install"];
  if (docker) {
    installArgs.push("--docker");
  }
  run(invocation.command, installArgs, { cwd: packageInstall.packageRoot });
  const doctor = runCaptured(invocation.command, [...invocation.args, "--doctor"], {
    cwd: packageInstall.packageRoot,
  });
  const doctorOutput = stripAnsi(`${doctor.stdout}${doctor.stderr}`);
  const runtimeRoot = parseRuntimeRootFromTokamakDoctorOutput(doctorOutput);
  const compatibleBackendVersion = readTokamakCliPackageCompatibleBackendVersion(packageInstall.packageRoot);
  expect(
    doctor.status === 0 && runtimeRoot,
    [
      "Tokamak zk-EVM CLI install completed, but tokamak-cli --doctor did not report a healthy runtime.",
      doctorOutput.trim(),
    ].filter(Boolean).join(" "),
  );
  return {
    packageName: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
    packageVersion: version,
    compatibleBackendVersion,
    packageRoot: packageInstall.packageRoot,
    entryPath: invocation.entryPath,
    installPrefix: packageInstall.installPrefix,
    runtimeRoot,
    dockerRequested: Boolean(docker),
  };
}

async function installGroth16RuntimeForPrivateState({ version, docker }) {
  const packageInstall = resolveGroth16RuntimePackageInstall(version);
  const packageRoot = packageInstall.packageRoot;
  const entryPath = resolveGroth16CliEntryPath(packageRoot);
  const args = [entryPath, "--install", "--no-setup"];
  if (docker) {
    args.push("--docker");
  }
  run(process.execPath, args, { cwd: packageRoot });
  const compatibleBackendVersion = readGroth16PackageCompatibleBackendVersion(packageRoot);
  const crsInstall = await installGroth16CrsForPrivateStateVersion(compatibleBackendVersion);
  const runtime = inspectGroth16Runtime({ packageRoot });
  expect(runtime.installed, "Groth16 runtime install completed, but tokamak-groth16 --doctor still reports an unhealthy runtime.");
  return {
    ...runtime,
    packageName: GROTH16_PACKAGE_NAME,
    packageVersion: version,
    compatibleBackendVersion,
    packageRoot,
    entryPath,
    installPrefix: packageInstall.installPrefix,
    crsVersion: crsInstall.version,
    crs: crsInstall,
    dockerRequested: Boolean(docker),
  };
}

function resolveGroth16RuntimePackageInstall(version) {
  const normalizedVersion = requireSemverVersion(version, `${GROTH16_PACKAGE_NAME} version`);
  const bundledPackageRoot = resolveGroth16PackageRoot();
  const bundledPackageJson = readJson(path.join(bundledPackageRoot, "package.json"));
  if (bundledPackageJson.name === GROTH16_PACKAGE_NAME && bundledPackageJson.version === normalizedVersion) {
    return {
      packageName: GROTH16_PACKAGE_NAME,
      version: normalizedVersion,
      installPrefix: null,
      packageRoot: bundledPackageRoot,
    };
  }

  return installManagedNpmPackage({
    packageName: GROTH16_PACKAGE_NAME,
    version: normalizedVersion,
  });
}

async function installGroth16CrsForPrivateStateVersion(version) {
  const workspaceRoot = defaultGroth16WorkspaceRoot();
  const crsDir = path.join(workspaceRoot, "crs");
  const existingInstall = readExistingGroth16CrsInstall({ version, crsDir });
  if (existingInstall) {
    return existingInstall;
  }
  const crsInstall = await downloadPublicGroth16MpcArtifactsByVersion({
    version,
    outputDir: crsDir,
    selectedFiles: [
      "circuit_final.zkey",
      "verification_key.json",
      "metadata.json",
      "zkey_provenance.json",
    ],
  });
  const manifestPath = path.join(workspaceRoot, "install-manifest.json");
  const manifest = readJsonIfExists(manifestPath) ?? {};
  writeJson(manifestPath, {
    ...manifest,
    workspaceRoot,
    crsSource: "public-drive-mpc",
    crs: crsInstall,
  });
  return crsInstall;
}

function readExistingGroth16CrsInstall({ version, crsDir }) {
  const normalizedVersion = requireCanonicalGroth16CompatibleBackendVersion(version, "Groth16 MPC CRS version");
  const selectedFiles = [
    "circuit_final.zkey",
    "verification_key.json",
    "metadata.json",
    "zkey_provenance.json",
  ];
  const targetPaths = selectedFiles.map((fileName) => path.join(crsDir, fileName));
  if (!targetPaths.every((targetPath) => fs.existsSync(targetPath))) {
    return null;
  }
  const metadata = readJson(path.join(crsDir, "metadata.json"));
  let metadataVersion;
  try {
    metadataVersion = requireCanonicalGroth16CompatibleBackendVersion(
      metadata.compatibleBackendVersion,
      "installed Groth16 MPC CRS version",
    );
  } catch {
    return null;
  }
  if (metadataVersion !== normalizedVersion) {
    return null;
  }
  const provenance = readJson(path.join(crsDir, "zkey_provenance.json"));
  return {
    source: "local-cache",
    archiveName: provenance.published_archive_name ?? null,
    archiveFileId: parseDriveFileIdFromDownloadUrl(provenance.zkey_download_url),
    folderUrl: provenance.published_folder_url ?? null,
    version: normalizedVersion,
    installedFiles: selectedFiles.map((archivePath, index) => ({
      archivePath,
      targetPath: targetPaths[index],
    })),
  };
}

function parseDriveFileIdFromDownloadUrl(value) {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  try {
    return new URL(value).searchParams.get("id");
  } catch {
    return null;
  }
}

function installManagedNpmPackage({ packageName, version, cacheBaseRoot = resolveArtifactCacheBaseRoot() }) {
  const normalizedPackageName = requireNonEmptyString(packageName, "packageName");
  const normalizedVersion = requireSemverVersion(version, `${normalizedPackageName} version`);
  const installPrefix = managedNpmPackageInstallPrefix({
    packageName: normalizedPackageName,
    version: normalizedVersion,
    cacheBaseRoot,
  });
  fs.mkdirSync(installPrefix, { recursive: true });
  run("npm", [
    "install",
    "--prefix",
    installPrefix,
    "--omit=dev",
    "--no-audit",
    "--fund=false",
    `${normalizedPackageName}@${normalizedVersion}`,
  ]);
  const packageRoot = path.join(installPrefix, "node_modules", ...normalizedPackageName.split("/"));
  const packageJsonPath = path.join(packageRoot, "package.json");
  const packageJson = readJson(packageJsonPath);
  expect(
    packageJson.name === normalizedPackageName && packageJson.version === normalizedVersion,
    `Installed package ${packageJsonPath} does not match ${normalizedPackageName}@${normalizedVersion}.`,
  );
  return {
    packageName: normalizedPackageName,
    version: normalizedVersion,
    installPrefix,
    packageRoot,
  };
}

function managedNpmPackageInstallPrefix({ packageName, version, cacheBaseRoot = resolveArtifactCacheBaseRoot() }) {
  const safePackageName = requireNonEmptyString(packageName, "packageName")
    .replace(/^@/, "")
    .replace(/[^A-Za-z0-9._-]+/g, "__");
  return path.join(privateStateCliRuntimeRoot(cacheBaseRoot), "npm", safePackageName, requireSemverVersion(version, "version"));
}

async function downloadGroth16CrsArtifactsForPrivateState({
  version,
  outputDir,
  selectedFiles,
}) {
  if (version === undefined || version === null) {
    return downloadLatestPublicGroth16MpcArtifacts({ outputDir, selectedFiles });
  }
  return downloadPublicGroth16MpcArtifactsByVersion({ version, outputDir, selectedFiles });
}

function collectDependencyPackageReports(installManifest = null) {
  const installVersions = new Map(
    Array.isArray(installManifest?.dependencies)
      ? installManifest.dependencies.map((entry) => [entry.name, entry.version])
      : [],
  );
  const targets = [
    {
      name: TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
      packageJsonPath: path.join(resolveBundledTokamakCliPackageRoot(), "package.json"),
    },
    {
      name: GROTH16_PACKAGE_NAME,
      resolveTarget: "@tokamak-private-dapps/groth16/public-drive-crs",
    },
    {
      name: "@tokamak-private-dapps/common-library",
      resolveTarget: "@tokamak-private-dapps/common-library/artifact-cache",
    },
    { name: "tokamak-l2js", resolveTarget: "tokamak-l2js" },
  ];

  return targets.map((target) => {
    const report = readPackageReport(target);
    const installVersion = installVersions.get(report.name) ?? null;
    return {
      ...report,
      installVersion,
      ok: Boolean(report.version) && (installVersion === null || installVersion === report.version),
    };
  });
}

function readPackageReport({ name, packageJsonPath = null, packageJson = null, resolveTarget = null }) {
  try {
    const resolvedPackageJsonPath = packageJsonPath
      ? path.resolve(packageJsonPath)
      : findPackageJsonForName(path.dirname(require.resolve(resolveTarget ?? name)), name);
    const resolvedPackageJson = packageJson ?? readJson(resolvedPackageJsonPath);
    return {
      name: resolvedPackageJson.name ?? name,
      version: resolvedPackageJson.version ?? null,
      packageRoot: path.dirname(resolvedPackageJsonPath),
      error: null,
    };
  } catch (error) {
    return {
      name,
      version: null,
      packageRoot: null,
      error: error.message,
      ok: false,
    };
  }
}

function findPackageJsonForName(startDir, expectedName) {
  let current = path.resolve(startDir);
  while (current !== path.dirname(current)) {
    const candidate = path.join(current, "package.json");
    if (fs.existsSync(candidate)) {
      const packageJson = readJson(candidate);
      if (packageJson.name === expectedName) {
        return candidate;
      }
    }
    current = path.dirname(current);
  }
  throw new Error(`Cannot locate package.json for ${expectedName} above ${startDir}.`);
}

function resolveGroth16PackageRoot() {
  const publicDriveCrsPath = require.resolve("@tokamak-private-dapps/groth16/public-drive-crs");
  return path.dirname(findPackageJsonForName(path.dirname(publicDriveCrsPath), "@tokamak-private-dapps/groth16"));
}

function readGroth16PackageCompatibleBackendVersion(packageRoot = resolveActiveGroth16PackageRoot()) {
  return readGroth16CompatibleBackendVersionFromPackageJson(
    readJson(path.join(packageRoot, "package.json")),
    GROTH16_PACKAGE_NAME,
  );
}

function readTokamakCliPackageCompatibleBackendVersion(packageRoot = resolveActiveTokamakCliPackageRoot()) {
  return readTokamakZkEvmCompatibleBackendVersionFromPackageJson(
    readJson(path.join(packageRoot, "package.json")),
    TOKAMAK_ZKEVM_CLI_PACKAGE_NAME,
  );
}

function resolveActiveGroth16PackageRoot() {
  const manifestPackageRoot = readPrivateStateCliInstallManifest()?.install?.groth16Runtime?.packageRoot;
  if (manifestPackageRoot && fs.existsSync(path.join(manifestPackageRoot, "package.json"))) {
    return manifestPackageRoot;
  }
  return resolveGroth16PackageRoot();
}

function resolveGroth16CliEntryPath(packageRoot = resolveGroth16PackageRoot()) {
  return path.join(packageRoot, "cli", "tokamak-groth16-cli.mjs");
}

function defaultGroth16WorkspaceRoot() {
  return path.join(os.homedir(), "tokamak-private-channels", "groth16");
}

function inspectGroth16Runtime({ packageRoot = resolveActiveGroth16PackageRoot() } = {}) {
  const entryPath = resolveGroth16CliEntryPath(packageRoot);
  const doctor = runCaptured(process.execPath, [entryPath, "--doctor", "--verbose"], { cwd: packageRoot });
  const stdout = stripAnsi(doctor.stdout).trim();
  const stderr = stripAnsi(doctor.stderr).trim();
  const report = parseJsonReport(stdout);
  const workspaceRoot = report?.workspaceRoot ?? defaultGroth16WorkspaceRoot();
  const workspaceManifest = readJsonIfExists(path.join(workspaceRoot, "install-manifest.json"));
  const crsVersion = workspaceManifest?.crs?.version ?? null;
  const packageReport = readPackageReport({
    name: GROTH16_PACKAGE_NAME,
    packageJsonPath: path.join(packageRoot, "package.json"),
  });
  const compatibleBackendVersion = readGroth16PackageCompatibleBackendVersion(packageRoot);
  const crsCompatibleBackendVersion = crsVersion
    ? requireCanonicalGroth16CompatibleBackendVersion(crsVersion, "installed Groth16 CRS version")
    : null;
  return {
    installed: doctor.status === 0 && report?.ok === true,
    packageVersion: packageReport.version,
    compatibleBackendVersion,
    packageRoot,
    entryPath,
    workspaceRoot: report?.workspaceRoot ?? null,
    crsVersion,
    crsCompatibleBackendVersion,
    crs: workspaceManifest?.crs ?? null,
    checks: report?.checks ?? [],
    doctor: {
      status: doctor.status,
      stdout,
      stderr,
    },
  };
}

function resolveActiveTokamakCliPackageRoot() {
  const manifestPackageRoot = readPrivateStateCliInstallManifest()?.install?.tokamakCliRuntime?.packageRoot;
  if (manifestPackageRoot && fs.existsSync(path.join(manifestPackageRoot, "package.json"))) {
    return manifestPackageRoot;
  }
  return resolveBundledTokamakCliPackageRoot();
}

function buildTokamakCliInvocationForPackageRoot(packageRoot = resolveActiveTokamakCliPackageRoot()) {
  const resolvedPackageRoot = path.resolve(packageRoot);
  const entryPath = resolvedPackageRoot === resolveBundledTokamakCliPackageRoot()
    ? resolveTokamakCliEntryPath()
    : path.join(resolvedPackageRoot, "dist", "cli.js");
  return {
    command: process.execPath,
    args: [entryPath],
    entryPath,
    packageRoot: resolvedPackageRoot,
  };
}

function resolveTokamakCliResourceDirForRuntimeRoot(runtimeRoot, ...segments) {
  return path.join(runtimeRoot, "resource", ...segments);
}

function requireActiveTokamakCliRuntimeRoot() {
  const runtime = inspectTokamakCliRuntime();
  expect(runtime.runtimeRoot, "Unable to resolve the installed Tokamak zk-EVM runtime root. Run install first.");
  return runtime.runtimeRoot;
}

function inspectTokamakCliRuntime({ packageRoot = resolveActiveTokamakCliPackageRoot() } = {}) {
  const invocation = buildTokamakCliInvocationForPackageRoot(packageRoot);
  const packageReport = readTokamakCliPackageReport(invocation.packageRoot);
  const doctor = runCaptured(invocation.command, [...invocation.args, "--doctor"], {
    cwd: invocation.packageRoot,
  });
  const doctorOutput = stripAnsi(`${doctor.stdout}${doctor.stderr}`);
  const runtimeRoot = parseRuntimeRootFromTokamakDoctorOutput(doctorOutput);
  const cacheRoot = resolveTokamakCliCacheRoot();
  const installations = readTokamakCliInstallations(cacheRoot);
  const dockerModeInstalled = installations.some((entry) => entry.installMode === "docker" || entry.docker);
  const cudaCompatible = installations.some((entry) => entry.docker?.useGpus === true);

  return {
    installed: doctor.status === 0 || installations.length > 0,
    packageRoot: invocation.packageRoot,
    entryPath: invocation.entryPath,
    cacheRoot,
    runtimeRoot,
    packageVersion: packageReport.version,
    compatibleBackendVersion: packageReport.compatibleBackendVersion,
    packageError: packageReport.error,
    dockerModeInstalled,
    cudaCompatible,
    doctor: {
      status: doctor.status,
      stdout: stripAnsi(doctor.stdout).trim(),
      stderr: stripAnsi(doctor.stderr).trim(),
    },
    installations,
  };
}

function inspectGpuDockerReadiness(tokamakCli) {
  const hostNvidiaSmi = runProbe("nvidia-smi", ["--query-gpu=name,driver_version", "--format=csv,noheader"]);
  const dockerNvidiaSmi = runProbe("docker", [
    "run",
    "--rm",
    "--gpus",
    "all",
    DOCKER_CUDA_PROBE_IMAGE,
    "nvidia-smi",
  ]);
  const expectedUseGpus = Boolean(tokamakCli.cudaCompatible);
  const liveUseGpus = hostNvidiaSmi.ok && dockerNvidiaSmi.ok;
  const mismatch = expectedUseGpus !== liveUseGpus;
  return {
    ok: !mismatch,
    skipped: false,
    expectedUseGpus,
    liveUseGpus,
    mismatch,
    mismatchError: mismatch
      ? [
        "Tokamak CLI Docker GPU metadata does not match live NVIDIA/Docker GPU probes.",
        `metadata useGpus=${expectedUseGpus}; live useGpus=${liveUseGpus}.`,
      ].join(" ")
      : null,
    probeImage: DOCKER_CUDA_PROBE_IMAGE,
    hostNvidiaSmi,
    dockerNvidiaSmi,
  };
}

function runProbe(command, args) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    timeout: DOCTOR_GPU_PROBE_TIMEOUT_MS,
    stdio: ["ignore", "pipe", "pipe"],
  });
  return {
    command,
    args,
    ok: !result.error && result.status === 0,
    status: result.status,
    signal: result.signal,
    error: result.error ? result.error.message : null,
    stdout: stripAnsi(result.stdout ?? "").trim(),
    stderr: stripAnsi(result.stderr ?? "").trim(),
    timedOut: result.error?.code === "ETIMEDOUT",
  };
}

function summarizeProbeResult(result) {
  return {
    command: [result.command, ...result.args].join(" "),
    ok: result.ok,
    status: result.status,
    signal: result.signal,
    error: result.error,
    timedOut: result.timedOut,
    stdout: truncateText(result.stdout, 2000),
    stderr: truncateText(result.stderr, 2000),
  };
}

function truncateText(value, maxLength) {
  const text = String(value ?? "");
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, maxLength)}...`;
}

function parseJsonReport(value) {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function resolveTokamakCliCacheRoot() {
  return path.resolve(process.env.TOKAMAK_ZKEVM_CLI_CACHE_DIR ?? path.join(os.homedir(), ".tokamak-zk-evm"));
}

function readTokamakCliInstallations(cacheRoot) {
  if (!fs.existsSync(cacheRoot)) {
    return [];
  }
  return fs.readdirSync(cacheRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const platformDir = path.join(cacheRoot, entry.name);
      const statePath = path.join(platformDir, "installation.json");
      if (!fs.existsSync(statePath)) {
        return null;
      }
      const state = readJsonIfExists(statePath);
      const dockerBootstrapPath = path.join(platformDir, "docker", "bootstrap.json");
      const docker = readJsonIfExists(dockerBootstrapPath);
      return {
        platform: entry.name,
        statePath,
        runtimeRoot: path.join(platformDir, "runtime"),
        installMode: state?.installMode ?? (docker ? "docker" : null),
        packageVersion: state?.packageVersion ?? docker?.packageVersion ?? null,
        installedAt: state?.installedAt ?? null,
        dockerBootstrapPath,
        docker,
      };
    })
    .filter(Boolean);
}

function parseRuntimeRootFromTokamakDoctorOutput(output) {
  const match = String(output ?? "").match(/^\[ ok \] Runtime workspace:\s*(.+)$/m);
  return match ? path.resolve(match[1].trim()) : null;
}

function stripAnsi(value) {
  return String(value ?? "").replace(/\u001b\[[0-9;]*m/g, "");
}

async function installPrivateStateCliArtifacts({
  dappName,
  indexFileId = process.env.PRIVATE_STATE_DRIVE_ARTIFACT_INDEX_FILE_ID
    ?? process.env.TOKAMAK_ARTIFACT_INDEX_FILE_ID
    ?? DEFAULT_PUBLIC_ARTIFACT_INDEX_FILE_ID,
  cacheBaseRoot,
  localDeploymentBaseRoot,
  localChainIds = [31337],
  groth16CrsVersion,
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
      groth16CrsVersion,
    }));
  }

  if (normalizedLocalDeploymentBaseRoot) {
    for (const chainId of localChainIds) {
      installed.push(await materializeLocalPrivateStateCliDeployment({
        chainId,
        dappName: normalizedDappName,
        cacheBaseRoot: normalizedCacheBaseRoot,
        localDeploymentBaseRoot: normalizedLocalDeploymentBaseRoot,
        groth16CrsVersion,
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
  groth16CrsVersion,
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
    selectedFiles: privateStateBridgeArtifactSelections(normalizedChainId, paths),
  });
  await materializeFlatGroth16Zkey({ paths, groth16CrsVersion });
  await materializeSelectedDriveFiles({
    targetDir: paths.rootDir,
    files: dapp.files,
    selectedFiles: privateStateDappArtifactSelections(normalizedChainId, paths),
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
  groth16CrsVersion,
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
      ...localizeArtifactSelections(bridgeDir, privateStateBridgeArtifactSelections(normalizedChainId, paths)),
      ...localizeArtifactSelections(dappDir, privateStateDappArtifactSelections(normalizedChainId, paths)),
    ],
  });
  await materializeFlatGroth16Zkey({ paths, groth16CrsVersion });
  rewriteFlatGroth16Manifest(paths.grothManifestPath, paths.grothZkeyPath);

  return {
    chainId: Number(normalizedChainId),
    source: "local",
    artifactDir: paths.rootDir,
    bridgeTimestamp,
    dappTimestamp,
  };
}

function privateStateBridgeArtifactSelections(chainId, paths) {
  return [
    [`bridge.${chainId}.json`, path.basename(paths.bridgeDeploymentPath)],
    [`bridge-abi-manifest.${chainId}.json`, path.basename(paths.bridgeAbiManifestPath)],
    [`groth16.${chainId}.latest.json`, path.basename(paths.grothManifestPath)],
  ];
}

function privateStateDappArtifactSelections(chainId, paths) {
  return [
    [`deployment.${chainId}.latest.json`, path.basename(paths.dappDeploymentPath)],
    [`storage-layout.${chainId}.latest.json`, path.basename(paths.dappStorageLayoutPath)],
    ["PrivateStateController.callable-abi.json", path.basename(paths.privateStateControllerAbiPath)],
    [`dapp-registration.${chainId}.json`, path.basename(paths.dappRegistrationPath)],
  ];
}

function localizeArtifactSelections(sourceDir, selections) {
  return selections.map(([sourceName, targetName]) => [path.join(sourceDir, sourceName), targetName]);
}

async function materializeFlatGroth16Zkey({ paths, groth16CrsVersion }) {
  await downloadGroth16CrsArtifactsForPrivateState({
    version: groth16CrsVersion,
    outputDir: paths.rootDir,
    selectedFiles: [
      ["circuit_final.zkey", path.basename(paths.grothZkeyPath)],
    ],
  });
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

export {
  buildDoctorReport,
  printDoctorHumanReport,
  resolvePrivateStateInstallRuntimeVersions,
  installTokamakCliRuntimeForPrivateState,
  installGroth16RuntimeForPrivateState,
  installPrivateStateCliArtifacts,
  writePrivateStateCliInstallManifest,
  resolveArtifactCacheBaseRoot,
  privateStateCliArtifactPaths,
  inspectGroth16Runtime,
  readTokamakCliPackageReport,
  requireActiveTokamakCliRuntimeRoot,
  resolveTokamakCliResourceDirForRuntimeRoot,
};
