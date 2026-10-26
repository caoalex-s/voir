# Using Daniels and VoIR

## Publication walkthrough

Open [publication_walkthrough.m](../publication_walkthrough.m) in the MATLAB Editor and run its sections in order:

1. Locate the implementation, input data and output folder.
2. Define the physical system.
3. Read case evidence and the intact reference.
4. Examine all initial damage outcomes under the applied load.
5. Assemble physical response probabilities by attack composition.
6. Select attacks under partial knowledge.
7. Calculate KL divergence, robustness and VoIR.
8. Export numerical tables.
9. Export figures and save the model.

The bundled inputs contain probabilities capped before saving. The walkthrough evaluates those missing tails by deterministic integration of the same Gaussian model, then combines them with the retained simulation estimates. No new sampling occurs.

The walkthrough uses the same calculation functions as `reproduce_publication`. Intermediate variables remain visible. Set `renderFigures = false` to omit figure export. Outputs go to `results/publication_walkthrough/`.

## Define and simulate a system

```matlab
system = daniels_system('BrittleCount',5,'DuctileCount',5, ...
    'Load',2000,'MeanCapacity',400,'CapacitySD',140, ...
    'LoadProbability',0.001);

data = simulate_daniels(system,'AttackSizes',1:7, ...
    'TrialsPerStratum',1000,'Seed',1234,'Workers',4);
```

This example uses **1,000 trials per initial damage case** for demonstration. A case fixes the numbers of initially broken brittle and yielded ductile components. The saved publication inputs used **1,000,000 trials per case**; matching that sample size does not guarantee adequate precision in every uncapped tail.

The component count $N$ is the sum of the brittle and ductile counts. Either class may be absent; the current simulation interface requires at least two remaining components. Load does not automatically scale with component count. Capacity parameters and load must be positive; the annual load probability lies in $[0,1]$.

`AttackSizes` defaults to `1:min(7,N-2)`. Supply `0` to calculate the intact system alone. Intermediate initial damage cases require simulation; the no-damage and all-damaged outcomes are added analytically. Both intact and attacked response probabilities condition on applied load. Annual reliability is a separate result.

`TrialsPerStratum` and `Seed` are explicit for new sampling. Serial execution is the default. A parallel call closes only a pool it creates. Each physical task uses a local mrg32k3a substream with the Inversion normal transform, so retain the seed, task order and physical definition when repeating a run.

`MaxProposalsPerAcceptance` defaults to 1000. Reaching this limit or an unsupported overloaded capacity tie returns incomplete data with the stopped trial; incomplete cases do not produce a response matrix.

## Inspect the physical results

| Field | Meaning and indexing |
| --- | --- |
| `data.tasks` | One entry per initial damage case. `configuration` identifies the remaining composition. `stratum` records the initial brittle breaks, ductile yields and their conditional weight. |
| `data.records` | Same order as `data.tasks`. `n` is the number of completed trials, `k` is the number of extinctions, and `weight` is the material-split probability conditional on damage count $j$. |
| `data.compositions` | One entry per remaining composition, including the intact system. `conditional_probability(j)` is extinction conditional on damage count $j$. `response` averages over all damage counts under the applied load. |
| `data.response` and `data.survival_response` | Extinction and survival matrices. Rows follow `data.attack_sizes`. Column $\delta+1$ represents removing $\delta$ ductile components. Infeasible entries are NaN. |
| `data.p_ref` and `data.reference_survival` | Intact extinction and survival under the same prescribed load as the attacked systems. |
| `data.annual_failure_probability` | Annual intact failure probability, reported separately from the conditional reference. |

The existing option `TrialsPerStratum` and field `stratum` use “stratum” to mean one initial damage case. These names are retained for compatibility with saved data and existing calls.

Raw counts are retained, and no $\pi$ floor is applied to numerical results. The function returns data in memory; save them explicitly when needed.

## Calculate VoIR

