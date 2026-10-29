# AlexsLemonade/metafactory: Usage

`metafactory` identifies _metaprograms_ — recurrent gene expression programs shared across samples — from single-cell and single-nuclei RNA-seq data.
See the [README](../README.md) for an overview of the pipeline steps and [output.md](output.md) for a description of the results.

> [!NOTE]
> If you are new to Nextflow, see the [nf-core environment setup docs](https://nf-co.re/docs/get_started/environment_setup/overview) for how to install and configure Nextflow.

## Samplesheet input

The pipeline takes filtered and normalized single-cell/single-nuclei objects, one per library, as AnnData `.h5ad` files.
Cells are expected to have already been filtered, and raw counts are expected to be available alongside the normalized data.
Currently the pipeline has been developed to handle processed `AnnData` objects from [ScPCA](https://scpca.alexslemonade.org), but future work will expand support to other single-cell file types.

Samples are described in a comma-separated samplesheet with three columns and a header row, whose location is provided with `--input`:

```bash
--input '[path to samplesheet file]'
```

| Column      | Description                                                                                                                                     |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `unique_id` | Unique identifier for the library. Used to name all per-library output.                                                                         |
| `group_id`  | Identifier for the group of samples that metaprograms are built across. All libraries sharing a `group_id` are analyzed together as one cohort. |
| `h5ad_file` | Path to the filtered and normalized `.h5ad` file for that library. Local and remote (e.g. `s3://`) paths are both supported.                    |

```csv title="samplesheet.csv"
unique_id,group_id,h5ad_file
SCPCL000001,SCPCP000001,/path/to/SCPCL000001_processed_rna.h5ad
SCPCL000002,SCPCP000001,/path/to/SCPCL000002_processed_rna.h5ad
SCPCL000003,SCPCP000001,/path/to/SCPCL000003_processed_rna.h5ad
```

Metaprograms are built once per `group_id`, so a single run can process multiple independent cohorts.
An [example samplesheet](../assets/samplesheet.csv) is provided with the pipeline, and the columns are validated against [`assets/schema_input.json`](../assets/schema_input.json).

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run AlexsLemonade/metafactory \
   -profile <docker/singularity/.../institute> \
   --input ./samplesheet.csv \
   --outdir ./results
```

Note that the pipeline will create the following files in your working directory:

```
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

Pipeline settings can also be provided in a `yaml` or `json` file via `-params-file <file>`:

```bash
nextflow run AlexsLemonade/metafactory -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
input: "./samplesheet.csv"
outdir: "./results/"
n_metaprograms: "8,9,10,11"
```

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors.
> Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/running/run-pipelines#configuring-pipelines), other infrastructural tweaks, or module arguments (`args`).

To check that the pipeline is able to run in your environment without running any analysis, you can run the workflow with the `stub` profile.
The stub samplesheet points to empty placeholder `.h5ad` files in `stub/data/` using paths relative to the root of the repository, so the stub run must be launched from the root of a clone of the repository:

```bash
git clone https://github.com/AlexsLemonade/metafactory.git
cd metafactory
nextflow run . -profile stub -stub
```

## Parameters

A full, automatically generated description of every parameter is available with `nextflow run AlexsLemonade/metafactory --help` (or `--help_full` for the complete list).
The parameters most relevant to an analysis are described below.

### Input/output options

| Parameter                      | Default                               | Description                                                                                                                            |
| ------------------------------ | ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `--input`                      | _required_                            | Path to the samplesheet CSV described above.                                                                                           |
| `--outdir`                     | _required_                            | Directory to write results to.                                                                                                         |
| `--msigdb_gene_sets`           | `assets/msigdb-gene-set-genes.tsv.gz` | Table of gene sets used for ORA. See [`assets/README.md`](../assets/README.md) for the file format and how to rebuild it.              |
| `--celltype_annotation_column` | `''`                                  | Column in `adata.obs` holding cell type annotations. If not provided, all cells are used.                                              |
| `--analysis_celltypes`         | `''`                                  | Comma-separated cell type values to keep for analysis (e.g. `'tumor,malignant'`). Required when `--celltype_annotation_column` is set. |

### General options

| Parameter | Default | Description                                                                                                             |
| --------- | ------- | ----------------------------------------------------------------------------------------------------------------------- |
| `--seed`  | `2025`  | Random seed used across all analysis modules for reproducibility.                                                       |
| `--nreps` | `1000`  | Number of permutation replicates used to build the background distributions that observed metrics are compared against. |

### cNMF options

These control the range of components (`k`) used when running cNMF within each sample.

By default, cNMF is skipped for any sample that already has results in `checkpoints/cnmf` created with the same cNMF options, and those existing results are used instead.

| Parameter            | Default | Description                                                                                     |
| -------------------- | ------- | ----------------------------------------------------------------------------------------------- |
| `--cnmf_k_lower`     | `5`     | Lower bound of the range of components tested in cNMF.                                          |
| `--cnmf_k_upper`     | `15`    | Upper bound of the range of components tested in cNMF.                                          |
| `--cnmf_k_step_size` | `5`     | Step size across that range.                                                                    |
| `--repeat_cnmf`      | `false` | Re-run cNMF for every sample, even if existing results were created with the same cNMF options. |

### Metaprogram options

These control how the spectra from all samples in a group are clustered into metaprograms.

| Parameter                       | Default       | Description                                                                                                                                  |
| ------------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `--n_metaprograms`              | `'8,9,10,11'` | Comma-separated values of `k` (numbers of metaprograms) to build and compare. At least four values are required to identify the optimal `k`. |
| `--n_top_genes`                 | `200`         | Number of top genes per metaprogram used for scoring and ORA.                                                                                |
| `--metaprograms_filter_spectra` | `true`        | Whether to remove orphan spectra, those with low correlation to spectra from other samples, prior to clustering.                             |
| `--metaprograms_orphan_cutoff`  | `0.3`         | Minimum cross-sample maximum correlation required to keep a spectra when filtering is enabled.                                               |

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen).

### `-profile`

Use this parameter to choose a configuration profile.
Profiles can give configuration presets for different compute environments, and multiple profiles can be combined, for example `-profile stub,docker` — the order matters, as later profiles overwrite earlier ones.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`.
This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility.
> If this is not possible, Conda is also supported.

The following profiles are bundled with the pipeline:

**Software profiles**

- `docker` — use [Docker](https://docker.com/) containers.
- `singularity` — use [Singularity](https://sylabs.io/docs/) containers.
- `apptainer` — use [Apptainer](https://apptainer.org/) containers.
- `podman` — use [Podman](https://podman.io/) containers.
- `shifter` — use [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/) containers.
- `charliecloud` — use [Charliecloud](https://charliecloud.io/) containers.
- `wave` — build containers on the fly with [Wave](https://seqera.io/wave/). Use together with one of the container profiles above.
- `conda` and `mamba` — use [Conda](https://conda.io/docs/) environments. Please only use Conda as a last resort, i.e. when it's not possible to run the pipeline with any of the container profiles above.

**Test profiles**

- `test` — runs the pipeline on a small set of test libraries with reduced settings (fewer permutation replicates and values of `k`), so it needs no other parameters.
  Use together with a software profile, for example `-profile test,docker`.
- `test_full` — runs the pipeline on the same test libraries as `test`, but with the default pipeline parameters.
- `stub` — runs the pipeline on a placeholder stub dataset; use together with `-stub` (see [Running the pipeline](#running-the-pipeline)).

**Hardware and debugging profiles**

- `arm64` and `emulate_amd64` — for running on ARM-based machines (e.g. Apple Silicon).
- `gpu` — passes GPU access through to Docker, Singularity, and Apptainer containers.
- `debug` — keeps the work directory after the run, prints the hostname for each task, and enables warnings for process selectors in config files that do not match any process.

**ALSF profiles**

- `batch`, `dev`, `scpca_testing`, and `scpca_staging` — ALSF-specific profiles for running on AWS Batch, defined in [`conf/alsf-profiles.config`](../conf/alsf-profiles.config).

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time.
For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

### `-resume`

Specify this when restarting a pipeline.
Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously.
You can also supply a run name to resume a specific run: `-resume [run-name]`.
Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command).
See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#set-max-resources) and [customise process resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#customize-process-resources) section of the nf-core website.

### Custom Containers

Most steps of the pipeline use a container built with [Seqera Wave](https://seqera.io/wave/) and hosted on the `community.wave.seqera.io` registry, built from the conda environment defined in the `environment.yml` file in each module directory.
When running with `-profile conda` or `-profile mamba`, those same `environment.yml` files are used to create the conda environments.

In some cases, you may wish to change the container or conda environment used by a step of the pipeline.
To do so, please see the [updating tool versions](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#update-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#modifying-tool-arguments) section of the nf-core website.

### nf-core/configs

Institutional profiles from the [`nf-core/configs`](https://github.com/nf-core/configs) repository are loaded automatically and can be used with `-profile` (see [`-profile`](#-profile)).
If your institution does not have a profile, you can provide your own config file with `-c`.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

## Updating the pipeline

Nextflow caches the pipeline code the first time you run it, and will keep using the cached version even after the pipeline has been updated.
To make sure you are running the latest version:

```bash
nextflow pull AlexsLemonade/metafactory
```

## Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data, so that the same version of the code and software is used every time.
Find the latest version on the [releases page](https://github.com/AlexsLemonade/metafactory/releases) and specify it with `-r`, e.g. `-r v1.0.0`.
This version number is logged in the reports produced by the run.

Sharing and reusing [parameter files](#running-the-pipeline) also helps repeat runs with the same settings.

> [!TIP]
> If you share a params file (such as supplementary material for a publication), make sure to NOT include cluster-specific paths to files, nor institutional specific profiles.

## Running in the background

Nextflow handles job submissions and supervises the running jobs, so the Nextflow process must run until the pipeline is finished.
The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal, with logs saved to a file.
Alternatively, you can use `screen` / `tmux` or a similar tool to create a detached session.

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machine can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~/.bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
