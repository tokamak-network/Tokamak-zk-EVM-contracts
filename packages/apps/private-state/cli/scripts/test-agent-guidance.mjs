#!/usr/bin/env node

import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { execFileSync, spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { Wallet } from "ethers";
import {
  buildL2WalletSecretSigningMessage,
  deriveParticipantIdentityFromSigner,
} from "../lib/private-state-cli-shared.mjs";
import {
  PRIVATE_STATE_CLI_COMMANDS,
  privateStateCliCommandRequiredOptionKeys,
} from "../lib/private-state-cli-command-registry.mjs";
import {
  buildEip712Payload,
  normalizeBrowserTransaction,
  personalSignPayload,
  safeJsonForScript,
} from "../lib/private-state-browser-wallet-helpers.mjs";
import {
  readPrivateStateTermsMetadata,
  readPrivateStateTermsText,
} from "../lib/private-state-terms.mjs";
import {
  deriveNoteReceiveKeyMaterial,
} from "../lib/private-state-note-delivery.mjs";
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

function postJson(url, payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload);
    const request = http.request(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "content-length": Buffer.byteLength(body),
      },
    }, (response) => {
      response.resume();
      response.on("end", () => resolve(response.statusCode));
    });
    request.on("error", reject);
    request.end(body);
  });
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    const request = http.request(url, {
      method: "GET",
    }, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => {
        if (response.statusCode !== 200) {
          reject(new Error(`Expected JSON response from ${url}, got HTTP ${response.statusCode}.`));
          return;
        }
        resolve(JSON.parse(body));
      });
    });
    request.on("error", reject);
    request.end();
  });
}

function runCliWithBrowserCallbacks(args, responses, options = {}) {
  return new Promise((resolve, reject) => {
    const home = options.home ?? fs.mkdtempSync(path.join(os.tmpdir(), "private-state-cli-home-"));
    if (options.writeTermsAcceptance !== false) {
      writeTermsAcceptanceForHome(home);
    }
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: options.cwd ?? cliRoot,
      env: {
        ...process.env,
        HOME: home,
        PATH: options.path ?? "/private-state-cli-test-no-browser-opener",
        ...(options.env ?? {}),
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let handledSigningUrlCount = 0;
    const pendingPosts = [];
    const scanInterval = setInterval(() => handleSigningUrls(), 25);
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`Timed out waiting for browser-wallet callback test.\nstdout:\n${stdout}\nstderr:\n${stderr}`));
    }, options.timeoutMs ?? 15_000);
    const handleSigningUrls = () => {
      const matches = [...stderr.matchAll(/Signing URL: (http:\/\/127\.0\.0\.1:\d+\/sign\?token=([^\s]+))/gu)];
      for (const match of matches.slice(handledSigningUrlCount)) {
        const url = match[1];
        const token = decodeURIComponent(match[2]);
        handledSigningUrlCount += 1;
        const response = responses.shift();
        if (!response) {
          reject(new Error(`No browser-wallet test response was provided for ${url}.`));
          continue;
        }
        pendingPosts.push((async () => {
          const activeRequest = await getJson(new URL(`/request?token=${encodeURIComponent(token)}`, url));
          await postJson(new URL("/result", url), { token, requestId: activeRequest.requestId, ...response });
        })());
      }
    };
    child.stdout.on("data", (chunk) => {
      stdout += String(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += String(chunk);
      handleSigningUrls();
    });
    child.on("error", reject);
    child.on("close", async (status) => {
      clearInterval(scanInterval);
      clearTimeout(timeout);
      try {
        await Promise.all(pendingPosts);
        if (status !== 0) {
          if (options.expectFailure) {
            resolve({ stdout, stderr, status });
            return;
          }
          reject(new Error(`CLI failed with status ${status}.\nstdout:\n${stdout}\nstderr:\n${stderr}`));
          return;
        }
        if (options.expectFailure) {
          reject(new Error(`Expected CLI failure.\nstdout:\n${stdout}\nstderr:\n${stderr}`));
          return;
        }
        resolve({ stdout, stderr, status });
      } catch (error) {
        reject(error);
      }
    });
  });
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
  expect(metadata.termsVersion === "2026-06-12", "Unexpected canonical Terms version.");
  expect(
    /^sha256:[0-9a-f]{64}$/u.test(metadata.termsHash),
    `Unexpected canonical Terms hash format: ${metadata.termsHash}`,
  );
  expect(metadata.termsPackagePath === "assets/service-terms.md", "Unexpected packaged Terms path.");
  expect(metadata.termsPublicPath === "docs/dapps/private-state/terms.md", "Unexpected public Terms path.");
  expect(metadata.termsContentBytes === Buffer.byteLength(packagedTerms, "utf8"), "Terms byte length mismatch.");
}

function createIsolatedHomeWithRpc(networkName = "mainnet") {
  return createIsolatedHomeWithRpcUrl(networkName, TEST_RPC_CONFIG.rpcUrl);
}

function createIsolatedHomeWithRpcUrl(networkName, rpcUrl) {
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
      `RPC_URL=${rpcUrl}`,
      "",
    ].join("\n"),
    "utf8",
  );
  return home;
}

