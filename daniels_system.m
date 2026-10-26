function system = daniels_system(varargin)
    %DANIELS_SYSTEM Define the same brittle/ductile Daniels model as the paper.
    % system=daniels_system('BrittleCount',3,'DuctileCount',2,'Load',1000)
    % The component count is the sum of the two counts. Load is explicit and is
    % not rescaled when the composition changes. All capacities share one normal
    % distribution and all components have the same elastic stiffness.
    %
    % Input options define material counts, force and the shared capacity law.
    % Output system is a scalar structure passed to simulate_daniels.
    % Load, MeanCapacity and CapacitySD must use the same force unit.

    %% 1. Choose the physical parameters
    % The defaults describe the publication example: five brittle and five
    % ductile components under load F = 2000. MeanCapacity and CapacitySD
    % describe the same Gaussian capacity distribution for both materials.
    % LoadProbability is lambda, the annual probability of load occurrence.
    parser = inputParser;
    addParameter(parser, 'BrittleCount', 5);
    addParameter(parser, 'DuctileCount', 5);
    addParameter(parser, 'Load', 2000);
    addParameter(parser, 'MeanCapacity', 400);
    addParameter(parser, 'CapacitySD', 140);
    addParameter(parser, 'LoadProbability', .001);
    parse(parser, varargin{:});
    parameters = parser.Results;

    %% 2. Check that the system can be defined
    % Counts must be whole numbers; zero permits a homogeneous system.
    % The current simulation interface supports at least two components;
    % it samples intermediate damage cases and adds both endpoints analytically. These checks do not change the load.
    for name = {'BrittleCount', 'DuctileCount'}
        validateattributes(parameters.(name{1}), {'double'}, {'scalar', 'real', 'finite', 'integer', 'nonnegative', '<=', flintmax});
    end
    assert(parameters.BrittleCount+parameters.DuctileCount >= 2&&parameters.BrittleCount+parameters.DuctileCount <= flintmax, ...
        'daniels:Composition', 'At least two components are required.');
    for name = {'Load', 'MeanCapacity', 'CapacitySD'}
        validateattributes(parameters.(name{1}), {'double'}, {'scalar', 'real', 'finite', 'positive'});
    end
    validateattributes(parameters.LoadProbability, {'double'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});

    %% 3. Return the definition used by the calculations
    % n_bars is N; F is the applied load; fy and fy_sd describe capacity.
    % fy_cov is the standard deviation divided by the mean. The returned
    % structure contains parameters only: no samples or VoIR are computed.
    system = struct('n_brittle', parameters.BrittleCount, 'n_ductile', parameters.DuctileCount, ...
        'n_bars', parameters.BrittleCount+parameters.DuctileCount, 'F', parameters.Load, 'fy', parameters.MeanCapacity, ...
        'fy_sd', parameters.CapacitySD, 'fy_cov', parameters.CapacitySD/parameters.MeanCapacity, 'lambda', parameters.LoadProbability);
end
