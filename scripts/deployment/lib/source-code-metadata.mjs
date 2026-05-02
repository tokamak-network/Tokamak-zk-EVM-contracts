import path from "node:path";
import { spawnSync } from "node:child_process";

export const BRIDGE_SOURCE_PATHS = [
  "bridge/src/BridgeCore.sol",
  "bridge/src/BridgeStructs.sol",
  "bridge/src/ChannelManager.sol",
  "bridge/src/DAppManager.sol",
  "bridge/src/L1TokenVault.sol",
  "bridge/src/generated/Groth16Verifier.sol",
  "bridge/src/generated/TokamakEnvironment.sol",
  "bridge/src/generated/TokamakVerifierKey.generated.sol",
  "bridge/src/interfaces/IChannelRegistry.sol",
  "bridge/src/interfaces/IGrothVerifier.sol",
  "bridge/src/interfaces/ITokamakVerifier.sol",
  "bridge/src/mocks/FeeOnTransferMockERC20.sol",
  "bridge/src/mocks/MockERC20.sol",
  "bridge/src/verifiers/TokamakVerifier.sol",
];

export const PRIVATE_STATE_DAPP_SOURCE_PATHS = [
  "packages/apps/private-state/src/L2AccountingVault.sol",
  "packages/apps/private-state/src/PrivateStateController.sol",
];

export function buildSourceCodeMetadata(repoRoot, sourcePaths) {
  const remoteUrl = gitOutput(repoRoot, ["remote", "get-url", "origin"]) ?? "unknown";
  const commit = gitOutput(repoRoot, ["rev-parse", "HEAD"]) ?? "unknown";
  const repositoryName = parseRepositoryName(remoteUrl) ?? "unknown";
  const branch = resolveBranchLabel(repoRoot);
  const sourceBaseUrl = buildSourceBaseUrl(remoteUrl, repositoryName, commit);

  return {
    repository: {
      name: repositoryName,
      remoteUrl,
      branch,
      commit,
    },
    sources: sourcePaths.map((sourcePath) => {
      const normalizedPath = normalizeRelativePath(sourcePath);
      const source = {
        name: path.basename(normalizedPath),
        path: normalizedPath,
      };
      if (sourceBaseUrl) {
        source.sourceUrl = `${sourceBaseUrl}/${encodePathSegments(normalizedPath)}`;
      }
      return source;
    }),
  };
}

function resolveBranchLabel(repoRoot) {
  if (process.env.GITHUB_ACTIONS === "true") {
    if (process.env.GITHUB_REF_TYPE === "tag") {
      return "tagged";
    }
    if (process.env.GITHUB_REF_TYPE === "branch" && process.env.GITHUB_REF_NAME) {
      return process.env.GITHUB_REF_NAME;
    }
  }

  const branch = gitOutput(repoRoot, ["branch", "--show-current"]);
  if (branch) {
    return branch;
  }

  if (gitOutput(repoRoot, ["describe", "--tags", "--exact-match", "HEAD"])) {
    return "tagged";
  }

  if (process.env.GITHUB_ACTIONS === "true" || process.env.CI === "true") {
    return "CI";
  }

  if (gitOutput(repoRoot, ["rev-parse", "--verify", "HEAD"])) {
    return "detached head";
  }

  return "unknown";
}

function gitOutput(cwd, args) {
  const result = spawnSync("git", args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  if (result.status !== 0) {
    return null;
  }
  const output = result.stdout.trim();
  return output.length > 0 ? output : null;
}

function parseRepositoryName(remoteUrl) {
  if (!remoteUrl || remoteUrl === "unknown") {
    return null;
  }

  const httpsMatch = remoteUrl.match(/^https?:\/\/[^/]+\/(.+?)(?:\.git)?$/);
  if (httpsMatch) {
    return stripGitSuffix(httpsMatch[1]);
  }

  const sshMatch = remoteUrl.match(/^[^@]+@[^:]+:(.+?)(?:\.git)?$/);
  if (sshMatch) {
    return stripGitSuffix(sshMatch[1]);
  }

  return stripGitSuffix(path.basename(remoteUrl));
}

function stripGitSuffix(value) {
  return value.replace(/\.git$/, "");
}

function buildSourceBaseUrl(remoteUrl, repositoryName, commit) {
  if (repositoryName === "unknown" || commit === "unknown") {
    return null;
  }
  if (remoteUrl.includes("github.com")) {
    return `https://github.com/${repositoryName}/blob/${commit}`;
  }
  if (remoteUrl.includes("gitlab.com")) {
    return `https://gitlab.com/${repositoryName}/-/blob/${commit}`;
  }
  return null;
}

function normalizeRelativePath(sourcePath) {
  return sourcePath.split(path.sep).join("/");
}

function encodePathSegments(sourcePath) {
  return sourcePath.split("/").map(encodeURIComponent).join("/");
}
