export const PRIVATE_STATE_CLI_FIELD_CATALOG = Object.freeze({
  channelName: {
    label: "Channel Name",
    type: "text",
    placeholder: "demo-channel",
    valueLabel: "<NAME>",
    option: "--channel-name",
  },
  network: {
    label: "Network",
    type: "select",
    options: ["sepolia", "mainnet", "anvil"],
    valueLabel: "<NAME>",
    option: "--network",
  },
  rpcUrl: {
    label: "RPC URL",
    type: "password",
    placeholder: "https://example-rpc",
    valueLabel: "<URL>",
    hint: "Optional. When omitted, the CLI reads RPC_URL from ~/tokamak-private-channels/secrets/<network>/.env.",
    option: "--rpc-url",
    optional: true,
  },
  account: {
    label: "Account",
    type: "text",
    placeholder: "my-account",
    valueLabel: "<NAME>",
    option: "--account",
  },
  txSubmitter: {
    label: "Transaction Submitter",
    type: "text",
    placeholder: "relayer-account",
    valueLabel: "<ACCOUNT>",
    hint: "Optional for proof-backed note commands. Uses a separate local L1 account to submit executeChannelTransaction.",
    option: "--tx-submitter",
    optional: true,
  },
  privateKeyFile: {
    label: "Private Key File",
    type: "text",
    placeholder: "/path/to/private-key",
    valueLabel: "<PATH>",
    hint: "Source file permissions are not enforced; the imported canonical account secret is protected.",
    option: "--private-key-file",
  },
  joinToll: {
    label: "Join Toll",
    type: "text",
    placeholder: "1",
    valueLabel: "<TOKENS>",
    option: "--join-toll",
  },
  walletSecretPath: {
    label: "Wallet Secret File",
    type: "text",
    placeholder: "/path/to/wallet-secret",
    valueLabel: "<PATH>",
    hint: "Source file permissions are not enforced; the imported wallet-local secret is protected.",
    option: "--wallet-secret-path",
  },
  wallet: {
    label: "Wallet Name",
    type: "text",
    placeholder: "channel-0xYourL1Address",
    valueLabel: "<NAME>",
    option: "--wallet",
  },
  amount: {
    label: "Amount",
    type: "text",
    placeholder: "3",
    valueLabel: "<TOKENS>",
    option: "--amount",
  },
  amounts: {
    label: "Amounts",
    type: "textarea",
    placeholder: "[1,2,3]",
    valueLabel: "<A,B,...>",
    option: "--amounts",
  },
  noteIds: {
    label: "Note IDs",
    type: "textarea",
    placeholder: "[\"0x...\"]",
    valueLabel: "<ID,ID,...>",
    option: "--note-ids",
  },
  recipients: {
    label: "Recipients JSON",
    type: "textarea",
    placeholder: "[\"0xRecipientL2Address\"]",
    valueLabel: "<ADDR,ADDR,...>",
    option: "--recipients",
  },
  docker: {
    label: "Docker Install Mode",
    type: "checkbox",
    hint: "Forward --docker to install. This mode is supported only on Linux hosts by the Tokamak CLI.",
    option: "--docker",
    optional: true,
  },
  includeLocalArtifacts: {
    label: "Include Local Artifacts",
    type: "checkbox",
    hint: "Also install local deployment/ artifacts from the current working directory.",
    option: "--include-local-artifacts",
    optional: true,
  },
  groth16CliVersion: {
    label: "Groth16 CLI Version",
    type: "text",
    placeholder: "0.2.0",
    option: "--groth16-cli-version",
    valueLabel: "<VERSION>",
    optional: true,
  },
  tokamakZkEvmCliVersion: {
    label: "Tokamak zk-EVM CLI Version",
    type: "text",
    placeholder: "2.0.16",
    option: "--tokamak-zk-evm-cli-version",
    valueLabel: "<VERSION>",
    optional: true,
  },
  fromGenesis: {
    label: "Scan From Genesis",
    type: "checkbox",
    hint: "Ignore the local recovery index and replay channel logs from genesis.",
    option: "--from-genesis",
    optional: true,
  },
  json: {
    label: "JSON Output",
    type: "checkbox",
    hint: "Print the command result as JSON.",
    option: "--json",
    optional: true,
  },
  gpu: {
    label: "Live GPU Probe",
    type: "checkbox",
    hint: "Run live NVIDIA and Docker GPU probes during doctor.",
    option: "--gpu",
    optional: true,
  },
});

