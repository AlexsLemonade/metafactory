# This script is used to generate metaprograms using cNMF results across all samples in a group
# Outputs an RDS file with a list of:

# metaprogram_list: List of gene weights for each MP
# clusters: original vector of cluster assignments for each spectra
# cluster_list: Spectra assigned to each cluster/MP
# cor_matrix: Correlation matrix of spectra
# spectra_cor_df: Data frame with all spectra correlation information
# shuffled_metaprograms: List of shuffled MPs (top genes only) for each permutation replicate
# gene_universe: List of all genes used to calculate metaprograms
# n_metaprograms: Number of metaprograms specified
# cnmf_k_range: Set of k values used with cNMF to consider when generating MPs
# filter_spectra: Whether or not orphan spectra were removed
# orphan_cutoff: If orphan spectra were removed, the minimum cross sample correlation
# to keep the spectra. If no filtering, this is -1
# unique_ids: Vector of unique IDs associated with the MPs
# removed_unique_ids: Vector of unique IDs that are removed when filtering the spectra

# Functions --------------------------------------------------------------------

# helper to read in a list of files with spectra from cNMF and create a single mtx
build_spectra_mtx <- function(spectra_files){

  # read in all spectra and combine into a single matrix
  # rows are genes and each column is a spectra
  # any genes that are not present in a spectra will have NA
  spectra_mtx <- purrr::imap(
    spectra_files, function(file, id) {

      # extract k value to use for labeling columns
      k_value <- stringr::str_extract(file, pattern = "k_[0-9]+") |>
        stringr::str_extract("[0-9]+") |>
        as.integer()

      k_value <- sprintf("k%02d", k_value)

      # read in file and create dataframe
      df <- data.table::fread(file, header = TRUE) |>
        tibble::column_to_rownames("V1") |>
        t() |>
        as.data.frame() |>
        tibble::rownames_to_column("gene_id")

      # rename columns to have id, k, and nmf number
      nmf_number <- sprintf("%02d", as.integer(colnames(df)[-1]))
      colnames(df)[-1] <- glue::glue("{id}_{k_value}_CNMF{nmf_number}")
      return(df)
    }
  ) |>
    purrr::reduce(dplyr::full_join, by = "gene_id") |>
    tibble::column_to_rownames("gene_id") |>
    as.matrix()

  return(spectra_mtx)

}

# helper function to build correlation dataframe with one row per pair of spectra
# duplicates are included to aid in calculation of statistics
build_spectra_cor_df <- function(cor_matrix){

  # turn the correlation matrix into a dataframe for plotting
  # one row for each correlation
  all_cor_df <- as.data.frame(as.table(cor_matrix)) |>
    dplyr::rename(spectra1 = Var1, spectra2 = Var2, correlation = Freq) |>
    # these should be characters and not factors
    dplyr::mutate(spectra1 = as.character(spectra1),
                  spectra2 = as.character(spectra2)) |>
    # remove correlations between the same spectra
    dplyr::filter(spectra1 != spectra2) |>
    dplyr::mutate(
      # add columns for sample and k value to help distinguish between/within sample comparisons
      sample1 = stringr::word(spectra1, 1, sep = "_"),
      sample2 = stringr::word(spectra2, 1, sep = "_"),
      pair_type = dplyr::if_else(sample1 == sample2, "within_sample", "between_sample")
    )

  return(all_cor_df)

}

# generate a character vector of spectra to keep after removing orphans
remove_orphan_spectra <- function(spectra_mtx, cor_matrix, orphan_cutoff){

  # create correlation dataframe with info about each spectra
  all_cor_df <- build_spectra_cor_df(cor_matrix)

  # compute cross sample max for each spectra
  cross_sample_max <- all_cor_df |>
    # only keep correlations between samples
    dplyr::filter(pair_type == "between_sample") |>
    # find the max correlation for each spectra
    dplyr::summarise(
      max_sample_cor = max(correlation, na.rm = TRUE),
      .by = spectra1
    )

  # get a vector of orphan spectra to remove
  orphan_spectra <- cross_sample_max |>
    dplyr::filter(max_sample_cor < orphan_cutoff) |>
    dplyr::pull(spectra1) |>
    as.character() # make sure they aren't factors

  keep_spectra <- which(!colnames(spectra_mtx) %in% orphan_spectra)

  return(keep_spectra)
}

# Nextflow input variables — values are interpolated by the template engine before execution
cnmf_results_dirs <- strsplit("${cnmf_dirs_string}", ",")[[1]]
n_metaprograms     <- as.integer(${n_metaprograms})
do_filter_spectra  <- tolower("${filter_spectra}") == "true"
orphan_cutoff      <- as.double(${orphan_cutoff})
n_top_genes        <- as.integer(${n_top_genes})
output_file        <- "${output_file}"
process_name       <- "${task.process}"
cnmf_k_range       <- "${cnmf_k_range}"
seed               <- as.integer(${seed})

# Fixed parameters
nreps <- 1000

# Set up -----------------------------------------------------------------------

set.seed(seed)

# make sure inputs are correct
stopifnot(
  "Not all cNMF results directories exist" = all(dir.exists(cnmf_results_dirs)),
  "orphan cutoff should be between -1 and 1" = dplyr::between(orphan_cutoff, -1, 1),
  "Output file must end in .rds" = endsWith(output_file, ".rds")
)

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

# define k range
k_range <- stringr::str_split_1(cnmf_k_range, ",") |>
    as.integer()

