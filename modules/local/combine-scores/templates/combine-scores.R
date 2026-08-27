#!/usr/bin/env Rscript

# This script combines a list of TSV files holding scores for individual libraries into a single
# table.
# All input files must have the same columns, so one task is run per score type: either the per
# cell metaprogram scores from the score metaprograms module or the per shuffled metaprogram
# background score stats from the score background module.
# Output is a single gzipped TSV with all rows from all input files, written to the publish
# directory for the metaprogram set the scores were calculated against.

# Input variables --------------------------------------------------------------
# Nextflow input variables — values are interpolated by the template engine before execution
input_tsv_files <- stringr::str_split_1("${input_files_string}", ",")
output_file     <- "${output_file}"
process_name    <- "${task.process}"

# Combine scores ---------------------------------------------------------------

# all input files hold the same columns, so the tables are stacked as is and no library
# identifier is added here; every score table already carries a `unique_id` column
score_df <- input_tsv_files |>
  purrr::map(readr::read_tsv, show_col_types = FALSE) |>
  dplyr::bind_rows()

# export
readr::write_tsv(score_df, output_file)

# Versions ----------------------------------------------------------------------

writeLines(
  c(
    sprintf('"%s":', process_name),
    sprintf("    r-base: %s", as.character(getRversion())),
    sprintf("    dplyr: %s", as.character(utils::packageVersion("dplyr"))),
    sprintf("    purrr: %s", as.character(utils::packageVersion("purrr"))),
    sprintf("    readr: %s", as.character(utils::packageVersion("readr"))),
    sprintf("    stringr: %s", as.character(utils::packageVersion("stringr")))
  ),
  "versions.yml"
)
