# Tokamak Private App Channels Conference Talk Script

Last updated: 2026-03-18

Target duration: 20 minutes

## Purpose

This document is the detailed speaking script for the conference slide deck. It is written for a technical audience, but it keeps each slide anchored to one primary claim so that the talk can fit into a 20-minute slot.

## Slide 1. Title and Thesis

- Target time: 1.0 minute
- Goal: establish the main claim of the talk.

Suggested script:

“Today I want to introduce Tokamak Private App Channels. The simplest way to think about the project is this: we are trying to make private, proof-based application channels practical on Ethereum without forcing every application team to become a protocol team. The system keeps Ethereum as the canonical layer for settlement and accepted state, while giving each application its own dedicated private execution environment. Over the next twenty minutes, I will explain what problem that solves, how the architecture works, what privacy it provides, and where its current limits still are.”

Transition:

“Let me start from the broader category that this project belongs to.”

## Slide 2. Why Privacy L2 Systems Matter

- Target time: 1.5 minutes
- Goal: explain the field and why the topic matters.

Suggested script:

“This project sits in the broader area of privacy Layer 2 systems. These systems try to keep the settlement and asset-safety properties of Ethereum while reducing how much user activity must be exposed during execution. That matters because many real applications need more than raw throughput. They need lower execution cost, stronger control over information disclosure, and a way to keep using Ethereum as the place where value is ultimately secured. The relevant application space is wide. It includes payments and trading, but it also includes games, social applications, and other application-specific workflows where developers want dedicated execution logic rather than one shared global state.”

Transition:

“Once we accept that privacy L2 systems matter, the next question is why building them is still hard.”

## Slide 3. The Problem We Are Solving

- Target time: 1.5 minutes
- Goal: define the project's core problem statement.

Suggested script:

“The first problem this project tries to solve is not only privacy. It is usability at the system-design level. Proof-based Layer 2 systems are powerful, but they are still hard to operate. In too many cases, an application team has to become a protocol team. They must understand proving systems, security assumptions, operational data models, and a lot of machinery that is not really their product. Tokamak Private App Channels try to lower that barrier. The goal is to let an ordinary application developer open a dedicated proof-based channel through a standardized framework instead of building a custom Layer 2 stack from scratch. On the user side, the goal is also to avoid outsourcing proof generation to a third party, because that would weaken the privacy story.”

Transition:

“So what is the one-sentence architecture that tries to deliver that?”

## Slide 4. One-Sentence System View

- Target time: 1.5 minutes
- Goal: present the system at the highest level.

Suggested script:

“At the highest level, the architecture is simple. Ethereum remains the canonical settlement layer. Each channel becomes a dedicated private execution environment for one application. That means the system is not trying to turn every application into one shared execution pool. Instead, it treats the channel as the basic operating unit. This gives us isolation between applications, a clear settlement boundary on Ethereum, and a privacy baseline in which users can submit proofs without revealing the original transaction content to outside observers.”

Transition:

“To make that concrete, it helps to compare this model with an ordinary L1-native DApp.”

## Slide 5. Ordinary L1 DApp vs. This System

- Target time: 2.0 minutes
- Goal: explain the central architectural shift.

Suggested script:

“In an ordinary L1-native DApp, the developer deploys contracts directly to Ethereum, users submit transactions, validators re-execute those transactions, and if the execution succeeds, Ethereum updates storage. In our system, the approval condition changes. The developer still defines the application surface, but users do not submit the original transaction in the same way. Instead, they execute privately, generate a proof, and submit the proof and the required public inputs. Validators do not re-execute the original private transaction. They verify a proof. This is the central architectural shift in the whole design: transaction re-execution becomes proof verification. Once you see that shift clearly, most of the rest of the architecture follows from it.”

Transition:

“Now let us look at the main system components that make that shift operational.”

## Slide 6. Architecture

- Target time: 2.0 minutes
- Goal: explain the main roles in the system.

Suggested script:

“The architecture has three practical roles. First, the Ethereum bridge manages channels, accepted state, proof verification, and token-vault custody. Second, the channel server is the off-chain environment where private execution is coordinated. It is operationally important, but it is not the trust anchor. Third, there is a bridge-managed application registry that determines which contracts and functions are supported and which subset a given channel may use. This matters because it means a channel is not an unconstrained execution sandbox. It has a defined application surface. That keeps the design more structured, and it helps make proof verification and channel behavior predictable.”

Transition:

“With that architecture in mind, the next question is what exactly a channel state looks like.”

