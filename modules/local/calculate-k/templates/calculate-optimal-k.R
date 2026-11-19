#!/usr/bin/env Rscript

# This script combines the metrics calculated for every set of metaprograms generated across a
# range of k values (numbers of metaprograms) for a single group of libraries and uses them to identify the
# optimal value of k. The number of metaprograms is the number of clusters specified during hierarchical
# clustering of spectra to define metaprograms, not cNMF k.

# Five metrics are used to rank each metaprogram set:

# 1. Normalized effective library count: Proportion of metaprograms with a normalized effective
# library count significantly greater than the metric background
# 2. Maximum metaprogram correlation: Proportion of metaprograms with a maximum metaprogram
# correlation below the correlation cutoff
# 3. Coherence: Whether the k value (number of metaprograms) is at, below, or above the elbow of the median
# coherence curve, identified with the kneedle algorithm
# 4. Gene set specificity: Whether the overall gene set specificity for that metaprogram set is
# significantly greater than the metric background
# 5. CV of cell scores: Proportion of metaprograms with a coefficient of variation (CV) of
# cell scores significantly greater than the score background

# Each metric is ranked across all metaprogram sets, the ranks are normalized to a 0-1 scale, and
# the number of metaprograms with the highest mean rank is reported as the optimal value of k.

# Outputs the optimal value of k and the TSV files that the companion report
# (`combined-metaprogram-metrics.Rmd`) reads in to make its plots:

# 1. A TSV with one row per metaprogram per metaprogram set, holding every observed metric for that
# metaprogram and whether it passes each cutoff
# 2. A TSV with one row per metaprogram set, holding the summarized metrics used for ranking, the
# normalized rank of each of those metrics (the `rank_` columns), and the mean rank across all
# metrics. Excluded metaprogram sets are reported here with `is_excluded` set to TRUE and no metrics
# 3. Three gzipped TSVs holding the two metric backgrounds (effective library count and gene set
# specificity) and the score background (cell score CV), with the excluded metaprogram sets removed
# 4. A text file holding the optimal value of k, which is used downstream to pick out the
# metaprograms and metrics that are published as the final result for the group

# Input variables --------------------------------------------------------------
# Nextflow input variables — values are interpolated by the template engine before execution
# all file lists are comma separated with one file per metaprogram set
mp_metrics_files             <- stringr::str_split_1("${mp_metrics_files_string}", ",")
geneset_metrics_files        <- stringr::str_split_1("${geneset_metrics_files_string}", ",")
mp_background_files          <- stringr::str_split_1("${mp_background_files_string}", ",")
specificity_background_files <- stringr::str_split_1("${specificity_background_files_string}", ",")
scores_files                 <- stringr::str_split_1("${scores_files_string}", ",")
background_scores_files      <- stringr::str_split_1("${background_scores_files_string}", ",")

# output files
metaprogram_metrics_file    <- "${metaprogram_metrics_file}"
k_metrics_file              <- "${k_metrics_file}"
neff_background_file        <- "${neff_background_file}"
specificity_background_file <- "${specificity_background_file}"
cv_background_file          <- "${cv_background_file}"
optimal_k_file              <- "${optimal_k_file}"

process_name <- "${task.process}"
nreps        <- as.integer(${options.nreps})

# Constants --------------------------------------------------------------------

# adjusted pvalue at or below this value is considered significant
SIG_CUTOFF <- 0.05

# metaprograms with a maximum metaprogram correlation above this value are considered redundant
CORRELATION_CUTOFF <- 0.5

# metaprograms with a coherence at or below this value are likely to represent noise
COHERENCE_CUTOFF <- 0.1

# metrics used to rank each metaprogram set, in the order they are reported
# the names are the rank columns added to the summary metrics table, one for each metric
METRICS_COLUMNS <- c(
  rank_effective_library_count = "neff_sig_proportion",
  rank_correlation = "proportion_passing_correlation",
  rank_coherence = "coherence_elbow_passing",
  rank_gene_set_specificity = "geneset_specificity_significant",
  rank_coefficient_of_variation = "proportion_significant_cv"
)

# Functions --------------------------------------------------------------------

