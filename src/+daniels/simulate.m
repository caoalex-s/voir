function data = simulate(system, tasks, options)
    %SIMULATE Count outcomes; derive conditional responses without running VoIR.
    %
    % Called by simulate_daniels after input validation. tasks comes from
    % catalogue; options holds trial counts, seed and worker settings.
    % Output records and tasks have matching indices, including the intact
    % system. derive adds response matrices only when every task completes.

    %% 1. Associate each physical task with its input sequence
    % Each task is evaluated independently. Only prescribed examples need
    % an explicit cell of proposals; random trials use local task streams.
    prescribedTrials = options.CapacityProposals;
    options = rmfield(options, 'CapacityProposals');
    taskInputs = cell(1, numel(tasks));
    for taskIndex = 1:numel(tasks)
        if options.prescribed
            taskInputs{taskIndex} = prescribedTrials(taskIndex, :);
        else
            taskInputs{taskIndex} = {};
        end
    end

    %% 2. Evaluate the same task calculation serially or in parallel
    % Both branches call sampleTask. Results are kept in catalogue order,
    % so later weighting uses physical identities rather than completion
    % order. A process pool is closed only when this call created it.
    results = cell(1, numel(tasks));
    if options.Workers == 1
        for taskIndex = 1:numel(tasks)
            results{taskIndex} = daniels.sampleTask(tasks(taskIndex), options, taskInputs{taskIndex});
        end
    else
        pool = gcp('nocreate');
        owned = isempty(pool);
        if owned
            cluster = parcluster('Processes');
            cluster.NumWorkers = max(cluster.NumWorkers, options.Workers);
            pool = parpool(cluster, options.Workers);
        else
            assert(isa(pool, 'parallel.ProcessPool')&&pool.NumWorkers >= options.Workers, ...
                'daniels:Pool', 'The existing pool must have at least the requested number of process workers.');
        end
        poolCleanup = onCleanup(@() closeOwnedPool(pool, owned));
        workers = options.Workers;
        parfor (taskIndex = 1:numel(tasks), workers)
            results{taskIndex} = daniels.sampleTask(tasks(taskIndex), options, taskInputs{taskIndex});
        end
    end

    %% 3. Collect raw counts with their physical definitions
    % records stores n completed trials and k extinctions for every task.
    % Keep the seed, task order and parameters beside the counts so a new
    % simulation can be repeated with the same conditional draw sequences.
    data = struct('format', 'daniels-response-v1', 'status', 'incomplete', 'system', system, ...
        'attack_sizes', options.AttackSizes, 'formula_version', daniels.formulaVersion, ...
        'root_seed', options.Seed, 'random_sampling', ~options.prescribed, ...
        'generator_family', 'mrg32k3a', 'normal_transform', 'Inversion', ...
        'trials_per_stratum', options.TrialsPerStratum, 'max_proposals_per_acceptance', options.MaxProposalsPerAcceptance, ...
        'records', [results{:}], 'tasks', tasks, 'response', [], 'p_ref', []);
    if options.prescribed
        data.generator_family = 'prescribed-capacities';
        data.normal_transform = 'not_used';
    end

    %% 4. Combine only complete results into response probabilities
    % derive applies material-split weights and all initial damage weights.
    % It adds the analytical endpoint outcomes without a numerical pi floor. Incomplete data keep their raw counts
    % and stopped state, but have no derived response matrix.
    if all(strcmp({data.records.status}, 'complete'))
        data.status = 'complete';
        data = daniels.derive(data);
    else
        warning('daniels:Incomplete', 'Some initial damage cases stopped. Partial counts are retained; no response matrix was derived.');
    end
end

% Close only the process pool created by this simulation call.
function closeOwnedPool(pool, owned)
    if owned&&~isempty(pool)&&isvalid(pool)
        delete(pool);
    end
end
