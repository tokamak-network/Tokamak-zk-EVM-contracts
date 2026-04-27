import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import yazl from "yazl";
import { pipeline } from "node:stream/promises";
import {
  downloadLatestPublicGroth16MpcArtifacts,
  extractZipEntriesFromBuffer,
} from "./public-drive-crs.mjs";
import {
  groth16PackageRoot,
  groth16WorkspacePaths,
  resolveGroth16WorkspaceRoot,
} from "./paths.mjs";
import {
  assertInstalledCircuit,
  installWorkspaceCircuit,
  installedTokamakL2JsVersion,
} from "./circuit-install.mjs";
import { main as generateUpdateTreeProof } from "../prover/updateTree/generateProof.mjs";

const CRS_FILES = [
  "circuit_final.zkey",
  "verification_key.json",
  "metadata.json",
  "zkey_provenance.json",
];

export async function installGroth16Runtime({
  workspaceRoot = resolveGroth16WorkspaceRoot(),
  trustedSetup = false,
  noSetup = false,
  docker = false,
} = {}) {
  const paths = groth16WorkspacePaths(workspaceRoot);
  fs.mkdirSync(paths.rootDir, { recursive: true });

  let crsInstall = null;
  if (trustedSetup) {
    crsInstall = copyTrustedSetupArtifacts(paths.crsDir);
  } else if (!noSetup) {
    crsInstall = await downloadLatestPublicGroth16MpcArtifacts({
      outputDir: paths.crsDir,
      selectedFiles: CRS_FILES,
    });
  }

  if (!noSetup) {
    assertInstalledCrs(paths);
  }

  const circuitMetadataPath = fs.existsSync(paths.metadataPath)
    ? paths.metadataPath
    : path.join(groth16PackageRoot, "mpc-setup", "crs", "metadata.json");
  const fallbackMetadata = {
    mtDepth: Number((await import("tokamak-l2js")).MT_DEPTH),
    tokamakL2JsVersion: installedTokamakL2JsVersion(),
  };
  const circuitInstall = await installWorkspaceCircuit({
    workspaceRoot: paths.rootDir,
    metadataPath: fs.existsSync(circuitMetadataPath) ? circuitMetadataPath : null,
    metadata: fs.existsSync(circuitMetadataPath) ? null : fallbackMetadata,
  });
  const manifest = {
    installedAt: new Date().toISOString(),
    workspaceRoot: paths.rootDir,
    crsSource: noSetup ? "skipped" : trustedSetup ? "trusted-setup" : "public-drive-mpc",
    dockerRequested: Boolean(docker),
    crs: crsInstall,
    circuit: circuitInstall,
    tokamakL2JsVersion: installedTokamakL2JsVersion(),
  };
  writeJson(paths.manifestPath, manifest);
  return manifest;
}

export function uninstallGroth16Runtime({
  workspaceRoot = resolveGroth16WorkspaceRoot(),
} = {}) {
  const rootDir = resolveGroth16WorkspaceRoot(workspaceRoot);
  const existed = fs.existsSync(rootDir);
  fs.rmSync(rootDir, { recursive: true, force: true });
  return { workspaceRoot: rootDir, existed };
}

