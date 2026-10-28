---
title: Contributing
markdownPlugin: checklist
---

# `AlexsLemonade/metafactory`: Contributing guidelines

Hi there!
Thanks for taking an interest in improving AlexsLemonade/metafactory.

This page describes the recommended nf-core way to contribute to both AlexsLemonade/metafactory and nf-core pipelines in general, including:

- [General contribution guidelines](#general-contribution-guidelines): common procedures or guides across all nf-core pipelines.
- [Pipeline-specific contribution guidelines](#pipeline-specific-contribution-guidelines): procedures or guides specific to the development conventions of AlexsLemonade/metafactory.

## General contribution guidelines

### Contribution quick start

To contribute code to any nf-core pipeline:

- [ ] Ensure you have Nextflow, nf-core tools, and nf-test installed. See the [nf-core/tools repository](https://github.com/nf-core/tools) for instructions.
- [ ] Check whether a GitHub [issue](https://github.com/AlexsLemonade/metafactory/issues) about your idea already exists. If an issue does not exist, create one so that others are aware you are working on it.
- [ ] [Fork](https://help.github.com/en/github/getting-started-with-github/fork-a-repo) the [AlexsLemonade/metafactory repository](https://github.com/AlexsLemonade/metafactory) to your GitHub account.
- [ ] Create a branch on your forked repository and make your changes following [pipeline conventions](#pipeline-contribution-conventions) (if applicable).
- [ ] To fix major bugs, name your branch `patch` and follow the [patch release](#patch-release) process.
- [ ] Update relevant documentation within the `docs/` folder, use nf-core/tools to update `nextflow_schema.json`, and update `CITATIONS.md`.
- [ ] Run and/or update tests. See [Testing](#testing) for more information.
- [ ] [Lint](#lint-tests) your code with nf-core/tools.
- [ ] Submit a pull request (PR) against the `dev` branch and request a review.

If you are not used to this workflow with Git, see the [GitHub documentation](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests) or [Git resources](https://try.github.io/) for more information.

### Testing

Once you have made your changes, run the pipeline tests with [nf-test](https://www.nf-test.com/) to test them locally.
For additional information, use the `--verbose` flag to view the Nextflow console log output.

#### Running tests

Run every test with Docker:

```bash
nf-test test --profile +docker
```

The `+` adds `docker` to the `test` profile that nf-test uses by default (set in `nf-test.config`).

The pipeline-level tests live in `tests/` and are all tagged `pipeline`:

- `tests/default.nf.test` runs the full pipeline with `-profile test` on the test libraries in `tests/assets/samplesheet.csv`
- `tests/stub.nf.test` runs the full pipeline with `-stub` on the samplesheet in `stub/` (which points at the empty placeholder `.h5ad` files in `stub/data/`), which checks the channel wiring between modules in a few seconds
- `tests/params.nf.test` checks that invalid parameters and samplesheets fail

Each local subworkflow also has its own tests, tagged `subworkflows_local` and the name of the subworkflow:

- `subworkflows/local/calculate_metrics/tests/main.nf.test`
- `subworkflows/local/calculate_scores/tests/main.nf.test`
- `subworkflows/local/generate_reports/tests/main.nf.test`

Most of these tests run with `-stub` and are also tagged `stub`.
The rest run the real analysis on the files in `tests/data/`, so they need a container profile.
Helpers shared by the subworkflow tests are in `tests/lib/SubworkflowTestUtils.groovy`.

`tests/data/` holds output from a full run of the pipeline with `-profile test` for the one group in `tests/assets/samplesheet.csv`.
These files are the inputs to the `CALCULATE_METRICS` and `GENERATE_REPORTS` subworkflow tests, and the expected outputs for some of the `CALCULATE_METRICS` tests.
If you change the output of any module upstream of the reports, regenerate them from the root of the repository with:

```bash
tests/scripts/update-test-data.sh
```

This runs the pipeline with `-profile test,docker` in a temporary directory and copies the files into `tests/data/`, replacing what is there.
Any additional arguments are passed on to `nextflow run`, for example `-resume`.
The script requires R with the `optparse` and `tidyverse` packages.

To run a single test file or a subset of tests by tag:

```bash
nf-test test tests/stub.nf.test --profile +docker
nf-test test --tag stub --profile +docker
```

The stub and parameter validation tests do not run any analysis, so they can also be run without a container profile, which avoids pulling any images:

```bash
nf-test test tests/stub.nf.test tests/params.nf.test
```

Test outputs are compared against the snapshots in the `.nf.test.snap` file next to each test.
Files whose content changes between runs (for example, HTML reports, RDS files, and gzipped files) are listed in `tests/.nftignore`, so only their paths are snapshotted.
The metaprogram metrics tables vary in the last digits between platforms, so they are also listed in `tests/.nftignore`, and `tests/default.nf.test` snapshots their number of rows and header columns instead.
If you have added new functionality or intentionally changed an output, update the test assertions in the `.nf.test` files and regenerate the snapshots:

```bash
nf-test test --profile +docker --update-snapshot
```

Then run the tests again without `--update-snapshot` to confirm the new snapshots are stable, and commit the updated `.nf.test.snap` files.

When you create a pull request with changes, GitHub Actions will run automatic tests.
Pull requests are typically reviewed when these tests are passing.

Two types of tests are typically run:

#### Lint tests

nf-core has a [set of guidelines](https://nf-co.re/docs/specifications/overview) which all pipelines must follow.
To enforce these, run linting with nf-core/tools:

```bash
nf-core pipelines lint <pipeline_directory>
```

If you encounter failures or warnings, follow the linked documentation printed to screen.
For more information about linting tests, see [nf-core/tools API documentation](https://nf-co.re/docs/nf-core-tools/api_reference/latest/pipeline_lint_tests/actions_awsfulltest).

#### Pipeline tests

Each nf-core pipeline should be set up with a minimal set of test data.
GitHub Actions runs the pipeline on this data to ensure it runs through and exits successfully.
If there are any failures then the automated tests fail.
These tests are run with the latest available version of Nextflow and the minimum required version specified in the pipeline code.

### Patch release

> [!WARNING]
> Only in the unlikely event of a release that contains a critical bug.

- [ ] Create a new branch `patch` on your fork based on `upstream/main` or `upstream/master`.
- [ ] Fix the bug and use nf-core/tools to bump the version to the next semantic version, for example, `1.2.3` → `1.2.4`.
- [ ] Open a Pull Request from `patch` directly to `main`/`master` with the changes.

### Pipeline contribution conventions

nf-core semi-standardises how you write code and other contributions to make the AlexsLemonade/metafactory code and processing logic more understandable for new contributors and to ensure quality.

#### Add a new pipeline step

To contribute a new step to the pipeline, follow the general nf-core coding procedure.
Please also refer to the [pipeline-specific contribution guidelines](#pipeline-specific-contribution-guidelines):

- [ ] Define the corresponding [input channel](#channel-naming-schemes) into your new process from the expected previous process channel.
- [ ] Install a module with nf-core/tools, or write a local module (see [default processes resource requirements](#default-processes-resource-requirements)), and add it to the target `<workflow>.nf`.
- [ ] Define the output channel if needed. Emit software versions from the process with `path "versions.yml", emit: versions, topic: versions`, so that they are collected from the `versions` topic channel and added to the software versions file automatically.
- [ ] Add new or updated parameters to `nextflow.config` with a [default value](#default-parameter-values).
- [ ] Add new or updated parameters and relevant help text to `nextflow_schema.json` with [nf-core/tools](#default-parameter-values).
- [ ] Add validation for relevant parameters to the pipeline utilisation section of `utils_nfcore_metafactory_pipeline/main.nf` subworkflow.
- [ ] Perform local tests to validate that the new code works as expected.
  - [ ] If applicable, add a new test in the `tests` directory.
- [ ] Update `usage.md`, `output.md`, and `CITATIONS.md` as appropriate.
- [ ] [Lint](#lint-tests) the code with nf-core/tools.
- [ ] Update any diagrams or pipeline images as necessary.

To update the minimum required Nextflow version, see the [Nextflow version bumping](#nextflow-version-bumping) section below. For more information about pipeline contributions, see [pipeline-specific contribution guidelines](#pipeline-specific-contribution-guidelines).

#### Channel naming schemes

Use the following naming schemes for channels to make the channel flow easier to understand:

- Initial process channel: `ch_output_from_<process>`
- Intermediate and terminal channels: `ch_<previousprocess>_for_<nextprocess>`

#### Default parameter values

Parameters should be initialised and defined with default values within the `params` scope in `nextflow.config`.
They should also be documented in the pipeline JSON schema.

To update `nextflow_schema.json`, run:

```bash
nf-core pipelines schema build
```

The schema builder interface that loads in your browser should automatically update the defaults in the parameter documentation.

#### Default processes resource requirements

If you write a local module, specify a default set of resource requirements for the process.

Sensible defaults for process resource requirements (CPUs, memory, time) should be defined in `conf/base.config`.
Specify these with generic `withLabel:` selectors, so they can be shared across multiple processes and steps of the pipeline.

nf-core provides a set of standard labels that you should follow where possible, as seen in the [nf-core pipeline template](https://github.com/nf-core/tools/blob/main/nf_core/pipeline-template/conf/base.config).
These labels define resource defaults for single-core processes, modules that require a GPU, and different levels of multi-core configurations with increasing memory requirements.

Values assigned within these labels can be dynamically passed to a tool using the `${task.cpus}` and `${task.memory}` Nextflow variables in the `script:` block of a module (see an example in the [modules repository](https://github.com/nf-core/modules/blob/bd1b6a40f55933d94b8c9ca94ec8c1ea0eaf4b82/modules/nf-core/samtools/bam2fq/main.nf#L30)).

#### Nextflow version bumping

If you use a new feature from core Nextflow, bump the minimum required Nextflow version in the pipeline with:

```bash
nf-core pipelines bump-version --nextflow . <min_nf_version>
```

#### Images and figures guidelines

If you update images or graphics, follow the nf-core [style guidelines](https://nf-co.re/docs/community/brand/workflow-schematics).

## Pipeline specific contribution guidelines

### Local modules

All modules in this pipeline are local modules in `modules/local/`, each with a `main.nf`, `meta.yml`, and `environment.yml`.

- **Templates:** The analysis code for a module lives in an R or Python script in the module's `templates/` directory and is called from the `script:` block with `template('<script-name>')`.
  Only modules that run a simple shell command, such as `publish-metaprograms`, write the command directly in the `script:` block.
  Nextflow variables (for example `${meta.unique_id}` or `${options.seed}`) are interpolated into the script before it runs, so define all input variables at the top of the script.
  The script should also write the `versions.yml` file.
- **Options:** Any pipeline parameters a module needs are passed to it as a map in a `val options` input from the workflow or subworkflow, rather than read from `params` inside the module.
- **Stub blocks:** Every module must have a `stub:` block that creates empty files with the same names as the real outputs and a `versions.yml` file with `stub: x.y.z` as the version.
  The stub tests (`tests/stub.nf.test` and the subworkflow tests tagged `stub`) rely on these to check the channel wiring between modules.

### Output directories

- **`metaprograms_publish_dir`:** Every module that runs once per set of metaprograms writes its output inside the directory stored in `meta.metaprograms_publish_dir`, which is set in `workflows/metafactory.nf` as `<group_id>/k-<k>_<filtered_<cutoff>|unfiltered>`.
  This keeps all output for a set of metaprograms together in each checkpoint directory.
- **Publishing:** Where output is published is set in `conf/modules.config`, not in the module.
  Intermediate output is published to a subdirectory of `checkpoints/` with a `withName:` selector.
  Final results are published to `results/` by adding the `results` label to the process, and should be written inside a directory named for the group (`${meta.group_id}`).
- Update [`docs/output.md`](output.md) when adding or changing any published file.

### Containers

Modules use a container built with [Seqera Wave](https://seqera.io/wave/) from the module's `environment.yml`.
The exception is `publish-metaprograms`, which only copies files and uses the `ubuntu` image from Docker Hub.
To build the containers after creating or updating `environment.yml`, run:

```bash
scripts/build-wave.sh modules/local/<module>
```

This requires the `TOWER_ACCESS_TOKEN` environment variable to be set to a valid Seqera Platform token.
The script builds both a Docker image and a Singularity image, and prints a `container` directive with both image URIs.
Copy that directive into the module's `main.nf`, replacing the existing one if there is one.
