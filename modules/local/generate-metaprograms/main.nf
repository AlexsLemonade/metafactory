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
    tuple val(meta), path(output_file), path(mp_export_file), emit: results
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

    // define output file in the publish directory for this metaprogram set
    output_file = "${meta.metaprograms_publish_dir}/k-${n_metaprograms}_metaprograms.rds"

    // define a python readable export of the metaprogram gene weights, written alongside the RDS file
    mp_export_file = "${meta.metaprograms_publish_dir}/k-${n_metaprograms}_metaprograms.tsv.gz"

    // parse the range of k values to test into a list of integers
    def n = (cnmf_k_upper - cnmf_k_lower).intdiv(cnmf_k_step_size)
    def cnmf_k_range_list = (0..n).collect { cnmf_k_lower + it * cnmf_k_step_size }
    cnmf_k_range = cnmf_k_range_list.join(',')

    template('generate-metaprograms.R')

    stub:
    output_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms.rds"
    mp_export_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms.tsv.gz"
    """
    mkdir -p "${meta.metaprograms_publish_dir}"
    touch "${output_file}"
    touch "${mp_export_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
