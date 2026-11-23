import groovy.json.JsonOutput

// Helpers for the tests in `tests/stub.nf.test` that check when existing cNMF and
// metaprogram checkpoints are reused. nf-test adds `tests/lib` to the classpath (`libDir` in
// nf-test.config), so a test file can call these directly, e.g. `CheckpointTestUtils.tasksRun(...)`.
//
// Each test writes checkpoints into its output directory before the pipeline starts, as an earlier
// run with the same `--outdir` would have, then checks which CNMF and GENERATE_METAPROGRAMS tasks ran.
// The checkpoint files other than the meta JSON files are empty, as the stub modules do not read them.
class CheckpointTestUtils {

    // the libraries in each group of the stub samplesheet (`stub/samplesheet.csv`)
    static final Map<String, List<String>> GROUPS = [
        GROUP01: ['STUB01', 'STUB02'],
        GROUP02: ['STUB03', 'STUB04'],
    ]

    // the values of k (numbers of metaprograms) in the test profile (`conf/test.config`)
    static final List<Integer> N_METAPROGRAMS = [4, 5, 6, 7]

    // the options recorded in cnmf-meta.json, with the values the test profile runs with
    // (`conf/test.config` and the defaults in `nextflow.config`). if these drift from the test
    // profile, the test that expects every checkpoint to be reused fails
    static final Map CNMF_OPTIONS = [
        cnmf_k_lower: 5,
        cnmf_k_upper: 10,
        cnmf_k_step_size: 5,
        celltype_annotation_column: '',
        analysis_celltypes: '',
        seed: 2025,
    ]

    // the options recorded in metaprograms-meta.json, with the values the test profile runs with
    static final Map METAPROGRAM_OPTIONS = [
        n_top_genes: 200,
        filter_spectra: true,
        orphan_cutoff: 0.3,
        cnmf_k_lower: 5,
        cnmf_k_upper: 10,
        cnmf_k_step_size: 5,
        celltype_annotation_column: '',
        analysis_celltypes: '',
        seed: 2025,
        nreps: 3,
    ]

    // the cnmf_run_id written to existing cNMF checkpoints. the CNMF stub writes `stub`, so a library
    // whose cNMF runs in the test always gets a different run id from its existing checkpoint
    static final String PREVIOUS_RUN_ID = 'previous-run'

    // writes the cNMF checkpoint for one library: a spectra file for each cNMF k and cnmf-meta.json
    // `changes` are merged into the recorded JSON. a key with a null value is left out of the JSON,
    // e.g. `[cnmf_run_id: null]` writes a checkpoint from before run ids were recorded
    static void writeCnmfCheckpoint(outdir, String unique_id, Map changes = [:]) {
        def cnmf_dir = new File("${outdir}/checkpoints/cnmf/${unique_id}_cnmf")
        cnmf_dir.mkdirs()

        (CNMF_OPTIONS.cnmf_k_lower..CNMF_OPTIONS.cnmf_k_upper).step(CNMF_OPTIONS.cnmf_k_step_size).each { k ->
            new File(cnmf_dir, "${unique_id}_cnmf.gene_spectra_score.k_${k}.dt_0_1.txt").createNewFile()
        }

        def cnmf_meta = CNMF_OPTIONS + [cnmf_run_id: PREVIOUS_RUN_ID] + changes
        new File(cnmf_dir, 'cnmf-meta.json').text = toJson(cnmf_meta)
    }

    // writes the metaprogram checkpoint for one group and value of k: the three results files and
    // metaprograms-meta.json, recording the cNMF run id of every library in the group as
    // PREVIOUS_RUN_ID. `changes` are merged into the recorded JSON, as for writeCnmfCheckpoint.
    // `missing` is a list of results file suffixes to leave out, e.g. `['shuffled_metaprograms.tsv.gz']`
    static void writeMetaprogramCheckpoint(outdir, String group_id, int n_metaprograms, Map changes = [:], List<String> missing = []) {
        def mp_dir = new File("${outdir}/checkpoints/metaprograms/${group_id}/k-${n_metaprograms}_filtered_${METAPROGRAM_OPTIONS.orphan_cutoff}")
        mp_dir.mkdirs()
        def prefix = "k-${n_metaprograms}"

        // files in `missing` are deleted, so this can also replace a checkpoint written earlier,
        // e.g. by writeAllCheckpoints
        ['metaprograms.rds', 'metaprograms.tsv.gz', 'shuffled_metaprograms.tsv.gz'].each { suffix ->
            def results_file = new File(mp_dir, "${prefix}_${suffix}")
            if (suffix in missing) {
                results_file.delete()
            } else {
                results_file.createNewFile()
            }
        }

        def unique_ids = GROUPS[group_id]
        def mp_meta = [
            n_metaprograms: n_metaprograms,
            unique_ids: unique_ids,
            cnmf_run_ids: unique_ids.collect { _unique_id -> PREVIOUS_RUN_ID },
        ] + METAPROGRAM_OPTIONS + changes
        new File(mp_dir, "${prefix}_metaprograms-meta.json").text = toJson(mp_meta)
    }

    // writes a matching checkpoint for every library and every metaprogram set in the stub samplesheet,
    // as a complete earlier run with the same options would have
    static void writeAllCheckpoints(outdir) {
        GROUPS.each { group_id, unique_ids ->
            unique_ids.each { unique_id -> writeCnmfCheckpoint(outdir, unique_id) }
            N_METAPROGRAMS.each { n_metaprograms -> writeMetaprogramCheckpoint(outdir, group_id, n_metaprograms) }
        }
    }

    // the tags of the tasks of a process that ran successfully, sorted, e.g. `['STUB01', 'STUB02']`
    // for CNMF or `['GROUP01-k4']` for GENERATE_METAPROGRAMS. task names are of the form
    // `<workflow>:<process> (<tag>)`
    static List<String> tasksRun(workflow, String process_name) {
        workflow.trace.succeeded()*.name
            .collect { name ->
                def matcher = name =~ /(?:^|:)${process_name} \((.+)\)$/
                matcher.find() ? matcher.group(1) : null
            }
            .findAll { tag -> tag != null }
            .sort()
    }

    // the GENERATE_METAPROGRAMS task tags for every value of k for a group, e.g. `GROUP01-k4`
    static List<String> allMetaprogramTasks(String group_id) {
        N_METAPROGRAMS.collect { n_metaprograms -> "${group_id}-k${n_metaprograms}".toString() }
    }

    // keys with a null value are left out, so that tests can write checkpoints missing a key
    private static String toJson(Map values) {
        JsonOutput.prettyPrint(JsonOutput.toJson(values.findAll { _key, value -> value != null }))
    }
}