async function withJsonRpcChain(chainId, callback) {
  const server = http.createServer((request, response) => {
    let body = "";
    request.on("data", (chunk) => {
      body += String(chunk);
    });
    request.on("end", () => {
      let payload;
      try {
        payload = JSON.parse(body || "{}");
      } catch {
        response.writeHead(400, { "content-type": "application/json" });
        response.end(JSON.stringify({ error: "invalid json" }));
        return;
      }
      const result = payload.method === "eth_chainId"
        ? `0x${BigInt(chainId).toString(16)}`
        : null;
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({
        jsonrpc: "2.0",
        id: payload.id ?? 1,
        result,
      }));
    });
  });
  await new Promise((resolve, reject) => {
    server.listen(0, "127.0.0.1", resolve);
    server.once("error", reject);
  });
  try {
    const address = server.address();
    expect(address && typeof address !== "string", "Test JSON-RPC server did not expose a TCP address.");
    return await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function createIsolatedHomeWithRpcAndReadOnlyArtifacts(networkName = "mainnet", chainId = 1, rpcUrl = TEST_RPC_CONFIG.rpcUrl) {
  const home = createIsolatedHomeWithRpcUrl(networkName, rpcUrl);
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

function testInstallHumanProgressMessages() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  expect(
    runtimeSource.includes("function createInstallProgressReporter"),
    "install should have a dedicated human progress reporter.",
  );
  expect(
    runtimeSource.includes("Install ${currentStep}/${totalSteps}"),
    "install progress should show step counts in human mode.",
  );
  expect(
    runtimeSource.includes("Elapsed ${elapsed()}"),
    "install progress should show elapsed time after completed steps.",
  );
  expect(
    runtimeSource.includes("Installing Groth16 runtime"),
    "full install progress should describe the Groth16 runtime step before it starts.",
  );
  expect(
    runtimeSource.includes("Read-only mode selected. Proof runtimes are skipped."),
    "read-only install progress should explain skipped proof runtimes.",
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
  expect(
    stdout.includes("Omit --account to use a MetaMask-compatible browser wallet instead of a local account alias; the CLI does not read or store the raw L1 private key in this mode."),
    "Command help should explain browser-wallet mode through omitted --account.",
  );
  expect(
    stdout.includes("Use --tx-submitter without a value when a browser wallet should submit executeChannelTransaction and pay gas."),
    "Command help should explain value-less --tx-submitter browser-wallet submission.",
  );
  expect(
    stdout.includes("Browser-wallet L1 signing does not replace local wallet keys; note commands still use the local viewing key and spending key."),
    "Command help should explain that browser-wallet L1 signing does not replace local L2 wallet keys.",
  );
  expect(
    stdout.includes("With browser-wallet mode, the user approves account connection, chain check, the L2 spending-key message signature, the note-receive viewing-key typed-data signature, any Join Toll token approval, and the join transaction in the browser wallet"),
    "Channel join help should explain each browser-wallet approval request.",
  );
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
    normalizedReadme.includes("The CLI supports two L1 signing paths"),
    "README should explain local-account and browser-wallet L1 signing paths.",
  );
  expect(
    normalizedReadme.includes("Browser-wallet mode avoids CLI access to the raw L1 private key"),
    "README should explain that browser-wallet mode avoids raw L1 private-key access.",
  );
  expect(
    normalizedReadme.includes("Browser-wallet mode avoids CLI access to the raw L1 private key") && normalizedReadme.includes("does not remove the local private-state wallet key model"),
    "README should explain that local L2 spending/viewing keys still apply in browser-wallet mode.",
  );
  expect(
    normalizedReadme.includes("The localhost page is a request relay, not an approval UI")
      && normalizedReadme.includes("approve or reject only in the MetaMask-compatible wallet UI"),
    "README should explain that browser-wallet approval happens in the wallet UI, not the localhost page.",
  );
  expect(
    normalizedReadme.includes("account connection, chain check, network switch when needed, the EIP-191 message signature for L2 spending-key derivation"),
    "README should document channel join browser-wallet approval order.",
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
  expect(
    agents.includes("whether the user wants a local account alias or browser wallet L1 signing"),
    "agents.md should let user-controlled agents ask for the intended L1 signing path without asking for secrets.",
  );
  expect(
    agents.includes("private-state-cli channel join --channel-name <CHANNEL> --network <NETWORK> --wallet-secret-path ./wallet-secret.txt"),
    "agents.md should include the browser-wallet channel join template without --account.",
  );
  expect(
    agents.includes("private-state-cli wallet transfer-notes --wallet <WALLET> --network <NETWORK> --note-ids <JSON_ARRAY> --recipients <JSON_ARRAY> --amounts <JSON_ARRAY> --tx-submitter"),
    "agents.md should include the value-less --tx-submitter browser-wallet template.",
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

function commandById(commandId) {
  const command = PRIVATE_STATE_CLI_COMMANDS.find((entry) => entry.id === commandId);
  expect(command, `Missing command registry entry for ${commandId}.`);
  return command;
}

function sourceBetween(source, start, end) {
  const startIndex = source.indexOf(start);
  expect(startIndex >= 0, `Missing source start marker: ${start}`);
  const endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex > startIndex, `Missing source end marker: ${end}`);
  return source.slice(startIndex, endIndex);
}

function indexInSource(source, marker) {
  const index = source.indexOf(marker);
  expect(index >= 0, `Missing source marker: ${marker}`);
  return index;
}

function countOccurrences(source, marker) {
  return source.split(marker).length - 1;
}

function testBrowserWalletAccountGrammar() {
  const accountOptionalCommands = [
    "account-get-l1-address",
    "account-get-bridge-fund",
    "account-deposit-bridge",
    "account-withdraw-bridge",
    "channel-create",
    "channel-set-workspace-mirror",
    "channel-abandon-operation",
    "channel-join",
    "wallet-recover-workspace",
  ];
  for (const commandId of accountOptionalCommands) {
    const requiredKeys = privateStateCliCommandRequiredOptionKeys(commandById(commandId));
    expect(
      !requiredKeys.includes("account"),
      `${commandId} must not require --account because omitted --account selects browser-wallet mode.`,
    );
  }

  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  expect(
    runtimeSource.includes("function resolveL1AccountMode"),
    "Runtime should centralize local-account versus browser-wallet L1 account selection.",
  );
  expect(
    runtimeSource.includes("function isValueLessOption"),
    "Runtime should explicitly recognize value-less options.",
  );
  expect(
    !runtimeSource.includes("--tx-submitter requires a local account name."),
    "Value-less --tx-submitter must no longer be rejected as a missing local account name.",
  );
  expect(
    runtimeSource.includes("TX_SUBMITTER_SOURCES.BROWSER_WALLET"),
    "Runtime should handle value-less --tx-submitter without treating it as a schema error.",
  );
  expect(
    runtimeSource.includes("class BrowserWalletSigner"),
    "Runtime should provide a browser-wallet signer adapter.",
  );
  expect(
    runtimeSource.includes("method: \"eth_sendTransaction\""),
    "Browser-wallet signer should submit L1 transactions through the browser wallet.",
  );
  expect(
    runtimeSource.includes("method: \"eth_signTypedData_v4\""),
    "Browser-wallet signer should support MetaMask typed-data signatures.",
  );
}

function testBrowserWalletPayloadHelpers() {
  const tx = normalizeBrowserTransaction({
    from: "0x1111111111111111111111111111111111111111",
    to: "0x2222222222222222222222222222222222222222",
    data: Uint8Array.from([0x12, 0x34]),
    value: 15n,
    gasLimit: 21000n,
    maxFeePerGas: 30_000_000_000n,
    maxPriorityFeePerGas: 2_000_000_000n,
    nonce: 7,
    chainId: 1n,
    gasPrice: null,
  });
  expect(tx.from === "0x1111111111111111111111111111111111111111", "Browser tx from address should be checksummed.");
  expect(tx.to === "0x2222222222222222222222222222222222222222", "Browser tx to address should be checksummed.");
  expect(tx.data === "0x1234", "Browser tx data should be hex encoded.");
  expect(tx.value === "0xf", "Browser tx value should use JSON-RPC quantity format.");
  expect(tx.gas === "0x5208", "Browser tx gasLimit should map to gas quantity.");
  expect(tx.maxFeePerGas === "0x6fc23ac00", "Browser tx maxFeePerGas should use quantity format.");
  expect(tx.maxPriorityFeePerGas === "0x77359400", "Browser tx maxPriorityFeePerGas should use quantity format.");
  expect(tx.nonce === "0x7", "Browser tx nonce should use quantity format when present.");
  expect(tx.chainId === "0x1", "Browser tx chainId should use quantity format when present.");
  expect(!Object.hasOwn(tx, "gasPrice"), "Browser tx should omit null fee fields.");

  const payload = buildEip712Payload({
    domain: {
      name: "PrivateState",
      version: "1",
      chainId: 1n,
      verifyingContract: "0x3333333333333333333333333333333333333333",
      salt: Uint8Array.from([0xaa, 0xbb]),
      ignored: undefined,
    },
    types: {
      NoteReceiveKey: [
        { name: "channelId", type: "uint256" },
        { name: "account", type: "address" },
        { name: "seed", type: "bytes" },
      ],
    },
    value: {
      channelId: 5n,
      account: "0x4444444444444444444444444444444444444444",
      seed: Uint8Array.from([0x01, 0x02]),
      ignored: undefined,
    },
  });
  expect(payload.primaryType === "NoteReceiveKey", "EIP-712 payload should preserve the primary typed-data type.");
  expect(payload.domain.chainId === "1", "EIP-712 domain BigInt values should serialize as decimal strings.");
  expect(payload.domain.salt === "0xaabb", "EIP-712 domain bytes should serialize as hex strings.");
  expect(!Object.hasOwn(payload.domain, "ignored"), "EIP-712 domain should omit undefined fields.");
  expect(payload.message.channelId === "5", "EIP-712 message BigInt values should serialize as decimal strings.");
  expect(payload.message.seed === "0x0102", "EIP-712 message bytes should serialize as hex strings.");
  expect(!Object.hasOwn(payload.message, "ignored"), "EIP-712 message should omit undefined fields.");
  expect(
    JSON.stringify(payload).includes("\"channelId\":\"5\""),
    "EIP-712 payload should be JSON-serializable for eth_signTypedData_v4.",
  );

  expect(personalSignPayload("hello") === "0x68656c6c6f", "personal_sign string payload should be UTF-8 hex.");
  expect(personalSignPayload(Uint8Array.from([0xde, 0xad])) === "0xdead", "personal_sign bytes payload should be hex.");
  const scriptJson = safeJsonForScript({
    text: "</script><script>alert(1)</script>",
    amp: "&",
  });
  expect(!scriptJson.includes("</script>"), "Browser signing page JSON should not contain raw script-closing text.");
  expect(scriptJson.includes("\\u003c/script\\u003e"), "Browser signing page JSON should escape '<' characters.");
  expect(scriptJson.includes("\\u0026"), "Browser signing page JSON should escape '&' characters.");
}

async function testMockedBrowserSignaturesDeriveWalletKeys() {
  const l1Wallet = new Wallet("0x59c6995e998f97a5a0044966f094538e7a7b2ee70b2d7e4e6f8f8f8f8f8f8f8f");
  const calls = [];
  const signer = {
    address: l1Wallet.address,
    async signMessage(message) {
      calls.push({ method: "personal_sign", message });
      return await l1Wallet.signMessage(message);
    },
    async signTypedData(domain, types, value) {
      calls.push({ method: "eth_signTypedData_v4", domain, types, value });
      return await l1Wallet.signTypedData(domain, types, value);
    },
  };
  const channelName = "browser-wallet-test-channel";
  const walletSecret = "test wallet secret";
  const expectedMessage = buildL2WalletSecretSigningMessage({ channelName, walletSecret });
  const l2Identity = await deriveParticipantIdentityFromSigner({
    channelName,
    walletSecret,
    signer,
  });
  expect(calls[0]?.method === "personal_sign", "L2 spending-key derivation should request an EIP-191 message signature.");
  expect(calls[0]?.message === expectedMessage, "L2 spending-key derivation should sign the channel-bound wallet-secret message.");
  expect(l2Identity.seedSignature === await l1Wallet.signMessage(expectedMessage), "L2 spending-key derivation should use the mocked browser signature.");
  expect(l2Identity.l2PrivateKey instanceof Uint8Array && l2Identity.l2PrivateKey.length > 0, "L2 spending-key derivation should produce a local spending private key.");
  expect(l2Identity.l2PublicKey instanceof Uint8Array && l2Identity.l2PublicKey.length > 0, "L2 spending-key derivation should produce a local spending public key.");
  expect(/^0x[0-9a-fA-F]{40}$/u.test(l2Identity.l2Address), "L2 spending-key derivation should produce a channel-local address.");

  const noteReceive = await deriveNoteReceiveKeyMaterial({
    signer,
    chainId: 1,
    channelId: 123n,
    channelName,
    account: l1Wallet.address,
  });
  const typedDataCall = calls.find((entry) => entry.method === "eth_signTypedData_v4");
  expect(typedDataCall, "Note-receive key derivation should request an EIP-712 typed-data signature.");
  expect(typedDataCall.domain.name === "TokamakPrivateState", "Note-receive typed-data domain should identify private-state.");
  expect(typedDataCall.domain.version === "1", "Note-receive typed-data domain should include the version.");
  expect(typedDataCall.domain.chainId === 1, "Note-receive typed-data domain should include the selected chain id.");
  expect(Array.isArray(typedDataCall.types.NoteReceiveKey), "Note-receive typed-data should include the NoteReceiveKey type.");
  expect(typedDataCall.value.protocol === "PRIVATE_STATE_NOTE_RECEIVE_KEY_V2", "Note-receive typed-data should include the protocol domain.");
  expect(typedDataCall.value.dapp === "private-state", "Note-receive typed-data should include the DApp label.");
  expect(typedDataCall.value.channelId === "123", "Note-receive typed-data should include the channel id as a decimal string.");
  expect(typedDataCall.value.channelName === channelName, "Note-receive typed-data should include the channel name.");
  expect(typedDataCall.value.account === l1Wallet.address, "Note-receive typed-data should include the selected browser wallet account.");
  expect(
    noteReceive.signature === await l1Wallet.signTypedData(typedDataCall.domain, typedDataCall.types, typedDataCall.value),
    "Note-receive key derivation should use the mocked browser typed-data signature.",
  );
  expect(/^0x[0-9a-fA-F]{64}$/u.test(noteReceive.privateKey), "Note-receive key derivation should produce a local viewing private key.");
  expect(/^0x[0-9a-fA-F]{64}$/u.test(noteReceive.noteReceivePubKey.x), "Note-receive key derivation should produce a viewing public key x-coordinate.");
  expect(
    noteReceive.noteReceivePubKey.yParity === 0 || noteReceive.noteReceivePubKey.yParity === 1,
    "Note-receive key derivation should produce a viewing public key y parity.",
  );
}

function testChannelJoinBrowserWalletFlowCoverage() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const joinSource = sourceBetween(
    runtimeSource,
    "async function handleJoinChannel",
    "async function handleExitChannel",
  );
  const browserSignerSource = sourceBetween(
    runtimeSource,
    "class BrowserWalletSigner",
    "async function requestBrowserWallet",
  );
  const browserSigningPageSource = sourceBetween(
    runtimeSource,
    "function browserWalletSigningHtml",
    "function browserWalletResultHtml",
  );
  const browserBridgeSessionSource = sourceBetween(
    runtimeSource,
    "class BrowserWalletBridgeSession",
    "function browserWalletSigningHtml",
  );
  expect(
    joinSource.includes("const signer = await requireL1Signer(args, provider);"),
    "channel join should resolve local-account or browser-wallet L1 authority through requireL1Signer.",
  );
  expect(
    indexInSource(joinSource, "deriveParticipantIdentityFromSigner")
      < indexInSource(joinSource, "deriveNoteReceiveKeyMaterial"),
    "channel join should derive the L2 spending identity before deriving note-receive viewing material.",
  );
  expect(
    indexInSource(joinSource, "deriveNoteReceiveKeyMaterial") < indexInSource(joinSource, "asset.approve"),
    "channel join should finish browser wallet key-derivation signatures before token approval.",
  );
  expect(
    indexInSource(joinSource, "asset.approve") < indexInSource(joinSource, "joinChannel"),
    "channel join should approve the join toll before submitting joinChannel.",
  );
  expect(
    browserSignerSource.includes("method: \"eth_requestAccounts\"")
      && browserSignerSource.includes("method: \"eth_chainId\"")
      && browserSignerSource.includes("method: \"wallet_switchEthereumChain\"")
      && browserSignerSource.includes("method: \"personal_sign\"")
      && browserSignerSource.includes("method: \"eth_signTypedData_v4\"")
      && browserSignerSource.includes("method: \"eth_sendTransaction\""),
    "BrowserWalletSigner should cover the channel join connect, chain check, chain switch, key derivation, and transaction methods.",
  );
  expect(
    indexInSource(browserSignerSource, "action: \"switch network\"")
      < indexInSource(browserSignerSource, "action: \"recheck network\""),
    "BrowserWalletSigner should recheck the chain after requesting wallet_switchEthereumChain.",
  );
  expect(
    !browserSigningPageSource.includes("Continue In Browser Wallet")
      && !browserSigningPageSource.includes("addEventListener(\"click\"")
      && !browserSigningPageSource.includes("<button")
      && !browserSigningPageSource.includes("Browser Wallet Approval"),
    "Browser wallet signing page must not present a CLI-controlled approval UI.",
  );
  expect(
    browserSigningPageSource.includes("window.addEventListener(\"load\"")
      && browserSigningPageSource.includes("runRelayLoop()")
      && browserSigningPageSource.includes("readNextRequest")
      && browserSigningPageSource.includes("waitForEthereumProvider")
      && browserSigningPageSource.includes("provider.request"),
    "Browser wallet signing page should keep one relay loop, wait for provider injection, and start provider requests from the page.",
  );
  expect(
    runtimeSource.includes("buildBrowserWalletRequestExplanation")
      && runtimeSource.includes("whatThisDoes")
      && runtimeSource.includes("approvalEffect")
      && runtimeSource.includes("publicDisclosure")
      && runtimeSource.includes("privacyEffect")
      && runtimeSource.includes("safeToReject")
      && runtimeSource.includes("noteParagraphs")
      && browserBridgeSessionSource.includes("explanation: this.pending.explanation")
      && browserSigningPageSource.includes("renderRequestExplanation")
      && browserSigningPageSource.includes("activeRequest.explanation")
      && browserSigningPageSource.includes("appendNoteParagraph")
      && !browserSigningPageSource.includes("Role: ")
      && !browserSigningPageSource.includes("Action: ")
      && !browserSigningPageSource.includes("\"Result\"")
      && !browserSigningPageSource.includes("\"Public\"")
      && !browserSigningPageSource.includes("\"Privacy\"")
      && !browserSigningPageSource.includes("\"Account\"")
      && !browserSigningPageSource.includes("\"Network\""),
    "Browser wallet signing page should render friendly note-style request explanations instead of developer labels or information-table labels.",
  );
  expect(
    browserSigningPageSource.includes("activeRequest && activeRequest.done")
      && browserSigningPageSource.includes("markComplete(activeRequest.message)")
      && browserSigningPageSource.includes("AbortController")
      && browserSigningPageSource.includes("requestReadFailureStartedAt")
      && browserSigningPageSource.includes("Waiting for the CLI relay to respond...")
      && browserSigningPageSource.includes("The CLI relay is not responding. Check the terminal for the command result.")
      && browserSigningPageSource.includes("markRelayStopped(error)"),
    "Browser wallet signing page should stop cleanly on command completion, retry transient relay fetch failures, and avoid showing raw stale fetch failures.",
  );
  expect(
    browserSigningPageSource.includes("postStatus(activeRequest, \"loaded\")")
      && browserSigningPageSource.includes("postStatus(activeRequest, \"request-started\")"),
    "Browser wallet signing page should report page load and provider request start status back to the CLI.",
  );
  expect(
    browserSigningPageSource.includes("collectTransactionFailureDiagnostics")
      && browserSigningPageSource.includes("provider.isMetaMask")
      && browserSigningPageSource.includes("\"eth_accounts\"")
      && browserSigningPageSource.includes("\"eth_chainId\"")
      && browserSigningPageSource.includes("dataByteLength"),
    "Browser wallet signing page should collect sanitized eth_sendTransaction failure diagnostics.",
  );
  expect(
    browserBridgeSessionSource.includes("this.token = ethers.hexlify(randomBytes(24))")
      && browserBridgeSessionSource.includes("requestId = ethers.hexlify(randomBytes(12))")
      && browserBridgeSessionSource.includes("requestUrl.pathname === \"/request\"")
      && browserBridgeSessionSource.includes("waitForPendingRequest")
      && browserBridgeSessionSource.includes("notifyRequestWaiters")
      && browserBridgeSessionSource.includes("canDeliverPendingRequest")
      && browserBridgeSessionSource.includes("this.closing")
      && browserBridgeSessionSource.includes("writeCompletionResponse")
      && browserBridgeSessionSource.includes("done: true")
      && browserBridgeSessionSource.includes("pageReopenAttempted")
      && browserBridgeSessionSource.includes("this.server.unref()"),
    "Browser wallet bridge should keep one localhost origin, long-poll per-request IDs, and safely wake stale relay pages including command completion.",
  );
  expect(
    joinSource.includes("typeof signer.privateKey === \"string\""),
    "channel join should detect whether the signer is backed by a local L1 private key.",
  );
  expect(
    joinSource.includes("const nextL1TransactionOverrides = () => usesLocalL1PrivateKey ? { nonce: nextNonce++ } : undefined;"),
    "channel join should omit explicit nonce overrides when browser wallet submission is used.",
  );
}

function testL1TransactionBrowserWalletFlowCoverage() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const l1CommandSources = [
    ["channel create", sourceBetween(runtimeSource, "async function handleChannelCreate", "async function handleWorkspaceInit")],
    ["channel set-workspace-mirror", sourceBetween(runtimeSource, "async function handleSetChannelWorkspaceMirror", "async function handleAbandonChannelOperation")],
    ["channel abandon-operation", sourceBetween(runtimeSource, "async function handleAbandonChannelOperation", "async function publishChannelWorkspaceMirrorFromRecoveredWorkspace")],
    ["account deposit-bridge", sourceBetween(runtimeSource, "async function handleDepositBridge", "async function handleAccountGetBridgeFund")],
    ["account withdraw-bridge", sourceBetween(runtimeSource, "async function handleWithdrawBridge", "function resolveFunctionMetadataProofForExecution")],
    ["wallet recover-workspace", sourceBetween(runtimeSource, "async function handleRecoverWallet", "async function deriveRecoverWalletSpendingIdentity")],
  ];
  for (const [name, source] of l1CommandSources) {
    expect(
      source.includes("const signer = await requireL1Signer(args, provider);"),
      `${name} should resolve omitted --account through browser-wallet-capable requireL1Signer.`,
    );
  }

  const depositSource = sourceBetween(
    runtimeSource,
    "async function handleDepositBridge",
    "async function handleAccountGetBridgeFund",
  );
  expect(
    depositSource.includes("const usesLocalL1PrivateKey = typeof signer.privateKey === \"string\";"),
    "account deposit-bridge should distinguish local account signing from browser-wallet signing.",
  );
  expect(
    depositSource.includes("const nextL1TransactionOverrides = () => usesLocalL1PrivateKey ? { nonce: nextNonce++ } : undefined;"),
    "account deposit-bridge should omit explicit nonce overrides when browser wallet submission is used.",
  );
  expect(
    depositSource.includes("asset.allowance(signer.address, bridgeVaultContext.bridgeTokenVaultAddress)")
      && depositSource.includes("if (currentAllowance < amount)")
      && depositSource.includes("approveSkipped"),
    "account deposit-bridge should reuse sufficient existing allowance instead of forcing a duplicate approval.",
  );
  expect(
    countOccurrences(depositSource, "nextL1TransactionOverrides()") === 2,
    "account deposit-bridge should apply the browser-safe override policy to both approve and fund transactions.",
  );

  const browserSignerSource = sourceBetween(
    runtimeSource,
    "class BrowserWalletSigner",
    "async function requestBrowserWallet",
  );
  expect(
    indexInSource(browserSignerSource, "method: \"eth_requestAccounts\"")
      < indexInSource(browserSignerSource, "method: \"eth_chainId\""),
    "BrowserWalletSigner should connect the account before checking chain id for provider-backed L1 transaction commands.",
  );
  expect(
    browserSignerSource.includes("Browser wallet chain ${walletChainId} does not match selected network chain ${expectedChainId}."),
    "BrowserWalletSigner should fail clearly on wrong-chain browser wallets.",
  );
  expect(
    browserSignerSource.includes("method: \"eth_sendTransaction\""),
    "BrowserWalletSigner should submit L1 transaction commands through eth_sendTransaction.",
  );
  expect(
    !browserSignerSource.includes("wallet_requestPermissions")
      && !browserSignerSource.includes("ensureAuthorizedAccount")
      && !browserSignerSource.includes("eth_accounts"),
    "BrowserWalletSigner should not add extra account-permission prompts beyond the initial browser wallet connection.",
  );
}

function testWalletOwnerBrowserFallbackFlowCoverage() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const exitSource = sourceBetween(
    runtimeSource,
    "async function handleExitChannel",
    "async function handleGrothVaultMove",
  );
  const grothMoveSource = sourceBetween(
    runtimeSource,
    "async function handleGrothVaultMove",
    "async function handleWithdrawBridge",
  );
  const ownerSignerSource = sourceBetween(
    runtimeSource,
    "async function requireWalletOwnerSigner",
    "function requireWalletSpendingCapability",
  );
  const registrationSource = sourceBetween(
    runtimeSource,
    "async function loadWalletChannelRegistrationState",
    "function walletRegistrationMatchesIdentity",
  );
  expect(
    ownerSignerSource.includes("expectedAddress: walletContext.wallet.l1Address"),
    "Wallet-owner browser fallback must require the selected browser address to match the wallet owner address.",
  );
  expect(
    registrationSource.includes("const signer = restoreWalletSigner(walletContext, provider);"),
    "Read-only wallet registration and fund loading should use the stored wallet owner address without opening a browser wallet.",
  );
  expect(
    !registrationSource.includes("requireWalletOwnerSigner("),
    "Read-only wallet registration and fund loading must not require browser-wallet owner approval.",
  );
  expect(
    grothMoveSource.includes("const signer = await requireWalletOwnerSigner(walletContext, provider);"),
    "wallet deposit-channel and wallet withdraw-channel should use browser-wallet fallback when the local owner L1 key is absent.",
  );
  expect(
    grothMoveSource.includes("const l2Identity = restoreParticipantIdentityFromWallet(walletContext.wallet);"),
    "wallet deposit-channel and wallet withdraw-channel should keep L2 identity restoration local to the wallet workspace.",
  );
  expect(
    !grothMoveSource.includes("const { signer, l2Identity } = restoreWalletParticipant(walletContext, provider);"),
    "wallet deposit-channel and wallet withdraw-channel must not submit through an address-only restored signer.",
  );
  expect(
    countOccurrences(exitSource, "requireWalletOwnerSigner(") === 1,
    "channel exit should request wallet owner approval once, after read-only channel-fund validation.",
  );
  expect(
    exitSource.includes("const ownerSigner = await requireWalletOwnerSigner(walletContext, provider);"),
    "channel exit should use browser-wallet fallback for the owner transaction submitter.",
  );
}

