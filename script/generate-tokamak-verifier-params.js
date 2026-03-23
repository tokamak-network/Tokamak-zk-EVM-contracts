#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const DEFAULT_INPUT = "submodules/Tokamak-zk-EVM/dist/resource/qap-compiler/library/setupParams.json";
const DEFAULT_OUTPUT = "tokamak-zkp/TokamakVerifier.sol";

const OMEGA_SMAX_INVERSES = new Map([
  [64, "0x199cdaee7b3c79d6566009b5882952d6a41e85011d426b52b891fa3f982b68c5"],
  [128, "0x1996fa8d52f970ba51420be43501370b166fb582ac74db12571ba2fccf28601b"],
  [256, "0x6d64ed25272e58ee91b000235a5bfd4fc03cae032393991be9561c176a2f777a"],
  [512, "0x1907a56e80f82b2df675522e37ad4eca1c510ebfb4543a3efb350dbef02a116e"],
  [1024, "0x2bcd9508a3dad316105f067219141f4450a32c41aa67e0beb0ad80034eb71aa6"],
  [2048, "0x394fda0d65ba213edeae67bc36f376e13cc5bb329aa58ff53dc9e5600f6fb2ac"],
]);

function rewriteVerifierSource(source, expectedSmax, omegaInverse) {
  const smaxPattern = /uint256 internal constant EXPECTED_SMAX = \d+;/;
  const omegaPattern = /uint256 internal constant OMEGA_SMAX_MINUS_1 =\s*\n\s*0x[0-9a-f]+;/;

  if (!smaxPattern.test(source) || !omegaPattern.test(source)) {
    throw new Error("Failed to update TokamakVerifier.sol smax constants. Expected replacement markers were not found.");
  }

  const replacedSmax = source.replace(
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

  const expectedSmax = Number(json.s_max);
  if (!Number.isInteger(expectedSmax) || expectedSmax <= 0) {
    throw new Error(`setupParams.json s_max must be a positive integer. Received: ${json.s_max}`);
  }

  const omegaInverse = OMEGA_SMAX_INVERSES.get(expectedSmax);
  if (!omegaInverse) {
    throw new Error(
      `Unsupported s_max=${expectedSmax}. Extend generate-tokamak-verifier-params.js with the matching omega_smax inverse first.`,
    );
  }

  const source = fs.readFileSync(outputPath, "utf8");
  const output = rewriteVerifierSource(source, expectedSmax, omegaInverse);
  fs.writeFileSync(outputPath, output);

  console.log(
    `Updated ${path.relative(process.cwd(), outputPath)} from ${path.relative(process.cwd(), inputPath)} with s_max=${expectedSmax}`,
  );
}

main();
