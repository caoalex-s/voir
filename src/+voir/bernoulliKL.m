function divergence = bernoulliKL(p, q, referenceSurvival, survival)
    %BERNOULLIKL Forward divergence from Bernoulli p to Bernoulli q, in nats.
    % Scalar inputs expand to the other argument's shape. A zero probability
    % contributes zero; incompatible certain outcomes give infinite divergence.
    %
    % Used by aggregateKnowledge and the publication robustness panels.
    % p and q are extinction probabilities under the same conditioning.
    % Optional survival inputs retain tails too small to obtain by 1-p or 1-q.

    %% 1. Interpret the two Bernoulli distributions
    % p is the reference extinction probability; q is the compared one.
    % Optional complementary probabilities preserve rare survival outcomes.
    % Without them the defaults are 1-p and 1-q. Input arrays may be
    % compared with a scalar reference by implicit expansion below.
    assert(all(isfinite(p(:)) & p(:) >= 0 & p(:) <= 1) ...
        && all(isfinite(q(:)) & q(:) >= 0 & q(:) <= 1), ...
        'voir:InvalidProbability', 'KL inputs must be finite probabilities.');
    if nargin < 3, referenceSurvival = 1-p; end
    if nargin < 4, survival = 1-q; end
    [logP, logReferenceSurvival] = voir.logProbabilities(p, referenceSurvival);
    [logQ, logSurvival] = voir.logProbabilities(q, survival);
    p = p + zeros(size(q));

    %% 2. Add the survival and extinction contributions
    % D_KL = (1-p) log((1-p)/(1-q)) + p log(p/q).
    % log1p(-p) evaluates log(1-p) accurately when p is small.
    % The two following assignments implement the limit 0*log(0)=0.
    referenceSurvival = referenceSurvival+zeros(size(p));
    survivalTerm = referenceSurvival .* (logReferenceSurvival-logSurvival);
    extinctionTerm = p .* (logP-logQ);
    survivalTerm(referenceSurvival == 0) = 0;
    extinctionTerm(p == 0) = 0;
    divergence = survivalTerm + extinctionTerm;
end