export const PRIVATE_STATE_CLI_COMMANDS = Object.freeze([
  {
    id: "install",
    description: "Install the Tokamak zk-EVM CLI runtime, Groth16 runtime, and private-state deployment artifacts.",
    fields: ["docker", "includeLocalArtifacts", "groth16CliVersion", "tokamakZkEvmCliVersion"],
    usage: "optional --docker, --include-local-artifacts, --groth16-cli-version, and --tokamak-zk-evm-cli-version",
    help: [
      "Version options install exact CLI package versions; omitted versions resolve to npm registry latest",
      "Use --docker on Linux to forward Docker mode to the Tokamak zk-EVM and Groth16 runtimes",
      "Use --include-local-artifacts to also install local deployment/ artifacts from the current working directory",
    ],
  },
  {
    id: "uninstall",
    description: "Interactively remove local private-state workspaces, wallet secrets, proof artifacts, Tokamak zk-EVM runtime data, and the global CLI package when installed.",
    fields: [],
    usage: "no options",
  },
  {
    id: "doctor",
    description: "Check private-state CLI package versions, runtime install state, Docker mode, CUDA mode, and deployment artifacts.",
    fields: ["gpu", "json"],
    usage: "optional --gpu and optional --json",
    help: [
      "Prints a concise human-readable table by default; use --json for the full machine-readable report",
      "Use --gpu to run live NVIDIA/Docker GPU probes",
    ],
  },
  {
    id: "guide",
    description: "Inspect local CLI state and available on-chain state, then print the next safe command.",
    fields: ["network", "channelName", "account", "wallet"],
    optionalFields: ["network", "channelName", "account", "wallet"],
    usage: "optional --network, --channel-name, --account, and --wallet",
    help: ["Does not accept --rpc-url and never writes RPC configuration"],
  },
  {
    id: "transaction-fees",
    description: "Estimate ETH and USD fees for transaction-sending commands from packaged measured gas data and live network fee data.",
    fields: ["network", "rpcUrl", "json"],
    usage: "--network, optional --rpc-url, and optional --json",
    help: [
      "Uses packages/apps/private-state/cli/assets/tx-fees.json as the measured gas source packaged with the CLI",
      "Reads live fee data from the selected network RPC and live ETH/USD from CoinGecko",
    ],
  },
  {
    id: "account-import",
    display: "account import",
    description: "Import a private-key source file into a protected local L1 account secret for later --account use.",
    fields: ["account", "network", "privateKeyFile"],
    usage: "--account, --network, and --private-key-file",
  },
  {
    id: "create-channel",
    description: "Create a bridge channel and initialize its workspace.",
    fields: ["channelName", "joinToll", "network", "account", "rpcUrl"],
    usage: "--channel-name, --join-toll, --network, --account, and optional --rpc-url",
    help: ["Prints the immutable policy snapshot before sending the transaction"],
  },
  {
    id: "recover-workspace",
    description: "Rebuild the local channel workspace from bridge state.",
    fields: ["channelName", "network", "fromGenesis", "rpcUrl"],
    usage: "--channel-name, --network, optional --from-genesis, and optional --rpc-url",
    help: [
      "By default, resumes RPC log scanning from the workspace recovery index when available",
      "Use --from-genesis to ignore the recovery index and replay logs from channel genesis",
      "Prints RPC log scan progress while rebuilding the workspace",
    ],
  },
  {
    id: "get-channel",
    description: "Read channel existence, manager, vault, toll, refund schedule, and immutable policy snapshot.",
    fields: ["channelName", "network", "rpcUrl"],
    usage: "--channel-name, --network, and optional --rpc-url",
  },
  {
    id: "deposit-bridge",
    description: "Deposit canonical tokens into the shared bridge vault.",
    fields: ["amount", "network", "account", "rpcUrl"],
    usage: "--amount, --network, --account, and optional --rpc-url",
  },
  {
    id: "withdraw-bridge",
    description: "Withdraw tokens from the shared bridge vault back to the wallet.",
    fields: ["amount", "network", "account", "rpcUrl"],
    usage: "--amount, --network, --account, and optional --rpc-url",
  },
  {
    id: "get-my-bridge-fund",
    description: "Read the current shared bridge vault balance.",
    fields: ["network", "account", "rpcUrl"],
    usage: "--network, --account, and optional --rpc-url",
  },
  {
    id: "recover-wallet",
    description: "Rebuild a recoverable local wallet from on-chain channel state.",
    fields: ["channelName", "network", "account", "rpcUrl"],
    usage: "--channel-name, --network, --account, and optional --rpc-url",
    help: [
      "Requires the protected wallet-local secret imported during join-channel to exist at the canonical secret path",
      "Does not create or recover the wallet secret itself",
      "Prints RPC log scan progress while rebuilding channel state and received-note state",
    ],
  },
  {
    id: "join-channel",
    description: "Pay the channel join toll and bind a wallet to a channel-specific L2 identity.",
    fields: ["channelName", "network", "account", "walletSecretPath", "rpcUrl"],
    usage: "--channel-name, --network, --account, --wallet-secret-path, and optional --rpc-url",
    help: [
      "--wallet-secret-path imports an existing source secret file into the protected wallet-local secret file",
      "Prints the immutable policy snapshot before first registration",
    ],
  },
  {
    id: "get-my-wallet-meta",
    description: "Check whether a wallet matches the on-chain channel registration.",
    fields: ["wallet", "network"],
    usage: "--wallet and --network",
  },
  {
    id: "get-my-l1-address",
    description: "Derive the L1 address for a private key.",
    fields: ["account", "network"],
    usage: "--network and --account",
  },
  {
    id: "list-local-wallets",
    description: "List saved local wallet names that can be reused with --wallet.",
    fields: ["network", "channelName"],
    optionalFields: ["network", "channelName"],
    usage: "optional --network and --channel-name",
  },
  {
    id: "deposit-channel",
    description: "Move bridged funds into the channel L2 accounting balance.",
    fields: ["wallet", "network", "amount"],
    usage: "--wallet, --network, and --amount",
  },
  {
    id: "withdraw-channel",
    description: "Move channel L2 balance back into the shared bridge vault.",
    fields: ["wallet", "network", "amount"],
    usage: "--wallet, --network, and --amount",
  },
  {
    id: "get-my-channel-fund",
    description: "Read the current channel L2 accounting balance.",
    fields: ["wallet", "network"],
    usage: "--wallet and --network",
  },
  {
    id: "exit-channel",
    description: "Exit a channel. Both the CLI and bridge contract require a zero channel balance.",
    fields: ["wallet", "network"],
    usage: "--wallet and --network",
  },
  {
    id: "mint-notes",
    description: "Mint one or two private-state notes from the wallet's channel balance.",
    fields: ["wallet", "network", "amounts", "txSubmitter"],
    usage: "--wallet, --network, --amounts, and optional --tx-submitter",
    help: ["Use --tx-submitter <ACCOUNT> to let a separate local L1 account pay gas for stronger transaction privacy"],
  },
  {
    id: "transfer-notes",
    description: "Spend input notes into the registered 1->1, 1->2, or 2->1 private transfer shapes.",
    fields: ["wallet", "network", "noteIds", "recipients", "amounts", "txSubmitter"],
    usage: "--wallet, --network, --note-ids, --recipients, --amounts, and optional --tx-submitter",
    help: ["Use --tx-submitter <ACCOUNT> to let a separate local L1 account pay gas for stronger transaction privacy"],
  },
  {
    id: "redeem-notes",
    description: "Redeem one tracked note back into the wallet's channel balance.",
    fields: ["wallet", "network", "noteIds", "txSubmitter"],
    usage: "--wallet, --network, --note-ids, and optional --tx-submitter",
    help: ["Use --tx-submitter <ACCOUNT> to let a separate local L1 account pay gas for stronger transaction privacy"],
  },
  {
    id: "get-my-notes",
    description: "Show the wallet's tracked note state and refresh received notes.",
    fields: ["wallet", "network"],
    usage: "--wallet and --network",
  },
]);

