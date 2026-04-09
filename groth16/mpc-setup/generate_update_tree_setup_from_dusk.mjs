#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import https from "node:https";
import path from "node:path";
import { fileURLToPath, pathToFileURL, URL, URLSearchParams } from "node:url";

import { resolveCircomBinaryPath } from "../../scripts/groth16/circuits/circom-platform.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../..");
const groth16Root = path.join(repoRoot, "groth16");
const circuitsRoot = path.join(groth16Root, "circuits");
const trustedSetupRoot = path.join(groth16Root, "mpc-setup");
const tmpRoot = path.join(trustedSetupRoot, ".tmp");
const outputDir = path.join(trustedSetupRoot, "crs");
const templatePath = path.join(circuitsRoot, "src", "circuit_updateTree.template.circom");
const renderedCircuitPath = path.join(circuitsRoot, "src", "circuit_updateTree.circom");
const buildDir = path.join(circuitsRoot, "build", "updateTree");
const circuitBaseName = "circuit_updateTree";
const compiledR1csPath = path.join(buildDir, `${circuitBaseName}.r1cs`);
const rustManifestPath = path.join(trustedSetupRoot, "Cargo.toml");
const localSnarkJsBinary = path.join(circuitsRoot, "node_modules", ".bin", "snarkjs");
const resolvedCommands = new Map();
const duskSource = Object.freeze({
    ceremony: "Dusk Trusted Setup for BLS12-381",
    ceremonyUrl: "https://github.com/dusk-network/trusted-setup",
    contributionId: "0015",
    responseUrl: "https://drive.google.com/file/d/1nv9WpxXWMiP8-YwImd2FVn523u7_sb48/view?usp=sharing",
    responseFileId: "1nv9WpxXWMiP8-YwImd2FVn523u7_sb48",
    responseBlake2b:
        "eaaed2b710a90c0a54fb98e47a60f14ac341ee48d6d39322164f36690dc414465e07b104e0208ad0d9d58111fcc53fd032dd3676940fa3c9232f3428d0b00ca6",
    reportUrl: "https://raw.githubusercontent.com/dusk-network/trusted-setup/main/contributions/0015/report.txt",
    maxPower: 21
});

function resolveCommand(command) {
    if (resolvedCommands.has(command)) {
        return resolvedCommands.get(command);
    }

    const directCandidates = [];
    if (command === "node") {
        if (process.execPath) {
            directCandidates.push(process.execPath);
        }
    }
    if (command === "snarkjs") {
        directCandidates.push(localSnarkJsBinary);
    }

    const pathEntries = (process.env.PATH ?? "").split(path.delimiter).filter(Boolean);
    const candidates = [
        ...directCandidates,
        ...pathEntries.map((entry) => path.join(entry, command))
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
    if (command === "snarkjs") {
        return execFileSync(resolveCommand("node"), [resolveCommand("snarkjs"), ...args], {
            cwd: repoRoot,
            encoding: "utf8",
            stdio: ["ignore", "pipe", "pipe"],
            ...options
        });
    }

    return execFileSync(resolveCommand(command), args, {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
        ...options
    });
}

function run(command, args, options = {}) {
    if (command === "snarkjs") {
        execFileSync(resolveCommand("node"), [resolveCommand("snarkjs"), ...args], {
            cwd: repoRoot,
            stdio: "inherit",
            ...options
        });
        return;
    }

    execFileSync(resolveCommand(command), args, {
        cwd: repoRoot,
        stdio: "inherit",
        ...options
    });
}

function ensureTooling() {
    const tools = [
        { name: "cargo", command: "cargo", args: ["--version"] },
        { name: "npm", command: "npm", args: ["--version"] },
        { name: "node", command: "node", args: ["--version"] },
        { name: "snarkjs", command: "snarkjs", args: ["r1cs", "info", "--help"], allowNonZeroExit: true }
    ];

    for (const tool of tools) {
        const resolved = resolveCommand(tool.command);
        if (!fs.existsSync(resolved)) {
            throw new Error(`Missing required tool: ${tool.name}`);
        }

        try {
            runCapture(tool.command, tool.args);
        } catch (error) {
            if (tool.allowNonZeroExit) {
                continue;
            }
            throw new Error(`Missing required tool: ${tool.name}`);
        }
    }

    resolveCircomBinaryPath();
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
        if (
            entry.startsWith("tokamak-l2js-latest-") ||
            entry.startsWith("updateTree-dusk-setup-")
        ) {
            fs.rmSync(path.join(tmpRoot, entry), { recursive: true, force: true });
        }
    }
}

