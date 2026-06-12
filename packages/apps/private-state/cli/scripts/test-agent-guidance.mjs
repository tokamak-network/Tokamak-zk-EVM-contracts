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
import {
  readPrivateStateTermsMetadata,
  readPrivateStateTermsText,
} from "../lib/private-state-terms.mjs";
import {
  writePrivateStateCliInstallManifest,
} from "../lib/private-state-runtime-management.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const cliRoot = path.resolve(__dirname, "..");
const cliPath = path.join(cliRoot, "private-state-bridge-cli.mjs");
const runtimePath = path.join(cliRoot, "lib", "runtime.mjs");
const e2eCliPath = path.resolve(cliRoot, "..", "scripts", "e2e", "run-bridge-private-state-cli-e2e.mjs");
const agentsPath = path.join(cliRoot, "agents.md");
const readmePath = path.join(cliRoot, "README.md");
const publicTermsPath = path.resolve(cliRoot, "../../../../docs/dapps/private-state/terms.md");
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

function testCanonicalTermsAssetMatchesPublicTerms() {
  const packagedTerms = readPrivateStateTermsText();
  const publicTerms = fs.readFileSync(publicTermsPath, "utf8");
  const metadata = readPrivateStateTermsMetadata();

  expect(packagedTerms === publicTerms, "Packaged canonical Terms must match docs/dapps/private-state/terms.md.");
  expect(metadata.termsVersion === "2026-06-11", "Unexpected canonical Terms version.");
  expect(
    /^sha256:[0-9a-f]{64}$/u.test(metadata.termsHash),
    `Unexpected canonical Terms hash format: ${metadata.termsHash}`,
  );
  expect(metadata.termsPackagePath === "assets/service-terms.md", "Unexpected packaged Terms path.");
  expect(metadata.termsPublicPath === "docs/dapps/private-state/terms.md", "Unexpected public Terms path.");
  expect(metadata.termsContentBytes === Buffer.byteLength(packagedTerms, "utf8"), "Terms byte length mismatch.");
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

function writeTermsAcceptanceForHome(home, overrides = {}) {
  const terms = readPrivateStateTermsMetadata();
  const termsAcceptance = {
    termsVersion: terms.termsVersion,
    termsHash: terms.termsHash,
    termsHashAlgorithm: terms.termsHashAlgorithm,
    acceptedAt: "2026-06-10T00:00:00.000Z",
    cliPackageVersion: "0.0.0-test",
    acceptanceSource: "interactive-test-fixture",
    acceptedByJson: false,
    ...overrides,
  };
  const acceptanceDir = path.join(home, "tokamak-private-channels", "dapps", "private-state");
  fs.mkdirSync(acceptanceDir, { recursive: true });
  fs.writeFileSync(
    path.join(acceptanceDir, "terms-acceptance.json"),
    `${JSON.stringify({ termsAcceptance }, null, 2)}\n`,
    "utf8",
  );
  return termsAcceptance;
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
  expect(payload.agentGuidance.refs.includes("E.3"), "agentGuidance.refs must include Terms and safety context.");
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

function testInstallJsonDoesNotInstallOrAcceptTerms() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-install-json-home-"));
  const payload = parseJson(runCli(["install", "--read-only", "--json"], { home }));
  const terms = readPrivateStateTermsMetadata();
  expect(payload.ok === true, "install --json should return a structured result.");
  expect(payload.action === "install", "install --json should identify the install action.");
  expect(payload.terms?.termsVersion === terms.termsVersion, "install --json should include the canonical Terms version.");
  expect(payload.terms?.termsHash === terms.termsHash, "install --json should include the canonical Terms hash.");
  expect(payload.terms?.termsHashAlgorithm === terms.termsHashAlgorithm, "install --json should include the Terms hash algorithm.");
  expect(payload.installed === false, "install --json must not install artifacts.");
  expect(payload.requiresInteractiveTermsAcceptance === true, "install --json should require interactive Terms acceptance.");
  expect(payload.terms_acceptance_flow === "browser_localhost_interactive", "install --json should describe the browser-localhost Terms acceptance flow.");
  expect(payload.termsAcceptanceCanBeProvidedByJson === false, "install --json must not accept Terms.");
  expect(
    Array.isArray(payload.terms_refs) && payload.terms_refs.includes("1") && payload.terms_refs.includes("20"),
    "install --json should describe the relevant Terms references.",
  );
  expect(
    payload.terms_acceptance_action === "accept_terms_and_continue_installation_button",
    "install --json should describe the single browser acceptance action.",
  );
  expect(payload.nextSafeAction === "private-state-cli install --read-only", "install --json should preserve the requested install mode in the interactive command.");
  expect(
    !fs.existsSync(path.join(home, "tokamak-private-channels")),
    "install --json must not create the private-state workspace.",
  );
}

function testHumanModeHasNoJsonObjectFallback() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const humanFormatterSource = runtimeSource.slice(
    runtimeSource.indexOf("function printHumanResult"),
    runtimeSource.indexOf("function humanizeLabel"),
  );
  expect(
    runtimeSource.includes("install: printInstallHumanResult"),
    "install must have a dedicated human-readable result renderer.",
  );
  expect(
    !humanFormatterSource.includes("JSON.stringify"),
    "human-readable fallback must not stringify object values as raw JSON.",
  );
}

