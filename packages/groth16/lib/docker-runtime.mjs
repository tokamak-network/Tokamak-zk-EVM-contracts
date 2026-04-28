import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { groth16PackageRoot, groth16WorkspacePaths, resolveGroth16WorkspaceRoot } from "./paths.mjs";

export const DOCKER_CONTAINER_HOME = "/tmp";
export const DOCKER_CONTAINER_WORKSPACE_ROOT = "/tmp/tokamak-private-channels/groth16";
export const DOCKER_SNARKJS_ENTRYPOINT = "/opt/tokamak-groth16/node_modules/.bin/snarkjs";

const DOCKER_BOOTSTRAP_VERSION = 1;
const DOCKER_BASE_IMAGE = "ubuntu:22.04";
const DOCKERFILE_PATH = path.join("docker", "Dockerfile");

export function installGroth16DockerRuntime({
  workspaceRoot = resolveGroth16WorkspaceRoot(),
  trustedSetup = false,
  noSetup = false,
  verbose = false,
} = {}) {
  const hostPlatform = detectDockerHostPlatform();
  ensureDockerDaemonAvailable();

  const paths = groth16WorkspacePaths(workspaceRoot);
  fs.mkdirSync(paths.rootDir, { recursive: true });

  const packageVersion = resolveGroth16PackageVersion();
  const bootstrap = {
    version: DOCKER_BOOTSTRAP_VERSION,
    createdAt: new Date().toISOString(),
    dockerEnvironment: "ubuntu22",
    hostPlatform,
    imageName: dockerImageName(packageVersion),
    packageVersion,
    containerWorkspaceRoot: DOCKER_CONTAINER_WORKSPACE_ROOT,
  };

  buildDockerInstallImage(bootstrap.imageName);
  execFileSync("docker", dockerInstallArgs(paths.rootDir, bootstrap, { trustedSetup, noSetup, verbose }), {
    cwd: groth16PackageRoot,
    stdio: "inherit",
  });
  writeDockerBootstrap(paths, bootstrap);
  return bootstrap;
}

export function runDockerTool({
  workspaceRoot = resolveGroth16WorkspaceRoot(),
  entrypoint,
  args = [],
  cwd,
  stdio = "inherit",
}) {
  const result = runDockerToolInternal({ workspaceRoot, entrypoint, args, cwd, stdio });
  return result;
}

export function captureDockerTool({
  workspaceRoot = resolveGroth16WorkspaceRoot(),
  entrypoint,
  args = [],
  cwd,
}) {
  return runDockerToolInternal({
    workspaceRoot,
    entrypoint,
    args,
    cwd,
    stdio: ["ignore", "pipe", "pipe"],
    encoding: "utf8",
  });
}

export function readDockerBootstrap(workspaceRoot = resolveGroth16WorkspaceRoot()) {
  const paths = groth16WorkspacePaths(workspaceRoot);
  try {
    return validateDockerBootstrap(JSON.parse(fs.readFileSync(paths.dockerBootstrapPath, "utf8")));
  } catch {
    return null;
  }
}

function readInstallManifest(paths) {
  try {
    return JSON.parse(fs.readFileSync(paths.manifestPath, "utf8"));
  } catch {
    return null;
  }
}

export function dockerBootstrapRunnable(workspaceRoot = resolveGroth16WorkspaceRoot()) {
  const paths = groth16WorkspacePaths(workspaceRoot);
  const bootstrap = readDockerBootstrap(paths.rootDir);
  const manifest = readInstallManifest(paths);
  const dockerRequired = manifest?.installMode === "docker"
    || Boolean(bootstrap)
    || fs.existsSync(paths.dockerBootstrapPath);
  if (!bootstrap) {
    if (dockerRequired || process.platform === "win32") {
      throw new Error(`Groth16 Docker runtime is required, but the Docker bootstrap is missing or invalid: ${paths.dockerBootstrapPath}`);
    }
    return null;
  }
  if (process.platform === "darwin") {
    if (dockerRequired) {
      throw new Error("Groth16 Docker runtime is installed, but Docker mode is not supported on macOS.");
    }
    return null;
  }
  if (!dockerDaemonAvailable()) {
    if (dockerRequired || process.platform === "win32") {
      throw new Error("Docker is required to run the installed Groth16 Docker runtime, but the Docker daemon is not available.");
    }
    return null;
  }
  return bootstrap;
}

function runDockerToolInternal({
  workspaceRoot,
  entrypoint,
  args,
  cwd,
  stdio,
  encoding,
}) {
  const paths = groth16WorkspacePaths(workspaceRoot);
  const bootstrap = dockerBootstrapRunnable(paths.rootDir);
  if (!bootstrap) {
    return { executed: false, output: null };
  }
  const dockerArgs = [
    ...dockerRunPrefix(bootstrap),
    ...dockerUserArgs(),
    "-v",
    `${paths.rootDir}:${DOCKER_CONTAINER_WORKSPACE_ROOT}`,
    "-e",
    `HOME=${DOCKER_CONTAINER_HOME}`,
    "-w",
    mapContainerPath(path.resolve(cwd ?? paths.rootDir), paths.rootDir),
    "--entrypoint",
    entrypoint,
    bootstrap.imageName,
    ...args.map((arg) => mapContainerArgument(arg, paths.rootDir)),
  ];
  const output = execFileSync("docker", dockerArgs, {
    cwd: groth16PackageRoot,
    stdio,
    encoding,
  });
  return { executed: true, output };
}

