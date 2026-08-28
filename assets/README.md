# Assets

Files bundled with the pipeline and used as default inputs.

## `samplesheet.csv`

An example samplesheet, used as the default `--input` for the `dev` profile (see `conf/alsf-profiles.config`).
It points at simulated test data from OpenScPCA-nf.
Columns are described in and validated against `schema_input.json`.

## `schema_input.json`

JSON schema used by `nf-schema` to validate the file passed to `--input`.
It is referenced from the `input` parameter in `nextflow_schema.json`, and is applied automatically when the samplesheet is parsed.

## `msigdb-gene-sets.tsv`

A tab-separated file listing which [MSigDB](https://www.gsea-msigdb.org/gsea/msigdb) gene sets are used when running overrepresentation analysis on each set of metaprograms.
Each row selects either an entire (sub)collection or a single named gene set.

This file is not read by the pipeline itself.
It is the input to `scripts/build-msigdb-gene-sets.R`, which downloads the selected gene sets from MSigDB and writes `msigdb-gene-set-genes.tsv.gz` (see below).
Downloading requires internet access, so the gene sets are bundled with the pipeline rather than pulled at runtime.

| Column          | Description                                                                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`          | Short label used to identify this row in the pipeline output. Must be unique.                                                                                |
| `collection`    | MSigDB collection code, e.g. `H` (hallmark), `C2` (curated), `C6` (oncogenic signatures).                                                                    |
| `subcollection` | MSigDB subcollection code within `collection`, e.g. `CP:REACTOME`. Use `NA` for collections that have no subcollections, or to use the full collection.      |
| `geneset`       | Name of a single gene set within the selected (sub)collection, e.g. `HALLMARK_HYPOXIA`. Use `all` to include every gene set in the selected (sub)collection. |

The collection and subcollection codes must match those used by MSigDB.
The full list is available in the [MSigDB collections documentation](https://www.gsea-msigdb.org/gsea/msigdb/human/collections.jsp).

To change which gene sets are used, edit this file and re-run `scripts/build-msigdb-gene-sets.R` to rebuild `msigdb-gene-set-genes.tsv.gz`.

## `msigdb-gene-set-genes.tsv.gz`

The default value of `--msigdb_gene_sets`.
This is a gzipped tab-separated file holding the genes in each of the MSigDB gene sets selected by `msigdb-gene-sets.tsv`, with one row per gene per gene set.
It is built by `scripts/build-msigdb-gene-sets.R` and only needs to be rebuilt when `msigdb-gene-sets.tsv` changes or when the gene sets should be updated to a newer release of MSigDB.

| Column         | Description                                                                                |
| -------------- | ------------------------------------------------------------------------------------------ |
| `collection`   | Label for the gene set collection, taken from the `name` column of `msigdb-gene-sets.tsv`. |
| `gs_name`      | Name of the MSigDB gene set, e.g. `HALLMARK_HYPOXIA`.                                      |
| `ensembl_gene` | Ensembl gene ID of a gene in `gs_name`.                                                    |

To use a different set of gene sets, build your own table with these columns and pass it with `--msigdb_gene_sets <path/to/file.tsv[.gz]>`.