function testBrowserTermsUsesMarkdownRendering() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  expect(
    runtimeSource.includes("function renderMarkdownDocument"),
    "browser Terms page should render packaged Terms Markdown into HTML.",
  );
  expect(
    runtimeSource.includes("<article class=\"panel terms-markdown\">"),
    "browser Terms page should display rendered Terms content in a Markdown article.",
  );
  expect(
    !runtimeSource.includes("<pre>${escapeHtml(termsText.trimEnd())}</pre>"),
    "browser Terms page must not display the Terms as raw preformatted Markdown text.",
  );
}

function testTerminalTermsFallbackRequiresInteractiveTermsAcceptance() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-install-human-home-"));
  const failure = runCliExpectFailure(["install", "--read-only", "--terminal-terms"], { home });
  expect(failure.status !== 0, "terminal Terms fallback without an interactive terminal should fail.");
  expect(
    failure.stderr.includes("Service Terms acceptance requires an interactive terminal."),
    "terminal Terms fallback should reject before installing when Terms cannot be accepted interactively.",
  );
  expect(
    !fs.existsSync(path.join(home, "tokamak-private-channels")),
    "terminal Terms fallback without Terms acceptance must not create the private-state workspace.",
  );
}

function testInstallManifestPersistsTermsAcceptance() {
  const cacheBaseRoot = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-install-manifest-"));
  const terms = readPrivateStateTermsMetadata();
  const termsAcceptance = {
    termsVersion: terms.termsVersion,
    termsHash: terms.termsHash,
    termsHashAlgorithm: terms.termsHashAlgorithm,
    acceptedAt: "2026-06-10T00:00:00.000Z",
    cliPackageVersion: "0.0.0-test",
    acceptanceSource: "interactive-install",
    acceptedByJson: false,
    acceptedCategoryIds: [
      "scope-and-eligibility",
      "public-records-and-privacy-limits",
      "self-custody-and-secrets",
      "prohibited-use-and-third-parties",
      "risks-and-liability",
      "changes-and-disputes",
    ],
  };
  const { manifestPath, manifest } = writePrivateStateCliInstallManifest({
    installMode: "read-only",
    dockerRequested: false,
    includeLocalArtifacts: false,
    localDeploymentBaseRoot: null,
    termsAcceptance,
    deploymentArtifacts: {
      cacheBaseRoot,
      installed: [],
    },
    selectedVersions: null,
    tokamakCliRuntime: null,
    groth16Runtime: null,
  });
  expect(fs.existsSync(manifestPath), "Install manifest should be written.");
  expect(
    JSON.stringify(manifest.install.termsAcceptance) === JSON.stringify(termsAcceptance),
    "Install manifest should persist the exact Terms acceptance record.",
  );
}

