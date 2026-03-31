#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const DEFAULT_INPUT = "submodules/Tokamak-zk-EVM/dist/resource/qap-compiler/library/setupParams.json";
const TARGET_FILES = [
  {
    path: "bridge/src/ChannelManager.sol",
    pattern: /uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = \d+;/,
    render: (value) => `uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = ${value};`,
  },
  {
    path: "apps/private-state/cli/private-state-bridge-cli.mjs",
    pattern: /const TOKAMAK_APUB_BLOCK_LENGTH = \d+;/,
    render: (value) => `const TOKAMAK_APUB_BLOCK_LENGTH = ${value};`,
  },
  {
    path: "script/zk/lib/tokamak-artifacts.mjs",
    pattern: /const TOKAMAK_APUB_BLOCK_LENGTH = \d+;/,
    render: (value) => `const TOKAMAK_APUB_BLOCK_LENGTH = ${value};`,
  },
];

function main() {
  const inputPath = path.resolve(process.argv[2] ?? DEFAULT_INPUT);
  const raw = fs.readFileSync(inputPath, "utf8");
  const json = JSON.parse(raw);

  const lUser = Number(json.l_user);
  const lFree = Number(json.l_free);
  if (!Number.isInteger(lUser) || lUser < 0) {
    throw new Error(`setupParams.json l_user must be a non-negative integer. Received: ${json.l_user}`);
  }
  if (!Number.isInteger(lFree) || lFree <= 0) {
    throw new Error(`setupParams.json l_free must be a positive integer. Received: ${json.l_free}`);
  }

  const aPubBlockLength = lFree - lUser;
  if (!Number.isInteger(aPubBlockLength) || aPubBlockLength <= 0) {
    throw new Error(
      `setupParams.json must satisfy l_free - l_user > 0. Received: ${lFree} - ${lUser} = ${aPubBlockLength}`,
    );
  }

  for (const target of TARGET_FILES) {
    const targetPath = path.resolve(target.path);
    const source = fs.readFileSync(targetPath, "utf8");
    if (!target.pattern.test(source)) {
      throw new Error(`Failed to update ${target.path}: replacement marker not found.`);
    }
    const next = source.replace(target.pattern, target.render(aPubBlockLength));
    fs.writeFileSync(targetPath, next);
  }

  console.log(
    `Updated shared Tokamak a_pub_block length to ${aPubBlockLength} from ${path.relative(process.cwd(), inputPath)} (l_free=${lFree}, l_user=${lUser}).`,
  );
}

main();
