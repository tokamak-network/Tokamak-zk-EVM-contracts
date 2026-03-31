---
name: repo-submodule-boundary
description: Use when editing code, scripts, CLIs, deployment tooling, or generators anywhere in this repository and the change may introduce, remove, or reshape dependencies across the parent-repository and `submodules/` boundary. It enforces that repository-owned code may depend on submodule code, but submodule code must never depend on parent-repository files.
---

# Repo Submodule Boundary

Use this skill whenever a task touches code under this repository and there is any chance that
the work changes how files are referenced across the boundary between:

- repository-owned code such as `apps/`, `bridge/`, `scripts/`, `.codex/`, or other root modules
- code that lives inside `submodules/`

## Boundary Rule

- Repository-owned code may reference files inside `submodules/` when needed.
- Code inside `submodules/` must not reference files from the parent repository.

This is a one-way dependency rule. Treat any reverse dependency from a submodule back into the
parent repository as a design bug.

## Required Handling

1. Check both direct file-path references and indirect helper defaults.
   - A submodule helper that defaults to a parent-repo path still violates the rule.
   - Error messages, bootstrap hints, and fallback paths should not instruct the submodule to
     read parent-repo files directly.
2. If submodule tooling needs deployment manifests, storage-layout manifests, ABI snapshots, or
   other generated artifacts from the parent repository, mirror those artifacts into the submodule
   as part of repository-owned deployment or refresh flows.
3. After mirroring, make the submodule read only its mirrored local copies.
4. Keep ownership clear:
   - parent repository generates or refreshes mirrored artifacts
   - submodule consumes mirrored artifacts only
5. When reviewing a change, search for:
   - `repoRoot`
   - parent-repo relative climbs such as repeated `..`
   - references to `apps/`, `bridge/`, or root deployment folders from submodule code
   - helper defaults that still point outside `submodules/`

## Preferred Fix Pattern

When a submodule currently reads parent-repo artifacts:

1. Add or extend a repository-owned script that writes or copies the needed artifacts into a
   stable path under the submodule.
2. Change the submodule script or helper to read that stable in-submodule path.
3. Remove any remaining parent-repo fallback or guidance from the submodule side.

## Completion Check

Before finishing, verify:

- no edited submodule file references parent-repo files
- any required mirrored artifacts are produced by repository-owned code
- the submodule path is stable and local to `submodules/`
- the dependency direction remains parent repo -> submodule only
