#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolveCircomBinaryPath } from '../circuits/circom-platform.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const groth16Root = path.join(repoRoot, "groth16");
const circuitsRoot = path.join(groth16Root, "circuits");
const trustedSetupRoot = path.join(groth16Root, "trusted-setup");
const tmpRoot = path.join(trustedSetupRoot, ".tmp");
const outputDir = path.join(trustedSetupRoot, "crs");
const templatePath = path.join(circuitsRoot, "src", "circuit_updateTree.template.circom");
const renderedCircuitPath = path.join(circuitsRoot, "src", "circuit_updateTree.circom");
const buildDir = path.join(circuitsRoot, "build", "updateTree");
const circuitBaseName = "circuit_updateTree";
const compiledR1csPath = path.join(buildDir, `${circuitBaseName}.r1cs`);
const resolvedCommands = new Map();

function resolveCommand(command) {
    if (resolvedCommands.has(command)) {
        return resolvedCommands.get(command);
    }

    const pathEntries = (process.env.PATH ?? "").split(path.delimiter).filter(Boolean);
    const candidates = [
        ...pathEntries.map((entry) => path.join(entry, command)),
        path.join("/opt/homebrew/bin", command),
        path.join("/usr/local/bin", command),
        path.join("/usr/bin", command)
    ];

    for (const candidate of candidates) {
        if (fs.existsSync(candidate)) {
            resolvedCommands.set(command, candidate);
            return candidate;
        }
    }

    resolvedCommands.set(command, command);
    return command;
}

function runCapture(command, args, options = {}) {
    return execFileSync(resolveCommand(command), args, {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
        ...options
    });
}

function run(command, args, options = {}) {
    execFileSync(resolveCommand(command), args, {
        cwd: repoRoot,
        stdio: "inherit",
        ...options
    });
}

function ensureTooling() {
    const tools = [
        { name: "npm", command: "npm", args: ["--version"] },
        { name: "node", command: "node", args: ["--version"] },
        { name: "snarkjs", command: "snarkjs", args: [] }
    ];

    for (const tool of tools) {
        const resolved = resolveCommand(tool.command);
        if (!fs.existsSync(resolved)) {
            throw new Error(`Missing required tool: ${tool.name}`);
        }

        if (tool.args.length > 0) {
            try {
                runCapture(tool.command, tool.args);
            } catch (error) {
                throw new Error(`Missing required tool: ${tool.name}`);
            }
        }
    }

    try {
        resolveCircomBinaryPath();
    } catch (error) {
        throw new Error(error instanceof Error ? error.message : String(error));
    }
}

