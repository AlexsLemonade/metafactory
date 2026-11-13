# metafactory

metafactory identifies metaprograms, clusters of NMF programs that recur across libraries, from single-cell and single-nuclei RNA-seq data.

## Language

### Inputs

**Library**:
The unit of analysis: one filtered and normalized single-cell or single-nuclei dataset, provided as one `.h5ad` file and one samplesheet row.
Identified by its `unique_id`, the unique combination of its sample ID and library ID.
_Avoid_: Sample

**Sample**:
The biological specimen that one or more libraries were sequenced from.
Not a pipeline concept: it is never specified as input, so every count, metric and output is in terms of libraries.

**Group**:
A set of libraries, sharing a `group_id`, that metaprograms are built across.
A library can belong to more than one group.
_Avoid_: Cohort

### Programs

**NMF program**:
One set of gene weights found by running non-negative matrix factorization (NMF) on a single library.
**Spectrum** (plural **spectra**) is an accepted synonym, taken from the cNMF package's own terminology.
_Avoid_: Program, gene expression program (without the "NMF" qualifier)

**Orphan NMF program**:
An NMF program whose highest correlation with any NMF program from a different library in the same group falls below the orphan cutoff.
Orphan status depends on the group, so the same NMF program can be an orphan in one group and not in another.

**Metaprogram**:
A cluster of NMF programs from at least two different libraries in the same group.

### Genes

**Gene weight**:
How strongly a gene contributes to an NMF program or a metaprogram.

**Top genes**:
A metaprogram's highest-weighted genes, which stand in for it in cell scores and gene set annotation.

**Gene universe**:
Every gene that appears in at least one NMF program clustered into a group's metaprograms; genes found only in orphan NMF programs are not part of it.

### Sizes

**cNMF k**:
The number of NMF programs cNMF is asked to find within a single library.
**Rank** is an accepted synonym.
_Avoid_: k (on its own), components

**Number of metaprograms**:
How many metaprograms the NMF programs of a group are clustered into; the pipeline builds metaprograms at several values.
_Avoid_: k (on its own)

**Metaprogram set**:
All the metaprograms built for one group at one number of metaprograms.

**Excluded metaprogram set**:
A metaprogram set in which clustering produced at least one cluster of NMF programs from fewer than two libraries; it is not considered when choosing the optimal k.

**Optimal k**:
The number of metaprograms the pipeline selects for a group from the values it tested, among the metaprogram sets that are not excluded.

### Scores

**Cell score**:
How strongly a single cell expresses a metaprogram's top genes.

**Shuffled metaprogram**:
A metaprogram whose gene labels have been randomly permuted.

**Score background**:
The cell scores for shuffled metaprograms, pooled across all libraries in a group; the null distribution that cell scores are compared against.
_Avoid_: Background (on its own)

### Metrics

**Metric background**:
A null distribution for a metaprogram metric, built by randomly reassigning NMF programs or gene sets to metaprograms.
_Avoid_: Background (on its own)

**Maximum metaprogram correlation**:
A metaprogram's highest correlation of gene weights with any other metaprogram in the same metaprogram set; a high value means the metaprogram is redundant.
Distinct from the correlation between NMF programs used for orphan filtering and clustering.
_Avoid_: Correlation (on its own)

**Coherence**:
How much more similar a metaprogram's NMF programs are to each other than to the NMF programs in other metaprograms of the same metaprogram set.

**Gene set specificity**:
How uniquely a metaprogram's significant gene sets belong to it rather than to other metaprograms in the same metaprogram set.

**CV of cell scores**:
How much a metaprogram's cell scores vary across cells; a higher value means the metaprogram picks out a subset of cells.

**Library diversity**:
How evenly a metaprogram's NMF programs are spread across the libraries that contribute to it.
_Avoid_: Sample diversity

**Effective library count**:
The number of equally represented libraries that would give a metaprogram the same library diversity.
_Avoid_: Effective sample size, effective species size
