# AlexsLemonade/metafactory: Output

## Introduction

This document describes the output produced by the pipeline.
All paths are relative to the directory provided with `--outdir`.

Output is split into three top-level directories:

- [`results/`](#results) - Final results for each group of libraries, including the metaprograms for the optimal value of `k` and the reports
- [`checkpoints/`](#checkpoints) - Intermediate output from each step of the pipeline, for every metaprogram set
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

Throughout this document, `<group_id>` and `<unique_id>` refer to the columns of the input samplesheet, and `<n>` refers to the number of metaprograms in a metaprogram set, one of the k values provided with `--n_metaprograms` from which the optimal k is chosen.
The `k-<n>_` and `all-k_` file prefixes refer to the number of metaprograms, not cNMF k.

## Results

The final results are written to `results/<group_id>/`, with one directory for each group of libraries in the samplesheet.
Only the metaprograms and metrics for the optimal value of `k` chosen for the group are included here.
The output for all other metaprogram sets can be found in [`checkpoints/`](#checkpoints).

<details markdown="1">
<summary>Output files</summary>

- `results/<group_id>/`
  - `optimal-k.txt`: A text file holding the optimal value of `k` chosen for the group.
  - `combined-metaprogram-metrics.html`: The [metrics report](#metrics-report), comparing every metaprogram set built for the group.
  - `individual-metaprogram-evaluation.html`: The [individual metaprogram evaluation report](#individual-metaprogram-evaluation-report), evaluating the metaprograms for the optimal value of `k`.
  - `k-<n>_metaprograms.rds`: The [metaprograms object](#metaprograms-object) for the optimal value of `k`.
  - `k-<n>_mp_metrics.tsv`: [Metaprogram metrics](#metaprogram-metrics) for the optimal value of `k`.
  - `k-<n>_geneset_metrics.tsv`: [Gene set metrics](#gene-set-metrics) for the optimal value of `k`.
  - `k-<n>_ora_results.tsv`: [Overrepresentation analysis (ORA) results](#ora-results) for the optimal value of `k`.
  - `k-<n>_combined_metaprogram_scores.tsv.gz`: [Cell scores](#cell-scores) for every cell in every library in the group, for the optimal value of `k`.
  - `reports/`: Tables used to build the metrics report, holding metrics for every metaprogram set.
    - `all-k_summary_metrics.tsv`: [Summary metrics](#summary-metrics-for-each-metaprogram-set) for each metaprogram set, used to choose the optimal value of `k`.
    - `all-k_metaprogram_metrics.tsv`: [Metrics for every metaprogram](#metrics-for-every-metaprogram-across-all-metaprogram-sets) across all metaprogram sets.
    - `all-k_background_eff_library_count.tsv.gz`: Metric background of the normalized effective library count (columns: `n_metaprograms`, `metaprogram`, `replicate`, `eff_number_norm`).
    - `all-k_background_geneset_specificity.tsv.gz`: Metric background of the overall gene set specificity, with one row per permutation replicate per metaprogram set (columns: `n_metaprograms`, `replicate`, `overall_geneset_specificity`).
    - `all-k_background_cell_score_cv.tsv.gz`: Score background of the coefficient of variation (CV) of cell scores (columns: `n_metaprograms`, `metaprogram`, `replicate`, `score_cv`).

</details>

### Reports

#### Metrics report

`combined-metaprogram-metrics.html` compares the metrics calculated for every metaprogram set built for a group, and describes how the optimal value of `k` was chosen.
It includes sections on library diversity (proportion of libraries and normalized effective library count), maximum metaprogram correlation, coherence, gene set specificity, and CV of cell scores, followed by a heatmap of the normalized rank of each metric for each metaprogram set.
Any excluded metaprogram sets are listed at the top of the report.

#### Individual metaprogram evaluation report

`individual-metaprogram-evaluation.html` evaluates the set of metaprograms for the optimal value of `k`.
It includes the parameters used to build the metaprograms and sections on the redundancy of metaprograms, the diversity of libraries contributing to each metaprogram, biological interpretability based on the top genes and ORA results, and the distribution of cell scores across cells and libraries.

### Choosing the optimal value of `k`

Each metaprogram set is evaluated using five metrics.
Note that any value of `k` with at least one metaprogram made up of a single spectrum is excluded from these comparisons.

1. **Normalized effective library count**: The proportion of metaprograms with a normalized effective library count significantly greater than the metric background.
2. **Maximum metaprogram correlation**: The proportion of metaprograms with a maximum metaprogram correlation at or below 0.5.
3. **Coherence**: Whether the k value (number of metaprograms) is at, below, or above the elbow of the median coherence curve, identified with the kneedle algorithm.
   k values at the elbow score 1, those below the elbow score 0.5, and those above the elbow score 0.
   If no elbow can be found, every metaprogram set scores 0.5.
4. **Gene set specificity**: Whether the overall gene set specificity differs significantly from its metric background, using a two-sided permutation test.
5. **CV of cell scores**: The proportion of metaprograms with a CV of cell scores significantly greater than the score background.

Each metric is ranked across all metaprogram sets and the ranks are normalized to a 0-1 scale.
The number of metaprograms with the highest mean rank across all metrics is chosen as the optimal value of `k`.
Any ties are broken by the rank for CV of cell scores.
Significance for all metrics is determined using an adjusted p-value cutoff of 0.05, with the metric backgrounds and score background built from `--nreps` permutation replicates.

### File formats

#### Metaprograms object

`k-<n>_metaprograms.rds` is an RDS file holding a list with the following items:

<!-- prettier-ignore -->
| Item                    | Description  
| ----------------------- | --------------------------------------------------------------------------------------------------------------------
| `metaprogram_list`      | Gene weights for each metaprogram  
| `clusters`              | Cluster (metaprogram) assignment for each spectrum  
| `cluster_list`          | Spectra assigned to each metaprogram  
| `cor_matrix`            | Correlation matrix of all spectra  
| `spectra_cor_df`        | Data frame with correlation information for all spectra  
| `shuffled_metaprograms` | Shuffled metaprograms (top genes only) for each permutation replicate, used to build the score background  
| `gene_universe`         | All genes used to calculate metaprograms; genes found only in orphan spectra are excluded when spectra are filtered  
| `top_genes`             | The top `--n_top_genes` gene IDs for each metaprogram, ordered by decreasing weight  
| `n_metaprograms`        | Number of metaprograms (`k`)  
| `n_top_genes`           | Number of top genes kept for each metaprogram  
| `cnmf_k_range`          | Values of cNMF k (rank) used with cNMF  
| `filter_spectra`        | Whether orphan spectra were removed  
| `orphan_cutoff`         | Orphan cutoff used to remove orphan spectra, or `-1` if they were not removed
| `unique_ids`            | Unique IDs of the libraries used to build the metaprograms  
| `removed_unique_ids`    | Unique IDs of the libraries removed when filtering spectra

#### Metaprogram metrics

`k-<n>_mp_metrics.tsv` has one row per metaprogram with the following columns:

<!-- prettier-ignore -->
| Column                               | Description  
| ------------------------------------ | --------------------------------------------------------------------------------------------------
| `metaprogram`                        | Metaprogram identifier  
| `max_correlation`                    | Maximum metaprogram correlation  
| `median_difference`                  | Coherence, the difference in median correlation of spectra within and between metaprograms  
| `num_spectra_per_mp`                 | Number of spectra in the metaprogram  
| `num_libraries`                        | Number of libraries represented in the metaprogram  
| `proportion_of_libraries`              | Proportion of all libraries represented in the metaprogram  
| `shannon_entropy`                    | Shannon entropy measuring the relative abundance of libraries in the metaprogram  
| `shannon_entropy_norm`               | Normalized Shannon entropy  
| `eff_number`                         | Effective library count  
| `eff_number_norm`                    | Effective library count normalized by the total libraries in the metaprogram  
| `greater_pvalue_eff_number_norm`     | P-value for the normalized effective library count being greater than the metric background  
| `greater_adj_pvalue_eff_number_norm` | Adjusted p-value for the normalized effective library count being greater than the metric background

#### Gene set metrics

`k-<n>_geneset_metrics.tsv` has one row per metaprogram with the following columns:

<!-- prettier-ignore -->
| Column                     | Description  
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------
| `metaprogram`              | Metaprogram identifier  
| `num_sig_genesets`         | Number of gene sets identified as significant by ORA  
| `mean_geneset_specificity` | Mean specificity of all significant gene sets for the metaprogram. `NA` if the metaprogram has no significant gene sets.

#### ORA results

`k-<n>_ora_results.tsv` has one row per significant gene set per metaprogram (adjusted p-value ≤ 0.05).
ORA is performed on the top `--n_top_genes` genes of each metaprogram against the gene sets provided with `--msigdb_gene_sets`, using [`clusterProfiler::enricher()`](https://yulab-smu.top/biomedical-knowledge-mining-book/universal-api.html).
The table holds the full results returned by `enricher()`, including the `geneID` column listing the genes in each gene set that overlap the metaprogram's top genes.

#### Cell scores

`k-<n>_combined_metaprogram_scores.tsv.gz` is a long format table with one row per cell per metaprogram, with the following columns:

<!-- prettier-ignore -->
| Column        | Description  
| ------------- | -------------------------------------------
| `metaprogram` | Metaprogram identifier  
| `barcodes`    | Cell barcode  
| `mp_score`    | Cell score for the cell against the metaprogram  
| `unique_id`   | Unique ID of the library the cell came from

Cell scores are calculated as the dot product of the gene weights for the top genes in each metaprogram and the quantile-normalized expression of those genes in each cell.
If `--celltype_annotation_column` and `--analysis_celltypes` are provided, only cells of the selected cell types are scored.

#### Summary metrics for each metaprogram set

`reports/all-k_summary_metrics.tsv` has one row per metaprogram set with the following columns:

<!-- prettier-ignore -->
| Column                                                                    | Description  
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------
| `n_metaprograms`                                                          | Number of metaprograms in the metaprogram set  
| `is_excluded`                                                             | Whether the metaprogram set is an excluded metaprogram set. Excluded metaprogram sets have no metrics.  
| `is_optimal_k`                                                            | Whether this number of metaprograms was chosen as the optimal value of `k`  
| `num_metaprograms`                                                        | Number of metaprograms  
| `neff_sig_number`, `neff_sig_proportion`                                  | Number and proportion of metaprograms with a significant normalized effective library count  
| `num_passing_correlation`, `proportion_passing_correlation`               | Number and proportion of metaprograms with a maximum metaprogram correlation at or below 0.5  
| `num_passing_coherence`                                                   | Number of metaprograms with a coherence greater than 0.1  
| `median_coherence`                                                        | Median coherence across all metaprograms  
| `num_metaprograms_with_genesets`, `proportion_metaprograms_with_genesets` | Number and proportion of metaprograms with at least one significant gene set  
| `overall_geneset_specificity`                                             | Mean gene set specificity across all metaprograms with at least one significant gene set  
| `num_significant_cv`, `proportion_significant_cv`                         | Number and proportion of metaprograms with a significant CV of cell scores  
| `total_libraries`                                                           | Number of libraries with cell scores  
| `is_coherence_elbow`                                                      | Whether this number of metaprograms is the elbow of the median coherence curve  
| `coherence_elbow_passing`                                                 | Coherence score used for ranking: 1 at the elbow, 0.5 below the elbow or if there is no elbow, 0 above  
| `geneset_specificity_pvalue`, `geneset_specificity_adj_pvalue`            | P-value and adjusted p-value for the overall gene set specificity being significantly different compared to the metric background using a two-sided permutation test
| `geneset_specificity_significant`                                         | Whether the overall gene set specificity is significant (1) or not (0)  
| `rank_effective_library_count`                                              | Normalized rank of `neff_sig_proportion`  
| `rank_correlation`                                                        | Normalized rank of `proportion_passing_correlation`  
| `rank_coherence`                                                          | Normalized rank of `coherence_elbow_passing`  
| `rank_gene_set_specificity`                                               | Normalized rank of `geneset_specificity_significant`  
| `rank_coefficient_of_variation`                                           | Normalized rank of `proportion_significant_cv`  
| `mean_rank`                                                               | Mean of the five normalized ranks

#### Metrics for every metaprogram across all metaprogram sets

`reports/all-k_metaprogram_metrics.tsv` has one row per metaprogram per metaprogram set, for every metaprogram set that was not excluded.
It holds an `n_metaprograms` column with the number of metaprograms, all columns of the [metaprogram metrics](#metaprogram-metrics) and [gene set metrics](#gene-set-metrics) tables, and the following additional columns:

<!-- prettier-ignore -->
| Column                                                   | Description  
| -------------------------------------------------------- | --------------------------------------------------------------------------------
| `neff_is_significant`                                    | Whether the normalized effective library count is significant  
| `correlation_is_passing`                                 | Whether the maximum metaprogram correlation (`max_correlation`) is at or below 0.5  
| `coherence_is_passing`                                   | Whether coherence (`median_difference`) is greater than 0.1  
| `score_var`, `score_cv`                                  | Variance and CV of the cell scores across all cells  
| `greater_pvalue_score_cv`, `greater_adj_pvalue_score_cv` | P-value and adjusted p-value for the CV of cell scores being greater than the score background
| `cv_is_significant`                                      | Whether the CV of cell scores is significant

## Checkpoints

Intermediate output from each step of the pipeline is written to `checkpoints/`.
Unlike `results/`, these directories hold the output for every metaprogram set, not only the one for the optimal value of `k`.

Output for each set of metaprograms is written to a subdirectory named for the group, the number of metaprograms, and the spectra filtering settings used to build the metaprograms:

- `<group_id>/k-<n>_filtered_<cutoff>/` if orphan spectra were removed (`--metaprograms_filter_spectra true`), where `<cutoff>` is the value of `--metaprograms_orphan_cutoff`
- `<group_id>/k-<n>_unfiltered/` if orphan spectra were not removed

Below, this subdirectory is referred to as `<group_id>/<metaprogram_set>/`.

<details markdown="1">
<summary>Output files</summary>

- `checkpoints/cnmf/<unique_id>_cnmf/`
  - `*.gene_spectra_score.k_*.dt_*.txt`: Consensus NMF programs (spectra) from cNMF, one file for each value of cNMF k (rank) tested.
  - `cnmf-meta.json`: The cNMF options used for this library.
- `checkpoints/metaprograms/<group_id>/<metaprogram_set>/`
  - `k-<n>_metaprograms.rds`: The [metaprograms object](#metaprograms-object).
  - `k-<n>_metaprograms.tsv.gz`: The gene weights for each metaprogram in long format (columns: `metaprogram`, `gene_id`, `weight`).
  - `k-<n>_shuffled_metaprograms.tsv.gz`: The gene weights for the top genes of each shuffled metaprogram for each permutation replicate (columns: `replicate`, `metaprogram`, `gene_id`, `weight`).
- `checkpoints/metrics/<group_id>/<metaprogram_set>/`
  - `k-<n>_mp_metrics.tsv`: [Metaprogram metrics](#metaprogram-metrics).
  - `k-<n>_background_mp_stats.tsv.gz`: Metric background of the metaprogram library diversity stats, with one row per metaprogram per permutation replicate.
  - `k-<n>_geneset_metrics.tsv`: [Gene set metrics](#gene-set-metrics).
  - `k-<n>_background_specificity.tsv.gz`: Metric background of the gene set specificity, with one row per metaprogram per permutation replicate (columns: `replicate`, `metaprogram`, `mean_geneset_specificity`, `overall_geneset_specificity`).
  - `k-<n>_ora_results.tsv`: [ORA results](#ora-results).
- `checkpoints/metaprogram_scores/<group_id>/<metaprogram_set>/`
  - `<unique_id>_metaprogram_scores.tsv.gz`: [Cell scores](#cell-scores) for each cell in a single library.
- `checkpoints/background_scores/<group_id>/<metaprogram_set>/`
  - `<unique_id>_background_score_stats.tsv.gz`: Summary statistics of the cell scores for each shuffled metaprogram in a single library, used to build the score background of the CV of cell scores (columns: `metaprogram`, `replicate`, `num_cells`, `mean_mp_score`, `M2`, `unique_id`).
- `checkpoints/combined_scores/<group_id>/<metaprogram_set>/`
  - `k-<n>_combined_metaprogram_scores.tsv.gz`: [Cell scores](#cell-scores) for all libraries in the group.
  - `k-<n>_combined_background_score_stats.tsv.gz`: Score background statistics for all libraries in the group.

</details>

### Reusing cNMF results

cNMF is the most time consuming step of the pipeline, so existing cNMF results are reused when the pipeline is run again with the same `--outdir` and same cNMF parameters.
`cnmf-meta.json` records the options used to run cNMF for each library (`cnmf_k_lower`, `cnmf_k_upper`, `cnmf_k_step_size`, `celltype_annotation_column`, `analysis_celltypes`, and `seed`).
If `checkpoints/cnmf/<unique_id>_cnmf/cnmf-meta.json` exists and all of these options match the current run, cNMF is skipped for that library and the existing results are used.
Use `--repeat_cnmf` to run cNMF for every library, even if existing results were created with the same options.

### Reusing metaprograms

Existing metaprograms are also reused when the pipeline is run again with the same `--outdir`.
`k-<k>_metaprograms-meta.json` records the options used to build each set of metaprograms (`n_metaprograms`, `unique_ids`, `n_top_genes`, `filter_spectra`, `orphan_cutoff`, `cnmf_k_lower`, `cnmf_k_upper`, `cnmf_k_step_size`, `celltype_annotation_column`, `analysis_celltypes`, `seed`, and `nreps`).
Generating metaprograms is skipped for a group and value of `k` and the existing results are used if all of the following are true:

- The `.rds`, `.tsv.gz`, and `-meta.json` files for that set of metaprograms all exist in `checkpoints/metaprograms/<group_id>/<metaprogram_set>/`.
- All of the options in `k-<k>_metaprograms-meta.json`, including the libraries in the group, match the current run.
- cNMF was skipped for every library in the group.

Use `--repeat_metaprograms` to generate every set of metaprograms, even if existing results were created with the same options.

## Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report_<timestamp>.html`, `execution_timeline_<timestamp>.html`, `execution_trace_<timestamp>.txt` and `pipeline_dag_<timestamp>.html`.
  - Parameters used by the pipeline run: `params_<timestamp>.json`.
  - Versions of the software used in each step of the pipeline: `metafactory_software_versions.yml`.

</details>

`<timestamp>` uses the format `yyyy-MM-dd_HH-mm-ss` by default. For the execution report, timeline, trace, and DAG filenames, the suffix can be changed with `--trace_report_suffix`. The parameters JSON filename uses a separately generated timestamp and is not affected by this option.

[Nextflow](https://docs.seqera.io/platform-cloud/reports/overview) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