export async function proveUpdateTree({
  inputPath,
  workspaceRoot = resolveGroth16WorkspaceRoot(),
  outputDir,
} = {}) {
  const paths = groth16WorkspacePaths(workspaceRoot);
  const resolvedInputPath = path.resolve(requireNonEmptyString(inputPath, "inputPath"));
  const runDir = outputDir ? path.resolve(outputDir) : paths.latestRunDir;
  const runInputPath = path.join(runDir, "input.json");
  const runWitnessPath = path.join(runDir, "witness.wtns");
  const runProofPath = path.join(runDir, "proof.json");
  const runPublicPath = path.join(runDir, "public.json");
  const runFixturePath = path.join(runDir, "solidity_fixture.json");
  const runManifestPath = path.join(runDir, "proof-manifest.json");

  assertInstalledRuntime(paths);
  fs.rmSync(runDir, { recursive: true, force: true });
  fs.mkdirSync(runDir, { recursive: true });
  fs.copyFileSync(resolvedInputPath, runInputPath);

  const result = await generateUpdateTreeProof([
    "--input", runInputPath,
    "--metadata", paths.metadataPath,
    "--wasm", paths.wasmPath,
    "--zkey", paths.zkeyPath,
    "--witness-output", runWitnessPath,
    "--proof-output", runProofPath,
    "--public-output", runPublicPath,
    "--solidity-fixture-output", runFixturePath,
    "--skip-compile",
  ]);
  const manifest = {
    generatedAt: new Date().toISOString(),
    workspaceRoot: paths.rootDir,
    inputPath: runInputPath,
    witnessPath: result.witnessPath,
    proofPath: result.proofPath,
    publicPath: result.publicPath,
    zkeyPath: paths.zkeyPath,
    metadataPath: paths.metadataPath,
    zkeyProvenancePath: paths.provenancePath,
  };
  writeJson(runManifestPath, manifest);
  return manifest;
}

export async function verifyUpdateTreeProof({
  inputPath,
  workspaceRoot = resolveGroth16WorkspaceRoot(),
} = {}) {
  const paths = groth16WorkspacePaths(workspaceRoot);
  const proofDir = inputPath ? await materializeProofInput(inputPath, paths) : paths.latestRunDir;
  const proofPath = path.join(proofDir, "proof.json");
  const publicPath = path.join(proofDir, "public.json");

  assertInstalledCrs(paths);
  assertFile("Groth16 proof", proofPath);
  assertFile("Groth16 public signals", publicPath);
  run(findSnarkjs(), ["groth16", "verify", paths.verificationKeyPath, publicPath, proofPath], paths.rootDir);
  return {
    proofPath,
    publicPath,
    verificationKeyPath: paths.verificationKeyPath,
  };
}

async function materializeProofInput(inputPath, paths) {
  const resolvedInputPath = path.resolve(inputPath);
  if (!resolvedInputPath.endsWith(".zip")) {
    return resolvedInputPath;
  }

  const tempDir = path.join(paths.rootDir, "runs", ".verify-tmp");
  fs.rmSync(tempDir, { recursive: true, force: true });
  fs.mkdirSync(tempDir, { recursive: true });
  const entries = await extractZipEntriesFromBuffer(fs.readFileSync(resolvedInputPath), [
    "proof.json",
    "public.json",
  ]);
  for (const fileName of ["proof.json", "public.json"]) {
    const content = entries.get(fileName);
    if (!content) {
      throw new Error(`Proof archive is missing ${fileName}: ${resolvedInputPath}`);
    }
    fs.writeFileSync(path.join(tempDir, fileName), content);
  }
  return tempDir;
}

export async function extractLatestProof({
  outputPath,
  workspaceRoot = resolveGroth16WorkspaceRoot(),
} = {}) {
  const resolvedOutputPath = path.resolve(requireNonEmptyString(outputPath, "outputPath"));
  const paths = groth16WorkspacePaths(workspaceRoot);
  const files = [
    [path.join(paths.latestRunDir, "input.json"), "input.json"],
    [path.join(paths.latestRunDir, "proof.json"), "proof.json"],
    [path.join(paths.latestRunDir, "public.json"), "public.json"],
    [path.join(paths.latestRunDir, "proof-manifest.json"), "proof-manifest.json"],
    [paths.metadataPath, "metadata.json"],
  ];
  if (fs.existsSync(paths.provenancePath)) {
    files.push([paths.provenancePath, "zkey_provenance.json"]);
  }

  for (const [filePath, label] of files) {
    assertFile(label, filePath);
  }

  fs.mkdirSync(path.dirname(resolvedOutputPath), { recursive: true });
  const zipFile = new yazl.ZipFile();
  for (const [filePath, archivePath] of files) {
    zipFile.addFile(filePath, archivePath);
  }
  zipFile.end();
  await pipeline(zipFile.outputStream, fs.createWriteStream(resolvedOutputPath));
  return { outputPath: resolvedOutputPath, files: files.map(([, archivePath]) => archivePath) };
}

