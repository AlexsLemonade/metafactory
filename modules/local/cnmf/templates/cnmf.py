#!/usr/bin/env python
"""Run cNMF on a processed AnnData object to identify consensus gene expression programs."""

from importlib.metadata import version
import sys
from pathlib import Path

import anndata
import cnmf
import numpy
import scipy.sparse

# Nextflow input variables — values are interpolated by the template engine before execution
h5ad_file                  = Path("${h5ad_file}")
unique_id                  = "${unique_id}"
k_lower                    = int(${cnmf_k_lower})
k_upper                    = int(${cnmf_k_upper})
k_step_size                = int(${cnmf_k_step_size})
celltype_annotation_column = "${celltype_annotation_column}"
analysis_celltypes         = "${analysis_celltypes}"
n_jobs                     = int(${task.cpus})
process_name               = "${task.process}"
SEED                       = int(${seed})

# Fixed cNMF parameters
N_ITER            = 100
MAX_NMF_ITER      = 2000
DENSITY_THRESHOLD = 0.1


def subset_cells(adata, celltype_annotation_column, analysis_celltypes):
    """Subset an AnnData object to cells matching the requested cell type(s).

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
        AnnData object containing only the requested cells.
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

    return adata[cell_mask].copy()


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
        fh.write(f"    cnmf: {version('cnmf')}\\n")


def main():
    """Subset cells (optionally), filter genes, and run cNMF factorization."""
    if not h5ad_file.is_file() or h5ad_file.suffix != ".h5ad":
        raise ValueError(
            f"H5AD file not found or has wrong extension: {h5ad_file}. "
            "Please ensure the file exists and has a '.h5ad' extension."
        )

    # Both annotation arguments must be provided together or not at all
    if celltype_annotation_column and not analysis_celltypes:
        raise ValueError("analysis_celltypes is required when celltype_annotation_column is provided.")
    if analysis_celltypes and not celltype_annotation_column:
        raise ValueError("celltype_annotation_column is required when analysis_celltypes is provided.")

    if k_lower >= k_upper:
        raise ValueError("cnmf_k_lower must be less than cnmf_k_upper.")

    k_range = numpy.arange(k_lower, k_upper + 1, k_step_size)

    adata = anndata.read_h5ad(h5ad_file)

    if celltype_annotation_column:
        adata = subset_cells(adata, celltype_annotation_column, analysis_celltypes)

    # adata.X contains normalized values when adata.raw is set; replace with raw counts
    if adata.raw is not None:
        adata.X = adata.raw.X

    x_vals = adata.X.data if scipy.sparse.issparse(adata.X) else adata.X.ravel()
    if numpy.any(x_vals % 1 != 0):
        raise ValueError("adata.X does not contain integer counts.")

    # Retain only genes with non-zero mean expression across the cells being analyzed
    detected_genes = numpy.asarray(adata.X.mean(axis=0)).ravel() > 0
    adata = adata[:, detected_genes].copy()

    # cNMF requires a minimal AnnData containing only the count matrix and index names
    cnmf_input = anndata.AnnData(X=adata.X)
    cnmf_input.obs_names = adata.obs_names
    cnmf_input.var_names = adata.var_names

    anndata_file = "anndata.h5ad"
    cnmf_input.write_h5ad(anndata_file)

    cnmf_obj = cnmf.cNMF(output_dir=".", name=f"{unique_id}_cnmf")
    cnmf_obj.prepare(
        counts_fn=anndata_file,
        components=k_range,
        n_iter=N_ITER,
        max_NMF_iter=MAX_NMF_ITER,
        seed=SEED,
    )

    cnmf_obj.factorize_multi_process(n_jobs)
    cnmf_obj.combine()

    for k in k_range:
        try:
            cnmf_obj.consensus(k=k, density_threshold=DENSITY_THRESHOLD)
        except RuntimeError as e:
            print(f"WARNING: consensus failed for k={k}: {e}")

    write_versions(process_name)


if __name__ == "__main__":
    main()
