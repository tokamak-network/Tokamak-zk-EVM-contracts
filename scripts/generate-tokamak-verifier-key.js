#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const DEFAULT_INPUT = "tokamak-zkp/TokamakVerifierKey/sigma_verify.json";
const DEFAULT_OUTPUT = "tokamak-zkp/TokamakVerifierKey/TokamakVerifierKey.generated.sol";
const DEFAULT_VERIFIER_SOURCE = "tokamak-zkp/TokamakVerifier.sol";
const BLS12_381_FQ_MODULUS = BigInt(
    "0x1a0111ea397fe69a4b1ba7b6434bacd7" +
    "64774b84f38512bf6730d2a0f6b0f624" +
    "1eabfffeb153ffffb9feffffffffaaab",
);

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

function splitFq(value, label) {
    return splitG1(value, label);
}

function splitG2Coordinate(value, label) {
    const hex = normalizeHex(value, label, 192);
    return {
        c0: splitFq(`0x${hex.slice(0, 96)}`, `${label}.c0`),
        c1: splitFq(`0x${hex.slice(96)}`, `${label}.c1`),
    };
}

function negateFq(value, label) {
    const hex = normalizeHex(value, label, 96);
    const bigint = BigInt(`0x${hex}`);
    if (bigint === 0n) {
        return `0x${hex}`;
    }
    return `0x${(BLS12_381_FQ_MODULUS - bigint).toString(16).padStart(96, "0")}`;
}

function negateG2YCoordinate(value, label) {
    const hex = normalizeHex(value, label, 192);
    const c0 = negateFq(`0x${hex.slice(0, 96)}`, `${label}.c0`);
    const c1 = negateFq(`0x${hex.slice(96)}`, `${label}.c1`);
    return `0x${c0.slice(2)}${c1.slice(2)}`;
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

function readG2Point(pathLabel, point, { negateY = false } = {}) {
    if (!point || typeof point !== "object") {
        throw new Error(`${pathLabel} is missing`);
    }

    const y = negateY ? negateG2YCoordinate(point.y, `${pathLabel}.y`) : point.y;
    return {
        x: splitG2Coordinate(point.x, `${pathLabel}.x`),
        y: splitG2Coordinate(y, `${pathLabel}.y`),
    };
}

function g2ConstantLines(prefix, point) {
    return [
        `    uint256 internal constant ${prefix}_X0_PART1 = ${point.x.c0.part1};`,
        `    uint256 internal constant ${prefix}_X0_PART2 = ${point.x.c0.part2};`,
        `    uint256 internal constant ${prefix}_X1_PART1 = ${point.x.c1.part1};`,
        `    uint256 internal constant ${prefix}_X1_PART2 = ${point.x.c1.part2};`,
        `    uint256 internal constant ${prefix}_Y0_PART1 = ${point.y.c0.part1};`,
        `    uint256 internal constant ${prefix}_Y0_PART2 = ${point.y.c0.part2};`,
        `    uint256 internal constant ${prefix}_Y1_PART1 = ${point.y.c1.part1};`,
        `    uint256 internal constant ${prefix}_Y1_PART2 = ${point.y.c1.part2};`,
    ];
}

function buildGeneratedSolidity(points) {
    return `// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @dev AUTO-GENERATED FILE. DO NOT EDIT MANUALLY.
/// Source: tokamak-zkp/TokamakVerifierKey/sigma_verify.json
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

${g2ConstantLines("IDENTITY2", points.identity2).join("\n")}

${g2ConstantLines("ALPHA", points.alpha).join("\n")}

${g2ConstantLines("ALPHA_POWER2", points.alpha2).join("\n")}

${g2ConstantLines("ALPHA_POWER3", points.alpha3).join("\n")}

${g2ConstantLines("ALPHA_POWER4", points.alpha4).join("\n")}

${g2ConstantLines("GAMMA", points.gamma).join("\n")}

${g2ConstantLines("DELTA", points.delta).join("\n")}

${g2ConstantLines("ETA", points.eta).join("\n")}

${g2ConstantLines("X", points.x).join("\n")}

${g2ConstantLines("Y", points.y).join("\n")}
}
`;
}

function rewriteVerifierG2Constants(source, points) {
    let output = source;
    for (const [prefix, point] of Object.entries({
        IDENTITY2: points.identity2,
        ALPHA: points.alpha,
        ALPHA_POWER2: points.alpha2,
        ALPHA_POWER3: points.alpha3,
        ALPHA_POWER4: points.alpha4,
        GAMMA: points.gamma,
        DELTA: points.delta,
        ETA: points.eta,
        X: points.x,
        Y: points.y,
    })) {
        for (const line of g2ConstantLines(prefix, point)) {
            const [, name, value] = line.match(/constant ([A-Z0-9_]+) = (0x[0-9a-f]+);/) ?? [];
            if (!name || !value) {
                throw new Error(`Failed to parse generated constant line: ${line}`);
            }
            const pattern = new RegExp(`uint256 internal constant ${name} = 0x[0-9a-f]+;`);
            if (!pattern.test(output)) {
                throw new Error(`TokamakVerifier.sol is missing expected G2 constant ${name}`);
            }
            output = output.replace(pattern, `uint256 internal constant ${name} = ${value};`);
        }
    }
    return output;
}

function main() {
    const inputPath = path.resolve(process.argv[2] ?? DEFAULT_INPUT);
    const outputPath = path.resolve(process.argv[3] ?? DEFAULT_OUTPUT);
    const verifierSourcePath = path.resolve(process.argv[4] ?? DEFAULT_VERIFIER_SOURCE);

    const raw = fs.readFileSync(inputPath, "utf8");
    const json = JSON.parse(raw);

    const points = {
        lagrange: readPoint(json, "lagrange_KL", json.lagrange_KL),
        identity: readPoint(json, "G", json.G),
        sigmaX: readPoint(json, "sigma_1.x", json.sigma_1?.x),
        sigmaY: readPoint(json, "sigma_1.y", json.sigma_1?.y),
        identity2: readG2Point("H", json.H),
        alpha: readG2Point("sigma_2.alpha", json.sigma_2?.alpha),
        alpha2: readG2Point("sigma_2.alpha2", json.sigma_2?.alpha2),
        alpha3: readG2Point("sigma_2.alpha3", json.sigma_2?.alpha3),
        alpha4: readG2Point("sigma_2.alpha4", json.sigma_2?.alpha4),
        gamma: readG2Point("sigma_2.gamma", json.sigma_2?.gamma, { negateY: true }),
        delta: readG2Point("sigma_2.delta", json.sigma_2?.delta, { negateY: true }),
        eta: readG2Point("sigma_2.eta", json.sigma_2?.eta, { negateY: true }),
        x: readG2Point("sigma_2.x", json.sigma_2?.x, { negateY: true }),
        y: readG2Point("sigma_2.y", json.sigma_2?.y, { negateY: true }),
    };

    const output = buildGeneratedSolidity(points);
    fs.writeFileSync(outputPath, output);

    const verifierSource = fs.readFileSync(verifierSourcePath, "utf8");
    fs.writeFileSync(verifierSourcePath, rewriteVerifierG2Constants(verifierSource, points));

    console.log(`Generated ${path.relative(process.cwd(), outputPath)} from ${path.relative(process.cwd(), inputPath)}`);
    console.log(`Updated ${path.relative(process.cwd(), verifierSourcePath)} G2 constants from ${path.relative(process.cwd(), inputPath)}`);
}

main();
