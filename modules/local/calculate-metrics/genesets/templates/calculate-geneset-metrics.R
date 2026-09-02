#!/usr/bin/env Rscript

# This script is used to annotate metaprograms with gene sets using overrepresentation analysis
# (ORA) and to calculate metrics describing how specific those gene sets are to each metaprogram.
# Outputs three TSV files:

# 1. A TSV with every gene set assigned to a metaprogram by ORA that passes the
# significance threshold, with one row per gene set per metaprogram. This holds the full result
# table returned by `clusterProfiler::enricher()`, so it has a wide `geneID` column.
# 2. A TSV with one row per metaprogram holding the ORA derived metrics described below
# 3. A gzipped TSV with the background values for gene set specificity, with one row per
# metaprogram per permutation replicate (columns: replicate, metaprogram,
# mean_geneset_specificity, overall_geneset_specificity). This is the null distribution the
# `mean_geneset_specificity` p-values are calculated against.

# The gene set metrics TSV contains the following metrics:

# num_sig_genesets: Total number of gene sets identified as significant by ORA
# mean_geneset_specificity: Mean specificity of all gene sets assigned to a metaprogram through ORA
# overall_pvalue_geneset_specificity: pvalue of observed specificity being > or < background
# overall_adj_pvalue_geneset_specificity: adjusted pvalue for gene set specificity

# Metaprograms that have no significant gene sets are still reported, with a
# `mean_geneset_specificity` of NaN and no p-value, since there is nothing to average over. The
# permuted background covers the same set of metaprograms so that the observed values and the
# background are always calculated across the same metaprograms.

# Input variables --------------------------------------------------------------
# Nextflow input variables — values are interpolated by the template engine before execution
metaprograms_file <- "${metaprograms_file}"
term2gene_file    <- "${term2gene_file}"
ora_results_file  <- "${ora_results_file}"
metrics_file      <- "${metrics_file}"
background_file   <- "${background_file}"
process_name      <- "${task.process}"
nreps             <- as.integer(${options.nreps})
seed              <- as.integer(${options.seed})

# Constants
SIG_CUTOFF <- 0.05

# Functions --------------------------------------------------------------------

# function for running ORA with clusterProfiler::enricher on each metaprogram
# uses the top genes stored on the metaprograms object for each metaprogram
# returns a df with all gene sets for each metaprogram with p.adjust <= sig_cutoff
sig_cutoff <- function(mp_top_list, gene_universe, term2gene_df, sig_cutoff) {

  # run ORA using the top genes
  ora_results <- mp_top_list |>
    purrr::map(function(genes) {
      clusterProfiler::enricher(
        gene = genes,
        universe = gene_universe,
        TERM2GENE = term2gene_df
      )
    })

  # combine ora results into a single dataframe
  # only include genesets with pvalue < sig_cutoff, the default by enricher
  ora_results_df <- ora_results |>
    purrr::map(function(ora) ora@result) |>
    purrr::list_rbind(names_to = "metaprogram") |>
    dplyr::filter(p.adjust <= sig_cutoff)

  return(ora_results_df)

}

# helper function to get a table with the total number of genesets per metaprogram
# `mp_names` is the full set of metaprogram names, so metaprograms that ORA found no significant
# gene sets for are reported with a count of 0 rather than being dropped
get_total_genesets <- function(mp_names, ora_results_df) {

  # table of number of gene sets per metaprogram
  df <- ora_results_df |>
    dplyr::group_by(metaprogram) |>
    dplyr::summarise(num_sig_genesets = length(ID)) |>
    dplyr::mutate(
      num_sig_genesets = dplyr::if_else(is.na(num_sig_genesets), 0, num_sig_genesets)
    )

  return(df)

}

