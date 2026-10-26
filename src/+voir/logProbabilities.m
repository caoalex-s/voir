function [logExtinction, logSurvival] = logProbabilities(extinction, survival)
    %LOGPROBABILITIES Keep both outcome tails when evaluating logarithms.
    % A supplied small survival probability must not be reconstructed as
    % 1-extinction: extinction may already have rounded to one. Conversely,
    % log1p retains the small correction in the logarithm of a likely event.
    %
    % Used by bernoulliKL and the direct VoIR contrast in aggregateKnowledge.
    % Inputs describe complementary outcomes with compatible array shapes.
    % Outputs are their natural logarithms; exact zero remains minus infinity.

    %% 1. Check the independently retained complementary probabilities
    assert(all(isfinite(extinction) & extinction >= 0 & extinction <= 1, 'all') && ...
        all(isfinite(survival) & survival >= 0 & survival <= 1, 'all') && ...
        all(abs(extinction+survival-1) <= 8*eps, 'all'), ...
        'voir:InvalidProbability', 'Supply consistent extinction and survival probabilities.');
    extinction = extinction+zeros(size(survival));
    survival = survival+zeros(size(extinction));

    %% 2. Evaluate each logarithm using the smaller outcome probability
    logExtinction = log(extinction);
    logSurvival = log(survival);
    useSurvival = extinction > .5;
    logExtinction(useSurvival) = log1p(-survival(useSurvival));
    useExtinction = survival > .5;
    logSurvival(useExtinction) = log1p(-extinction(useExtinction));
end
