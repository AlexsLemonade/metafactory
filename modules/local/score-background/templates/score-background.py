#!/usr/bin/env python
"""Calculate a background (null) score distribution for one library from shuffled metaprograms.

Each (replicate, metaprogram) pair in the shuffled metaprograms file is one gene label shuffled
metaprogram, and is scored exactly as a real metaprogram is by the score metaprograms module: the
dot product of its gene weights and the quantile normalized expression of those genes in a cell.

Per cell scores are never written out. For each shuffled metaprogram only the number of cells,
the mean score, and the sum of squared deviations from that mean (M2) are kept, because that
triple is exactly what Chan's parallel variance algorithm needs to pool the mean and variance of
the null distribution across libraries downstream. Keeping the per cell scores would mean
writing n_replicates x n_metaprograms x n_cells rows per library for no additional information.

The output is a gzipped long format TSV containing the following columns:
metaprogram, replicate, num_cells, mean_mp_score, M2, unique_id
"""

from importlib.metadata import version
import pathlib
import sys

import anndata
import numpy
import pandas
import qnorm
import scipy.sparse

# Nextflow input variables — values are interpolated by the template engine before execution
h5ad_file                  = "${h5ad_file}"
metaprograms_file          = "${metaprograms_file}"
shuffled_metaprograms_file = "${shuffled_metaprograms_file}"
celltype_annotation_column = "${options.celltype_annotation_column}"
analysis_celltypes         = "${options.analysis_celltypes}"
unique_id                  = "${meta.unique_id}"
output_path                = pathlib.Path("${output_file}")
n_jobs                     = int(${task.cpus})
process_name               = "${task.process}"
SEED                       = int(${options.seed})

# columns of the output table, kept here so an empty table has the same header as a populated one
OUTPUT_COLUMNS = ["metaprogram", "replicate", "num_cells", "mean_mp_score", "M2", "unique_id"]


def subset_cells(adata, celltype_annotation_column, analysis_celltypes):
    """Subset an AnnData object to cells matching the requested cell type(s).

    This is the same subsetting used by the cnmf module, so that the metaprograms are scored on
    the cells they were generated from. Unlike that module a view is returned rather than a copy,
    because `.copy()` raises on a backed object and the object is read in backed mode here so
    that only the cells being scored are read from disk.

    Parameters
    ----------
    adata:
        AnnData object to subset.
    celltype_annotation_column:
        Column in adata.obs containing cell type labels.
    analysis_celltypes:
        Comma-separated string of cell type values to retain.

    Returns
    -------
    anndata.AnnData
        View of the AnnData object containing only the requested cells. The view contains no
        cells if none of them match, which is not an error; a library that does not contain the
        requested cell types contributes nothing to the null distribution rather than failing
        the run.
    """
    if celltype_annotation_column not in adata.obs.columns:
        raise KeyError(
            f"Annotations column '{celltype_annotation_column}' not found in adata.obs. "
            f"Available columns: {list(adata.obs.columns)}"
        )

    celltype_list = [v.strip() for v in analysis_celltypes.split(",")]
    cell_mask = adata.obs[celltype_annotation_column].isin(celltype_list)

    return adata[cell_mask]


