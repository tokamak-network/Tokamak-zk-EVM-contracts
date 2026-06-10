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
  requireCurrentTermsAcceptanceForCommand,
} from "../lib/runtime.mjs";

export const notesCommands = Object.freeze({
  "wallet-mint-notes": async (args) => {
    assertMintNotesArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleMintNotes({ args, provider });
  },
  "wallet-redeem-notes": async (args) => {
    assertRedeemNotesArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleRedeemNotes({ args, provider });
  },
  "wallet-get-notes": async (args) => {
    assertWalletGetNotesArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleWalletGetNotes({ args, provider });
  },
  "wallet-transfer-notes": async (args) => {
    assertTransferNotesArgs(args);
    await requireCurrentTermsAcceptanceForCommand(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleTransferNotes({ args, provider });
  },
});
