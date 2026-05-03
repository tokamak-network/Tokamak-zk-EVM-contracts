#!/usr/bin/env node

import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { resolveCircomBinaryPath } from "../circuits/circom-platform.mjs";
import { readGroth16CompatibleBackendVersionFromPackageJsonPath } from "../lib/versioning.mjs";
import {
    createCommandRunner,
    downloadFile,
    ensureTools,
    hashFile
} from "./lib/setup-utils.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(import.meta.url);
const groth16Root = path.resolve(__dirname, "..");
const circuitsRoot = path.join(groth16Root, "circuits");
const trustedSetupRoot = path.join(groth16Root, "mpc-setup");
const packageJsonPath = path.join(groth16Root, "package.json");
const tmpRoot = path.join(trustedSetupRoot, ".tmp");
const outputDir = path.join(trustedSetupRoot, "crs");
const templatePath = path.join(circuitsRoot, "src", "circuit_updateTree.template.circom");
const renderedCircuitPath = path.join(circuitsRoot, "src", "circuit_updateTree.circom");
const buildDir = path.join(circuitsRoot, "build", "updateTree");
const circuitBaseName = "circuit_updateTree";
const compiledR1csPath = path.join(buildDir, `${circuitBaseName}.r1cs`);
const rustManifestPath = path.join(trustedSetupRoot, "Cargo.toml");
const localSnarkJsBinary = path.join(circuitsRoot, "node_modules", ".bin", "snarkjs");
const { run, runCapture, resolveCommand } = createCommandRunner({ groth16Root, localSnarkJsBinary });
const duskSource = Object.freeze({
    ceremony: "Dusk Trusted Setup for BLS12-381",
    ceremonyUrl: "https://github.com/dusk-network/trusted-setup",
    contributionId: "0015",
    readmeUrl: "https://raw.githubusercontent.com/dusk-network/trusted-setup/main/contributions/0015/README.md",
    responseUrl: "https://drive.google.com/file/d/1nv9WpxXWMiP8-YwImd2FVn523u7_sb48/view?usp=sharing",
    responseFileId: "1nv9WpxXWMiP8-YwImd2FVn523u7_sb48",
    responseSha256: "52c9d47e5cddd585b9b0c2e5ade6f809046d516289302871766bdc463e7be214",
    responseBlake2b:
        "eaaed2b710a90c0a54fb98e47a60f14ac341ee48d6d39322164f36690dc414465e07b104e0208ad0d9d58111fcc53fd032dd3676940fa3c9232f3428d0b00ca6",
    reportUrl: "https://raw.githubusercontent.com/dusk-network/trusted-setup/main/contributions/0015/report.txt",
    maxPower: 21
});

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function ensureTooling() {
    ensureCircuitDependencies();

    ensureTools({
        resolveCommand,
        runCapture,
        tools: [
            { name: "cargo", command: "cargo", args: ["--version"] },
            { name: "npm", command: "npm", args: ["--version"] },
            { name: "node", command: "node", args: ["--version"] },
            { name: "snarkjs", command: "snarkjs", args: ["r1cs", "info", "--help"], allowNonZeroExit: true }
        ]
    });

    resolveCircomBinaryPath();
}