# helper function for computing metaprogram specificity
# `mp_geneset_df` is any table assigning gene sets to metaprograms, with a `metaprogram` column and
# an `ID` column holding the gene set. It is either the observed ORA results or a shuffled copy of
# them, so this is the single implementation of the specificity formula used by both the observed
# and the permuted path
# `mp_names` is the full set of metaprogram names, so that both paths always cover the same
# metaprograms and a metaprogram with no gene sets is reported as NaN rather than dropped
compute_metaprogram_specificity <- function(mp_geneset_df, n_metaprograms, mp_names) {

  # calculate specificity for each gene set
  # one row per gene set
  geneset_specificity_df <- mp_geneset_df |>
    dplyr::group_by(ID) |>
    dplyr::summarize(num_mps = dplyr::n_distinct(metaprogram)) |>
    dplyr::mutate(geneset_specificity = 1 - (num_mps - 1) / (n_metaprograms - 1))

  # add gene set specificity to metaprograms
  # get one row per metaprogram with mean gene set specificity
  data.frame(metaprogram = mp_names) |>
    dplyr::left_join(mp_geneset_df, by = "metaprogram") |>
    dplyr::left_join(geneset_specificity_df, by = "ID") |>
    dplyr::summarize(mean_geneset_specificity = mean(geneset_specificity), .by = "metaprogram")

}

# shuffle gene sets assigned to each metaprogram and then re-calculate specificity
# weight gene sets based on the number of times they appear in the table
permute_specificity <- function(
  ora_results_df,
  n_metaprograms,
  mp_names,
  nreps
) {

  # get gene set weights
  geneset_weights <- table(ora_results_df[["ID"]])
  # pool of all significant gene sets across all metaprograms
  all_genesets <- names(geneset_weights)

  # get the size (number of sig gene sets) for each metaprogram
  mp_geneset_counts <- ora_results_df |>
    dplyr::group_by(metaprogram) |>
    dplyr::summarise(geneset_count = dplyr::n_distinct(ID), .groups = "drop")

  # shuffle genesets assigned to each metaprogram
  background <- replicate(
    nreps,
    {
      # keep the total number of genesets the same
      shuffled_ora_results <- mp_geneset_counts[["geneset_count"]] |>
        purrr::set_names(mp_geneset_counts[["metaprogram"]]) |>
        purrr::map(function(count) {
          # sample without replacement from the full pool
          # ensuring no duplicate gene sets within a metaprogram
          sample(all_genesets, count, replace = FALSE, prob = geneset_weights)
        }) |>
        tibble::enframe(name = "metaprogram", value = "ID") |>
        tidyr::unnest_longer(ID)

      # use the same specificity calculation as the observed results, over the same metaprograms
      compute_metaprogram_specificity(shuffled_ora_results, n_metaprograms, mp_names) |>
        dplyr::mutate(
          # get the overall mean across all MPs
          overall_geneset_specificity = mean(mean_geneset_specificity, na.rm = TRUE)
        )

    },
    simplify = FALSE
  ) |>
    dplyr::bind_rows(.id = "replicate")

  return(background)
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
  "Term2gene file does not exist" = file.exists(term2gene_file),
  "Number of replicates must be at least 1" = nreps >= 1,
  "ORA results file must end in .tsv" =
    endsWith(ora_results_file, ".tsv"),
  "Metrics file must end in .tsv" =
    endsWith(metrics_file, ".tsv"),
  "Background specificity file must end in .tsv or .tsv.gz" =
    endsWith(background_file, ".tsv") || endsWith(background_file, ".tsv.gz")
)

# define output directory so Nextflow doesn't complain
dir.create(dirname(metrics_file), recursive = TRUE, showWarnings = FALSE)

# object with metaprogram results
mp_object <- readr::read_rds(metaprograms_file)

# the top genes are calculated by the generate metaprograms module and read from the object here so
# that every module uses the same gene lists
stopifnot(
  "Metaprograms file has no `top_genes` element. It was written before the top genes were added to the metaprograms object, so it must be regenerated." =
    !is.null(mp_object[["top_genes"]]),
  "Metaprograms file has no `gene_universe` element" = !is.null(mp_object[["gene_universe"]])
)

