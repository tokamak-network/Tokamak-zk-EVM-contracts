import {
  assertCreateChannelArgs,
  assertAbandonChannelOperationArgs,
  assertExitChannelArgs,
  assertGetChannelArgs,
  assertJoinChannelArgs,
  assertProviderChainIdMatchesNetwork,
  assertRecoverWorkspaceArgs,
  assertSetWorkspaceMirrorArgs,
  handleChannelCreate,
  handleAbandonChannelOperation,
  handleExitChannel,
  handleGetChannel,
  handleJoinChannel,
  handleSetChannelWorkspaceMirror,
  handleWorkspaceInit,
  loadExplicitCommandRuntime,
  loadWalletCommandRuntime,
} from "../lib/runtime.mjs";

export const channelCommands = Object.freeze({
  "channel-create": async (args) => {
    assertCreateChannelArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args, { prepareArtifacts: true });
    await handleChannelCreate({ args, network, provider });
  },
  "channel-recover-workspace": async (args) => {
    assertRecoverWorkspaceArgs(args);
    const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args, { staticNetwork: true, prepareArtifacts: true });
    await assertProviderChainIdMatchesNetwork({ provider, network, rpcUrl });
    await handleWorkspaceInit({ args, network, provider });
  },
  "channel-get-meta": async (args) => {
    assertGetChannelArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args, { prepareArtifacts: true });
    await handleGetChannel({ args, network, provider });
  },
  "channel-set-workspace-mirror": async (args) => {
    assertSetWorkspaceMirrorArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args, { prepareArtifacts: true });
    await handleSetChannelWorkspaceMirror({ args, network, provider });
  },
  "channel-abandon-operation": async (args) => {
    assertAbandonChannelOperationArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args, { prepareArtifacts: true });
    await handleAbandonChannelOperation({ args, network, provider });
  },
  "channel-join": async (args) => {
    assertJoinChannelArgs(args);
    const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args, { prepareArtifacts: true });
    await handleJoinChannel({ args, network, provider, rpcUrl });
  },
  "channel-exit": async (args) => {
    assertExitChannelArgs(args);
    const { provider } = loadWalletCommandRuntime(args, { prepareArtifacts: true });
    await handleExitChannel({ args, provider });
  },
});
