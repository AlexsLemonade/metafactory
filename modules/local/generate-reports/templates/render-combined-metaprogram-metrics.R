#!/usr/bin/env Rscript

# This script renders the report that compares the metaprograms generated for a single group of
# samples across every value of k that was tested.
# Here k refers to the number of clusters specified during hierarchical clustering of spectra to
# define metaprograms.

# All of the plots and tables in the report are built from the tables written by the calculate k
# module (`calculate-optimal-k.R`)

# Input variables --------------------------------------------------------------
# Nextflow input variables — values are interpolated by the template engine before execution

# the report, staged from the module's `resources/` directory into a subdirectory of the task
# directory
report_rmd <- "${report_rmd}"

# tables and the optimal value of k written by the calculate k module
metaprogram_metrics_file    <- "${metaprogram_metrics_file}"
k_metrics_file              <- "${k_metrics_file}"
neff_background_file        <- "${neff_background_file}"
specificity_background_file <- "${specificity_background_file}"
cv_background_file          <- "${cv_background_file}"
optimal_k_file              <- "${optimal_k_file}"

# output files
output_dir  <- "${output_dir}"
report_file <- "${report_file}"

process_name <- "${task.process}"

# the number of top genes the metaprograms were annotated and scored with and the seed
n_top_genes <- as.integer(${options.n_top_genes})
seed        <- as.integer(${options.seed})

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
    metaprogram_metrics_file = metaprogram_metrics_file,
    k_metrics_file = k_metrics_file,
    neff_background_file = neff_background_file,
    specificity_background_file = specificity_background_file,
    cv_background_file = cv_background_file,
    optimal_k_file = optimal_k_file,
    n_top_genes = n_top_genes,
    seed = seed
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
    sprintf("    readr: %s", as.character(utils::packageVersion("readr"))),
    sprintf("    tibble: %s", as.character(utils::packageVersion("tibble"))),
    sprintf("    glue: %s", as.character(utils::packageVersion("glue"))),
    sprintf("    ggplot2: %s", as.character(utils::packageVersion("ggplot2"))),
    sprintf("    ggforce: %s", as.character(utils::packageVersion("ggforce"))),
    sprintf("    ggbeeswarm: %s", as.character(utils::packageVersion("ggbeeswarm"))),
    sprintf("    DT: %s", as.character(utils::packageVersion("DT"))),
    sprintf("    circlize: %s", as.character(utils::packageVersion("circlize"))),
    sprintf("    ComplexHeatmap: %s", as.character(utils::packageVersion("ComplexHeatmap")))
  ),
  "versions.yml"
)
