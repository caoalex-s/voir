function result = sampleTask(task, options, prescribedTrials)
    %SAMPLETASK Count completed outcomes for one initial damage case.
    % Local streams are indexed by task, so scheduling does not change the draws.
    %
    % Called once per catalogue task by simulate. Output result.n counts
    % completed trials and result.k counts extinctions among those trials.
    % An incomplete result retains the stopped trial without counting it.

    %% 1. Fix one physical state and its conditional sampling rule
    % All trials here have the same remaining material counts, initiating
    % damage j and number of yielded ductile components. Only their
    % sampled capacities and resulting collapse outcomes vary.
    configuration = task.configuration;
    damageCase = task.stratum;
    rule = daniels.rule(configuration, damageCase);

    %% 2. Give this task its own capacity sequence
    % A local mrg32k3a stream is selected by seed and task index, so running
    % tasks on different workers does not change their scalar draw order.
    % For prescribed inputs, the same sampler reads supplied numbers.
    identity = struct('requested_trials', options.TrialsPerStratum, ...
        'root_seed', options.Seed, 'substream_index', task.index);
    context = struct('mean', configuration.parameters.fy, 'sd', configuration.parameters.fy_sd);
    if options.prescribed
        mode = 'prescribed';
    else
        mode = 'gaussian';
        context.stream = RandStream('mrg32k3a', 'Seed', options.Seed, 'NormalTransform', 'Inversion');
        context.stream.Substream = task.index;
    end
    sampler = daniels.source(prescribedTrials, identity, mode, context, options.MaxProposalsPerAcceptance);

    %% 3. Initialize extinction and completed-trial counts
    % n is the number of completed trials; k is the number of extinctions.
    % Their ratio estimates the extinction probability for this initial damage case.
    % The composition weight is applied later, not during sampling.
    result = struct('configuration', configuration.id, 'j', damageCase.j, ...
        'source_case_index', damageCase.source_case_index, ...
        'yielded_ductile', damageCase.yielded_ductile, 'weight', damageCase.weight, ...
        'n', 0, 'k', 0, 'status', 'complete', ...
        'consumed_proposals', 0, 'stopped_trial', []);

    %% 4. Sample, redistribute and count each completed outcome
    % trial first samples the conditional capacities and then calls collapse.
    % An unresolved tie or sampling stop is retained for inspection and
    % never counted as either survival or extinction.
    for trialIndex = 1:options.TrialsPerStratum
        sampler.beginTrial(trialIndex);
        outcome = daniels.trial(rule, sampler);
        result.consumed_proposals = result.consumed_proposals + outcome.consumed_proposals;
        if ~strcmp(outcome.status, 'complete')
            result.status = 'incomplete';
            result.stopped_trial = outcome;
            break
        end
        sampler.finishTrial();
        result.n = result.n + 1;
        result.k = result.k + double(outcome.extinct);
    end
end
