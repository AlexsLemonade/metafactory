import java.nio.file.Files
import java.util.zip.GZIPInputStream

// Helpers shared by the nf-test tests of the local subworkflows. nf-test adds `tests/lib` to the
// classpath (`libDir` in nf-test.config), so a test file can call these directly, e.g.
// `SubworkflowTestUtils.taskMetas(...)`.
//
// The parts that differ between subworkflows are passed in as arguments:
// - `emits`: a map of process name -> the items emitted by that process's tasks. Each task emits
//   one item, `[meta, path, ...]`, and the meta in that item is the meta the task ran with.
// - `taskId`: a closure that turns a meta into a string identifying the task, used for sorting.
class SubworkflowTestUtils {

    // the group in the test samplesheet, which the files in `tests/data/` were generated for
    static final String DATA_GROUP_ID = 'SCPCP000001'

    // the pipeline outputs shared by the subworkflow tests. regenerate them with
    // `tests/scripts/update-test-data.sh`
    static String dataDir(baseDir) {
        "${baseDir}/tests/data".toString()
    }

    // the optimal value of k chosen in the pipeline run the files in `tests/data/` were generated from
    static int dataOptimalK(data_dir) {
        new File(data_dir.toString(), 'optimal-k.txt').text.trim().toInteger()
    }

    // a file in `tests/data/` for the metaprogram set with `k` metaprograms, by its name without the
    // `k-<k>_` prefix, e.g. `mp_metrics.tsv`. k is passed in, usually from dataOptimalK, so a test
    // reads optimal-k.txt once rather than for every file
    static String dataFile(data_dir, int k, String name) {
        "${data_dir}/k-${k}_${name}".toString()
    }

    // the meta of each task that ran, by process. sorted, as tasks finish in no fixed order
    static Map taskMetas(Map emits, Closure taskId) {
        emits.collectEntries { process, items ->
            [process, items.collect { item -> item[0] }.sort { meta -> taskId(meta) }]
        }
    }

    // emitted items as [meta, file name, ...] for snapshots. items are emitted in no fixed order, so
    // they are sorted, and only the file names are kept so the snapshot holds no machine specific paths
    static List outputSummary(items, Closure taskId) {
        items.collect { item -> [item[0]] + item.drop(1).collect { path -> new File(path.toString()).name } }
            .sort { item -> taskId(item[0]) }
    }

    // the names of the files staged into the task that emitted each item, with the task's process and
    // meta. `outputDepth` is the number of directories between the task directory and the first
    // output of an item, as where outputs are written inside the task directory differs per
    // subworkflow, e.g. 1 for `<task dir>/<group>/<output>`.
    // inputs are symlinked into the task directory, while outputs are not symlinks, so the symlinks
    // are exactly the staged inputs. inputs can be staged into a subdirectory, so symlinks one
    // directory down are kept too, named by their path relative to the task directory
    static List stagedInputs(Map emits, int outputDepth) {
        def isLink = { File f -> Files.isSymbolicLink(f.toPath()) }
        emits.collectMany { process, items ->
            items.collect { item ->
                def meta = item[0]
                def task_dir = new File(item[1].toString()).parentFile
                outputDepth.times { task_dir = task_dir.parentFile }
                def staged = task_dir.listFiles().findAll { f -> isLink(f) }*.name
                task_dir.listFiles().findAll { f -> f.isDirectory() && !isLink(f) && !f.name.startsWith('.') }.each { sub_dir ->
                    staged += sub_dir.listFiles().findAll { f -> isLink(f) }.collect { f -> "${sub_dir.name}/${f.name}".toString() }
                }
                [process: process, meta: meta, staged: staged.sort()]
            }
        }
    }

    // the lines of a TSV file, which may be gzipped
    static List<String> tsvLines(file) {
        def path = file.toString()
        if (path.endsWith('.gz')) {
            return new GZIPInputStream(new FileInputStream(path)).withReader { reader -> reader.readLines() }
        }
        new File(path).readLines()
    }

    // a TSV file as a list of maps, one per row, keyed by column name. all values are strings. every
    // row must have as many fields as the header, so no field is dropped or left missing
    static List<Map> readTsv(file) {
        def lines = tsvLines(file)
        def header = lines[0].split('\t', -1) as List
        lines.drop(1).findAll { line -> line }.withIndex().collect { line, i ->
            def fields = line.split('\t', -1) as List
            assert fields.size() == header.size() :
                "row ${i + 1} of ${file} has ${fields.size()} fields, but the header has ${header.size()}"
            [header, fields].transpose().collectEntries()
        }
    }

    // checks that two TSV files have the same header and the same rows in the same order. values
    // that differ as strings must both be numbers within the tolerance of each other
    static void assertTsvEqual(actual_file, expected_file, double tolerance = 1e-8) {
        assert tsvLines(actual_file)[0] == tsvLines(expected_file)[0]
        def actual = readTsv(actual_file)
        def expected = readTsv(expected_file)
        assert actual.size() == expected.size()
        [actual, expected].transpose().each { actual_row, expected_row ->
            expected_row.each { column, value ->
                def actual_value = actual_row[column]
                assert actual_value != null : "${column} is missing from a row of ${actual_file}"
                assert actual_value == value || (actual_value.isDouble() && value.isDouble() &&
                    Math.abs(actual_value.toDouble() - value.toDouble()) <= tolerance) :
                    "${column} in ${expected_file}: ${actual_value} != ${value}"
            }
        }
    }

    // the combined stdout and stderr of a test run, for checking error messages
    static String runOutput(workflow) {
        (workflow.stdout + workflow.stderr).join('\n')
    }

    // whether any task of the process succeeded in a test run
    static boolean processSucceeded(workflow, String process) {
        workflow.trace.succeeded()*.name.any { name -> name.contains(process) }
    }

    // writes lines to a file named `name` in `dir`, ending with a newline, and returns the file
    static File writeLines(List lines, dir, String name) {
        def out_file = new File(dir.toString(), name)
        out_file.text = lines.join('\n') + '\n'
        out_file
    }

    // writes a changed copy of a data file to `outDir`, keeping its name, and returns the copy.
    // `modify` takes the lines of the file and returns the lines to use in their place. only
    // uncompressed files can be modified. the original file is never changed
    static File modifiedFile(file, Closure modify, outDir) {
        def in_file = new File(file.toString())
        writeLines(modify(in_file.readLines()), outDir, in_file.name)
    }
}
