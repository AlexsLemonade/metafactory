#!/usr/bin/env Rscript

# Writes a small term2gene table for the CALCULATE_METRICS subworkflow tests, with gene sets that
# ORA finds significant for known metaprograms. Each set only holds genes that are in the top genes
# of the metaprograms it is meant for and of no other metaprogram:
#   SET_MP01: 20 genes unique to MP01
#   SET_MP02: 20 genes unique to MP02
#   SET_MP01_MP02: 10 genes unique to MP01 and 10 unique to MP02
# Every set has at least 10 genes, the default minimum gene set size used by enricher.

# Called by update-test-data.sh after it copies the metaprograms RDS into `tests/data/`.
# It requires the `optparse` and `tidyverse` packages.

# Usage:
#   Rscript make-term2gene.R --metaprograms_file <metaprograms RDS> --output_file <term2gene TSV>

library(optparse)

# Parse options ----------------------------------------------------------------

option_list <- list(
  make_option(
    "--metaprograms_file",
    type = "character",
    help = "Path to the RDS file written by the generate metaprograms module"
  ),
  make_option(
    "--output_file",
    type = "character",
    help = "Path to the output term2gene TSV, with `gs_name` and `ensembl_gene` columns"
  )
)

opts <- parse_args(OptionParser(option_list = option_list))

stopifnot(
  "`--metaprograms_file` must be provided" = !is.null(opts$metaprograms_file),
  "`--output_file` must be provided" = !is.null(opts$output_file),
  "Metaprograms file does not exist" = file.exists(opts$metaprograms_file)
)

# Constants
# number of genes in a gene set for a single metaprogram, and half of the shared gene set
N_GENES <- 20
N_SHARED_GENES <- 10

# Find unique top genes --------------------------------------------------------

mp_object <- readr::read_rds(opts$metaprograms_file)
top_genes <- mp_object[["top_genes"]]

# top genes of each metaprogram that are not in the top genes of any other metaprogram
unique_genes <- names(top_genes) |>
  purrr::set_names() |>
  purrr::map(\(mp) setdiff(top_genes[[mp]], unlist(top_genes[names(top_genes) != mp])))

stopifnot(
  "Metaprograms object must have MP01 and MP02" = all(c("MP01", "MP02") %in% names(top_genes)),
  "MP01 and MP02 must each have enough unique top genes" =
    all(lengths(unique_genes[c("MP01", "MP02")]) >= N_GENES),
  "Top genes must all be in the gene universe" =
    all(unlist(top_genes) %in% mp_object[["gene_universe"]])
)

# Build term2gene table --------------------------------------------------------

gene_sets <- list(
  SET_MP01 = head(unique_genes[["MP01"]], N_GENES),
  SET_MP02 = head(unique_genes[["MP02"]], N_GENES),
  SET_MP01_MP02 = c(
    head(unique_genes[["MP01"]], N_SHARED_GENES),
    head(unique_genes[["MP02"]], N_SHARED_GENES)
  )
)

term2gene_df <- gene_sets |>
  tibble::enframe(name = "gs_name", value = "ensembl_gene") |>
  tidyr::unnest_longer(ensembl_gene)

readr::write_tsv(term2gene_df, opts$output_file)
