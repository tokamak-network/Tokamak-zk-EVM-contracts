#!/usr/bin/env node

import {
  doctorGroth16Runtime,
  extractLatestProof,
  installGroth16Runtime,
  proveUpdateTree,
  uninstallGroth16Runtime,
  verifyUpdateTreeProof,
} from "../lib/proof-runtime.mjs";

function usage() {
  console.log(`Commands:
  --install [--trusted-setup] [--no-setup] [--docker]
      Prepare the local Groth16 runtime under ~/tokamak-private-channels/groth16
      By default CRS artifacts are installed from the public Groth16 MPC archive
      Use --trusted-setup to generate a local trusted setup in the workspace instead
      Use --no-setup to skip CRS provisioning while still rendering and compiling the circuit
      Use --docker on Linux or Windows with Docker Desktop to install and run Groth16 commands through an Ubuntu 22 container

  --uninstall
      Remove the local Groth16 runtime workspace

  --prove <INPUT_JSON>
      Generate witness, proof, and public signals from an updateTree input JSON

  --verify [<PROOF_ZIP|DIR>]
      Verify proof.json and public.json against the installed verification key

  --extract-proof <OUTPUT_ZIP_PATH>
      Export the fixed workspace proof artifacts to the given zip path

  --doctor
      Check package and runtime health

  --help
      Show this help

Options:
  --verbose          Show detailed JSON output
`);
}

function parseArgs(argv) {
  const parsed = {
    command: null,
    positional: [],
    trustedSetup: false,
    noSetup: false,
    docker: false,
    verbose: false,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];

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

  switch (args.command) {
    case "--install":
      assertNoPositionals(args);
      if (args.trustedSetup && args.noSetup) {
        throw new Error("--trusted-setup and --no-setup cannot be used together.");
      }
      printResult(await installGroth16Runtime({
        trustedSetup: args.trustedSetup,
        noSetup: args.noSetup,
        docker: args.docker,
        verbose: args.verbose,
      }), args);
      return;
    case "--uninstall":
      assertNoPositionals(args);
      printResult(uninstallGroth16Runtime(), args);
      return;
    case "--prove":
      assertPositionals(args, 1, "--prove requires <INPUT_JSON>.");
      printResult(await proveUpdateTree({
        inputPath: args.positional[0],
      }), args);
      return;
    case "--verify":
      assertMaxPositionals(args, 1, "--verify accepts at most one proof directory or zip.");
      printResult(await verifyUpdateTreeProof({
        inputPath: args.positional[0] ?? null,
      }), args);
      return;
    case "--extract-proof":
      assertPositionals(args, 1, "--extract-proof requires <OUTPUT_ZIP_PATH>.");
      printResult(await extractLatestProof({
        outputPath: args.positional[0],
      }), args);
      return;
    case "--doctor":
      assertNoPositionals(args);
      printResult(doctorGroth16Runtime(), { ...args, verbose: true });
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