## Slide 7. Channel State and Storage

- Target time: 1.5 minutes
- Goal: explain the state model succinctly.

Suggested script:

“A channel state is represented as a vector of Merkle roots rather than as one monolithic root. Each channel has exactly one dedicated token-vault storage domain, and it may also have one or more application storage domains. This split is important. It means asset-related state and general application state can be treated differently. The model stays compact enough to anchor accepted state on Ethereum, but it also gives us a clean place to reason separately about asset movement, application logic, privacy, and data availability.”

Transition:

“That state split is mirrored by the proof split.”

## Slide 8. Two Proof Systems

- Target time: 2.0 minutes
- Goal: explain why there are two proof systems.

Suggested script:

“The system uses two proof systems with different jobs. Groth zkp is used for token-vault control. Its role is narrow: it proves that a balance update in the vault path is correct for deposit or withdrawal. Tokamak zkp is used for application execution. Its role is broader: it proves that an allowed application function executed correctly and produced the correct state update. This separation is not only an implementation detail. It is a design decision. Asset movement and application execution have different verification needs, so the system keeps them distinct instead of forcing one proof path to do everything.”

Transition:

“Once we understand the proof split, we can walk through the main user flows.”

## Slide 9. Core User Flows

- Target time: 2.0 minutes
- Goal: summarize the operational story.

Suggested script:

“Operationally, the system can be explained through three flows. For a normal in-channel transaction, the user executes privately, generates a proof, and Ethereum verifies that proof before accepted state changes. For deposit and withdrawal, the user goes through the vault path, proves the vault-state update, and Ethereum settles the result. The point is that even though execution happens in the channel environment, economic authority still comes from Ethereum verification. That is what keeps custody and accepted state aligned with the settlement layer.”

Transition:

“Now let me separate what privacy the system gives by itself from what still depends on application design.”

## Slide 10. Privacy Model

- Target time: 1.5 minutes
- Goal: explain baseline privacy versus stronger privacy.

Suggested script:

“The system by itself gives a privacy baseline. The original user transaction does not need to be openly revealed to outside observers, and the user does not need to outsource proof generation. But that does not mean the system alone gives complete application-level privacy. The channel operator may still observe state changes and infer user behavior. That is why the white paper distinguishes system-level privacy from DApp-level private-state design. If the application itself uses a private-state model, then the system can hide the transaction while the DApp can hide the semantic meaning of visible state. Those two layers are complementary.”

Transition:

“A similar distinction appears again in data availability.”

## Slide 11. Data Availability and Safe Exit

- Target time: 1.5 minutes
- Goal: explain the system's main availability tradeoff.

Suggested script:

“Data availability is asymmetric in the current design. Asset-related vault state is more directly recoverable from Ethereum-visible proof data. General application state depends much more heavily on the channel operator. That means an operator failure can interrupt normal application activity. But it should not eliminate safe exit, because the user should still be able to rely on the vault path that remains anchored to Ethereum. This is one of the most important design tradeoffs in the project. The system currently has a stronger story for asset recovery than for full application-state availability.”

Transition:

“So let me close by summarizing what the current version guarantees and what it still leaves for later.”

## Slide 12. Security Properties and Future Work

- Target time: 1.0 minute
- Goal: separate current guarantees from deferred design work.

Suggested script:

“The current version prioritizes a few things very clearly: Ethereum-anchored custody, proof-verified state acceptance, channel isolation, and safe exit even under weaker application-data availability. At the same time, one important line of work is explicitly deferred. That is the proposal-pool model together with rewards, penalties, and token economics. The current system uses immediate proof verification rather than that deferred mechanism. If a proposal-pool model is introduced later, its incentive layer may become one way to improve the practical liveness of application-state handling, but it is not part of the current operative design.”

Transition:

“With that, let me end on the main thesis.”

## Slide 13. Closing

- Target time: 1.0 minute
- Goal: leave the audience with one memorable summary.

Suggested script:

“The main point I want to leave you with is that Tokamak Private App Channels should not be understood as just one more monolithic Layer 2. It is better understood as a framework for application-specific private channels. Ethereum keeps custody and accepted state. Users keep direct control over private proof submission. And developers get a path to dedicated proof-based channels without having to build an entire Layer 2 protocol on their own. That is the core value proposition of the project. Thank you.”

## Delivery Tips

- If time runs short, compress Slides 2 and 3.
- If the audience asks about proof internals, answer from Slides 8 and 12.
- If the audience asks about privacy limits, answer from Slides 10 and 11 together.