def normalized_expression(h5ad_file, gene_universe, celltype_annotation_column, analysis_celltypes, n_jobs):
    """Read a library and return its quantile normalized expression for the metaprogram genes.

    This is the same preprocessing the score metaprograms module does, so that the background
    scores are on the same scale as the real scores.

    Parameters
    ----------
    h5ad_file:
        Path to the AnnData object for the library.
    gene_universe:
        Gene IDs the expression matrix is subset to before normalizing.
    celltype_annotation_column:
        Column in adata.obs containing cell type labels, or an empty string to score all cells.
    analysis_celltypes:
        Comma-separated string of cell type values to retain.
    n_jobs:
        Number of processes to use for quantile normalization.

    Returns
    -------
    tuple of (numpy.ndarray, pandas.Index)
        Quantile normalized gene x cell expression matrix, and the gene IDs in the order of its
        rows. Both are None when there are no cells left to score after subsetting.
    """
    # read in backed mode so that only the cells and genes being scored are read from disk
    adata = anndata.read_h5ad(h5ad_file, backed="r")

    if adata.var_names.has_duplicates:
        raise ValueError("Gene IDs in the AnnData object are not unique.")

    # only score the cells the metaprograms were generated from
    if celltype_annotation_column:
        adata = subset_cells(adata, celltype_annotation_column, analysis_celltypes)

    # nothing to normalize or score, which the caller turns into an empty output table
    if adata.n_obs == 0:
        print(
            f"No cells to score in '{h5ad_file}' after subsetting.",
            file=sys.stderr,
        )
        del adata
        return None, None

    # genes to score; scored_genes is the row order of the matrix returned below
    gene_positions = adata.var_names.isin(gene_universe)
    scored_genes = adata.var_names[gene_positions]

    if not gene_positions.any():
        raise ValueError("None of the metaprogram genes are present in the AnnData object.")

    # adata.X contains normalized values when adata.raw is set, otherwise they are in the logcounts layer
    if adata.raw is not None:
        expr = adata.X
    elif "logcounts" in adata.layers:
        expr = adata.layers["logcounts"]
    else:
        raise ValueError(
            "Log normalized counts not found: adata.raw is not set and the AnnData object has "
            "no 'logcounts' layer."
        )

    # subset the genes while the matrix is still sparse, before it is densified below
    expr = expr[:, gene_positions]

    # if the subset was not materialized by the indexing above the matrix is still on disk,
    # so read it in before the file handle is released with adata
    if not (isinstance(expr, numpy.ndarray) or scipy.sparse.issparse(expr)):
        expr = expr[:]

    del adata

    # densify only the gene x cell submatrix that is scored, transposing sparse data is free
    expr = expr.astype(numpy.float32, copy=False)
    if scipy.sparse.issparse(expr):
        expr = expr.T.toarray()
    else:
        expr = numpy.ascontiguousarray(expr.T)

    # quantile normalize across cells, matching preprocessCore::normalize.quantiles()
    # axis=1 normalizes each column, which is one cell in this gene x cell matrix
    return qnorm.quantile_normalize(expr, axis=1, ncpus=n_jobs), scored_genes


def score_shuffled_metaprogram(mp_rows, norm_expr):
    """Score every cell for a single shuffled metaprogram.

    The score for a cell is the dot product of the shuffled metaprogram's gene weights and the
    quantile normalized expression of those genes in that cell. The rows passed in are already
    the top weighted genes of the metaprogram, selected upstream when the shuffles were built.

    Parameters
    ----------
    mp_rows:
        Rows of the shuffled metaprograms table for one shuffled metaprogram, including the
        `gene_row` column giving each gene's row in norm_expr and `weight` column.
    norm_expr:
        Quantile normalized gene x cell expression matrix.

    Returns
    -------
    numpy.ndarray
        Score for each cell, in the column order of norm_expr.
    """
    gene_rows = mp_rows["gene_row"].to_numpy()

    # drop genes that are not in the AnnData object, as scoring the real metaprograms does
    found_genes = gene_rows >= 0

    if not found_genes.any():
        raise ValueError("None of the genes for this shuffled metaprogram are present in the object.")

    return mp_rows["weight"].to_numpy()[found_genes] @ norm_expr[gene_rows[found_genes], :]


def summarize_scores(scores):
    """Reduce the per cell scores of one shuffled metaprogram to summary statistics.

    Parameters
    ----------
    scores:
        Score for each cell for a single shuffled metaprogram.

    Returns
    -------
    dict
        The number of cells, the mean score, and the sum of squared deviations from that mean.
    """
    mean_score = scores.mean(dtype=numpy.float64)
    diff = scores.astype(numpy.float64, copy=False) - mean_score
    M2 = numpy.dot(diff, diff)

    return {
        "num_cells": scores.size,
        "mean_mp_score": mean_score,
        "M2": M2,
    }

