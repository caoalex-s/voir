function value = formulaVersion
    %FORMULAVERSION Corrected retained force of initially yielded ductile components.
    %
    % Output is a character label written with counts and checked when
    % loading them. The label identifies the force convention in trial.

    %% 1. Identify the initial ductile-force calculation
    % This label accompanies exported data. It means every initially
    % yielded ductile component retains its sampled force in trial.m.
    % It selects no alternative mechanics and performs no calculation.
    value = 'corrected-ductile-force-v1';
end