top_genes <- mp_object[["top_genes"]]
gene_universe <- mp_object[["gene_universe"]]

# take the metaprogram names from a single source and pass them explicitly everywhere they are
# needed, so that the set of metaprograms is identical across the gene set counts, the observed
# specificity and the permuted background
mp_names <- names(mp_object[["metaprogram_list"]])
n_metaprograms <- length(mp_names)

stopifnot(
  "Metaprograms object has unnamed metaprograms" = !is.null(mp_names),
  "Top genes do not cover the same metaprograms as the metaprogram list" =
    identical(sort(names(top_genes)), sort(mp_names)),
  "Number of metaprograms does not match the metaprogram list" =
    n_metaprograms == mp_object[["n_metaprograms"]]
)

# pre-formatted term2gene table, with one row per gene per gene set
term2gene_df <- readr::read_tsv(term2gene_file, show_col_types = FALSE)

stopifnot(
  "Term2gene file must have `gs_name` and `ensembl_gene` columns" =
    all(c("gs_name", "ensembl_gene") %in% colnames(term2gene_df))
)

# enricher expects a two column term2gene table, so drop any extra columns that are used to
# describe the gene sets but are not needed here
term2gene_df <- term2gene_df |>
  dplyr::select("gs_name", "ensembl_gene") |>
  tidyr::drop_na() |>
  unique()

stopifnot(
  "Term2gene file has no gene set assignments" = nrow(term2gene_df) > 0
)

# ORA --------------------------------------------------------------------------

# get ora results
ora_results_df <- run_ora(
  mp_top_list = top_genes,
  gene_universe = gene_universe,
  term2gene_df = term2gene_df,
  sig_cutoff = SIG_CUTOFF
)

# table of number of gene sets per metaprogram
num_genesets_df <- get_total_genesets(mp_names, ora_results_df)

# Gene set specificity ---------------------------------------------------------

# calculate gene set specificity
obs_specificity_df <- compute_metaprogram_specificity(ora_results_df, n_metaprograms, mp_names)

# Calculate background for gene set specificity
background_specificity_df <- permute_specificity(
  ora_results_df,
  n_metaprograms,
  mp_names,
  nreps
)

# calculate pvalue for specificity
specificity_pvalue_df <- calculate_permutation_significance(
  "mean_geneset_specificity",
  obs_specificity_df,
  background_specificity_df,
  nreps
) |>
  dplyr::select(
    "metaprogram",
    "overall_pvalue_geneset_specificity" = "overall_pvalue",
    "overall_adj_pvalue_geneset_specificity" = "overall_adj_pvalue"
  )

# Combine and export -----------------------------------------------------------

# join all gene set metrics
geneset_metrics_df <- num_genesets_df |>
  # gene set specificity and pvalue
  dplyr::left_join(obs_specificity_df, by = "metaprogram") |>
  dplyr::left_join(specificity_pvalue_df, by = "metaprogram")

readr::write_tsv(ora_results_df, ora_results_file)
readr::write_tsv(geneset_metrics_df, metrics_file)
readr::write_tsv(background_specificity_df, background_file)

# Versions ----------------------------------------------------------------------

writeLines(
  c(
    sprintf('"%s":', process_name),
    sprintf("    r-base: %s", as.character(getRversion())),
    sprintf("    clusterProfiler: %s", as.character(utils::packageVersion("clusterProfiler"))),
    sprintf("    dplyr: %s", as.character(utils::packageVersion("dplyr"))),
    sprintf("    purrr: %s", as.character(utils::packageVersion("purrr"))),
    sprintf("    readr: %s", as.character(utils::packageVersion("readr"))),
    sprintf("    tibble: %s", as.character(utils::packageVersion("tibble"))),
    sprintf("    tidyr: %s", as.character(utils::packageVersion("tidyr")))
  ),
  "versions.yml"
)
