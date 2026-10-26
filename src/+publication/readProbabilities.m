function [conditional, rows, integrations, conditionalSurvival] = readProbabilities(stored, configuration, damageCases)
    %READPROBABILITIES Retain uncensored estimates and evaluate missing tails.
    % Each returned row identifies one initial brittle/ductile damage case.
    % No capped probability is silently used as an uncensored point estimate.
    %
    % Called by loadData for one remaining composition. damageCases gives
    % the catalogue order of initial brittle/ductile splits. conditional
    % and conditionalSurvival have N-1 rows for j=1,...,N-1 and two columns
    % [lower, upper]. rows retains each split before averaging; integrations
    % records diagnostics only for cases evaluated by Gaussian integration.

    %% 1. Read each damage count and its material split
    N = configuration.remaining_total;
    conditional = zeros(N-1, 2);
    conditionalSurvival = zeros(N-1, 2);
    rows = cell(0, 12);
    integrations = struct([]);
    hasCounts = isfield(stored, 'records');
    if hasCounts
        assert(numel(stored.records) == numel(damageCases), 'publication:Counts', 'Unexpected number of labelled count records.');
    end
    for j = 1:N-1
        cases = damageCases([damageCases.j] == j);
        weights = [cases.weight];
        if ~hasCounts
            if ~isfield(stored, 'Prob_c_cell') && numel(cases) == 1
                % Homogeneous legacy pi_vec_1 stores all j, not a split vector.
                savedPi = stored.pi_vec_clust(j);
            elseif isfield(stored, 'pi_cell')
                savedPi = reshape(stored.pi_cell{j}, 1, []);
            elseif isfield(stored, sprintf('pi_vec_%d', j))
                savedPi = reshape(stored.(sprintf('pi_vec_%d', j)), 1, []);
            else
                assert(numel(cases) == 1, 'publication:MissingCases', ...
                    'Individual material-split responses are required for %s, j=%d.', configuration.id, j);
                savedPi = stored.pi_vec_clust(j);
            end
            assert(numel(savedPi) == numel(cases) && ~any(isnan(savedPi)), ...
                'publication:Cases', 'Saved case responses do not match the physical catalogue.');
        end
        for k = 1:numel(cases)
            state = cases(k);
            if hasCounts
                records = stored.records;
                selected = strcmp({records.configuration}, configuration.id) & [records.j] == j & ...
                    [records.yielded_ductile] == state.yielded_ductile;
                assert(nnz(selected) == 1, 'publication:Counts', 'Missing or repeated physical case.');
                record = records(selected);
                trialCount = record.n;
                failures = record.k;
                assert(abs(record.weight-state.weight) < 1e-12, 'publication:Counts', 'Count weight differs from the physical case.');
                validateattributes(trialCount, {'double'}, {'scalar', 'finite', 'integer', 'positive'});
                validateattributes(failures, {'double'}, {'scalar', 'finite', 'integer', '>=', 0, '<=', trialCount});
                lower = failures/trialCount;
                upper = lower;
                source = 'raw-counts';
                survivalBounds = repmat((trialCount-failures)/trialCount, 1, 2);
            else
                trialCount = stored.n_simu;
                validateattributes(trialCount, {'double'}, {'scalar', 'finite', 'integer', 'positive'});
                % The legacy source floors each case at pi=-3 before mixtures.
                % An uncapped saved pi recovers its empirical failure count.
                % A capped value only identifies a range of possible counts.
                if savedPi(k) <= -3+1e-10
                    failures = NaN;
                    lower = ceil(trialCount*normcdf(3))/trialCount;
                    upper = 1;
                    source = 'censored-legacy-count';
                    survivalBounds = [0, 1-lower];
                    activeBrittle = configuration.remaining_brittle-state.failed_brittle;
                    activeDuctile = configuration.remaining_ductile-state.yielded_ductile;
                    active = activeBrittle+activeDuctile;
                    supported = (active <= 2 && state.yielded_ductile <= 5) || ...
                        (active == 3 && state.yielded_ductile == 0);
                    if configuration.remaining_ductile > 0 && supported
                        % Evaluate missing tails from the same Gaussian model.
                        % These are deterministic probabilities, not recovered counts.
                        [survival, calculation] = daniels.conditionalSurvival(configuration.parameters, ...
                            activeBrittle, activeDuctile, state.yielded_ductile);
                        lower = 1-survival;
                        upper = lower;
                        trialCount = NaN;
                        source = 'deterministic-Gaussian-integration';
                        survivalBounds = [survival, survival];
                        calculation.configuration = configuration.id;
                        calculation.j = j;
                        calculation.yielded_ductile = state.yielded_ductile;
                        if isempty(integrations)
                            integrations = calculation;
                        else
                            integrations(end+1) = calculation; %#ok<AGROW>
                        end
                    end
                else
                    reconstructed = trialCount*normcdf(-savedPi(k));
                    failures = round(reconstructed);
                    assert(abs(failures-reconstructed) < 1e-5, 'publication:Counts', ...
                        'Saved probability does not support an integer count at its recorded sample size.');
                    lower = failures/trialCount;
                    upper = lower;
                    source = 'uncensored-legacy-estimate';
                    survivalBounds = repmat((trialCount-failures)/trialCount, 1, 2);
                end
            end
            conditional(j, :) = conditional(j, :)+weights(k)*[lower, upper];
            conditionalSurvival(j, :) = conditionalSurvival(j, :)+weights(k)*survivalBounds;
            rows(end+1, :) = {configuration.id, configuration.attack_r, configuration.attacked_ductile, ...
                j, state.failed_brittle, state.yielded_ductile, trialCount, failures, ...
                weights(k), lower, upper, source}; %#ok<AGROW>
        end
    end

    %% 2. Recover homogeneous brittle tails analytically
    % These saved cases need no new Monte Carlo. Keep their analytic origin
    % explicit; their probabilities are not reconstructed simulation counts.
    if ~hasCounts && configuration.remaining_ductile == 0
        survival = daniels.brittleSurvival(configuration.parameters);
        conditional = repmat((1-survival(2:N))', 1, 2);
        conditionalSurvival = repmat(survival(2:N)', 1, 2);
        for k = 1:size(rows, 1)
            j = rows{k, 4};
            rows{k, 8} = NaN;
            rows{k, 7} = NaN;
            rows{k, 10} = conditional(j, 1);
            rows{k, 11} = conditional(j, 2);
            rows{k, 12} = 'analytic-brittle';
        end
    end
end
