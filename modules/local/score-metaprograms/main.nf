process SCORE_METAPROGRAMS {
    tag "${meta.unique_id}-k${meta.n_metaprograms}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/score-metaprograms:e26abd9f451bb888'
            : 'community.wave.seqera.io/library/score-metaprograms:ece0ac8762f9a4b1'
    }

    input:
    tuple val(meta), path(metaprograms_file), path(h5ad_file)
    val options

    output:
    tuple val(meta), path(output_file), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    // write scores to the publish directory for the metaprogram set they were scored against
    output_file = "${meta.metaprograms_publish_dir}/${meta.unique_id}_metaprogram_scores.tsv.gz"

    template('score-metaprograms.py')

    stub:
    output_file = "${meta.metaprograms_publish_dir}/${meta.unique_id}_metaprogram_scores.tsv.gz"
    """
    mkdir -p "${meta.metaprograms_publish_dir}"
    touch "${output_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
