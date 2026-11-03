#!/usr/bin/env Rscript

# This script builds the table of MSigDB gene sets used for overrepresentation analysis in the
# workflow, `assets/msigdb-gene-set-genes.tsv.gz`.
# Gene sets are downloaded from MSigDB with `msigdbr` and saved as a single gzipped TSV with
# one row per gene per gene set (columns: collection, gs_name, ensembl_gene).

# The gene sets to download are defined by `assets/msigdb-gene-sets.tsv`, where each row selects
# either an entire (sub)collection or a single named gene set (see `assets/README.md`).
# The `name` column of that file is used as the `collection` column of the output, so the labels
# in the output are the short labels defined there rather than the MSigDB collection codes.

# This script is not part of the workflow and requires internet access to reach MSigDB.
# It only needs to be re-run if `assets/msigdb-gene-sets.tsv` changes or if the gene sets need to
# be updated to a newer release of MSigDB.
# It requires the `msigdbr` package, which as of v10 also requires the `msigdbdf` data package.

# Parameters -------------------------------------------------------------------

gene_sets_file <- here::here("assets", "msigdb-gene-sets.tsv")
output_file <- here::here("assets", "msigdb-gene-set-genes.tsv.gz")
species <- "Homo sapiens"

# Read requested gene sets -----------------------------------------------------

if (!requireNamespace("msigdbr", quietly = TRUE)) {
  stop("The `msigdbr` package must be installed to run this script.")
}

gene_sets_df <- readr::read_tsv(gene_sets_file, show_col_types = FALSE)

required_columns <- c("name", "collection", "subcollection", "geneset")
missing_columns <- setdiff(required_columns, colnames(gene_sets_df))
if (length(missing_columns) > 0) {
  stop(sprintf(
    "%s is missing the following required column(s): %s",
    gene_sets_file,
    paste(missing_columns, collapse = ", ")
  ))
}

# names label the rows in the output, so they must be unique
if (any(duplicated(gene_sets_df$name))) {
  stop(sprintf("The `name` column in %s must contain unique values.", gene_sets_file))
}

# Download gene sets -----------------------------------------------------------

message(sprintf("Using msigdbr %s", as.character(utils::packageVersion("msigdbr"))))

# one call to `msigdbr()` per row of the gene sets table
msigdb_df <- gene_sets_df |>
  purrr::pmap(function(name, collection, subcollection, geneset, ...) {
    message(sprintf("Downloading gene sets for: %s", name))

    # `NA` in the subcollection column means the full collection is used
    subcollection <- if (is.na(subcollection)) NULL else subcollection

    collection_df <- msigdbr::msigdbr(
      species = species,
      collection = collection,
      subcollection = subcollection
    )

    if (nrow(collection_df) == 0) {
      stop(sprintf("No gene sets found in MSigDB for %s.", name))
    }

    # `all` in the geneset column means every gene set in the (sub)collection is used,
    # otherwise a single named gene set is pulled out
    if (geneset != "all") {
      collection_df <- collection_df |>
        dplyr::filter(gs_name == geneset)

      if (nrow(collection_df) == 0) {
        stop(sprintf("No gene set named %s found for %s.", geneset, name))
      }
    }

    collection_df |>
      # include relevant columns
      dplyr::mutate(
        collection = collection,
        subcollection = subcollection,
        name = name
      ) |>
      dplyr::select(collection, subcollection, name, gs_name, ensembl_gene)
  }) |>
  dplyr::bind_rows() |>
  # remove anything without an ensembl id
  dplyr::filter(!is.na(ensembl_gene)) |>
  dplyr::distinct() |>
  # sorted so that the output is stable if the script is re-run
  dplyr::arrange(collection, gs_name, ensembl_gene)

# Export -----------------------------------------------------------------------

message(sprintf(
  "Writing %s rows across %s gene sets to %s",
  nrow(msigdb_df),
  dplyr::n_distinct(msigdb_df$gs_name),
  output_file
))

readr::write_tsv(msigdb_df, output_file)