def write_versions(process_name):
    """Write a versions.yml file recording the versions of all software used.

    Parameters
    ----------
    process_name:
        Nextflow process name, used as the top-level key in versions.yml.
    """
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    with open("versions.yml", "w") as fh:
        fh.write(f'"{process_name}":\\n')
        fh.write(f"    python: {python_version}\\n")
        fh.write(f"    anndata: {version('anndata')}\\n")
        fh.write(f"    numpy: {version('numpy')}\\n")
        fh.write(f"    pandas: {version('pandas')}\\n")
        fh.write(f"    qnorm: {version('qnorm')}\\n")
        fh.write(f"    scipy: {version('scipy')}\\n")


def main():
    """Score all cells used to generate the metaprograms against each shuffled metaprogram."""

    # the scoring below is deterministic, the seed is set for parity with the other modules
    numpy.random.seed(SEED)

    if not output_path.name.endswith((".tsv", ".tsv.gz")):
        raise ValueError("Output file must end in .tsv or .tsv.gz")

    # both annotation arguments must be provided together or not at all
    if celltype_annotation_column and not analysis_celltypes:
        raise ValueError("analysis_celltypes is required when celltype_annotation_column is provided.")
    if analysis_celltypes and not celltype_annotation_column:
        raise ValueError("celltype_annotation_column is required when analysis_celltypes is provided.")

    # read in the real metaprograms file, which is used only to define the gene universe
    mp_df = pandas.read_csv(
        metaprograms_file,
        sep="\\t",
        usecols=["metaprogram", "gene_id", "weight"],
        dtype={"metaprogram": str, "gene_id": str, "weight": numpy.float32},
    )

    # read in the shuffled metaprograms file, which is used to make the background score distribution
    shuffled_df = pandas.read_csv(
        shuffled_metaprograms_file,
        sep="\\t",
        usecols=["replicate", "metaprogram", "gene_id", "weight"],
        dtype={
            "replicate": numpy.int32,
            "metaprogram": str,
            "gene_id": str,
            "weight": numpy.float32,
        },
    )

    # define the gene universe based on the union of all genes in metaprograms
    # don't use the shuffled ones since we only save the top 200 genes
    gene_universe = mp_df["gene_id"].unique()

    # quantile normalize the expression of the metaprogram genes in the cells being scored, and get the
    # gene IDs in the order of the rows of the returned matrix, which is used to look up each gene's row in the matrix for scoring
    norm_expr, scored_genes = normalized_expression(
        h5ad_file, gene_universe, celltype_annotation_column, analysis_celltypes, n_jobs
    )

    # a library with no cells to score has no background distribution, so write an empty table
    # with the expected columns instead of failing the run
    if norm_expr is None:
        pandas.DataFrame(columns=OUTPUT_COLUMNS).to_csv(output_path, sep="\\t", index=False)
        write_versions(process_name)
        return

    # look up each gene's row in norm_expr once; genes that are not in the object get -1 which means they will be dropped
    shuffled_df["gene_row"] = scored_genes.get_indexer(shuffled_df["gene_id"])

    # score one shuffled metaprogram at a time, keeping only its summary statistics, so that the
    # scores for a single shuffled metaprogram are the largest array held at any point
    background_stats = []
    for (replicate, mp_name), mp_rows in shuffled_df.groupby(["replicate", "metaprogram"], sort=True):
        scores = score_shuffled_metaprogram(mp_rows, norm_expr)
        background_stats.append(
            {"metaprogram": mp_name, "replicate": replicate, **summarize_scores(scores)}
        )

    background_df = pandas.DataFrame(background_stats).sort_values(
        ["metaprogram", "replicate"], ignore_index=True
    )
    # add a column with unique id for combining all background files later
    background_df["unique_id"] = unique_id

    # export summarized background stats
    background_df.to_csv(output_path, sep="\\t", index=False)

    write_versions(process_name)


if __name__ == "__main__":
    main()