```matlab
analysis = calculate_voir(data);

% Or supply physical responses and a matching reference directly:
analysis = calculate_voir(response,p_ref, ...
    'BrittleCount',5,'DuctileCount',5, ...
    'AttackSizes',1:7,'KnowledgeSizes',[0,3,5,10]);
```

Dataset input is rebuilt from its corrected-mechanics raw counts before calculating VoIR. For matrix input, every feasible probability must lie in $[0,1]$ and be at least `p_ref`; this is the stated domain where maximizing extinction also maximizes forward KL. Intact and attacked probabilities must have the same loading definition.

`KnowledgeSizes` defaults to $h=0,\ldots,N$ and must begin with $h=0$. The result matrices `probability`, `survival`, `pi`, `KL`, `robustness`, `VoIR_D` and `VoIR_R` have one row per requested knowledge size and one column per requested attack size. Their order is returned in `analysis.knowledge_sizes` and `analysis.attack_sizes`. A row index equals $h+1$ only when every knowledge size $h=0,\ldots,N$ is included.

`policy_details{knowledgeIndex,attackIndex}` contains one entry per possible observed material composition. Its `candidates` matrix has columns for known components attacked, known ductile components attacked, and expected extinction. `selected_action` records the first two entries of the chosen action. Selected responses are averaged over observations before KL is evaluated.

When physical survival tails are available directly, pass them using `'SurvivalResponse',survivalResponse` with the same matrix shape; `'ReferenceSurvival',referenceSurvival` optionally supplies the intact complement. Dataset input passes both outcomes automatically. This preserves rare survival when extinction rounds to one. `policy_details` also records `candidate_survival` and `selected_survival` so these attack choices can be inspected.

Mathematical zero/one limits are retained. If both compared divergences are infinite, their difference is unresolved; an artificial interior probability is not substituted.

## Publication pipeline

```matlab
[model, report] = reproduce_publication('Render',false);

% Rebuild, export and reload a complete newly simulated paper-system dataset:
[model, report] = reproduce_publication('SimulationData',data);
```

The default reads the 30 composition files in `data/publication/`. Another `DataFolder` must have the same physical compositions and matching parameters. The publication pipeline requires the five-brittle/five-ductile system and saved or simulated inputs for attack sizes $r=1,\ldots,7$. It adds the one- and two-component responses analytically, so Figure 6 and the aggregate table cover $r=1,\ldots,9$. Figure 7 retains $r=1,\ldots,7$ for readability. Other systems use the general interfaces above.

The bundled cases are covered by the deterministic tail calculation. `initial_damage_cases.csv` identifies the origin of every probability; deterministic rows have no trial count. `tail_integration.csv` records the integration results and convergence checks. If another input contains an unsupported capped case, the pipeline reports `needs-tail-data` and writes bounds instead of final figures.

For resolved inputs, `report.status` is `complete`. Outputs include the 99-row `aggregate_h_r.csv`, `analytical_responses.csv`, `figure_series.csv`, `results.mat`, and optional PDF/SVG/PNG figures. `survival_post` retains the small survival probabilities even where `p_post` rounds to one. Numerical $x$ coordinates remain uncapped; `display_x` records the plotting boundary separately. Individual panels of Figures 4, 5 and 7 are intended for LaTeX subfigure environments.

Outputs default to `results/publication/`; use `OutputFolder` to select another directory. Repeated calls replace generated files. Bundled MAT inputs are preserved.

## Read the implementation

The physical path is `daniels_system` → `simulate_daniels` → `daniels.trial` → `daniels.collapse`. Raw counts pass through `daniels.derive` and the shared `daniels.combineResponse`. The saved-data reader uses that same mixture. The separate `voir.aggregateKnowledge` handles observations, action choices and robustness.

Functions use numbered sections explaining the calculation, with input and output descriptions for the reusable helpers. Use the walkthrough for running individual sections interactively. The [paper-to-code map](METHODS.md#from-the-paper-to-the-code) identifies the functions behind each concept and figure. The same document explains probability definitions and saved-data limitations.
