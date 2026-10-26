%% Reproduce and understand the updated publication example
% Work through these sections in order in the MATLAB Editor. Variables remain
% in the workspace so that each probability, decision and result can be inspected.
% Run All combines saved estimates with deterministic calculations of missing
% tails. Unsupported cases would produce an assessment instead of final figures.
% The numerical pipeline reads the bundled
% MAT files. The bundled inputs record 1,000,000 Monte Carlo trials per initial
% damage case: specified numbers of initially broken brittle components and
% yielded ductile components in the remaining system. No new sampling is run.
%
% Reading route for the physical calculation:
% daniels_system -> simulate_daniels -> daniels.trial -> daniels.collapse
% Reading route for knowledge and robustness:
% calculate_voir -> voir.aggregateKnowledge -> voir.bernoulliKL
%
% This walkthrough uses those same functions. The ordinary callable pipeline
% remains reproduce_publication for automated runs and supplied simulation data.

%% 1. Locate the implementation, inputs and outputs
% Keep the publication inputs separate from generated results. Change
% renderFigures to false to inspect the numerical workflow without exporting
% the figures. Run this setup section before any subsequent section.
repositoryRoot = fileparts(mfilename('fullpath'));
addpath(repositoryRoot, fullfile(repositoryRoot, 'src'));

dataFolder = fullfile(repositoryRoot, 'data', 'publication');
outputFolder = fullfile(repositoryRoot, 'results', 'publication_walkthrough');
renderFigures = true;

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

%% 2. Define the Daniels system used in the paper
% Ten equal-stiffness components share the load: five are brittle and five
% ductile. Both have the same Gaussian capacity distribution. A brittle break
% carries zero force; a yielded ductile component retains its yield force.
% LoadProbability is the annual probability lambda of load occurrence.
system = daniels_system( ...
    'BrittleCount', 5, ...
    'DuctileCount', 5, ...
    'Load', 2000, ...
    'MeanCapacity', 400, ...
    'CapacitySD', 140, ...
    'LoadProbability', 0.001);
disp(system)

% The saved inputs below were generated for this physical definition.
% In a fresh simulation, catalogue enumerates attacked compositions and
% initiating states. trial samples capacities above the initial load share
% F/N and yielded ductile forces below it. It subtracts every retained ductile
% force, then collapse redistributes the remaining load step by step.
% See the numbered explanations in those functions for the actual recurrence.

%% 3. Read the saved physical responses and the null-action reference
% An attack removes r components, of which delta are ductile. Each MAT file
% describes one such composition, including the intact case r=0.
% loadData returns probabilities with their physical identities, rather than
% loading the original scripts' entire workspaces. The declared system
% is checked against these files before any responses are combined.
[cases, p_ref, inputInfo] = publication.loadData(dataFolder, system);

% pi encodes conditional extinction: probability = Phi(-pi).
% beta encodes the annual initiating probability: probability = Phi(-beta).
% p_ref is the intact failure probability conditional on applied load.
% It stays fixed across attacks and knowledge. Annual reliability is separate.
fprintf('Read %d compositions; intact reference conditional on load = %.12g.\n', ...
    numel(cases), p_ref);

% The legacy files lost some uncapped tails. loadData evaluates those small
% remaining systems by deterministic Gaussian integration, with numerical
% convergence checks. inputInfo records which values come from integration
% rather than Monte Carlo. No new sampling is performed.
if inputInfo.unresolved_cases > 0
    assessment = publication.assessTails(cases, inputInfo, outputFolder);
    save(fullfile(outputFolder, 'tail_assessment.mat'), 'cases', 'inputInfo', 'assessment');
    fprintf('Resolve the listed missing tails before continuing to point-valued figures.\n');
    return
end

%% 4. Examine the initiating-scenario mixture in the intact system
% Every initial damage count contributes under the prescribed load.
% j=0 gives survival and j=N gives extinction without simulation.
% The same all-outcome mixture supplies the intact reference used by VoIR.
intact = cases{1};
scenarioWeights = intact.initiating_probability;
initiatingProbability = intact.annual_initiating_probability;
conditionalExtinction = [0, intact.probability, 1];
intactConditionalResponse = conditionalExtinction*scenarioWeights';

scenarioTable = table((0:system.n_bars)', initiatingProbability', scenarioWeights', conditionalExtinction', ...
    'VariableNames', {'j', 'annual_initiating_probability', 'probability_given_load', 'conditional_extinction'});
disp(scenarioTable)
fprintf('Intact extinction conditional on applied load = %.12g.\n', intactConditionalResponse);
fprintf('Annual intact extinction probability = %.12g.\n', intact.annual_failure_bounds(1));

