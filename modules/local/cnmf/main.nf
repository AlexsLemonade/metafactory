process CNMF {
    tag "${meta.unique_id}"
    label 'process_high'
    label 'long_running'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/cnmf:35466eeefa6c2ce7'
            : 'community.wave.seqera.io/library/cnmf:eca7fd9ac02ef604'
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

    # one consensus spectra file per value of k, matching the cnmf.py SPECTRA_GLOB
    for k in \$(seq ${options.cnmf_k_lower} ${options.cnmf_k_step_size} ${options.cnmf_k_upper}); do
        touch "${meta.unique_id}_cnmf/${meta.unique_id}_cnmf.gene_spectra_score.k_\${k}.dt_0_1.txt"
    done

    cat <<-END_META > "${meta.unique_id}_cnmf/cnmf-meta.json"
    {
      "cnmf_k_lower": ${options.cnmf_k_lower},
      "cnmf_k_upper": ${options.cnmf_k_upper},
      "cnmf_k_step_size": ${options.cnmf_k_step_size},
      "celltype_annotation_column": "${options.celltype_annotation_column}",
      "analysis_celltypes": "${options.analysis_celltypes}",
      "seed": ${options.seed}
    }
    END_META

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
