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
    tuple val(meta), path(output_file), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    // define input file string for R script
    cnmf_dirs_string = cnmf_output_dirs.join(',')

    // define output file using filter label and orphan cutoff
    def filter_label = options.filter_spectra ? "filtered_${options.orphan_cutoff}" : 'unfiltered'
    def output_subdir = "${meta.group_id}/k-${meta.n_metaprograms}_${filter_label}"
    output_file = "${output_subdir}/k-${meta.n_metaprograms}_metaprograms.rds"

    template('generate-metaprograms.R')

    stub:
    def filter_label = options.filter_spectra ? "filtered_${options.orphan_cutoff}" : 'unfiltered'
    def output_subdir = "${meta.group_id}/k-${meta.n_metaprograms}_${filter_label}"
    output_file = "${output_subdir}/k-${meta.n_metaprograms}_metaprograms.rds"
    """
    mkdir -p "${output_subdir}"
    touch "${output_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
