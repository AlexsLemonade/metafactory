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

The default value of `--msigdb_gene_sets`.
This is a tab-separated file listing which [MSigDB](https://www.gsea-msigdb.org/gsea/msigdb) gene sets are used to when running overrepresentation analysis on each set of metaprograms.
Each row selects either an entire (sub)collection or a single named gene set.

| Column          | Description                                                                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`          | Short label used to identify this row in the pipeline output. Must be unique.                                                                                |
| `collection`    | MSigDB collection code, e.g. `H` (hallmark), `C2` (curated), `C6` (oncogenic signatures).                                                                    |
| `subcollection` | MSigDB subcollection code within `collection`, e.g. `CP:REACTOME`. Use `NA` for collections that have no subcollections, or to use the full collection.      |
| `geneset`       | Name of a single gene set within the selected (sub)collection, e.g. `HALLMARK_HYPOXIA`. Use `all` to include every gene set in the selected (sub)collection. |

The collection and subcollection codes must match those used by MSigDB.
The full list is available in the [MSigDB collections documentation](https://www.gsea-msigdb.org/gsea/msigdb/human/collections.jsp).

To use a different set of gene sets, copy this file, edit it, and pass it with `--msigdb_gene_sets <path/to/file.tsv>`.
