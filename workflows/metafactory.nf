/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap                             } from 'plugin/nf-schema'
include { softwareVersionsToYAML                       } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText                       } from '../subworkflows/local/utils_nfcore_metafactory_pipeline'
include { CNMF                                         } from '../modules/local/cnmf/main'
include { GENERATE_METAPROGRAMS                        } from '../modules/local/generate-metaprograms/main'
include { CALCULATE_METRICS_METAPROGRAMS               } from '../modules/local/calculate-metrics/metaprograms/main'
include { CALCULATE_METRICS_GENESETS                   } from '../modules/local/calculate-metrics/genesets/main'
include { SCORE_METAPROGRAMS                           } from '../modules/local/score-metaprograms/main'
include { SCORE_BACKGROUND                             } from '../modules/local/score-background/main'
include { COMBINE_SCORES as COMBINE_METAPROGRAM_SCORES ; COMBINE_SCORES as COMBINE_BACKGROUND_SCORES } from '../modules/local/combine-scores/main'
include { CALCULATE_K                                  } from '../modules/local/calculate-k/main'
include { PUBLISH_METAPROGRAMS                         } from '../modules/local/publish-metaprograms/main'

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

    // parse the comma separated list of k values to test into a list of integers
    def n_metaprograms_list = params.n_metaprograms
        .split(',')
        *.trim()
        *.toInteger()

    // the optimal value of k is chosen from the elbow of the coherence curve, which is not defined
    // with fewer than four values of k
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
    ch_samplesheet = ch_samplesheet.map { unique_id, group_id, h5ad_file ->
        def meta = [unique_id: unique_id, group_id: group_id]
        [meta, file(h5ad_file)]
    }


    //
    // MODULE: Run cNMF on each sample
    //
    CNMF(
        ch_samplesheet,
        [
            cnmf_k_lower: params.cnmf_k_lower,
            cnmf_k_upper: params.cnmf_k_upper,
            cnmf_k_step_size: params.cnmf_k_step_size,
            celltype_annotation_column: params.celltype_annotation_column,
            analysis_celltypes: params.analysis_celltypes,
            seed: params.seed,
        ],
    )

    //
    // MODULE: Generate metaprograms for each group of samples across all values of n_metaprograms
    //

    // group cNMF results from all unique_ids that share the same group_id
    def ch_cnmf_by_group = CNMF.out.results
        .map { meta, cnmf_output ->
            [meta.group_id, meta.unique_id, cnmf_output]
        }
        .groupTuple(by: 0)

    // labels used to identify the spectra filtering settings the metaprograms were built with
    def filter_label = params.metaprograms_filter_spectra ? 'filtered' : 'unfiltered'
    def orphan_label = params.metaprograms_filter_spectra ? "_${params.metaprograms_orphan_cutoff}" : ''

    // build one task per group_id/n_metaprograms combination
    // metaprograms_publish_dir is the subdirectory that all output for a metaprogram set is
    // written to, and is passed through meta so that every module writes to the same place
    def ch_metaprogram_input = ch_cnmf_by_group
        .combine(channel.fromList(n_metaprograms_list))
        .map { group_id, unique_ids, cnmf_output_dirs, n_metaprograms ->
            def meta = [
                group_id: group_id,
                n_metaprograms: n_metaprograms,
                unique_ids: unique_ids,
                metaprograms_publish_dir: "${group_id}/k-${n_metaprograms}_${filter_label}${orphan_label}".toString(),
            ]
            [meta, cnmf_output_dirs]
        }

    GENERATE_METAPROGRAMS(
        ch_metaprogram_input,
        [
            n_top_genes: params.n_top_genes,
            filter_spectra: params.metaprograms_filter_spectra,
            orphan_cutoff: params.metaprograms_orphan_cutoff,
            cnmf_k_lower: params.cnmf_k_lower,
            cnmf_k_upper: params.cnmf_k_upper,
            cnmf_k_step_size: params.cnmf_k_step_size,
            seed: params.seed,
            nreps: params.nreps,
        ],
    )

    //
    // MODULE: Calculate metrics for each set of metaprograms
    //

    // only the RDS object is needed to calculate metrics, so the python readable exports are
    // dropped here and left in the generate metaprograms channel for their other consumers
    def ch_metaprograms_rds = GENERATE_METAPROGRAMS.out.results.map { meta, metaprograms_file, _metaprograms_export_file, _shuffled_metaprograms_file ->
        [meta, metaprograms_file]
    }

    CALCULATE_METRICS_METAPROGRAMS(
        ch_metaprograms_rds,
        [
            seed: params.seed,
            nreps: params.nreps,
        ],
    )

    //
    // MODULE: Annotate each set of metaprograms with gene sets using ORA and calculate gene set metrics
    //

    // the gene sets are the same for every metaprogram set, so they are staged as a value channel
    // that every task can reuse. this has to be a `path` input on the process rather than an entry
    // in the options map, so that the file is staged into the task work directory and is readable
    // on executors that do not share a filesystem with the launch environment
    def ch_term2gene = channel.value(file(params.msigdb_gene_sets))

    CALCULATE_METRICS_GENESETS(
        ch_metaprograms_rds,
        ch_term2gene,
        [
            seed: params.seed,
            nreps: params.nreps,
        ],
    )

    //
    // MODULE: Score every library in a group against each set of metaprograms generated for that group
    //

    // channel of [group_id, unique_id, h5ad_file] to combine with each group's metaprograms
    // pull out the group id from meta so we can easily combine with the metaprograms channel
    def ch_h5ad_by_group = ch_samplesheet.map { meta, h5ad_file ->
        [meta.group_id, meta.unique_id, h5ad_file]
    }

    // build one task per metaprogram set/library combination
    // the RDS file is dropped here and left in the generate metaprograms channel for its other
    // consumers; only the python readable exports are needed for scoring
    def ch_metaprograms_by_library = GENERATE_METAPROGRAMS.out.results
        .map { meta, _metaprograms_file, metaprograms_export_file, shuffled_metaprograms_file ->
            [meta.group_id, meta, metaprograms_export_file, shuffled_metaprograms_file]
        }
        .combine(ch_h5ad_by_group, by: 0)
        .map { group_id, metaprogram_meta, metaprograms_export_file, shuffled_metaprograms_file, unique_id, h5ad_file ->
            def meta = [
                unique_id: unique_id,
                group_id: group_id,
                n_metaprograms: metaprogram_meta.n_metaprograms,
                metaprograms_publish_dir: metaprogram_meta.metaprograms_publish_dir,
            ]
            [meta, metaprograms_export_file, shuffled_metaprograms_file, h5ad_file]
        }

    // the shuffled metaprograms are only used to build the background distribution
    def ch_score_input = ch_metaprograms_by_library.map { meta, metaprograms_export_file, _shuffled_metaprograms_file, h5ad_file ->
        [meta, metaprograms_export_file, h5ad_file]
    }

    SCORE_METAPROGRAMS(
        ch_score_input,
        [
            celltype_annotation_column: params.celltype_annotation_column,
            analysis_celltypes: params.analysis_celltypes,
            n_top_genes: params.n_top_genes,
            seed: params.seed,
        ],
    )

    // combine the metaprogram scores for each library into a single channel for downstream processing
    def metaprograms_score_ch = SCORE_METAPROGRAMS.out.results
        .map { meta, scores_file ->
            def updated_meta = [
                group_id: meta.group_id,
                n_metaprograms: meta.n_metaprograms,
                score_type: 'metaprogram_scores',
                metaprograms_publish_dir: meta.metaprograms_publish_dir,
            ]
            [updated_meta, scores_file]
        }
        .groupTuple()

    COMBINE_METAPROGRAM_SCORES(metaprograms_score_ch)

    //
    // MODULE: Calculate a background score distribution from shuffled metaprograms for each library
    //
    SCORE_BACKGROUND(
        ch_metaprograms_by_library,
        [
            celltype_annotation_column: params.celltype_annotation_column,
            analysis_celltypes: params.analysis_celltypes,
            seed: params.seed,
        ],
    )

    // combine all background scores
    def background_score_ch = SCORE_BACKGROUND.out.results
        .map { meta, background_stats_file ->
            def updated_meta = [
                group_id: meta.group_id,
                n_metaprograms: meta.n_metaprograms,
                score_type: 'background_score_stats',
                metaprograms_publish_dir: meta.metaprograms_publish_dir,
            ]
            [updated_meta, background_stats_file]
        }
        .groupTuple()

    COMBINE_BACKGROUND_SCORES(background_score_ch)

    //
    // MODULE: Compare every metaprogram set generated for a group and pick the optimal value of k
    //

    // this process runs once per group rather than once per metaprogram set, so the output for
    // every value of k is grouped by group_id here
    def ch_metrics_by_group = CALCULATE_METRICS_METAPROGRAMS.out.metaprogram_metrics
        .map { meta, metrics_file, background_file ->
            [meta.group_id, metrics_file, background_file]
        }
        .groupTuple()

    // the ORA results are not used to compare values of k, so only the gene set metrics and their
    // background are grouped here
    def ch_geneset_metrics_by_group = CALCULATE_METRICS_GENESETS.out.ora_metrics
        .map { meta, _ora_results_file, metrics_file, background_file ->
            [meta.group_id, metrics_file, background_file]
        }
        .groupTuple()

    // generate channels with all scores and background scores grouped by group_id
    def ch_scores_by_group = COMBINE_METAPROGRAM_SCORES.out.results
        .map { meta, scores_file -> [meta.group_id, scores_file] }
        .groupTuple()

    def ch_background_scores_by_group = COMBINE_BACKGROUND_SCORES.out.results
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
    def ch_optimal_k = CALCULATE_K.out.optimal_k.map { meta, optimal_k_file ->
        [[meta.group_id, optimal_k_file.text.trim().toInteger()]]
    }

    // pull out files from each of the calculation steps for later joining and publishing
    // all are keyed on a [group_id, n_metaprograms] tuple, so that joining them against the
    // optimal value of k keeps only the metaprogram set chosen for each group and drops the rest
    def metaprograms_rds_ch = GENERATE_METAPROGRAMS.out.results.map { meta, metaprograms_rds_file, _metaprograms_export_file, _shuffled_metaprograms_file ->
        [[meta.group_id, meta.n_metaprograms], metaprograms_rds_file]
    }

    def metaprogram_metrics_ch = CALCULATE_METRICS_METAPROGRAMS.out.metaprogram_metrics.map { meta, metaprogram_metrics_file, _background_file ->
        [[meta.group_id, meta.n_metaprograms], metaprogram_metrics_file]
    }

    def geneset_metrics_ch = CALCULATE_METRICS_GENESETS.out.ora_metrics.map { meta, ora_results_file, geneset_metrics_file, _background_file ->
        [[meta.group_id, meta.n_metaprograms], ora_results_file, geneset_metrics_file]
    }

    def cell_scores_ch = COMBINE_METAPROGRAM_SCORES.out.results.map { meta, cell_scores_file ->
        [[meta.group_id, meta.n_metaprograms], cell_scores_file]
    }

    // joining on the key drops every metaprogram set except the one chosen for each group
    def publish_ch = ch_optimal_k
        .join(metaprograms_rds_ch)
        .join(metaprogram_metrics_ch)
        .join(geneset_metrics_ch)
        .join(cell_scores_ch)
        .map { key, metaprograms_rds_file, metaprogram_metrics_file, ora_results_file, geneset_metrics_file, cell_scores_file ->
            def meta = [group_id: key[0], optimal_k: key[1]]
            // make sure meta actually defines group id and key for use in the process
            [meta, metaprograms_rds_file, metaprogram_metrics_file, ora_results_file, geneset_metrics_file, cell_scores_file]
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
            name: 'metafactory_software_' + 'versions.yml',
            sort: true,
            newLine: true,
        )

    emit:
    optimal_k = ch_optimal_k
    versions  = ch_collated_versions
}
