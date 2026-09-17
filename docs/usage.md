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
SCPCL000003,SCPCP000002,/path/to/SCPCL000003_processed_rna.h5ad
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

```bash
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

To check that the pipeline is installed and your environment is set up without running any analysis, you can run the stub profile from the project root:

```bash
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

| Parameter            | Default | Description                                            |
| -------------------- | ------- | ------------------------------------------------------ |
| `--cnmf_k_lower`     | `5`     | Lower bound of the range of components tested in cNMF. |
| `--cnmf_k_upper`     | `15`    | Upper bound of the range of components tested in cNMF. |
| `--cnmf_k_step_size` | `5`     | Step size across that range.                           |

### Metaprogram options

These control how the spectra from all samples in a group are clustered into metaprograms.

| Parameter                       | Default       | Description                                                                                                                                  |
| ------------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `--n_metaprograms`              | `'8,9,10,11'` | Comma-separated values of `k` (numbers of metaprograms) to build and compare. At least four values are required to identify the optimal `k`. |
| `--n_top_genes`                 | `200`         | Number of top genes per metaprogram used for scoring and ORA.                                                                                |
| `--metaprograms_filter_spectra` | `true`        | Whether to remove orphan spectra — those that do not correlate with spectra from any other sample — before clustering.                       |
| `--metaprograms_orphan_cutoff`  | `0.3`         | Minimum cross-sample maximum correlation required to keep a spectra when filtering is enabled.                                               |

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen).

### `-profile`

Use this parameter to choose a configuration profile.
Profiles can give configuration presets for different compute environments, and multiple profiles can be combined, for example `-profile stub,docker` — the order matters, as later profiles overwrite earlier ones.

Profiles for running the pipeline software are bundled with the pipeline: `docker`, `singularity`, `apptainer`, `podman`, `shifter`, `charliecloud`, `conda`, `mamba`, and `wave`.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility.
> If this is not possible, Conda is also supported.

Below are a set of custom profiles bundled with the pipeline:

- `stub` — runs the pipeline against a small bundled stub dataset; use together with `-stub`.
- `arm64` and `emulate_amd64` — for running on ARM-based machines (e.g. Apple Silicon).
- `batch`, `dev`, `scpca_testing`, and `scpca_staging` — ALSF-specific profiles for running on AWS Batch, defined in [`conf/alsf-profiles.config`](../conf/alsf-profiles.config).

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time.
For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`.
This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://charliecloud.io/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow `24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.

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

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#update-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#modifying-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Updating the pipeline

Nextflow caches the pipeline code the first time you run it, and will keep using the cached version even after the pipeline has been updated.
To make sure you are running the latest version:

```bash
nextflow pull AlexsLemonade/metafactory
```

## Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data, so that the same version of the code and software is used every time.
Find the latest version on the [releases page](https://github.com/AlexsLemonade/metafactory/releases) and specify it with `-r`, e.g. `-r 1.3.1`.
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
