process CALCULATE_K {
    tag "${meta.group_id}"

    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/calculate-k:a929af000fddb451'
            : 'community.wave.seqera.io/library/calculate-k:dabf9ebb82a4478a'
    }

    input:
    tuple val(meta), path(mp_metrics_files), path(mp_background_files), path(geneset_metrics_files), path(specificity_background_files), path(scores_files), path(background_scores_files)
    val options

    output:
    tuple val(meta), path(optimal_k_file), emit: optimal_k
    tuple val(meta), path(metaprogram_metrics_file), path(k_metrics_file), path(neff_background_file), path(specificity_background_file), path(cv_background_file), emit: report_metrics
    path "versions.yml", emit: versions, topic: versions

    script:
    // define input file strings for the R script, one file per value of k in each list
    mp_metrics_files_string = mp_metrics_files.join(',')
    geneset_metrics_files_string = geneset_metrics_files.join(',')
    mp_background_files_string = mp_background_files.join(',')
    specificity_background_files_string = specificity_background_files.join(',')
    scores_files_string = scores_files.join(',')
    background_scores_files_string = background_scores_files.join(',')

    // all output for this group is written to one directory named for the group, which is published
    // as the final results for the group rather than as a checkpoint
    output_dir = "${meta.group_id}"

    // the optimal value of k, written as a number so it can be read back as `n_metaprograms` and
    // used to pick out the metaprograms that are published as the final result for this group
    optimal_k_file = "${output_dir}/optimal-k.txt"

    // the tables below are only read by the report, so they are kept in their own directory,
    // separate from the optimal value of k and the final metaprograms
    reports_dir = "${output_dir}/reports"

    // tables used to build the report, holding the metrics for every value of k
    metaprogram_metrics_file = "${reports_dir}/all-k_metaprogram_metrics.tsv"
    k_metrics_file = "${reports_dir}/all-k_summary_metrics.tsv"

    // null distributions the observed metrics are compared against, gzipped because they hold one
    // row per permutation replicate
    neff_background_file = "${reports_dir}/all-k_background_eff_sample_size.tsv.gz"
    specificity_background_file = "${reports_dir}/all-k_background_geneset_specificity.tsv.gz"
    cv_background_file = "${reports_dir}/all-k_background_cell_score_cv.tsv.gz"

    template('calculate-optimal-k.R')

    stub:
    output_dir = "${meta.group_id}"
    reports_dir = "${output_dir}/reports"
    optimal_k_file = "${output_dir}/optimal-k.txt"
    metaprogram_metrics_file = "${reports_dir}/all-k_metaprogram_metrics.tsv"
    k_metrics_file = "${reports_dir}/all-k_summary_metrics.tsv"
    neff_background_file = "${reports_dir}/all-k_background_eff_sample_size.tsv.gz"
    specificity_background_file = "${reports_dir}/all-k_background_geneset_specificity.tsv.gz"
    cv_background_file = "${reports_dir}/all-k_background_cell_score_cv.tsv.gz"

    // the optimal value of k can only be found from real metrics, so the first metaprogram set
    // staged stands in for it here
    stub_k = [mp_metrics_files].flatten().first().name.tokenize('_')[0].replace('k-', '')
    """
    mkdir -p "${reports_dir}"

    echo "${stub_k}" > "${optimal_k_file}"
    touch "${metaprogram_metrics_file}"
    touch "${k_metrics_file}"
    touch "${neff_background_file}"
    touch "${specificity_background_file}"
    touch "${cv_background_file}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
