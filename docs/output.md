# AlexsLemonade/metafactory: Output

## Introduction

This document describes the output produced by the pipeline.
All paths are relative to the directory provided with `--outdir`.

Output is split into three top-level directories:

- [`results/`](#results) - Final results for each group of samples, including the metaprograms for the optimal value of `k` and the reports
- [`checkpoints/`](#checkpoints) - Intermediate output from each step of the pipeline, for every value of `k` tested
- [`pipeline_info/`](#pipeline-information) - Reports and logs describing the pipeline run

```
<OUTDIR>
├── results
│   └── <group_id>
├── checkpoints
│   ├── cnmf
│   ├── metaprograms
│   ├── metrics
│   ├── metaprogram_scores
│   ├── background_scores
│   └── combined_scores
└── pipeline_info
```

Throughout this document, `<group_id>` and `<unique_id>` refer to the columns of the input samplesheet, and `<k>` refers to the number of metaprograms in a set, one of the values provided with `--n_metaprograms`.

## Results

The final results are written to `results/<group_id>/`, with one directory for each group of samples in the samplesheet.
Only the metaprograms and metrics for the optimal value of `k` chosen for the group are included here.
The output for all other values of `k` can be found in [`checkpoints/`](#checkpoints).

<details markdown="1">
<summary>Output files</summary>

- `results/<group_id>/`
  - `optimal-k.txt`: A text file holding the optimal value of `k` chosen for the group.
  - `combined-metaprogram-metrics.html`: The [metrics report](#metrics-report), comparing every value of `k` tested for the group.
  - `individual-metaprogram-evaluation.html`: The [individual metaprogram evaluation report](#individual-metaprogram-evaluation-report), evaluating the metaprograms for the optimal value of `k`.
  - `k-<k>_metaprograms.rds`: The [metaprograms object](#metaprograms-object) for the optimal value of `k`.
  - `k-<k>_mp_metrics.tsv`: [Metaprogram metrics](#metaprogram-metrics) for the optimal value of `k`.
  - `k-<k>_geneset_metrics.tsv`: [Gene set metrics](#gene-set-metrics) for the optimal value of `k`.
  - `k-<k>_ora_results.tsv`: [Overrepresentation analysis (ORA) results](#ora-results) for the optimal value of `k`.
  - `k-<k>_combined_metaprogram_scores.tsv.gz`: [Metaprogram scores](#metaprogram-scores) for every cell in every library in the group, for the optimal value of `k`.
  - `reports/`: Tables used to build the metrics report, holding metrics for every value of `k` tested.
    - `all-k_summary_metrics.tsv`: [Summary metrics](#summary-metrics-for-each-value-of-k) for each value of `k`, used to choose the optimal value of `k`.
    - `all-k_metaprogram_metrics.tsv`: [Metrics for every metaprogram](#metrics-for-every-metaprogram-across-all-values-of-k) across all values of `k`.
    - `all-k_background_eff_sample_size.tsv.gz`: Null distribution of the normalized effective sample size (columns: `n_metaprograms`, `metaprogram`, `replicate`, `eff_number_norm`).
    - `all-k_background_geneset_specificity.tsv.gz`: Null distribution of the overall gene set specificity, with one row per permutation replicate per value of `k` (columns: `n_metaprograms`, `replicate`, `overall_geneset_specificity`).
    - `all-k_background_cell_score_cv.tsv.gz`: Null distribution of the coefficient of variation (CV) of cell scores (columns: `n_metaprograms`, `metaprogram`, `replicate`, `score_cv`).

</details>

### Reports

#### Metrics report

`combined-metaprogram-metrics.html` compares the metrics calculated for every value of `k` tested for a group, and describes how the optimal value of `k` was chosen.
It includes sections on sample diversity (proportion of samples and normalized effective sample size), correlation between metaprograms, coherence, gene set specificity, and variation in cell scores, followed by a heatmap of the normalized rank of each metric for each value of `k`.
Any values of `k` that were excluded from the comparison are listed at the top of the report.

#### Individual metaprogram evaluation report

`individual-metaprogram-evaluation.html` evaluates the set of metaprograms for the optimal value of `k`.
It includes the parameters used to build the metaprograms and sections on the redundancy of metaprograms, the diversity of libraries contributing to each metaprogram, biological interpretability based on the top genes and ORA results, and the distribution of metaprogram scores across cells and samples.

### Choosing the optimal value of `k`

Each value of `k` is evaluated using five metrics. 
Note that any value of `k` with at least one metaprogram made up of a single spectra is excluded from these comparisons. 

1. **Normalized effective sample size**: The proportion of metaprograms with a normalized effective sample size significantly greater than the null distribution.
2. **Correlation of gene weights**: The proportion of metaprograms with a maximum correlation to all other metaprograms at or below 0.5.
3. **Coherence**: Whether the value of `k` is at, below, or above the elbow of the median coherence curve, identified with the kneedle algorithm.
   Values of `k` at the elbow score 1, values below the elbow score 0.5, and values above the elbow score 0.
   If no elbow can be found, every value of `k` scores 0.5.
4. **Gene set specificity**: Whether the overall gene set specificity is significantly greater than the null distribution.
5. **Variation in cell scores**: The proportion of metaprograms with a CV of cell scores significantly greater than the null distribution.

Each metric is ranked across all values of `k` and the ranks are normalized to a 0-1 scale.
The value of `k` with the highest mean rank across all metrics is chosen as the optimal value of `k`.
Any ties are broken by the rank for variation in cell scores.
Significance for all metrics is determined using an adjusted p-value cutoff of 0.05, with null distributions built from `--nreps` permutation replicates.

### File formats

#### Metaprograms object

`k-<k>_metaprograms.rds` is an RDS file holding a list with the following items:

| Item                    | Description                                                                                                      |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `metaprogram_list`      | Gene weights for each metaprogram                                                                                |
| `clusters`              | Cluster (metaprogram) assignment for each spectra                                                                |
| `cluster_list`          | Spectra assigned to each metaprogram                                                                             |
| `cor_matrix`            | Correlation matrix of all spectra                                                                                |
| `spectra_cor_df`        | Data frame with correlation information for all spectra                                                          |
| `shuffled_metaprograms` | Shuffled metaprograms (top genes only) for each permutation replicate, used to build null distributions          |
| `gene_universe`         | All genes used to calculate metaprograms                                                                         |
| `top_genes`             | The top `--n_top_genes` gene IDs for each metaprogram, ordered by decreasing weight                               |
| `n_metaprograms`        | Number of metaprograms (`k`)                                                                                     |
| `n_top_genes`           | Number of top genes kept for each metaprogram                                                                    |
| `cnmf_k_range`          | Values of `k` used with cNMF                                                                                     |
| `filter_spectra`        | Whether orphan spectra were removed                                                                              |
| `orphan_cutoff`         | Minimum cross-sample correlation required to keep a spectra if orphan spectra were removed, or `-1` if they were not |
| `unique_ids`            | Unique IDs of the libraries used to build the metaprograms                                                       |
| `removed_unique_ids`    | Unique IDs of the libraries removed when filtering spectra                                                       |

#### Metaprogram metrics

`k-<k>_mp_metrics.tsv` has one row per metaprogram with the following columns:

| Column                               | Description                                                                                       |
| ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `metaprogram`                        | Metaprogram identifier                                                                            |
| `max_correlation`                    | Maximum correlation of the metaprogram's gene weights to all other metaprograms                   |
| `median_difference`                  | Coherence, the difference in median correlation of spectra within and between metaprograms       |
| `num_spectra_per_mp`                 | Number of spectra in the metaprogram                                                              |
| `num_samples`                        | Number of samples represented in the metaprogram                                                  |
| `proportion_of_samples`              | Proportion of all samples represented in the metaprogram                                          |
| `shannon_entropy`                    | Shannon entropy measuring the relative abundance of samples in the metaprogram                    |
| `shannon_entropy_norm`               | Normalized Shannon entropy                                                                        |
| `eff_number`                         | Effective sample size                                                                             |
| `eff_number_norm`                    | Effective sample size normalized by the total samples in the metaprogram                          |
| `greater_pvalue_eff_number_norm`     | P-value for the normalized effective sample size being greater than the null distribution         |
| `greater_adj_pvalue_eff_number_norm` | Adjusted p-value for the normalized effective sample size being greater than the null distribution |

#### Gene set metrics

`k-<k>_geneset_metrics.tsv` has one row per metaprogram with the following columns:

| Column                     | Description                                                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `metaprogram`              | Metaprogram identifier                                                                                              |
| `num_sig_genesets`         | Number of gene sets identified as significant by ORA                                                                |
| `mean_geneset_specificity` | Mean specificity of all significant gene sets for the metaprogram. `NA` if the metaprogram has no significant gene sets. |

#### ORA results

`k-<k>_ora_results.tsv` has one row per significant gene set per metaprogram (adjusted p-value ≤ 0.05).
ORA is performed on the top `--n_top_genes` genes of each metaprogram against the gene sets provided with `--msigdb_gene_sets`, using [`clusterProfiler::enricher()`](https://yulab-smu.top/biomedical-knowledge-mining-book/universal-api.html).
The table holds the full results returned by `enricher()`, including the `geneID` column listing the genes in each gene set that overlap the metaprogram's top genes.

#### Metaprogram scores

`k-<k>_combined_metaprogram_scores.tsv.gz` is a long format table with one row per cell per metaprogram, with the following columns:

| Column        | Description                                 |
| ------------- | ------------------------------------------- |
| `metaprogram` | Metaprogram identifier                      |
| `barcodes`    | Cell barcode                                |
| `mp_score`    | Score for the cell against the metaprogram  |
| `unique_id`   | Unique ID of the library the cell came from |

Scores are calculated as the dot product of the gene weights for the top genes in each metaprogram and the quantile-normalized expression of those genes in each cell.
If `--celltype_annotation_column` and `--analysis_celltypes` are provided, only cells of the selected cell types are scored.

#### Summary metrics for each value of `k`

`reports/all-k_summary_metrics.tsv` has one row per value of `k` with the following columns:

| Column                                                                    | Description                                                                                           |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `n_metaprograms`                                                          | Value of `k`                                                                                          |
| `is_excluded`                                                             | Whether the value of `k` was excluded from the comparison. Excluded values of `k` have no metrics.    |
| `is_optimal_k`                                                            | Whether this value of `k` was chosen as the optimal value of `k`                                      |
| `num_metaprograms`                                                        | Number of metaprograms                                                                                |
| `neff_sig_number`, `neff_sig_proportion`                                  | Number and proportion of metaprograms with a significant normalized effective sample size             |
| `num_passing_correlation`, `proportion_passing_correlation`               | Number and proportion of metaprograms with a maximum correlation at or below 0.5                      |
| `num_passing_coherence`                                                   | Number of metaprograms with a coherence greater than 0.1                                              |
| `median_coherence`                                                        | Median coherence across all metaprograms                                                              |
| `num_metaprograms_with_genesets`, `proportion_metaprograms_with_genesets` | Number and proportion of metaprograms with at least one significant gene set                          |
| `overall_geneset_specificity`                                             | Mean gene set specificity across all metaprograms with at least one significant gene set              |
| `num_significant_cv`, `proportion_significant_cv`                         | Number and proportion of metaprograms with a significant CV of cell scores                            |
| `total_samples`                                                           | Number of libraries with cell scores                                                                  |
| `is_coherence_elbow`                                                      | Whether this value of `k` is the elbow of the median coherence curve                                  |
| `coherence_elbow_passing`                                                 | Coherence score used for ranking: 1 at the elbow, 0.5 below the elbow or if there is no elbow, 0 above |
| `geneset_specificity_pvalue`, `geneset_specificity_adj_pvalue`            | P-value and adjusted p-value for the overall gene set specificity being greater than the null distribution |
| `geneset_specificity_significant`                                         | Whether the overall gene set specificity is significant (1) or not (0)                                |
| `rank_effective_sample_size`                                              | Normalized rank of `neff_sig_proportion`                                                              |
| `rank_correlation`                                                        | Normalized rank of `proportion_passing_correlation`                                                   |
| `rank_coherence`                                                          | Normalized rank of `coherence_elbow_passing`                                                          |
| `rank_gene_set_specificity`                                               | Normalized rank of `geneset_specificity_significant`                                                  |
| `rank_coefficient_of_variation`                                           | Normalized rank of `proportion_significant_cv`                                                        |
| `mean_rank`                                                               | Mean of the five normalized ranks                                                                     |

#### Metrics for every metaprogram across all values of `k`

`reports/all-k_metaprogram_metrics.tsv` has one row per metaprogram per value of `k`, for every value of `k` that was not excluded.
It holds an `n_metaprograms` column with the value of `k`, all columns of the [metaprogram metrics](#metaprogram-metrics) and [gene set metrics](#gene-set-metrics) tables, and the following additional columns:

| Column                                                       | Description                                                                        |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| `neff_is_significant`                                        | Whether the normalized effective sample size is significant                        |
| `correlation_is_passing`                                     | Whether `max_correlation` is at or below 0.5                                       |
| `coherence_is_passing`                                       | Whether coherence (`median_difference`) is greater than 0.1                        |
| `score_var`, `score_cv`                                      | Variance and CV of the metaprogram scores across all cells                         |
| `greater_pvalue_score_cv`, `greater_adj_pvalue_score_cv`     | P-value and adjusted p-value for the CV being greater than the null distribution   |
| `cv_is_significant`                                          | Whether the CV of cell scores is significant                                       |

## Checkpoints

Intermediate output from each step of the pipeline is written to `checkpoints/`.
Unlike `results/`, these directories hold the output for every value of `k` tested, not only the optimal value of `k`.

Output for each set of metaprograms is written to a subdirectory named for the group, the value of `k`, and the spectra filtering settings used to build the metaprograms:

- `<group_id>/k-<k>_filtered_<cutoff>/` if orphan spectra were removed (`--metaprograms_filter_spectra true`), where `<cutoff>` is the value of `--metaprograms_orphan_cutoff`
- `<group_id>/k-<k>_unfiltered/` if orphan spectra were not removed

Below, this subdirectory is referred to as `<group_id>/<metaprogram_set>/`.

<details markdown="1">
<summary>Output files</summary>

- `checkpoints/cnmf/<unique_id>_cnmf/`
  - `*.gene_spectra_score.k_*.dt_*.txt`: Consensus gene expression programs (spectra) from cNMF, one file for each value of `k` tested in cNMF.
  - `cnmf-meta.json`: The cNMF options used for this library.
- `checkpoints/metaprograms/<group_id>/<metaprogram_set>/`
  - `k-<k>_metaprograms.rds`: The [metaprograms object](#metaprograms-object).
  - `k-<k>_metaprograms.tsv.gz`: The gene weights for each metaprogram in long format (columns: `metaprogram`, `gene_id`, `weight`).
  - `k-<k>_shuffled_metaprograms.tsv.gz`: The gene weights for the top genes of each shuffled metaprogram for each permutation replicate (columns: `replicate`, `metaprogram`, `gene_id`, `weight`).
- `checkpoints/metrics/<group_id>/<metaprogram_set>/`
  - `k-<k>_mp_metrics.tsv`: [Metaprogram metrics](#metaprogram-metrics).
  - `k-<k>_background_mp_stats.tsv.gz`: Null distribution of the metaprogram sample statistics, with one row per metaprogram per permutation replicate.
  - `k-<k>_geneset_metrics.tsv`: [Gene set metrics](#gene-set-metrics).
  - `k-<k>_background_specificity.tsv.gz`: Null distribution of the gene set specificity, with one row per metaprogram per permutation replicate (columns: `replicate`, `metaprogram`, `mean_geneset_specificity`, `overall_geneset_specificity`).
  - `k-<k>_ora_results.tsv`: [ORA results](#ora-results).
- `checkpoints/metaprogram_scores/<group_id>/<metaprogram_set>/`
  - `<unique_id>_metaprogram_scores.tsv.gz`: [Metaprogram scores](#metaprogram-scores) for each cell in a single library.
- `checkpoints/background_scores/<group_id>/<metaprogram_set>/`
  - `<unique_id>_background_score_stats.tsv.gz`: Summary statistics of the scores for each shuffled metaprogram in a single library, used to build the null distribution of the CV of cell scores (columns: `metaprogram`, `replicate`, `num_cells`, `mean_mp_score`, `M2`, `unique_id`).
- `checkpoints/combined_scores/<group_id>/<metaprogram_set>/`
  - `k-<k>_combined_metaprogram_scores.tsv.gz`: [Metaprogram scores](#metaprogram-scores) for all libraries in the group.
  - `k-<k>_combined_background_score_stats.tsv.gz`: Background score statistics for all libraries in the group.

</details>

### Reusing cNMF results

cNMF is the most time consuming step of the pipeline, so existing cNMF results are reused when the pipeline is run again with the same `--outdir` and same cNMF parameters.
`cnmf-meta.json` records the options used to run cNMF for each library (`cnmf_k_lower`, `cnmf_k_upper`, `cnmf_k_step_size`, `celltype_annotation_column`, `analysis_celltypes`, and `seed`).
If `checkpoints/cnmf/<unique_id>_cnmf/cnmf-meta.json` exists and all of these options match the current run, cNMF is skipped for that library and the existing results are used.
Use `--repeat_cnmf` to run cNMF for every library, even if existing results were created with the same options.

## Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report_<timestamp>.html`, `execution_timeline_<timestamp>.html`, `execution_trace_<timestamp>.txt` and `pipeline_dag_<timestamp>.html`.
  - Parameters used by the pipeline run: `params_<timestamp>.json`.
  - Versions of the software used in each step of the pipeline: `metafactory_software_versions.yml`.

</details>

`<timestamp>` is the date and time the pipeline was launched, in the format `yyyy-MM-dd_HH-mm-ss`, and can be changed with `--trace_report_suffix`.

[Nextflow](https://docs.seqera.io/platform-cloud/reports/overview) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
