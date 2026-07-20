process CNMF {
    tag "${unique_id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/cnmf:2bfd10b26312d44a'
            : 'community.wave.seqera.io/library/cnmf:3a21b0c95745bea0'
    }

    input:
    tuple val(unique_id), val(group_id), path(h5ad_file)
    val cnmf_k_lower
    val cnmf_k_upper
    val cnmf_k_step_size
    val annotations_column
    val celltype_value

    output:
    tuple val(unique_id), val(group_id), path("${unique_id}/"), emit: results
    path "versions.yml", emit: versions

    script:
    template('cnmf.py')

    stub:
    """
    mkdir -p "${unique_id}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //')
        anndata: \$(python -c "import anndata; print(anndata.__version__)")
        cnmf: \$(python -c "import importlib.metadata; print(importlib.metadata.version('cnmf'))")
    END_VERSIONS
    """
}
