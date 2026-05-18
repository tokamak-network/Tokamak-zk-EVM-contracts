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
  prepareDeploymentArtifacts,
} from "../lib/runtime.mjs";

export const notesCommands = Object.freeze({
  "wallet-mint-notes": async (args) => {
    assertMintNotesArgs(args);
    const { network, provider } = loadWalletCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId, { mode: "full" });
    await handleMintNotes({ args, provider });
  },
  "wallet-redeem-notes": async (args) => {
    assertRedeemNotesArgs(args);
    const { network, provider } = loadWalletCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId, { mode: "full" });
    await handleRedeemNotes({ args, provider });
  },
  "wallet-get-notes": async (args) => {
    assertWalletGetNotesArgs(args);
    const { network, provider } = loadWalletCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId, { mode: "read-only" });
    await handleWalletGetNotes({ args, provider });
  },
  "wallet-transfer-notes": async (args) => {
    assertTransferNotesArgs(args);
    const { network, provider } = loadWalletCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId, { mode: "full" });
    await handleTransferNotes({ args, provider });
  },
});