# helper function to assign names to a list of file names
# names are the number of metaprograms taken from the `k-<n>_` file prefix
assign_k_names <- function(file_list) {

  # since nextflow sometimes changes the order of files, grab the number of metaprograms from the filename
  # directly here
  files_n_metaprograms <- basename(file_list) |>
    stringr::word(1, sep = "_") |>
    stringr::str_remove("^k-") |>
    as.integer()

  stopifnot(
    "Could not pull the number of metaprograms out of all file names" = !any(is.na(files_n_metaprograms))
  )

  # add the numbers of metaprograms as the names of the files in the list
  names(file_list) <- files_n_metaprograms

  return(file_list)

}

# read a list of TSV files and combine them into a single data frame with a column holding the
# number of metaprograms of the metaprogram set the file came from
# `bind_rows(.id = )` always adds that column as character, so it is converted back to a number here too
read_k_files <- function(file_list, ...) {

  file_list |>
    assign_k_names() |>
    purrr::map(function(file) readr::read_tsv(file, show_col_types = FALSE, ...)) |>
    dplyr::bind_rows(.id = "n_metaprograms") |>
    dplyr::mutate(n_metaprograms = as.integer(n_metaprograms))

}

# function to calculate the "kneedle"
# copied from https://github.com/AlexsLemonade/ews-nf/blob/main/exploratory-notebooks/05-metaprogram-correlation.Rmd
# returns NA when there is no elbow to find, either because too few metaprogram sets are left or
# because the curve is flat
kneedle <- function(k_values, metric_values, concave = TRUE) {

  # smoothing needs at least four metaprogram sets, and an elbow is not meaningful with fewer
  if (length(unique(k_values)) < 4) {
    return(NA_real_)
  }

  # Step 1: Smooth data to preserve original shape
  fit <- smooth.spline(k_values, metric_values)
  metric_values <- predict(fit, k_values)[["y"]]

  # a flat curve has the same value for every metaprogram set, so normalizing it divides by zero and leaves no
  # well defined knee
  if (diff(range(metric_values)) == 0) {
    return(NA_real_)
  }

  # Step 2: Normalize to [0, 1]
  x <- (k_values - min(k_values)) / (max(k_values) - min(k_values))
  y <- (metric_values - min(metric_values)) / (max(metric_values) - min(metric_values))

  # Step 3: Subtract the diagonal (line from first to last point)
  # This "rotates" the curve so the elbow becomes a maximum
  y_diff <- y - x # for concave (increasing); use x - y for convex (decreasing)
  if (!concave) y_diff <- x - y

  # Step 4: The knee is the point with the maximum difference
  knee_index <- which.max(y_diff)

  k_values[knee_index]

}

# calculate significance for permutation testing
# reports a pvalue for a specified statistic
# copied from https://github.com/AlexsLemonade/ews-nf/blob/main/modules/metaprograms/resources/usr/bin/04-metaprogram-metrics.R
# used here for overall gene set specificity and cell score CV
# `group_columns` defines the level the pvalue is calculated at, either one pvalue per metaprogram
# within a metaprogram set, or a single pvalue for each metaprogram set
# `adjust_columns` defines the family the pvalues are adjusted within
calculate_permutation_significance <- function(
  stat,
  observed_df,
  background_df,
  nreps,
  group_columns = c("n_metaprograms", "metaprogram"),
  adjust_columns = "n_metaprograms"
) {

  # combine the observed values with the metric or score background
  combined_df <- observed_df |>
    dplyr::select(
      dplyr::all_of(group_columns),
      obs_value = dplyr::all_of(stat)
    ) |>
    dplyr::left_join(background_df, by = group_columns) |>
    dplyr::select(-replicate)

  # calculate the pvalue for the requested stat
  pvalue_df <- combined_df |>
    dplyr::mutate(
      # indicate which rows have background values > or < obs
      greater_than_obs = .data[[stat]] >= obs_value,
      lower_than_obs = .data[[stat]] <= obs_value
    ) |>
    dplyr::summarize(
      # calculate p values and retain a column with the observed value
      obs_value = unique(obs_value),
      greater_pvalue = (sum(greater_than_obs) + 1) / (nreps + 1),
      lower_pvalue = (sum(lower_than_obs) + 1) / (nreps + 1),
      # the two sided pvalue is capped at 1, since every background value that ties the observed
      # value counts towards both one sided pvalues, and doubling the smaller of the two can then
      # give a value above 1
      overall_pvalue = min(2 * min(greater_pvalue, lower_pvalue), 1),
      .by = dplyr::all_of(group_columns)
    ) |>
    # add adjusted pvalue
    # depending on the stat will depend on which pvalue we use, either 1 or 2 sided test
    # `summarize(.by = )` returns an ungrouped table, so the adjustment is grouped again here
    # a BH adjusted pvalue depends on the other pvalues it is adjusted with, so adjusting every
    # metaprogram set together would make each one depend on which other metaprogram sets were run
    dplyr::group_by(dplyr::across(dplyr::all_of(adjust_columns))) |>
    dplyr::mutate(
      greater_adj_pvalue = p.adjust(greater_pvalue, method = "BH"),
      lower_adj_pvalue = p.adjust(lower_pvalue, method = "BH"),
      overall_adj_pvalue = p.adjust(overall_pvalue, method = "BH")
    ) |>
    dplyr::ungroup()

  return(pvalue_df)

}