export function privateStateCliCommandDisplay(command) {
  return command.display ?? command.id;
}

export function privateStateCliCommandOptionKeys(command) {
  return ["command", "positional", ...command.fields];
}

export function privateStateCliCommandRequiredOptionKeys(command) {
  const optionalFields = new Set(command.optionalFields ?? []);
  return command.fields.filter((fieldKey) => {
    const field = PRIVATE_STATE_CLI_FIELD_CATALOG[fieldKey];
    return field?.optional !== true
      && field?.type !== "checkbox"
      && !optionalFields.has(fieldKey);
  });
}

export function privateStateCliCommandSynopsis(command) {
  const display = privateStateCliCommandDisplay(command);
  const optionalFields = new Set(command.optionalFields ?? []);
  const options = command.fields
    .filter((fieldKey) => fieldKey !== "json")
    .map((fieldKey) => {
      const field = PRIVATE_STATE_CLI_FIELD_CATALOG[fieldKey];
      if (!field?.option) {
        return null;
      }
      const valueLabel = field.valueLabel ?? field.placeholderLabel ?? `<${field.label?.toUpperCase().replace(/\s+/g, "_") ?? "VALUE"}>`;
      const option = field.type === "checkbox" || fieldKey === "fromGenesis"
        ? field.option
        : `${field.option} ${valueLabel}`;
      return field.optional || optionalFields.has(fieldKey) ? `[${option}]` : option;
    })
    .filter(Boolean);
  return [display, ...options].join(" ");
}
