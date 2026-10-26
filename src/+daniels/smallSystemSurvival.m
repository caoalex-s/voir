function survival = smallSystemSurvival(parameters, brittle, ductile)
    %SMALLSYSTEMSURVIVAL Exact Gaussian responses of one or two components.
    % The prescribed load, identical independent capacities and equal initial
    % stiffness are unchanged. No initial-damage conditioning or sampling is
    % needed: these formulas average over every possible capacity directly.
    %
    % Called by publication.modelFromCases for attack sizes 8 and 9.
    % Output is a scalar survival probability conditional only on load.
    % brittle and ductile count all remaining components, unlike the elastic
    % counts passed to conditionalSurvival after initial damage.

    %% 1. Define the small remaining system and its Gaussian upper tail
    validateattributes([brittle, ductile], {'double'}, ...
        {'vector', 'numel', 2, 'finite', 'integer', 'nonnegative'});
    count = brittle+ductile;
    assert(ismember(count, [1, 2]), 'daniels:SmallSystem', ...
        'The analytical calculation requires one or two remaining components.');
    validateattributes(parameters.F, {'double'}, {'scalar', 'finite', 'positive'});
    validateattributes(parameters.fy, {'double'}, {'scalar', 'finite', 'real'});
    validateattributes(parameters.fy_sd, {'double'}, {'scalar', 'finite', 'positive'});
    tail = @(force) normcdf(force, parameters.fy, parameters.fy_sd, 'upper');

    %% 2. A single component survives if its capacity exceeds the full load
    % Its material identity cannot matter: no redistribution follows a break
    % or yield. Identical capacity distributions therefore give identical
    % survival probabilities for the brittle and ductile cases.
    if count == 1
        survival = tail(parameters.F);
        return
    end

    %% 3. Two brittle components survive by sharing or by one carrying all
    % Either both capacities exceed F/2, or the weaker breaks below F/2 and
    % the stronger exceeds F. The two disjoint events give the expression.
    halfTail = tail(parameters.F/2);
    halfBelow = normcdf(parameters.F/2, parameters.fy, parameters.fy_sd);
    brittleSurvival = halfTail^2+2*halfBelow*tail(parameters.F);

    %% 4. Two ductile capacities add; a mixed pair averages the two cases
    % The ductile sum is normal with twice the mean and sqrt(2) times the SD.
    % For a mixed pair, exchangeability makes the weaker component brittle
    % or ductile with equal probability. These are respectively the brittle
    % and ductile resistance rules, conditional on the ordered capacities.
    ductileSurvival = normcdf(parameters.F, 2*parameters.fy, ...
        sqrt(2)*parameters.fy_sd, 'upper');
    survival = ((2-ductile)*brittleSurvival+ductile*ductileSurvival)/2;
end
