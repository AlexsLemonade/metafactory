process CALCULATE_METRICS_METAPROGRAMS {
    tag "${meta.group_id}-k${meta.n_metaprograms}"

    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/metaprogram-metrics:e8fb8b86e17626f9'
            : 'community.wave.seqera.io/library/metaprogram-metrics:21ea77835f3ef03c'
    }

    input:
    tuple val(meta), path(metaprograms_file)
    val options

    output:
    tuple val(meta), path(metrics_file), emit: metrics
    tuple val(meta), path(background_file), emit: background
    path "versions.yml", emit: versions, topic: versions

    script:
    // metaprogram specific metrics
    metrics_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_mp_metrics.tsv"

    // the background holds one row per metaprogram per replicate, so it is gzipped
    background_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_background_mp_stats.tsv.gz"

    template('calculate-metaprogram-metrics.R')

    stub:
    metrics_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_mp_metrics.tsv"
    background_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_background_mp_stats.tsv.gz"
    """
    mkdir -p "${meta.metaprograms_publish_dir}"
    touch "${metrics_file}"
    touch "${background_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
