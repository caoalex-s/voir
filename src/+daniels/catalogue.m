function tasks = catalogue(system, attackSizes)
    %CATALOGUE Enumerate compositions and the damage cases requiring simulation.
    %
    % Inputs are the original system definition and requested attack sizes.
    % Output tasks is an ordered structure array. Each task contains a
    % configuration for the remaining composition and a stratum for one
    % initial damage case. The field names retain the saved data format.

    %% 1. Start an ordered list of physical calculations
    % Each task represents one attacked composition, one initiating damage
    % count j, and one split of that damage into brittle and ductile types.
    % The task index also identifies its local simulation substream.
    tasks = struct('index', {}, 'configuration', {}, 'stratum', {});

    %% 2. Remove r components and enumerate their material composition
    % delta of the removed components are ductile; r-delta are brittle.
    % Feasible limits prevent removal of more components than exist.
    % The intact case r=0 precedes the requested attacks.
    for r = [0, reshape(attackSizes, 1, [])]
        for delta = max(0, r-system.n_brittle):min(r, system.n_ductile)
            remainingBrittle = system.n_brittle-r+delta;
            remainingDuctile = system.n_ductile-delta;
            remainingCount = remainingBrittle+remainingDuctile;
            parameters = struct('F', system.F, 'fy', system.fy, 'fy_sd', system.fy_sd, ...
                'fy_cov', system.fy_cov, 'lambda', system.lambda, 'n_bars', remainingCount);
            configuration = struct('id', sprintf('attack_b%d_d%d', r-delta, delta), 'attack_r', r, ...
                'attacked_brittle', r-delta, 'attacked_ductile', delta, ...
                'remaining_brittle', remainingBrittle, 'remaining_ductile', remainingDuctile, 'remaining_total', remainingCount, ...
                'parameters', parameters);

            % 2a. Condition on j initially broken/yielded components under F/N.
            % Given j, the number of yielded ductile components is hypergeometric.
            % Its probability is the weight used when combining trial outcomes.
            % J=0 and J=N are included analytically by combineResponse.
            for j = 1:remainingCount-1
                caseIndex = 0;
                for yieldedDuctile = max(0, j-remainingBrittle):min(j, remainingDuctile)
                    caseIndex = caseIndex+1;
                    failedBrittle = j-yieldedDuctile;
                    weight = hygepdf(yieldedDuctile, remainingCount, remainingDuctile, j);
                    damageCase = struct('j', j, 'failed_brittle', failedBrittle, 'yielded_ductile', yieldedDuctile, ...
                        'case_label', [repmat('B', 1, failedBrittle), repmat('D', 1, yieldedDuctile)], ...
                        'source_case_index', caseIndex, 'weight', weight);
                    tasks(end+1) = struct('index', numel(tasks)+1, 'configuration', configuration, 'stratum', damageCase); %#ok<AGROW>
                end
            end
        end
    end
end
