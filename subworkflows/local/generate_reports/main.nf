// Subworkflow to generate reports based on the optimal value of k and the associated report metrics


// TODO: Add in module for generating the individual report
include { RENDER_METRICS_REPORT } from '../../../modules/local/generate-reports/metrics-report/main'


workflow GENERATE_REPORTS {
    take:
    optimal_k_ch // channel: [ meta, optimal_k_file ]
    report_metrics_ch // channel: [ meta, report metrics files ]

    main:

    // combine the report metrics and the optimal k into a single channel for the report
    def ch_report_input = report_metrics_ch.join(optimal_k_ch)

    // the report rmd file is staged as a value channel that every task
    // can reuse. like the gene sets, this has to be a `path` input on the process rather than a
    // path built from `moduleDir`, so that the file is staged into the task work directory and is
    // readable on executors that do not share a filesystem with the launch environment
    RENDER_METRICS_REPORT(
        ch_report_input,
        file("${projectDir}/modules/local/generate-reports/assets/combined-metaprogram-metrics.Rmd")
        [
            n_top_genes: params.n_top_genes,
            seed: params.seed,
        ],
    )

    emit:
    metrics_report = RENDER_METRICS_REPORT.out.report // channel: [ val(meta), [ report ] ]
}
