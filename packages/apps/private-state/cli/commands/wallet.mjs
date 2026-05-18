import {
  assertProviderChainIdMatchesNetwork,
  assertListLocalWalletsArgs,
  assertRecoverWalletArgs,
  assertWalletChannelMoveArgs,
  assertWalletExportBackupArgs,
  assertWalletExportKeyArgs,
  assertWalletGetChannelFundArgs,
  assertWalletGetMetaArgs,
  assertWalletImportBackupArgs,
  assertWalletImportKeyArgs,
  handleGrothVaultMove,
  handleListLocalWallets,
  handleRecoverWallet,
  handleWalletExportBackup,
  handleWalletExportKey,
  handleWalletGetChannelFund,
  handleWalletGetMeta,
  handleWalletImportBackup,
  handleWalletImportKey,
  loadExplicitCommandRuntime,
  loadWalletCommandRuntime,
} from "../lib/runtime.mjs";

export const walletCommands = Object.freeze({
  "wallet-list": async (args) => {
    assertListLocalWalletsArgs(args);
    handleListLocalWallets({ args });
  },
  "wallet-export-backup": async (args) => {
    assertWalletExportBackupArgs(args);
    handleWalletExportBackup({ args });
  },
  "wallet-export-viewing-key": async (args) => {
    assertWalletExportKeyArgs(args, "wallet-export-viewing-key");
    handleWalletExportKey({ args, keyKind: "viewing" });
  },
  "wallet-export-spending-key": async (args) => {
    assertWalletExportKeyArgs(args, "wallet-export-spending-key");
    handleWalletExportKey({ args, keyKind: "spending" });
  },
  "wallet-import-backup": async (args) => {
    assertWalletImportBackupArgs(args);
    handleWalletImportBackup({ args });
  },
  "wallet-import-viewing-key": async (args) => {
    assertWalletImportKeyArgs(args, "wallet-import-viewing-key");
    handleWalletImportKey({ args, keyKind: "viewing" });
  },
  "wallet-import-spending-key": async (args) => {
    assertWalletImportKeyArgs(args, "wallet-import-spending-key");
    handleWalletImportKey({ args, keyKind: "spending" });
  },
  "wallet-recover-workspace": async (args) => {
    assertRecoverWalletArgs(args);
    const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args, { staticNetwork: true, prepareArtifacts: true });
    await assertProviderChainIdMatchesNetwork({ provider, network, rpcUrl });
    await handleRecoverWallet({ args, network, provider, rpcUrl });
  },
  "wallet-get-meta": async (args) => {
    assertWalletGetMetaArgs(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleWalletGetMeta({ args, provider });
  },
  "wallet-get-channel-fund": async (args) => {
    assertWalletGetChannelFundArgs(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleWalletGetChannelFund({ args, provider });
  },
  "wallet-deposit-channel": async (args) => {
    assertWalletChannelMoveArgs(args, "wallet-deposit-channel");
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleGrothVaultMove({ args, provider, direction: "deposit" });
  },
  "wallet-withdraw-channel": async (args) => {
    assertWalletChannelMoveArgs(args, "wallet-withdraw-channel");
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleGrothVaultMove({ args, provider, direction: "withdraw" });
  },
});
