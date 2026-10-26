#!/bin/bash
set -euo pipefail
# Regenerates the test data shared by the GENERATE_REPORTS and CALCULATE_METRICS subworkflow tests.
# Runs the full pipeline with the test profile, then copies the files the two reports read for the
# single group in the test samplesheet into `tests/data/`. The CALCULATE_METRICS tests
# use the metaprograms RDS as their input and the metrics tables as their expected outputs.
# Also writes a small term2gene table built from the top genes in the metaprograms RDS, so that the
# CALCULATE_METRICS tests can check ORA results with significant gene sets.
# Rerun this whenever the output of a module upstream of the reports changes.
# Requires R with the `optparse` and `tidyverse` packages, to run make-term2gene.R.
# Usage, from the root of the repository: tests/scripts/update-test-data.sh [additional nextflow run arguments]
# Any additional arguments are passed on to `nextflow run`, e.g. `-resume`

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tests_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${tests_dir}/.." && pwd)"
data_dir="${tests_dir}/data"

# the only group in tests/assets/samplesheet.csv
group_id="SCPCP000001"

# run the pipeline outside the repository so that the work directory, logs and results are not left
# behind, and are removed once the files have been copied
run_dir="$(mktemp -d)"
trap 'rm -rf "${run_dir}"' EXIT

cd "${run_dir}"
echo "Running nextflow pipeline in temporary directory: ${run_dir}"
nextflow run "${repo_dir}" -profile "test,docker" --outdir "${run_dir}/output"

# final results for the group, including the files for the metaprogram set chosen as the optimal value of k
group_dir="${run_dir}/output/results/${group_id}"
optimal_k="$(tr -d '[:space:]' < "${group_dir}/optimal-k.txt")"

# replace any previous data, so files for a previous optimal value of k are not left behind
rm -rf "${data_dir}"
mkdir -p "${data_dir}/reports"

# inputs to the metrics report
cp "${group_dir}/optimal-k.txt" "${data_dir}/"
for report_file in \
    all-k_metaprogram_metrics.tsv \
    all-k_summary_metrics.tsv \
    all-k_background_eff_sample_size.tsv.gz \
    all-k_background_geneset_specificity.tsv.gz \
    all-k_background_cell_score_cv.tsv.gz
do
    cp "${group_dir}/reports/${report_file}" "${data_dir}/reports/"
done

# inputs to the individual report, for the optimal value of k
for suffix in \
    metaprograms.rds \
    mp_metrics.tsv \
    ora_results.tsv \
    geneset_metrics.tsv \
    combined_metaprogram_scores.tsv.gz
do
    cp "${group_dir}/k-${optimal_k}_${suffix}" "${data_dir}/"
done

# term2gene table with gene sets that ORA finds significant for known metaprograms. The test
# profile run finds no significant gene sets with the default gene sets, so this is built from the
# top genes of the metaprograms instead; see make-term2gene.R for the gene sets.
Rscript "${script_dir}/make-term2gene.R" \
    --metaprograms_file "${data_dir}/k-${optimal_k}_metaprograms.rds" \
    --output_file "${data_dir}/k-${optimal_k}_term2gene.tsv"

echo "Copied test data for ${group_id} with an optimal k of ${optimal_k} to ${data_dir}:"
du -ah "${data_dir}"
