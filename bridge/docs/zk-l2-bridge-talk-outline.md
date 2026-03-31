# Tokamak Private App Channels Conference Talk Outline

Last updated: 2026-03-18

Target duration: 20 minutes

## Purpose

This outline is the planning draft for a technical-conference presentation based on the Tokamak Private App Channels white paper. It is optimized for a 20-minute slot, so each slide is designed to deliver one main message, one supporting visual, and one clear transition to the next slide.

## Slide Plan

### Slide 1. Title and Thesis

- Main message: Tokamak Private App Channels make proof-based private L2 channels practical for ordinary application developers and privacy-sensitive users.
- Visual suggestion: title slide with one-line thesis and subtitle.
- Time: 1.0 minute

### Slide 2. Why Privacy L2 Systems Matter

- Main message: privacy L2 systems matter because many applications need lower cost, stronger information control, and Ethereum-level settlement at the same time.
- Visual suggestion: three-column diagram for cost, privacy, and settlement.
- Time: 1.5 minutes

### Slide 3. The Problem This System Tries to Solve

- Main message: the project tries to make proof-based L2 channels easy to deploy without forcing every application team to become a protocol team.
- Visual suggestion: contrast between "build an app" and "build an L2 protocol stack."
- Time: 1.5 minutes

### Slide 4. One-Sentence System View

- Main message: Ethereum remains the canonical settlement layer, while each channel becomes a dedicated private execution environment for one application.
- Visual suggestion: simple two-layer block diagram.
- Time: 1.5 minutes

### Slide 5. How It Differs from an Ordinary L1 DApp

- Main message: the approval condition changes from validator-side transaction re-execution to validator-side proof verification.
- Visual suggestion: side-by-side pipeline comparing L1-native DApp flow and System flow.
- Time: 2.0 minutes

### Slide 6. Architecture

- Main message: the architecture has three practical roles: Ethereum bridge, channel execution environment, and bridge-managed application registry.
- Visual suggestion: component diagram showing users, L2 server, bridge, and Ethereum.
- Time: 2.0 minutes

### Slide 7. Channel State and Storage

- Main message: a channel state is a vector of Merkle roots, with one dedicated token-vault storage domain and additional application storage domains.
- Visual suggestion: channel-state diagram with vault storage and app storage.
- Time: 1.5 minutes

### Slide 8. Two Proof Systems

- Main message: one proof system controls asset movement and one proof system controls application execution.
- Visual suggestion: table comparing Groth zkp and Tokamak zkp.
- Time: 2.0 minutes

### Slide 9. Core User Flows

- Main message: the operational story is simple: open channel, execute privately, deposit, withdraw, and settle through Ethereum verification.
- Visual suggestion: flowchart with three lanes: transaction, deposit, withdrawal.
- Time: 2.0 minutes

### Slide 10. Privacy Model

- Main message: the System gives baseline privacy by hiding original transactions, and private-state DApps can add state-level privacy on top.
- Visual suggestion: layered privacy diagram.
- Time: 1.5 minutes

### Slide 11. Data Availability and Safe Exit

- Main message: application data availability is weaker than vault-state availability, but users can still exit safely through Ethereum-visible vault state.
- Visual suggestion: split diagram for vault data and app data.
- Time: 1.5 minutes

### Slide 12. Security Properties, Limits, and Future Work

- Main message: the current version prioritizes custody safety, proof-verified acceptance, and safe exit, while proposal-pool economics remain future work.
- Visual suggestion: two-column slide for "current guarantees" and "future work."
- Time: 1.0 minute

### Slide 13. Closing

- Main message: the project is best understood as a framework for application-specific private channels rather than as one more monolithic L2.
- Visual suggestion: short takeaway list.
- Time: 1.0 minute

## Timing Summary

- Slides 1-4: 5.5 minutes
- Slides 5-9: 9.5 minutes
- Slides 10-13: 5.0 minutes

Total planned speaking time: 20.0 minutes

## Delivery Notes

- If the slot is strict, compress Slides 2 and 3 into one faster transition and reduce Slide 12 to one minute.
- If the audience is more protocol-oriented, spend more time on Slides 5, 8, and 11.
- If the audience is more product-oriented, spend more time on Slides 2, 3, and 10.
