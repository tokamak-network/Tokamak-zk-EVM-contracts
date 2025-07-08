name: Feature Request
description: Suggest an improvement or new feature
title: "[Feature] <short description>"
labels: ["enhancement"]
assignees: ""

body:
  - type: input
    id: request-summary
    attributes:
      label: Summary
      description: A short summary of the feature request
      placeholder: Add a new opcode verifier...

  - type: textarea
    id: motivation
    attributes:
      label: Motivation
      description: Why is this feature important?
      placeholder: It helps reduce gas cost in...
    validations:
      required: true

  - type: textarea
    id: proposal
    attributes:
      label: Proposal
      description: Describe your proposed solution
      placeholder: We could refactor the verifier to...

  - type: dropdown
    id: priority
    attributes:
      label: Priority
      options:
        - High
        - Medium
        - Low