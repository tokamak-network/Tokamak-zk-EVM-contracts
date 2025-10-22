# Dispute System Documentation

## Overview

The Tokamak zkRollup bridge implements a robust dispute resolution system designed to ensure the integrity of off-chain computations and protect participants from malicious behavior. The system operates on the principle that disputes can only be raised against channel leaders, who are responsible for submitting valid proofs and managing channel operations. This streamlined approach reduces complexity while maintaining strong security guarantees through economic incentives and automated enforcement mechanisms.

## Architecture and Design Principles

The dispute system is built around a two-phase channel closure process that provides participants with sufficient time to verify and challenge any suspicious activity. When a channel leader initiates closure by calling `closeChannel()`, the channel transitions to a dispute period rather than immediately closing. This dispute period lasts for 14 days, during which any channel participant can raise disputes against the leader's actions or proof submissions.

The system distinguishes between two critical time windows that govern dispute resolution. The challenge period of 14 days determines how long participants have to raise disputes after a channel closure is initiated. Simultaneously, the dispute timeout of 14 days sets the maximum duration for resolving any pending disputes. This parallel timing structure ensures that disputes cannot be used to indefinitely delay channel finalization while still providing adequate time for proper investigation.

## Dispute Lifecycle and State Management

Channel participants can raise disputes against leaders only during the active dispute period, which begins when `closeChannel()` is called and the channel enters the `Dispute` state. Disputes are always directed toward the channel leader, reflecting their role as the primary party responsible for proof validity and channel management. Each dispute contains evidence, a description of the alleged misconduct, and is timestamped to enable proper timeout enforcement.

Once raised, disputes enter a pending state where they await resolution by the contract owner. The owner serves as an arbitrator who can examine the evidence and determine whether the dispute is valid. If a dispute is resolved in favor of the accuser, indicating that the leader committed misconduct, the system automatically enables emergency mode for the affected channel. This immediate response protects participants by allowing them to recover their funds through emergency withdrawal mechanisms.

## Automatic Timeout and Resolution

The dispute system incorporates sophisticated timeout logic to prevent disputes from blocking channel finalization indefinitely. Disputes that remain unresolved for more than 14 days are automatically considered rejected, allowing normal channel operations to proceed. This automatic timeout mechanism is implemented through the `hasResolvedDisputesAgainstLeader()` function, which evaluates both the dispute status and timing when determining whether channel finalization can proceed.

The timeout calculation considers the dispute creation timestamp and compares it against the current block time to determine expiration. This design ensures that even if disputes are raised near the end of the challenge period, they still receive adequate time for investigation. However, expired disputes do not prevent channel finalization, maintaining system liveness while preserving security.

## Leader Bond Integration and Economic Security

The dispute system is tightly integrated with the leader bond mechanism, creating strong economic incentives for honest behavior. When disputes are resolved against a leader, their bond is automatically slashed and added to the pool of recoverable funds managed by the treasury system. This economic penalty serves as both punishment for misconduct and compensation for the disruption caused to other participants.

Leaders cannot reclaim their bonds while disputes remain pending or after disputes have been resolved against them. The `reclaimLeaderBond()` function explicitly checks for resolved disputes through the same timeout logic used for channel finalization, ensuring consistent enforcement across all system components. This integration creates a comprehensive accountability framework where economic incentives align with security requirements.

## Emergency Mode Activation and Participant Protection

When disputes are resolved against leaders, the system automatically transitions the affected channel into emergency mode. This state change enables all participants to recover their deposited funds through emergency withdrawal mechanisms, bypassing the normal proof-based withdrawal process that might be compromised. Emergency mode serves as a safety valve that protects participant funds when the standard channel operation cannot be trusted.

The automatic activation of emergency mode upon dispute resolution demonstrates the system's protective bias toward participants. Rather than requiring additional manual steps or governance decisions, the technical resolution of a dispute immediately triggers participant protection mechanisms. This design choice prioritizes fund safety and reduces the potential for further complications or delays in dispute resolution.

## State Machine Enforcement and Finalization Logic

The dispute system fundamentally alters the channel state machine to enforce proper timing and resolution procedures. Channels cannot transition from the `Dispute` state to the `Closed` state until both the challenge period has expired and no pending or resolved disputes exist against the leader. The `finalizeChannel()` function serves as the gatekeeper for this transition, implementing comprehensive checks before allowing normal channel conclusion.

This state machine design ensures that disputes receive proper consideration and resolution before channels can be finalized. The system prevents premature finalization while maintaining clear progression rules that avoid indefinite delays. Participants benefit from guaranteed dispute periods, while the overall system maintains efficiency through automatic timeout and resolution mechanisms.

## Security Guarantees and Trust Assumptions

The dispute system operates under the assumption that at least one honest participant will monitor channel activity and raise disputes when necessary. This assumption is reasonable given that participants have economic incentives to protect their deposited funds and that dispute raising does not require significant technical expertise or resources. The 14-day challenge period provides ample time for detection and response to suspicious activity.

The system's security also relies on the integrity of the contract owner who serves as the dispute arbitrator. While this introduces a degree of centralization, it enables rapid dispute resolution and provides clear accountability for arbitration decisions. Future iterations of the system might incorporate more decentralized arbitration mechanisms, but the current design prioritizes practical dispute resolution over complete decentralization.

The dispute timeout mechanism ensures system liveness even in scenarios where arbitration fails or becomes unavailable. This feature prevents the system from becoming permanently stuck due to unresolved disputes while still providing meaningful protection against misconduct. The balance between security and liveness represents a careful design choice that prioritizes overall system functionality while maintaining essential protections for participants.