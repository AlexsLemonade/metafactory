# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This repo keeps its domain docs under `docs/`, not at the repo root.
Wherever a skill refers to `GLOSSARY.md` or `docs/adr/`, use the paths below instead; never create `GLOSSARY.md` at the repo root or a `docs/adr/` directory.

## Before exploring, read these

- **`docs/GLOSSARY.md`**: the domain glossary.
- **`docs/planning/decisions/`**: the ADRs (architecture decision records), numbered `0001-<slug>.md`, `0002-<slug>.md`, and so on.
  Read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**.
Don't flag their absence; don't suggest creating them upfront.
The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily, at these paths, when terms or decisions actually get resolved.

## File structure

This is a single-context repo:

```text
/
├── docs/
│   ├── GLOSSARY.md
│   ├── planning/
│   │   └── decisions/
│   │       ├── 0001-<slug>.md
│   │       └── 0002-<slug>.md
│   ├── agents/
│   └── issues/
├── modules/
├── subworkflows/
└── workflows/
```

## ADR location and naming

ADRs live in `docs/planning/decisions/`, **not** `docs/adr/`.
When a skill says to write or read an ADR in `docs/adr/`, use `docs/planning/decisions/` instead.

Name each ADR `NNN-<slug>.md`: a three-digit, zero-padded sequence number followed by a short kebab-case slug (e.g. `001-metaprogram-inputs.md`).
Number new ADRs one higher than the highest existing number, and refer to them as `Decision-001`, `Decision-002`, etc.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `docs/GLOSSARY.md`.
Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (some decision), but worth reopening because…_
