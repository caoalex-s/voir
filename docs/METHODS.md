# Model conventions

These are the conventions used by the Daniels calculation and VoIR workflow. Physical parameters can vary; the constitutive and information models remain those of the paper.

## From the paper to the code

For the publication calculation, read [publication_walkthrough.m](../publication_walkthrough.m) in section order. Its saved-data path is `publication.loadData` → `publication.modelFromCases` → `calculate_voir` → tables and figures. The loader resolves saved probabilities and missing tails. The model assembles responses by attacked composition, and VoIR selects and averages attacks under each knowledge state.

For a new physical system, read `daniels_system` → `simulate_daniels` → `daniels.sampleTask` → `daniels.trial` → `daniels.collapse`. The first two functions expose the settings. The helpers draw conditional capacities and redistribute load. `daniels.derive` then combines completed trial counts into the response matrix used by `calculate_voir`. Both input paths use `daniels.combineResponse` to include every initial damage outcome.

| Concept or result | Where to read it |
| --- | --- |
| Component counts, load and capacity distribution | [daniels_system.m](../daniels_system.m) |
| Remaining compositions and initial damage cases | [catalogue.m](../src/+daniels/catalogue.m) and [rule.m](../src/+daniels/rule.m) |
| Capacities conditional on initial damage | [source.m](../src/+daniels/source.m) and [trial.m](../src/+daniels/trial.m) |
| Brittle breaks, ductile yielding and equal load sharing | [collapse.m](../src/+daniels/collapse.m) |
| Extinction probability under the prescribed load | [derive.m](../src/+daniels/derive.m) and [combineResponse.m](../src/+daniels/combineResponse.m) |
| Saved probabilities and deterministic missing-tail calculations | [readProbabilities.m](../src/+publication/readProbabilities.m), [brittleSurvival.m](../src/+daniels/brittleSurvival.m) and [conditionalSurvival.m](../src/+daniels/conditionalSurvival.m) |
| One or two remaining components, extending Figure 6 | [smallSystemSurvival.m](../src/+daniels/smallSystemSurvival.m) |
| Observations, candidate actions and the selected response | [aggregateKnowledge.m](../src/+voir/aggregateKnowledge.m), sections 1–3 |
| Forward KL divergence and robustness, Eqs. (10) and (13) | [bernoulliKL.m](../src/+voir/bernoulliKL.m) and `aggregateKnowledge`, section 4 |
| VoIR, Eqs. (19) and (21) | `aggregateKnowledge`, section 5 |
| Figure 1 illustration and Figures 3–7 | [modelFromCases.m](../src/+publication/modelFromCases.m) prepares the physical series. [renderFigures.m](../src/+publication/renderFigures.m) names each drawing section by figure |
| Numerical values behind the figures | [writeTables.m](../src/+publication/writeTables.m) exports coordinates and aggregate responses |

