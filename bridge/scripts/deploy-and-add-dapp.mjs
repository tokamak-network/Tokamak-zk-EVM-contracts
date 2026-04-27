#!/usr/bin/env node

import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { APP_NETWORKS, resolveAppNetwork } from "@tokamak-private-dapps/common-library/network-config";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const deployPrivateStateScriptPath = path.join(
  repoRoot,
  "packages",
  "apps",
  "private-state",
  "scripts",
  "deploy",
  "deploy-private-state.mjs",
);
const writePrivateStateArtifactsPath = path.join(
  repoRoot,
  "packages",
  "apps",
  "private-state",
  "scripts",
  "deploy",
  "write-deploy-artifacts.mjs",
);
const addDappScriptPath = path.join(repoRoot, "bridge", "scripts", "admin-add-dapp.mjs");

const CHAIN_ID_TO_APP_NETWORK = new Map(
  Object.entries(APP_NETWORKS).map(([network, config]) => [config.chainId, network]),
);

function usage() {
  console.log(`Usage:
  node bridge/scripts/deploy-and-add-dapp.mjs --group <example-group> [--group <example-group> ...] --dapp-id <uint> [options]

This orchestrator deploys the private-state app first and then invokes:
  node bridge/scripts/admin-add-dapp.mjs ...

Deploy-only options:
  --app-network <name>              App deployment network; defaults to APPS_NETWORK, BRIDGE_NETWORK, or the bridge chain name
  --app-env-file <path>             Environment file for app deployment; defaults to packages/apps/.env
  --app-rpc-url <url>               RPC URL override used only for app deployment

All other options are forwarded to admin-add-dapp.mjs unchanged.
`);
}

function resolveDefaultAppNetwork() {
  if (process.env.APPS_NETWORK) {
    return process.env.APPS_NETWORK;
  }
  if (process.env.BRIDGE_NETWORK) {
    return process.env.BRIDGE_NETWORK;
  }
  const rawChainId = process.env.BRIDGE_CHAIN_ID;
  if (rawChainId) {
    const chainId = Number.parseInt(rawChainId, 10);
    const network = CHAIN_ID_TO_APP_NETWORK.get(chainId);
    if (network) {
      return network;
    }
  }
  throw new Error(
    "Unable to infer an app deployment network. Pass --app-network explicitly or set APPS_NETWORK/BRIDGE_NETWORK.",
  );
}

function parseArgs(argv) {
  const forwardedArgs = [];
  const deployOptions = {
    appNetwork: null,
    appEnvFile: null,
    appRpcUrl: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    const next = argv[i + 1];

    const take = (name) => {
      if (!next || next.startsWith("--")) {
        throw new Error(`Missing value for ${name}.`);
      }
      i += 1;
      return next;
    };

    switch (current) {
      case "--app-network":
        deployOptions.appNetwork = take(current);
        forwardedArgs.push(current, deployOptions.appNetwork);
        break;
      case "--app-env-file":
        deployOptions.appEnvFile = path.resolve(process.cwd(), take(current));
        break;
      case "--app-rpc-url":
        deployOptions.appRpcUrl = take(current);
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        forwardedArgs.push(current);
        break;
    }
  }

  return { deployOptions, forwardedArgs };
}

function run(command, args, { cwd = repoRoot, env = process.env } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env,
      stdio: "inherit",
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} ${args.join(" ")} exited with code ${code ?? "unknown"}.`));
      }
    });
  });
}

async function main() {
  const { deployOptions, forwardedArgs } = parseArgs(process.argv.slice(2));
  const appNetwork = deployOptions.appNetwork ?? resolveDefaultAppNetwork();
  const appChainId = resolveAppNetwork(appNetwork).chainId;
  const deployEnv = {
    ...process.env,
    APPS_NETWORK: appNetwork,
  };

  if (deployOptions.appEnvFile) {
    deployEnv.APPS_ENV_FILE = deployOptions.appEnvFile;
  }
  if (deployOptions.appRpcUrl) {
    deployEnv.APPS_RPC_URL_OVERRIDE = deployOptions.appRpcUrl;
  }

  await run("node", [deployPrivateStateScriptPath], {
    cwd: repoRoot,
    env: deployEnv,
  });

  await run("node", [writePrivateStateArtifactsPath, String(appChainId)], {
    cwd: repoRoot,
    env: deployEnv,
  });

  await run("node", [addDappScriptPath, ...forwardedArgs], {
    cwd: repoRoot,
    env: {
      ...process.env,
      APPS_NETWORK: appNetwork,
    },
  });
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
