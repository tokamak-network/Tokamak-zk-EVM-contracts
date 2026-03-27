#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { resolveCircomBinaryPath } from "./circom-platform.mjs";

function ensureOutputDirectory(args) {
  const outputFlagIndex = args.indexOf("--output");
  if (outputFlagIndex === -1 || outputFlagIndex + 1 >= args.length) {
    return;
  }

  const outputDir = args[outputFlagIndex + 1];
  const resolvedOutputDir = path.resolve(process.cwd(), outputDir);
  fs.mkdirSync(resolvedOutputDir, { recursive: true });
}

const args = process.argv.slice(2);
ensureOutputDirectory(args);

const binaryPath = resolveCircomBinaryPath();
const result = spawnSync(binaryPath, args, {
  stdio: "inherit",
});

if (result.error) {
  throw result.error;
}

process.exit(result.status ?? 1);
