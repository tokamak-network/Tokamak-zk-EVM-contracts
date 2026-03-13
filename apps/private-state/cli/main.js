const { BrowserProvider, Interface, formatEther, toQuantity } = window.ethers;

const NETWORKS = {
  sepolia: {
    chainId: 11155111,
    chainIdHex: "0xaa36a7",
    displayName: "Sepolia"
  },
  mainnet: {
    chainId: 1,
    chainIdHex: "0x1",
    displayName: "Ethereum Mainnet"
  },
  "base-sepolia": {
    chainId: 84532,
    chainIdHex: "0x14a34",
    displayName: "Base Sepolia"
  },
  "base-mainnet": {
    chainId: 8453,
    chainIdHex: "0x2105",
    displayName: "Base Mainnet"
  },
  "arb-sepolia": {
    chainId: 421614,
    chainIdHex: "0x66eee",
    displayName: "Arbitrum Sepolia"
  },
  "arb-mainnet": {
    chainId: 42161,
    chainIdHex: "0xa4b1",
    displayName: "Arbitrum One"
  },
  "op-sepolia": {
    chainId: 11155420,
    chainIdHex: "0xaa37dc",
    displayName: "OP Sepolia"
  },
  "op-mainnet": {
    chainId: 10,
    chainIdHex: "0xa",
    displayName: "OP Mainnet"
  },
  anvil: {
    chainId: 31337,
    chainIdHex: "0x7a69",
    displayName: "anvil",
    addEthereumChain: {
      chainId: "0x7a69",
      chainName: "anvil",
      nativeCurrency: {
        name: "Ether",
        symbol: "ETH",
        decimals: 18
      },
      rpcUrls: ["http://127.0.0.1:8545"]
    }
  }
};

const state = {
  provider: null,
  signerAddress: null,
  connectedChainId: null,
  functionIndex: [],
  deploymentManifest: null,
  selectedTemplate: null,
  abiCache: new Map()
};

const elements = {
  networkSelect: document.querySelector("#network-select"),
  functionSelect: document.querySelector("#function-select"),
  connectWallet: document.querySelector("#connect-wallet"),
  switchNetwork: document.querySelector("#switch-network"),
  reloadTemplate: document.querySelector("#reload-template"),
  calldataEditor: document.querySelector("#calldata-editor"),
  functionDescription: document.querySelector("#function-description"),
  manifestPath: document.querySelector("#manifest-path"),
  contractKey: document.querySelector("#contract-key"),
  contractAddress: document.querySelector("#contract-address"),
  functionMode: document.querySelector("#function-mode"),
  functionMethod: document.querySelector("#function-method"),
  walletStatus: document.querySelector("#wallet-status"),
  walletAccount: document.querySelector("#wallet-account"),
  walletChain: document.querySelector("#wallet-chain"),
  transactionPreview: document.querySelector("#transaction-preview"),
  resultOutput: document.querySelector("#result-output"),
  generateCalldata: document.querySelector("#generate-calldata"),
  performCall: document.querySelector("#perform-call"),
  sendTransaction: document.querySelector("#send-transaction")
};

bootstrap().catch((error) => {
  renderResult(error.message ?? String(error));
});

async function bootstrap() {
  populateNetworkOptions();
  state.functionIndex = await fetchJson("./functions/index.json");
  populateFunctionOptions();

  elements.networkSelect.addEventListener("change", onSelectionChanged);
  elements.functionSelect.addEventListener("change", onSelectionChanged);
  elements.connectWallet.addEventListener("click", connectMetaMask);
  elements.switchNetwork.addEventListener("click", switchNetwork);
  elements.reloadTemplate.addEventListener("click", loadSelectedTemplate);
  elements.generateCalldata.addEventListener("click", generateTransactionPreview);
  elements.performCall.addEventListener("click", performCall);
  elements.sendTransaction.addEventListener("click", sendTransaction);

  if (window.ethereum) {
    state.provider = new BrowserProvider(window.ethereum);
    window.ethereum.on("accountsChanged", handleAccountsChanged);
    window.ethereum.on("chainChanged", handleChainChanged);
  }

  await onSelectionChanged();
  await refreshWalletState();
}