function testTermsGatedJsonRequiresCurrentTermsAcceptance() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-terms-json-"));
  const home = path.join(tempRoot, "home");
  const outputPath = path.join(tempRoot, "wallet-secret.txt");
  const failure = runCliExpectFailure([
    "secret",
    "create-wallet-secret-source",
    "--output",
    outputPath,
    "--random",
    "--json",
  ], {
    cwd: tempRoot,
    home,
  });
  const payload = parseJson(failure.stdout);
  expect(payload.ok === false, "Terms-gated command without acceptance should fail.");
  expect(payload.error?.code === "TERMS_ACCEPTANCE_REQUIRED", "Missing acceptance should use TERMS_ACCEPTANCE_REQUIRED.");
  expect(payload.error?.details?.terms?.termsHash === readPrivateStateTermsMetadata().termsHash, "Terms error should include current Terms metadata.");
  expect(
    payload.error?.hints?.some((hint) => String(hint).includes("without --json")),
    "Terms error should tell the agent to rerun interactively without --json.",
  );
  expect(!fs.existsSync(outputPath), "Terms-gated command without acceptance must not create secret files.");
}

function testTermsGatedJsonRejectsStaleTermsAcceptance() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-terms-stale-"));
  const home = path.join(tempRoot, "home");
  const outputPath = path.join(tempRoot, "wallet-secret.txt");
  writeTermsAcceptanceForHome(home, {
    termsHash: "stale-hash",
  });
  const failure = runCliExpectFailure([
    "secret",
    "create-wallet-secret-source",
    "--output",
    outputPath,
    "--random",
    "--json",
  ], {
    cwd: tempRoot,
    home,
  });
  const payload = parseJson(failure.stdout);
  expect(payload.ok === false, "Terms-gated command with stale acceptance should fail.");
  expect(payload.error?.code === "TERMS_ACCEPTANCE_REQUIRED", "Stale acceptance should use TERMS_ACCEPTANCE_REQUIRED.");
  expect(
    String(payload.error?.message ?? "").includes("stale"),
    "Stale acceptance failure should explain that the stored acceptance is stale.",
  );
  expect(!fs.existsSync(outputPath), "Terms-gated command with stale acceptance must not create secret files.");
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
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  expect(!stdout.includes("--acknowledge-action-impact"), "Command help must not expose the deprecated action-impact flag.");
  expect(!stdout.includes("Action impact:"), "Command help must use warning-summary wording.");
  expect(stdout.includes("Warning summary:"), "Command help should describe transaction warnings as warning summaries.");
  expect(stdout.includes("channel exit"), "Command help should include channel exit.");
  expect(
    stdout.includes("Warning summary: emits public channel exit and Join Toll refund events"),
    "Channel exit help should describe its warning summary.",
  );
  expect(!runtimeSource.includes("requireActionImpactAcknowledgement"), "Runtime should not use action-impact acknowledgement internals.");
  expect(!runtimeSource.includes("assertActionImpactArg"), "Runtime should not retain action-impact argument checks.");
  expect(stdout.includes("Opens a local browser Terms page and requires explicit human acceptance before installation proceeds"), "Install help should explain browser-based human Terms acceptance.");
  expect(stdout.includes("Use --terminal-terms only when the local browser flow cannot be used"), "Install help should explain the terminal fallback.");
  expect(stdout.includes("--json reports that browser-based interactive Terms acceptance is required, includes Terms references, and does not install artifacts"), "Install help should explain JSON mode does not install and reports Terms references.");
  expect(stdout.includes("Install results include the canonical Terms version and deterministic Terms hash"), "Install help should mention canonical Terms metadata.");
  expect(stdout.includes("Use --json for machine-readable fee data when another tool needs to inspect the fee table"), "Transaction-fees help should use tool-neutral JSON wording.");
  expect(!stdout.includes("AI agents should run this command"), "Human command help should not use AI-agent-first fee wording.");
  expect(stdout.includes("help observer --network <NAME> --channel-name <NAME>"), "Observer help should require channel-scoped selectors.");
  expect(stdout.includes("Reads the selected Channel's observer URL from on-chain Channel metadata"), "Observer help should describe on-chain observer URL lookup.");
  expect(stdout.includes("Fails clearly when the Channel Provider has not registered an observer URL for that Channel"), "Observer help should explain missing observer registration.");
  expect(!stdout.includes("the CLI cannot recover lost secrets"), "Command help should use no-recovery-method wording.");
  expect(stdout.includes("uninstall [--include-wallet-keys]"), "Command help should expose the uninstall wallet-key deletion option.");
  expect(stdout.includes("Default uninstall preserves wallet spending-key and viewing-key files"), "Command help should explain default uninstall wallet-key preservation.");
  expect(stdout.includes("wallet export viewing-key"), "Command help should include viewing-key export.");
  expect(stdout.includes("Requires an interactive terminal because the output file contains secret-bearing viewing authority"), "Viewing-key export help should explain interactive confirmation.");
  expect(stdout.includes("Requires an interactive terminal because the output file contains secret-bearing spending authority"), "Spending-key export help should explain interactive confirmation.");
  expect(stdout.includes("Use --export-evidence <PATH> to write a local full-note evidence ZIP for private-state-cli investigator after interactive confirmation"), "Evidence export help should explain interactive confirmation.");
  expect(stdout.includes("The raw evidence ZIP may include plaintext note facts for all locally known notes and retained exited epochs for the selected wallet"), "Evidence export help should explain raw evidence scope.");
  expect(stdout.includes("User-Controlled AI Agents must not confirm this export or receive the raw evidence ZIP"), "Evidence export help should forbid agent confirmation and raw ZIP handling.");
  expect(stdout.includes("Do not give the raw evidence ZIP to User-Controlled AI Agents, support channels, or untrusted parties"), "Investigator help should warn against raw ZIP disclosure.");
}

