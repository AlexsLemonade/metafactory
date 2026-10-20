# CLAUDE.md

You are working in a Childhood Cancer Data Lab repository.

## Rules

- Do NOT run `git commit`, `git push`, or any other git write commands. The human will handle all git operations.
- Do NOT create, read, or modify `.env` files or any file containing credentials, tokens, or secrets.
- Do NOT make network requests to external services (no `curl`, `wget`, API calls, etc.), except as allowed by the Nextflow exception below.
- Do NOT install system-level packages or modify system configuration. 
Installing Nextflow to `~/.local/bin` as described below is user-level and allowed.
- Do NOT access or reference any data that is not already present in this repository, except for the downloads the Nextflow exception allows.

## Approved exception: Nextflow toolchain

This exception is pre-approved. 
When I ask you to install Nextflow, or you use an install-nextflow skill, follow the steps below without asking for confirmation, then report what you did.

### Installing Nextflow

If `nextflow -version` already works, skip the install. 
Otherwise install Nextflow using the Nextflow agent skill that is installed.

### Running Nextflow

Network access is allowed for Nextflow's own downloads (GitHub, registry.nextflow.io, container registries) and for `nextflow run` on a pipeline I have named explicitly. 
Ask before running any pipeline I have not named.

### Limits of this exception

- Install only to `~/.local/bin`. 
No sudo, no system package changes.
- Never run the installer inside the repo.
- Do not pipe curl into bash.
- Do not use this exception for any other tool, package manager, or service.
- If the install fails in a way these steps don't cover, stop and ask. 
Do not try other install methods or download sources.

## Expectations

- When you have made changes, stop and describe what you changed and why so the human can review.
- If you are unsure whether an action is allowed, ask rather than proceeding. 
The steps under the Nextflow exception are already approved and do not need confirmation.
- Keep changes small and incremental. 
Prefer multiple small steps over one large batch of changes.
