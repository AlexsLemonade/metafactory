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
    // define options
    n_metaprograms = meta.n_metaprograms
    n_top_genes = options.n_top_genes
    filter_spectra = options.filter_spectra
    orphan_cutoff = options.orphan_cutoff
    cnmf_k_lower = options.cnmf_k_lower
    cnmf_k_upper = options.cnmf_k_upper
    cnmf_k_step_size = options.cnmf_k_step_size
    seed = options.seed

    // define input file string for R script
    cnmf_dirs_string = cnmf_output_dirs.join(',')

    // define output file using filter label and orphan cutoff
    def filter_label = filter_spectra ? 'filtered' : 'unfiltered'
    def orphan_label = filter_spectra ? "_${orphan_cutoff}" : ''
    def output_subdir = "${meta.group_id}/k-${n_metaprograms}_${filter_label}${orphan_label}"
    output_file = "${output_subdir}/k-${n_metaprograms}_metaprograms.rds"

    // parse the range of k values to test into a list of integers
    def n = (cnmf_k_upper - cnmf_k_lower).intdiv(cnmf_k_step_size)
    def cnmf_k_range_list = (0..n).collect { cnmf_k_lower + it * cnmf_k_step_size }
    cnmf_k_range = cnmf_k_range_list.join(',')

    template('generate-metaprograms.R')

    stub:
    def filter_label = options.filter_spectra ? 'filtered' : 'unfiltered'
    def orphan_label = options.filter_spectra ? "_${options.orphan_cutoff}" : ''
    def output_subdir = "${meta.group_id}/k-${meta.n_metaprograms}_${filter_label}${orphan_label}"
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
