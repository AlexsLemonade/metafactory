process GENERATE_METAPROGRAMS {
    tag "${meta.group_id}-k${meta.n_metaprograms}"
    label 'process_medium'
    label 'process_high_memory'
    label 'long_running'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/metafactory:a76461cf4574fb02'
            : 'community.wave.seqera.io/library/metafactory:8ef5094455987626'
    }

    input:
    tuple val(meta), path(cnmf_output_dirs), val(cnmf_run_ids)
    val options

    output:
    tuple val(meta), path(output_file), path(mp_export_file), path(shuffled_mp_export_file), emit: results
    tuple val(meta), path(metaprograms_meta_file), emit: metaprograms_meta
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

    // define a JSON file recording the options and cNMF results used to build this metaprogram set
    // the workflow compares this to the current run to decide whether this step can be skipped,
    // so the JSON is built here from the same values the workflow compares against
    // cnmf_run_ids identifies the cNMF run each library's results came from, so that metaprograms
    // built from an earlier cNMF run are not reused
    metaprograms_meta_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms-meta.json"
    metaprograms_meta_json = groovy.json.JsonOutput.prettyPrint(
        groovy.json.JsonOutput.toJson([n_metaprograms: meta.n_metaprograms, unique_ids: meta.unique_ids, cnmf_run_ids: cnmf_run_ids] + options)
    )
    template('generate-metaprograms.R')

    stub:
    output_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms.rds"
    mp_export_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms.tsv.gz"
    shuffled_mp_export_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_shuffled_metaprograms.tsv.gz"
    metaprograms_meta_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_metaprograms-meta.json"
    // kept on a single line so that the heredoc below keeps a common indentation to strip
    metaprograms_meta_json = groovy.json.JsonOutput.toJson([n_metaprograms: meta.n_metaprograms, unique_ids: meta.unique_ids, cnmf_run_ids: cnmf_run_ids] + options)
    """
    mkdir -p "${meta.metaprograms_publish_dir}"
    touch "${output_file}"
    touch "${mp_export_file}"
    touch "${shuffled_mp_export_file}"

    cat <<-'END_META' > "${metaprograms_meta_file}"
    ${metaprograms_meta_json}
    END_META

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
