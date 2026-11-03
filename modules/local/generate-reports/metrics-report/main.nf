process RENDER_METRICS_REPORT {
    tag "${meta.group_id}"

    label 'process_medium'
    label 'results'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/generate-reports:793f057fb260cd19'
            : 'community.wave.seqera.io/library/generate-reports:23cf21ec4e453820'
    }

    input:
    tuple val(meta), path(metaprogram_metrics_file), path(k_metrics_file), path(neff_background_file), path(specificity_background_file), path(cv_background_file), path(optimal_k_file)
    path report_rmd, stageAs: 'report/report.rmd'
    val options

    output:
    tuple val(meta), path(report_file), emit: report
    path "versions.yml", emit: versions, topic: versions

    script:

    // define output files
    output_dir = "${meta.group_id}"
    report_file = "${output_dir}/combined-metaprogram-metrics.html"

    template('render-combined-metaprogram-metrics.R')

    stub:
    output_dir = "${meta.group_id}"
    report_file = "${output_dir}/combined-metaprogram-metrics.html"
    """
    mkdir -p "${output_dir}"
    touch "${report_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
