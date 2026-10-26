# Publication data

The 30 files in `publication/` are the saved physical responses supplied for the paper: six corrected coauthor simulations and 24 unaffected original datasets. Their bytes are preserved. Names identify removed components: `attack_b4_d1.mat` removes four brittle and one ductile component; `attack_b0_d0.mat` is intact.

All files record **1,000,000 trials per initial damage case**, meaning a specified number of initially broken brittle and yielded ductile components. The original seeds and complete uncensored count records are unavailable. Some case probabilities were capped at $\pi=-3$ before saving.

## How the revised calculation reads these files

The physical parameters and material labels must match the declared system. Individual case probabilities and material-split weights are read before aggregation. An uncapped saved probability can identify an integer count at the recorded denominator; a capped value identifies only a range. Workspace counters left over from the final simulation loop are not a complete labelled count record.

The loader retains uncensored simulation estimates, calculates homogeneous brittle cases analytically, and evaluates the other 85 capped cases by deterministic Gaussian integration. No new capacity samples are drawn. These calculated values are not labelled as recovered original counts. All initial damage outcomes, including the two analytical endpoints, enter the common calculation conditional on applied load. Legacy annual summary values do not define the revised reference.

`reproduce_publication` and `publication_walkthrough` retain the source of each value in their outputs. `initial_damage_cases.csv` distinguishes empirical estimates from analytical and integrated probabilities; trial and failure counts are absent for deterministic rows. `tail_integration.csv` records numerical convergence. The original MAT files remain unchanged.

The MAT files cover the intact system and attack sizes $r=1,\ldots,7$. For attack sizes $r=8$ and $r=9$, the pipeline evaluates the five possible one- and two-component compositions analytically under the same Gaussian model. These values are recorded in `analytical_responses.csv`; they are not additional simulated datasets and have no Monte Carlo sample size. The aggregate table retains survival directly, including values too small to recover from a rounded extinction probability.

## Corrected inputs

| Received filename | Repository filename | Remaining brittle / ductile |
| --- | --- | --- |
| Case_study_2_results_1_br_4_du.mat | attack_b4_d1.mat | 1 / 4 |
| Case_study_2_results_2_br_3_du.mat | attack_b3_d2.mat | 2 / 3 |
| Case_study_2_results_3_br_2_du.mat | attack_b2_d3.mat | 3 / 2 |
| Case_study_2_results_3_br_3_du.mat | attack_b3_d3.mat | 2 / 2 |
| Case_study_2_results_4_br_2_du.mat | attack_b4_d2.mat | 1 / 3 |
| Case_study_2_results_4_br_3_du.mat | attack_b4_d3.mat | 1 / 2 |

The first three received names describe the remaining composition. Files were matched by their stored material labels; repository filenames consistently describe the removed components.

## Saved fields

| Field | Meaning |
| --- | --- |
| `n_bars`, `bar_l` | Remaining component count and material labels: 1 brittle, 2 ductile |
| `F`, `fy`, `fy_sd`, `fy_cov`, `lambda` | Load, capacity parameters and annual load-occurrence probability |
| `pi_cell` or `pi_vec_j` | Individual material-split case responses, including legacy caps |
| `pi_vec_clust` | Response aggregated over material splits for each intermediate damage count |
| `beta_star_vec_clust` | Annual initiating-damage probabilities encoded as $\beta$ |
| `Prob_c_cell` | Material-split probabilities within each damage count |
| `n_simu` | Recorded trials per initial damage case |

New simulations retain labelled integer `records`, physical parameters and stream identities. Exporting through `reproduce_publication('SimulationData',data)` writes these records to new MAT files and reloads them through the same calculation. The definition is recorded as `load-all-damage-v1`; annual summary values remain separate.

`batlow10.mat` supplies the publication palette; see the [third-party notice](../THIRD_PARTY_NOTICES.md). These data are included with the publication code and figures in the [version 1.0.0 Zenodo archive](https://doi.org/10.5281/zenodo.23657006).
