process CNMF {
    tag "${unique_id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/cnmf:464b3c8962877d9d'
            : 'community.wave.seqera.io/library/cnmf:83812d80a4b86f24'
    }

    input:
    tuple val(unique_id), val(group_id), path(h5ad_file)
    val cnmf_k_lower
    val cnmf_k_upper
    val cnmf_k_step_size
    val celltype_annotation_column
    val analysis_celltypes
    val seed

    output:
    // switch the order of group_id and unique_id in the output tuple so we can group results easily
    tuple val(group_id), val(unique_id), path("${unique_id}_cnmf"), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    template('cnmf.py')

    stub:
    """
    mkdir -p "${unique_id}_cnmf"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
