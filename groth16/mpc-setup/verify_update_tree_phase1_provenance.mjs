#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import https from "node:https";
import path from "node:path";
import { fileURLToPath, URL, URLSearchParams } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../..");
const groth16Root = path.join(repoRoot, "groth16");
const circuitsRoot = path.join(groth16Root, "circuits");
const trustedSetupRoot = path.join(groth16Root, "mpc-setup");
const tmpRoot = path.join(trustedSetupRoot, ".tmp");
const defaultMetadataPath = path.join(trustedSetupRoot, "updateTree", "metadata.json");
const rustManifestPath = path.join(trustedSetupRoot, "Cargo.toml");
const localSnarkJsBinary = path.join(circuitsRoot, "node_modules", ".bin", "snarkjs");
const preferredNodeCandidates = [
    "/opt/homebrew/opt/node@20/bin/node",
    "/opt/homebrew/Cellar/node@20/20.20.0/bin/node"
];
const resolvedCommands = new Map();

function findFlag(name) {
    const index = process.argv.indexOf(name);
    if (index === -1 || index + 1 >= process.argv.length) {
        return null;
    }
    return path.resolve(process.cwd(), process.argv[index + 1]);
}

function hasFlag(name) {
    return process.argv.includes(name);
}

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function resolveCommand(command) {
    if (resolvedCommands.has(command)) {
        return resolvedCommands.get(command);
    }

    const directCandidates = [];
    if (command === "node") {
        directCandidates.push(...preferredNodeCandidates);
    }
    if (command === "snarkjs") {
        directCandidates.push(localSnarkJsBinary);
    }

    const pathEntries = (process.env.PATH ?? "").split(path.delimiter).filter(Boolean);
    const candidates = [
        ...directCandidates,
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

function ensureTooling() {
    const tools = [
        { name: "cargo", command: "cargo", args: ["--version"] },
        { name: "node", command: "node", args: ["--version"] },
        { name: "snarkjs", command: "snarkjs", args: ["powersoftau", "prepare", "phase2", "--help"], allowNonZeroExit: true }
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

function fetchText(url) {
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
                fetchText(redirectedUrl).then(resolve, reject);
                return;
            }

            if (response.statusCode !== 200) {
                response.resume();
                reject(new Error(`Failed to download ${url}: HTTP ${response.statusCode ?? "unknown"}`));
                return;
            }

            const chunks = [];
            response.on("data", (chunk) => chunks.push(chunk));
            response.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
            response.on("error", reject);
        });

        request.on("error", reject);
    });
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

async function ensureResponseFile(source, cacheDir) {
    const cachedPath = path.join(cacheDir, `dusk_response_${source.contributionId}`);
    const expectedHash = source.verifiedBlake2b512.toLowerCase();

    if (fs.existsSync(cachedPath)) {
        const hash = await hashFile(cachedPath, "blake2b512");
        if (hash === expectedHash) {
            return cachedPath;
        }
        fs.rmSync(cachedPath, { force: true });
    }

    console.log(`Downloading Dusk response ${source.contributionId}...`);
    await downloadFile(source.responseUrl, cachedPath);
    const downloadedHash = await hashFile(cachedPath, "blake2b512");
    if (downloadedHash !== expectedHash) {
        throw new Error(
            `Dusk response hash mismatch. expected=${expectedHash} actual=${downloadedHash}`
        );
    }

    return cachedPath;
}

function verifyPublishedReport(reportText, expectedHash) {
    const normalized = reportText.toLowerCase().replace(/[^0-9a-f]/g, "");
    if (!normalized.includes(expectedHash.toLowerCase())) {
        throw new Error("Published Dusk report does not contain the expected response hash.");
    }
}

async function main() {
    ensureTooling();

    const metadataPath = findFlag("--metadata") ?? defaultMetadataPath;
    const metadata = readJson(metadataPath);
    const metadataDir = path.dirname(metadataPath);
    const expectedPtauPath = findFlag("--ptau") ?? path.join(
        metadataDir,
        `phase1_final_${String(metadata.powersOfTauPower).padStart(2, "0")}.ptau`
    );
    const keepTmp = hasFlag("--keep-tmp");

    const phase1Source = metadata.phase1Source;
    if (!phase1Source?.responseUrl || !phase1Source?.verifiedBlake2b512 || !phase1Source?.reportUrl) {
        throw new Error(`Metadata is missing phase1 provenance fields: ${metadataPath}`);
    }

    if (!Number.isInteger(metadata.powersOfTauPower) || metadata.powersOfTauPower <= 0) {
        throw new Error(`Metadata has invalid powersOfTauPower: ${metadata.powersOfTauPower}`);
    }

    if (!fs.existsSync(expectedPtauPath)) {
        throw new Error(`Missing committed phase1 ptau: ${expectedPtauPath}`);
    }

    fs.mkdirSync(tmpRoot, { recursive: true });
    const reportText = await fetchText(phase1Source.reportUrl);
    verifyPublishedReport(reportText, phase1Source.verifiedBlake2b512);

    const responsePath = await ensureResponseFile(phase1Source, tmpRoot);
    const workDir = fs.mkdtempSync(path.join(tmpRoot, "verify-updateTree-phase1-"));
    const rawPtauPath = path.join(workDir, `reconstructed_${String(metadata.powersOfTauPower).padStart(2, "0")}.ptau`);
    const preparedPtauPath = path.join(workDir, `prepared_${String(metadata.powersOfTauPower).padStart(2, "0")}.ptau`);

    try {
        run("cargo", [
            "run",
            "--manifest-path",
            rustManifestPath,
            "--release",
            "--",
            "response-to-ptau",
            "--response",
            responsePath,
            "--power",
            String(metadata.powersOfTauPower),
            "--output",
            rawPtauPath
        ]);

        run("snarkjs", ["powersoftau", "prepare", "phase2", rawPtauPath, preparedPtauPath]);

        const expectedHash = await hashFile(expectedPtauPath, "blake2b512");
        const rebuiltHash = await hashFile(preparedPtauPath, "blake2b512");
        const expectedSize = fs.statSync(expectedPtauPath).size;
        const rebuiltSize = fs.statSync(preparedPtauPath).size;

        if (expectedSize !== rebuiltSize || expectedHash !== rebuiltHash) {
            throw new Error(
                [
                    "Phase1 provenance verification failed.",
                    `Committed ptau size/hash: ${expectedSize} / ${expectedHash}`,
                    `Rebuilt ptau size/hash: ${rebuiltSize} / ${rebuiltHash}`
                ].join("\n")
            );
        }

        console.log("Phase1 provenance verified.");
        console.log(`Response contribution: ${phase1Source.contributionId}`);
        console.log(`Response blake2b512: ${phase1Source.verifiedBlake2b512}`);
        console.log(`Prepared ptau blake2b512: ${rebuiltHash}`);
    } finally {
        if (!keepTmp) {
            fs.rmSync(workDir, { recursive: true, force: true });
        }
    }
}

main().catch((error) => {
    console.error(error instanceof Error ? error.stack ?? error.message : String(error));
    process.exit(1);
});
