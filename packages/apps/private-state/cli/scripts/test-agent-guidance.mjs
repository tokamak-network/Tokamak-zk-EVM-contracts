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
const TEST_RPC_CONFIG = Object.freeze({
  provider: "ankr",
  rpcUrl: "https://example.invalid",
  logRequestsPerSecond: 27,
  blockRangeCap: 3000,
});

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

function createIsolatedHomeWithRpc(networkName = "mainnet") {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-home-"));
  const networkDir = path.join(home, "tokamak-private-channels", "workspace", networkName);
  fs.mkdirSync(networkDir, { recursive: true });
  fs.writeFileSync(
    path.join(networkDir, "rpc-config.env"),
    [
      `LOG_CHUNK_SIZE=${TEST_RPC_CONFIG.blockRangeCap}`,
      `LOG_REQUESTS_PER_SECOND=${TEST_RPC_CONFIG.logRequestsPerSecond}`,
      `RPC_BLOCK_RANGE_CAP=${TEST_RPC_CONFIG.blockRangeCap}`,
      `RPC_PROVIDER=${TEST_RPC_CONFIG.provider}`,
      `RPC_URL=${TEST_RPC_CONFIG.rpcUrl}`,
      "",
    ].join("\n"),
    "utf8",
  );
  return home;
}

function createIsolatedHomeWithRpcAndReadOnlyArtifacts(networkName = "mainnet", chainId = 1) {
  const home = createIsolatedHomeWithRpc(networkName);
  const artifactDir = path.join(
    home,
    "tokamak-private-channels",
    "dapps",
    "private-state",
    `chain-id-${chainId}`,
  );
  fs.mkdirSync(artifactDir, { recursive: true });
  for (const fileName of [
    `bridge.${chainId}.json`,
    `bridge-abi-manifest.${chainId}.json`,
    `deployment.${chainId}.latest.json`,
    `storage-layout.${chainId}.latest.json`,
  ]) {
    fs.writeFileSync(path.join(artifactDir, fileName), "{}\n", "utf8");
  }
  return home;
}

