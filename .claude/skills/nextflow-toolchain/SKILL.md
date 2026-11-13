---
name: nextflow-toolchain
description: Rules for installing Nextflow and for running `nextflow run` in this repo, including what network access is allowed and the install limits. Use before installing, upgrading, or checking Nextflow, before any `nextflow run`, or when using the nextflow:install-nextflow skill.
---

# Nextflow toolchain

## Installing Nextflow

If `nextflow -version` already works, skip the install.
Otherwise install Nextflow using the Nextflow agent skill that is installed.

## Running Nextflow

Network access is allowed for Nextflow's own downloads (GitHub, registry.nextflow.io, container registries) and for `nextflow run` on a pipeline I have named explicitly.
Ask before running any pipeline I have not named.

## Limits of this exception

- Install only to `~/.local/bin`.
  No sudo, no system package changes.
- Never run the installer inside the repo.
- Do not pipe curl into bash.
- Do not use this exception for any other tool, package manager, or service.
- If the install fails in a way these steps don't cover, stop and ask.
  Do not try other install methods or download sources.
