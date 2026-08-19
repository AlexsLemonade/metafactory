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
