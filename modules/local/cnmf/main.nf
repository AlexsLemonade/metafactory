process CNMF {
    tag "${unique_id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/cnmf:44abf3ada957f74e'
            : 'community.wave.seqera.io/library/cnmf:7238a13d519b57af'
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
    def annotations_col_arg = annotations_column ? "--annotations_column '${annotations_column}'" : ''
    def celltype_val_arg = celltype_value ? "--celltype_value '${celltype_value}'" : ''
    """
    cnmf.py \
        --h5ad_file "${h5ad_file}" \
        --unique_id "${unique_id}" \
        --output_dir . \
        --k_components_lower ${cnmf_k_lower} \
        --k_components_upper ${cnmf_k_upper} \
        --k_step_size ${cnmf_k_step_size} \
        --jobs ${task.cpus} \
        ${annotations_col_arg} \
        ${celltype_val_arg}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //')
        anndata: \$(python -c "import anndata; print(anndata.__version__)")
        cnmf: \$(python -c "import importlib.metadata; print(importlib.metadata.version('cnmf'))")
    END_VERSIONS
    """

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
