process PUBLISH_METAPROGRAMS {
    tag "${meta.group_id}-k${meta.optimal_k}"

    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/publish-metaprograms:25fa452f5af16069'
            : 'community.wave.seqera.io/library/publish-metaprograms:a3062d416e788dd4'
    }

    input:
    tuple val(meta), path(output_files)

    output:
    tuple val(meta), path("${output_dir}/*"), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    // every file for this group is copied into one directory named for the group
    output_dir = "${meta.group_id}"
    """
    mkdir -p "${output_dir}"

    for f in ${output_files}; do
      # -L so that the copies hold the file contents rather than the symlinks nextflow stages in
      cp -L "\${f}" "${output_dir}/"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: \$(cp --version | head -n 1 | sed 's/^.* //')
    END_VERSIONS
    """

    stub:
    output_dir = "${meta.group_id}"
    """
    mkdir -p "${output_dir}"

    for f in ${output_files}; do
      # -L so that the copies hold the file contents rather than the symlinks nextflow stages in
      cp -L "\${f}" "${output_dir}/"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
