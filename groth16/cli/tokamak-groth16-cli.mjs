#!/usr/bin/env node

import {
  doctorGroth16Runtime,
  extractLatestProof,
  installGroth16Runtime,
  proveUpdateTree,
  uninstallGroth16Runtime,
  verifyUpdateTreeProof,
} from "../lib/proof-runtime.mjs";
import { resolveGroth16WorkspaceRoot } from "../lib/paths.mjs";

function usage() {
  console.log(`Commands:
  --install [--trusted-setup] [--no-setup] [--docker]
      Prepare the local Groth16 runtime under ~/tokamak-private-channels/groth16
      By default CRS artifacts are installed from the public Groth16 MPC archive
      Use --trusted-setup to install packaged trusted setup artifacts instead
      Use --no-setup to skip CRS provisioning while still rendering and compiling the circuit
      --docker is accepted for command parity but the Groth16 runtime uses packaged native Circom binaries

  --uninstall
      Remove the local Groth16 runtime workspace

  --prove <INPUT_JSON> [--output <DIR>]
      Generate witness, proof, and public signals from an updateTree input JSON, then verify the proof

  --verify [<PROOF_ZIP|DIR>]
      Verify proof.json and public.json against the installed verification key

  --extract-proof <OUTPUT_ZIP_PATH>
      Collect the latest proof artifacts and zip them to the given path

  --doctor
      Check package and runtime health

  --help
      Show this help

Options:
  --workspace <DIR>  Override the Groth16 runtime workspace root
  --verbose          Show detailed JSON output
`);
}

function parseArgs(argv) {
  const parsed = {
    command: null,
    positional: [],
    workspaceRoot: null,
    trustedSetup: false,
    noSetup: false,
    docker: false,
    output: null,
    verbose: false,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    const next = argv[index + 1];
    const take = (name) => {
      if (!next || next.startsWith("--")) {
        throw new Error(`Missing value for ${name}.`);
      }
      index += 1;
      return next;
    };

    switch (current) {
      case "--install":
      case "--uninstall":
      case "--prove":
      case "--verify":
      case "--extract-proof":
      case "--doctor":
        if (parsed.command) {
          throw new Error(`Only one command can be used at a time: ${parsed.command}, ${current}`);
        }
        parsed.command = current;
        break;
      case "--trusted-setup":
        parsed.trustedSetup = true;
        break;
      case "--no-setup":
        parsed.noSetup = true;
        break;
      case "--docker":
        parsed.docker = true;
        break;
      case "--workspace":
        parsed.workspaceRoot = take(current);
        break;
      case "--output":
        parsed.output = take(current);
        break;
      case "--verbose":
        parsed.verbose = true;
        break;
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      default:
        if (current.startsWith("--")) {
          throw new Error(`Unknown option: ${current}`);
        }
        parsed.positional.push(current);
        break;
    }
  }

  return parsed;
}

async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help || !args.command) {
    usage();
    return;
  }

  const workspaceRoot = resolveGroth16WorkspaceRoot(args.workspaceRoot ?? undefined);

  switch (args.command) {
    case "--install":
      assertNoPositionals(args);
      if (args.trustedSetup && args.noSetup) {
        throw new Error("--trusted-setup and --no-setup cannot be used together.");
      }
      printResult(await installGroth16Runtime({
        workspaceRoot,
        trustedSetup: args.trustedSetup,
        noSetup: args.noSetup,
        docker: args.docker,
      }), args);
      return;
    case "--uninstall":
      assertNoPositionals(args);
      printResult(uninstallGroth16Runtime({ workspaceRoot }), args);
      return;
    case "--prove":
      assertPositionals(args, 1, "--prove requires <INPUT_JSON>.");
      printResult(await proveUpdateTree({
        workspaceRoot,
        inputPath: args.positional[0],
        outputDir: args.output,
      }), args);
      return;
    case "--verify":
      assertMaxPositionals(args, 1, "--verify accepts at most one proof directory or zip.");
      printResult(await verifyUpdateTreeProof({
        workspaceRoot,
        inputPath: args.positional[0] ?? null,
      }), args);
      return;
    case "--extract-proof":
      assertPositionals(args, 1, "--extract-proof requires <OUTPUT_ZIP_PATH>.");
      printResult(await extractLatestProof({
        workspaceRoot,
        outputPath: args.positional[0],
      }), args);
      return;
    case "--doctor":
      assertNoPositionals(args);
      printResult(doctorGroth16Runtime({ workspaceRoot }), { ...args, verbose: true });
      return;
    default:
      throw new Error(`Unsupported command: ${args.command}`);
  }
}

function assertNoPositionals(args) {
  assertPositionals(args, 0, `${args.command} does not accept positional arguments.`);
}

function assertPositionals(args, expected, message) {
  if (args.positional.length !== expected) {
    throw new Error(message);
  }
}

function assertMaxPositionals(args, max, message) {
  if (args.positional.length > max) {
    throw new Error(message);
  }
}

function printResult(result, args) {
  if (args.verbose) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  switch (args.command) {
    case "--install":
      console.log(`Installed Groth16 runtime: ${result.workspaceRoot}`);
      console.log(`CRS source: ${result.crsSource}`);
      console.log(`WASM: ${result.circuit.wasmPath}`);
      break;
    case "--uninstall":
      console.log(`${result.existed ? "Removed" : "No existing"} Groth16 runtime: ${result.workspaceRoot}`);
      break;
    case "--prove":
      console.log(`Proof: ${result.proofPath}`);
      console.log(`Public signals: ${result.publicPath}`);
      break;
    case "--verify":
      console.log(`Verified proof: ${result.proofPath}`);
      break;
    case "--extract-proof":
      console.log(`Proof archive: ${result.outputPath}`);
      break;
    default:
      console.log(JSON.stringify(result, null, 2));
      break;
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
