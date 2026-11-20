/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 */
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_metafactory_pipeline'
include { CNMF                   } from '../modules/local/cnmf/main'
include { GENERATE_METAPROGRAMS  } from '../modules/local/generate-metaprograms/main'
include { CALCULATE_METRICS      } from '../subworkflows/local/calculate_metrics/main'
include { CALCULATE_K            } from '../modules/local/calculate-k/main'
include { PUBLISH_METAPROGRAMS   } from '../modules/local/publish-metaprograms/main'
include { CALCULATE_SCORES       } from '../subworkflows/local/calculate_scores/main'
include { GENERATE_REPORTS       } from '../subworkflows/local/generate_reports/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 */

workflow METAFACTORY {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    outdir

    main:

    def ch_versions = channel.empty()

    // parse the comma separated list of k values (numbers of metaprograms) to test into a list of integers
    def n_metaprograms_list = params.n_metaprograms
        .split(',')
        *.trim()
        *.toInteger()

    // the optimal value of k is chosen from the elbow of the coherence curve, which is not defined
    // with fewer than four k values (numbers of metaprograms)
    // the schema enforces this as well, so this is here to catch runs that skip parameter
    // validation, and to fail before any task is submitted rather than in the last process
    if (n_metaprograms_list.size() < 4) {
        error(
            "At least 4 values of --n_metaprograms are required to choose the optimal value of k, but ${n_metaprograms_list.size()} were provided: ${params.n_metaprograms}"
        )
    }

    //
    // Create channel samplesheet of [meta, file(h5ad_file)]
    //
    // only libraries whose group_id is in the comma separated list of --group_id are kept,
    // unless --group_id is All, in which case every library is kept
    def run_all_groups = params.group_id.trim().equalsIgnoreCase('all')
    def group_id_list = params.group_id.split(',')*.trim()

    ch_samplesheet = ch_samplesheet
        .filter { _unique_id, group_id, _h5ad_file ->
            run_all_groups || group_id in group_id_list
        }
        .map { unique_id, group_id, h5ad_file ->
            def meta = [unique_id: unique_id, group_id: group_id]
            [meta, file(h5ad_file)]
        }


    //
    // MODULE: Run cNMF on each library
    //

    // these options are passed to cNMF and recorded in the cnmf-meta.json file of each checkpoint
    def cnmf_options = [
        cnmf_k_lower: params.cnmf_k_lower,
        cnmf_k_upper: params.cnmf_k_upper,
        cnmf_k_step_size: params.cnmf_k_step_size,
        celltype_annotation_column: params.celltype_annotation_column,
        analysis_celltypes: params.analysis_celltypes,
        seed: params.seed,
    ]

    // cNMF is skipped for any library that already has a checkpoint created with the same options,
    // unless --repeat_cnmf is set, in which case cNMF is run for every library
    // values are compared as strings so that numbers read from JSON match numbers set in params
    // the strict syntax parser passes command line values as strings, so repeat_cnmf may be "true"
    // or "false" rather than a boolean and is converted here
    def repeat_cnmf = params.repeat_cnmf.toString().toBoolean()
    def ch_cnmf_input = ch_samplesheet.branch { meta, _h5ad_file ->
        skip_cnmf: !repeat_cnmf && checkpointMatches(file("${outdir}/checkpoints/cnmf/${meta.unique_id}_cnmf/cnmf-meta.json"), cnmf_options)
        run_cnmf: true
    }

    CNMF(
        ch_cnmf_input.run_cnmf,
        cnmf_options,
    )

    // skipped libraries use the existing checkpoint directory, matching the output of the CNMF process
    def ch_cnmf_skipped = ch_cnmf_input.skip_cnmf.map { meta, _h5ad_file ->
        [meta, file("${outdir}/checkpoints/cnmf/${meta.unique_id}_cnmf")]
    }

    // each result is tagged with the cnmf_run_id from its cnmf-meta.json, which is new every time
    // cNMF runs, so that metaprograms built from an earlier cNMF run for any library are not reused
    def ch_cnmf_results = CNMF.out.results
        .mix(ch_cnmf_skipped)
        .map { meta, cnmf_output -> [meta, cnmf_output, readCheckpointMeta(cnmf_output.resolve('cnmf-meta.json')).cnmf_run_id] }

    //
    // MODULE: Generate metaprograms for each group of libraries across all values of n_metaprograms
    //

    // group cNMF results from all unique_ids that share the same group_id
    def ch_cnmf_by_group = ch_cnmf_results
        .map { meta, cnmf_output, cnmf_run_id ->
            [meta.group_id, meta.unique_id, cnmf_output, cnmf_run_id]
        }
        .groupTuple(by: 0)
        // groupTuple collects results in the order the cNMF tasks finish, which changes between runs
        // the input order sets the spectra order, and with it the metaprogram assignment and the
        // permutations, so results are sorted by unique_id to give the same metaprograms every run
        .map { group_id, unique_ids, cnmf_output_dirs, cnmf_run_ids ->
            def sorted_results = [unique_ids, cnmf_output_dirs, cnmf_run_ids].transpose().sort { result -> result[0] }
            [group_id] + sorted_results.transpose()
        }

    // labels used to identify the spectra filtering settings the metaprograms were built with
    def filter_label = params.metaprograms_filter_spectra ? 'filtered' : 'unfiltered'
    def orphan_label = params.metaprograms_filter_spectra ? "_${params.metaprograms_orphan_cutoff}" : ''

    // build one task per group_id/n_metaprograms combination
    // metaprograms_publish_dir is the subdirectory that all output for a metaprogram set is
    // written to, and is passed through meta so that every module writes to the same place
    def ch_metaprogram_input = ch_cnmf_by_group
        .combine(channel.fromList(n_metaprograms_list))
        .map { group_id, unique_ids, cnmf_output_dirs, cnmf_run_ids, n_metaprograms ->
            def meta = [
                group_id: group_id,
                n_metaprograms: n_metaprograms,
                unique_ids: unique_ids,
                metaprograms_publish_dir: "${group_id}/k-${n_metaprograms}_${filter_label}${orphan_label}".toString(),
            ]
            [meta, cnmf_output_dirs, cnmf_run_ids]
        }

    // these options are passed to the generate metaprograms module and recorded, along with
    // n_metaprograms, unique_ids and cnmf_run_ids, in the metaprograms-meta.json file of each checkpoint
    // the cell type options are not used to build metaprograms, but are recorded so that
    // metaprograms built from cNMF results for a different set of cells are not reused
    def metaprogram_options = [
        n_top_genes: params.n_top_genes,
        filter_spectra: params.metaprograms_filter_spectra,
        orphan_cutoff: params.metaprograms_orphan_cutoff,
        cnmf_k_lower: params.cnmf_k_lower,
        cnmf_k_upper: params.cnmf_k_upper,
        cnmf_k_step_size: params.cnmf_k_step_size,
        celltype_annotation_column: params.celltype_annotation_column,
        analysis_celltypes: params.analysis_celltypes,
        seed: params.seed,
        nreps: params.nreps,
    ]

    // generating metaprograms is skipped for any metaprogram set that already has a complete
    // checkpoint created with the same options and libraries, from the same cNMF run for every
    // library in the group
    // cNMF results created before run IDs were recorded have no cnmf_run_id, which is recorded as
    // null, so metaprograms built from them are reused only until cNMF runs again
    // --repeat_metaprograms runs this step for every metaprogram set
    // values are compared as strings, as for cNMF above
    def repeat_metaprograms = params.repeat_metaprograms.toString().toBoolean()
    // the checkpoint files are listed in the same order as the results output of the
    // GENERATE_METAPROGRAMS process, so skipped sets can be passed on in their place
    def ch_metaprograms_branch = ch_metaprogram_input
        .map { meta, cnmf_output_dirs, cnmf_run_ids ->
            def checkpoint_prefix = "${outdir}/checkpoints/metaprograms/${meta.metaprograms_publish_dir}/k-${meta.n_metaprograms}"
            def checkpoint_files = ['metaprograms.rds', 'metaprograms.tsv.gz', 'shuffled_metaprograms.tsv.gz']
                .collect { suffix -> file("${checkpoint_prefix}_${suffix}") }
            def expected_meta = [n_metaprograms: meta.n_metaprograms, unique_ids: meta.unique_ids, cnmf_run_ids: cnmf_run_ids] + metaprogram_options
            def use_checkpoint = !repeat_metaprograms &&
                checkpoint_files.every { checkpoint_file -> checkpoint_file.exists() } &&
                checkpointMatches(file("${checkpoint_prefix}_metaprograms-meta.json"), expected_meta)
            [meta, cnmf_output_dirs, cnmf_run_ids, checkpoint_files, use_checkpoint]
        }
        .branch { _meta, _cnmf_output_dirs, _cnmf_run_ids, _checkpoint_files, use_checkpoint ->
            skip_metaprograms: use_checkpoint
            run_metaprograms: true
        }

    GENERATE_METAPROGRAMS(
        ch_metaprograms_branch.run_metaprograms.map { meta, cnmf_output_dirs, cnmf_run_ids, _checkpoint_files, _use_checkpoint -> [meta, cnmf_output_dirs, cnmf_run_ids] },
        metaprogram_options,
    )

    def ch_metaprograms_skipped = ch_metaprograms_branch.skip_metaprograms.map { meta, _cnmf_output_dirs, _cnmf_run_ids, checkpoint_files, _use_checkpoint ->
        [meta] + checkpoint_files
    }

    def ch_metaprograms_results = GENERATE_METAPROGRAMS.out.results.mix(ch_metaprograms_skipped)

    //
    // SUBWORKFLOW: Calculate metaprogram and gene set metrics for each set of metaprograms
    //

    // only the RDS object is needed to calculate metrics, so the python readable exports are
    // dropped here and left in the generate metaprograms channel for their other consumers
    def ch_metaprograms_rds = ch_metaprograms_results.map { meta, metaprograms_file, _metaprograms_export_file, _shuffled_metaprograms_file ->
        [meta, metaprograms_file]
    }

    // the gene sets are the same for every metaprogram set, so they are staged as a value channel
    // that every task can reuse. this has to be a `path` input on the process rather than an entry
    // in the options map, so that the file is staged into the task work directory and is readable
    // on executors that do not share a filesystem with the launch environment
    def ch_term2gene = channel.value(file(params.msigdb_gene_sets))

    CALCULATE_METRICS(
        ch_metaprograms_rds,
        ch_term2gene,
        channel.value(
            [
                seed: params.seed,
                nreps: params.nreps,
            ]
        ),
    )

    //
    // SUBWORKFLOW: Score every library in a group against each set of metaprograms and build a score background distribution
    //
    CALCULATE_SCORES(
        ch_samplesheet,
        ch_metaprograms_results,
        channel.value(
            [
                celltype_annotation_column: params.celltype_annotation_column,
                analysis_celltypes: params.analysis_celltypes,
                n_top_genes: params.n_top_genes,
                seed: params.seed,
            ]
        ),
    )

    //
    // MODULE: Compare every metaprogram set generated for a group and pick the optimal value of k
    //

    // this process runs once per group rather than once per metaprogram set, so the output for
    // every metaprogram set is grouped by group_id here
    def ch_metrics_by_group = CALCULATE_METRICS.out.metaprogram_metrics
        .map { meta, metrics_file, background_file ->
            [meta.group_id, metrics_file, background_file]
        }
        .groupTuple()

    // the ORA results are not used to compare metaprogram sets, so only the gene set metrics and their
    // metric background are grouped here
    def ch_geneset_metrics_by_group = CALCULATE_METRICS.out.geneset_metrics
        .map { meta, _ora_results_file, metrics_file, background_file ->
            [meta.group_id, metrics_file, background_file]
        }
        .groupTuple()

    // generate channels with all cell scores and score background stats grouped by group_id
    def ch_scores_by_group = CALCULATE_SCORES.out.metaprogram_scores
        .map { meta, scores_file -> [meta.group_id, scores_file] }
        .groupTuple()

    def ch_background_scores_by_group = CALCULATE_SCORES.out.background_scores
        .map { meta, background_stats_file -> [meta.group_id, background_stats_file] }
        .groupTuple()

    // joining on group_id lines up every file list for a group into a single task
    def ch_calculate_k_input = ch_metrics_by_group
        .join(ch_geneset_metrics_by_group)
        .join(ch_scores_by_group)
        .join(ch_background_scores_by_group)
        .map { group_id, mp_metrics_files, mp_background_files, geneset_metrics_files, specificity_background_files, scores_files, background_scores_files ->
            def meta = [group_id: group_id]
            [meta, mp_metrics_files, mp_background_files, geneset_metrics_files, specificity_background_files, scores_files, background_scores_files]
        }

    CALCULATE_K(
        ch_calculate_k_input,
        [nreps: params.nreps],
    )

    // the optimal value of k is written to a file so that it survives as a process output, and is
    // read back here as the number of metaprograms to use for the report and for determining which files to publish to results
    // we need group id and optimal k for joining as the first element of the tuple
    // a file without a number in it means no optimal k could be chosen for the group, so fail
    // with a clear message rather than a failed integer conversion
    def ch_optimal_k = CALCULATE_K.out.optimal_k.map { meta, optimal_k_file ->
        def optimal_k = optimal_k_file.text.trim()
        if (!optimal_k.isInteger()) {
            def problem = optimal_k ? "contains '${optimal_k}' instead of a single number" : "is empty"
            error("Cannot find the optimal value of k for group ${meta.group_id}: ${optimal_k_file.name} ${problem}")
        }
        [[meta.group_id, optimal_k.toInteger()]]
    }

    // pull out files from each of the calculation steps for later joining, reporting and publishing
    // all are keyed on a [group_id, n_metaprograms] tuple, so that joining them against the
    // optimal value of k keeps only the metaprogram set chosen for each group and drops the rest
    def metaprograms_rds_ch = ch_metaprograms_results.map { meta, metaprograms_rds_file, _metaprograms_export_file, _shuffled_metaprograms_file ->
        [[meta.group_id, meta.n_metaprograms], metaprograms_rds_file]
    }

    def metaprogram_metrics_ch = CALCULATE_METRICS.out.metaprogram_metrics.map { meta, metaprogram_metrics_file, _background_file ->
        [[meta.group_id, meta.n_metaprograms], metaprogram_metrics_file]
    }

    def geneset_metrics_ch = CALCULATE_METRICS.out.geneset_metrics.map { meta, ora_results_file, geneset_metrics_file, _background_file ->
        [[meta.group_id, meta.n_metaprograms], ora_results_file, geneset_metrics_file]
    }

    def cell_scores_ch = CALCULATE_SCORES.out.metaprogram_scores.map { meta, cell_scores_file ->
        [[meta.group_id, meta.n_metaprograms], cell_scores_file]
    }

    // joining on the key drops every metaprogram set except the one chosen for each group
    // shared by the individual report and the publish module, which both only need the files for
    // the metaprogram set chosen as the final result for each group
    def ch_optimal_metaprogram_set = ch_optimal_k
        .join(metaprograms_rds_ch)
        .join(metaprogram_metrics_ch)
        .join(geneset_metrics_ch)
        .join(cell_scores_ch)
        .map { key, metaprograms_rds_file, metaprogram_metrics_file, ora_results_file, geneset_metrics_file, cell_scores_file ->
            // make sure meta actually defines group id and key for use in the process
            def meta = [group_id: key[0], optimal_k: key[1]]
            [meta, metaprograms_rds_file, metaprogram_metrics_file, ora_results_file, geneset_metrics_file, cell_scores_file]
        }

    //
    // MODULE: Render a set of reports
    // Metrics report for comparing every metaprogram set that was tested for a group
    // Individual report evaluating the metaprogram set chosen as the optimal value of k
    //

    GENERATE_REPORTS(
        CALCULATE_K.out.optimal_k,
        CALCULATE_K.out.report_metrics,
        ch_optimal_metaprogram_set,
        channel.value(
            [
                n_top_genes: params.n_top_genes,
                seed: params.seed,
            ]
        ),
    )

    // bundle the same files into a single list for the publish module, which copies them as is
    def publish_ch = ch_optimal_metaprogram_set.map { meta, metaprograms_rds_file, metaprogram_metrics_file, ora_results_file, geneset_metrics_file, cell_scores_file ->
        [meta, [metaprograms_rds_file, metaprogram_metrics_file, ora_results_file, geneset_metrics_file, cell_scores_file]]
    }

    PUBLISH_METAPROGRAMS(publish_ch)

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'metafactory_software_'  + 'versions.yml',
            sort: true,
            newLine: true,
        )

    emit:
    optimal_k = ch_optimal_k
    versions  = ch_collated_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 */

// returns the contents of the JSON file recording the options a checkpoint was created with,
// or an empty map if the file does not exist
def readCheckpointMeta(meta_file) {
    return meta_file.exists() ? new groovy.json.JsonSlurper().parseText(meta_file.text) : [:]
}

// returns true if the JSON file recording the options a checkpoint was created with exists and
// contains every expected key with a matching value
// values are compared as strings so that numbers read from JSON match numbers set in params
def checkpointMatches(meta_file, expected) {
    def recorded = readCheckpointMeta(meta_file)
    return expected.every { key, value -> recorded.containsKey(key) && recorded[key].toString() == value.toString() }
}
