process CALCULATE_METRICS_GENESETS {
    tag "${meta.group_id}-k${meta.n_metaprograms}"

    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/geneset-metrics:365eafac83465b3e'
            : 'community.wave.seqera.io/library/geneset-metrics:ad03383e372795db'
    }

    input:
    tuple val(meta), path(metaprograms_file)
    path term2gene_file
    val options

    output:
    tuple val(meta), path(ora_results_file), path(metrics_file), path(background_file), emit: ora_metrics
    path "versions.yml", emit: versions, topic: versions

    script:
    // full set of ORA results
    ora_results_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_ora_results.tsv"

    // ORA derived metrics, one row per metaprogram
    metrics_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_geneset_metrics.tsv"

    // the background gene set stats with one row per metaprogram per replicate
    background_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_background_specificity.tsv.gz"

    template('calculate-geneset-metrics.R')

    stub:
    ora_results_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_ora_results.tsv"
    metrics_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_geneset_metrics.tsv"
    background_file = "${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}_background_specificity.tsv.gz"
    """
    mkdir -p "${meta.metaprograms_publish_dir}"
    touch "${ora_results_file}"
    touch "${metrics_file}"
    touch "${background_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