The sections below state the conventions used in the updated calculation, including the corrected initial ductile force, common loading condition and uncapped probabilities. [Usage](USAGE.md#inspect-the-physical-results) describes the returned structures and their indexing.

## Daniels mechanics

Brittle components carry zero force after breaking. Ductile components retain their sampled yield force. Elastic components share the remaining load equally. Initially yielded ductile forces are all subtracted before redistribution; subsequent ductile yielding retains that component's force, while a brittle break retains none.

Capacities follow the stated untruncated normal distribution. Scalar rejection sampling retains the strict above/below initial load-share thresholds. Capacity equality with the current share does not trigger failure. An overloaded tie between minimum active capacities stops the trial without counting an outcome. The normal model admits negative capacities; this approximation has not been changed.

## Probability definition

Both intact and attacked system extinction probabilities condition on the prescribed load being applied. All initial damage outcomes are included. The no-damage event gives survival, and damage to every remaining component gives extinction, so these two cases require no simulation.

Intermediate damage counts are binomially weighted; the brittle/ductile splits within each count have hypergeometric weights. The complete mixture is calculated by the shared function `daniels.combineResponse` for both saved and fresh data. The annual failure probability is the load-occurrence probability times this full conditional response. Annual reliability is reported separately and is not the reference used in VoIR.

Raw trial counts are averaged directly. No $\pi$ floor or interior probability clipping is applied to numerical probabilities, robustness or VoIR. Bernoulli KL uses its mathematical endpoint limits. A difference of two infinite divergences is unresolved, rather than replaced by an arbitrary finite value.

## Saved evidence and missing tails

The bundled inputs contain six corrected coauthor simulations and 24 unaffected original datasets. Some legacy case probabilities were floored at $\pi=-3$ before saving. Those values do not identify the uncensored probability.

Uncensored case counts can be reconstructed from their saved probability and recorded sample size when the integer count is unambiguous. The revised calculation retains these estimates. Homogeneous brittle conditional survival is calculated analytically by counting capacities above the successive load-sharing thresholds.

All 85 other capped cases in the bundled data have at most three elastic components remaining. `daniels.conditionalSurvival` evaluates their survival probabilities by deterministic Gaussian integration. It conditions on the initially yielded ductile forces and the first subsequent break or yield, retaining the same force accounting as the simulation. For three to five initially yielded components, convolution evaluates their total retained force. Increasing integration resolution checks numerical convergence. These values are model calculations, not recovered Monte Carlo counts, and their origin is recorded in `initial_damage_cases.csv` and `tail_integration.csv`.

Thus the publication calculation combines retained simulation estimates with deterministic tail calculations under the same physical model. It does not claim that the original simulations themselves estimated every rare outcome accurately. Unsupported capped cases, if supplied in another dataset, remain explicit missing-information bounds; those bounds are not statistical confidence intervals.

## One or two components remaining

For $r=8$ and $r=9$, `daniels.smallSystemSurvival` evaluates the remaining system analytically under the same Gaussian capacity model and prescribed load. No additional MAT files or Monte Carlo trials are required. A single component survives if its capacity exceeds the full load, irrespective of material type. Two brittle components survive if both capacities exceed half the load, or if the weaker breaks and the stronger can carry the full load. Two ductile components survive if their capacity sum exceeds the load. For one of each type, exchangeability of the identically distributed capacities gives the mean of the two homogeneous survival probabilities.

Survival probabilities are passed directly into action selection, averaging, KL divergence and VoIR. Their small values must not be reconstructed by subtracting an extinction probability that has rounded to one. Both outcome probabilities are exported. The difference in KL values is evaluated through the corresponding log ratios, retaining the same mathematical definition.

The selected Figure 6 curves peak at $r=7$, decrease at $r=8$ and reach zero at $r=9$. The zero follows from identical response distributions for the single remaining brittle or ductile component, so type-only information cannot improve the attack. Near-certain extinction alone does not imply a vanishing KL contrast: relative survival probabilities can still differ. Removing all ten components gives exactly zero survival and infinite forward KL values; their difference is undefined, so $r=10$ is not plotted.

## Knowledge and robustness

The adversary observes the identities of $h$ components uniformly and removes exactly $r$ components. Unknown identities follow the conditional composition distribution. For each observation, the code selects the action with maximum expected extinction. It compares extinction directly when both candidate probabilities are at most one half, and otherwise compares survival in the opposite direction. This retains differences in either small outcome probability. Exact numerical ties keep enumeration order. Near-tie diagnostics do not change the objective.

Maximizing extinction is equivalent to maximizing forward Bernoulli KL on the stated domain: every supplied attack probability is at least the fixed intact reference. The general interface checks this condition. Selected responses are averaged over observations before evaluating KL. VoIR compares each knowledge state with the uninformed state using the same reference.

## Figures

Figures 3–5 retain separate points conditional on each labelled intermediate damage count. Their system-level responses include all initial damage outcomes. The annual initiating-event coordinate of a system triangle represents load occurrence; its $\pi$ coordinate represents extinction conditional on that load.

Every Figure 5 series uses the same intact reference under applied load. Figure 6 shows the full aggregate responses for $r=1,\ldots,9$. Figure 7 shows $r=1,\ldots,7$ for readability; the additional points would overlap at its display boundary. The renderer alone places $\pi$ values below $-3$ at the display boundary; exported numerical coordinates remain uncapped, with a separate `display_x` column.

Figure 1 illustrates the manuscript's small-reference approximation. Figure 7 uses exact Bernoulli KL and locates the robustness category levels $0.5$ and $0.84$ on that finite-reference curve. No peak location is prescribed in the code.