function detectDockerHostPlatform() {
  switch (process.platform) {
    case "linux":
      return "linux";
    case "win32":
      return "windows";
    case "darwin":
      throw new Error("`tokamak-groth16 --install --docker` is not supported on macOS hosts.");
    default:
      throw new Error(`Unsupported Docker host platform: ${process.platform}. Use Linux or Windows with Docker Desktop.`);
  }
}

function dockerDaemonAvailable() {
  if (!commandExists("docker")) {
    return false;
  }
  const result = spawnSync("docker", ["info"], {
    stdio: "ignore",
  });
  return result.status === 0;
}

function ensureDockerDaemonAvailable() {
  if (!dockerDaemonAvailable()) {
    throw new Error("Docker is required for `tokamak-groth16 --install --docker`, but the Docker daemon is not available.");
  }
}

function commandExists(command) {
  const result = spawnSync(command, ["--version"], {
    stdio: "ignore",
  });
  return !result.error && result.status === 0;
}

function dockerImageName(packageVersion) {
  const sanitizedVersion = packageVersion.replace(/[^a-zA-Z0-9_.-]/gu, "-");
  return `tokamak-groth16:${sanitizedVersion}-ubuntu22`;
}

function dockerRunPrefix() {
  return ["run", "--rm"];
}

function dockerUserArgs() {
  if (typeof process.getuid !== "function" || typeof process.getgid !== "function") {
    return [];
  }
  return ["--user", `${process.getuid()}:${process.getgid()}`];
}

function buildDockerInstallImage(imageName) {
  const dockerfilePath = path.join(groth16PackageRoot, DOCKERFILE_PATH);
  if (!fs.existsSync(dockerfilePath)) {
    throw new Error(`Missing Groth16 Dockerfile: ${dockerfilePath}`);
  }
  execFileSync("docker", [
    "build",
    "--build-arg",
    `BASE_IMAGE=${DOCKER_BASE_IMAGE}`,
    "-t",
    imageName,
    "-f",
    dockerfilePath,
    groth16PackageRoot,
  ], {
    cwd: groth16PackageRoot,
    stdio: "inherit",
  });
}

function dockerInstallArgs(workspaceRoot, bootstrap, { trustedSetup, noSetup, verbose }) {
  const args = [
    ...dockerRunPrefix(bootstrap),
    ...dockerUserArgs(),
    "-v",
    `${workspaceRoot}:${DOCKER_CONTAINER_WORKSPACE_ROOT}`,
    "-e",
    `HOME=${DOCKER_CONTAINER_HOME}`,
    bootstrap.imageName,
    "--install",
  ];
  if (trustedSetup) {
    args.push("--trusted-setup");
  }
  if (noSetup) {
    args.push("--no-setup");
  }
  if (verbose) {
    args.push("--verbose");
  }
  return args;
}

function writeDockerBootstrap(paths, bootstrap) {
  fs.mkdirSync(paths.dockerDir, { recursive: true });
  fs.writeFileSync(paths.dockerBootstrapPath, `${JSON.stringify(bootstrap, null, 2)}\n`, "utf8");
  const script = [
    "#!/usr/bin/env sh",
    "set -eu",
    "exec docker run --rm \\",
    ...dockerUserShellLines(),
    `  -v ${shellQuote(`${paths.rootDir}:${DOCKER_CONTAINER_WORKSPACE_ROOT}`)} \\`,
    `  -e ${shellQuote(`HOME=${DOCKER_CONTAINER_HOME}`)} \\`,
    `  ${shellQuote(bootstrap.imageName)} "$@"`,
    "",
  ].join("\n");
  fs.writeFileSync(paths.dockerRunScriptPath, script, "utf8");
  fs.chmodSync(paths.dockerRunScriptPath, 0o755);
}

function dockerUserShellLines() {
  if (typeof process.getuid !== "function" || typeof process.getgid !== "function") {
    return [];
  }
  return ['  --user "$(id -u):$(id -g)" \\'];
}

function shellQuote(value) {
  return `'${value.replace(/'/gu, `'\\''`)}'`;
}

function validateDockerBootstrap(value) {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  if (
    value.version !== DOCKER_BOOTSTRAP_VERSION ||
    value.dockerEnvironment !== "ubuntu22" ||
    (value.hostPlatform !== "linux" && value.hostPlatform !== "windows") ||
    typeof value.imageName !== "string" ||
    typeof value.packageVersion !== "string" ||
    typeof value.createdAt !== "string" ||
    value.containerWorkspaceRoot !== DOCKER_CONTAINER_WORKSPACE_ROOT
  ) {
    return null;
  }
  return value;
}

function mapContainerArgument(arg, workspaceRoot) {
  if (typeof arg !== "string" || !path.isAbsolute(arg)) {
    return arg;
  }
  return mapContainerPath(arg, workspaceRoot);
}

function mapContainerPath(hostPath, workspaceRoot) {
  const relative = path.relative(workspaceRoot, hostPath);
  if (!relative) {
    return DOCKER_CONTAINER_WORKSPACE_ROOT;
  }
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`Docker Groth16 runtime cannot map path outside the workspace: ${hostPath}`);
  }
  return path.posix.join(DOCKER_CONTAINER_WORKSPACE_ROOT, ...relative.split(path.sep));
}

function resolveGroth16PackageVersion() {
  const packageJson = JSON.parse(fs.readFileSync(path.join(groth16PackageRoot, "package.json"), "utf8"));
  if (typeof packageJson.version === "string" && packageJson.version.length > 0) {
    return packageJson.version;
  }
  throw new Error("packages/groth16/package.json is missing a package version.");
}
