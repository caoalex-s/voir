function data = writeSimulationData(data, folder)
    %WRITESIMULATIONDATA Export regenerated responses and raw counts as MATs.
    %
    % Called by reproduce_publication when SimulationData is supplied.
    % Input data must be a completed paper-system simulation. Output data
    % has its responses refreshed from counts; folder receives one MAT per
    % composition for subsequent reading through loadData.

    %% 1. Use completed simulations of the publication system
    % The general Daniels interface permits other compositions and loads;
    % the publication layout specifically needs the paper system and r=1:7.
    % Rebuild responses from integer counts before exporting them.
    assert(strcmp(data.format, 'daniels-response-v1')&&strcmp(data.status, 'complete')&& ...
        strcmp(data.formula_version, daniels.formulaVersion), ...
        'publication:IncompleteData', 'Completed corrected Daniels data required.');
    assert(isequal(data.system, daniels_system)&&isequal(sort(data.attack_sizes), 1:7), ...
        'publication:System', 'Publication plots require the paper system and all attack sizes 1:7.');
    data = daniels.derive(data); % Rebuild responses from counts; no sampling.
    if ~isfolder(folder)
        mkdir(folder);
    end

    %% 2. Write one MAT per removed-material composition
    % Preserve the publication field names so regenerated and bundled
    % responses follow the same loader. pi and beta are inverse-normal
    % encodings of conditional extinction and initiating probabilities.
    % beta fields keep annual initiating-event coordinates for reliability plots.
    % All-outcome responses and the null reference condition on applied load.
    % records retains raw counts so both saved and fresh data can be rebuilt.
    for k = 1:numel(data.compositions)
        composition = data.compositions(k);
        indices = find(strcmp({data.records.configuration}, composition.configuration));
        records = data.records(indices);
        remainingCount = composition.remaining_brittle+composition.remaining_ductile;
        stored = struct('configuration_id', composition.configuration, 'formula_version', data.formula_version, ...
            'n_bars', remainingCount, 'F', data.system.F, 'fy', data.system.fy, 'fy_sd', data.system.fy_sd, ...
            'fy_cov', data.system.fy_cov, 'lambda', data.system.lambda, ...
            'bar_l', [ones(1, composition.remaining_brittle), 2*ones(1, composition.remaining_ductile)], ...
            'n_simu', data.trials_per_stratum, 'pi_vec_clust', -norminv(composition.conditional_probability), ...
            'beta_star_vec_clust', -norminv(data.system.lambda*composition.initiating_probability), ...
            'pi_tot', -norminv(composition.response), 'beta_tot', -norminv(data.system.lambda), ...
            'annual_failure_probability', composition.annual_failure_probability, 'records', records, ...
            'probability_definition', data.probability_definition, ...
            'root_seed', data.root_seed, 'generator_family', data.generator_family, ...
            'normal_transform', data.normal_transform);

        % 2a. Store the conditional brittle/ductile split weights for each j,
        % then save the structure fields as named MAT variables.
        stored.Prob_c_cell = cell(1, remainingCount-1);
        for j = 1:remainingCount-1
            stored.Prob_c_cell{j} = [records([records.j] == j).weight];
        end
        save(fullfile(folder, [composition.configuration, '.mat']), '-struct', 'stored', '-v7');
    end
end
