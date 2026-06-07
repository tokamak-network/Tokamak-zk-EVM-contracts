#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  PRIVATE_STATE_CLI_COMMANDS,
} from "../lib/private-state-cli-command-registry.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const cliRoot = path.resolve(__dirname, "..");
const cliPath = path.join(cliRoot, "private-state-bridge-cli.mjs");
const agentsPath = path.join(cliRoot, "agents.md");

function expect(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function runCli(args, options = {}) {
  const stdout = execFileSync(process.execPath, [cliPath, ...args], {
    cwd: options.cwd ?? cliRoot,
    env: {
      ...process.env,
      HOME: options.home ?? fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-home-")),
      ...(options.env ?? {}),
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  return stdout;
}

function runCliExpectFailure(args, options = {}) {
  try {
    runCli(args, options);
  } catch (error) {
    return {
      stdout: String(error.stdout ?? ""),
      stderr: String(error.stderr ?? ""),
      status: error.status,
    };
  }
  throw new Error(`Expected CLI failure: ${args.join(" ")}`);
}

function parseJson(stdout) {
  return JSON.parse(stdout);
}

function readAgentRefs() {
  const content = fs.readFileSync(agentsPath, "utf8");
  return new Set(
    [...content.matchAll(/^### ([A-Z]\.\d+) /gmu)]
      .map((match) => match[1]),
  );
}

function assertAgentGuidance(payload, expectedRefs) {
  expect(payload.agentGuidance?.source === "agents.md", "agentGuidance.source must point to agents.md.");
  expect(typeof payload.agentGuidance.step === "string", "agentGuidance.step must be present.");
  expect(Array.isArray(payload.agentGuidance.refs), "agentGuidance.refs must be an array.");
  for (const ref of expectedRefs) {
    expect(payload.agentGuidance.refs.includes(ref), `Missing expected guide ref ${ref}.`);
  }
  expect(!Object.hasOwn(payload, "why"), "JSON guide output must not include human guidance prose in why.");
  expect(!Object.hasOwn(payload, "privacyTip"), "JSON guide output must not include human privacy prose.");
  expect(!Object.hasOwn(payload, "mirrorTip"), "JSON guide output must not include human mirror prose.");
}

function testGuideJsonRefs() {
  const refs = readAgentRefs();
  const noNetwork = parseJson(runCli(["help", "guide", "--json"]));
  assertAgentGuidance(noNetwork, ["A.1", "D.1"]);

  const missingRpc = parseJson(runCli(["help", "guide", "--network", "mainnet", "--json"]));
  assertAgentGuidance(missingRpc, ["C.1", "C.2", "C.3", "C.4", "D.3"]);
  expect(
    missingRpc.nextSafeAction === "set rpc --network mainnet --rpc-url <URL> --provider ankr",
    "Missing-RPC guide should recommend Ankr explicitly without implying a default RPC.",
  );

  for (const payload of [noNetwork, missingRpc]) {
    for (const ref of payload.agentGuidance.refs) {
      expect(refs.has(ref), `Guide output references missing agents.md index ${ref}.`);
    }
  }
}

function testGuideHumanOutputIsUserFacing() {
  const stdout = runCli(["help", "guide", "--network", "mainnet"]);
  expect(stdout.includes("Next Step"), "Human guide output should include a Next Step section.");
  expect(stdout.includes("Command\nset rpc --network mainnet --rpc-url <URL> --provider ankr"), "Human guide output should show the next command.");
  expect(stdout.includes("create an Ankr endpoint"), "Human guide output should explain the concrete RPC setup action.");
  expect(!stdout.includes("Agent Guidance"), "Human guide output must not show AI-only guidance refs.");
  expect(!stdout.includes("Refs:"), "Human guide output must not show agents.md refs.");
  expect(!stdout.includes("Privacy Tip"), "Human guide output must not show unrelated global privacy tips.");
  expect(!stdout.includes("Mirror Tip"), "Human guide output must not show unrelated mirror tips.");
}

function testSecretCommandsRegistered() {
  const commandIds = new Set(PRIVATE_STATE_CLI_COMMANDS.map((command) => command.id));
  expect(commandIds.has("secret-create-private-key-source"), "Missing private-key source helper registry entry.");
  expect(commandIds.has("secret-create-wallet-secret-source"), "Missing wallet-secret source helper registry entry.");
}

function testRandomWalletSecretHelper() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-secret-"));
  const outputPath = path.join(tempRoot, "wallet-secret.txt");
  const stdout = runCli([
    "secret",
    "create-wallet-secret-source",
    "--output",
    outputPath,
    "--random",
    "--json",
  ], {
    cwd: tempRoot,
    home: path.join(tempRoot, "home"),
  });
  const payload = parseJson(stdout);
  const secret = fs.readFileSync(outputPath, "utf8").trim();

  expect(payload.action === "secret create-wallet-secret-source", "Unexpected wallet secret helper action.");
  expect(payload.secretPrinted === false, "Wallet secret helper must report that it did not print the secret.");
  expect(payload.outputPath === outputPath, "Wallet secret helper should report the output path.");
  expect(secret.length === 64, "Random wallet secret should be 32 random bytes encoded as hex.");
  expect(!stdout.includes(secret), "Wallet secret helper stdout must not include the secret.");

  if (process.platform !== "win32") {
    const mode = fs.statSync(outputPath).mode & 0o777;
    expect((mode & 0o077) === 0, `Wallet secret source should not be group/world-readable: ${mode.toString(8)}.`);
  }

  const overwrite = runCliExpectFailure([
    "secret",
    "create-wallet-secret-source",
    "--output",
    outputPath,
    "--random",
    "--json",
  ], {
    cwd: tempRoot,
    home: path.join(tempRoot, "home"),
  });
  const errorPayload = parseJson(overwrite.stdout);
  expect(errorPayload.ok === false, "Overwrite attempt should fail.");
  expect(
    String(errorPayload.error?.message ?? "").includes("already exists"),
    "Overwrite failure should explain that the output already exists.",
  );
  expect(!overwrite.stdout.includes(secret), "Overwrite failure must not leak the existing secret.");
}

function testNonTtyPrivateKeyPromptFailsClearly() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-private-key-"));
  const outputPath = path.join(tempRoot, "ethereum-private-key.txt");
  const failure = runCliExpectFailure([
    "secret",
    "create-private-key-source",
    "--output",
    outputPath,
    "--json",
  ], {
    cwd: tempRoot,
    home: path.join(tempRoot, "home"),
  });
  const payload = parseJson(failure.stdout);
  expect(payload.ok === false, "Non-TTY private-key helper run should fail.");
  expect(
    String(payload.error?.message ?? "").includes("interactive terminal"),
    "Non-TTY private-key helper failure should explain the terminal requirement.",
  );
  expect(!fs.existsSync(outputPath), "Failed private-key helper run must not create an output file.");
}

testSecretCommandsRegistered();
testGuideJsonRefs();
testGuideHumanOutputIsUserFacing();
testRandomWalletSecretHelper();
testNonTtyPrivateKeyPromptFailsClearly();

console.log("private-state CLI agent guidance tests passed.");
