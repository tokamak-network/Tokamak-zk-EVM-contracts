---
name: bridge-docs-discipline
description: Use when editing `bridge/docs/spec.md`, `bridge/docs/zk-l2-bridge-design-notes.md`, or adjacent bridge documentation in this repository. It enforces the role split that `spec.md` is a math-first abstract model for theory and paper work, while `zk-l2-bridge-design-notes.md` is a stable high-level architecture document for future developer docs and should avoid volatile implementation detail.
---

# Bridge Docs Discipline

Use this skill whenever a task touches bridge documentation and there is any risk of
mixing up the roles of:

- `bridge/docs/spec.md`
- `bridge/docs/zk-l2-bridge-design-notes.md`
- `bridge/docs/current-implementation.md`

## Documentation Writing Quality

Every sentence, paragraph, section, and document must have a logical flow. The writing
must carry the reader smoothly from the problem or thesis, through the reasoning, to the
conclusion. Do not leave a statement hanging after presenting a fact. Explain why the
fact matters, what it enables, what risk it creates, or what conclusion follows from it.

Each paragraph should give the reader a reason to continue. Avoid writing lists of true
statements that do not explain their own relevance. Prefer a progression such as:

1. introduce the problem, concept, or claim
2. define the terms needed to understand it
3. explain the mechanism or reasoning
4. give a concrete example when the concept is not common
5. state the resulting implication or conclusion

For any concept or term that is not ordinary, universal, or already established in the
same document, define it accurately and clearly before relying on it. When a definition
is subtle, include an example that shows how the term is used in the system. The example
should reduce ambiguity, not add another unexplained abstraction.

Before finishing documentation work, review the edited text as a third-party reader:

- Can the reader tell why each sentence is present?
- Does each paragraph have a clear conclusion or implication?
- Does each section follow naturally from the previous section?
- Are nonstandard terms defined before they are used as premises?
- Are examples included where a new concept would otherwise be hard to internalize?

## Role Split

### `bridge/docs/spec.md`

Treat `bridge/docs/spec.md` as the abstract mathematical model.

Required properties:

- Mathematics is the primary language.
- English is only auxiliary glue around the mathematics.
- Security constraints, invariants, relations, and transition rules should be stated as
  mathematical objects and formulas.
- Use renderer-friendly LaTeX delimiters: `$...$` and `$$...$$`.
- Prefer abstract parameters over concrete implementation instantiations.

Do not put these into `spec.md` unless the user explicitly asks for an instantiated
model:

- concrete ABI shapes
- event names
- calldata field names
- storage-slot packing
- cache layout
- current hardcoded numeric parameter values such as a specific deployed depth or
  storage-count cap
- temporary implementation workarounds

When current implementation constraints matter, lift them into abstract form. Example:

- good: parameterized limits, abstract admissibility conditions, uniqueness relations,
  proof-gated transition rules
- bad: "the contract stores `currentRootVectorHash` in slot X and emits event Y"

### `bridge/docs/zk-l2-bridge-design-notes.md`

Treat `bridge/docs/zk-l2-bridge-design-notes.md` as a stable architecture note for future
developer documentation.

Required properties:

- High-level architectural intent is primary.
- The document should survive small implementation changes.
- It should describe stable concepts, responsibilities, boundaries, and design
  preferences.

Prefer:

- component responsibilities
- trust boundaries
- state-model choices
- proof-system roles
- DApp/channel metadata ownership
- soundness principles
- observability requirements

Avoid or remove if not essential:

- exact function signatures
- exact event payloads
- exact synthesizer word offsets
- exact cache shapes
- step-by-step script behavior
- temporary optimizations
- any wording that will become stale after a small refactor

### `bridge/docs/current-implementation.md`

Put volatile implementation detail here instead of polluting the other two documents.

This includes:

- mismatches between implementation and spec
- currently enforced concrete parameter values
- current ABI and event details when they matter
- temporary limitations or shortcuts

## Workflow

1. Identify which document the requested change actually belongs to.
2. Before editing, classify each fact as one of:
   - abstract theorem/spec fact
   - stable design fact
   - current implementation fact
3. Put each fact in exactly one document family:
   - abstract theorem/spec fact -> `bridge/docs/spec.md`
   - stable design fact -> `bridge/docs/zk-l2-bridge-design-notes.md`
   - current implementation fact -> `bridge/docs/current-implementation.md`
4. If a statement depends on exact current code structure, it does not belong in
   `bridge/docs/spec.md`.
5. If a statement is likely to change after a small refactor, it usually does not
   belong in `bridge/docs/zk-l2-bridge-design-notes.md`.

## Guardrails

Before finishing any edit to these docs, check:

- Is `spec.md` math-first rather than prose-first?
- Does `spec.md` avoid concrete implementation numbers unless explicitly parameterized?
- Does `design notes` stay useful if ABI names and event shapes change next week?
- Are implementation-specific details pushed into `current-implementation.md` instead?

If the answer to any of those is no, revise before finishing.