function testHelpObserverUsesChannelScopedSelectors() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const failure = runCliExpectFailure(["help", "observer", "--json"]);
  const payload = parseJson(failure.stdout);

  expect(payload.ok === false, "help observer without selectors should fail.");
  expect(
    String(payload.error?.message ?? "").includes("Missing --network"),
    "help observer should require --network before it can read channel metadata.",
  );
  expect(
    !runtimeSource.includes("PRIVATE_STATE_OBSERVER_URL"),
    "Runtime must not keep a Tonnel-level observer URL constant.",
  );
  expect(
    !runtimeSource.includes("https://observer.tonnel.io"),
    "Runtime must not hardcode observer.tonnel.io as the user-visible observer URL.",
  );
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
    stdout.includes("The local account alias alice is not connected to an Ethereum account on this computer yet."),
    "Human private-key flow should describe the missing local account in ordinary language.",
  );
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
  expect(!stdout.includes("private-key source yet"), "Human private-key flow should avoid source-file-first status wording.");
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

function testReadmeJsonPurposeIsAgentSafe() {
  const readme = fs.readFileSync(readmePath, "utf8");
  const normalizedReadme = readme.replace(/\s+/gu, " ");
  expect(
    normalizedReadme.includes("The purpose of `--json` mode is to let the user's AI agent guide the user through the smallest safe next action"),
    "README should state the JSON mode purpose.",
  );
  expect(
    normalizedReadme.includes("not permission") && normalizedReadme.includes("bypass human review"),
    "README should state that JSON mode cannot bypass human review.",
  );
  expect(normalizedReadme.includes("must not accept Terms or confirmations"), "README should forbid agent acceptance.");
  expect(
    normalizedReadme.includes("Do not ask users to paste raw private keys, wallet secrets, seed phrases"),
    "README should forbid secret collection through prompts.",
  );
  expect(
    normalizedReadme.includes("Channel public observer URLs are also Channel-scoped"),
    "README should explain Channel-scoped observer URLs.",
  );
  expect(
    normalizedReadme.includes("The CLI does not use a Tonnel-wide observer URL"),
    "README should reject Tonnel-wide observer URL defaults.",
  );
  expect(!normalizedReadme.includes("agent's full machine-readable state"), "README should avoid implementation-centered agent-state wording.");
  expect(!normalizedReadme.includes("LLM Agent Guidance"), "README should not use stale LLM agent terminology.");
}

