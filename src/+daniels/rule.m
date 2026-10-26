function rule = rule(configuration, damageCase)
    %RULE Describe the capacities needed for one conditional Daniels trial.
    % j components have already broken/yielded under the initial equal load F/N.
    % Still-elastic capacities are sampled above that threshold. Only yielded
    % ductile components need below-threshold draws: broken brittle forces are 0.
    %
    % Called by sampleTask. configuration fixes the attacked composition;
    % damageCase fixes the initial brittle breaks and ductile yields.
    % The output records conditional sampling thresholds and retained
    % material identities for trial, without drawing any capacities.

    %% 1. Count the components that remain elastic
    % The attack has already set the remaining composition. The initiating
    % state now removes failed brittle components from the elastic set and
    % moves yielded ductile components to their constant-force state.
    % Material labels 1 and 2 below mean brittle and ductile, respectively.
    elasticBrittle = configuration.remaining_brittle - damageCase.failed_brittle;
    elasticDuctile = configuration.remaining_ductile - damageCase.yielded_ductile;
    materials = [ones(1, elasticBrittle), 2 * ones(1, elasticDuctile)];

    %% 2. State what must be sampled for this conditional trial
    % Elastic capacities must exceed the initial load share F/N.
    % Each initially yielded ductile force must be sampled below F/N;
    % every such force will be subtracted before further redistribution.
    % Broken brittle components contribute zero and require no draw.
    rule = struct('configuration', configuration, 'stratum', damageCase, ...
        'threshold', configuration.parameters.F / configuration.remaining_total, ...
        'elastic_count', numel(materials), 'yielded_ductile_count', damageCase.yielded_ductile, ...
        'materials', materials, 'force', configuration.parameters.F, ...
        'formula_version', daniels.formulaVersion);
end
