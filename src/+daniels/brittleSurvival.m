function survival = brittleSurvival(parameters)
    %BRITTLESURVIVAL Exact conditional survival for a homogeneous brittle bundle.
    % Entry j+1 conditions on j capacities below the initial load share F/N.
    % The calculation uses normal tail probabilities and finite binomial sums,
    % with no capacity sampling. It retains the stated Gaussian strength model.
    %
    % Called when the saved composition has no ductile components.
    % Output survival is a 1-by-(N+1) row for j=0,...,N, including the
    % analytical endpoint outcomes. parameters describes this remaining bundle.

    %% 1. The two endpoint outcomes are known
    N = parameters.n_bars;
    survival = zeros(1, N+1);
    survival(1) = 1;
    initialTail = normcdf(parameters.F/N, parameters.fy, parameters.fy_sd, 'upper');
    assert(initialTail > 0, 'daniels:NumericalTail', 'Initial upper tail underflowed; use a suitable numerical range.');

    %% 2. A brittle bundle survives if enough capacities exceed F/m
    % Given j broken components, N-j capacities are independently above F/N.
    % At each threshold F/m, count how many of those capacities remain above
    % it. At least m such capacities can carry F. Absorb that probability as
    % survival and continue only states that have not yet met this condition.
    for j = 1:N-1
        active = N-j;
        % Entry m+1 holds the unresolved probability of m capacities above
        % the preceding threshold. Index 1 therefore represents zero survivors.
        pendingProbability = zeros(1, active+1);
        pendingProbability(active+1) = 1;
        previousTail = initialTail;
        survivalProbability = 0;
        for required = active:-1:1
            currentTail = normcdf(parameters.F/required, parameters.fy, parameters.fy_sd, 'upper');
            if previousTail == 0
                break
            end
            probabilityAbove = currentTail/previousTail;
            nextPendingProbability = zeros(size(pendingProbability));
            for remaining = 0:active
                if pendingProbability(remaining+1) == 0
                    continue
                end
                for above = 0:remaining
                    mass = pendingProbability(remaining+1)*binopdf(above, remaining, probabilityAbove);
                    if above >= required
                        survivalProbability = survivalProbability+mass;
                    else
                        nextPendingProbability(above+1) = nextPendingProbability(above+1)+mass;
                    end
                end
            end
            pendingProbability = nextPendingProbability;
            previousTail = currentTail;
        end
        survival(j+1) = survivalProbability;
    end
end