function testNoteCommandBrowserSubmitterFlowCoverage() {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const mintSource = sourceBetween(
    runtimeSource,
    "async function handleMintNotes",
    "async function handleRedeemNotes",
  );
  const redeemSource = sourceBetween(
    runtimeSource,
    "async function handleRedeemNotes",
    "async function handleWalletGetNotes",
  );
  const transferSource = sourceBetween(
    runtimeSource,
    "async function handleTransferNotes",
    "function assertWalletMatchesChannelContext",
  );
  const directExecutionSource = sourceBetween(
    runtimeSource,
    "async function executeWalletDirectTemplateCommand",
    "async function executeWalletTemplateSend",
  );
  const resolverSource = sourceBetween(
    runtimeSource,
    "async function resolveTxSubmitterSigner",
    "function resolvePrivateKeySource",
  );
  for (const [name, source] of [
    ["wallet mint-notes", mintSource],
    ["wallet redeem-notes", redeemSource],
    ["wallet transfer-notes", transferSource],
  ]) {
    expect(
      source.includes("const txSubmitterResolution = await resolveTxSubmitterSigner({"),
      `${name} should resolve the L1 submitter once before warning output and execution.`,
    );
    expect(
      source.includes("txSubmitterResolution,"),
      `${name} should pass the resolved L1 submitter into the execution path.`,
    );
  }
  expect(
    directExecutionSource.includes("txSubmitterResolution = null"),
    "Wallet direct note execution should accept a pre-resolved L1 submitter.",
  );
  expect(
    directExecutionSource.includes("} = txSubmitterResolution ?? (await resolveTxSubmitterSigner({"),
    "Wallet direct note execution should resolve the L1 submitter only when one was not pre-resolved.",
  );
  expect(
    directExecutionSource.includes("const { signer, l2Identity } = restoreWalletParticipant(wallet, provider);"),
    "Wallet direct note execution should restore local L2 identity from the wallet workspace.",
  );
  expect(
    directExecutionSource.includes("requireWalletSpendingCapability(wallet);"),
    "Wallet direct note execution should require local L2 spending capability.",
  );
  const templateSendSource = sourceBetween(
    runtimeSource,
    "async function executeWalletTemplateSend",
    "function loadTokamakPayloadFromStep",
  );
  expect(
    templateSendSource.includes("signerPrivateKey: l2Identity.l2PrivateKey"),
    "Proof-backed note execution should sign the Tokamak L2 transaction with the local L2 spending key.",
  );
  expect(
    templateSendSource.includes("context.channelManager.connect(txSubmitter).executeChannelTransaction"),
    "Proof-backed note execution should submit executeChannelTransaction through the resolved L1 submitter.",
  );
  expect(
    resolverSource.includes("ownerSigner instanceof BrowserWalletSigner"),
    "No --tx-submitter owner fallback should reuse an already connected browser wallet owner signer.",
  );
  expect(
    resolverSource.includes("source: TX_SUBMITTER_SOURCES.BROWSER_WALLET_OWNER"),
    "Browser wallet owner fallback should remain visible in operation output.",
  );
}

