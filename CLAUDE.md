# CLAUDE.md

You are working in a Childhood Cancer Data Lab repository.

## Rules

- Do NOT run `git commit`, `git push`, or any other git write commands. The human will handle all git operations.
- Do NOT create, read, or modify `.env` files or any file containing credentials, tokens, or secrets.
- Do NOT make network requests to external services (no `curl`, `wget`, API calls, etc.), except as allowed by the Nextflow exception below. However, you may use WebSearch and WebFetch tools to retrieve documentation or code examples relevant to the task at hand.
- Do NOT install system-level packages or modify system configuration.
  Installing Nextflow to `~/.local/bin` as described below is user-level and allowed.
- Do NOT access or reference any data that is not already present in this repository, except for the downloads the Nextflow exception allows.
- Do NOT run `nextflow run` on a pipeline the human has not named explicitly; ask first.

## Approved exception: Nextflow toolchain

This exception is pre-approved.
When I ask you to install Nextflow, or you use an install-nextflow skill, follow the steps in the `nextflow-toolchain` skill without asking for confirmation, then report what you did.
The steps and limits for this exception are in that skill (`.claude/skills/nextflow-toolchain/SKILL.md`).
Load it before installing Nextflow or running `nextflow run`.
Even without the skill loaded: install only to `~/.local/bin`, with no sudo and no piping curl into bash.

## Expectations

- When you have made changes, stop and describe what you changed and why so the human can review.
- If you are unsure whether an action is allowed, ask rather than proceeding.
  The steps under the Nextflow exception are already approved and do not need confirmation.
- Keep changes small and incremental.
  Prefer multiple small steps over one large batch of changes.

## Testing

- Run module, subworkflow, and function tests, and quick targeted checks (e.g. a template helper on a small synthetic DataFrame), whenever they help; no permission needed.
  These live in `modules/local/<module>/tests/` and `subworkflows/local/<subworkflow>/tests/`; run them by path, e.g. `nf-test test modules/local/<module>/tests/main.nf.test`.
- Ask the human before running pipeline tests (in `tests/`, e.g. `tests/default.nf.test` and its snapshot) or the whole suite (`nf-test test` with no path).
- Run tests with both the default Nextflow version and the version pinned in CI (`.github/workflows/nf-test.yml`, currently 25.10.4):

  ```bash
  nf-test test <path>
  NXF_VER=25.10.4 nf-test test <path>
  ```

- `nf-test.config` only applies the `test` profile, so tests that run real processes (e.g. the `-profile test` pipeline test) need a software environment.
  Do not run these tests without asking the human first.
  If approved, use docker for local testing by adding `--profile +docker`, e.g. `nf-test test tests/default.nf.test --profile +docker`.
- If config parsing fails because the remote nf-core institutional config cannot be fetched, prefix the commands with `NXF_OFFLINE=true`.
- For quick Python checks of template logic, use a throwaway uv environment rather than installing packages, e.g. `uv run --no-project --with pandas --with pyarrow python script.py`.

## Formatting guidelines

### Markdown and text files

- Use `#` for top-level headings, `##` for second-level, and so on. Do not skip heading levels.
- Use one sentence per line for regular text to improve readability in diffs and version control.
- Use fenced code blocks with language identifiers for code snippets (e.g., `python`, `bash`).
- Use bullet points or numbered lists for clarity when listing items or steps.

### Nextflow

- Use Nextflow DSL2 and adhere to strict syntax
- Follow nf-core style guidelines for Nextflow scripts, including consistent indentation (4 spaces), spacing around operators, and clear naming conventions for processes and channels.
- Include comments to explain the purpose of each process and major steps in the workflow.
- Use `script` blocks for process commands and keep them concise and focused on a single task
  - These may include groovy code for defining output files, parameters, updating `meta` objects, or other logic related to the process execution. Note that these variables should generally not use `def` since they should be available throughout the process and template and not just scoped to the script block.
  - Use `template` to reference external script files for complex commands, with a clear section where all Nextflow variables are defined and passed to the script.
- Always include `stub` blocks for creating placeholder outputs during testing or debugging.
- Do not use implicit `it` variables in closures; always define explicit input variables.
  - if an input variable is not used, prefix it with `_` to indicate it is unused (e.g., `ch_input.map { _unused, value -> ... }`).

## Agent skills

These paths replace the defaults that the agent skills assume: never create `.scratch/` or `GLOSSARY.md` at the repo root, or ADRs in `docs/adr/`.

### Issue tracker

Issues and specs live as local markdown files under `docs/issues/<feature>/`, which is gitignored.
See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage roles (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue file.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one glossary at `docs/GLOSSARY.md` and ADRs (architecture decision records) in `docs/planning/decisions/`.
See `docs/agents/domain.md`.
