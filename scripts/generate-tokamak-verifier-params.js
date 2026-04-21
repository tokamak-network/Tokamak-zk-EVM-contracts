#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { resolveSubcircuitSetupParamsPath } from "./zk/lib/tokamak-runtime-paths.mjs";

const DEFAULT_INPUT = resolveSubcircuitSetupParamsPath();
const DEFAULT_OUTPUT = "tokamak-zkp/TokamakVerifier.sol";

const OMEGA_SMAX_INVERSES = new Map([
  [64, "0x199cdaee7b3c79d6566009b5882952d6a41e85011d426b52b891fa3f982b68c5"],
  [128, "0x1996fa8d52f970ba51420be43501370b166fb582ac74db12571ba2fccf28601b"],
  [256, "0x6d64ed25272e58ee91b000235a5bfd4fc03cae032393991be9561c176a2f777a"],
  [512, "0x1907a56e80f82b2df675522e37ad4eca1c510ebfb4543a3efb350dbef02a116e"],
  [1024, "0x2bcd9508a3dad316105f067219141f4450a32c41aa67e0beb0ad80034eb71aa6"],
  [2048, "0x394fda0d65ba213edeae67bc36f376e13cc5bb329aa58ff53dc9e5600f6fb2ac"],
]);

const OMEGA_LFREE_VALUES = new Map([
  [64, "0x0e4840ac57f86f5e293b1d67bc8de5d9a12a70a615d0b8e4d2fc5e69ac5db47f"],
  [128, "0x07d0c802a94a946e8cbe2437f0b4b276501dff643be95635b750da4cab28e208"],
  [512, "0x1bb466679a5d88b1ecfbede342dee7f415c1ad4c687f28a233811ea1fe0c65f4"],
]);

const OMEGA_MI_INVERSES = new Map([
  [2048, "0x394fda0d65ba213edeae67bc36f376e13cc5bb329aa58ff53dc9e5600f6fb2ac"],
  [4096, "0x58c3ba636d174692ad5a534045625d9514180e0e8b24f12309f239f760b82267"],
]);

function rewriteVerifierSource(
  source,
  expectedLUser,
  expectedLFree,
  omegaLFree,
  expectedSmax,
  omegaInverse,
  expectedN,
  expectedMi,
  omegaMiInverse,
) {
  const lUserPattern = /uint256 internal constant EXPECTED_L_USER = \d+;/;
  const lFreePattern = /uint256 internal constant EXPECTED_L_FREE = \d+;/;
  const omegaLFreePattern = /uint256 internal constant OMEGA_L_FREE = 0x[0-9a-f]+;/;
  const nPattern = /uint256 internal constant CONSTANT_N = \d+;/;
  const miPattern = /uint256 internal constant CONSTANT_MI = \d+;/;
  const omegaMiPattern = /uint256 internal constant OMEGA_MI_1 = 0x[0-9a-f]+;/;
  const smaxPattern = /uint256 internal constant EXPECTED_SMAX = \d+;/;
  const omegaPattern = /uint256 internal constant OMEGA_SMAX_MINUS_1 =\s*\n\s*0x[0-9a-f]+;/;
  const denominatorSlotPattern = /uint256 internal constant COMPUTE_APUB_DENOMINATOR_BUFFER_SLOT = 0x[0-9a-f]+;/;
  const prefixSlotPattern = /uint256 internal constant COMPUTE_APUB_PREFIX_BUFFER_SLOT = 0x[0-9a-f]+;/;
  const step4CgSlotPattern = /uint256 internal constant STEP4_COEFF_C_G_SLOT = 0x[0-9a-f]+;/;
  const step4CfSlotPattern = /uint256 internal constant STEP4_COEFF_C_F_SLOT = 0x[0-9a-f]+;/;
  const step4CbSlotPattern = /uint256 internal constant STEP4_COEFF_C_B_SLOT = 0x[0-9a-f]+;/;

  if (
    !lUserPattern.test(source) ||
    !lFreePattern.test(source) ||
    !omegaLFreePattern.test(source) ||
    !nPattern.test(source) ||
    !miPattern.test(source) ||
    !omegaMiPattern.test(source) ||
    !smaxPattern.test(source) ||
    !omegaPattern.test(source) ||
    !denominatorSlotPattern.test(source) ||
    !prefixSlotPattern.test(source) ||
    !step4CgSlotPattern.test(source) ||
    !step4CfSlotPattern.test(source) ||
    !step4CbSlotPattern.test(source)
  ) {
    throw new Error(
      "Failed to update TokamakVerifier.sol setup constants. Expected replacement markers were not found.",
    );
  }

  const bufferBytes = expectedLFree * 0x20;
  const denominatorSlot = 0x10000 + bufferBytes;
  const prefixSlot = denominatorSlot + bufferBytes;
  const step4CgSlot = prefixSlot + bufferBytes;
  const step4CfSlot = step4CgSlot + 0x20;
  const step4CbSlot = step4CgSlot + 0x40;

  const replacedLFree = source.replace(
    lUserPattern,
    `uint256 internal constant EXPECTED_L_USER = ${expectedLUser};`,
  ).replace(
    lFreePattern,
    `uint256 internal constant EXPECTED_L_FREE = ${expectedLFree};`,
  ).replace(
    omegaLFreePattern,
    `uint256 internal constant OMEGA_L_FREE = ${omegaLFree};`,
  ).replace(
    nPattern,
    `uint256 internal constant CONSTANT_N = ${expectedN};`,
  ).replace(
    miPattern,
    `uint256 internal constant CONSTANT_MI = ${expectedMi};`,
  ).replace(
    omegaMiPattern,
    `uint256 internal constant OMEGA_MI_1 = ${omegaMiInverse};`,
  ).replace(
    denominatorSlotPattern,
    `uint256 internal constant COMPUTE_APUB_DENOMINATOR_BUFFER_SLOT = 0x${denominatorSlot.toString(16)};`,
  ).replace(
    prefixSlotPattern,
    `uint256 internal constant COMPUTE_APUB_PREFIX_BUFFER_SLOT = 0x${prefixSlot.toString(16)};`,
  ).replace(
    step4CgSlotPattern,
    `uint256 internal constant STEP4_COEFF_C_G_SLOT = 0x${step4CgSlot.toString(16)};`,
  ).replace(
    step4CfSlotPattern,
    `uint256 internal constant STEP4_COEFF_C_F_SLOT = 0x${step4CfSlot.toString(16)};`,
  ).replace(
    step4CbSlotPattern,
    `uint256 internal constant STEP4_COEFF_C_B_SLOT = 0x${step4CbSlot.toString(16)};`,
  );

  const replacedSmax = replacedLFree.replace(
    smaxPattern,
    `uint256 internal constant EXPECTED_SMAX = ${expectedSmax};`,
  );

  const replacedOmega = replacedSmax.replace(
    omegaPattern,
    `uint256 internal constant OMEGA_SMAX_MINUS_1 =\n        ${omegaInverse};`,
  );

  return replacedOmega;
}

