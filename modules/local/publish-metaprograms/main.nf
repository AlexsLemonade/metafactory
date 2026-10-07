process PUBLISH_METAPROGRAMS {
    tag "${meta.group_id}-k${meta.optimal_k}"

    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container 'docker.io/library/ubuntu:24.04'

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
}
