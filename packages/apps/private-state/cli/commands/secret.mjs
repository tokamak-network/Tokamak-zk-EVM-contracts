import {
  assertCreatePrivateKeySourceArgs,
  assertCreateWalletSecretSourceArgs,
  handleCreatePrivateKeySource,
  handleCreateWalletSecretSource,
  requireCurrentTermsAcceptanceForCommand,
} from "../lib/runtime.mjs";

export const secretCommands = Object.freeze({
  "secret-create-private-key-source": async (args) => {
    assertCreatePrivateKeySourceArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    await handleCreatePrivateKeySource({ args });
  },
  "secret-create-wallet-secret-source": async (args) => {
    assertCreateWalletSecretSourceArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    await handleCreateWalletSecretSource({ args });
  },
});