function main() {
  const inputPath = path.resolve(process.argv[2] ?? DEFAULT_INPUT);
  const outputPath = path.resolve(process.argv[3] ?? DEFAULT_OUTPUT);

  const raw = fs.readFileSync(inputPath, "utf8");
  const json = JSON.parse(raw);

  const expectedLUser = Number(json.l_user);
  const expectedLFree = Number(json.l_free);
  const expectedN = Number(json.n);
  const expectedMi = Number(json.l_D) - Number(json.l);
  const expectedSmax = Number(json.s_max);
  if (!Number.isInteger(expectedLUser) || expectedLUser <= 0) {
    throw new Error(`setupParams.json l_user must be a positive integer. Received: ${json.l_user}`);
  }
  if (!Number.isInteger(expectedLFree) || expectedLFree <= 0) {
    throw new Error(`setupParams.json l_free must be a positive integer. Received: ${json.l_free}`);
  }
  if (!Number.isInteger(expectedSmax) || expectedSmax <= 0) {
    throw new Error(`setupParams.json s_max must be a positive integer. Received: ${json.s_max}`);
  }
  if (!Number.isInteger(expectedN) || expectedN <= 0) {
    throw new Error(`setupParams.json n must be a positive integer. Received: ${json.n}`);
  }
  if (!Number.isInteger(expectedMi) || expectedMi <= 0) {
    throw new Error(`setupParams.json l_D - l must be a positive integer. Received: ${json.l_D} - ${json.l}`);
  }

  const omegaLFree = OMEGA_LFREE_VALUES.get(expectedLFree);
  const omegaMiInverse = OMEGA_MI_INVERSES.get(expectedMi);
  const omegaInverse = OMEGA_SMAX_INVERSES.get(expectedSmax);
  if (!omegaLFree) {
    throw new Error(
      `Unsupported l_free=${expectedLFree}. Extend generate-tokamak-verifier-params.js with the matching omega_l_free value first.`,
    );
  }
  if (!omegaMiInverse) {
    throw new Error(
      `Unsupported m_i=${expectedMi}. Extend generate-tokamak-verifier-params.js with the matching omega_m_i inverse first.`,
    );
  }
  if (!omegaInverse) {
    throw new Error(
      `Unsupported s_max=${expectedSmax}. Extend generate-tokamak-verifier-params.js with the matching omega_smax inverse first.`,
    );
  }

  const source = fs.readFileSync(outputPath, "utf8");
  const output = rewriteVerifierSource(
    source,
    expectedLUser,
    expectedLFree,
    omegaLFree,
    expectedSmax,
    omegaInverse,
    expectedN,
    expectedMi,
    omegaMiInverse,
  );
  fs.writeFileSync(outputPath, output);

  console.log(
    `Updated ${path.relative(process.cwd(), outputPath)} from ${path.relative(process.cwd(), inputPath)} with l_user=${expectedLUser}, l_free=${expectedLFree}, n=${expectedN}, m_i=${expectedMi}, s_max=${expectedSmax}`,
  );
}

main();
