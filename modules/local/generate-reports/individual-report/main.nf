process RENDER_INDIVIDUAL_REPORT {
    tag "${meta.group_id}-k${meta.n_metaprograms}"

    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/generate-reports:f755ba2f18798ae8'
            : 'community.wave.seqera.io/library/generate-reports:ec6d0d1777ea5c08'
    }

    input:
    tuple val(meta), path(metaprograms_file), path(metaprogram_metrics_file), path(geneset_metrics_file), path(ora_results_file), path(combined_scores_file)
    path report_rmd, stageAs: 'report/report.rmd'

    output:
    tuple val(meta), path(report_file), emit: report
    path "versions.yml", emit: versions, topic: versions

    script:

    // all output for this metaprogram set is written alongside the other checkpoint files for it
    output_dir = "${meta.metaprograms_publish_dir}"
    report_file = "${output_dir}/k-${meta.n_metaprograms}_individual-metaprogram-evaluation.html"

    template('render-individual-metaprogram-evaluation.R')

    stub:
    output_dir = "${meta.metaprograms_publish_dir}"
    report_file = "${output_dir}/k-${meta.n_metaprograms}_individual-metaprogram-evaluation.html"
    """
    mkdir -p "${output_dir}"
    touch "${report_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