function testMissingAccountSelectsBrowserWalletMode() {
  const failure = runCliExpectFailure([
    "account",
    "get-l1-address",
    "--network",
    "mainnet",
    "--json",
  ]);
  const payload = parseJson(failure.stdout);
  expect(payload.ok === false, "Browser-wallet mode should reject non-interactive JSON runs.");
  expect(
    String(payload.error?.message ?? "").includes("requires interactive human approval and cannot run in --json mode"),
    "Missing --account should select browser-wallet mode and reject --json without opening a browser.",
  );
  expect(
    !String(payload.error?.message ?? "").includes("Missing --account"),
    "Missing --account should no longer be reported as a required-option error.",
  );
}

async function testBrowserWalletHumanConnectsFromLocalCallback() {
  const selectedAddress = "0x1111111111111111111111111111111111111111";
  const result = await runCliWithBrowserCallbacks([
    "account",
    "get-l1-address",
    "--network",
    "mainnet",
  ], [
    { ok: true, result: [selectedAddress] },
  ]);
  expect(
    result.stderr.includes("Browser wallet approval required: connect."),
    "Human browser-wallet mode should print an approval prompt for the connect request.",
  );
  expect(
    result.stderr.includes("MetaMask-capable browser"),
    "Human browser-wallet mode should explain that the signing URL can be opened in a MetaMask-capable browser.",
  );
  expect(
    result.stderr.includes("localhost page is only a wallet-request relay and has no approval button"),
    "Human browser-wallet mode should explain that approval happens in the wallet UI, not the localhost page.",
  );
  expect(
    result.stdout.includes(selectedAddress),
    "Browser-wallet account get-l1-address should use the address returned by the localhost wallet callback.",
  );
  expect(
    !result.stdout.includes("privateKey"),
    "Browser-wallet account get-l1-address output must not include any private-key field.",
  );
}

