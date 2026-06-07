import {
  assertCreatePrivateKeySourceArgs,
  assertCreateWalletSecretSourceArgs,
  handleCreatePrivateKeySource,
  handleCreateWalletSecretSource,
} from "../lib/runtime.mjs";

export const secretCommands = Object.freeze({
  "secret-create-private-key-source": async (args) => {
    assertCreatePrivateKeySourceArgs(args);
    await handleCreatePrivateKeySource({ args });
  },
  "secret-create-wallet-secret-source": async (args) => {
    assertCreateWalletSecretSourceArgs(args);
    await handleCreateWalletSecretSource({ args });
  },
});
