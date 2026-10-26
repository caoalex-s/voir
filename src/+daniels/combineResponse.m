function result = combineResponse(parameters, conditional, conditionalSurvival)
    %COMBINERESPONSE Include every initial damage outcome under the applied load.
    % conditional has N-1 rows, for j=1,...,N-1, and either one probability
    % column or two columns containing lower/upper bounds. Bounds describe
    % missing saved information, not Monte Carlo confidence intervals.
    %
    % Called by derive and publication.loadData. Material-split averaging
    % has already occurred: row j now conditions only on damage count j.
    % conditionalSurvival has the same shape and preserves the other tail.
    % Output bounds have two entries [lower, upper]; equal entries are a
    % point estimate. Only annual_failure_bounds includes load occurrence.

    %% 1. Calculate the probability of every initial damage count
    N = parameters.n_bars;
    assert(N >= 2 && size(conditional, 1) == N-1 && ismember(size(conditional, 2), [1, 2]), ...
        'daniels:Response', 'Supply one row for each intermediate initial damage count.');
    if size(conditional, 2) == 1
        conditional = [conditional, conditional];
    end
    assert(all(isfinite(conditional), 'all') && all(conditional >= -1e-14 & conditional <= 1+1e-14, 'all') && ...
        all(conditional(:, 1) <= conditional(:, 2)), 'daniels:Response', 'Invalid probability bounds.');
    % Repair only floating-point overshoot of exact endpoints after weighting.
    % This never moves an interior probability away from zero or one.
    conditional = min(max(conditional, 0), 1);

    % Keep supplied survival tails instead of subtracting rounded extinction.
    % Both interval columns are ordered lower, upper.
    if nargin < 3
        conditionalSurvival = 1-fliplr(conditional);
    end
    if size(conditionalSurvival, 2) == 1
        conditionalSurvival = [conditionalSurvival, conditionalSurvival];
    end
    assert(isequal(size(conditionalSurvival), size(conditional)) && ...
        all(isfinite(conditionalSurvival) & conditionalSurvival >= -1e-14 & conditionalSurvival <= 1+1e-14, 'all') && ...
        all(conditionalSurvival(:, 1) <= conditionalSurvival(:, 2)), ...
        'daniels:Response', 'Invalid complementary survival bounds.');
    conditionalSurvival = min(max(conditionalSurvival, 0), 1);
    assert(all(abs(conditional+fliplr(conditionalSurvival)-1) < 1e-12, 'all'), ...
        'daniels:Response', 'Extinction and survival bounds must be complementary.');

    threshold = parameters.F/N;
    initialDamageProbability = normcdf(threshold, parameters.fy, parameters.fy_sd);
    initialElasticProbability = normcdf(threshold, parameters.fy, parameters.fy_sd, 'upper');
    % Evaluate both tails directly. This avoids losing the no-damage event
    % through subtraction when initial damage is almost certain.
    initiatingProbability = zeros(1, N+1);
    for j = 0:N
        initiatingProbability(j+1) = nchoosek(N, j)*initialDamageProbability^j*initialElasticProbability^(N-j);
    end
    assert(abs(sum(initiatingProbability)-1) < 1e-10, 'daniels:Weights', 'Initial damage probabilities must sum to one.');
    initiatingProbability = initiatingProbability/sum(initiatingProbability); % Roundoff only; no event is excluded.

    %% 2. Add the two outcomes that do not require simulation
    % With j=0 every capacity exceeds F/N, so the bundle survives.
    % With j=N every capacity is below F/N. Brittle forces vanish and even
    % the sum of all retained ductile forces is below F, so the bundle fails.
    failure = [0, 0; conditional; 1, 1];
    response = initiatingProbability*failure;
    survival = initiatingProbability*[1, 1; conditionalSurvival; 0, 0];
    assert(all(abs(response+fliplr(survival)-1) < 1e-12), 'daniels:Response', 'Survival and extinction must exhaust the outcomes.');

    %% 3. Keep conditional-on-load and annual quantities distinct
    result = struct('j', 0:N, 'initiating_probability', initiatingProbability, ...
        'conditional_probability_bounds', failure, 'response_bounds', response, ...
        'survival_bounds', survival, ...
        'annual_failure_bounds', parameters.lambda*response, ...
        'definition', 'load-all-damage-v1');
end
