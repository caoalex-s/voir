function model = modelFromCases(root, cases, p_ref)
    %MODELFROMCASES Assemble physical responses and publication reliability mixtures.
    %
    % Called after loadData has resolved every required probability.
    % Output model collects figure inputs and a 9-by-6 response matrix:
    % row r is attack size and column delta+1 is ductile removals.
    % The caller attaches calculate_voir output as model.aggregate.

    %% 1. Build the intact-system reliability result
    % Each case stores extinction indices pi and initiating indices beta.
    % Individual j points retain their damage conditioning and annual initiating
    % probabilities. System triangles use all damage outcomes conditional on
    % load; their initiating event is the applied load itself.
    assert(all(cellfun(@(c)c.resolved, cases)), 'publication:UnresolvedTails', ...
        'Use the saved-data assessment until uncensored case probabilities are available.');
    intact = cases{1};
    assert(isequal(p_ref, intact.response), 'publication:Reference', ...
        'The reference must be the intact response under the same applied load.');
    model.intact.pi = intact.pi;
    model.intact.beta = intact.beta;
    loadProbability = sum(intact.annual_initiating_probability);
    model.intact.system_beta = -norminv(loadProbability);
    model.intact.system_pi = -norminv(intact.response);
    model.p_ref = p_ref;
    model.reference_survival = intact.survival;
    model.reference_beta = -norminv(p_ref);
    model.annual_failure_probability = intact.annual_failure_bounds(1);
    model.annual_reliability_beta = -norminv(model.annual_failure_probability);

    %% 2. Collect the physical responses for each attack composition
    % Saved response rows are r=1,...,7; column delta+1 is ductile removals.
    % Section 3 extends the response matrix with analytical r=8 and r=9.
    % For each r, also retain the scenario-by-composition matrices needed
    % to draw the reliability panels in Figures 4 and 5.
    model.compositions = cell(7, 6);
    model.attack_sizes = 1:9;
    model.response = NaN(9, 6);
    model.survival_response = NaN(9, 6);
    residual = cell(1, 7);
    for r = 1:7
        remainingCount = 10-r;
        deltas = max(0, r-5):min(r, 5);
        piMatrix = zeros(numel(deltas), remainingCount-1);
        betaMatrix = piMatrix;
        probabilityMatrix = piMatrix;
        attackWeights = zeros(1, numel(deltas));
        for k = 1:numel(deltas)
            delta = deltas(k);
            brittleRemoved = r-delta;
            index = find(cellfun(@(v)v.r == r&&v.delta == delta, cases));
            assert(isscalar(index), 'publication:Composition', 'Missing physical composition.');
            composition = cases{index};
            model.compositions{r, delta+1} = composition;
            model.response(r, delta+1) = composition.response;
            model.survival_response(r, delta+1) = composition.survival;
            piMatrix(k, :) = composition.pi;
            betaMatrix(k, :) = composition.beta;
            probabilityMatrix(k, :) = composition.probability;
            attackWeights(k) = nchoosek(5, delta)*nchoosek(5, brittleRemoved)/nchoosek(10, r);
        end

        % 2a. The uninformed attacker removes material compositions at random.
        % For a particular initiating damage scenario, use Bayes' rule to
        % condition those composition weights before averaging extinction.
        initiating = normcdf(-betaMatrix);
        meanInitiating = attackWeights*initiating;
        conditionalAttack = attackWeights'.*(initiating./meanInitiating);
        conditionalAttack = conditionalAttack./sum(conditionalAttack, 1);
        meanSystem = sum(conditionalAttack.*probabilityMatrix, 1);
        assert(all(meanSystem >= -1e-14 & meanSystem <= 1+1e-14), ...
            'publication:Probability', 'Invalid conditional response mixture.');
        meanSystem = min(max(meanSystem, 0), 1); % Endpoint roundoff only.
        residualState = struct('r', r, 'n', remainingCount, 'deltas', deltas, 'pi', piMatrix, 'beta', betaMatrix, ...
            'attack_weights', attackWeights, 'pi_uninformed', -norminv(meanSystem), ...
            'probability_uninformed', meanSystem, 'beta_uninformed', -norminv(meanInitiating));
        residualState.system_beta_uninformed = -norminv(loadProbability);
        residualState.system_pi_uninformed = -norminv(attackWeights*model.response(r, deltas+1)');

        % 2b. Use the composition maximizing the full response under applied load.
        % Individual j points then show that same selected physical composition.
        [~, informedIndex] = max(model.response(r, deltas+1));
        residualState.informed_delta = deltas(informedIndex);
        informed = model.compositions{r, deltas(informedIndex)+1};
        residualState.probability_informed = informed.probability;
        residualState.pi_informed = informed.pi;
        residualState.beta_informed = informed.beta;
        residualState.system_beta_informed = -norminv(loadProbability);
        residualState.system_pi_informed = -norminv(informed.response);
        residualState.annual_beta_uninformed = -norminv(normcdf(-residualState.system_pi_uninformed)*normcdf(-residualState.system_beta_uninformed));
        residualState.annual_beta_informed = -norminv(normcdf(-residualState.system_pi_informed)*normcdf(-residualState.system_beta_informed));
        residual{r} = residualState;
    end
    model.residual = [residual{:}];

    %% 3. Add one- and two-component responses without new simulation files
    % At r=8 the remaining pair can be BB, BD or DD. At r=9 the single
    % capacity has the same law for both materials. Preserve survival itself:
    % at r=9 the complementary extinction probability rounds to one.
    system = daniels_system;
    analyticalRows = cell(0, 7);
    for r = 8:9
        for delta = max(0, r-5):5
            brittle = 5-r+delta;
            ductile = 5-delta;
            survival = daniels.smallSystemSurvival(system, brittle, ductile);
            model.survival_response(r, delta+1) = survival;
            model.response(r, delta+1) = 1-survival;
            analyticalRows(end+1, :) = {r, delta, brittle, ductile, ...
                1-survival, survival, 'analytic-Gaussian-small-system'}; %#ok<AGROW>
        end
    end
    model.analytical_responses = cell2table(analyticalRows, 'VariableNames', ...
        {'r', 'attacked_ductile', 'remaining_brittle', 'remaining_ductile', ...
        'extinction', 'survival', 'source'});

    %% 4. Construct the robustness points shown in Figure 5
    % All series use the same intact reference under the applied load.
    % The second argument is extinction conditional on the labelled damage j.
    % These diagnostic points differ from the aggregate responses in Figures 6-7.
    model.figure5.baseline = exp(-voir.bernoulliKL(p_ref, intact.probability));
    for r = 1:4
        residualState = model.residual(r);
        model.figure5.uninformed{r} = exp(-voir.bernoulliKL(p_ref, residualState.probability_uninformed));
        model.figure5.informed{r} = exp(-voir.bernoulliKL(p_ref, residualState.probability_informed));
    end

    %% 5. Attach the figure palette and calculation conventions
    % Rendering needs only this model and the measured figure layout.
    % The caller adds its calculate_voir result as model.aggregate before
    % passing the completed model to table and figure exporters.
    palette = load(fullfile(root, 'data', 'batlow10.mat'), 'batlow10');
    model.palette = palette.batlow10;
    model.conditioning = 'Prescribed load applied; all initial damage outcomes; fixed intact reference under the same load.';
    model.censoring = 'No numerical pi floor; display limit applied only by the renderer.';
    model.formula_version = daniels.formulaVersion;
    model.probability_definition = 'load-all-damage-v1';
    model.robustness_threshold_pi = [thresholdPi(p_ref, .5), thresholdPi(p_ref, .84)];
end

% Locate the manuscript's robustness category levels on the exact finite-
% reference curve. Figure 1 remains the stated small-reference illustration.
function pi = thresholdPi(reference, robustness)
    % Locate a displayed robustness category on the exact finite-reference
    % curve. Bisection searches extinction probabilities from reference to 1,
    % then converts the result to pi; it does not modify physical responses.
    lower = reference;
    upper = 1;
    target = -log(robustness);
    for iteration = 1:60
        middle = (lower+upper)/2;
        if voir.bernoulliKL(reference, middle) < target
            lower = middle;
        else
            upper = middle;
        end
    end
    pi = -norminv((lower+upper)/2);
end
