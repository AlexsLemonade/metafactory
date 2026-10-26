// Subworkflow to calculate metrics for each set of metaprograms, and annotate each set of metaprograms
// with gene sets using ORA to calculate gene set metrics

include { CALCULATE_METRICS_METAPROGRAMS } from '../../../modules/local/calculate-metrics/metaprograms/main'
include { CALCULATE_METRICS_GENESETS     } from '../../../modules/local/calculate-metrics/genesets/main'


workflow CALCULATE_METRICS {
    take:
    ch_metaprograms_rds // channel: [ meta, metaprograms_file ]

    main:

    //
    // MODULE: Calculate metrics for each set of metaprograms
    //
    CALCULATE_METRICS_METAPROGRAMS(
        ch_metaprograms_rds,
        [
            seed: params.seed,
            nreps: params.nreps,
        ],
    )

    //
    // MODULE: Annotate each set of metaprograms with gene sets using ORA and calculate gene set metrics
    //

    // the gene sets are the same for every metaprogram set, so they are staged as a value channel
    // that every task can reuse. this has to be a `path` input on the process rather than an entry
    // in the options map, so that the file is staged into the task work directory and is readable
    // on executors that do not share a filesystem with the launch environment
    def ch_term2gene = channel.value(file(params.msigdb_gene_sets))

    CALCULATE_METRICS_GENESETS(
        ch_metaprograms_rds,
        ch_term2gene,
        [
            seed: params.seed,
            nreps: params.nreps,
        ],
    )

    emit:
    metaprogram_metrics = CALCULATE_METRICS_METAPROGRAMS.out.metaprogram_metrics // channel: [ val(meta), metrics_file, background_file ]
    geneset_metrics     = CALCULATE_METRICS_GENESETS.out.ora_metrics // channel: [ val(meta), ora_results_file, metrics_file, background_file ]
}
