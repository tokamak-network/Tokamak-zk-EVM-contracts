# Public Documentation Index

This index is the public entrypoint for repository documentation. It groups the official
white paper, bridge gas reference, DApp protocol documents, and audit support packets under the
top-level `docs/` tree.

## Core Documents

- [Tokamak Private App Channels White Paper](whitepaper.md)
  - Public narrative for the bridge model, DApp/channel policy surface, custody boundary, privacy
    model, security posture, and current operational policy.
- [Bridge Gas Assessment](bridge/gas-assessment.md)
  - Public gas-cost reference for bridge owner, operator, and user-facing calls, including the
    historical Ethereum gas-fee distribution used for USD estimates.

## DApp Documents

- [Private-State DApp Documentation](dapps/private-state/index.md)
  - Reading order for the private-state DApp protocol, contract specification, function
    constraints, security model, workflow, and channel workspace mirror protocol.
- [Private-State Background Theory](dapps/private-state/background-theory.md)
  - Conceptual model for custody, accounting balances, notes, commitments, nullifiers, and local
    secret material.
- [Private-State Contract Specification](dapps/private-state/contract-spec.md)
  - Mapping from the conceptual model to the current private-state contracts and public transition
    semantics.
- [Private-State Function Constraints](dapps/private-state/function-constraints.md)
  - Fixed-arity function shapes and validity constraints for mint, transfer, and redeem flows.
- [Private-State Security Model](dapps/private-state/security-model.md)
  - Bridge-inherited assumptions, wallet capability separation, note-receive key derivation, and
    collision-risk analysis.
- [Private-State Workflow](dapps/private-state/workflow.md)
  - CLI workflow, wallet and workspace artifacts, event recovery, proof input bundles, and
    bridge-DApp execution coupling.
- [Channel Workspace Mirror Protocol](dapps/private-state/channel-workspace-mirror-protocol.md)
  - Optional static server protocol for signed channel workspace checkpoints and delta bundles.

## Audit And Monitoring Documents

- [Monitoring Packet](audit/monitoring/Monitoring-Packet.md)
  - Data-backed public monitoring packet for contract addresses, public event surfaces, channel
    policy data, admin wallets, and user-controlled evidence boundaries.
- [Admin Wallets And Upgrade Policy](audit/monitoring/data/Admin-Wallets-and-Upgrade-Policy.md)
  - Monitoring packet companion document for privileged wallets, proxy ownership, implementation
    pointers, and upgrade policy.
- [Private-State Observability Matrix](audit/monitoring/data/Private-State-Observability-Matrix.md)
  - Public surface matrix for bridge edges, channel events, commitments, nullifiers, and encrypted
    note-delivery events.
- [User-Controlled Evidence Scope](audit/monitoring/data/User-Controlled-Evidence-Scope.md)
  - Scope statement for user-selected evidence packages and what they do or do not disclose.
- [Mainnet Deployment Audit Checklist](audit/mainnet-deploy/audit-for-mainnet-deploy.md)
  - Consolidated mainnet deployment security checklist and current deployment review status.

## Assets

- [Documentation Assets](assets/)
  - Charts, diagrams, and raw data used by the public white paper, gas assessment, and DApp
    security analysis.

## Developer References

Developer bridge notes remain outside this public documentation index under `bridge/docs/dev/`.
They are useful for implementation work and formal review, but they are not the public narrative
entrypoint.
