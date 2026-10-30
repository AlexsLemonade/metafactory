# AlexsLemonade/metafactory: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.1.0 - [2026-11-02]

Initial release of AlexsLemonade/metafactory, created with the [nf-core](https://nf-co.re/) template.

### `Added`

Implementation of the `metafactory` workflow which computes metaprograms for a specified group of samples across a range of k values (number of metaprograms).
The optimal number of metaprograms is determined by calculating a set of metrics designed to identify biologically interpretable metaprograms.
This initial version of the pipeline requires input data to be stored as an `AnnData` object (`.h5ad` file).

Modules (`modules/local/`):

- `CNMF`: runs consensus NMF on each library to identify gene expression programs.
- `GENERATE_METAPROGRAMS`: correlates and clusters the spectra from every library in a group into `k` metaprograms, for each value of `k` in `--n_metaprograms`.
- `CALCULATE_METRICS_METAPROGRAMS`: calculates per-metaprogram metrics (effective sample size, correlation, coherence) and their background distributions.
- `CALCULATE_METRICS_GENESETS`: annotates metaprograms with MSigDB gene sets using ORA and calculates gene set specificity metrics.
- `CALCULATE_K`: ranks every value of `k` tested and picks the optimal value of `k` for each group.
- `PUBLISH_METAPROGRAMS`: copies the metaprograms for the optimal value of `k` into the final results directory for the group.
- `SCORE_METAPROGRAMS`: scores every cell in every library of a group against each metaprogram.
- `SCORE_BACKGROUND`: scores cells against gene-shuffled metaprograms to build a background score distribution.
- `COMBINE_SCORES`: combines per-library cell scores or background score stats into one table per metaprogram set.
- `RENDER_METRICS_REPORT`: renders a report comparing the metrics for every value of `k` tested for a group.
- `RENDER_INDIVIDUAL_REPORT`: renders an evaluation report for the metaprograms at the optimal value of `k`.

Subworkflows (`subworkflows/local/`):

- `CALCULATE_METRICS`: runs `CALCULATE_METRICS_METAPROGRAMS` and `CALCULATE_METRICS_GENESETS`.
- `CALCULATE_SCORES`: runs `SCORE_METAPROGRAMS`, `SCORE_BACKGROUND`, and `COMBINE_SCORES`.
- `GENERATE_REPORTS`: runs `RENDER_METRICS_REPORT` and `RENDER_INDIVIDUAL_REPORT`.

### `Fixed`

### `Dependencies`

### `Deprecated`
