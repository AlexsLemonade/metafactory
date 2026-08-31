#!/usr/bin/env Rscript

# This script is used to calculate a set of metrics on metaprograms
# Outputs two TSV files:

# 1. A TSV with one row per metaprogram holding the metrics described below
# 2. A gzipped TSV with the background values for the metaprogram sample stats, with one row per
# metaprogram per permutation replicate (columns: replicate, then every sample stat below). This is
# the null distribution the `eff_number_norm` p-values are calculated against.

# The metaprogram metrics TSV contains the following metrics:

# max_correlation: Max correlation of the specified metaprogram to all other metaprograms
# median_difference: Difference in medians between the correlation of spectra
#  within metaprograms and between metaprograms
# num_spectra_per_mp: Number of spectra found in that metaprogram
# num_samples: Number of samples represented in the metaprogram
# proportion_of_samples: Proportion of the total samples represented in the metaprogram
# shannon_entropy: shannon's entropy measuring relative abundance of samples in the metaprogram
# shannon_entropy_norm: Normalized shannon's entropy
# eff_number: Effective sample size
# eff_number_norm: Effective sample size normalized by the total samples in a metaprogram
# greater_pvalue_eff_number_norm: Pvalue of the observed effective sample size > background
# greater_adj_pvalue_eff_number_norm: Adjusted pvalue for effective sample size

# Input variables --------------------------------------------------------------
# Nextflow input variables — values are interpolated by the template engine before execution
metaprograms_file <- "${metaprograms_file}"
metrics_file      <- "${metrics_file}"
background_file   <- "${background_file}"
process_name      <- "${task.process}"
nreps             <- as.integer(${options.nreps})
seed              <- as.integer(${options.seed})

# Functions --------------------------------------------------------------------

# helper function for calculating entropy
entropy <- function(sample_n) {
  sample_freq <- sample_n / sum(sample_n)
  -sum(sample_freq * log(sample_freq))
}

# calculate stats for all metaprograms
# returns a dataframe with one row for each metaprogram and one column for each stat
calculate_sample_stats <- function(mp_clusters_df, total_samples) {

  # df with one row per mp
  # calculates total spectra, entropy, norm entropy, eff species size
  mp_entropy_df <- mp_clusters_df |>
    dplyr::group_by(metaprogram, sample_id) |>
    # first get total spectra per sample
    dplyr::summarize(
      num_spectra_per_sample = dplyr::n(),
      .groups = "drop_last"
    ) |>
    # now calculate stats for each metaprogram, drop sample grouping
    dplyr::summarize(
      # totals for each group (spectra, sample)
      num_spectra_per_mp = sum(num_spectra_per_sample),
      num_samples = length(sample_id),
      # proportion of the total samples
      proportion_of_samples = num_samples / total_samples,
      # entropy and neff
      shannon_entropy = entropy(num_spectra_per_sample), # entropy
      shannon_entropy_norm = dplyr::if_else(num_samples > 1, shannon_entropy / log(num_samples), 0), # normalize by total possible samples in that mp
      eff_number = exp(shannon_entropy), # effective species size or Hill number order of 1
      eff_number_norm = eff_number / num_samples # eff number should be close to the total possible samples in that mp
    )

  return(mp_entropy_df)

}

# calculate significance for permutation testing
# reports a pvalue for a specified statistic
calculate_permutation_significance <- function(stat, observed_df, background_df, nreps) {

  # combine the observed values with the background
  combined_df <- observed_df |>
    dplyr::select(
      metaprogram,
      obs_value = tidyselect::all_of(stat)
    ) |>
    dplyr::left_join(background_df, by = c("metaprogram")) |>
    dplyr::select(-replicate)

  # calculate the pvalue for the requested stat
  pvalue_df <- combined_df |>
    dplyr::mutate(
      # indicate which rows have background > or < obs
      greater_than_obs = .data[[stat]] >= obs_value,
      lower_than_obs = .data[[stat]] <= obs_value
    ) |>
    dplyr::group_by(metaprogram) |>
    dplyr::summarize(
      # calculate p values and retain a column with the observed value
      obs_value = unique(obs_value),
      greater_pvalue = (sum(greater_than_obs) + 1) / (nreps + 1),
      lower_pvalue = (sum(lower_than_obs) + 1) / (nreps + 1),
      overall_pvalue = min(greater_pvalue, lower_pvalue) * 2
    ) |>
    # add adjusted pvalue
    # depending on the stat will depend on which pvalue we use, either 1 or 2 sided test
    dplyr::mutate(
      greater_adj_pvalue = p.adjust(greater_pvalue, method = "BH"),
      lower_adj_pvalue = p.adjust(lower_pvalue, method = "BH"),
      overall_adj_pvalue = p.adjust(overall_pvalue, method = "BH")
    )

  return(pvalue_df)

}

# Set up -----------------------------------------------------------------------

set.seed(seed)

# make sure the staged inputs and requested outputs are correct
stopifnot(
  "Metaprograms file does not exist" = file.exists(metaprograms_file),
  "Number of replicates must be at least 1" = nreps >= 1,
  "Metrics file must end in .tsv or .tsv.gz" =
    endsWith(metrics_file, ".tsv") || endsWith(metrics_file, ".tsv.gz"),
  "Background stats file must end in .tsv or .tsv.gz" =
    endsWith(background_file, ".tsv") || endsWith(background_file, ".tsv.gz")
)