# get all the spectra files
spectra_files <- fs::dir_ls(
  path = cnmf_results_dirs,
  glob = "*.gene_spectra_score.k_*.dt_*.txt",
  recurse = TRUE
) |>
  # only keep files that have the values of k that we want to keep
  purrr::keep(function(file){
    k <- stringr::str_match(file, "k_([0-9]+)")[ ,2] |>
      as.integer()
    k %in% k_range || length(k_range) == 0
  })

# extract the unique ID for labeling
# everything before the first `.` corresponds to the unique ID
unique_ids <- stringr::str_extract(basename(spectra_files), pattern = "^[^.]+")
names(spectra_files) <- unique_ids

# check that there are spectra files found and that they have ids
stopifnot(
  "No spectra files found in the provided cnmf results directories with the specified values of k" =
    length(spectra_files) != 0,
  "Unable to find unique IDs for each spectra" = length(names(spectra_files)) != 0
)

# Read and filter spectra ------------------------------------------------------

# read in and build spectra mtx
spectra_mtx <- build_spectra_mtx(spectra_files)

# get correlations
cor_mtx <- cor(spectra_mtx, method = "pearson", use = "pairwise.complete.obs")

# filter spectra, identify orphans and remove them
if (do_filter_spectra) {

  # list of spectra to keep after removing orphans
  keep_spectra <- remove_orphan_spectra(spectra_mtx, cor_mtx, orphan_cutoff)

  # filter spectra mtx and cor mtx
  spectra_mtx <- spectra_mtx[, keep_spectra, drop = FALSE]
  cor_mtx <- cor_mtx[keep_spectra, keep_spectra, drop = FALSE]

}

# turn the spectra information into a dataframe
# save this to the final object for use in the report and calculating metrics
spectra_cor_df <- build_spectra_cor_df(cor_mtx)

# Generate MPs -----------------------------------------------------------------

# cluster spectra into MPs using correlation
dist_mtx <- as.dist(1-cor_mtx)
tree <- hclust(dist_mtx, method = "ward.D2")
dend <- as.dendrogram(tree)
clusters <- cutree(tree, k = n_metaprograms)

# make a list with all spectra in each cluster and name with MP0X
mp_cluster_list <- split(colnames(spectra_mtx), clusters)
names(mp_cluster_list) <- sprintf("MP%02d",seq(1, length(mp_cluster_list)))

# generate list of MPs
# each MP is a list of gene weights where weights are averaged across all spectra
# names of each list correspond to ensembl gene id
mp_list <- mp_cluster_list |>
  purrr::map(function(cluster_spectra){
    rowMeans(spectra_mtx[, cluster_spectra, drop = FALSE], na.rm = TRUE)
  })

# get a vector of any samples that might not be represented in the output spectra
spectra_unique_ids <- names(clusters) |>
  # grab just the unique ids from the spectra names that are remaining
  stringr::word(1, sep = "_")
removed_unique_ids <- setdiff(unique_ids, spectra_unique_ids)

# Shuffle MPs ------------------------------------------------------------------
# make gene x metaprogram matrix
mp_mtx <- do.call(cbind, mp_list)

# return a list of shuffled mps for each replicate
shuffled_mps <- replicate(nreps, {
  # shuffle genes for metaprograms
  rownames(mp_mtx) <- sample(rownames(mp_mtx))

  # extract top genes for each mp
  # first turn matrix into a list of vector weights where the names are gene ids
  mp_list <- asplit(mp_mtx, MARGIN = 2)
  # now return the named list of weights, names are genes
  mp_top_list <- mp_list |>
    purrr::map(function(scores){
      scores |>
        sort(decreasing = TRUE) |>
        head(n = n_top_genes)
    })
}, simplify = FALSE)


# Export MPs -------------------------------------------------------------------

# build a list with MPs, clustered spectra, cor mtx and parameters used to export
mp_info_list <- list(
  "metaprogram_list" = mp_list,
  "clusters" = clusters, # original cluster assignments
  "cluster_list" = mp_cluster_list, # spectra grouped by cluster
  "cor_matrix" = cor_mtx,
  "spectra_cor_df" = spectra_cor_df,
  "shuffled_metaprograms" = shuffled_mps,
  "gene_universe" = rownames(spectra_mtx),
  "n_metaprograms" = n_metaprograms,
  "cnmf_k_range" = cnmf_k_range,
  "filter_spectra" = do_filter_spectra,
  # if no filtering, this is -1 which means everything was kept
  "orphan_cutoff" = ifelse(do_filter_spectra, orphan_cutoff, -1),
  "unique_ids" = unique(unique_ids),
  "removed_unique_ids" = removed_unique_ids
)

readr::write_rds(mp_info_list, output_file, compress = "bz2")

# Versions ----------------------------------------------------------------------

writeLines(
  c(
    sprintf('"%s":', process_name),
    sprintf("    r-base: %s", as.character(getRversion())),
    sprintf("    dplyr: %s", as.character(utils::packageVersion("dplyr"))),
    sprintf("    purrr: %s", as.character(utils::packageVersion("purrr"))),
    sprintf("    stringr: %s", as.character(utils::packageVersion("stringr"))),
    sprintf("    data.table: %s", as.character(utils::packageVersion("data.table"))),
    sprintf("    readr: %s", as.character(utils::packageVersion("readr")))
  ),
  "versions.yml"
)
