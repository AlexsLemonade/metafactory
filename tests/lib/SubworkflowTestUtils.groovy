import java.nio.file.Files

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
    // meta. `taskDirOf` takes the meta and the first output path of an item and returns the task
    // directory, as where outputs are written inside the task directory differs per subworkflow.
    // inputs are symlinked into the task directory, while outputs are not symlinks, so the symlinks
    // are exactly the staged inputs. inputs can be staged into a subdirectory, so symlinks one
    // directory down are kept too, named by their path relative to the task directory
    static List stagedInputs(Map emits, Closure taskDirOf) {
        def isLink = { File f -> Files.isSymbolicLink(f.toPath()) }
        emits.collectMany { process, items ->
            items.collect { item ->
                def meta = item[0]
                File task_dir = taskDirOf(meta, item[1])
                def staged = task_dir.listFiles().findAll { f -> isLink(f) }*.name
                task_dir.listFiles().findAll { f -> f.isDirectory() && !isLink(f) && !f.name.startsWith('.') }.each { sub_dir ->
                    staged += sub_dir.listFiles().findAll { f -> isLink(f) }.collect { f -> "${sub_dir.name}/${f.name}".toString() }
                }
                [process: process, meta: meta, staged: staged.sort()]
            }
        }
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
