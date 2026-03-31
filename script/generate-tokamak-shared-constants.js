#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const DEFAULT_SETUP_PARAMS_PATH = "submodules/Tokamak-zk-EVM/dist/resource/qap-compiler/library/setupParams.json";
const DEFAULT_FRONTEND_CFG_PATH = "submodules/Tokamak-zk-EVM/dist/resource/qap-compiler/library/frontendCfg.json";
const TARGET_FILES = [
  {
    path: "bridge/src/ChannelManager.sol",
    replacements: [
      {
        pattern: /uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = \d+;/,
        render: ({ aPubBlockLength }) => `uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = ${aPubBlockLength};`,
      },
      {
        pattern: /uint256 internal constant TOKAMAK_PREVIOUS_BLOCK_HASHES = \d+;/,
        render: ({ previousBlockHashCount }) =>
          `uint256 internal constant TOKAMAK_PREVIOUS_BLOCK_HASHES = ${previousBlockHashCount};`,
      },
    ],
  },
  {
    path: "apps/private-state/cli/private-state-bridge-cli.mjs",
    replacements: [
      {
        pattern: /const TOKAMAK_APUB_BLOCK_LENGTH = \d+;/,
        render: ({ aPubBlockLength }) => `const TOKAMAK_APUB_BLOCK_LENGTH = ${aPubBlockLength};`,
      },
      {
        pattern: /const TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT = \d+;/,
        render: ({ previousBlockHashCount }) =>
          `const TOKAMAK_PREVIOUS_BLOCK_HASH_COUNT = ${previousBlockHashCount};`,
      },
    ],
  },
  {
    path: "script/zk/lib/tokamak-artifacts.mjs",
    replacements: [
      {
        pattern: /const TOKAMAK_APUB_BLOCK_LENGTH = \d+;/,
        render: ({ aPubBlockLength }) => `const TOKAMAK_APUB_BLOCK_LENGTH = ${aPubBlockLength};`,
      },
    ],
  },
];

function main() {
  const setupParamsPath = path.resolve(process.argv[2] ?? DEFAULT_SETUP_PARAMS_PATH);
  const frontendCfgPath = path.resolve(process.argv[3] ?? DEFAULT_FRONTEND_CFG_PATH);
  const json = JSON.parse(fs.readFileSync(setupParamsPath, "utf8"));
  const frontendCfg = JSON.parse(fs.readFileSync(frontendCfgPath, "utf8"));

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

  const previousBlockHashCount = Number(frontendCfg.nPrevBlockHashes);
  if (!Number.isInteger(previousBlockHashCount) || previousBlockHashCount < 0) {
    throw new Error(
      `frontendCfg.json nPrevBlockHashes must be a non-negative integer. Received: ${frontendCfg.nPrevBlockHashes}`,
    );
  }

  for (const target of TARGET_FILES) {
    const targetPath = path.resolve(target.path);
    let next = fs.readFileSync(targetPath, "utf8");
    for (const replacement of target.replacements) {
      if (!replacement.pattern.test(next)) {
        throw new Error(`Failed to update ${target.path}: replacement marker not found.`);
      }
      next = next.replace(
        replacement.pattern,
        replacement.render({ aPubBlockLength, previousBlockHashCount }),
      );
    }
    fs.writeFileSync(targetPath, next);
  }

  console.log(
    [
      `Updated shared Tokamak constants from ${path.relative(process.cwd(), setupParamsPath)}`,
      `and ${path.relative(process.cwd(), frontendCfgPath)}.`,
      `a_pub_block length=${aPubBlockLength} (l_free=${lFree}, l_user=${lUser}),`,
      `nPrevBlockHashes=${previousBlockHashCount}.`,
    ].join(" "),
  );
}

main();
