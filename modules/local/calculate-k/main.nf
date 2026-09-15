process CALCULATE_K {
    tag "${meta.group_id}"

    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container {
        workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
            ? 'oras://community.wave.seqera.io/library/calculate-k:a929af000fddb451'
            : 'community.wave.seqera.io/library/calculate-k:dabf9ebb82a4478a'
    }

    input:
    tuple val(meta), path(metaprograms_files), path(mp_metrics_files), path(mp_background_files), path(ora_results_files), path(geneset_metrics_files), path(specificity_background_files), path(scores_files), path(background_scores_files)
    val options

    output:
    tuple val(meta), path(optimal_k_file), emit: optimal_k
    tuple val(meta), path(metaprogram_metrics_file), path(k_metrics_file), path(neff_background_file), path(specificity_background_file), path(cv_background_file), emit: report_metrics
    tuple val(meta), path("${output_dir}/k-*"), emit: final_metaprograms
    path "versions.yml", emit: versions, topic: versions

    script:
    // define input file strings for the R script, one file per value of k in each list
    mp_metrics_files_string = mp_metrics_files.join(',')
    geneset_metrics_files_string = geneset_metrics_files.join(',')
    mp_background_files_string = mp_background_files.join(',')
    specificity_background_files_string = specificity_background_files.join(',')
    scores_files_string = scores_files.join(',')
    background_scores_files_string = background_scores_files.join(',')

    // the metaprograms and the ORA results are not read by the script, they are staged so that the
    // ones belonging to the optimal value of k can be copied into the output directory and
    // published as the final metaprograms for this group
    metaprograms_files_string = metaprograms_files.join(',')
    ora_results_files_string = ora_results_files.join(',')

    // all output for this group is written to one directory named for the group, which is published
    // as the final results for the group rather than as a checkpoint
    output_dir = "${meta.group_id}"

    // the optimal value of k, written as a number so it can be read back as `n_metaprograms`
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
    // staged stands in for it here and gives the final metaprogram files their expected names
    stub_k = [metaprograms_files].flatten().first().name.tokenize('_')[0].replace('k-', '')
    """
    mkdir -p "${reports_dir}"

    echo "${stub_k}" > "${optimal_k_file}"
    touch "${metaprogram_metrics_file}"
    touch "${k_metrics_file}"
    touch "${neff_background_file}"
    touch "${specificity_background_file}"
    touch "${cv_background_file}"

    touch "${output_dir}/k-${stub_k}_metaprograms.rds"
    touch "${output_dir}/k-${stub_k}_mp_metrics.tsv"
    touch "${output_dir}/k-${stub_k}_ora_results.tsv"
    touch "${output_dir}/k-${stub_k}_geneset_metrics.tsv"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        stub: x.y.z
    END_VERSIONS
    """
}
