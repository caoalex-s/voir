function data = derive(data)
    %DERIVE Combine raw counts under the applied load, without a probability floor.
    %
    % Input data contains aligned records and tasks from simulate.
    % Output data keeps those inputs and adds composition probabilities,
    % response matrices and the intact reference for calculate_voir.
    % No sampling or attack optimization occurs in this aggregation.

    %% 1. Group trials by the remaining material composition
    configurationIds = unique({data.records.configuration}, 'stable');
    compositions = cell(1, numel(configurationIds));
    data.response = NaN(numel(data.attack_sizes), data.system.n_ductile+1);
    data.survival_response = data.response;

    %% 2. Average uncapped estimates within each initial damage count
    % Counts estimate extinction conditional on j and a brittle/ductile split.
    % Hypergeometric weights combine those splits. No inverse-normal transform
    % is needed for this calculation; pi is only a derived plotting coordinate.
    for k = 1:numel(configurationIds)
        indices = find(strcmp({data.records.configuration}, configurationIds{k}));
        configuration = data.tasks(indices(1)).configuration;
        N = configuration.remaining_total;
        conditional = zeros(N-1, 1);
        conditionalSurvival = conditional;
        compositionRecords = data.records(indices);
        for j = 1:N-1
            records = compositionRecords([compositionRecords.j] == j);
            assert(all(isfinite([records.n])) && all([records.n] > 0 & [records.n] == fix([records.n])) && ...
                all([records.k] >= 0 & [records.k] <= [records.n] & [records.k] == fix([records.k])) && ...
                abs(sum([records.weight])-1) < 1e-12, 'daniels:Counts', 'Complete counts and weights are required.');
            % Each split contributes its estimate weighted by its probability.
            % Form survival from surviving counts, retaining small complements.
            splitWeights = [records.weight];
            trialCounts = [records.n];
            extinctionCounts = [records.k];
            conditional(j) = sum(splitWeights.*(extinctionCounts./trialCounts));
            conditionalSurvival(j) = sum(splitWeights.*((trialCounts-extinctionCounts)./trialCounts));
        end

        %% 3. Include j=0 and j=N through the shared probability calculation
        mixture = daniels.combineResponse(configuration.parameters, conditional, conditionalSurvival);
        compositions{k} = struct('configuration', configuration.id, 'attack_r', configuration.attack_r, ...
            'attacked_ductile', configuration.attacked_ductile, 'remaining_brittle', configuration.remaining_brittle, ...
            'remaining_ductile', configuration.remaining_ductile, ...
            'conditional_probability', mixture.conditional_probability_bounds(2:N, 1)', ...
            'initiating_probability', mixture.initiating_probability(2:N), ...
            'all_initiating_probability', mixture.initiating_probability, ...
            'response', mixture.response_bounds(1), 'survival', mixture.survival_bounds(1), ...
            'annual_failure_probability', mixture.annual_failure_bounds(1));
        if configuration.attack_r == 0
            data.p_ref = mixture.response_bounds(1);
            data.reference_survival = mixture.survival_bounds(1);
            data.annual_failure_probability = mixture.annual_failure_bounds(1);
        else
            data.response(data.attack_sizes == configuration.attack_r, configuration.attacked_ductile+1) = mixture.response_bounds(1);
            data.survival_response(data.attack_sizes == configuration.attack_r, configuration.attacked_ductile+1) = mixture.survival_bounds(1);
        end
    end

    %% 4. Record the definition beside the result
    % Both intact and attacked probabilities condition only on applied load.
    % Annual reliability remains a separate result, not the KL reference.
    data.compositions = [compositions{:}];
    data.probability_definition = 'load-all-damage-v1';
    data.conditioning = 'Prescribed load applied; all initial damage outcomes included; same intact reference.';
    data.censoring = 'None in numerical calculations; raw integer counts retained.';
end