function downloadFile(url, destinationPath) {
    const tmpDestinationPath = `${destinationPath}.download`;
    fs.rmSync(tmpDestinationPath, { force: true });

    return downloadFileInternal(url, destinationPath, tmpDestinationPath);
}

function downloadFileInternal(url, destinationPath, tmpDestinationPath) {
    return new Promise((resolve, reject) => {
        const request = https.get(url, { headers: { "user-agent": "Mozilla/5.0" } }, (response) => {
            if (
                response.statusCode &&
                response.statusCode >= 300 &&
                response.statusCode < 400 &&
                response.headers.location
            ) {
                response.resume();
                const redirectedUrl = new URL(response.headers.location, url).toString();
                downloadFileInternal(redirectedUrl, destinationPath, tmpDestinationPath).then(resolve, reject);
                return;
            }

            if (response.statusCode !== 200) {
                response.resume();
                reject(new Error(`Failed to download ${url}: HTTP ${response.statusCode ?? "unknown"}`));
                return;
            }

            const contentType = String(response.headers["content-type"] ?? "").toLowerCase();
            if (contentType.includes("text/html")) {
                const chunks = [];
                response.on("data", (chunk) => chunks.push(chunk));
                response.on("end", () => {
                    try {
                        const html = Buffer.concat(chunks).toString("utf8");
                        const confirmedUrl = extractGoogleDriveConfirmedDownloadUrl(url, html);
                        if (!confirmedUrl) {
                            reject(new Error(`Failed to resolve Google Drive confirmed download URL for ${url}`));
                            return;
                        }
                        downloadFileInternal(confirmedUrl, destinationPath, tmpDestinationPath).then(resolve, reject);
                    } catch (error) {
                        reject(error);
                    }
                });
                response.on("error", reject);
                return;
            }

            const file = fs.createWriteStream(tmpDestinationPath);
            file.on("error", (error) => {
                response.destroy(error);
            });

            response.on("error", (error) => {
                file.destroy(error);
            });

            file.on("finish", () => {
                file.close(() => {
                    fs.renameSync(tmpDestinationPath, destinationPath);
                    resolve();
                });
            });

            response.pipe(file);
        });

        request.on("error", (error) => {
            fs.rmSync(tmpDestinationPath, { force: true });
            reject(error);
        });
    });
}

function extractGoogleDriveConfirmedDownloadUrl(sourceUrl, html) {
    const formMatch = html.match(/<form[^>]*id="download-form"[^>]*action="([^"]+)"/i);
    if (!formMatch) {
        return null;
    }

    const actionUrl = new URL(formMatch[1], sourceUrl);
    const params = new URLSearchParams();
    const inputPattern = /<input[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*value="([^"]*)"/gi;
    let match;
    while ((match = inputPattern.exec(html)) !== null) {
        params.set(match[1], match[2]);
    }

    actionUrl.search = params.toString();
    return actionUrl.toString();
}

async function ensureDuskResponse(workDir) {
    const responsePath = path.join(workDir, `dusk_response_${duskSource.contributionId}`);
    const url = `https://drive.google.com/uc?export=download&id=${duskSource.responseFileId}`;

    for (let attempt = 0; attempt < 2; attempt += 1) {
        if (!fs.existsSync(responsePath)) {
            console.log(`Downloading Dusk response ${duskSource.contributionId}...`);
            await downloadFile(url, responsePath);
        }

        const hash = await hashFile(responsePath, "blake2b512");
        if (hash === duskSource.responseBlake2b) {
            return responsePath;
        }

        fs.rmSync(responsePath, { force: true });
        if (attempt === 1) {
            throw new Error(
                `Dusk response hash mismatch. expected=${duskSource.responseBlake2b} actual=${hash}`
            );
        }
    }
}

function hashFile(filePath, algorithm) {
    return new Promise((resolve, reject) => {
        const hasher = crypto.createHash(algorithm);
        const stream = fs.createReadStream(filePath);

        stream.on("data", (chunk) => hasher.update(chunk));
        stream.on("end", () => resolve(hasher.digest("hex")));
        stream.on("error", reject);
    });
}

