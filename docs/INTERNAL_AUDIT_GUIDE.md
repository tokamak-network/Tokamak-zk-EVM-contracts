# Internal Audit Guide - Tokamak zkRollup Bridge

## Overview

This document provides guidance for internal auditors reviewing the Tokamak zkRollup bridge implementation. It outlines expected system behaviors, design decisions that may appear unusual but are intentional, and potential findings that should not be considered security issues. Understanding these design choices is crucial for conducting an effective audit that focuses on genuine vulnerabilities rather than architectural decisions.

## Expected Behaviors and Design Decisions

### State Machine Progression and Timing

The bridge implements a multi-stage channel lifecycle with specific timing requirements that may initially appear restrictive but serve important security purposes. Channels progress through `Initialized`, `Open`, `Active`, `Closing`, `Dispute`, and finally `Closed` states, with mandatory waiting periods between certain transitions. The 14-day dispute period after channel closure is intentionally long to accommodate participants who may not monitor the system continuously. This extended period should not be flagged as excessive, as it provides essential security guarantees for participants who rely on the dispute mechanism for protection.

The system requires channels to remain in the `Dispute` state for the full challenge period even when no disputes are raised. This behavior ensures consistent timing across all channels and prevents timing-based attacks where malicious leaders might attempt to bypass dispute periods through specific timing manipulations. Auditors should not consider this mandatory waiting period as inefficient, as it represents a fundamental security feature rather than a performance limitation.

### Leader Bond and Slashing Mechanisms

The leader bond system requires a fixed 1 ETH deposit from channel leaders, which may seem arbitrary but was chosen to balance accessibility with meaningful economic incentives. The bond amount is not configurable by design, as dynamic bonding could introduce complexity and potential manipulation vectors. The fixed amount ensures predictable economics for all participants and simplifies the dispute resolution calculations.

When leader bonds are slashed, the funds are not immediately distributed but instead accumulate in the contract for later withdrawal by the treasury. This design prevents immediate redistribution that could complicate accounting and introduces a controlled process for managing slashed funds. The treasury withdrawal mechanism requires owner intervention, which is intentional centralization that enables proper fund management and prevents automated distributions that might be exploited.

### Emergency Mode and Withdrawal Patterns

Emergency mode can be activated automatically through dispute resolution or manually by the contract owner, creating dual pathways for participant protection. This redundancy is intentional and provides both automated responses to detected issues and manual intervention capabilities for unforeseen circumstances. The ability for the owner to manually enable emergency mode should not be considered excessive centralization, as it serves as a critical safety mechanism when automated systems may be insufficient.

The emergency withdrawal mechanism bypasses normal proof verification requirements and allows direct fund recovery based on deposit records. This apparent circumvention of the proof system is intentional for emergency scenarios where the standard verification process may be compromised. Emergency withdrawals are mutually exclusive with normal withdrawals to prevent double-spending, and this restriction should be viewed as a security feature rather than a limitation.

### Merkle Tree Operations and Root Management

The embedded Merkle tree implementation maintains multiple root versions and allows for non-sequential leaf additions in certain circumstances. This flexibility supports the dynamic nature of zkRollup state management and accommodates various proof generation strategies. The apparent complexity of root management is necessary for maintaining consistency across different proof submission patterns and should not be simplified without careful consideration of the cryptographic requirements.

The system caches intermediate tree nodes and maintains subtree information for gas optimization purposes. This caching mechanism introduces apparent redundancy in storage but significantly reduces computational costs for participants. The trade-off between storage efficiency and computational performance was deliberately chosen to favor user experience over contract storage optimization.

### Access Control and Permission Systems

The contract implements role-based access control with the owner having significant privileges across various functions. This centralization is intentional during the initial deployment phase and provides necessary flexibility for system management and emergency response. The concentration of permissions in the owner role should not be immediately flagged as excessive centralization without considering the operational requirements of a complex bridging system.

Certain functions are restricted to specific participant roles, such as leaders being able to initialize channel states and submit proofs. These restrictions reflect the economic and operational responsibilities associated with different participant types and should be evaluated in the context of the overall incentive structure rather than viewed as arbitrary access limitations.

## Potential Non-Issues and Expected Findings

### Gas Consumption and Performance Characteristics

High gas consumption during channel operations, particularly for proof submission and verification, is expected given the cryptographic complexity involved. Gas costs that appear excessive should be evaluated against the computational requirements of zero-knowledge proof verification rather than compared to simple transfer operations. The system prioritizes security and correctness over gas optimization in critical operations.

Batch operations that process multiple participants or proofs simultaneously may consume significant gas but provide necessary functionality for channel management. These operations should be evaluated for their efficiency relative to alternative approaches rather than flagged simply for high gas usage.

### State Consistency and Update Patterns

The system maintains consistency across multiple state variables that track overlapping information, such as participant lists, deposit amounts, and channel status. This apparent redundancy serves important purposes for gas optimization and query efficiency, and should not be considered unnecessary duplication without careful analysis of the access patterns and performance requirements.

Certain state updates may appear to occur in non-atomic patterns due to the complex nature of multi-participant operations. The system carefully manages these updates to maintain consistency while accommodating the various failure modes that can occur during complex operations involving multiple external calls and state changes.

### Timing Dependencies and Block Number Usage

The contract relies on block timestamps for various timing calculations, including dispute periods and channel timeouts. This dependency on block time is acceptable for the time scales involved in bridge operations and should not be flagged as a precision issue unless the timing requirements are more stringent than the intended use cases.

The system does not implement strict block number-based timing due to the variability in block times across different networks. The use of timestamp-based calculations provides more predictable timing behavior for participants and should be considered appropriate for the operational context.

### External Contract Dependencies and Integration Points

The bridge integrates with external verifier contracts and token contracts, creating dependencies that may appear to introduce trust assumptions. These integrations are necessary for the system's functionality and are designed with appropriate safety checks and fallback mechanisms. The external dependencies should be evaluated for their specific implementation rather than flagged generically as trust issues.

The system makes external calls to user-provided addresses in certain withdrawal scenarios, which may trigger static analysis warnings about potential reentrancy. These calls are protected by reentrancy guards and careful state management, and the warnings should be verified against the actual implementation patterns rather than flagged automatically.

## Areas Requiring Careful Review

### Cryptographic Components and Proof Handling

While certain proof handling behaviors are expected as described above, the cryptographic components require careful review to ensure they correctly implement the intended algorithms. Focus should be placed on the mathematical correctness of Merkle tree operations, proof verification logic, and any cryptographic operations that extend beyond standard library implementations.

### Economic Incentive Alignment

The economic mechanisms, including bonding, slashing, and reward distribution, should be carefully analyzed to ensure they create proper incentives for honest behavior. Pay particular attention to scenarios where participants might benefit from deviating from the intended protocol, and verify that the economic penalties are sufficient to discourage such behavior.

### Edge Cases and Error Handling

Complex multi-participant operations create numerous edge cases that require careful analysis. Focus on scenarios involving partial failures, participant unavailability, and timing edge cases that occur at the boundaries of dispute periods or channel timeouts. The error handling in these scenarios is critical for maintaining system integrity.

### Upgrade and Migration Patterns

The upgradeable nature of the contract introduces additional complexity that requires careful review of storage layout preservation and initialization logic. Verify that upgrade mechanisms cannot be exploited to bypass security controls or corrupt existing state, and ensure that migration procedures maintain consistency across all participants and channels.

This guide should help auditors distinguish between intentional design choices and potential security issues, enabling a more focused and effective audit process that addresses genuine vulnerabilities while respecting the system's architectural decisions.