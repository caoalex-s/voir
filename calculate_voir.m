function result = calculate_voir(response, p_ref, varargin)
    %CALCULATE_VOIR Same knowledge/action and robustness calculation as the paper.
    % result=calculate_voir(data) accepts a completed simulate_daniels dataset.
    % result=calculate_voir(response,p_ref,'BrittleCount',3,'DuctileCount',2,...)
    % Response rows follow AttackSizes; column delta+1 is the probability for
    % removing delta ductile components. Infeasible compositions can be NaN.
    % Supply 'SurvivalResponse' and optionally 'ReferenceSurvival' when
    % complementary tails were evaluated directly and must not be rounded away.
    %
    % Output result matrices have rows following KnowledgeSizes and columns
    % following AttackSizes. policy_details retains observations and choices.

    %% 1. Use the common knowledge and robustness calculation
    % This layer takes physical response probabilities as inputs. It does
    % not draw capacities or redistribute load; those belong to Daniels.
    repositoryRoot = fileparts(mfilename('fullpath'));
    previousPath = path;
    restorePath = onCleanup(@() path(previousPath));
    addpath(fullfile(repositoryRoot, 'src'));

    %% 2. Identify the response matrix and null-action reference
    % A completed simulation carries its composition, attack-size order,
    % response matrix and p_ref. Alternatively, supply those explicitly.
    % p_ref is held fixed while the adversary's knowledge and attack vary.
    if nargin == 1&&isstruct(response)
        data = response;
        assert(strcmp(data.status, 'complete'), 'voir:IncompleteData', 'A complete Daniels dataset is required.');
        assert(isfield(data, 'records') && isfield(data, 'tasks'), 'voir:Counts', ...
            'Dataset input requires raw counts. Otherwise supply a probability matrix and matching reference.');
        assert(isfield(data, 'formula_version') && strcmp(data.formula_version, daniels.formulaVersion), ...
            'voir:Formula', 'Counts must use the corrected Daniels force calculation.');
        data = daniels.derive(data); % Refresh the common probability definition from raw counts.

        % 2a. Use the physical definitions saved with this simulation.
        % The called function explains observation weights, action selection,
        % marginalization, KL divergence, robustness and VoIR in that order.
        result = voir.aggregateKnowledge(data.response, data.p_ref, ...
            'BrittleCount', data.system.n_brittle, 'DuctileCount', data.system.n_ductile, ...
            'AttackSizes', data.attack_sizes, ...
            'SurvivalResponse', data.survival_response, 'ReferenceSurvival', data.reference_survival);
    else
        assert(nargin >= 2, 'voir:Reference', 'Supply a response matrix and reference probability.');

        % 2b. Use independently supplied responses with the same framework.
        result = voir.aggregateKnowledge(response, p_ref, varargin{:});
    end
end
