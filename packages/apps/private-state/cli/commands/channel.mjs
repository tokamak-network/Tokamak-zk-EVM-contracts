import {
  assertCreateChannelArgs,
  assertExitChannelArgs,
  assertGetChannelArgs,
  assertJoinChannelArgs,
  assertProviderChainIdMatchesNetwork,
  assertPublishWorkspaceMirrorArgs,
  assertRecoverWorkspaceArgs,
  assertSetWorkspaceMirrorArgs,
  handleChannelCreate,
  handleExitChannel,
  handleGetChannel,
  handleJoinChannel,
  handlePublishChannelWorkspaceMirror,
  handleSetChannelWorkspaceMirror,
  handleWorkspaceInit,
  loadExplicitCommandRuntime,
  loadWalletCommandRuntime,
  prepareDeploymentArtifacts,
} from "../lib/runtime.mjs";

export const channelCommands = Object.freeze({
  "channel-create": async (args) => {
    assertCreateChannelArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handleChannelCreate({ args, network, provider });
  },
  "channel-recover-workspace": async (args) => {
    assertRecoverWorkspaceArgs(args);
    const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args, { staticNetwork: true });
    await assertProviderChainIdMatchesNetwork({ provider, network, rpcUrl });
    await prepareDeploymentArtifacts(network.chainId);
    await handleWorkspaceInit({ args, network, provider });
  },
  "channel-get-meta": async (args) => {
    assertGetChannelArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handleGetChannel({ args, network, provider });
  },
  "channel-set-workspace-mirror": async (args) => {
    assertSetWorkspaceMirrorArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handleSetChannelWorkspaceMirror({ args, network, provider });
  },
  "channel-publish-workspace-mirror": async (args) => {
    assertPublishWorkspaceMirrorArgs(args);
    const { network, provider } = loadExplicitCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handlePublishChannelWorkspaceMirror({ args, network, provider });
  },
  "channel-join": async (args) => {
    assertJoinChannelArgs(args);
    const { network, provider, rpcUrl } = loadExplicitCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handleJoinChannel({ args, network, provider, rpcUrl });
  },
  "channel-exit": async (args) => {
    assertExitChannelArgs(args);
    const { network, provider } = loadWalletCommandRuntime(args);
    await prepareDeploymentArtifacts(network.chainId);
    await handleExitChannel({ args, provider });
  },
});
