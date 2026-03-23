#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const DEFAULT_INPUT = "src/verifier/TokamakVerifierKey/sigma_verify.json";
const DEFAULT_OUTPUT = "src/verifier/TokamakVerifierKey/TokamakVerifierKey.generated.sol";

function normalizeHex(value, label, expectedHexLen) {
    if (typeof value !== "string") {
        throw new Error(`${label} must be a hex string`);
    }

    let hex = value.startsWith("0x") ? value.slice(2) : value;
    hex = hex.toLowerCase();

    if (hex.length > expectedHexLen) {
        throw new Error(`${label} exceeds expected length (${hex.length} > ${expectedHexLen})`);
    }

    return hex.padStart(expectedHexLen, "0");
}

function splitG1(value, label) {
    const hex = normalizeHex(value, label, 96);
    const part1 = hex.slice(0, 32);
    const part2 = hex.slice(32);

    return {
        part1: `0x${part1.padStart(64, "0")}`,
        part2: `0x${part2.padStart(64, "0")}`,
    };
}

function readPoint(json, pathLabel, point) {
    if (!point || typeof point !== "object") {
        throw new Error(`${pathLabel} is missing`);
    }

    return {
        x: splitG1(point.x, `${pathLabel}.x`),
        y: splitG1(point.y, `${pathLabel}.y`),
    };
}

function buildGeneratedSolidity(points) {
    return `// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @dev AUTO-GENERATED FILE. DO NOT EDIT MANUALLY.
/// Source: src/verifier/TokamakVerifierKey/sigma_verify.json
library TokamakVerifierKeyGenerated {
    uint256 internal constant LAGRANGE_KL_X_PART1 = ${points.lagrange.x.part1};
    uint256 internal constant LAGRANGE_KL_X_PART2 = ${points.lagrange.x.part2};
    uint256 internal constant LAGRANGE_KL_Y_PART1 = ${points.lagrange.y.part1};
    uint256 internal constant LAGRANGE_KL_Y_PART2 = ${points.lagrange.y.part2};

    uint256 internal constant IDENTITY_X_PART1 = ${points.identity.x.part1};
    uint256 internal constant IDENTITY_X_PART2 = ${points.identity.x.part2};
    uint256 internal constant IDENTITY_Y_PART1 = ${points.identity.y.part1};
    uint256 internal constant IDENTITY_Y_PART2 = ${points.identity.y.part2};

    uint256 internal constant SIGMA_X_X_PART1 = ${points.sigmaX.x.part1};
    uint256 internal constant SIGMA_X_X_PART2 = ${points.sigmaX.x.part2};
    uint256 internal constant SIGMA_X_Y_PART1 = ${points.sigmaX.y.part1};
    uint256 internal constant SIGMA_X_Y_PART2 = ${points.sigmaX.y.part2};

    uint256 internal constant SIGMA_Y_X_PART1 = ${points.sigmaY.x.part1};
    uint256 internal constant SIGMA_Y_X_PART2 = ${points.sigmaY.x.part2};
    uint256 internal constant SIGMA_Y_Y_PART1 = ${points.sigmaY.y.part1};
    uint256 internal constant SIGMA_Y_Y_PART2 = ${points.sigmaY.y.part2};
}
`;
}

function main() {
    const inputPath = path.resolve(process.argv[2] ?? DEFAULT_INPUT);
    const outputPath = path.resolve(process.argv[3] ?? DEFAULT_OUTPUT);

    const raw = fs.readFileSync(inputPath, "utf8");
    const json = JSON.parse(raw);

    const points = {
        lagrange: readPoint(json, "lagrange_KL", json.lagrange_KL),
        identity: readPoint(json, "G", json.G),
        sigmaX: readPoint(json, "sigma_1.x", json.sigma_1?.x),
        sigmaY: readPoint(json, "sigma_1.y", json.sigma_1?.y),
    };

    const output = buildGeneratedSolidity(points);
    fs.writeFileSync(outputPath, output);

    console.log(`Generated ${path.relative(process.cwd(), outputPath)} from ${path.relative(process.cwd(), inputPath)}`);
}

main();