# Set up -----------------------------------------------------------------------

# make sure the staged inputs and requested outputs are correct
stopifnot(
  "Some or all metaprogram metrics files do not exist" = all(file.exists(mp_metrics_files)),
  "Some or all gene set metrics files do not exist" = all(file.exists(geneset_metrics_files)),
  "Some or all metaprogram metric background files do not exist" = all(file.exists(mp_background_files)),
  "Some or all gene set specificity metric background files do not exist" = all(file.exists(specificity_background_files)),
  "Some or all cell score files do not exist" = all(file.exists(scores_files)),
  "Some or all score background files do not exist" = all(file.exists(background_scores_files)),
  "Metaprogram metrics file must end in .tsv" = endsWith(metaprogram_metrics_file, ".tsv"),
  "Summary metrics file must end in .tsv" = endsWith(k_metrics_file, ".tsv"),
  "Metric and score background files must end in .tsv.gz" = all(
    endsWith(
      c(neff_background_file, specificity_background_file, cv_background_file),
      ".tsv.gz"
    )
  )
)

# define output directories so Nextflow doesn't complain
# the report tables are written to their own directory, nested inside the directory the optimal
# k is written to
dir.create(dirname(optimal_k_file), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(metaprogram_metrics_file), recursive = TRUE, showWarnings = FALSE)

# Read input files -------------------------------------------------------------

# metrics with one row per metaprogram for each metaprogram set
# the metaprogram metrics and the gene set metrics are calculated by separate modules, so they are
# joined here into a single table with one row per metaprogram
mp_metrics_df <- read_k_files(mp_metrics_files) |>
  dplyr::left_join(
    read_k_files(geneset_metrics_files),
    by = c("n_metaprograms", "metaprogram")
  )

# metric backgrounds used to calculate significance of the observed metrics
neff_background_df <- read_k_files(mp_background_files)
specificity_background_df <- read_k_files(specificity_background_files)

# cell scores for every library, used to calculate the observed CV of cell scores
scores_df <- scores_files |>
  read_k_files(col_types = list(.default = "c", mp_score = "d"))

# per library summary stats for the shuffled metaprograms, used to build the score background for
# the cell score CV
background_scores_df <- background_scores_files |>
  read_k_files(col_types = list(.default = "d", metaprogram = "c", unique_id = "c"))

# Filter metaprogram sets ------------------------------------------------------

# a metaprogram must contain NMF programs from at least two libraries, so any metaprogram set in
# which clustering produced at least one cluster of NMF programs from fewer than two libraries is
# excluded from the comparison. this includes clusters made up of a single NMF program
excluded_k <- mp_metrics_df |>
  dplyr::filter(num_libraries < 2) |>
  dplyr::pull(n_metaprograms) |>
  unique()