function stripAnsi(value) {
    return value.replace(/\u001b\[[0-9;]*m/g, "");
}

function nextPowerOfTwoExponent(value) {
    let power = 0;
    let limit = 1;
    while (limit < value) {
        limit *= 2;
        power += 1;
    }
    return power;
}

function readLatestPackageVersion() {
    const raw = runCapture("npm", ["view", "tokamak-l2js", "version", "--json"]);
    const version = JSON.parse(raw.trim());
    if (typeof version !== "string" || version.length === 0) {
        throw new Error("Failed to resolve the latest tokamak-l2js version.");
    }
    return version;
}

function cleanupStaleTemporaryState() {
    if (!fs.existsSync(tmpRoot)) {
        return;
    }

    for (const entry of fs.readdirSync(tmpRoot)) {
        if (entry.startsWith("tokamak-l2js-latest-") || entry.startsWith("updateTree-setup-")) {
            fs.rmSync(path.join(tmpRoot, entry), { recursive: true, force: true });
        }
    }
}

async function installLatestTokamakL2Js(version, installDir) {
    fs.mkdirSync(installDir, { recursive: true });
    fs.writeFileSync(
        path.join(installDir, "package.json"),
        JSON.stringify(
            {
                name: "update-tree-setup-runner",
                private: true,
                type: "module"
            },
            null,
            2
        ) + "\n"
    );

    run(
        "npm",
        ["install", "--no-package-lock", "--ignore-scripts", `tokamak-l2js@${version}`],
        { cwd: installDir }
    );

    const packageRoot = path.join(installDir, "node_modules", "tokamak-l2js");
    const packageJson = JSON.parse(fs.readFileSync(path.join(packageRoot, "package.json"), "utf8"));
    const moduleUrl = pathToFileURL(path.join(packageRoot, "dist", "index.js")).href;
    const pkg = await import(moduleUrl);
    const mtDepth = pkg.MT_DEPTH;

    if (!Number.isInteger(mtDepth) || mtDepth <= 0) {
        throw new Error(`Invalid MT_DEPTH exported by tokamak-l2js@${packageJson.version}: ${String(mtDepth)}`);
    }

    return { version: packageJson.version, mtDepth };
}

function renderCircuit(mtDepth, version) {
    const template = fs.readFileSync(templatePath, "utf8");
    const body = template.split("__MT_DEPTH__").join(String(mtDepth));
    const rendered = [
        "pragma circom 2.2.2;",
        "",
        'include "./templates.circom";',
        "",
        "// Generated by scripts/groth16/trusted-setup/generate_update_tree_setup.mjs.",
        "// Source template: groth16/circuits/src/circuit_updateTree.template.circom",
        `// tokamak-l2js version: ${version}`,
        `// MT_DEPTH: ${mtDepth}`,
        body.split("\n").slice(3).join("\n")
    ].join("\n");

    fs.writeFileSync(renderedCircuitPath, rendered.endsWith("\n") ? rendered : `${rendered}\n`);
}

function compileCircuit() {
    fs.rmSync(buildDir, { recursive: true, force: true });
    fs.mkdirSync(buildDir, { recursive: true });

    run(
        resolveCircomBinaryPath(),
        [
            "src/circuit_updateTree.circom",
            "--r1cs",
            "--wasm",
            "--sym",
            "--output",
            buildDir,
            "--prime",
            "bls12381"
        ],
        { cwd: circuitsRoot }
    );
}

function readConstraintCount(r1csPath) {
    const info = stripAnsi(runCapture("snarkjs", ["r1cs", "info", r1csPath]));
    const match = info.match(/# of Constraints:\s+(\d+)/);
    if (!match) {
        throw new Error("Failed to parse constraint count from snarkjs r1cs info output.");
    }
    return Number(match[1]);
}

function generateSetupArtifacts(constraintCount, manifest) {
    const power = nextPowerOfTwoExponent(constraintCount + 1);
    const workDir = path.join(tmpRoot, `updateTree-setup-${Date.now()}`);
    const ptau0 = path.join(workDir, `powersOfTau_${power}_0000.ptau`);
    const ptau1 = path.join(workDir, `powersOfTau_${power}_0001.ptau`);
    const ptauBeacon = path.join(workDir, `powersOfTau_${power}_beacon.ptau`);
    const ptauFinal = path.join(workDir, `powersOfTau_${power}_final.ptau`);
    const zkey0 = path.join(workDir, `${circuitBaseName}_0000.zkey`);
    const zkey1 = path.join(workDir, `${circuitBaseName}_0001.zkey`);
    const zkeyFinal = path.join(outputDir, "circuit_final.zkey");
    const verificationKey = path.join(outputDir, "verification_key.json");
    const beacon = crypto.randomBytes(32).toString("hex");

    fs.rmSync(workDir, { recursive: true, force: true });
    fs.mkdirSync(workDir, { recursive: true });
    fs.mkdirSync(outputDir, { recursive: true });

    run("snarkjs", ["powersoftau", "new", "bls12-381", String(power), ptau0]);
    run(
        "snarkjs",
        [
            "powersoftau",
            "contribute",
            ptau0,
            ptau1,
            '--name=updateTree phase1 contribution',
            '--entropy=updateTree phase1 deterministic entropy'
        ]
    );
    run(
        "snarkjs",
        [
            "powersoftau",
            "beacon",
            ptau1,
            ptauBeacon,
            "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
            "10",
            '--name=updateTree phase1 beacon'
        ]
    );
    run("snarkjs", ["powersoftau", "prepare", "phase2", ptauBeacon, ptauFinal]);
    run("snarkjs", ["groth16", "setup", compiledR1csPath, ptauFinal, zkey0]);
    run(
        "snarkjs",
        [
            "zkey",
            "contribute",
            zkey0,
            zkey1,
            '--name=updateTree phase2 contribution',
            '--entropy=updateTree phase2 deterministic entropy'
        ]
    );
    run("snarkjs", ["zkey", "verify", compiledR1csPath, ptauFinal, zkey1]);
    run(
        "snarkjs",
        [
            "zkey",
            "beacon",
            zkey1,
            zkeyFinal,
            "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
            "10",
            '--name=updateTree phase2 beacon'
        ]
    );
    run("snarkjs", ["zkey", "verify", compiledR1csPath, ptauFinal, zkeyFinal]);
    run("snarkjs", ["zkey", "export", "verificationkey", zkeyFinal, verificationKey]);

    const metadata = {
        circuit: "updateTree",
        tokamakL2JsVersion: manifest.version,
        mtDepth: manifest.mtDepth,
        constraintCount,
        powersOfTauPower: power,
        generatedAt: new Date().toISOString(),
        note: "This is a local deterministic development ceremony, not a production multi-party ceremony.",
        phase1Contributions: 1,
        phase2Contributions: 1,
        phase1BeaconApplied: true,
        phase2BeaconApplied: true
    };

    fs.writeFileSync(path.join(outputDir, "metadata.json"), JSON.stringify(metadata, null, 2) + "\n");
    fs.rmSync(workDir, { recursive: true, force: true });
}

async function main() {
    ensureTooling();
    fs.mkdirSync(tmpRoot, { recursive: true });
    cleanupStaleTemporaryState();

    const installDir = fs.mkdtempSync(path.join(tmpRoot, "tokamak-l2js-latest-"));
    try {
        const latestVersion = readLatestPackageVersion();
        const manifest = await installLatestTokamakL2Js(latestVersion, installDir);

        renderCircuit(manifest.mtDepth, manifest.version);
        compileCircuit();

        const constraintCount = readConstraintCount(compiledR1csPath);
        generateSetupArtifacts(constraintCount, manifest);
    } finally {
        fs.rmSync(installDir, { recursive: true, force: true });
    }
}

main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
});