async function testBrowserWalletHumanRejectsLocalCallback() {
  const result = await runCliWithBrowserCallbacks([
    "account",
    "get-l1-address",
    "--network",
    "mainnet",
  ], [
    { ok: false, error: "User rejected the browser wallet request." },
  ], {
    expectFailure: true,
  });
  expect(
    result.status !== 0,
    "Rejected browser-wallet approval must fail the CLI command.",
  );
  expect(
    result.stderr.includes("Browser wallet connect failed: User rejected the browser wallet request."),
    "Rejected browser-wallet approval should explain the wallet rejection.",
  );
}

async function testBrowserWalletFailureIncludesDiagnostics() {
  const longCalldata = `0x${"12".repeat(128)}`;
  const selectedAddress = "0x1111111111111111111111111111111111111111";
  const result = await runCliWithBrowserCallbacks([
    "account",
    "get-l1-address",
    "--network",
    "mainnet",
  ], [
    {
      ok: false,
      error: {
        code: 4100,
        message: "Unauthorized.",
        data: {
          calldata: longCalldata,
        },
      },
      diagnostics: {
        provider: { isMetaMask: true },
        preflight: {
          ethAccounts: [selectedAddress],
          ethChainId: "0xaa36a7",
        },
        transaction: {
          from: selectedAddress,
          to: "0x2222222222222222222222222222222222222222",
          value: "0x0",
          dataByteLength: 128,
        },
        signerAddress: selectedAddress,
      },
    },
  ], {
    expectFailure: true,
  });
  expect(
    result.stderr.includes("Wallet error code: 4100")
      && result.stderr.includes("provider.isMetaMask: true")
      && result.stderr.includes("eth_chainId: 0xaa36a7")
      && result.stderr.includes(`transaction.from: ${selectedAddress}`)
      && result.stderr.includes("transaction.dataByteLength: 128")
      && result.stderr.includes(`signerAddress: ${selectedAddress}`),
    "Browser wallet failures should include structured diagnostics.",
  );
  expect(
    !result.stderr.includes(longCalldata),
    "Browser wallet diagnostics must not print full calldata.",
  );
}