function populateNetworkOptions() {
  const options = Object.entries(NETWORKS).map(([networkKey, config]) => {
    const option = document.createElement("option");
    option.value = networkKey;
    option.textContent = `${config.displayName} (${config.chainId})`;
    return option;
  });

  elements.networkSelect.replaceChildren(...options);
  elements.networkSelect.value = "sepolia";
}

function populateFunctionOptions() {
  const options = state.functionIndex.map((entry) => {
    const option = document.createElement("option");
    option.value = entry.name;
    option.textContent = entry.name;
    return option;
  });

  elements.functionSelect.replaceChildren(...options);

  if (state.functionIndex.length > 0) {
    elements.functionSelect.value = state.functionIndex[0].name;
  }
}

async function onSelectionChanged() {
  state.deploymentManifest = await loadDeploymentManifest(elements.networkSelect.value);
  await loadSelectedTemplate();
  renderDeployment();
  await refreshWalletState();
}

async function loadDeploymentManifest(networkKey) {
  const network = NETWORKS[networkKey];
  const manifestPath = `../deploy/deployment.${network.chainId}.latest.json`;
  elements.manifestPath.textContent = manifestPath;

  try {
    return await fetchJson(manifestPath);
  } catch (error) {
    renderResult(`Failed to load deployment manifest for ${networkKey}: ${error.message}`);
    return null;
  }
}

async function loadSelectedTemplate() {
  const functionName = elements.functionSelect.value;
  const templatePath = `./functions/${functionName}/calldata.json`;
  const template = await fetchJson(templatePath);
  state.selectedTemplate = template;

  elements.calldataEditor.value = JSON.stringify(template, null, 2);
  elements.functionDescription.textContent = template.description ?? "-";
  renderDeployment();
  elements.transactionPreview.textContent = "-";
}

function renderDeployment() {
  const template = state.selectedTemplate;
  const manifest = state.deploymentManifest;
  const contractKey = template?.contractKey ?? "-";
  const contractAddress = manifest?.contracts?.[contractKey] ?? "Missing deployment";

  elements.contractKey.textContent = contractKey;
  elements.contractAddress.textContent = contractAddress;
  elements.functionMode.textContent = template?.mode ?? "-";
  elements.functionMethod.textContent = template?.method ?? "-";
}

async function refreshWalletState() {
  if (!window.ethereum || !state.provider) {
    elements.walletStatus.textContent = "MetaMask unavailable";
    elements.walletAccount.textContent = "-";
    elements.walletChain.textContent = "-";
    return;
  }

  const accounts = await window.ethereum.request({ method: "eth_accounts" });
  const chainIdHex = await window.ethereum.request({ method: "eth_chainId" });

  state.signerAddress = accounts[0] ?? null;
  state.connectedChainId = Number.parseInt(chainIdHex, 16);

  elements.walletStatus.textContent = state.signerAddress ? "Connected" : "Disconnected";
  elements.walletAccount.textContent = state.signerAddress ?? "-";
  elements.walletChain.textContent = state.connectedChainId ? String(state.connectedChainId) : "-";
}

async function connectMetaMask() {
  if (!window.ethereum || !state.provider) {
    renderResult("MetaMask is not available in this browser.");
    return;
  }

  const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
  state.signerAddress = accounts[0] ?? null;
  await refreshWalletState();
}

async function switchNetwork() {
  if (!window.ethereum) {
    renderResult("MetaMask is not available in this browser.");
    return;
  }

  const networkKey = elements.networkSelect.value;
  const network = NETWORKS[networkKey];

  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: network.chainIdHex }]
    });
  } catch (error) {
    if (error.code === 4902 && network.addEthereumChain) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [network.addEthereumChain]
      });
    } else {
      renderResult(`Failed to switch network: ${error.message}`);
      return;
    }
  }

  await refreshWalletState();
}

