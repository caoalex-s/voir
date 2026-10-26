function analysis = aggregateKnowledge(response, p_ref, varargin)
    %AGGREGATEKNOWLEDGE Choose attacks, average over observations, calculate VoIR.
    % Response rows follow AttackSizes. Column delta+1 is the extinction
    % probability after removing delta ductile components. Each row in the
    % returned analysis follows KnowledgeSizes; each column follows AttackSizes.
    %
    % Called by calculate_voir. Inputs condition on the same applied load.
    % Output analysis stores optimized mixtures, KL, robustness and VoIR.
    % policy_details{knowledgeIndex, attackIndex} explains each observation
    % and action. Its candidate columns are known removals, known ductile
    % removals and expected extinction, in that order.

    %% 1. Define the compositions, attack sizes and knowledge states
    % response contains conditional extinction probabilities supplied by
    % the physical model. r is the number attacked, h the number whose
    % identities are observed, and delta the number of ductile removals.
    % The null reference p_ref remains fixed across all these choices.
    parser = inputParser;
    addParameter(parser, 'BrittleCount', 5);
    addParameter(parser, 'DuctileCount', 5);
    addParameter(parser, 'AttackSizes', 1:size(response, 1));
    addParameter(parser, 'KnowledgeSizes', []);
    addParameter(parser, 'SurvivalResponse', []);
    addParameter(parser, 'ReferenceSurvival', 1-p_ref);
    parse(parser, varargin{:});
    parameters = parser.Results;

    %% 2. Check the probability table and its indexing
    % Only feasible removed-material compositions require probabilities.
    % Each output row follows KnowledgeSizes and each column AttackSizes.
    % Include h=0 first because VoIR compares with uninformed knowledge.
    for name = {'BrittleCount', 'DuctileCount'}
        validateattributes(parameters.(name{1}), {'double'}, ...
            {'scalar', 'real', 'integer', 'nonnegative', 'finite', '<=', flintmax});
    end
    brittleCount = parameters.BrittleCount;
    ductileCount = parameters.DuctileCount;
    componentCount = brittleCount + ductileCount;
    assert(componentCount >= 1 && componentCount <= flintmax, ...
        'voir:Composition', 'At least one component is required.');

    attackSizes = reshape(parameters.AttackSizes, 1, []);
    validateattributes(attackSizes, {'double'}, ...
        {'vector', 'nonempty', 'integer', 'finite', '>=', 1, '<=', componentCount});
    assert(numel(unique(attackSizes)) == numel(attackSizes), ...
        'voir:AttackSizes', 'Attack sizes must be unique.');
    knowledgeSizes = parameters.KnowledgeSizes;
    if isempty(knowledgeSizes)
        knowledgeSizes = 0:componentCount;
    end
    validateattributes(knowledgeSizes, {'double'}, ...
        {'vector', 'nonempty', 'integer', 'finite', '>=', 0, '<=', componentCount});
    knowledgeSizes = reshape(knowledgeSizes, 1, []);
    assert(knowledgeSizes(1) == 0 && numel(unique(knowledgeSizes)) == numel(knowledgeSizes), ...
        'voir:KnowledgeSizes', 'KnowledgeSizes must start with 0 and contain unique values.');
    validateattributes(p_ref, {'double'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});
    assert(isa(response, 'double') && isreal(response) ...
        && isequal(size(response), [numel(attackSizes), ductileCount + 1]), ...
        'voir:Response', 'Provide one row per attack size and DuctileCount+1 columns.');
    survivalResponse = parameters.SurvivalResponse;
    if isempty(survivalResponse), survivalResponse = 1-response; end
    assert(isa(survivalResponse, 'double') && isreal(survivalResponse) && ...
        isequal(size(survivalResponse), size(response)), 'voir:Response', ...
        'SurvivalResponse must have the same shape as response.');
    referenceSurvival = parameters.ReferenceSurvival;
    validateattributes(referenceSurvival, {'double'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});
    voir.logProbabilities(p_ref, referenceSurvival);
    for attackIndex = 1:numel(attackSizes)
        r = attackSizes(attackIndex);
        feasibleDuctile = max(0, r - brittleCount):min(r, ductileCount);
        values = response(attackIndex, feasibleDuctile + 1);
        assert(all(isfinite(values) & values >= 0 & values <= 1), ...
            'voir:Response', 'Every feasible composition needs a probability in [0,1].');
        survivalValues = survivalResponse(attackIndex, feasibleDuctile+1);
        voir.logProbabilities(values, survivalValues);
        assert(all(values >= p_ref) && all(survivalValues <= referenceSurvival), 'voir:ObjectiveDomain', ...
            'Extinction maximization represents KL maximization only when all supplied attack probabilities are at least p_ref.');
    end

    %% 3. Select attacks under each knowledge state
    % For every (h,r), enumerate possible observations, choose the attack
    % with highest expected extinction for each observation, then average
    % the selected responses over the observation probabilities.
    rowCount = numel(knowledgeSizes);
    columnCount = numel(attackSizes);
    analysis.probability = zeros(rowCount, columnCount);
    analysis.survival = zeros(rowCount, columnCount);
    analysis.unclipped_probability = zeros(rowCount, columnCount);
    analysis.composition_weights = zeros(rowCount, columnCount, ductileCount + 1);
    analysis.policy = cell(rowCount, columnCount);
    analysis.policy_details = cell(rowCount, columnCount);

    for knowledgeIndex = 1:rowCount
        h = knowledgeSizes(knowledgeIndex);
        for attackIndex = 1:columnCount
            r = attackSizes(attackIndex);
            combinedWeights = zeros(1, ductileCount + 1);
            decisions = [];
            minimumKnownDuctile = max(0, h - brittleCount);
            maximumKnownDuctile = min(h, ductileCount);
            details = cell(1, maximumKnownDuctile - minimumKnownDuctile + 1);

            % 3a. The observation reveals knownDuctile ductile identities among h.
            % Count the ways to observe that composition and divide by all ways
            % to observe h components: this is its hypergeometric probability.
            for knownDuctile = minimumKnownDuctile:maximumKnownDuctile
                observationProbability = nchoosek(ductileCount, knownDuctile) ...
                    * nchoosek(brittleCount, h - knownDuctile) / nchoosek(componentCount, h);
                bestObjective = -Inf;
                bestSurvival = Inf;
                bestWeights = zeros(1, ductileCount + 1);
                selectedAction = [NaN, NaN];
                candidates = zeros(0, 3);
                candidateSurvivals = zeros(0, 1);

                % 3b. An action chooses how many known components to remove and how
                % many of them are ductile. Its remaining removals target unknown
                % identities, whose conditional composition must be averaged out.
                for attackKnown = max(0, r - (componentCount - h)):min(r, h)
                    for attackKnownDuctile = max(0, attackKnown - (h - knownDuctile)):min(attackKnown, knownDuctile)
                        attackUnknown = r - attackKnown;
                        unknownDuctile = ductileCount - knownDuctile;
                        unknownBrittle = brittleCount - h + knownDuctile;
                        compositionWeights = zeros(1, ductileCount + 1);

                        % 3c. Enumerate ductile removals among the unknown identities.
                        % Each count gives delta and a hypergeometric weight. Weight the
                        % corresponding physical response before comparing candidate actions.
                        for removedUnknownDuctile = max(0, attackUnknown - unknownBrittle):min(attackUnknown, unknownDuctile)
                            delta = attackKnownDuctile + removedUnknownDuctile;
                            compositionWeights(delta + 1) = nchoosek(unknownDuctile, removedUnknownDuctile) ...
                                * nchoosek(unknownBrittle, attackUnknown - removedUnknownDuctile) ...
                                / nchoosek(componentCount - h, attackUnknown);
                        end
                        assert(abs(sum(compositionWeights) - 1) < 1e-12);
                        selected = compositionWeights > 0;
                        expectedExtinction = weightedResponse(compositionWeights(selected), ...
                            response(attackIndex, selected));
                        expectedSurvival = weightedResponse(compositionWeights(selected), ...
                            survivalResponse(attackIndex, selected));
                        candidates(end + 1, :) = [attackKnown, attackKnownDuctile, expectedExtinction]; %#ok<AGROW>
                        candidateSurvivals(end+1, 1) = expectedSurvival; %#ok<AGROW>

                        % Compare extinction directly while both candidates are
                        % at most one half; their survival may round to one.
                        % Otherwise compare survival, retaining its small tail
                        % when extinction rounds to one. The objective is unchanged.
                        % Exact ties retain traversal order.
                        if expectedExtinction <= .5 && bestObjective <= .5
                            betterAction = expectedExtinction > bestObjective;
                        else
                            betterAction = expectedSurvival < bestSurvival;
                        end
                        if betterAction
                            bestSurvival = expectedSurvival;
                            bestObjective = expectedExtinction;
                            bestWeights = compositionWeights;
                            selectedAction = [attackKnown, attackKnownDuctile];
                        end
                    end
                end

                % 3d. Weight the selected action by this observation's probability.
                % The result is a mixture of physical outcomes. KL is evaluated after
                % this mixture, because averaging KL would be a different calculation.
                combinedWeights = combinedWeights + observationProbability * bestWeights;
                decisions(end + 1, :) = [knownDuctile, selectedAction, bestObjective]; %#ok<AGROW>
                % Report gaps in the same outcome used to choose the best action.
                if bestObjective <= .5
                    comparisonValues = -candidates(:, 3);
                else
                    comparisonValues = candidateSurvivals;
                end
                rankedValues = sort(comparisonValues, 'ascend');
                objectiveGap = Inf;
                if numel(rankedValues) > 1
                    objectiveGap = rankedValues(2)-rankedValues(1);
                end
                detail = struct('known_ductile', knownDuctile, ...
                    'observation_probability', observationProbability, 'candidates', candidates, ...
                    'selected_action', selectedAction, 'selected_objective', bestObjective, ...
                    'candidate_survival', candidateSurvivals, 'selected_survival', bestSurvival, ...
                    'ties_within_1e12', candidates(abs(comparisonValues-rankedValues(1)) <= 1e-12, 1:2), ...
                    'best_to_second_objective_gap', objectiveGap);
                details{knownDuctile - minimumKnownDuctile + 1} = detail;
            end

            assert(abs(sum(combinedWeights) - 1) < 1e-12);
            combinedWeights = combinedWeights/sum(combinedWeights);
            feasibleDuctile = max(0, r - brittleCount):min(r, ductileCount);

            % 3e. Combine the physical responses with the selected-action weights.
            % Retain the actual mixture. Endpoint limits belong in bernoulliKL;
            % a numerical floor must not change the physical probabilities.
            probability = weightedResponse(combinedWeights(feasibleDuctile + 1), ...
                response(attackIndex, feasibleDuctile + 1));
            assert(probability >= -1e-14 && probability <= 1+1e-14, 'voir:Probability', 'Invalid weighted response.');
            probability = min(max(probability, 0), 1); % Endpoint roundoff only; no interior floor.
            analysis.unclipped_probability(knowledgeIndex, attackIndex) = probability;
            analysis.probability(knowledgeIndex, attackIndex) = probability;
            analysis.survival(knowledgeIndex, attackIndex) = weightedResponse( ...
                combinedWeights(feasibleDuctile+1), survivalResponse(attackIndex, feasibleDuctile+1));
            analysis.composition_weights(knowledgeIndex, attackIndex, :) = reshape(combinedWeights, 1, 1, []);
            analysis.policy{knowledgeIndex, attackIndex} = decisions;
            analysis.policy_details{knowledgeIndex, attackIndex} = [details{:}];
        end
    end

    %% 4. Calculate divergence and entropy-based robustness
    % Use forward Bernoulli KL from the null-action distribution to each
    % post-attack distribution: D_KL(p_ref || p_attack), in nats.
    % I_rob = exp(-D_KL). bernoulliKL spells out both outcome terms.
    % pi = -Phi^(-1)(p_attack) is the plotted extinction-probability index.
    reference = p_ref;
    analysis.pi = -norminv(analysis.probability);
    rareSurvival = analysis.probability > .5;
    analysis.pi(rareSurvival) = norminv(analysis.survival(rareSurvival));
    analysis.KL = voir.bernoulliKL(reference, analysis.probability, referenceSurvival, analysis.survival);
    analysis.robustness = exp(-analysis.KL);

    %% 5. Compare each knowledge state with uninformed knowledge
    % Subtract the h=0 divergence at the same attack size to obtain VoIR_D.
    % VoIR_R = exp(-VoIR_D). No further physical simulation is involved.
    % Evaluate the algebraic difference through log ratios. This avoids
    % subtracting two large KL values, and does not floor either probability.
    [logExtinction, logSurvival] = voir.logProbabilities(analysis.probability, analysis.survival);
    extinctionContrast = reference*(logExtinction(1, :)-logExtinction);
    survivalContrast = referenceSurvival*(logSurvival(1, :)-logSurvival);
    if reference == 0
        extinctionContrast(:) = 0;
    end
    if referenceSurvival == 0
        survivalContrast(:) = 0;
    end
    analysis.VoIR_D = extinctionContrast+survivalContrast;
    % A finite divergence compared with itself gives zero. A true endpoint
    % with two infinite divergences remains undefined, including for h=0.
    analysis.VoIR_D(1, isfinite(analysis.KL(1, :))) = 0;
    analysis.VoIR_R = exp(-analysis.VoIR_D);
    if any(isnan(analysis.VoIR_D), 'all')
        warning('voir:UnresolvedEndpoint', ...
            'A difference of infinite divergences is unresolved. No artificial probability floor was applied.');
    end

    %% 6. Return the indexing and reference beside the results
    % policy_details retains observations, candidate actions and selected
    % actions, so the result can be traced to its decision calculation.
    analysis.knowledge_sizes = knowledgeSizes;
    analysis.attack_sizes = attackSizes;
    analysis.brittle_count = brittleCount;
    analysis.ductile_count = ductileCount;
    analysis.p_ref = p_ref;
    analysis.reference_survival = referenceSurvival;
end

%% Average outcomes without inventing differences between identical responses
function value = weightedResponse(weights, values)
    % Matching vectors contain feasible-composition weights and one outcome
    % probability per composition. Return their scalar weighted response.
    weights = weights/sum(weights);
    % Subtracting a common anchor makes a constant response exactly invariant
    % to the selected material mixture, including the one-component case.
    anchor = min(values);
    value = anchor+sum(weights.*(values-anchor));
end