async function testBrowserWalletHumanRejectsMalformedAccounts() {
  const result = await runCliWithBrowserCallbacks([
    "account",
    "get-l1-address",
    "--network",
    "mainnet",
  ], [
    { ok: true, result: [] },
  ], {
    expectFailure: true,
  });
  expect(
    result.status !== 0,
    "Malformed browser-wallet account response must fail the CLI command.",
  );
  expect(
    result.stderr.includes("Browser wallet did not return any account."),
    "Malformed browser-wallet account response should explain that no account was returned.",
  );
}

async function testBrowserWalletSwitchesWrongChainBeforeContinuing() {
  await withJsonRpcChain(1, async (rpcUrl) => {
    const selectedAddress = "0x1111111111111111111111111111111111111111";
    const result = await runCliWithBrowserCallbacks([
      "account",
      "get-bridge-fund",
      "--network",
      "mainnet",
    ], [
      { ok: true, result: [selectedAddress] },
      { ok: true, result: "0xaa36a7" },
      { ok: true, result: null },
      { ok: true, result: "0x1" },
    ], {
      home: createIsolatedHomeWithRpcAndReadOnlyArtifacts("mainnet", 1, rpcUrl),
      expectFailure: true,
    });
    expect(
      result.stderr.includes("Browser wallet approval required: switch network."),
      "Wrong-chain browser wallet path should request wallet_switchEthereumChain.",
    );
    expect(
      result.stderr.includes("Browser wallet approval required: recheck network."),
      "Wrong-chain browser wallet path should recheck eth_chainId after switching.",
    );
    expect(
      !result.stderr.includes("Browser wallet chain 11155111 does not match selected network chain 1."),
      "Successful switch recheck should avoid the old wrong-chain failure.",
    );
    expect(result.status !== 0, "Isolated test command should fail after the chain-switch path is exercised.");
  });
}

