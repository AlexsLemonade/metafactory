process GENERATE_METAPROGRAMS {
    tag "${meta.group_id}-k${meta.n_metaprograms}"
    label 'process_medium'
    label 'process_high_memory'

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/metafactory:a76461cf4574fb02'
            : 'community.wave.seqera.io/library/metafactory:8ef5094455987626'
    }

    input:
    tuple val(meta), path(cnmf_output_dirs)
    val options

    output:
    tuple val(meta), path(output_file), path(mp_export_file), path(shuffled_mp_export_file), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    // define input file string for R script
    cnmf_dirs_string = cnmf_output_dirs.join(',')

    // define output file in the publish directory for this metaprogram set
    output_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms.rds"

    // define a python readable export of the metaprogram gene weights, written alongside the RDS file
    mp_export_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms.tsv.gz"

    // define a python readable export of the gene shuffled metaprograms, written alongside the RDS file
    shuffled_mp_export_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_shuffled_metaprograms.tsv.gz"
    template('generate-metaprograms.R')

    stub:
    output_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms.rds"
    mp_export_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms.tsv.gz"
    shuffled_mp_export_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_shuffled_metaprograms.tsv.gz"
    """
    mkdir -p "${meta.metaprograms_publish_dir}"
    touch "${output_file}"
    touch "${mp_export_file}"
    touch "${shuffled_mp_export_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
