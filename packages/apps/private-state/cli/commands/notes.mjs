import {
  assertMintNotesArgs,
  assertRedeemNotesArgs,
  assertTransferNotesArgs,
  assertWalletGetNotesArgs,
  handleMintNotes,
  handleRedeemNotes,
  handleTransferNotes,
  handleWalletGetNotes,
  loadWalletCommandRuntime,
} from "../lib/runtime.mjs";

export const notesCommands = Object.freeze({
  "wallet-mint-notes": async (args) => {
    assertMintNotesArgs(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleMintNotes({ args, provider });
  },
  "wallet-redeem-notes": async (args) => {
    assertRedeemNotesArgs(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleRedeemNotes({ args, provider });
  },
  "wallet-get-notes": async (args) => {
    assertWalletGetNotesArgs(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleWalletGetNotes({ args, provider });
  },
  "wallet-transfer-notes": async (args) => {
    assertTransferNotesArgs(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleTransferNotes({ args, provider });
  },
});
