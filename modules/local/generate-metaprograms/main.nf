process GENERATE_METAPROGRAMS {
    tag "${group_id}-k${n_metaprograms}"
    label 'process_medium'
    label 'process_high_memory'

    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/metafactory:a76461cf4574fb02'
            : 'community.wave.seqera.io/library/metafactory:8ef5094455987626'
    }

    input:
    tuple val(group_id), val(unique_ids), path(cnmf_output_dirs), val(n_metaprograms)
    val n_top_genes
    val filter_spectra
    val orphan_cutoff
    val cnmf_k_lower
    val cnmf_k_upper
    val cnmf_k_step_size
    val seed

    output:
    tuple val(group_id), val(n_metaprograms), val(unique_ids), path(output_file), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    cnmf_dirs_string = cnmf_output_dirs.join(',')
    def filter_label = filter_spectra ? 'filtered' : 'unfiltered'
    def orphan_label = filter_spectra ? "_${orphan_cutoff}" : ''
    def output_subdir = "${group_id}/k-${n_metaprograms}_${filter_label}${orphan_label}"
    output_file = "${output_subdir}/k-${n_metaprograms}_metaprograms.rds"
    def n = (cnmf_k_upper - cnmf_k_lower).intdiv(cnmf_k_step_size)
    def cnmf_k_range_list = (0..n).collect { cnmf_k_lower + it * cnmf_k_step_size }
    def cnmf_k_range = cnmf_k_range_list.join(',')
    template('generate-metaprograms.R')

    stub:
    def filter_label = filter_spectra ? 'filtered' : 'unfiltered'
    def orphan_label = filter_spectra ? "_${orphan_cutoff}" : ''
    def output_subdir = "${group_id}/k-${n_metaprograms}_${filter_label}${orphan_label}"
    output_file = "${output_subdir}/k-${n_metaprograms}_metaprograms.rds"
    """
    mkdir -p "${output_subdir}"
    touch "${output_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
