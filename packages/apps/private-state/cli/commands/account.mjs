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
  prepareDeploymentArtifacts,
} from "../lib/runtime.mjs";

export const accountCommands = Object.freeze({
  "account-get-l1-address": async (args) => {
    assertAccountGetL1AddressArgs(args);
    handleAccountGetL1Address({ args });
  },
  "account-import": async (args) => {
    assertAccountImportArgs(args);
    handleAccountImport({ args });
  },
  "account-get-bridge-fund": async (args) => {
    assertAccountGetBridgeFundArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handleAccountGetBridgeFund({ args, provider });
  },
  "account-deposit-bridge": async (args) => {
    assertDepositBridgeArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handleDepositBridge({ args, network, provider });
  },
  "account-withdraw-bridge": async (args) => {
    assertWithdrawBridgeArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handleWithdrawBridge({ args, network, provider });
  },
});