function testAgentsDescribeChannelScopedObserverMetadata() {
  const agents = fs.readFileSync(agentsPath, "utf8").replace(/\s+/gu, " ");
  expect(
    agents.includes("whether a Channel-scoped observer URL is registered"),
    "agents.md should tell User-Controlled AI Agents to inspect Channel-scoped observer registration.",
  );
  expect(
    agents.includes("Mirror and observer URLs are Channel-scoped metadata"),
    "agents.md should state that mirror and observer URLs are Channel-scoped metadata.",
  );
}

function testDeprecatedAcknowledgementOptionsAreAbsentFromRunnableSurfaces() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const e2eSource = fs.readFileSync(e2eCliPath, "utf8");
  const commandHelp = runCli(["help", "commands"]);
  for (const source of [runtimeSource, e2eSource, commandHelp]) {
    expect(!source.includes("--acknowledge-action-impact"), "Runnable CLI surfaces must not use --acknowledge-action-impact.");
    expect(!source.includes("--acknowledge-full-note-plaintext-export"), "Runnable CLI surfaces must not use --acknowledge-full-note-plaintext-export.");
  }
  expect(!e2eSource.includes("acknowledgeActionImpact"), "E2E runner must not keep action-impact acknowledgement helpers.");
}

function testSecretCommandsRegistered() {
  const commandIds = new Set(PRIVATE_STATE_CLI_COMMANDS.map((command) => command.id));
  expect(commandIds.has("secret-create-private-key-source"), "Missing private-key source helper registry entry.");
  expect(commandIds.has("secret-create-wallet-secret-source"), "Missing wallet-secret source helper registry entry.");
}

function testRandomWalletSecretHelper() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-secret-"));
  const home = path.join(tempRoot, "home");
  const outputPath = path.join(tempRoot, "wallet-secret.txt");
  writeTermsAcceptanceForHome(home);
  const stdout = runCli([
    "secret",
    "create-wallet-secret-source",
    "--output",
    outputPath,
    "--random",
    "--json",
  ], {
    cwd: tempRoot,
    home,
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
    home,
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
  const home = path.join(tempRoot, "home");
  const outputPath = path.join(tempRoot, "ethereum-private-key.txt");
  writeTermsAcceptanceForHome(home);
  const failure = runCliExpectFailure([
    "secret",
    "create-private-key-source",
    "--output",
    outputPath,
    "--json",
  ], {
    cwd: tempRoot,
    home,
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
testCanonicalTermsAssetMatchesPublicTerms();
testGuideJsonRefs();
testGuideJsonDeploymentArtifactsMissing();
testInstallJsonDoesNotInstallOrAcceptTerms();
testHumanModeHasNoJsonObjectFallback();
testBrowserTermsUsesMarkdownRendering();
testTerminalTermsFallbackRequiresInteractiveTermsAcceptance();
testInstallManifestPersistsTermsAcceptance();
testTermsGatedJsonRequiresCurrentTermsAcceptance();
testTermsGatedJsonRejectsStaleTermsAcceptance();
testGuideJsonAccountSecretMissing();
testGuideJsonWalletMissingBeforeChannelJoin();
testGuideHumanOutputIsUserFacing();
testHelpCommandsOutputUsesFinalPromptPolicy();
testHelpObserverUsesChannelScopedSelectors();
testGuideHumanPrivateKeyFlowIncludesAddressVerification();
testGuideHumanWalletSecretFlowExplainsMasking();
testReadmeJsonPurposeIsAgentSafe();
testAgentsDescribeChannelScopedObserverMetadata();
testDeprecatedAcknowledgementOptionsAreAbsentFromRunnableSurfaces();
testRandomWalletSecretHelper();
testNonTtyPrivateKeyPromptFailsClearly();

console.log("private-state CLI agent guidance tests passed.");
