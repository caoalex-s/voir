function [summary, trace] = collapse(capacities, materials, force)
    %COLLAPSE Redistribute load until elastic components settle or disappear.
    % materials uses 1 for brittle and 2 for ductile. force is the load remaining
    % after contributions from previously yielded ductile components.
    % A second output requests an event history from this same recurrence.
    % An overloaded tie is unresolved and never counted as an outcome.
    %
    % Input capacities and materials are matching vectors for the current
    % elastic set. Forces and capacities use the same unit. summary gives
    % the final state; optional trace lists each break or yield in order.

    %% 1. Define the current elastic set and remaining force
    % capacities contains only the components that are still elastic.
    % Previously broken brittle components carry zero; previously yielded
    % ductile contributions have already been subtracted from force.
    % activeIds keeps each remaining component's original input position.
    validateattributes(force, {'double'}, {'real', 'finite', 'scalar'});
    capacities = reshape(capacities, 1, []);
    materials = reshape(materials, 1, []);
    activeIds = 1:numel(capacities);
    status = 'complete';
    recordEvents = nargout > 1;
    if recordEvents
        initialForce = force;
        events = struct('original_id', {}, 'material', {}, 'capacity', {}, 'share', {}, ...
            'force_before', {}, 'force_after', {}, 'retained_force', {}, ...
            'count_before', {}, 'count_after', {});
        tie = struct('ids', [], 'capacities', [], 'materials', [], 'force', [], 'count', []);
    end

    %% 2. Check equilibrium and remove the weakest overloaded component
    % The current equal share is force / number of elastic components.
    % If every capacity reaches that share, the set is stable. Otherwise,
    % remove its weakest component and recalculate the share. Equality
    % does not trigger failure under the retained strict convention.
    while ~isempty(capacities) && any(capacities < force / numel(capacities))
        weakest = find(capacities == min(capacities));

        % 2a. Keep an overloaded tie unresolved. The original scalar recurrence
        % does not define a supported simultaneous-transition rule here.
        % Do not turn that ambiguity into a counted survival or extinction.
        if numel(weakest) > 1
            status = 'unsupported_overloaded_tie';
            if recordEvents
                tie = struct('ids', activeIds(weakest), 'capacities', capacities, ...
                    'materials', materials, 'force', force, 'count', numel(capacities));
            end
            break
        end

        % 2b. A brittle break leaves all remaining force to the elastic set.
        % A ductile yield retains its capacity as force, so subtract that
        % contribution before the next equal-load redistribution.
        componentCount = numel(capacities);
        forceBefore = force;
        retainedForce = 0;
        if materials(weakest) == 2
            % A yielded ductile component leaves the elastic set but retains
            % its yield force. A broken brittle component retains no force.
            retainedForce = capacities(weakest);
            force = force - retainedForce;
        end
        if recordEvents
            events(end + 1) = struct('original_id', activeIds(weakest), ...
                'material', materials(weakest), 'capacity', capacities(weakest), ...
                'share', forceBefore / componentCount, 'force_before', forceBefore, ...
                'force_after', force, 'retained_force', retainedForce, ...
                'count_before', componentCount, 'count_after', componentCount - 1); %#ok<AGROW>
        end
        capacities(weakest) = [];
        materials(weakest) = [];
        activeIds(weakest) = [];
    end

    %% 3. Classify the settled state
    % The calculation identifies extinction when no elastic component
    % remains. An unresolved state has no classified outcome. Requesting
    % trace also returns each break/yield and its retained force.
    extinct = isempty(capacities);
    if ~strcmp(status, 'complete')
        extinct = []; % An unresolved tie is neither survival nor extinction.
    end
    summary = struct('status', status, 'extinct', extinct, ...
        'remaining_force', force, 'active_ids', activeIds);
    if recordEvents
        trace = struct('status', status, 'extinct', extinct, 'initial_force', initialForce, ...
            'remaining_force', force, 'active_ids', activeIds, ...
            'events', events, 'tie_diagnostic', tie);
    end
end