function assertAgentGuidance(payload, expectedRefs) {
  expect(payload.agentGuidance?.source === "agents.md", "agentGuidance.source must point to agents.md.");
  expect(typeof payload.agentGuidance.step === "string", "agentGuidance.step must be present.");
  expect(Array.isArray(payload.agentGuidance.refs), "agentGuidance.refs must be an array.");
  expect(
    payload.agentGuidance.termsSource === "docs/dapps/private-state/terms.md",
    "agentGuidance.termsSource must point to the Terms document.",
  );
  expect(Array.isArray(payload.agentGuidance.termsRefs), "agentGuidance.termsRefs must be an array.");
  expect(payload.agentGuidance.termsRefs.includes("1"), "agentGuidance.termsRefs must include Terms definitions.");
  expect(payload.agentGuidance.termsRefs.includes("6"), "agentGuidance.termsRefs must include Self-Custody terms.");
  expect(payload.agentGuidance.termsRefs.includes("16"), "agentGuidance.termsRefs must include liability terms.");
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

function testGuideJsonDeploymentArtifactsMissing() {
  const refs = readAgentRefs();
  const payload = parseJson(runCli(["help", "guide", "--network", "mainnet", "--json"], {
    home: createIsolatedHomeWithRpc("mainnet"),
  }));

  assertAgentGuidance(payload, ["D.2"]);
  expect(payload.agentGuidance.step === "install-runtime", "Missing artifacts should select the install-runtime step.");
  expect(payload.nextSafeAction === "install", "Missing artifacts should guide to install.");
  expect(payload.state.network.rpcConfigured === true, "RPC fixture should let the guide advance past missing RPC.");
  expect(payload.state.deploymentArtifacts.installed === false, "Deployment artifacts should be missing in the fixture.");
  for (const ref of payload.agentGuidance.refs) {
    expect(refs.has(ref), `Guide output references missing agents.md index ${ref}.`);
  }
}

function testGuideJsonAccountSecretMissing() {
  const refs = readAgentRefs();
  const payload = parseJson(runCli([
    "help",
    "guide",
    "--network",
    "mainnet",
    "--account",
    "alice",
    "--json",
  ], {
    home: createIsolatedHomeWithRpcAndReadOnlyArtifacts("mainnet", 1),
  }));

  assertAgentGuidance(payload, ["B.1", "B.2", "B.3", "D.4", "I.1"]);
  expect(
    payload.agentGuidance.step === "create-private-key-source-and-import-account",
    "Missing account secret should select the private-key source and account import step.",
  );
  expect(
    payload.nextSafeAction === "secret create-private-key-source --output ./ethereum-private-key.txt",
    "Missing account secret should guide to the private-key source helper.",
  );
  expect(payload.state.network.rpcConfigured === true, "RPC fixture should let the guide advance past missing RPC.");
  expect(payload.state.deploymentArtifacts.installed === true, "Artifact fixture should let the guide advance past install.");
  expect(payload.state.account.exists === false, "Account secret should be missing in the fixture.");
  for (const ref of payload.agentGuidance.refs) {
    expect(refs.has(ref), `Guide output references missing agents.md index ${ref}.`);
  }
}

function testGuideJsonWalletMissingBeforeChannelJoin() {
  const refs = readAgentRefs();
  const walletName = "test-0x0000000000000000000000000000000000000001";
  const payload = parseJson(runCli([
    "help",
    "guide",
    "--network",
    "mainnet",
    "--wallet",
    walletName,
    "--json",
  ], {
    home: createIsolatedHomeWithRpcAndReadOnlyArtifacts("mainnet", 1),
  }));

  assertAgentGuidance(payload, ["B.4", "B.5", "B.6", "B.7", "D.5", "D.8", "E.1", "E.2"]);
  expect(
    payload.agentGuidance.step === "create-wallet-secret-source-and-join-channel",
    "Missing wallet should select the wallet-secret source and channel join step.",
  );
  expect(
    payload.nextSafeAction === "secret create-wallet-secret-source --output ./wallet-secret.txt",
    "Missing wallet should guide to the wallet-secret source helper.",
  );
  expect(payload.state.network.rpcConfigured === true, "RPC fixture should let the guide advance past missing RPC.");
  expect(payload.state.deploymentArtifacts.installed === true, "Artifact fixture should let the guide advance past install.");
  expect(payload.state.wallet.exists === false, "Wallet should be missing in the fixture.");
  for (const ref of payload.agentGuidance.refs) {
    expect(refs.has(ref), `Guide output references missing agents.md index ${ref}.`);
  }
}

function testGuideHumanOutputIsUserFacing() {
  const stdout = runCli(["help", "guide", "--network", "mainnet"]);
  expect(stdout.includes("Current status"), "Human guide output should include a Current status section.");
  expect(stdout.includes("Next step"), "Human guide output should include a Next step section.");
  expect(stdout.includes("Run this command\nprivate-state-cli set rpc --network mainnet --rpc-url <URL> --provider ankr"), "Human guide output should show one prefixed next command.");
  expect(stdout.includes("After it succeeds\nRerun: private-state-cli help guide --network mainnet"), "Human guide output should show the follow-up action.");
  expect(stdout.includes("Ethereum mainnet connection URL"), "Human guide output should describe RPC as an Ethereum connection URL.");
  expect(stdout.includes("Ankr is recommended"), "Human guide output should present Ankr as a recommendation.");
  expect(stdout.includes("free plan is fast when this CLI checks past Ethereum records"), "Human guide output should explain why Ankr is recommended.");
  expect(stdout.includes("Ankr is not a default"), "Human guide output should not imply Ankr is a default provider.");
  expect(!stdout.includes("RPC endpoint"), "Human guide output should avoid specialist RPC endpoint wording.");
  expect(!stdout.includes("recovery and log scanning"), "Human guide output should avoid specialist recovery/log scanning wording.");
  expect(!stdout.includes("Checks"), "Human guide output must not lead with diagnostic checks.");
  expect(!stdout.includes("Candidate Commands"), "Human guide output must not show raw candidate command lists.");
  expect(!stdout.includes("Use --json only when an AI"), "Human guide output must not include AI/script-only JSON guidance.");
  expect(!stdout.includes("Agent Guidance"), "Human guide output must not show AI-only guidance refs.");
  expect(!stdout.includes("Refs:"), "Human guide output must not show agents.md refs.");
  expect(!stdout.includes("termsRefs"), "Human guide output must not show Terms refs.");
  expect(!stdout.includes("Privacy Tip"), "Human guide output must not show unrelated global privacy tips.");
  expect(!stdout.includes("Mirror Tip"), "Human guide output must not show unrelated mirror tips.");
  expect(!/\bchat\b/iu.test(stdout), "Human guide output should not use chat-oriented wording.");
}

function testHelpCommandsOutputUsesFinalPromptPolicy() {
  const stdout = runCli(["help", "commands"]);
  expect(!stdout.includes("--acknowledge-action-impact"), "Command help must not expose the deprecated action-impact flag.");
  expect(!stdout.includes("Action impact:"), "Command help must use warning-summary wording.");
  expect(stdout.includes("Warning summary:"), "Command help should describe transaction warnings as warning summaries.");
  expect(stdout.includes("uninstall [--include-wallet-keys]"), "Command help should expose the uninstall wallet-key deletion option.");
  expect(stdout.includes("Default uninstall preserves wallet spending-key and viewing-key files"), "Command help should explain default uninstall wallet-key preservation.");
}

function testGuideHumanPrivateKeyFlowIncludesAddressVerification() {
  const stdout = runCli([
    "help",
    "guide",
    "--network",
    "mainnet",
    "--account",
    "alice",
  ], {
    home: createIsolatedHomeWithRpcAndReadOnlyArtifacts("mainnet", 1),
  });

  expect(
    stdout.includes("Run this command\nprivate-state-cli secret create-private-key-source --output ./ethereum-private-key.txt"),
    "Human private-key flow should start with the local source helper.",
  );
  expect(
    stdout.includes("Then import the key into a local account alias:\nprivate-state-cli account import --account alice --network mainnet --private-key-file ./ethereum-private-key.txt"),
    "Human private-key flow should show the account import follow-up command.",
  );
  expect(
    stdout.includes("Then confirm the imported Ethereum address:\nprivate-state-cli account get-l1-address --account alice --network mainnet"),
    "Human private-key flow should show the address verification follow-up command.",
  );
}

function testGuideHumanWalletSecretFlowExplainsMasking() {
  const walletName = "test-0x0000000000000000000000000000000000000001";
  const stdout = runCli([
    "help",
    "guide",
    "--network",
    "mainnet",
    "--wallet",
    walletName,
  ], {
    home: createIsolatedHomeWithRpcAndReadOnlyArtifacts("mainnet", 1),
  });

  expect(
    stdout.includes("Run this command\nprivate-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt"),
    "Human wallet-secret flow should start with the local source helper.",
  );
  expect(
    stdout.includes("Your typing will appear as * characters."),
    "Human wallet-secret flow should explain masked terminal input.",
  );
  expect(
    stdout.includes("Preserve the file because it may be needed later to recover this channel wallet."),
    "Human wallet-secret flow should explain why the source file must be preserved.",
  );
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
testGuideJsonDeploymentArtifactsMissing();
testGuideJsonAccountSecretMissing();
testGuideJsonWalletMissingBeforeChannelJoin();
testGuideHumanOutputIsUserFacing();
testHelpCommandsOutputUsesFinalPromptPolicy();
testGuideHumanPrivateKeyFlowIncludesAddressVerification();
testGuideHumanWalletSecretFlowExplainsMasking();
testRandomWalletSecretHelper();
testNonTtyPrivateKeyPromptFailsClearly();

console.log("private-state CLI agent guidance tests passed.");
