function [cases, p_ref, info] = loadData(folder, system)
    %LOADDATA Read saved case evidence and use the shared all-outcome calculation.
    % Legacy capped probabilities are integrated from the same physical model
    % where supported; otherwise their missing-information intervals remain.
    % The loader never substitutes a capped value for missing uncapped data.
    %
    % Called by reproduce_publication and publication_walkthrough.
    % folder contains the 30 publication MAT files; system declares their
    % physical parameters. cases is a cell row with the intact composition
    % first. p_ref conditions on applied load; info describes input sources.

    %% 1. Identify the publication's physical compositions
    assert(system.n_brittle == 5 && system.n_ductile == 5 && system.n_bars == 10, ...
        'publication:Composition', 'Publication figures require five brittle and five ductile components.');
    tasks = daniels.catalogue(system, 1:7);
    configurationIds = unique(arrayfun(@(t)t.configuration.id, tasks, 'UniformOutput', false), 'stable');
    cases = cell(1, numel(configurationIds));
    files = cell(1, numel(configurationIds));
    hasCounts = false(1, numel(configurationIds));
    integrations = cell(1, numel(configurationIds));
    rows = cell(0, 13);

    %% 2. Check each saved physical definition before interpreting probabilities
    for k = 1:numel(configurationIds)
        selected = find(arrayfun(@(t)strcmp(t.configuration.id, configurationIds{k}), tasks));
        configuration = tasks(selected(1)).configuration;
        damageCases = [tasks(selected).stratum];
        files{k} = [configurationIds{k}, '.mat'];
        filename = fullfile(folder, files{k});
        assert(isfile(filename), 'publication:MissingData', 'Missing composition MAT: %s', filename);
        inventory = whos('-file', filename);
        names = {inventory.name};
        wanted = {'n_bars', 'F', 'fy', 'fy_sd', 'fy_cov', 'lambda', 'bar_l', 'n_simu', ...
            'pi_vec_clust', 'beta_star_vec_clust', 'Prob_c_cell', 'pi_cell', ...
            'configuration_id', 'formula_version', 'probability_definition', 'records'};
        wanted = [wanted, names(startsWith(names, 'pi_vec_'))];
        wanted = unique(wanted(ismember(wanted, names)), 'stable');
        stored = load(filename, wanted{:});
        required = {'n_bars', 'F', 'fy', 'fy_sd', 'fy_cov', 'lambda', 'n_simu', 'pi_vec_clust', 'beta_star_vec_clust'};
        assert(all(isfield(stored, required)), 'publication:Fields', 'Missing response fields: %s', filename);
        for name = {'F', 'fy', 'fy_sd', 'fy_cov', 'lambda'}
            assert(isequal(stored.(name{1}), configuration.parameters.(name{1})), 'publication:Parameters', ...
                'Saved %s differs from the declared system in %s.', name{1}, filename);
        end
        N = configuration.remaining_total;
        assert(stored.n_bars == N, 'publication:Composition', 'Wrong remaining component count.');
        if isfield(stored, 'bar_l')
            assert(numel(stored.bar_l) == N && sum(stored.bar_l == 1) == configuration.remaining_brittle && ...
                sum(stored.bar_l == 2) == configuration.remaining_ductile, 'publication:Composition', 'Wrong material composition.');
        else
            assert(configuration.remaining_brittle == 0 || configuration.remaining_ductile == 0, ...
                'publication:Composition', 'Material labels required for a mixed system.');
        end
        if isfield(stored, 'configuration_id')
            assert(strcmp(stored.configuration_id, configuration.id), 'publication:Composition', 'Wrong saved configuration identity.');
        end
        if isfield(stored, 'formula_version')
            assert(strcmp(stored.formula_version, daniels.formulaVersion), 'publication:Formula', 'Corrected force accounting required.');
        end

        %% 3. Recover case estimates or explicit intervals, then combine all j
        if isfield(stored, 'Prob_c_cell')
            assert(iscell(stored.Prob_c_cell) && numel(stored.Prob_c_cell) == N-1, 'publication:Weights', 'Invalid material weights.');
            for j = 1:N-1
                saved = reshape(stored.Prob_c_cell{j}, 1, []);
                expected = [damageCases([damageCases.j] == j).weight];
                assert(numel(saved) == numel(expected) && all(abs(saved-expected) < 1e-12), ...
                    'publication:Weights', 'Material-split order or probabilities differ.');
            end
        end
        [conditional, caseRows, integrations{k}, conditionalSurvival] = publication.readProbabilities(stored, configuration, damageCases);
        mixture = daniels.combineResponse(configuration.parameters, conditional, conditionalSurvival);
        conditional = mixture.conditional_probability_bounds(2:N, :);

        % Legacy beta fields encode annual initiating probabilities. New MATs
        % retain that encoding for Figures 3-4, while their response definition
        % is explicitly load-all-damage-v1.
        beta = reshape(stored.beta_star_vec_clust, 1, []);
        annualInitiating = system.lambda*mixture.initiating_probability(2:N);
        assert(numel(beta) == N-1 && ~any(isnan(beta)) && ...
            all(abs(normcdf(-beta)-annualInitiating) <= 1e-15+1e-10*annualInitiating), ...
            'publication:Weights', 'Saved initiating probabilities differ from the declared model.');
        for row = 1:size(caseRows, 1)
            j = caseRows{row, 4};
            % Columns 9-11 hold the split weight and its probability bounds.
            % Weight the unresolved interval by both levels of the mixture.
            splitWeight = caseRows{row, 9};
            probabilityWidth = caseRows{row, 11}-caseRows{row, 10};
            caseRows{row, 13} = mixture.initiating_probability(j+1)*splitWeight*probabilityWidth;
        end
        rows = [rows; caseRows]; %#ok<AGROW>
        hasCounts(k) = isfield(stored, 'records');
        resolved = all(conditional(:, 1) == conditional(:, 2));
        probability = conditional(:, 1)';
        probability(conditional(:, 1) ~= conditional(:, 2)) = NaN;
        response = NaN;
        if resolved
            response = mixture.response_bounds(1);
        end
        cases{k} = struct('id', configuration.id, 'r', configuration.attack_r, ...
            'delta', configuration.attacked_ductile, 'n', N, ...
            'remaining_brittle', configuration.remaining_brittle, 'remaining_ductile', configuration.remaining_ductile, ...
            'probability', probability, 'probability_bounds', conditional, ...
            'pi', -norminv(probability), 'beta', -norminv(annualInitiating), ...
            'initiating_probability', mixture.initiating_probability, ...
            'annual_initiating_probability', system.lambda*mixture.initiating_probability, ...
            'response', response, 'response_bounds', mixture.response_bounds, ...
            'survival', mixture.survival_bounds(1), ...
            'annual_failure_bounds', mixture.annual_failure_bounds, 'resolved', resolved);
    end

    %% 4. Return evidence availability as well as the reference
    names = {'configuration', 'attack_r', 'attacked_ductile', 'j', 'broken_brittle', 'yielded_ductile', ...
        'trials', 'failures', 'split_weight', 'probability_lower', 'probability_upper', 'source', 'full_response_width'};
    caseTable = cell2table(rows, 'VariableNames', names);
    unresolved = caseTable.probability_lower ~= caseTable.probability_upper;
    p_ref = cases{1}.response;
    info = struct('kind', 'saved-compositions', 'data_folder', folder, 'system', system, ...
        'files', {files}, 'configurations', numel(configurationIds), 'raw_counts_available', all(hasCounts), ...
        'probability_definition', 'load-all-damage-v1', 'case_table', caseTable, ...
        'unresolved_cases', nnz(unresolved), 'reference_bounds', cases{1}.response_bounds, ...
        'tail_integrations', [integrations{~cellfun(@isempty, integrations)}]);
end
