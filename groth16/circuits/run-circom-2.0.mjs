#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { resolveCircomBinaryPath } from "./circom-platform.mjs";

const binaryPath = resolveCircomBinaryPath();
const result = spawnSync(binaryPath, process.argv.slice(2), {
  stdio: "inherit",
});

if (result.error) {
  throw result.error;
}

process.exit(result.status ?? 1);