async function testBrowserWalletChainSwitchRejectionFailsClosed() {
  await withJsonRpcChain(1, async (rpcUrl) => {
    const selectedAddress = "0x1111111111111111111111111111111111111111";
    const result = await runCliWithBrowserCallbacks([
      "account",
      "get-bridge-fund",
      "--network",
      "mainnet",
    ], [
      { ok: true, result: [selectedAddress] },
      { ok: true, result: "0xaa36a7" },
      { ok: false, error: "User rejected the network switch." },
    ], {
      home: createIsolatedHomeWithRpcAndReadOnlyArtifacts("mainnet", 1, rpcUrl),
      expectFailure: true,
    });
    expect(
      result.stderr.includes("Browser wallet switch network failed: User rejected the network switch."),
      "Rejected wallet_switchEthereumChain should fail closed with the wallet rejection.",
    );
    expect(
      !result.stderr.includes("Browser wallet approval required: recheck network."),
      "Rejected wallet_switchEthereumChain must not continue to the recheck step.",
    );
  });
}

function testValueLessTxSubmitterPassesArgumentValidation() {
  const failure = runCliExpectFailure([
    "wallet",
    "mint-notes",
    "--wallet",
    "demo-0x0000000000000000000000000000000000000001",
    "--network",
    "mainnet",
    "--amounts",
    "[\"1\"]",
    "--tx-submitter",
    "--json",
  ]);
  const payload = parseJson(failure.stdout);
  expect(payload.ok === false, "Command should fail later because the isolated test home is not set up.");
  expect(
    !String(payload.error?.message ?? "").includes("--tx-submitter requires"),
    "Value-less --tx-submitter should select browser-wallet submitter mode instead of failing argument validation.",
  );
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

async function main() {
  testSecretCommandsRegistered();
  testBrowserWalletAccountGrammar();
  testBrowserWalletPayloadHelpers();
  await testMockedBrowserSignaturesDeriveWalletKeys();
  testChannelJoinBrowserWalletFlowCoverage();
  testL1TransactionBrowserWalletFlowCoverage();
  testWalletOwnerBrowserFallbackFlowCoverage();
  testNoteCommandBrowserSubmitterFlowCoverage();
  testMissingAccountSelectsBrowserWalletMode();
  await testBrowserWalletHumanConnectsFromLocalCallback();
  await testBrowserWalletHumanRejectsLocalCallback();
  await testBrowserWalletFailureIncludesDiagnostics();
  await testBrowserWalletHumanRejectsMalformedAccounts();
  await testBrowserWalletSwitchesWrongChainBeforeContinuing();
  await testBrowserWalletChainSwitchRejectionFailsClosed();
  testValueLessTxSubmitterPassesArgumentValidation();
  testCanonicalTermsAssetMatchesPublicTerms();
  testGuideJsonRefs();
  testGuideJsonDeploymentArtifactsMissing();
  testInstallJsonDoesNotInstallOrAcceptTerms();
  testHumanModeHasNoJsonObjectFallback();
  testBrowserTermsUsesMarkdownRendering();
  testInstallHumanProgressMessages();
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
}

await main();