async function installLatestTokamakL2Js(version, installDir) {
    fs.mkdirSync(installDir, { recursive: true });
    fs.writeFileSync(
        path.join(installDir, "package.json"),
        JSON.stringify(
            {
                name: "update-tree-mpc-setup-runner",
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

function runRustPtauConverter(responsePath, outputPath, targetPower) {
    run(
        "cargo",
        [
            "run",
            "--manifest-path",
            rustManifestPath,
            "--release",
            "--",
            "response-to-ptau",
            "--response",
            responsePath,
            "--power",
            String(targetPower),
            "--output",
            outputPath
        ]
    );
}

async function generateSetupArtifacts(constraintCount, manifest) {
    const power = nextPowerOfTwoExponent(constraintCount + 1);
    if (power > duskSource.maxPower) {
        throw new Error(
            `updateTree requires power ${power}, but the imported Dusk response only supports up to ${duskSource.maxPower}.`
        );
    }

    const workDir = path.join(tmpRoot, `updateTree-dusk-setup-${Date.now()}`);
    const responsePath = path.join(workDir, `dusk_response_${duskSource.contributionId}`);
    const rawPhase1Ptau = path.join(workDir, `dusk_truncated_${String(power).padStart(2, "0")}.ptau`);
    const phase1FinalPtau = path.join(outputDir, `phase1_final_${String(power).padStart(2, "0")}.ptau`);
    const zkey0 = path.join(workDir, `${circuitBaseName}_0000.zkey`);
    const zkey1 = path.join(workDir, `${circuitBaseName}_0001.zkey`);
    const zkeyFinal = path.join(outputDir, "circuit_final.zkey");
    const verificationKey = path.join(outputDir, "verification_key.json");

    fs.rmSync(workDir, { recursive: true, force: true });
    fs.mkdirSync(workDir, { recursive: true });
    fs.mkdirSync(outputDir, { recursive: true });

    fs.copyFileSync(await ensureDuskResponse(tmpRoot), responsePath);
    runRustPtauConverter(responsePath, rawPhase1Ptau, power);
    run("snarkjs", ["powersoftau", "prepare", "phase2", rawPhase1Ptau, phase1FinalPtau]);

    run("snarkjs", ["groth16", "setup", compiledR1csPath, phase1FinalPtau, zkey0]);
    run("snarkjs", [
        "zkey",
        "contribute",
        zkey0,
        zkey1,
        "--name=updateTree phase2 contribution",
        "--entropy=updateTree phase2 deterministic entropy"
    ]);
    run("snarkjs", ["zkey", "verify", compiledR1csPath, phase1FinalPtau, zkey1]);
    run("snarkjs", [
        "zkey",
        "beacon",
        zkey1,
        zkeyFinal,
        "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
        "10",
        "--name=updateTree phase2 beacon"
    ]);
    run("snarkjs", ["zkey", "verify", compiledR1csPath, phase1FinalPtau, zkeyFinal]);
    run("snarkjs", ["zkey", "export", "verificationkey", zkeyFinal, verificationKey]);

    const responseHash = await hashFile(responsePath, "blake2b512");
    const metadata = {
        circuit: "updateTree",
        tokamakL2JsVersion: manifest.version,
        mtDepth: manifest.mtDepth,
        constraintCount,
        powersOfTauPower: power,
        generatedAt: new Date().toISOString(),
        phase1Source: {
            ceremony: duskSource.ceremony,
            ceremonyUrl: duskSource.ceremonyUrl,
            contributionId: duskSource.contributionId,
            responseUrl: duskSource.responseUrl,
            reportUrl: duskSource.reportUrl,
            verifiedBlake2b512: responseHash
        },
        note: "Phase 1 points were extracted from the published Dusk response artifact only for the powers required by updateTree. The generated ptau is a tooling-compatible truncated reconstruction, not a faithful serialized transcript of the original Dusk ceremony.",
        phase2Contributions: 1,
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
        await generateSetupArtifacts(constraintCount, manifest);
    } finally {
        fs.rmSync(installDir, { recursive: true, force: true });
    }
}

main().catch((error) => {
    console.error(error instanceof Error ? error.stack ?? error.message : String(error));
    process.exit(1);
});
