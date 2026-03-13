export const APP_NETWORKS = {
  sepolia: {
    chainId: 11155111,
    displayName: "Sepolia",
    alchemyNetwork: "eth-sepolia"
  },
  mainnet: {
    chainId: 1,
    displayName: "Ethereum Mainnet",
    alchemyNetwork: "eth-mainnet"
  },
  "base-sepolia": {
    chainId: 84532,
    displayName: "Base Sepolia",
    alchemyNetwork: "base-sepolia"
  },
  "base-mainnet": {
    chainId: 8453,
    displayName: "Base Mainnet",
    alchemyNetwork: "base-mainnet"
  },
  "arb-sepolia": {
    chainId: 421614,
    displayName: "Arbitrum Sepolia",
    alchemyNetwork: "arb-sepolia"
  },
  "arb-mainnet": {
    chainId: 42161,
    displayName: "Arbitrum One",
    alchemyNetwork: "arb-mainnet"
  },
  "op-sepolia": {
    chainId: 11155420,
    displayName: "OP Sepolia",
    alchemyNetwork: "opt-sepolia"
  },
  "op-mainnet": {
    chainId: 10,
    displayName: "OP Mainnet",
    alchemyNetwork: "opt-mainnet"
  },
  anvil: {
    chainId: 31337,
    displayName: "anvil",
    defaultRpcUrl: "http://127.0.0.1:8545"
  }
};

export function resolveAppNetwork(networkName) {
  const network = APP_NETWORKS[networkName];

  if (!network) {
    throw new Error(`Unsupported APPS_NETWORK: ${networkName}`);
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