export function doctorGroth16Runtime({
  workspaceRoot = resolveGroth16WorkspaceRoot(),
} = {}) {
  const paths = groth16WorkspacePaths(workspaceRoot);
  const checks = [];
  const add = (name, ok, details = null) => checks.push({ name, ok, details });
  const installManifest = fs.existsSync(paths.manifestPath) ? readJson(paths.manifestPath) : null;
  const requiresProvenance = installManifest?.crsSource !== "trusted-setup";

  add("workspace", fs.existsSync(paths.rootDir), paths.rootDir);
  for (const [name, filePath] of [
    ["circuit_final.zkey", paths.zkeyPath],
    ["verification_key.json", paths.verificationKeyPath],
    ["metadata.json", paths.metadataPath],
    ["circuit_updateTree.wasm", paths.wasmPath],
  ]) {
    add(name, fs.existsSync(filePath), filePath);
  }
  if (requiresProvenance || fs.existsSync(paths.provenancePath)) {
    add("zkey_provenance.json", fs.existsSync(paths.provenancePath), paths.provenancePath);
  }

  let hashChecks = [];
  if (fs.existsSync(paths.provenancePath)) {
    const provenance = readJson(paths.provenancePath);
    hashChecks = [
      ["zkey_sha256", paths.zkeyPath],
      ["verification_key_sha256", paths.verificationKeyPath],
      ["metadata_sha256", paths.metadataPath],
    ].map(([field, filePath]) => ({
      field,
      expected: provenance[field] ?? null,
      actual: fs.existsSync(filePath) ? sha256FileSync(filePath) : null,
      ok: Boolean(provenance[field]) && fs.existsSync(filePath) && sha256FileSync(filePath) === provenance[field],
    }));
    add("provenance hashes", hashChecks.every((entry) => entry.ok), hashChecks);
  }

  if (fs.existsSync(paths.metadataPath)) {
    const metadata = readJson(paths.metadataPath);
    const installedVersion = installedTokamakL2JsVersion();
    add(
      "tokamak-l2js version",
      metadata.tokamakL2JsVersion === installedVersion,
      { metadata: metadata.tokamakL2JsVersion, installed: installedVersion },
    );
  }

  const ok = checks.every((check) => check.ok);
  return { ok, workspaceRoot: paths.rootDir, checks };
}

function copyTrustedSetupArtifacts(crsDir) {
  const sourceDir = path.join(groth16PackageRoot, "trusted-setup", "crs");
  fs.rmSync(crsDir, { recursive: true, force: true });
  fs.mkdirSync(crsDir, { recursive: true });
  for (const fileName of CRS_FILES.filter((entry) => entry !== "zkey_provenance.json")) {
    fs.copyFileSync(path.join(sourceDir, fileName), path.join(crsDir, fileName));
  }
  return { source: "trusted-setup", sourceDir, installedFiles: CRS_FILES.filter((entry) => entry !== "zkey_provenance.json") };
}

function assertInstalledRuntime(paths) {
  assertInstalledCrs(paths);
  assertInstalledCircuit(paths.rootDir);
}

function assertInstalledCrs(paths) {
  assertFile("Groth16 proving key", paths.zkeyPath);
  assertFile("Groth16 verification key", paths.verificationKeyPath);
  assertFile("Groth16 metadata", paths.metadataPath);
}

function findSnarkjs() {
  const candidates = [
    path.join(groth16PackageRoot, "node_modules", ".bin", "snarkjs"),
    path.join(groth16PackageRoot, "..", "node_modules", ".bin", "snarkjs"),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) ?? "snarkjs";
}

function run(command, args, cwd) {
  execFileSync(command, args, {
    cwd,
    stdio: "inherit",
  });
}

function assertFile(label, filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, payload) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function sha256FileSync(filePath) {
  return createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function requireNonEmptyString(value, label) {
  const normalized = String(value ?? "").trim();
  if (!normalized) {
    throw new Error(`${label} must be a non-empty string.`);
  }
  return normalized;
}