%% 5. Assemble the response matrix passed to the VoIR calculation
% Row r contains the physical response after removing r components.
% Column delta+1 corresponds to removing delta ductile and r-delta brittle
% components. NaN means the composition is infeasible. These are probabilities
% of extinction; no knowledge or adversary optimization has been applied yet.
% The model builder collects these responses and assembles the scenario-level
% reliability mixtures for Figures 3-5. Its numbered sections explain those
% physical mixtures. Knowledge and attack choices follow in the next section.
model = publication.modelFromCases(repositoryRoot, cases, p_ref);
attackSizes = model.attack_sizes;
% The existing MAT files supply r=1,...,7. One- and two-component systems
% add r=8,9 analytically, with no new trials or MAT files.
% Retain survival separately: 1-extinction loses the very small r=9 tail.
survivalResponse = model.survival_response;
disp(model.analytical_responses)
response = model.response;
disp(response)

%% 6. Choose attacks under each knowledge state
% h is the number of component identities observed by the adversary.
% For each observation, evaluate feasible attacks, average over unknown
% identities, and select the largest expected extinction probability.
% Then average the selected responses over observations, before evaluating KL.
% The numbered stages of aggregateKnowledge implement these steps explicitly.
analysis = calculate_voir(response, p_ref, ...
    'BrittleCount', system.n_brittle, ...
    'DuctileCount', system.n_ductile, ...
    'AttackSizes', attackSizes, ...
    'SurvivalResponse', survivalResponse, 'ReferenceSurvival', model.reference_survival, ...
    'KnowledgeSizes', 0:system.n_bars);

% Inspect one existing decision: h=5, r=4, with two observed ductile identities.
% Candidate columns give known components attacked, known ductile components
% attacked, and expected extinction. No new physical trials are needed here.
decisionDetails = analysis.policy_details{6, 4};
observation = decisionDetails([decisionDetails.known_ductile] == 2);
candidateTable = array2table(observation.candidates, ...
    'VariableNames', {'known_attacked', 'known_ductile_attacked', ...
    'expected_extinction'});
disp(candidateTable)
disp(observation.selected_action)

%% 7. Inspect divergence, robustness and VoIR
% The same analysis computes forward D_KL(p_ref || p_attack), in nats.
% I_rob = exp(-D_KL).
% VoIR_D subtracts the uninformed (h=0) divergence at the same r.
% VoIR_R = exp(-VoIR_D).
% Output row h+1 corresponds to h observed identities; columns follow r=1:9.
selectedKnowledge = 5;
resultTable = table( ...
    attackSizes', ...
    analysis.probability(selectedKnowledge + 1, :)', ...
    analysis.survival(selectedKnowledge + 1, :)', ...
    analysis.KL(selectedKnowledge + 1, :)', ...
    analysis.robustness(selectedKnowledge + 1, :)', ...
    analysis.VoIR_D(selectedKnowledge + 1, :)', ...
    analysis.VoIR_R(selectedKnowledge + 1, :)', ...
    'VariableNames', {'r', 'conditional_extinction', 'conditional_survival', 'KL_nats', ...
    'Irob', 'VoIR_D_nats', 'VoIR_R'});
disp(resultTable)

%% 8. Export the publication tables using the displayed analysis
% The model from section 5 already contains the physical reliability mixtures.
% Attach the exact analysis calculated in section 6 and displayed in section 7.
% Tables, figures and results.mat will all use this same result.
% Figure 5 uses the same intact reference, with points conditional on each j.
model.aggregate = analysis;
publication.writeTables(model, outputFolder);
writetable(inputInfo.case_table, fullfile(outputFolder, 'initial_damage_cases.csv'));
if ~isempty(inputInfo.tail_integrations)
    writetable(struct2table(inputInfo.tail_integrations), fullfile(outputFolder, 'tail_integration.csv'));
end

% aggregate_h_r.csv contains all 99 (h,r) results.
% analytical_responses.csv gives the five analytical r=8,9 compositions.
% Figure 6 extends through r=9; Figure 7 retains r=1,...,7 for readability.
% figure_series.csv separates numerical x from display_x at the plotting limit.
% The model retains the intermediate mixtures as well as the final results.

%% 9. Export the numerical figures and save the model
% The renderer takes the computed model and the measured publication layout.
% It exports Figures 1 and 3-7, including individual panels, as PDF, SVG and PNG.
% Figure 2 is illustrative and omitted. Repeating this section replaces the
% generated files in outputFolder; the input MAT files are unchanged.
if renderFigures
    publication.renderFigures(model, outputFolder);
end

report = struct('status', 'complete', 'output_directory', outputFolder, ...
    'inputs', inputInfo, 'rendered', renderFigures, 'random_sampling', false);
save(fullfile(outputFolder, 'results.mat'), 'model', 'report', '-v7');
fprintf('Walkthrough complete. Tables, model and figures: %s\n', outputFolder);
