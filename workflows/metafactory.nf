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
include { SCORE_METAPROGRAMS     } from '../modules/local/score-metaprograms/main'
include { SCORE_BACKGROUND       } from '../modules/local/score-background/main'
include { COMBINE_SCORES         } from '../modules/local/combine-scores/main'

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

    // parse the comma separated list of k values to test into a list of integers
    def n_metaprograms_list = params.n_metaprograms
        .split(',')
        *.trim()
        *.toInteger()

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

    //
    // MODULE: Combine the per library scores for each metaprogram set into a single table
    //

    // drop unique_id from meta and group the per library scores by metaprogram set, tagging each
    // group with the type of score it holds (either metaprogram or background scores)
    def ch_combine_input = SCORE_METAPROGRAMS.out.results
        .map { meta, scores_file ->
            def updated_meta = [
                group_id: meta.group_id,
                n_metaprograms: meta.n_metaprograms,
                score_type: 'metaprogram_scores',
                metaprograms_publish_dir: meta.metaprograms_publish_dir,
            ]
            [updated_meta, scores_file]
        }
        .mix(
            SCORE_BACKGROUND.out.results.map { meta, background_stats_file ->
                def updated_meta = [
                    group_id: meta.group_id,
                    n_metaprograms: meta.n_metaprograms,
                    score_type: 'background_score_stats',
                    metaprograms_publish_dir: meta.metaprograms_publish_dir,
                ]
                [updated_meta, background_stats_file]
            }
        )
        .groupTuple()

    COMBINE_SCORES(ch_combine_input)

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
    versions = ch_collated_versions
}
