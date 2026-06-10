import {
  assertAccountGetBridgeFundArgs,
  assertAccountGetL1AddressArgs,
  assertAccountImportArgs,
  assertDepositBridgeArgs,
  assertWithdrawBridgeArgs,
  handleAccountGetBridgeFund,
  handleAccountGetL1Address,
  handleAccountImport,
  handleDepositBridge,
  handleWithdrawBridge,
  loadExplicitCommandRuntime,
  requireCurrentTermsAcceptanceForCommand,
} from "../lib/runtime.mjs";

export const accountCommands = Object.freeze({
  "account-get-l1-address": async (args) => {
    assertAccountGetL1AddressArgs(args);
    handleAccountGetL1Address({ args });
  },
  "account-import": async (args) => {
    assertAccountImportArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    handleAccountImport({ args });
  },
  "account-get-bridge-fund": async (args) => {
    assertAccountGetBridgeFundArgs(args);
    const { provider } = loadExplicitCommandRuntime(args, { prepareArtifacts: true });
    await handleAccountGetBridgeFund({ args, provider });
  },
  "account-deposit-bridge": async (args) => {
    assertDepositBridgeArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    const { network, provider } = loadExplicitCommandRuntime(args, { prepareArtifacts: true });
    await handleDepositBridge({ args, network, provider });
  },
  "account-withdraw-bridge": async (args) => {
    assertWithdrawBridgeArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    const { network, provider } = loadExplicitCommandRuntime(args, { prepareArtifacts: true });
    await handleWithdrawBridge({ args, network, provider });
  },
});
