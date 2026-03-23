---
marp: true
theme: default
paginate: true
title: Tokamak Private App Channels
description: Technical conference talk deck for a 20-minute presentation.
---

# Tokamak Private App Channels

### A Framework for Private, Proof-Based Application Channels on Ethereum

- 20-minute technical conference presentation
- Based on the current project white paper

---

# Why Privacy L2 Systems Matter

- Many applications need more than throughput
- They need lower execution cost
- They need stronger control over information disclosure
- They still want Ethereum-level settlement and asset safety

**Examples**

- payments
- trading
- games
- social applications
- application-specific private workflows

---

# The Problem We Are Solving

- Proof-based L2 systems are powerful
- But they are still hard to operate
- Too often, an app team must also become a protocol team

**Goal**

- Let ordinary application developers open dedicated proof-based channels
- Let users keep privacy without outsourcing proof generation

---

# One-Sentence System View

**Ethereum remains the canonical settlement layer.**

**Each channel becomes a dedicated private execution environment for one application.**

This gives us:

- application-specific isolation
- proof-based state acceptance
- user-controlled privacy baseline

---

# Ordinary L1 DApp vs. This System

| Ordinary L1 DApp | Tokamak Private App Channels |
| --- | --- |
| contracts deployed directly to Ethereum | app metadata registered to the bridge |
| users submit transactions | users submit proofs and public inputs |
| validators re-execute transactions | validators verify proofs |
| Ethereum full nodes reconstruct state | channel operator serves app state, Ethereum anchors vault state |

**Core shift**

Transaction re-execution becomes proof verification.

---

# Architecture

```text
Users
  |
  v
L2 Channel Server  <---->  Channel State
  |
  v
L1 Bridge on Ethereum
  |
  +-- DApp registry and channel management
  +-- Proof verification
  +-- Token vault custody
```

- Ethereum bridge: custody, proof verification, accepted state
- L2 server: private execution coordination
- DApp registry: allowed contracts and functions per channel

---

# Channel State and Storage

**A channel state is a vector of Merkle roots.**

Each channel contains:

- exactly one token-vault storage domain
- one or more application storage domains

Implications:

- one channel can serve one application cleanly
- accepted state stays compact on Ethereum
- vault state and app state have different availability properties

---

# Two Proof Systems

| Proof system | Role | Result |
| --- | --- | --- |
| Groth zkp | token-vault control | proves correct balance updates for deposit and withdrawal |
| Tokamak zkp | application execution | proves correct execution of an allowed application function |

**Design idea**

- asset movement and app execution are separated
- each path has a narrower verification target

---

# Core User Flows

**Transaction**

1. User executes privately in the channel
2. User generates a proof
3. Ethereum verifies the proof
4. Accepted channel state is updated

**Deposit / Withdrawal**

1. User interacts with the channel vault path
2. User proves the vault-state update
3. Ethereum accepts the vault-state change
4. Assets remain governed by Ethereum settlement

---

# Privacy Model

**System alone**

- hides the original transaction from outside observers
- does not fully hide the meaning of state changes from the channel operator

**System + private-state DApp**

- hides the original transaction
- also hides the user-level meaning of visible state

**Takeaway**

System privacy and DApp privacy are complementary.

---

# Data Availability and Safe Exit

| Storage class | Practical availability |
| --- | --- |
| token-vault state | more directly recoverable from Ethereum-visible proof data |
| application state | depends more heavily on the channel operator |

If application data becomes unavailable:

- normal app activity may stop
- safe exit should still remain possible through the vault path

---

# Security Properties and Future Work

**Current priorities**

- Ethereum-anchored custody
- proof-verified state acceptance
- channel isolation
- safe exit even under weaker app-data availability

**Future work**

- deferred proposal-pool operation
- rewards, penalties, and token economics
- stronger incentives for application-state liveness

---

# Closing

- Tokamak Private App Channels are not one more monolithic L2
- They are a framework for application-specific private channels
- Ethereum keeps custody and accepted state
- Users keep direct control over private proof submission

**Main claim**

Private, proof-based application channels can be made practical without forcing every DApp team to become a protocol team.
