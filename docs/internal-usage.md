# AlexsLemonade/metafactory: Internal usage

This page describes how the Data Lab runs `metafactory` on ScPCA data internally.
These directions are specific to the Data Lab team and assume access to the ScPCA AWS account and the `ScPCA-admin` repository.
For general instructions on running the pipeline, see [usage.md](usage.md).

> [!NOTE]
> These instructions are for using ScPCA data as input for testing or generating preliminary results.
> Instructions for formally running ScPCA data are forthcoming.

## Running with ScPCA data

ScPCA data is run with the `scpca_testing` profile, defined in [`conf/alsf-profiles.config`](../conf/alsf-profiles.config).
The pipeline is launched through a [GitHub Action (GHA) in the `ScPCA-admin` repository](https://github.com/AlexsLemonade/ScPCA-admin/actions/workflows/run-metafactory.yml), which runs the workflow from a branch of this repository.

1. Create a branch in this repository to use when running the workflow from the GHA.
2. Create a samplesheet that lists the libraries to include and the paths to their `.h5ad` files, and save it to the `assets` directory.
   See [Samplesheet input](usage.md#samplesheet-input) for the required columns, and [`assets/scpca-testing-samplesheet.csv`](../assets/scpca-testing-samplesheet.csv) for an example.
3. In the `scpca_testing` profile in [`conf/alsf-profiles.config`](../conf/alsf-profiles.config), update the `input` parameter to the path to your new samplesheet:

   ```groovy
   input = "${projectDir}/assets/<your-samplesheet>.csv"
   ```

   The profile also sets `group_id` and `n_metaprograms`, so check that these are appropriate for your samplesheet.
   These can be optionally set using the `Additional Nextflow options` box in the GHA too.

4. Push your branch to GitHub and navigate to the [GHA in `ScPCA-admin`](https://github.com/AlexsLemonade/ScPCA-admin/actions/workflows/run-metafactory.yml).
5. Run the workflow using the `scpca_testing` run mode, and enter the name of your branch in "Workflow version or branch to display".

## Output

Output files are saved to `s3://ccdl-scpca-nf-results-testing/metafactory/scpca-testing-output`.
See [output.md](output.md) for a description of the results.
