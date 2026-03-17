#!/usr/bin/env node

import fs from "fs";
import path from "path";
import process from "process";
import { execFileSync } from "child_process";
import { fileURLToPath } from "url";
import { deriveRpcUrl, resolveCliNetwork } from "../../script/network-config.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../..");
const appsRoot = path.resolve(projectRoot, "apps");
const deployRoot = path.resolve(projectRoot, "apps/private-state/deploy");
const functionsRoot = path.resolve(__dirname, "functions");
const defaultEnvFile = path.resolve(appsRoot, ".env");

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help || !args.command) {
    printHelp();
    return;
  }

  if (args.command === "list") {
    printJson(readJson(path.resolve(functionsRoot, "index.json")));
    return;
  }

  if (args.command === "show-template") {
    requireFunctionName(args);
    printJson(loadTemplate(args.functionName));
    return;
  }

  const env = loadEnv(args.envFile ?? defaultEnvFile);
  const networkName = args.network ?? env.APPS_NETWORK;

  if (!networkName) {
    throw new Error("Missing --network and APPS_NETWORK.");
  }

  const network = resolveCliNetwork(networkName);
  const manifest = readJson(path.resolve(deployRoot, `deployment.${network.chainId}.latest.json`));
  const payload = buildPayload(args.functionName, args);
  const abi = readJson(path.resolve(deployRoot, payload.abiFile.replace("../deploy/", "")));
  const fragment = findFunctionFragment(abi, payload.method);
  const contractAddress = manifest.contracts?.[payload.contractKey];

  if (!contractAddress) {
    throw new Error(`Missing deployed contract address for key ${payload.contractKey}.`);
  }

  const formattedArgs = formatArguments(fragment.inputs ?? [], payload.args ?? []);
  const inputSignature = buildInputSignature(fragment);
  const callSignature = buildCallSignature(fragment);

  switch (args.command) {
    case "generate":
      printJson(handleGenerate({
        contractAddress,
        payload,
        inputSignature,
        formattedArgs
      }));
      return;
    case "call":
      return printJson(handleCall({
        contractAddress,
        payload,
        rpcUrl: deriveRpcUrl({
          networkName,
          alchemyApiKey: args.alchemyApiKey ?? env.APPS_ALCHEMY_API_KEY,
          rpcUrlOverride: args.rpcUrl ?? env.APPS_RPC_URL_OVERRIDE
        }),
        callSignature,
        formattedArgs
      }));
    case "send":
      return printJson(handleSend({
        contractAddress,
        payload,
        rpcUrl: deriveRpcUrl({
          networkName,
          alchemyApiKey: args.alchemyApiKey ?? env.APPS_ALCHEMY_API_KEY,
          rpcUrlOverride: args.rpcUrl ?? env.APPS_RPC_URL_OVERRIDE
        }),
        inputSignature,
        formattedArgs,
        privateKey: args.privateKey ?? env.APPS_DEPLOYER_PRIVATE_KEY
      }));
    default:
      throw new Error(`Unsupported command: ${args.command}`);
  }
}

function parseArgs(argv) {
  const parsed = { positional: [] };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (token === "--help" || token === "-h") {
      parsed.help = true;
      continue;
    }

    if (token.startsWith("--")) {
      const [key, inlineValue] = token.slice(2).split("=", 2);
      const value = inlineValue ?? argv[++index];
      parsed[toCamelCase(key)] = value;
      continue;
    }

    parsed.positional.push(token);
  }

  [parsed.command, parsed.functionName] = parsed.positional;
  return parsed;
}

function toCamelCase(value) {
  return value.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
}

function printHelp() {
  console.log(`private-state CLI

Usage:
  node apps/private-state/cli/private-state-cli.mjs list
  node apps/private-state/cli/private-state-cli.mjs show-template <function-name>
  node apps/private-state/cli/private-state-cli.mjs generate <function-name> [--network <name>] [--args-file <path>] [--template-file <path>]
  node apps/private-state/cli/private-state-cli.mjs call <function-name> [--network <name>] [--args-file <path>] [--template-file <path>]
  node apps/private-state/cli/private-state-cli.mjs send <function-name> [--network <name>] [--private-key <hex>] [--args-file <path>] [--template-file <path>]

Flags:
  --network <name>         Override APPS_NETWORK from apps/.env. Allowed: mainnet, sepolia, anvil
  --rpc-url <url>          Explicit RPC endpoint override
  --alchemy-api-key <key>  Explicit Alchemy key override
  --env-file <path>        Alternate apps/.env location
  --private-key <hex>      Signer private key for send
  --args-file <path>       JSON file whose value replaces template.args
  --template-file <path>   Full JSON template override

The CLI always loads function templates from:
  apps/private-state/cli/functions/<function-name>/calldata.json

and deployment addresses from:
  apps/private-state/deploy/deployment.<chain-id>.latest.json`);
}

function handleGenerate({ contractAddress, payload, inputSignature, formattedArgs }) {
  const calldata = runCast(["calldata", inputSignature, ...formattedArgs]).trim();

  return {
    action: "generate",
    contractKey: payload.contractKey,
    method: payload.method,
    to: contractAddress,
    signature: inputSignature,
    args: formattedArgs,
    value: payload.value ?? "0x0",
    calldata
  };
}

function handleCall({ contractAddress, payload, rpcUrl, callSignature, formattedArgs }) {
  const callArgs = [
    "call",
    contractAddress,
    callSignature,
    ...formattedArgs,
    "--rpc-url",
    rpcUrl,
    "--json"
  ];

  if (payload.value && payload.value !== "0x0" && payload.value !== "0") {
    callArgs.push("--value", payload.value);
  }

  const rawResult = runCast(callArgs).trim();

  return {
    action: "call",
    contractKey: payload.contractKey,
    method: payload.method,
    to: contractAddress,
    signature: callSignature,
    args: formattedArgs,
    rpcUrl,
    result: parseMaybeJson(rawResult)
  };
}

