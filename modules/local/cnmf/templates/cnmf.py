#!/usr/bin/env python3
"""Run cNMF on a processed AnnData object to identify consensus gene expression programs."""

import argparse
import multiprocessing
from pathlib import Path

import numpy
import anndata
import cnmf
import scipy.sparse


def parse_args() -> argparse.Namespace:
    """Parse command line arguments for cNMF processing."""
    parser = argparse.ArgumentParser(
        description=(
            "Run cNMF on a given AnnData dataset to identify consensus gene expression programs. "
            "Optionally, subset cells to a specific cell type using a column in the AnnData object's "
            "cell metadata (adata.obs)."
        )
    )
    parser.add_argument(
        "--h5ad_file",
        type=Path,
        required=True,
        help="Path to the H5AD file containing a processed AnnData object.",
    )
    parser.add_argument(
        "--annotations_column",
        type=str,
        default=None,
        help=(
            "Column name in adata.obs containing cell type annotations used to subset cells for cNMF. "
            "If not provided, all cells are used."
        ),
    )
    parser.add_argument(
        "--celltype_value",
        type=str,
        default=None,
        help=(
            "Cell type value(s) in the annotations column to keep for cNMF. "
            "Multiple values can be supplied as a comma-separated string (e.g. 'tumor,malignant'). "
            "Required when --annotations_column is provided."
        ),
    )
    parser.add_argument(
        "--output_dir",
        "-o",
        type=Path,
        required=True,
        help="Path to the directory for output and intermediate results.",
    )
    parser.add_argument(
        "--unique_id",
        type=str,
        required=True,
        help="Unique ID of the sample. Used as a subdirectory name within the output directory.",
    )
    parser.add_argument(
        "--k_components_lower",
        type=int,
        default=5,
        help="Lower boundary for number of components (k) for cNMF. (default: %(default)d)",
    )
    parser.add_argument(
        "--k_components_upper",
        type=int,
        default=15,
        help="Upper boundary for number of components (k) for cNMF. (default: %(default)d)",
    )
    parser.add_argument(
        "--k_step_size",
        type=int,
        default=5,
        help="Step size for the range of k components used in cNMF. (default: %(default)d)",
    )
    parser.add_argument(
        "--n-iter",
        "-n",
        type=int,
        default=100,
        help="Number of iterations for cNMF. (default: %(default)d)",
    )
    parser.add_argument(
        "--max-nmf-iter",
        "-m",
        type=int,
        default=2000,
        help="Maximum number of iterations for NMF. (default: %(default)d)",
    )
    parser.add_argument(
        "--density-threshold",
        type=float,
        default=0.1,
        help="Density threshold for consensus. (default: %(default)f)",
    )
    parser.add_argument(
        "--jobs",
        "-j",
        type=int,
        default=multiprocessing.cpu_count(),
        help="Number of parallel jobs to run. (default: %(default)d)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=2025,
        help="Random seed for reproducibility. (default: %(default)d)",
    )

    return parser.parse_args()


def main():
    """Subset cells (optionally), filter genes, and run cNMF factorization."""
    args = parse_args()

    # Validate H5AD input
    if not args.h5ad_file.is_file() or args.h5ad_file.suffix != ".h5ad":
        raise ValueError(
            f"H5AD file not found or has wrong extension: {args.h5ad_file}. "
            "Please ensure the file exists and has a '.h5ad' extension."
        )

    # Both annotation arguments must be provided together or not at all
    if args.annotations_column is not None and args.celltype_value is None:
        raise ValueError("--celltype_value is required when --annotations_column is provided.")
    if args.celltype_value is not None and args.annotations_column is None:
        raise ValueError("--annotations_column is required when --celltype_value is provided.")

    if args.k_components_lower >= args.k_components_upper:
        raise ValueError("k_components_lower must be less than k_components_upper.")

    k_range = numpy.arange(args.k_components_lower, args.k_components_upper + 1, args.k_step_size)

    adata = anndata.read_h5ad(args.h5ad_file)

    # Subset to requested cell type(s) if an annotations column is provided
    if args.annotations_column is not None:
        if args.annotations_column not in adata.obs.columns:
            raise KeyError(
                f"Annotations column '{args.annotations_column}' not found in adata.obs. "
                f"Available columns: {list(adata.obs.columns)}"
            )

        celltype_values = [v.strip() for v in args.celltype_value.split(",")]
        cell_mask = adata.obs[args.annotations_column].isin(celltype_values)

        if not cell_mask.any():
            raise ValueError(
                f"No cells match '{args.celltype_value}' in column '{args.annotations_column}'."
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

    cnmf_obj = cnmf.cNMF(output_dir=args.output_dir, name=args.unique_id)
    cnmf_obj.prepare(
        counts_fn=anndata_file,
        components=k_range,
        n_iter=args.n_iter,
        max_NMF_iter=args.max_nmf_iter,
        seed=args.seed,
    )

    cnmf_obj.factorize_multi_process(args.jobs)
    cnmf_obj.combine()

    for k in k_range:
        try:
            cnmf_obj.consensus(k=k, density_threshold=args.density_threshold)
        except RuntimeError as e:
            print(f"WARNING: consensus failed for k={k}: {e}")


if __name__ == "__main__":
    main()