# define output directory so Nextflow doesn't complain
dir.create(dirname(metrics_file), recursive = TRUE, showWarnings = FALSE)

# object with metaprogram results
# list elements are pulled out with `[[` throughout so that this template holds no literal dollar
# signs and nothing needs to be escaped for the template engine
mp_object <- readr::read_rds(metaprograms_file)

# Max correlation --------------------------------------------------------------

# combine all mps into a matrix and get correlation to each other
mp_mtx <- do.call(cbind, mp_object[["metaprogram_list"]])
mp_cor_matrix <- cor(mp_mtx, method = "pearson", use = "pairwise.complete.obs")

# the diagonals are all self comparisons so set those to 0
diag(mp_cor_matrix) <- 0
max_cor_df <- data.frame(
  metaprogram = rownames(mp_cor_matrix),
  max_correlation = matrixStats::rowMaxs(mp_cor_matrix)
)

# Difference in medians/ Coherence ---------------------------------------------

# convert the mp cluster list into a dataframe with one row per spectra
# use this to get the assigned mp for each cluster/metaprogram when calculating metrics
mp_lookup <- tibble::enframe(mp_object[["cluster_list"]], name = "metaprogram", value = "spectra") |>
  tidyr::unnest_longer(spectra)

# for each correlation, add in the MPs being compared and classify MP
mp_cor_df <- mp_object[["spectra_cor_df"]] |>
  dplyr::filter(spectra1 != spectra2) |>
  # add in the mp assignment for the first spectra
  dplyr::left_join(mp_lookup, by = c("spectra1" = "spectra")) |>
  dplyr::rename(mp1 = metaprogram) |>
  # add in the metaprogram assignment for the second spectra
  dplyr::left_join(mp_lookup, by = c("spectra2" = "spectra")) |>
  dplyr::rename(mp2 = metaprogram) |>
  # add a column indicating if the spectra are assigned to the same or different mps
  dplyr::mutate(within_mp = ifelse(mp1 == mp2, "within", "between"))

# calculate the difference in medians between the two groups
mp_medians_df <- mp_cor_df |>
  dplyr::group_by(mp1, within_mp) |>
  dplyr::summarise(
    group_median = median(correlation)
  ) |>
  tidyr::pivot_wider(
    id_cols = mp1,
    names_from = within_mp,
    values_from = group_median
  ) |>
  dplyr::mutate(
    median_difference = within - between
  ) |>
  dplyr::select(metaprogram = mp1, median_difference)

# Sample proportion ------------------------------------------------------------

# get the total number of samples to use as the denominator for proportion
# use all samples even if they are not all present in the spectra after filtering
total_samples <- length(mp_object[["unique_ids"]])

# add sample column
mp_clusters_df <- mp_lookup |>
  # spectra are named with unique id which is <library_id>-<sample_id>_cnmf info
  dplyr::mutate(sample_id = stringr::word(spectra, 1, sep = "_") |>
                  stringr::word(-1, sep = "-"))

# get observed stats
# includes proportion of samples, shannon entropy and effective sample size
obs_stats_df <- calculate_sample_stats(mp_clusters_df, total_samples)

# get the background
background_mp_stats_df <- replicate(nreps, {
  # for each rep, shuffle the spectra
  # keep the distribution of num spectra/ mp the same
  dplyr::mutate(mp_clusters_df, metaprogram = sample(metaprogram)) |>
    calculate_sample_stats(total_samples)
}, simplify = FALSE) |>
  dplyr::bind_rows(.id = "replicate")


# pvalue for neff to add in to the final data frame
neff_pvalue_df <- calculate_permutation_significance(
  eff_number_norm,
  obs_stats_df,
  background_mp_stats_df,
  nreps
) |>
  # select the columns that we want
  # only care about greater than pvalue
  dplyr::select(
    metaprogram,
    "greater_pvalue_eff_number_norm" = "greater_pvalue",
    "greater_adj_pvalue_eff_number_norm" = "greater_adj_pvalue"
  )

# Combine and export -----------------------------------------------------------

# join all mp metrics
mp_metrics_df <- max_cor_df |>
  dplyr::left_join(mp_medians_df, by = "metaprogram") |>
  # add in all stats
  dplyr::left_join(obs_stats_df, by = "metaprogram") |>
  # add pvalue for neff
  dplyr::left_join(neff_pvalue_df, by = "metaprogram")

readr::write_tsv(mp_metrics_df, metrics_file)
readr::write_tsv(background_mp_stats_df, background_file)

# Versions ----------------------------------------------------------------------

writeLines(
  c(
    sprintf('"%s":', process_name),
    sprintf("    r-base: %s", as.character(getRversion())),
    sprintf("    dplyr: %s", as.character(utils::packageVersion("dplyr"))),
    sprintf("    matrixStats: %s", as.character(utils::packageVersion("matrixStats"))),
    sprintf("    readr: %s", as.character(utils::packageVersion("readr"))),
    sprintf("    stringr: %s", as.character(utils::packageVersion("stringr"))),
    sprintf("    tibble: %s", as.character(utils::packageVersion("tibble"))),
    sprintf("    tidyr: %s", as.character(utils::packageVersion("tidyr")))
  ),
  "versions.yml"
)
