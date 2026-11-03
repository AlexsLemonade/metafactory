process COMBINE_SCORES {
    tag "${meta.group_id}-k${meta.n_metaprograms}-${meta.score_type}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/combine-scores:5f7671390569f205'
            : 'community.wave.seqera.io/library/combine-scores:341c0ea24858146e'
    }

    input:
    tuple val(meta), path(score_files)

    output:
    tuple val(meta), path(output_file), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    // define input file string for R script
    input_files_string = score_files.join(',')

    // use the score type to specify the output files
    output_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_combined_${meta.score_type}.tsv.gz"

    template('combine-scores.R')

    stub:
    output_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_combined_${meta.score_type}.tsv.gz"
    """
    mkdir -p "${meta.metaprograms_publish_dir}"
    touch "${output_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
