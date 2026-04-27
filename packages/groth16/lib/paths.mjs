import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const groth16PackageRoot = path.resolve(__dirname, "..");

export function defaultGroth16WorkspaceRoot() {
  return path.join(os.homedir(), "tokamak-private-channels", "groth16");
}

export function resolveGroth16WorkspaceRoot(workspaceRoot = defaultGroth16WorkspaceRoot()) {
  return path.resolve(workspaceRoot);
}

export function groth16WorkspacePaths(workspaceRoot = resolveGroth16WorkspaceRoot()) {
  const rootDir = resolveGroth16WorkspaceRoot(workspaceRoot);
  const crsDir = path.join(rootDir, "crs");
  const buildDir = path.join(rootDir, "build");
  const proofDir = path.join(rootDir, "proof");
  const tmpDir = path.join(rootDir, "tmp");

  return {
    rootDir,
    crsDir,
    buildDir,
    proofDir,
    tmpDir,
    circuitSourceDir: path.join(tmpDir, "circuit-src"),
    verifyTmpDir: path.join(tmpDir, "verify"),
    wasmPath: path.join(buildDir, "circuit_updateTree.wasm"),
    r1csPath: path.join(buildDir, "circuit_updateTree.r1cs"),
    zkeyPath: path.join(crsDir, "circuit_final.zkey"),
    verificationKeyPath: path.join(crsDir, "verification_key.json"),
    metadataPath: path.join(crsDir, "metadata.json"),
    provenancePath: path.join(crsDir, "zkey_provenance.json"),
    inputPath: path.join(proofDir, "input.json"),
    witnessPath: path.join(tmpDir, "witness.wtns"),
    proofPath: path.join(proofDir, "proof.json"),
    publicPath: path.join(proofDir, "public.json"),
    proofManifestPath: path.join(proofDir, "proof-manifest.json"),
    manifestPath: path.join(rootDir, "install-manifest.json"),
  };
}
