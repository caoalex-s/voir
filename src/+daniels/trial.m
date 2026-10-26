function result = trial(rule, sampler)
    %TRIAL Draw one conditional state and evaluate the Daniels system.
    % First sample still-elastic capacities above F/N, then initially yielded
    % ductile capacities below F/N. Broken brittle components carry no force.
    %
    % Called by sampleTask with a rule from daniels.rule and a sampler from
    % daniels.source. result.extinct is logical for a completed trial and
    % empty for an unresolved outcome; result.status states which applies.

    %% 1. Prepare one conditional trial
    % rule fixes the initiating state. sampler supplies capacities in the
    % order described below. An empty extinction outcome means the trial
    % did not finish and must not enter a failure-probability estimate.
    result = struct('status', 'not_completed', 'extinct', [], ...
        'consumed_proposals', 0, 'remaining_force', [], 'active_ids', [], ...
        'current_state', [], 'witness', [], 'error_identifier', '', 'error_message', '');
    state = [];
    trace = [];
    try

        % 2. Sample capacities consistent with the initiating damage.
        % Draw every elastic capacity first, then every initially yielded
        % ductile force. This preserves the scalar conditional draw order.
        [elasticCapacities, abovePositions] = sampler.sample( ...
            rule.elastic_count, rule.threshold, 'above');
        [yieldForces, belowPositions] = sampler.sample( ...
            rule.yielded_ductile_count, rule.threshold, 'below');

        % 3. Apply equilibrium before any further redistribution.
        % Yielded ductile components still carry their sampled yield forces.
        % The elastic set therefore carries F minus their sum. Omitting any
        % of those contributions would change the physical system.
        remainingForce = rule.force - sum(yieldForces);
        state = struct('capacities', elasticCapacities, 'materials', rule.materials, ...
            'initial_force', remainingForce, 'initial_ductile_draws', yieldForces, ...
            'above_proposal_positions', abovePositions, 'below_proposal_positions', belowPositions);

        % 4. Redistribute until the elastic set settles or disappears.
        % collapse contains the shared brittle/ductile mechanics. Recording an
        % event history uses that same calculation, without additional draws.
        summary = daniels.collapse(elasticCapacities, rule.materials, remainingForce);
        result.status = summary.status;
        result.extinct = summary.extinct;
        result.remaining_force = summary.remaining_force;
        result.active_ids = summary.active_ids;
        if ~strcmp(summary.status, 'complete')
            % Only a stopped trial needs an event history, from the same kernel.
            [~, trace] = daniels.collapse(elasticCapacities, rule.materials, remainingForce);
        end
    catch exception
        result.status = 'trial_error';
        result.extinct = [];
        result.error_identifier = exception.identifier;
        result.error_message = exception.message;
    end

    %% 5. Return the outcome and retain stopped-trial inputs
    % A completed trial reports survival or extinction. An incomplete
    % trial instead retains its conditional state and capacity sequence
    % so the cause can be inspected without rerunning a random simulation.
    result.consumed_proposals = sampler.position();
    result.current_state = state;
    if ~strcmp(result.status, 'complete')
        result.witness = struct('status', result.status, ...
            'configuration', rule.configuration.id, 'j', rule.stratum.j, ...
            'case_label', rule.stratum.case_label, 'formula_version', rule.formula_version, ...
            'state', state, 'collapse', trace, 'provider_state', sampler.inspect(), ...
            'error_identifier', result.error_identifier, 'error_message', result.error_message);
    end
end