mp_metrics_df <- dplyr::filter(mp_metrics_df, !n_metaprograms %in% excluded_k)
neff_background_df <- dplyr::filter(neff_background_df, !n_metaprograms %in% excluded_k)
specificity_background_df <- dplyr::filter(specificity_background_df, !n_metaprograms %in% excluded_k)
scores_df <- dplyr::filter(scores_df, !n_metaprograms %in% excluded_k)
background_scores_df <- dplyr::filter(background_scores_df, !n_metaprograms %in% excluded_k)

# Metaprogram metrics ----------------------------------------------------------

# every metric in the metaprogram metrics table is calculated by the metrics modules, so all that
# is added here is whether each metaprogram passes the cutoff for that metric
# TODO: the effective library count treats every unique ID in the input samplesheet as a sample. If
# more than one library is generated from the same sample, we may want to collapse libraries to
# samples using the library to sample relationship before calculating the effective library count.
mp_metrics_df <- mp_metrics_df |>
  dplyr::mutate(
    # the effective library count pvalue is calculated by the metaprogram metrics module
    neff_is_significant = greater_adj_pvalue_eff_number_norm <= SIG_CUTOFF,
    # metaprograms with a maximum metaprogram correlation above the cutoff are redundant with another metaprogram
    correlation_is_passing = max_correlation <= CORRELATION_CUTOFF,
    # metaprograms at or below the coherence cutoff are likely to represent noise
    coherence_is_passing = median_difference > COHERENCE_CUTOFF
  )

# CV of cell scores ------------------------------------------------------------

# calculate CV for each metaprogram across all libraries using Chan's algorithm
# originally explored in https://github.com/AlexsLemonade/ews-nf/blob/main/exploratory-notebooks/08-cell-scoring-metrics.Rmd
# the score background module reports per library summary stats for each replicate, so the stats
# are pooled here to get one value for each metaprogram in each replicate
cv_background_df <- background_scores_df |>
  dplyr::summarize(
    n_total = sum(num_cells),
    global_mean = sum(num_cells * mean_mp_score) / sum(num_cells),
    M2_total = sum(M2) + sum(num_cells * (mean_mp_score - global_mean)^2),
    score_var = M2_total / (n_total - 1),
    global_sd = sqrt(score_var),
    score_cv = global_sd / global_mean,
    .by = c("n_metaprograms", "metaprogram", "replicate")
  )

# calculate variance and CV of the observed cell scores without using Chan's
# we confirmed previously that this calculation is equal to the result you get from Chan's
# so we can use this as the observed value and then compare to the score background
var_df <- scores_df |>
  dplyr::summarize(
    score_var = var(mp_score, na.rm = TRUE),
    score_cv = sqrt(score_var) / mean(mp_score),
    .by = c("n_metaprograms", "metaprogram")
  )

# calculate pvalues for each cv
# the observed values come from `var_df`, so only the pvalues are kept here
# the default adjustment family is the metaprograms within a metaprogram set, which is the family the
# metaprogram metrics module uses for the effective library count pvalues
cv_pvalue_df <- calculate_permutation_significance(
  "score_cv",
  var_df,
  cv_background_df,
  nreps
) |>
  dplyr::select(
    n_metaprograms,
    metaprogram,
    "greater_pvalue_score_cv" = "greater_pvalue",
    "greater_adj_pvalue_score_cv" = "greater_adj_pvalue"
  ) |>
  dplyr::mutate(
    cv_is_significant = greater_adj_pvalue_score_cv <= SIG_CUTOFF
  )

mp_metrics_df <- mp_metrics_df |>
  dplyr::left_join(var_df, by = c("n_metaprograms", "metaprogram")) |>
  dplyr::left_join(cv_pvalue_df, by = c("n_metaprograms", "metaprogram"))

# Summarize metrics for each metaprogram set -----------------------------------

# the total number of libraries is the number of unique IDs represented in the cell scores
# TODO: as above, every unique ID is treated as a sample here. If more than one library can come
# from the same sample, this should count samples rather than libraries.
total_libraries_df <- scores_df |>
  dplyr::summarize(
    total_libraries = dplyr::n_distinct(unique_id),
    .by = "n_metaprograms"
  )

