function [survival, calculation] = conditionalSurvival(parameters, brittle, ductile, yielded)
    %CONDITIONALSURVIVAL Integrate the small residual systems in saved tails.
    % brittle and ductile count components still elastic after initial damage.
    % yielded counts initially yielded ductile components. Broken components
    % carry no force. This evaluates the same Gaussian model as trial.m;
    % it does not sample capacities or reconstruct original Monte Carlo counts.
    %
    % Called by publication.readProbabilities for supported capped cases.
    % Output survival is a scalar conditional on the specified initial
    % damage. calculation contains numerical integration diagnostics.
    % parameters.n_bars counts the post-attack bundle before initial damage.

    %% 1. Define the conditional capacities and the supported small systems
    active = brittle+ductile;
    assert((active <= 2 && yielded <= 5) || (active == 3 && yielded == 0), ...
        'daniels:IntegrationRange', 'This integration covers one/two elastic components, or three with no initially yielded components.');
    assert(active >= 1 && all([brittle, ductile, yielded] >= 0) && ...
        all(fix([brittle, ductile, yielded]) == [brittle, ductile, yielded]), ...
        'daniels:IntegrationRange', 'Nonnegative integer component counts are required.');
    threshold = parameters.F/parameters.n_bars;
    initialDamageProbability = normcdf(threshold, parameters.fy, parameters.fy_sd);
    assert(initialDamageProbability > 0 && initialDamageProbability < 1, 'daniels:NumericalTail', 'Initial damage probability must be numerically interior.');
    upperTail = @(x) normcdf(x, parameters.fy, parameters.fy_sd, 'upper');
    density = @(x) normpdf(x, parameters.fy, parameters.fy_sd);

    %% 2. Integrate zero, one or two initially yielded forces directly
    % Still-elastic capacities exceed F/N. Initially yielded forces are below
    % F/N and are all subtracted before redistribution, as in trial.m.
    % A lower integration limit of mean-12*SD omits at most the mass reported
    % below; this is a numerical domain limit, not a truncated strength model.
    omittedMass = yielded*normcdf(-12)/initialDamageProbability;
    if yielded <= 2
        % Each order is the number of Gauss-Legendre nodes per integral.
        % The last two estimates must agree to the relative tolerance below.
        quadratureOrders = [40, 80, 160];
        estimates = zeros(size(quadratureOrders));
        for k = 1:numel(quadratureOrders)
            order = quadratureOrders(k);
            evaluate = @(force) elasticSurvival(force, threshold, brittle, ductile, order, upperTail, density);
            if yielded == 0
                estimates(k) = evaluate(parameters.F);
            else
                [nodes, weights] = gaussRule(order);
                bottom = parameters.fy-12*parameters.fy_sd;
                forces = (threshold+bottom)/2+(threshold-bottom)/2*nodes;
                weights = weights*(threshold-bottom)/2.*density(forces)/initialDamageProbability;
                if yielded == 1
                    estimates(k) = sum(weights.*evaluate(parameters.F-forces));
                else
                    total = 0;
                    for first = 1:order
                        total = total+weights(first)*sum(weights.*evaluate(parameters.F-forces(first)-forces));
                    end
                    estimates(k) = total;
                end
            end
        end
        survival = estimates(end);
        change = abs(estimates(end)-estimates(end-1))/max(survival, realmin);
        method = 'Gauss-Legendre';
        gridLower = NaN;
        gridUpper = NaN;
        negativeMass = NaN;
        assert(change < 2e-9, 'daniels:IntegrationConvergence', 'Direct tail integration did not converge.');
    else
        %% 3. Combine three to five yielded forces by one-dimensional convolution
        % Exact Gaussian bin probabilities define each yielded force. Their
        % convolutions define the sum; midpoint integration then averages the
        % elastic survival probability. Three grid sizes and Richardson
        % extrapolation remove the leading squared-step integration error.
        % bins counts intervals for each initially yielded capacity, not
        % simulation trials. Doubling resolution halves the integration step.
        bins = [4096, 8192, 16384];
        estimates = zeros(size(bins));
        for k = 1:numel(bins)
            [estimates(k), gridLower, gridUpper, negativeMass] = ...
                convolvedSurvival(parameters, threshold, brittle, ductile, yielded, bins(k), upperTail, density);
        end
        extrapolated = (4*estimates(2:3)-estimates(1:2))/3;
        survival = extrapolated(end);
        change = abs(extrapolated(2)-extrapolated(1))/max(survival, realmin);
        method = 'convolution-midpoint-Richardson';
        assert(change < 1e-7 && survival >= gridLower && survival <= gridUpper, ...
            'daniels:IntegrationConvergence', 'Convolved tail integration did not converge.');
    end

    %% 4. Return numerical diagnostics separately from physical probabilities
    % Grid-edge evaluations check discretization using monotonicity in the
    % sum of yielded forces. Convergence differences are numerical checks,
    % not confidence intervals or rigorous bounds on all floating-point error.
    assert(isfinite(survival) && survival >= 0 && survival <= 1, ...
        'daniels:Probability', 'Invalid integrated survival probability.');
    calculation = struct('method', method, 'survival', survival, ...
        'relative_order_change', change, 'omitted_integration_mass_bound', omittedMass, ...
        'grid_lower', gridLower, 'grid_upper', gridUpper, 'fft_negative_mass', negativeMass);
end

