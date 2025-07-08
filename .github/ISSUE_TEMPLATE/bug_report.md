name: Bug Report
description: Report a bug in the zkEVM verifier or related contracts
title: "[Bug] <short description>"
labels: ["bug", "needs triage"]
assignees: ""

body:
  - type: markdown
    attributes:
      value: |
        ## Thank you for reporting a bug!

  - type: input
    id: what-happened
    attributes:
      label: What happened?
      description: Describe the bug in detail.
      placeholder: Describe the unexpected behavior
    validations:
      required: true

  - type: textarea
    id: reproduction-steps
    attributes:
      label: Steps to reproduce
      description: How can we reproduce the issue?
      placeholder: |
        1. Go to '...'
        2. Click on '...'
        3. See the error
    validations:
      required: true

  - type: input
    id: contract-version
    attributes:
      label: Contract Version / Branch
      placeholder: e.g., main / L2toL2Implementation

  - type: textarea
    id: additional-context
    attributes:
      label: Additional context
      description: Add any other context or logs here