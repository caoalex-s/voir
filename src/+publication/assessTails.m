function assessment = assessTails(cases, info, outputFolder)
    %ASSESSTAILS Bound the effect of missing uncensored saved probabilities.
    % The bounds vary only information lost to the historical pi floor.
    % Uncensored Monte Carlo estimates are held fixed: these are NOT
    % confidence intervals or a claim about population sampling precision.
    %
    % Called only when loadData leaves unresolved case intervals.
    % Inputs cases and info come from that loader. Output assessment and
    % CSV files describe possible responses for r=1,...,7, without filling
    % the missing probabilities with a chosen point value.

    %% 1. Build physical response bounds and keep the intact reference separate
    lower = NaN(7, 6);
    upper = lower;
    for k = 2:numel(cases)
        composition = cases{k};
        lower(composition.r, composition.delta+1) = composition.response_bounds(1);
        upper(composition.r, composition.delta+1) = composition.response_bounds(2);
    end
    reference = cases{1}.response_bounds;
    assert(all(lower(isfinite(lower)) >= reference(2)), 'publication:ObjectiveDomain', ...
        'The probability bounds do not establish the domain for extinction-based attack selection.');

    %% 2. Reoptimize attacks at both physical bounds
    % Maximum expected extinction and observation averaging are monotone in
    % every physical response. Repeating the existing action calculation at
    % both ends therefore bounds the optimized outcome, even if policies change.
    lowerAnalysis = voir.aggregateKnowledge(lower, reference(2));
    upperAnalysis = voir.aggregateKnowledge(upper, reference(1));
    probabilityLower = lowerAnalysis.probability;
    probabilityUpper = upperAnalysis.probability;
    klLower = lowerAnalysis.KL;
    klUpper = upperAnalysis.KL;

    %% 3. Bound VoIR as a direct contrast with its shared reference
    % For q_h >= q_0 >= p_ref, the contrast increases with q_h, decreases
    % with q_0, and decreases with p_ref. Keeping the common reference
    % avoids subtracting two unrelated KL intervals.
    voirLower = zeros(11, 7);
    voirUpper = voirLower;
    for h = 2:11
        for r = 1:7
            if probabilityLower(h, r) > probabilityUpper(1, r)
                voirLower(h, r) = contrast(reference(2), probabilityLower(h, r), probabilityUpper(1, r));
            end
            voirUpper(h, r) = contrast(reference(1), probabilityUpper(h, r), probabilityLower(1, r));
        end
    end
    assert(all(voirLower >= -1e-12 & voirUpper >= voirLower-1e-12, 'all'), ...
        'publication:Bounds', 'Invalid VoIR bounds.');

    %% 4. Export the numerical consequences and the cases needing attention
    [r, h] = meshgrid(1:7, 0:10);
    results = table(h(:), r(:), probabilityLower(:), probabilityUpper(:), ...
        klLower(:), klUpper(:), exp(-klUpper(:)), exp(-klLower(:)), ...
        voirLower(:), voirUpper(:), ...
        'VariableNames', {'h', 'r', 'p_lower', 'p_upper', 'KL_lower', 'KL_upper', ...
        'Irob_lower', 'Irob_upper', 'VoIR_D_lower', 'VoIR_D_upper'});
    results = sortrows(results, {'h', 'r'});
    missing = info.case_table(info.case_table.probability_upper > info.case_table.probability_lower, :);
    missing = sortrows(missing, 'full_response_width', 'descend');
    writetable(results, fullfile(outputFolder, 'saved_probability_bounds.csv'));
    writetable(info.case_table, fullfile(outputFolder, 'initial_damage_cases.csv'));
    writetable(missing, fullfile(outputFolder, 'missing_tail_cases.csv'));

    %% 5. Identify what the saved information can establish
    selectedH = [1, 3, 5, 7, 10];
    possiblePeaks = cell(size(selectedH));
    for k = 1:numel(selectedH)
        row = selectedH(k)+1;
        possiblePeaks{k} = find(voirUpper(row, :) >= max(voirLower(row, :)));
    end
    % A homogeneous ductile system also has a closed-form total response:
    % the sum of N independent Gaussian yield forces is Gaussian. This is
    % a separate physical check, not an inferred uncensored Monte Carlo count.
    analyticRows = cell(0, 4);
    for k = 1:numel(cases)
        composition = cases{k};
        if composition.remaining_brittle == 0
            analyticExtinction = normcdf(info.system.F, composition.n*info.system.fy, sqrt(composition.n)*info.system.fy_sd);
            analyticRows(end+1, :) = {composition.id, analyticExtinction, composition.response_bounds(1), composition.response_bounds(2)}; %#ok<AGROW>
        end
    end
    analytic = cell2table(analyticRows, 'VariableNames', ...
        {'configuration', 'analytic_extinction', 'saved_estimate_lower', 'saved_estimate_upper'});
    writetable(analytic, fullfile(outputFolder, 'homogeneous_ductile_comparison.csv'));
    assessment = struct('kind', 'missing-saved-information-bounds', ...
        'statistical_confidence_intervals', false, 'random_sampling', false, ...
        'reference_bounds', reference, 'unresolved_cases', height(missing), ...
        'selected_knowledge', selectedH, 'possible_peak_attack_sizes', {possiblePeaks}, ...
        'results', results, 'missing_cases', missing, 'homogeneous_ductile', analytic);
    fprintf('Saved-data assessment: %d unresolved initial damage cases; no simulation.\n', height(missing));
    for k = 1:numel(selectedH)
        fprintf('h=%d: possible peak attack sizes from saved-information bounds: %s.\n', selectedH(k), mat2str(possiblePeaks{k}));
    end
end

function value = contrast(reference, informed, uninformed)
    % Direct difference of forward KL divergences with the same reference.
    % All three arguments are extinction probabilities conditional on load.
    assert(informed < 1 && uninformed > 0, 'publication:NumericalTail', ...
        'The saved-data contrast requires resolved interior system probabilities.');
    value = reference*log(uninformed/informed) + ...
        (1-reference)*(log1p(-uninformed)-log1p(-informed));
end
