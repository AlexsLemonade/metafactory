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

    // build one task per group_id/n_metaprograms combination
    def ch_metaprogram_input = ch_cnmf_by_group
        .combine(channel.fromList(n_metaprograms_list))
        .map { group_id, unique_ids, cnmf_output_dirs, n_metaprograms ->
            def meta = [group_id: group_id, n_metaprograms: n_metaprograms, unique_ids: unique_ids]
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
