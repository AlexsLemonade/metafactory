#!/bin/bash
set -euo pipefail
# Regenerates the input files used by the GENERATE_REPORTS subworkflow tests that render the reports.
# Runs the full pipeline with the test profile, then copies the files the two reports read for the
# single group in the test samplesheet into `data/` next to this script.
# Rerun this whenever the output of a module upstream of the reports changes.
# Usage: ./update-test-data.sh [additional nextflow run arguments]
# Any additional arguments are passed on to `nextflow run`, e.g. `-resume`

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${tests_dir}/../../../.." && pwd)"
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

echo "Copied test data for ${group_id} with an optimal k of ${optimal_k} to ${data_dir}:"
du -ah "${data_dir}"