# collapse the metaprogram metrics into one row per metaprogram set
k_metrics_df <- mp_metrics_df |>
  dplyr::summarize(
    num_metaprograms = dplyr::n(),
    # metaprograms with a significant effective library count
    neff_sig_number = sum(neff_is_significant),
    neff_sig_proportion = neff_sig_number / num_metaprograms,
    # metaprograms that are not redundant with another metaprogram
    num_passing_correlation = sum(correlation_is_passing),
    proportion_passing_correlation = num_passing_correlation / num_metaprograms,
    # the median coherence is used to find the elbow of the coherence curve below
    num_passing_coherence = sum(coherence_is_passing),
    median_coherence = median(median_difference),
    # metaprograms with at least one significant gene set
    num_metaprograms_with_genesets = sum(num_sig_genesets > 0),
    proportion_metaprograms_with_genesets = num_metaprograms_with_genesets / num_metaprograms,
    # the gene set metrics module reports specificity per metaprogram, so the mean is taken here to
    # get a single observed value for each metaprogram set
    # metaprograms with no identified gene sets have no specificity and are not considered
    overall_geneset_specificity = mean(mean_geneset_specificity, na.rm = TRUE),
    # metaprograms with a significant CV of cell scores
    num_significant_cv = sum(cv_is_significant),
    proportion_significant_cv = num_significant_cv / num_metaprograms,
    .by = "n_metaprograms"
  ) |>
  dplyr::left_join(total_libraries_df, by = "n_metaprograms") |>
  dplyr::relocate(n_metaprograms) |>
  dplyr::arrange(n_metaprograms)

# Coherence elbow --------------------------------------------------------------

# increasing the number of metaprograms doesn't improve coherence after a certain point, so a
# modified version of the kneedle algorithm is used to find the elbow of the coherence curve
# numbers of metaprograms greater than the elbow indicate no substantial gain of coherence over lower values
elbow_value <- kneedle(
  k_metrics_df[["n_metaprograms"]],
  k_metrics_df[["median_coherence"]],
  concave = TRUE
)

# the number of metaprograms at the elbow is prioritized, values below the elbow are preferred over
# values above it
# with no elbow every metaprogram set scores the same 0.5, the midpoint of the scale, so that
# coherence neither prefers nor penalizes any metaprogram set. Ranking ties them all at the top
# rank, which leaves the optimal value of k to the other four metrics
k_metrics_df <- k_metrics_df |>
  dplyr::mutate(
    is_coherence_elbow = !is.na(elbow_value) & n_metaprograms == elbow_value,
    coherence_elbow_passing = dplyr::case_when(
      is.na(elbow_value) ~ 0.5,
      n_metaprograms == elbow_value ~ 1,
      n_metaprograms < elbow_value ~ 0.5,
      n_metaprograms > elbow_value ~ 0
    )
  )

# Gene set specificity significance --------------------------------------------

# the metric background is reported per metaprogram, but the overall specificity is already the mean
# across all metaprograms for each replicate, so there is one value per replicate per metaprogram set
specificity_background_df <- specificity_background_df |>
  dplyr::select(n_metaprograms, replicate, overall_geneset_specificity) |>
  unique()

# compare the observed overall specificity to the metric background
# here we are calculating the overall mean pvalue so that we get one pvalue for each metaprogram set
# this mirrors what we did in: https://github.com/AlexsLemonade/ews-nf/blob/main/exploratory-notebooks/06-gene-set-uniqueness.Rmd
# the metrics calculation module calculates this per metaprogram so we need to do it separately here
# there is one test per metaprogram set here, so the metaprogram sets are the family and no columns
# are passed to adjust within
geneset_specificity_pvalue_df <- calculate_permutation_significance(
  "overall_geneset_specificity",
  k_metrics_df,
  specificity_background_df,
  nreps,
  group_columns = "n_metaprograms",
  adjust_columns = character(0)
) |>
  dplyr::select(
    n_metaprograms,
    "geneset_specificity_pvalue" = "overall_pvalue",
    "geneset_specificity_adj_pvalue" = "overall_adj_pvalue"
  )

