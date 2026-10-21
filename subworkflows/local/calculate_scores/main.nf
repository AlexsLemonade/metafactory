// Subworkflow to score every library in a group against each set of metaprograms generated for that group,
// calculate a background score distribution from shuffled metaprograms, and combine the scores for each metaprogram set

include { SCORE_METAPROGRAMS                           } from '../../../modules/local/score-metaprograms/main'
include { SCORE_BACKGROUND                             } from '../../../modules/local/score-background/main'
include { COMBINE_SCORES as COMBINE_METAPROGRAM_SCORES ; COMBINE_SCORES as COMBINE_BACKGROUND_SCORES } from '../../../modules/local/combine-scores/main'


workflow CALCULATE_SCORES {
    take:
    ch_samplesheet // channel: [ meta, h5ad_file ]
    ch_metaprograms // channel: [ meta, metaprograms_file, metaprograms_export_file, shuffled_metaprograms_file ]

    main:

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
    def ch_metaprograms_by_library = ch_metaprograms
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

    emit:
    metaprogram_scores = COMBINE_METAPROGRAM_SCORES.out.results // channel: [ val(meta), combined_scores_file ]
    background_scores  = COMBINE_BACKGROUND_SCORES.out.results // channel: [ val(meta), combined_background_stats_file ]
}
