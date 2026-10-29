// Subworkflow to calculate metrics for each set of metaprograms, and annotate each set of metaprograms
// with gene sets using ORA to calculate gene set metrics

include { CALCULATE_METRICS_METAPROGRAMS } from '../../../modules/local/calculate-metrics/metaprograms/main'
include { CALCULATE_METRICS_GENESETS     } from '../../../modules/local/calculate-metrics/genesets/main'


workflow CALCULATE_METRICS {
    take:
    ch_metaprograms_rds // channel: [ meta, metaprograms_file ]
    ch_term2gene // value channel: gene sets file used for ORA
    options // value channel: [ seed, nreps ]

    main:

    //
    // MODULE: Calculate metrics for each set of metaprograms
    //
    CALCULATE_METRICS_METAPROGRAMS(
        ch_metaprograms_rds,
        options,
    )

    //
    // MODULE: Annotate each set of metaprograms with gene sets using ORA and calculate gene set metrics
    //

    CALCULATE_METRICS_GENESETS(
        ch_metaprograms_rds,
        ch_term2gene,
        options,
    )

    emit:
    metaprogram_metrics = CALCULATE_METRICS_METAPROGRAMS.out.metaprogram_metrics // channel: [ val(meta), metrics_file, background_file ]
    geneset_metrics     = CALCULATE_METRICS_GENESETS.out.ora_metrics // channel: [ val(meta), ora_results_file, metrics_file, background_file ]
}