function handleSend({ contractAddress, payload, rpcUrl, inputSignature, formattedArgs, privateKey }) {
  if (!privateKey) {
    throw new Error("Missing --private-key and APPS_DEPLOYER_PRIVATE_KEY.");
  }

  const sendArgs = [
    "send",
    contractAddress,
    inputSignature,
    ...formattedArgs,
    "--rpc-url",
    rpcUrl,
    "--private-key",
    normalizePrivateKey(privateKey),
    "--json"
  ];

  if (payload.value && payload.value !== "0x0" && payload.value !== "0") {
    sendArgs.push("--value", payload.value);
  }

  const output = runCast(sendArgs).trim();

  return {
    action: "send",
    contractKey: payload.contractKey,
    method: payload.method,
    to: contractAddress,
    signature: inputSignature,
    args: formattedArgs,
    value: payload.value ?? "0x0",
    rpcUrl,
    result: parseMaybeJson(output)
  };
}

function buildPayload(functionName, args) {
  requireFunctionName(args);

  const template = args.templateFile
    ? readJson(resolveInputPath(args.templateFile))
    : loadTemplate(functionName);

  if (args.argsFile) {
    template.args = readJson(resolveInputPath(args.argsFile));
  }

  return template;
}

function loadTemplate(functionName) {
  return readJson(path.resolve(functionsRoot, functionName, "calldata.json"));
}

function findFunctionFragment(abi, methodName) {
  const fragment = abi.find((entry) => entry.type === "function" && entry.name === methodName);

  if (!fragment) {
    throw new Error(`Method ${methodName} was not found in the callable ABI.`);
  }

  return fragment;
}

function buildInputSignature(fragment) {
  const inputTypes = (fragment.inputs ?? []).map(formatCanonicalType).join(",");
  return `${fragment.name}(${inputTypes})`;
}

function buildCallSignature(fragment) {
  const inputSignature = buildInputSignature(fragment);
  const outputTypes = (fragment.outputs ?? []).map(formatCanonicalType).join(",");
  return `${inputSignature}(${outputTypes})`;
}

function formatCanonicalType(parameter) {
  const type = parameter.type;

  if (!type.startsWith("tuple")) {
    return type;
  }

  const suffix = type.slice("tuple".length);
  const componentTypes = (parameter.components ?? []).map(formatCanonicalType).join(",");
  return `(${componentTypes})${suffix}`;
}

function formatArguments(inputs, values) {
  if (inputs.length !== values.length) {
    throw new Error(`Expected ${inputs.length} arguments but received ${values.length}.`);
  }

  return inputs.map((input, index) => formatArgument(input, values[index]));
}

function formatArgument(parameter, value) {
  const { baseType, arraySuffix } = splitType(parameter.type);

  if (arraySuffix.length > 0) {
    if (!Array.isArray(value)) {
      throw new Error(`Expected array for ${parameter.name || parameter.type}.`);
    }

    const nestedParameter = {
      ...parameter,
      type: `${baseType}${arraySuffix.slice(1).join("")}`
    };
    return `[${value.map((item) => formatArgument(nestedParameter, item)).join(",")}]`;
  }

  if (baseType === "tuple") {
    if (Array.isArray(value)) {
      return `(${value.map((item, index) => formatArgument(parameter.components[index], item)).join(",")})`;
    }

    if (!value || typeof value !== "object") {
      throw new Error(`Expected object or array for tuple ${parameter.name || parameter.type}.`);
    }

    return `(${(parameter.components ?? [])
      .map((component, index) => {
        const componentValue = value[component.name] ?? value[index];
        return formatArgument(component, componentValue);
      })
      .join(",")})`;
  }

  return formatScalar(baseType, value);
}

function splitType(type) {
  const parts = type.match(/\[[^\]]*\]/g) ?? [];
  const baseType = type.replace(/\[[^\]]*\]/g, "");
  return {
    baseType,
    arraySuffix: parts
  };
}

function formatScalar(type, value) {
  if (value === null || value === undefined) {
    throw new Error(`Missing value for ${type}.`);
  }

  if (type === "bool") {
    return value ? "true" : "false";
  }

  if (type === "string") {
    return String(value);
  }

  return String(value);
}

function runCast(args) {
  return execFileSync("cast", args, {
    cwd: projectRoot,
    encoding: "utf8"
  });
}

function parseMaybeJson(value) {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function requireFunctionName(args) {
  if (!args.functionName) {
    throw new Error("Missing function name.");
  }
}

function loadEnv(envFile) {
  if (!fs.existsSync(envFile)) {
    return {};
  }

  const env = {};
  const lines = fs.readFileSync(envFile, "utf8").split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();

    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const separator = trimmed.indexOf("=");

    if (separator === -1) {
      continue;
    }

    const key = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim();
    env[key] = stripQuotes(value);
  }

  return env;
}

function stripQuotes(value) {
  if (
    (value.startsWith("\"") && value.endsWith("\"")) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }

  return value;
}

function resolveInputPath(inputPath) {
  return path.isAbsolute(inputPath) ? inputPath : path.resolve(projectRoot, inputPath);
}

function normalizePrivateKey(value) {
  return value.startsWith("0x") ? value : `0x${value}`;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function printJson(value) {
  console.log(JSON.stringify(value, null, 2));
}

main().catch((error) => {
  console.error(error.message ?? String(error));
  process.exitCode = 1;
});
