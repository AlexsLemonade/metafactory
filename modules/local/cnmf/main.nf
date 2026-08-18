process CNMF {
    tag "${meta.unique_id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/cnmf:464b3c8962877d9d'
            : 'community.wave.seqera.io/library/cnmf:83812d80a4b86f24'
    }

    input:
    tuple val(meta), path(h5ad_file)
    val options

    output:
    tuple val(meta), path("${meta.unique_id}_cnmf"), emit: results
    path "versions.yml", emit: versions, topic: versions

    script:
    // define options
    cnmf_k_lower = options.cnmf_k_lower
    cnmf_k_upper = options.cnmf_k_upper
    cnmf_k_step_size = options.cnmf_k_step_size
    celltype_annotation_column = options.celltype_annotation_column
    analysis_celltypes = options.analysis_celltypes
    seed = options.seed
    unique_id = meta.unique_id

    template('cnmf.py')

    stub:
    """
    mkdir -p "${meta.unique_id}_cnmf"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
