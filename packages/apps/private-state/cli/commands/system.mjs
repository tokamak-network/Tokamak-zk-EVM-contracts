import {
  assertDoctorArgs,
  assertGuideArgs,
  assertObserverArgs,
  assertInstallZkEvmArgs,
  assertSetRpcArgs,
  assertTransactionFeesArgs,
  assertUninstallArgs,
  assertUpdateArgs,
  handleDoctor,
  handleGuide,
  handleObserver,
  handleInstallZkEvm,
  handleSetRpc,
  handleTransactionFees,
  handleUninstall,
  handleUpdate,
  loadExplicitCommandRuntime,
} from "../lib/runtime.mjs";

export const systemCommands = Object.freeze({
  install: async (args) => {
    assertInstallZkEvmArgs(args);
    await handleInstallZkEvm({ args });
  },
  uninstall: async (args) => {
    assertUninstallArgs(args);
    await handleUninstall();
  },
  "set-rpc": async (args) => {
    assertSetRpcArgs(args);
    await handleSetRpc({ args });
  },
  "help-update": async (args) => {
    assertUpdateArgs(args);
    await handleUpdate();
  },
  "help-doctor": async (args) => {
    assertDoctorArgs(args);
    await handleDoctor({ args });
  },
  "help-guide": async (args) => {
    assertGuideArgs(args);
    await handleGuide({ args });
  },
  "help-observer": async (args) => {
    assertObserverArgs(args);
    handleObserver();
  },
  "help-transaction-fees": async (args) => {
    assertTransactionFeesArgs(args);
    const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args);
    await handleTransactionFees({ network, provider, rpcUrl });
  },
});