function ensureCircuitDependencies() {
    const poseidonCircuit = path.join(
        circuitsRoot,
        "node_modules",
        "poseidon-bls12381-circom",
        "circuits",
        "poseidon255.circom"
    );
    if (fs.existsSync(poseidonCircuit)) {
        return;
    }
    run("npm", ["install", "--ignore-scripts"], { cwd: circuitsRoot });
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

function cleanupStaleTemporaryState() {
    if (!fs.existsSync(tmpRoot)) {
        return;
    }

    for (const entry of fs.readdirSync(tmpRoot)) {
        if (entry.startsWith("updateTree-dusk-setup-")) {
            fs.rmSync(path.join(tmpRoot, entry), { recursive: true, force: true });
        }
    }
}

function resolveGroth16CompatibleBackendVersion() {
    return readGroth16CompatibleBackendVersionFromPackageJsonPath(packageJsonPath, "Groth16 package");
}

function resolveWorkspaceRoot() {
    const candidate = path.resolve(groth16Root, "..", "..");
    const workspacePackageJsonPath = path.join(candidate, "package.json");
    if (!fs.existsSync(workspacePackageJsonPath)) {
        return null;
    }

    const workspacePackageJson = readJson(workspacePackageJsonPath);
    const workspaces = Array.isArray(workspacePackageJson.workspaces)
        ? workspacePackageJson.workspaces
        : workspacePackageJson.workspaces?.packages;
    if (!Array.isArray(workspaces) || !workspaces.includes("packages/groth16")) {
        return null;
    }
    return candidate;
}

function installLatestTokamakL2JsFromRegistry() {
    const latestVersion = stripAnsi(runCapture("npm", ["view", "tokamak-l2js", "version"])).trim();
    if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(latestVersion)) {
        throw new Error(`Failed to resolve latest tokamak-l2js version from npm registry: ${latestVersion}`);
    }

    const workspaceRoot = resolveWorkspaceRoot();
    const installArgs = workspaceRoot
        ? [
            "install",
            "--workspace",
            "@tokamak-private-dapps/groth16",
            `tokamak-l2js@${latestVersion}`,
            "--ignore-scripts",
            "--no-audit",
            "--no-fund"
        ]
        : [
            "install",
            `tokamak-l2js@${latestVersion}`,
            "--ignore-scripts",
            "--no-audit",
            "--no-fund"
        ];
    const installCwd = workspaceRoot ?? groth16Root;
    console.log(`Installing tokamak-l2js@${latestVersion} from npm registry...`);
    run("npm", installArgs, { cwd: installCwd });

    const installedPackageJson = readJson(resolveTokamakL2JsPackageJsonPath());
    if (installedPackageJson.version !== latestVersion) {
        throw new Error(
            `tokamak-l2js registry/install mismatch: registry latest is ${latestVersion}, `
                + `but Node resolves ${installedPackageJson.version}.`
        );
    }
    console.log(`Using tokamak-l2js@${installedPackageJson.version} from ${resolveTokamakL2JsPackageJsonPath()}`);
    return installedPackageJson;
}

async function ensureDuskResponse(workDir) {
    const responsePath = path.join(workDir, `dusk_response_${duskSource.contributionId}`);
    const url = `https://drive.google.com/uc?export=download&id=${duskSource.responseFileId}`;
    let autoDownloaded = false;

    for (let attempt = 0; attempt < 2; attempt += 1) {
        if (!fs.existsSync(responsePath)) {
            console.log(`Downloading Dusk response ${duskSource.contributionId}...`);
            await downloadFile(url, responsePath);
            autoDownloaded = true;
        }

        const hash = await hashFile(responsePath, "blake2b512");
        if (hash === duskSource.responseBlake2b) {
            return {
                responsePath,
                autoDownloaded
            };
        }

        fs.rmSync(responsePath, { force: true });
        if (attempt === 1) {
            throw new Error(
                `Dusk response hash mismatch. expected=${duskSource.responseBlake2b} actual=${hash}`
            );
        }
    }
}

function buildPhase1SourceProvenance({ responsePath, responseSha256, autoDownloaded, power }) {
    const responseStat = fs.statSync(responsePath);
    const maxExponentUsed = 2 ** power;

    return {
        DuskGroth16: {
            source_url: `https://drive.usercontent.google.com/download?id=${duskSource.responseFileId}&export=download&confirm=t`,
            source_size_bytes: responseStat.size,
            raw_encoding: "compressed-response",
            pinned_contribution: duskSource.contributionId,
            pinned_readme_url: duskSource.readmeUrl,
            pinned_drive_file_id: duskSource.responseFileId,
            expected_source_sha256: duskSource.responseSha256,
            actual_source_sha256: responseSha256,
            auto_downloaded: autoDownloaded,
            downloaded_contribution: autoDownloaded ? duskSource.contributionId : null,
            downloaded_readme_url: autoDownloaded ? duskSource.readmeUrl : null,
            downloaded_drive_file_id: autoDownloaded ? duskSource.responseFileId : null,
            max_g1_exp_used: maxExponentUsed,
            max_g2_exp_used: maxExponentUsed,
            transcript_consistency_verified: false
        }
    };
}

