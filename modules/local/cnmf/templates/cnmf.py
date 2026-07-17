#!/usr/bin/env python3
"""Run cNMF on a processed AnnData object to identify consensus gene expression programs."""

import importlib.metadata
import sys
from pathlib import Path

import anndata
import cnmf
import numpy
import scipy.sparse

# Nextflow input variables — values are interpolated by the template engine before execution
h5ad_file          = Path("${h5ad_file}")
unique_id          = "${unique_id}"
k_lower            = int(${cnmf_k_lower})
k_upper            = int(${cnmf_k_upper})
k_step_size        = int(${cnmf_k_step_size})
annotations_column = "${annotations_column}" or None
celltype_value     = "${celltype_value}" or None
n_jobs             = int(${task.cpus})
process_name       = "${task.process}"

# Fixed cNMF parameters
N_ITER            = 100
MAX_NMF_ITER      = 2000
DENSITY_THRESHOLD = 0.1
SEED              = 2025


def main():
    """Subset cells (optionally), filter genes, and run cNMF factorization."""
    if not h5ad_file.is_file() or h5ad_file.suffix != ".h5ad":
        raise ValueError(
            f"H5AD file not found or has wrong extension: {h5ad_file}. "
            "Please ensure the file exists and has a '.h5ad' extension."
        )

    # Both annotation arguments must be provided together or not at all
    if annotations_column is not None and celltype_value is None:
        raise ValueError("celltype_value is required when annotations_column is provided.")
    if celltype_value is not None and annotations_column is None:
        raise ValueError("annotations_column is required when celltype_value is provided.")

    if k_lower >= k_upper:
        raise ValueError("cnmf_k_lower must be less than cnmf_k_upper.")

    k_range = numpy.arange(k_lower, k_upper + 1, k_step_size)

    adata = anndata.read_h5ad(h5ad_file)

    # Subset to requested cell type(s) if an annotations column is provided
    if annotations_column is not None:
        if annotations_column not in adata.obs.columns:
            raise KeyError(
                f"Annotations column '{annotations_column}' not found in adata.obs. "
                f"Available columns: {list(adata.obs.columns)}"
            )

        celltype_values = [v.strip() for v in celltype_value.split(",")]
        cell_mask = adata.obs[annotations_column].isin(celltype_values)

        if not cell_mask.any():
            raise ValueError(
                f"No cells match '{celltype_value}' in column '{annotations_column}'."
            )

        adata = adata[cell_mask].copy()

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

    cnmf_obj = cnmf.cNMF(output_dir=".", name=unique_id)
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

    python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    with open("versions.yml", "w") as fh:
        fh.write(f'"{process_name}":\n')
        fh.write(f"    python: {python_version}\n")
        fh.write(f"    anndata: {anndata.__version__}\n")
        fh.write(f'    cnmf: {importlib.metadata.version("cnmf")}\n')


if __name__ == "__main__":
    main()