k_metrics_df <- k_metrics_df |>
  dplyr::left_join(geneset_specificity_pvalue_df, by = "n_metaprograms") |>
  dplyr::mutate(
    geneset_specificity_significant = as.integer(geneset_specificity_adj_pvalue <= SIG_CUTOFF)
  )

# Rank metaprogram sets --------------------------------------------------------

# rank each metaprogram set for each metric, giving the same rank to any metaprogram sets with the
# exact same value for a metric
# ranks are normalized by the total number of metaprogram sets so that the scale is still 0-1, where
# a higher value indicates a better metaprogram set
# selecting with the named vector copies each metric into its rank column, which is then replaced
# by the rank, so that every rank sits in the same table as the metric it was calculated from
rank_columns <- names(METRICS_COLUMNS)

rank_df <- k_metrics_df |>
  dplyr::select(
    n_metaprograms,
    dplyr::all_of(METRICS_COLUMNS)
  ) |>
  dplyr::mutate(
    dplyr::across(
      dplyr::all_of(rank_columns),
      # normalize so that higher values get higher ranks
      # ultimately high ranks get a value of 1 and low ranks get a value of 0
      function(column) rank(column, ties = "max") / dplyr::n() # exact ties get the same highest rank
    )
  ) |>
  dplyr::mutate(
    mean_rank = rowMeans(dplyr::across(dplyr::all_of(rank_columns)))
  )

k_metrics_df <- dplyr::left_join(k_metrics_df, rank_df, by = "n_metaprograms")

# the optimal value of k is the number of metaprograms with the highest mean rank
optimal_k <- k_metrics_df |>
  dplyr::filter(mean_rank == max(mean_rank)) |>
  # account for any ties and take the one with the highest rank in proportion significant cv
  # ties are not kept so that a single optimal k is always reported, and since the ranks are
  # ordered by number of metaprograms, the smallest number of metaprograms wins any remaining tie
  dplyr::slice_max(rank_coefficient_of_variation, n = 1, with_ties = FALSE) |>
  dplyr::pull(n_metaprograms)

k_metrics_df <- k_metrics_df |>
  dplyr::mutate(
    is_optimal_k = n_metaprograms == optimal_k
  )

# add the excluded metaprogram sets back in so that they can be reported, with no metrics
k_metrics_df <- k_metrics_df |>
  dplyr::mutate(is_excluded = FALSE) |>
  dplyr::bind_rows(
    # a tibble is used here rather than a data frame so that the length 1 columns are still
    # recycled when no metaprogram sets were excluded and the table has no rows
    tibble::tibble(
      n_metaprograms = excluded_k,
      is_excluded = TRUE,
      is_optimal_k = FALSE
    )
  ) |>
  dplyr::relocate(n_metaprograms, is_excluded, is_optimal_k) |>
  dplyr::arrange(n_metaprograms)

# Export -----------------------------------------------------------------------

readr::write_tsv(mp_metrics_df, metaprogram_metrics_file)
readr::write_tsv(k_metrics_df, k_metrics_file)

# only the columns needed to plot the metric and score backgrounds are exported
readr::write_tsv(
  dplyr::select(neff_background_df, n_metaprograms, metaprogram, replicate, eff_number_norm),
  neff_background_file
)
readr::write_tsv(specificity_background_df, specificity_background_file)
readr::write_tsv(
  dplyr::select(cv_background_df, n_metaprograms, metaprogram, replicate, score_cv),
  cv_background_file
)

# export the optimal k as a number to match n_metaprograms in nextflow
readr::write_lines(optimal_k, optimal_k_file)

# Versions ----------------------------------------------------------------------

writeLines(
  c(
    sprintf('"%s":', process_name),
    sprintf("    r-base: %s", as.character(getRversion())),
    sprintf("    dplyr: %s", as.character(utils::packageVersion("dplyr"))),
    sprintf("    purrr: %s", as.character(utils::packageVersion("purrr"))),
    sprintf("    readr: %s", as.character(utils::packageVersion("readr"))),
    sprintf("    stringr: %s", as.character(utils::packageVersion("stringr"))),
    sprintf("    tibble: %s", as.character(utils::packageVersion("tibble")))
  ),
  "versions.yml"
)
