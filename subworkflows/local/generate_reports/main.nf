// Subworkflow to generate reports based on the optimal value of k and the associated report metrics

include { RENDER_METRICS_REPORT    } from '../../../modules/local/generate-reports/metrics-report/main'
include { RENDER_INDIVIDUAL_REPORT } from '../../../modules/local/generate-reports/individual-report/main'


workflow GENERATE_REPORTS {
    take:
    optimal_k_ch // channel: [ meta, optimal_k_file ]
    report_metrics_ch // channel: [ meta, report metrics files ]
    ch_optimal_metaprogram_set // channel: [ meta, metaprograms_file, metaprogram_metrics_file, geneset_metrics_file, ora_results_file, combined_scores_file ]

    main:

    // combine the report metrics and the optimal k into a single channel for the metrics report
    def ch_metrics_report_input = report_metrics_ch.join(optimal_k_ch)

    // the individual report does not read the gene set metrics table, so it is dropped here
    def ch_individual_report_input = ch_optimal_metaprogram_set.map { meta, metaprograms_rds_file, metaprogram_metrics_file, _geneset_metrics_file, ora_results_file, cell_scores_file ->
        [meta, metaprograms_rds_file, metaprogram_metrics_file, ora_results_file, cell_scores_file]
    }


    // the report rmd file is staged as a value channel that every task
    // can reuse. like the gene sets, this has to be a `path` input on the process rather than a
    // path built from `moduleDir`, so that the file is staged into the task work directory and is
    // readable on executors that do not share a filesystem with the launch environment
    RENDER_METRICS_REPORT(
        ch_metrics_report_input,
        file("${projectDir}/modules/local/generate-reports/metrics-report/assets/combined-metaprogram-metrics.Rmd"),
        [
            n_top_genes: params.n_top_genes,
            seed: params.seed,
        ],
    )

    // the individual report evaluates the metaprogram set chosen as the optimal value of k, so it
    // is built from the per metaprogram set files for that k rather than from the metrics
    // summarized across every value of k
    RENDER_INDIVIDUAL_REPORT(
        ch_individual_report_input,
        file("${projectDir}/modules/local/generate-reports/individual-report/assets/individual-metaprogram-evaluation.Rmd"),
        [seed: params.seed],
    )

    emit:
    metrics_report    = RENDER_METRICS_REPORT.out.report // channel: [ val(meta), [ report ] ]
    individual_report = RENDER_INDIVIDUAL_REPORT.out.report // channel: [ val(meta), [ report ] ]
}
