process SCORE_BACKGROUND {
    tag "${meta.unique_id}-k${meta.n_metaprograms}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/score-background:f7b56d72e2cd7bc8'
            : 'community.wave.seqera.io/library/score-background:6fe329cb616c2bf4'
    }

    input:
    tuple val(meta), path(metaprograms_file), path(shuffled_metaprograms_file), path(h5ad_file)
    val options

    output:
    tuple val(meta), path(output_file), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    // write background stats to the publish directory for the metaprogram set they were scored against
    output_file = "${meta.metaprograms_publish_dir}/${meta.unique_id}_background_score_stats.tsv.gz"

    template('score-background.py')

    stub:
    output_file = "${meta.metaprograms_publish_dir}/${meta.unique_id}_background_score_stats.tsv.gz"
    """
    mkdir -p "${meta.metaprograms_publish_dir}"
    touch "${output_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