async function generateTransactionPreview() {
  try {
    const payload = JSON.parse(elements.calldataEditor.value);
    const tx = await buildTransaction(payload);
    elements.transactionPreview.textContent = JSON.stringify(tx, null, 2);
    renderResult("Calldata generated successfully.");
  } catch (error) {
    renderResult(`Failed to generate calldata: ${error.message}`);
  }
}

async function performCall() {
  try {
    assertWalletConnected();
    assertExpectedNetwork();

    const payload = JSON.parse(elements.calldataEditor.value);
    const tx = await buildTransaction(payload);
    const result = await window.ethereum.request({
      method: "eth_call",
      params: [
        {
          from: tx.from,
          to: tx.to,
          data: tx.data,
          value: tx.value
        },
        "latest"
      ]
    });

    const decoded = await decodeResult(payload, result);
    renderResult(JSON.stringify(decoded, null, 2));
    elements.transactionPreview.textContent = JSON.stringify(tx, null, 2);
  } catch (error) {
    renderResult(`eth_call failed: ${error.message}`);
  }
}

async function sendTransaction() {
  try {
    assertWalletConnected();
    assertExpectedNetwork();

    const payload = JSON.parse(elements.calldataEditor.value);
    const tx = await buildTransaction(payload);
    const txHash = await window.ethereum.request({
      method: "eth_sendTransaction",
      params: [tx]
    });

    renderResult(JSON.stringify({ txHash }, null, 2));
    elements.transactionPreview.textContent = JSON.stringify(tx, null, 2);
  } catch (error) {
    renderResult(`Transaction submission failed: ${error.message}`);
  }
}

async function buildTransaction(payload) {
  if (!state.deploymentManifest) {
    throw new Error("Deployment manifest is not loaded.");
  }

  const abi = await loadAbi(payload.abiFile);
  const iface = new Interface(abi);
  const contractAddress = state.deploymentManifest.contracts?.[payload.contractKey];

  if (!contractAddress) {
    throw new Error(`Missing contract address for key ${payload.contractKey}`);
  }

  const data = iface.encodeFunctionData(payload.method, payload.args ?? []);
  const value = payload.value ?? "0x0";

  return {
    from: state.signerAddress ?? undefined,
    to: contractAddress,
    data,
    value
  };
}

async function decodeResult(payload, rawResult) {
  const abi = await loadAbi(payload.abiFile);
  const iface = new Interface(abi);
  const decoded = iface.decodeFunctionResult(payload.method, rawResult);

  return Array.from(decoded, normalizeValue);
}

async function loadAbi(relativePath) {
  if (!state.abiCache.has(relativePath)) {
    state.abiCache.set(relativePath, fetchJson(relativePath));
  }

  return state.abiCache.get(relativePath);
}

function normalizeValue(value) {
  if (typeof value === "bigint") {
    return value.toString();
  }

  if (Array.isArray(value)) {
    return value.map(normalizeValue);
  }

  if (value && typeof value === "object") {
    const entries = Object.entries(value).filter(([key]) => Number.isNaN(Number(key)));
    return Object.fromEntries(entries.map(([key, item]) => [key, normalizeValue(item)]));
  }

  return value;
}

async function fetchJson(path) {
  const response = await fetch(path, { cache: "no-store" });

  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}`);
  }

  return response.json();
}

function assertWalletConnected() {
  if (!state.signerAddress) {
    throw new Error("Connect MetaMask before performing this action.");
  }
}

function assertExpectedNetwork() {
  const expectedChainId = NETWORKS[elements.networkSelect.value].chainId;

  if (state.connectedChainId !== expectedChainId) {
    throw new Error(`MetaMask is connected to chain ${state.connectedChainId ?? "-"}, expected ${expectedChainId}.`);
  }
}

function handleAccountsChanged(accounts) {
  state.signerAddress = accounts[0] ?? null;
  refreshWalletState().catch((error) => renderResult(error.message));
}

function handleChainChanged(chainIdHex) {
  state.connectedChainId = Number.parseInt(chainIdHex, 16);
  refreshWalletState().catch((error) => renderResult(error.message));
}

function renderResult(message) {
  elements.resultOutput.textContent =
    typeof message === "string" ? message : JSON.stringify(message, null, 2);
}