function resolveTokamakL2JsPackageJsonPath() {
    const entryPath = require.resolve("tokamak-l2js");
    const packageRoot = entryPath.includes(`${path.sep}dist${path.sep}`)
        ? entryPath.slice(0, entryPath.lastIndexOf(`${path.sep}dist${path.sep}`))
        : path.dirname(entryPath);
    return path.join(packageRoot, "package.json");
}

function renderCircuit(mtDepth, version) {
    const template = fs.readFileSync(templatePath, "utf8");
    const body = template.split("__MT_DEPTH__").join(String(mtDepth));
    const rendered = [
        "pragma circom 2.2.2;",
        "",
        'include "./templates.circom";',
        "",
        "// Generated by packages/groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs.",
        "// Source template: packages/groth16/circuits/src/circuit_updateTree.template.circom",
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
    const zkeyProvenancePath = path.join(outputDir, "zkey_provenance.json");

    fs.rmSync(workDir, { recursive: true, force: true });
    fs.mkdirSync(workDir, { recursive: true });
    fs.mkdirSync(outputDir, { recursive: true });

    const duskResponse = await ensureDuskResponse(tmpRoot);
    fs.copyFileSync(duskResponse.responsePath, responsePath);
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
    const responseSha256 = await hashFile(responsePath, "sha256");
    const phase1FinalPtauSha256 = await hashFile(phase1FinalPtau, "sha256");
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

    const metadataPath = path.join(outputDir, "metadata.json");
    fs.writeFileSync(metadataPath, JSON.stringify(metadata, null, 2) + "\n");
    fs.writeFileSync(
        zkeyProvenancePath,
        JSON.stringify(
            {
                generated_at_utc: new Date().toISOString(),
                backend_version: resolveGroth16CompatibleBackendVersion(),
                phase1_source_provenance: buildPhase1SourceProvenance({
                    responsePath,
                    responseSha256,
                    autoDownloaded: duskResponse.autoDownloaded,
                    power
                }),
                phase1_final_ptau_file: path.basename(phase1FinalPtau),
                phase1_final_ptau_sha256: phase1FinalPtauSha256,
                zkey_sha256: await hashFile(zkeyFinal, "sha256"),
                metadata_sha256: await hashFile(metadataPath, "sha256"),
                verification_key_sha256: await hashFile(verificationKey, "sha256"),
                published_folder_url: null,
                published_archive_name: null,
                zkey_download_url: null
            },
            null,
            2
        ) + "\n"
    );
    fs.rmSync(workDir, { recursive: true, force: true });
}

async function main() {
    ensureTooling();
    const tokamakL2jsPackageJson = installLatestTokamakL2JsFromRegistry();
    fs.mkdirSync(tmpRoot, { recursive: true });
    cleanupStaleTemporaryState();

    const tokamakL2js = await import("tokamak-l2js");
    const mtDepth = tokamakL2js.MT_DEPTH;
    if (!Number.isInteger(mtDepth) || mtDepth <= 0) {
        throw new Error(`Invalid MT_DEPTH exported by tokamak-l2js@${tokamakL2jsPackageJson.version}: ${String(mtDepth)}`);
    }
    const manifest = { version: tokamakL2jsPackageJson.version, mtDepth };
    renderCircuit(manifest.mtDepth, manifest.version);
    compileCircuit();

    const constraintCount = readConstraintCount(compiledR1csPath);
    await generateSetupArtifacts(constraintCount, manifest);
}

main().catch((error) => {
    console.error(error instanceof Error ? error.stack ?? error.message : String(error));
    process.exit(1);
});
