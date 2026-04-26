import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const groth16PackageRoot = path.resolve(__dirname, "..");

export function defaultGroth16WorkspaceRoot() {
  return path.join(os.homedir(), "tokamak-private-channels", "groth16");
}

export function resolveGroth16WorkspaceRoot(workspaceRoot = process.env.TOKAMAK_GROTH16_WORKSPACE_ROOT
  ?? defaultGroth16WorkspaceRoot()) {
  return path.resolve(workspaceRoot);
}

export function groth16WorkspacePaths(workspaceRoot = resolveGroth16WorkspaceRoot()) {
  const rootDir = resolveGroth16WorkspaceRoot(workspaceRoot);
  const crsDir = path.join(rootDir, "crs");
  const circuitsDir = path.join(rootDir, "circuits");
  const latestRunDir = path.join(rootDir, "runs", "latest");

  return {
    rootDir,
    crsDir,
    circuitsDir,
    latestRunDir,
    circuitEntrypointPath: path.join(circuitsDir, "src", "circuit_updateTree.circom"),
    templatePath: path.join(circuitsDir, "src", "circuit_updateTree.template.circom"),
    wasmPath: path.join(circuitsDir, "build", "circuit_updateTree_js", "circuit_updateTree.wasm"),
    r1csPath: path.join(circuitsDir, "build", "circuit_updateTree.r1cs"),
    zkeyPath: path.join(crsDir, "circuit_final.zkey"),
    verificationKeyPath: path.join(crsDir, "verification_key.json"),
    metadataPath: path.join(crsDir, "metadata.json"),
    provenancePath: path.join(crsDir, "zkey_provenance.json"),
    inputPath: path.join(latestRunDir, "input.json"),
    witnessPath: path.join(latestRunDir, "witness.wtns"),
    proofPath: path.join(latestRunDir, "proof.json"),
    publicPath: path.join(latestRunDir, "public.json"),
    manifestPath: path.join(rootDir, "install-manifest.json"),
  };
}
