function data = simulate_daniels(system, varargin)
    %SIMULATE_DANIELS Conditional Daniels simulation, separate from VoIR.
    % data=simulate_daniels(system,'TrialsPerStratum',1000,'Seed',1234)
    % data=simulate_daniels(system,...,'AttackSizes',[1,2],'Workers',4)
    % A seed and an explicit trial count are required for random sampling.
    % CapacityProposals supplies a cell array (initial damage cases by trials) for
    % deterministic replay; each cell is the full sequence of capacity proposals.
    %
    % Output data retains one record per initial damage case and, when
    % complete, composition responses for calculate_voir. It does not save
    % files automatically. See docs/USAGE.md for the returned field meanings.

    %% 1. Make the model implementation available
    % src contains the shared mechanics and probability calculations.
    % Restore the caller's search path when this function returns.
    repositoryRoot = fileparts(mfilename('fullpath'));
    previousPath = path;
    restorePath = onCleanup(@() path(previousPath));
    addpath(fullfile(repositoryRoot, 'src'));

    %% 2. Read the physical system and experiment settings
    % Rebuild the parameter structure through daniels_system so that both
    % direct calls and saved definitions use the same input conventions.
    % TrialsPerStratum sets trials per initial damage case: specified numbers
    % of initially broken brittle and yielded ductile components. It is not
    % the total number of trials across all cases.
    assert(isstruct(system)&&isscalar(system), 'daniels:System', 'Use daniels_system to define the system.');
    assert(system.n_bars == system.n_brittle+system.n_ductile, ...
        'daniels:Composition', 'The component count must equal the brittle and ductile counts combined.');
    system = daniels_system('BrittleCount', system.n_brittle, 'DuctileCount', system.n_ductile, ...
        'Load', system.F, 'MeanCapacity', system.fy, 'CapacitySD', system.fy_sd, 'LoadProbability', system.lambda);
    parser = inputParser;
    addParameter(parser, 'TrialsPerStratum', []);
    addParameter(parser, 'Seed', []);
    addParameter(parser, 'AttackSizes', []);
    addParameter(parser, 'Workers', 1);
    addParameter(parser, 'CapacityProposals', {});
    addParameter(parser, 'MaxProposalsPerAcceptance', 1000);
    parse(parser, varargin{:});
    options = parser.Results;
    validateattributes(options.TrialsPerStratum, {'double'}, {'scalar', 'integer', 'positive', '<=', flintmax});
    validateattributes(options.Workers, {'double'}, {'scalar', 'integer', 'positive', 'finite'});
    validateattributes(options.MaxProposalsPerAcceptance, {'double'}, {'scalar', 'integer', 'positive', '<=', flintmax});

    %% 3. List the attacks and initiating states to evaluate
    % r counts removed components. Every composition retains at least two
    % components; J = 1,...,N-1 requires simulation. The two endpoints
    % are included analytically when combining all initial damage outcomes.
    % catalogue also includes the intact system once for the reference.
    if isempty(options.AttackSizes)
        options.AttackSizes = 1:min(7, system.n_bars-2);
    end
    if ~isempty(options.AttackSizes)
        validateattributes(options.AttackSizes, {'double'}, {'vector', 'real', 'finite', 'integer', '>=', 0, '<=', system.n_bars-2});
    end
    options.AttackSizes = reshape(options.AttackSizes, 1, []);
    assert(numel(unique(options.AttackSizes)) == numel(options.AttackSizes), 'daniels:AttackSizes', 'Attack sizes must be unique.');
    options.AttackSizes(options.AttackSizes == 0) = []; % The intact system is always included once.
    tasks = daniels.catalogue(system, options.AttackSizes);

    %% 4. Choose random draws or supplied capacity sequences
    % Normal simulation requires an explicit seed. Prescribed capacities
    % are used to examine the same mechanics without random sampling:
    % rows identify initial damage cases and columns identify trials.
    assert(iscell(options.CapacityProposals), 'daniels:FiniteInputs', 'CapacityProposals must be a cell array.');
    options.prescribed = ~isempty(options.CapacityProposals);
    if options.prescribed
        assert(isempty(options.Seed), 'daniels:FiniteInputs', 'Do not combine prescribed capacities and a random seed.');
        assert(isequal(size(options.CapacityProposals), [numel(tasks), options.TrialsPerStratum]), ...
            'daniels:FiniteInputs', 'CapacityProposals must have one row per initial damage case and one column per trial.');
    else
        validateattributes(options.Seed, {'double'}, {'scalar', 'integer', 'nonnegative', '<=', 2^32-1});
    end

    %% 5. Compute conditional extinction responses
    % simulate counts outcomes, then derive combines their probabilities.
    % The result contains the response matrix and intact reference under load
    % needed by calculate_voir, together with counts and system parameters.
    data = daniels.simulate(system, tasks, options);
end
