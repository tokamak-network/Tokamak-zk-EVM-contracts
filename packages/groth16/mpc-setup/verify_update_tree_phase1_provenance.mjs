#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
    createCommandRunner,
    downloadFile,
    ensureTools,
    fetchText,
    hashFile
} from "./lib/setup-utils.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const groth16Root = path.resolve(__dirname, "..");
const circuitsRoot = path.join(groth16Root, "circuits");
const trustedSetupRoot = path.join(groth16Root, "mpc-setup");
const tmpRoot = path.join(trustedSetupRoot, ".tmp");
const defaultMetadataPath = path.join(trustedSetupRoot, "crs", "metadata.json");
const rustManifestPath = path.join(trustedSetupRoot, "Cargo.toml");
const localSnarkJsBinary = path.join(circuitsRoot, "node_modules", ".bin", "snarkjs");
const { run, runCapture, resolveCommand } = createCommandRunner({ groth16Root, localSnarkJsBinary });

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

function ensureTooling() {
    ensureTools({
        resolveCommand,
        runCapture,
        tools: [
            { name: "cargo", command: "cargo", args: ["--version"] },
            { name: "node", command: "node", args: ["--version"] },
            { name: "snarkjs", command: "snarkjs", args: ["powersoftau", "prepare", "phase2", "--help"], allowNonZeroExit: true }
        ]
    });
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
