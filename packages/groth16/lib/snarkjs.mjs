import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { groth16PackageRoot, resolveGroth16WorkspaceRoot } from "./paths.mjs";
import {
  captureDockerTool,
  DOCKER_SNARKJS_ENTRYPOINT,
  runDockerTool,
} from "./docker-runtime.mjs";

export function findSnarkjs() {
  const candidates = [
    path.join(groth16PackageRoot, "node_modules", ".bin", "snarkjs"),
    path.join(groth16PackageRoot, "..", "node_modules", ".bin", "snarkjs"),
    path.join(groth16PackageRoot, "circuits", "node_modules", ".bin", "snarkjs"),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) ?? "snarkjs";
}

export function runSnarkjs(args, cwd, { workspaceRoot = resolveGroth16WorkspaceRoot() } = {}) {
  const dockerResult = runDockerTool({
    workspaceRoot,
    entrypoint: DOCKER_SNARKJS_ENTRYPOINT,
    args,
    cwd,
    stdio: "inherit",
  });
  if (dockerResult.executed) {
    return;
  }
  execFileSync(findSnarkjs(), args, {
    cwd,
    stdio: "inherit",
  });
}

export function captureSnarkjs(args, cwd, { workspaceRoot = resolveGroth16WorkspaceRoot() } = {}) {
  const dockerResult = captureDockerTool({
    workspaceRoot,
    entrypoint: DOCKER_SNARKJS_ENTRYPOINT,
    args,
    cwd,
  });
  if (dockerResult.executed) {
    return dockerResult.output;
  }
  return execFileSync(findSnarkjs(), args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
}