%% Survival of the elastic components after subtracting initial ductile forces
function result = elasticSurvival(force, threshold, brittle, ductile, order, tail, density)
    % Remaining force is shared by capacities conditioned to exceed threshold.
    % tail and density describe the common Gaussian capacity law. The result
    % matches the broadcast shape of force and threshold.
    % Match MATLAB's scalar/array expansion before flattening quadrature rows.
    shape = size(force+threshold); %#ok<ELARLOG>
    force = force+zeros(shape);
    threshold = threshold+zeros(shape);
    force = force(:);
    threshold = threshold(:);
    active = brittle+ductile;
    assert(all(force >= active*threshold-1e-10), 'daniels:IntegrationRange', 'Initial conditional force is inconsistent.');
    initialElasticProbability = tail(threshold);

    if active == 1
        % The last elastic component must carry the remaining force.
        value = tail(force)./initialElasticProbability;
    elseif active == 2
        % Both remain elastic, or the weaker component breaks/yields first.
        % A brittle break leaves force unchanged. A ductile yield retains x.
        halfTail = tail(force/2);
        value = halfTail.^2+brittle*(initialElasticProbability-halfTail).*tail(force);
        if ductile > 0
            ductileFirst = integrate(@(x) density(x).*tail(force-x), threshold, force/2, order);
            value = value+ductile*ductileFirst;
        end
        value = value./initialElasticProbability.^2;
    else
        % Condition on the minimum of three elastic capacities. After its
        % transition the other two capacities are independently above x.
        first = @(x) firstTransition(x, force, brittle, ductile, order, tail, density);
        value = (tail(force/3).^3+integrate(first, threshold, force/3, order))./initialElasticProbability.^3;
    end
    result = reshape(value, shape);
end

function value = firstTransition(x, force, brittle, ductile, order, tail, density)
    % Integrand for the weakest of three elastic capacities having value x.
    % Each material count multiplies its possible first transitions. The
    % density factor includes the other two capacities exceeding x.
    remaining = zeros(size(x));
    if brittle > 0
        remaining = remaining+brittle*elasticSurvival(force, x, brittle-1, ductile, order, tail, density);
    end
    if ductile > 0
        remaining = remaining+ductile*elasticSurvival(force-x, x, brittle, ductile-1, order, tail, density);
    end
    value = density(x).*tail(x).^2.*remaining;
end

%% Integrate over a sum of initially yielded ductile forces
function [estimate, lower, upper, negativeMass] = convolvedSurvival(convolutionParameters, threshold, brittle, ductile, yielded, bins, tail, density)
    % Average elastic survival over the sum of independently yielded forces.
    % Midpoints give estimate; bin edges give lower/upper grid bounds for the
    % retained integration domain. negativeMass records FFT roundoff.
    bottom = convolutionParameters.fy-12*convolutionParameters.fy_sd;
    step = (threshold-bottom)/bins;
    edges = linspace(bottom, threshold, bins+1);
    masses = diff(normcdf(edges, convolutionParameters.fy, convolutionParameters.fy_sd))/normcdf(threshold, convolutionParameters.fy, convolutionParameters.fy_sd);
    % The convolution has this many distinct summed-bin positions. Pad
    % the FFT to at least that length to avoid wrapping probability mass.
    count = yielded*(bins-1)+1;
    transformSize = 2^nextpow2(count);
    probabilities = real(ifft(fft(masses, transformSize).^yielded));
    probabilities = probabilities(1:count);
    negativeMass = -sum(probabilities(probabilities < 0));
    assert(negativeMass < 1e-12 && abs(sum(probabilities)-sum(masses)^yielded) < 1e-12, ...
        'daniels:Convolution', 'Excessive convolution roundoff.');
    probabilities = max(probabilities, 0); % Remove only recorded FFT roundoff.
    sums = yielded*(bottom+step/2)+(0:count-1)*step;
    estimate = 0;
    lower = 0;
    upper = 0;
    % Batches of 2048 limit temporary array sizes without changing the grid.
    % Each force value uses 48 nodes for the inner elastic-survival integral.
    for start = 1:2048:count
        indices = start:min(start+2047, count);
        force = convolutionParameters.F-sums(indices);
        evaluate = @(f) elasticSurvival(f, threshold, brittle, ductile, 48, tail, density);
        estimate = estimate+sum(probabilities(indices).*evaluate(force));
        lower = lower+sum(probabilities(indices).*evaluate(force+yielded*step/2));
        upper = upper+sum(probabilities(indices).*evaluate(force-yielded*step/2));
    end
end

%% Gauss-Legendre integration on finite intervals, with reusable nodes
function value = integrate(fn, lower, upper, order)
    % Map the rule on [-1,1] to each interval. Rows are intervals and columns
    % are quadrature nodes; summing columns returns one integral per row.
    [nodes, weights] = gaussRule(order);
    half = (upper(:)-lower(:))/2;
    middle = (upper(:)+lower(:))/2;
    value = half.*sum(fn(middle+half.*nodes).*weights, 2);
end

function [nodes, weights] = gaussRule(order)
    % Return row vectors for Gauss-Legendre integration on [-1,1]. The
    % symmetric tridiagonal eigenproblem gives nodes and weights; caching
    % reuses the same rule across repeated conditional-survival evaluations.
    persistent rules
    if isempty(rules)
        rules = cell(1, 160);
    end
    if isempty(rules{order})
        k = 1:order-1;
        offDiagonal = k./sqrt(4*k.^2-1);
        [vectors, values] = eig(diag(offDiagonal, 1)+diag(offDiagonal, -1));
        [nodes, indices] = sort(diag(values));
        weights = 2*vectors(1, indices).^2;
        rules{order} = {nodes', weights};
    end
    nodes = rules{order}{1};
    weights = rules{order}{2};
end
