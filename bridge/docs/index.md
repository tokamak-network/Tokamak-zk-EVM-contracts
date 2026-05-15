# Bridge Documentation Index

This index separates public bridge documentation from developer notes, archival reviews, and
optimization work logs. Start here when deciding which bridge document should be cited externally.

## Official Public Documents

- [Tokamak Private App Channels White Paper](whitepaper.md)
  - Public narrative for the bridge model, DApp/channel policy surface, custody boundary, privacy
    model, security posture, and current operational policy.
- [Bridge Gas Assessment](gas-assessment.md)
  - Public gas-cost reference for bridge owner, operator, and user-facing calls, including the
    historical Ethereum gas-fee distribution used for USD estimates.

## Developer Reference

These files are useful for implementation work and review, but they are not the public narrative
entrypoint.

- [Current Bridge Implementation Notes](dev/current-implementation.md)
  - Volatile implementation detail, deployment helper behavior, and current registration
    assumptions.
- [Abstract Bridge Contract Spec](dev/spec.md)
  - Math-first abstract model for constraints and invariants. Use it for formal reasoning, not for
    deployment addresses or ABI details.
- [Verifier Spec Notes](dev/verifier-spec.md)
  - Developer notes for the verifier pairing equation and coefficient grouping.

## Optimization Reports

- [Optimization Report](optimization/optimization_report.md)
  - Source-series gas snapshots and links to per-snapshot mini-reports.
- [Optimization Mini-Reports](optimization/mini-reports/)
  - Historical verifier optimization notes. These are work logs, not general bridge guidance.

## Archive

- [Bridge and Private-State Mainnet Security Review](archive/bridge-private-state-mainnet-security-review.md)
  - Historical mainnet review snapshot. Use it as dated audit context, not as the current public
    security model.

## References And Assets

- [Reference papers](references/)
  - External PDF references used during verifier and proof-system review.
- [Assets](assets/)
  - Images, charts, and raw data used by the official and supporting bridge documents.
