export const APP_NETWORKS = {
  sepolia: {
    chainId: 11155111,
    displayName: "Sepolia",
    alchemyNetwork: "eth-sepolia",
    explorerTxBaseUrl: "https://sepolia.etherscan.io/tx"
  },
  mainnet: {
    chainId: 1,
    displayName: "Ethereum Mainnet",
    alchemyNetwork: "eth-mainnet",
    explorerTxBaseUrl: "https://etherscan.io/tx"
  },
  "base-sepolia": {
    chainId: 84532,
    displayName: "Base Sepolia",
    alchemyNetwork: "base-sepolia",
    explorerTxBaseUrl: "https://sepolia.basescan.org/tx"
  },
  "base-mainnet": {
    chainId: 8453,
    displayName: "Base Mainnet",
    alchemyNetwork: "base-mainnet",
    explorerTxBaseUrl: "https://basescan.org/tx"
  },
  "arb-sepolia": {
    chainId: 421614,
    displayName: "Arbitrum Sepolia",
    alchemyNetwork: "arb-sepolia",
    explorerTxBaseUrl: "https://sepolia.arbiscan.io/tx"
  },
  "arb-mainnet": {
    chainId: 42161,
    displayName: "Arbitrum One",
    alchemyNetwork: "arb-mainnet",
    explorerTxBaseUrl: "https://arbiscan.io/tx"
  },
  "op-sepolia": {
    chainId: 11155420,
    displayName: "OP Sepolia",
    alchemyNetwork: "opt-sepolia",
    explorerTxBaseUrl: "https://sepolia-optimism.etherscan.io/tx"
  },
  "op-mainnet": {
    chainId: 10,
    displayName: "OP Mainnet",
    alchemyNetwork: "opt-mainnet",
    explorerTxBaseUrl: "https://optimistic.etherscan.io/tx"
  },
  anvil: {
    chainId: 31337,
    displayName: "anvil",
    defaultRpcUrl: "http://127.0.0.1:8545"
  }
};

export const CLI_NETWORKS = {
  mainnet: APP_NETWORKS.mainnet,
  sepolia: APP_NETWORKS.sepolia,
  anvil: APP_NETWORKS.anvil
};

export function resolveAppNetwork(networkName) {
  const network = APP_NETWORKS[networkName];

  if (!network) {
    throw new Error(`Unsupported APPS_NETWORK: ${networkName}`);
  }

  return network;
}

export function resolveCliNetwork(networkName) {
  const network = CLI_NETWORKS[networkName];

  if (!network) {
    throw new Error(`Unsupported CLI network: ${networkName}. Allowed values: mainnet, sepolia, anvil.`);
  }

  return network;
}

export function deriveRpcUrl({ networkName, alchemyApiKey, rpcUrlOverride }) {
  if (rpcUrlOverride) {
    return rpcUrlOverride;
  }

  const network = resolveAppNetwork(networkName);

  if (network.defaultRpcUrl) {
    return network.defaultRpcUrl;
  }

  if (!alchemyApiKey) {
    throw new Error(`APPS_ALCHEMY_API_KEY is required for network ${networkName}`);
  }

  return `https://${network.alchemyNetwork}.g.alchemy.com/v2/${alchemyApiKey}`;
}
