import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { groth16PackageRoot } from "./paths.mjs";

export function findSnarkjs() {
  const candidates = [
    path.join(groth16PackageRoot, "node_modules", ".bin", "snarkjs"),
    path.join(groth16PackageRoot, "..", "node_modules", ".bin", "snarkjs"),
    path.join(groth16PackageRoot, "circuits", "node_modules", ".bin", "snarkjs"),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) ?? "snarkjs";
}

export function runSnarkjs(args, cwd) {
  execFileSync(findSnarkjs(), args, {
    cwd,
    stdio: "inherit",
  });
}

export function captureSnarkjs(args, cwd) {
  return execFileSync(findSnarkjs(), args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
}
