# AlexsLemonade/metafactory

[![GitHub Actions CI Status](https://github.com/AlexsLemonade/metafactory/actions/workflows/nf-test.yml/badge.svg)](https://github.com/AlexsLemonade/metafactory/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/AlexsLemonade/metafactory/actions/workflows/linting.yml/badge.svg)](https://github.com/AlexsLemonade/metafactory/actions/workflows/linting.yml)[![Cite with Zenodo](http://img.shields.io/badge/DOI-10.5281/zenodo.XXXXXXX-1073c8?labelColor=000000)](https://doi.org/10.5281/zenodo.XXXXXXX)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A525.10.4-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-4.1.0-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/4.1.0)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/AlexsLemonade/metafactory)

## Introduction

`metafactory` is a Nextflow pipeline for identifying _metaprograms_ — recurrent gene expression programs that are shared across samples — from single-cell and single-nuclei RNA-sequencing data.

Gene expression programs are first found within each sample independently using consensus non-negative matrix factorization (cNMF).
The programs from every sample in a cohort are then compared to one another and clustered into metaprograms, so that only the programs that recur across multiple samples are retained.
Because the number of metaprograms (`k`) present in a cohort is not known ahead of time, the pipeline builds metaprograms across a range of values of `k`, evaluates each set with a panel of metrics, and reports the optimal value of `k` along with the metaprograms, their gene set annotations, and a score for every cell.

### Pipeline summary

1. **Use [`cNMF`](https://github.com/dylkot/cNMF) to identify gene expression programs in each sample.**
   cNMF is run on the raw counts across a range of components to produce a set of consensus gene expression programs (spectra) for each sample.
   By default, all cells are used but cells can be optionally subset to the cell types of interest prior to running `cNMF`.
2. **Build metaprograms for each group of samples.**
   The spectra from all samples in a group are combined and correlated, low-correlation (orphan) spectra are optionally removed, and the remaining spectra are hierarchically clustered into `k` metaprograms.
   Each metaprogram is a set of gene weights averaged across the spectra assigned to it.
   This step is repeated for every value of `k` specified using the `--n_metaprograms` parameter.
3. **Annotate metaprograms with gene sets.**
   Overrepresentation analysis (ORA) is run on the top genes of each metaprogram against a set of MSigDB gene sets.
4. **Score cells against metaprograms.**
   Every cell in every sample of a group is scored against each metaprogram built for that group.
   Scores are calculated by taking the dot product of the gene weights for the top genes in each metaprogram and the quantile-normalized expression of those genes in a given cell.
5. **Calculate metaprogram metrics.**
   Metrics describing the interpretability of each metaprogram are calculated.
   These include: normalized effective sample size, correlation, coherence of individual gene expression programs within a metaprogram, gene set specificity, and coefficient of variation of cell scores.
6. **Choose the optimal value of `k`.**
   All values of `k` tested for a group are compared using the five metrics described in step 5.
   Each metric is ranked across values of `k`, and the value of `k` with the highest mean rank is selected.

**Caution:** `metafactory` is actively in development.

## Usage

> [!NOTE]
> If you are new to Nextflow and nf-core, please refer to [this page](https://nf-co.re/docs/get_started/environment_setup/overview) on how to set-up Nextflow. Make sure to [test your setup](https://nf-co.re/docs/get_started/run-your-first-pipeline) with `-profile test` before running the workflow on actual data.

### Input

The pipeline takes filtered and normalized single-cell/single-nuclei objects, one per library, provided as AnnData `.h5ad` files.
Currently, the pipeline has been developed to handle processed `AnnData` objects from [ScPCA](https://scpca.alexslemonade.org), but future work will expand support to other single-cell file types.
Cells are expected to have already been filtered, and raw counts are expected to be available alongside the normalized data.

Samples are described in a comma-separated samplesheet with three columns and a header row:

| Column      | Description                                                                                                                                     |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `unique_id` | Unique identifier for the library. Used to name all per-library output.                                                                         |
| `group_id`  | Identifier for the group of samples that metaprograms are built across. All libraries sharing a `group_id` are analyzed together as one cohort. |
| `h5ad_file` | Path to the filtered and normalized `.h5ad` file for that library. Local and remote (e.g. `s3://`) paths are both supported.                    |

Metaprograms are built once per `group_id`, so a single run can process multiple independent cohorts.

### Running the pipeline

```bash
nextflow run AlexsLemonade/metafactory \
   -profile <docker/singularity/.../institute> \
   --input samplesheet.csv \
   --outdir <OUTDIR>
```

> [!WARNING]
> Please provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration _**except for parameters**_; see [docs](https://nf-co.re/docs/running/run-pipelines#using-parameter-files).

## Output

Final results are written to `<OUTDIR>/results/<group_id>/`, with one directory per group.
For each group, the pipeline produces:

- **Metaprograms for the optimal value of `k`** — the metaprograms object holding the gene weights for each metaprogram, the spectra assigned to it, and the parameters used to build it.
- **Metrics report** — a report summarizing the metrics calculated for every value of `k` tested, the metrics used to rank them, and the value of `k` that was selected.
- **ORA results** — the gene sets significantly associated with each metaprogram, as identified by overrepresentation analysis of its top genes.
- **Metaprogram scores** — a table of scores for every cell in every library of the group against each metaprogram.

Intermediate output from each step, including the results for the values of `k` that were not selected, is written to `<OUTDIR>/checkpoints/`.
Nextflow execution reports, the validated samplesheet, the parameters used, and the software versions are written to `<OUTDIR>/pipeline_info/`.

## Parameters

The pipeline parameters, including the samplesheet format and the options controlling cNMF and metaprogram generation, are described in [`docs/usage.md`](docs/usage.md).
A full, automatically generated description of every parameter is also available with `nextflow run AlexsLemonade/metafactory --help` (or `--help_full` for the complete list).

## Credits

AlexsLemonade/metafactory was originally written by Ally Hawkins.

We thank the following people for their extensive assistance in the development of this pipeline:

<!-- TODO nf-core: If applicable, make list of people who have also contributed -->

## Contributions and Support

If you would like to contribute to this pipeline, please see the [contributing guidelines](docs/CONTRIBUTING.md).

## Citations

<!-- TODO nf-core: Add citation for pipeline after first release. Uncomment lines below and update Zenodo doi and badge at the top of this file. -->
<!-- If you use AlexsLemonade/metafactory for your analysis, please cite it using the following doi: [10.5281/zenodo.XXXXXX](https://doi.org/10.5281/zenodo.XXXXXX) -->

<!-- TODO nf-core: Add bibliography of tools and data used in your pipeline -->

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.

This pipeline uses code and infrastructure developed and maintained by the [nf-core](https://nf-co.re) community, reused here under the [MIT license](https://github.com/nf-core/tools/blob/main/LICENSE).

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).
