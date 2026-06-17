import {
  assertAllowedCommandSchema,
  assertProviderChainIdMatchesNetwork,
  assertListLocalWalletsArgs,
  assertRecoverWalletArgs,
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
  requireCurrentTermsAcceptanceForCommand,
} from "../lib/runtime.mjs";

export const walletCommands = Object.freeze({
  "wallet-list": async (args) => {
    assertListLocalWalletsArgs(args);
    handleListLocalWallets({ args });
  },
  "wallet-export-backup": async (args) => {
    assertWalletExportBackupArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    handleWalletExportBackup({ args });
  },
  "wallet-export-viewing-key": async (args) => {
    assertWalletExportKeyArgs(args, "wallet-export-viewing-key");
    await requireCurrentTermsAcceptanceForCommand(args);
    await handleWalletExportKey({ args, keyKind: "viewing" });
  },
  "wallet-export-spending-key": async (args) => {
    assertWalletExportKeyArgs(args, "wallet-export-spending-key");
    await requireCurrentTermsAcceptanceForCommand(args);
    await handleWalletExportKey({ args, keyKind: "spending" });
  },
  "wallet-import-backup": async (args) => {
    assertWalletImportBackupArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    handleWalletImportBackup({ args });
  },
  "wallet-import-viewing-key": async (args) => {
    assertWalletImportKeyArgs(args, "wallet-import-viewing-key");
    await requireCurrentTermsAcceptanceForCommand(args);
    handleWalletImportKey({ args, keyKind: "viewing" });
  },
  "wallet-import-spending-key": async (args) => {
    assertWalletImportKeyArgs(args, "wallet-import-spending-key");
    await requireCurrentTermsAcceptanceForCommand(args);
    handleWalletImportKey({ args, keyKind: "spending" });
  },
  "wallet-recover-workspace": async (args) => {
    assertRecoverWalletArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
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
    assertAllowedCommandSchema(args, "wallet-deposit-channel");
    await requireCurrentTermsAcceptanceForCommand(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleGrothVaultMove({ args, provider, direction: "deposit" });
  },
  "wallet-withdraw-channel": async (args) => {
    assertAllowedCommandSchema(args, "wallet-withdraw-channel");
    await requireCurrentTermsAcceptanceForCommand(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleGrothVaultMove({ args, provider, direction: "withdraw" });
  },
});
