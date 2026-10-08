#!/usr/bin/env Rscript

# This script renders the report that evaluates a single set of metaprograms generated for one
# group of samples with one value of k.

# Input variables --------------------------------------------------------------
# Nextflow input variables — values are interpolated by the template engine before execution

# the report to render, must be in a subdirectory
report_rmd <- "${report_rmd}"

# metaprograms object and metrics tables for a single metaprogram set
metaprograms_object_file <- "${metaprograms_file}"
metaprograms_metrics_file <- "${metaprogram_metrics_file}"
geneset_metrics_file <- "${geneset_metrics_file}"
ora_results_file <- "${ora_results_file}"
combined_scores_file <- "${combined_scores_file}"

# output files
output_dir  <- "${output_dir}"
report_file <- "${report_file}"

process_name <- "${task.process}"

# Render -----------------------------------------------------------------------

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# `rmarkdown::render()` resolves the input path before taking its directory as the place to write
# the intermediate files it needs, so rendering the staged file directly would resolve the symlink
# nextflow stages and write those files into the module directory in the project, which may not be
# writable. The report is copied into the task directory and that copy is rendered instead
local_rmd <- basename(report_rmd)
stopifnot(
  "The report could not be copied into the task directory" =
    file.copy(report_rmd, local_rmd, overwrite = TRUE)
)

# all of the staged input files are in the task directory, which is also where the report is knit
rmarkdown::render(
  input = local_rmd,
  output_file = basename(report_file),
  output_dir = output_dir,
  params = list(
    metaprograms_object_file = metaprograms_object_file,
    metaprograms_metrics_file = metaprograms_metrics_file,
    geneset_metrics_file = geneset_metrics_file,
    ora_results_file = ora_results_file,
    combined_scores_file = combined_scores_file
  ),
  envir = new.env()
)

# Versions ----------------------------------------------------------------------

writeLines(
  c(
    sprintf('"%s":', process_name),
    sprintf("    r-base: %s", as.character(getRversion())),
    sprintf("    pandoc: %s", as.character(rmarkdown::pandoc_version())),
    sprintf("    rmarkdown: %s", as.character(utils::packageVersion("rmarkdown"))),
    sprintf("    knitr: %s", as.character(utils::packageVersion("knitr"))),
    sprintf("    dplyr: %s", as.character(utils::packageVersion("dplyr"))),
    sprintf("    tidyr: %s", as.character(utils::packageVersion("tidyr"))),
    sprintf("    tibble: %s", as.character(utils::packageVersion("tibble"))),
    sprintf("    purrr: %s", as.character(utils::packageVersion("purrr"))),
    sprintf("    readr: %s", as.character(utils::packageVersion("readr"))),
    sprintf("    stringr: %s", as.character(utils::packageVersion("stringr"))),
    sprintf("    forcats: %s", as.character(utils::packageVersion("forcats"))),
    sprintf("    glue: %s", as.character(utils::packageVersion("glue"))),
    sprintf("    ggplot2: %s", as.character(utils::packageVersion("ggplot2"))),
    sprintf("    ggforce: %s", as.character(utils::packageVersion("ggforce"))),
    sprintf("    ggridges: %s", as.character(utils::packageVersion("ggridges"))),
    sprintf("    patchwork: %s", as.character(utils::packageVersion("patchwork"))),
    sprintf("    DT: %s", as.character(utils::packageVersion("DT"))),
    sprintf("    circlize: %s", as.character(utils::packageVersion("circlize"))),
    sprintf("    ComplexHeatmap: %s", as.character(utils::packageVersion("ComplexHeatmap")))
  ),
  "versions.yml"
)
