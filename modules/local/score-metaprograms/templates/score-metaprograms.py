#!/usr/bin/env python
"""Score every cell in an AnnData object against each metaprogram generated for its group.

The output is a gzipped long format TSV containing the following columns:
metaprogram, barcodes, mp_score, unique_id
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
celltype_annotation_column = "${options.celltype_annotation_column}"
analysis_celltypes         = "${options.analysis_celltypes}"
unique_id                  = "${meta.unique_id}"
n_top_genes                = int(${options.n_top_genes})
output_path                = pathlib.Path("${output_file}")
n_jobs                     = int(${task.cpus})
process_name               = "${task.process}"
SEED                       = int(${options.seed})


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
        View of the AnnData object containing only the requested cells.
    """
    if celltype_annotation_column not in adata.obs.columns:
        raise KeyError(
            f"Annotations column '{celltype_annotation_column}' not found in adata.obs. "
            f"Available columns: {list(adata.obs.columns)}"
        )

    celltype_list = [v.strip() for v in analysis_celltypes.split(",")]
    cell_mask = adata.obs[celltype_annotation_column].isin(celltype_list)

    if not cell_mask.any():
        raise ValueError(
            f"No cells match '{analysis_celltypes}' in column '{celltype_annotation_column}'."
        )

    return adata[cell_mask]


def score_metaprogram(gene_weights, scored_genes, norm_expr, n_top_genes):
    """Score every cell for a single metaprogram.

    The score for a cell is the dot product of the metaprogram's top gene weights and the
    quantile normalized expression of those genes in that cell.

    Parameters
    ----------
    gene_weights:
        Series of gene weights for one metaprogram, indexed by gene ID.
    scored_genes:
        Index of the gene IDs in norm_expr, in the same order as its rows.
    norm_expr:
        Quantile normalized gene x cell expression matrix.
    n_top_genes:
        Number of top weighted genes to use for scoring.

    Returns
    -------
    numpy.ndarray
        Score for each cell, in the column order of norm_expr.
    """
    # align the top weights to the rows of norm_expr, leaving NaN wherever a gene of the
    # metaprogram is not present in the AnnData object
    top_weights = gene_weights.nlargest(n_top_genes).reindex(scored_genes)
    found_genes = top_weights.notna().to_numpy()

    if not found_genes.any():
        raise ValueError("None of the top genes for this metaprogram are present in the object.")

    return top_weights.to_numpy()[found_genes] @ norm_expr[found_genes, :]


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
    """Score all cells used to generate the metaprograms against each metaprogram."""

    # the scoring below is deterministic, the seed is set for parity with the other modules
    numpy.random.seed(SEED)

    if not output_path.name.endswith((".tsv", ".tsv.gz")):
        raise ValueError("Output file must end in .tsv or .tsv.gz")

    # both annotation arguments must be provided together or not at all
    if celltype_annotation_column and not analysis_celltypes:
        raise ValueError("analysis_celltypes is required when celltype_annotation_column is provided.")
    if analysis_celltypes and not celltype_annotation_column:
        raise ValueError("celltype_annotation_column is required when analysis_celltypes is provided.")

    # read in the metaprograms file and build a dictionary of gene weights for each metaprogram
    mp_df = pandas.read_csv(
        metaprograms_file,
        sep="\\t",
        usecols=["metaprogram", "gene_id", "weight"],
        dtype={"metaprogram": str, "gene_id": str, "weight": numpy.float32},
    )

    mp_dict = {
        mp_name: group.set_index("gene_id")["weight"]
        for mp_name, group in mp_df.groupby("metaprogram", sort=True)
    }

    # define the gene universe based on the union of all genes in metaprograms
    gene_universe = mp_df["gene_id"].unique()

    # read in backed mode so that only the cells and genes being scored are read from disk
    adata = anndata.read_h5ad(h5ad_file, backed="r")

    if adata.var_names.has_duplicates:
        raise ValueError("Gene IDs in the AnnData object are not unique.")

    # only score the cells the metaprograms were generated from
    if celltype_annotation_column:
        adata = subset_cells(adata, celltype_annotation_column, analysis_celltypes)

    # cells and genes to score; scored_genes is the row order of the matrix scored below
    barcodes = adata.obs_names.to_numpy()
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
    norm_expr = qnorm.quantile_normalize(expr, axis=1, ncpus=n_jobs)
    del expr

    scores_df = pandas.concat(
        [
            pandas.DataFrame(
                {
                    "metaprogram": mp_name,
                    "barcodes": barcodes,
                    "mp_score": score_metaprogram(gene_weights, scored_genes, norm_expr, n_top_genes),
                }
            )
            for mp_name, gene_weights in mp_dict.items()
        ],
        ignore_index=True,
    )
    scores_df["unique_id"] = unique_id

    output_path.parent.mkdir(parents=True, exist_ok=True)
    scores_df.to_csv(output_path, sep="\\t", index=False)

    write_versions(process_name)


if __name__ == "__main__":
    main()
