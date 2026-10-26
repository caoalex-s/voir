function sampler = source(prescribedTrials, identity, mode, context, proposalLimit)
    %SOURCE Supply scalar capacity draws for one initial damage case.
    % Gaussian mode uses an explicit local RandStream. Prescribed mode reads
    % supplied capacity values, so deterministic checks use no random numbers.
    % sample(count,threshold,side) uses strict inequalities and rejects equality.
    % Only the current trial's proposals are retained, for inspecting a stop.
    %
    % Called by sampleTask. The returned sampler exposes beginTrial,
    % sample, position, finishTrial and inspect as function handles sharing
    % one trial state. Capacity values and thresholds use the load unit.

    %% 1. Choose where capacity proposals come from
    % Gaussian proposals use the task's explicit local stream. Prescribed
    % proposals are supplied for deterministic examples and verification.
    % proposalLimit bounds rejections for each required accepted capacity.
    assert(any(strcmp(mode, {'gaussian', 'prescribed'})), ...
        'daniels:Mode', 'Use gaussian or prescribed capacities.');
    validateattributes(proposalLimit, {'double'}, ...
        {'scalar', 'integer', 'positive', 'finite'});
    isRandom = strcmp(mode, 'gaussian');
    trialCount = identity.requested_trials;
    if isRandom
        assert(isa(context.stream, 'RandStream'), ...
            'daniels:Source', 'An explicit local random stream is required.');
    else
        assert(iscell(prescribedTrials) && numel(prescribedTrials) == trialCount ...
            && isempty(identity.root_seed), ...
            'daniels:Source', 'Provide one capacity sequence per trial and no seed.');
        for inputIndex = 1:trialCount
            prescribedSequence = prescribedTrials{inputIndex};
            validateattributes(prescribedSequence, {'double'}, {'real', 'finite', '2d'});
            assert(isempty(prescribedSequence) || isvector(prescribedSequence), ...
                'daniels:Source', 'Each prescribed sequence must be a vector.');
            prescribedTrials{inputIndex} = reshape(prescribedSequence, 1, []);
        end
    end

    %% 2. Keep the current trial state
    % The returned sampler contains handles to the nested functions below.
    % They share these counters and arrays: this lets trial request scalar
    % draws while keeping rejected proposals available if a trial stops.
    trialIndex = 0;
    proposalCount = 0;
    acceptedCount = 0;
    inputs = [];
    proposals = [];
    standardNormals = [];
    streamStart = [];
    % These initial buffer sizes grow as needed; they do not limit the system.
    acceptedPositions = zeros(1, 16);
    acceptedThresholds = zeros(1, 16);
    acceptedValues = zeros(1, 16);
    acceptedAbove = false(1, 16);

    sampler = struct('beginTrial', @beginTrial, 'sample', @sample, ...
        'position', @position, 'finishTrial', @finishTrial, 'inspect', @inspect);

    %% 3. Begin a trial with empty proposal and acceptance records
    % Reset only the trial records. Gaussian trials continue the same task
    % stream; prescribed trials select the corresponding input sequence.
    function beginTrial(requestedIndex)
        assert(requestedIndex >= 1 && requestedIndex <= trialCount && requestedIndex == fix(requestedIndex), ...
            'daniels:Source', 'Trial index is outside the requested range.');
        trialIndex = requestedIndex;
        proposalCount = 0;
        acceptedCount = 0;
        if isRandom
            proposals = zeros(1, 128);
            standardNormals = zeros(1, 128);
            streamStart = context.stream.State;
        else
            inputs = prescribedTrials{requestedIndex};
            proposals = zeros(1, numel(inputs));
        end
    end

    %% 4. Condition each accepted capacity on its initial state
    % Above-threshold values represent still-elastic components; values
    % below the threshold represent initially yielded ductile components.
    % Reject equality and wrong-side proposals, one scalar draw at a time.
    % positions records where each accepted value occurred in the sequence.
    function [values, positions] = sample(count, threshold, side)
        assert(any(strcmp(side, {'above', 'below'})), ...
            'daniels:Source', 'Choose the above or below conditional sample.');
        above = strcmp(side, 'above');
        values = zeros(1, count);
        positions = zeros(1, count);
        for component = 1:count
            found = false;
            for attempt = 1:proposalLimit
                value = next();
                if (above && value > threshold) || (~above && value < threshold)
                    values(component) = value;
                    positions(component) = proposalCount;
                    acceptedCount = acceptedCount + 1;
                    acceptedPositions(acceptedCount) = proposalCount;
                    acceptedThresholds(acceptedCount) = threshold;
                    acceptedValues(acceptedCount) = value;
                    acceptedAbove(acceptedCount) = above;
                    found = true;
                    break
                end
            end
            if ~found
                error('daniels:SupportProposalLimit', ...
                    'No %s-threshold capacity accepted within %d proposals.', side, proposalLimit);
            end
        end
    end

    %% 5. Generate or read one proposal, then retain it
    % A standard normal draw is scaled by the capacity standard deviation
    % and shifted by the mean. The normal distribution is not truncated
    % except by the conditional acceptance test in sample above.
    function value = next()
        if isRandom
            % Preserve the original scalar normal transform and draw order.
            normalValue = randn(context.stream, 1, 1);
            value = context.mean + context.sd * normalValue;
        else
            assert(proposalCount < numel(inputs), 'daniels:ProviderExhausted', ...
                'The prescribed capacity sequence is exhausted.');
            value = inputs(proposalCount + 1);
        end
        if proposalCount == numel(proposals)
            extra = zeros(1, max(1, numel(proposals)));
            proposals = [proposals, extra];
            if isRandom
                standardNormals = [standardNormals, extra];
            end
        end
        proposalCount = proposalCount + 1;
        proposals(proposalCount) = value;
        if isRandom
            standardNormals(proposalCount) = normalValue;
        end
        assert(isreal(value) && isfinite(value), ...
            'daniels:Draw', 'The capacity transformation produced a nonfinite value.');
    end

    %% 6. Expose the count and check prescribed-input consumption
    % position counts accepted and rejected proposals. finishTrial checks
    % that a prescribed sequence describes exactly one completed trial.
    function count = position()
        count = proposalCount;
    end

    function finishTrial()
        if ~isRandom
            assert(proposalCount == numel(inputs), 'daniels:UnusedProposal', ...
                'A prescribed trial must consume its entire capacity sequence.');
        end
    end

    %% 7. Make a stopped trial explainable
    % Return proposals, accepted values, their thresholds and their order.
    % Gaussian trials also retain the local stream states and normal draws.
    % This is diagnostic information; it does not generate further draws.
    function state = inspect()
        entry = struct('side', '', 'position', 0, 'value', 0, 'threshold', 0);
        accepted = repmat(entry, 1, acceptedCount);
        for acceptedIndex = 1:acceptedCount
            side = 'below';
            if acceptedAbove(acceptedIndex)
                side = 'above';
            end
            accepted(acceptedIndex) = struct('side', side, ...
                'position', acceptedPositions(acceptedIndex), 'value', acceptedValues(acceptedIndex), ...
                'threshold', acceptedThresholds(acceptedIndex));
        end
        state = struct('trial', trialIndex, 'consumed', proposalCount, ...
            'proposals', proposals(1:proposalCount), 'accepted', accepted, ...
            'stream_identity', identity, 'source_mode', mode);
        if isRandom
            state.standard_normal_inputs = standardNormals(1:proposalCount);
            state.stream_start = streamStart;
            state.stream_end = context.stream.State;
        end
    end
end
