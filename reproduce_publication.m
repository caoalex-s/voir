function [model, report] = reproduce_publication(varargin)
    %REPRODUCE_PUBLICATION Rebuild results or assess unresolved saved probabilities.
    % reproduce_publication                         reads evidence and integrates missing tails
    % reproduce_publication('Render',false)          tables/results only
    % reproduce_publication('SimulationData',data)   uses simulate_daniels output
    %
    % Output model contains physical mixtures and the VoIR analysis.
    % Output report identifies input availability and generated files.
    % This function reads saved data or completed simulation data; it never
    % starts a simulation. docs/METHODS.md maps its stages to the paper.

    %% 1. Locate the data and choose the output
    % This is the callable publication pipeline. For a script with visible
    % intermediate calculations, open publication_walkthrough.m instead.
    % Both use the same response, action-selection and plotting functions.
    repositoryRoot = fileparts(mfilename('fullpath'));
    previousPath = path;
    restorePath = onCleanup(@() path(previousPath));
    addpath(fullfile(repositoryRoot, 'src'));
    parser = inputParser;
    addParameter(parser, 'DataFolder', fullfile(repositoryRoot, 'data', 'publication'), @ischar);
    addParameter(parser, 'SimulationData', [], @(x)isempty(x)||(isstruct(x)&&isscalar(x)));
    addParameter(parser, 'OutputFolder', fullfile(repositoryRoot, 'results', 'publication'), @ischar);
    addParameter(parser, 'Render', true, @(x)islogical(x)&&isscalar(x));
    parse(parser, varargin{:});
    options = parser.Results;
    system = daniels_system;
    outputFolder = options.OutputFolder;
    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    %% 2. Read the updated saved physical responses
    % The default uses the 30 bundled composition MAT files. If a newly
    % simulated paper-system dataset is supplied, first export its counts
    % to that same MAT format, then read it through the same loader.
    % No capacity sampling takes place in either branch.
    if isempty(options.SimulationData)
        [cases, p_ref, inputs] = publication.loadData(options.DataFolder, system);
    else
        assert(ismember('DataFolder', parser.UsingDefaults), 'publication:Inputs', ...
            'Choose either DataFolder or SimulationData.');
        data = publication.writeSimulationData(options.SimulationData, fullfile(outputFolder, 'mat_data'));
        [cases, p_ref, inputs] = publication.loadData(fullfile(outputFolder, 'mat_data'), system);
        inputs.kind = 'regenerated-corrected-counts';
    end

    %% 3. Bound unresolved saved tails before producing point-valued figures
    % Censored legacy inputs are evidence intervals, not final probabilities.
    % Export a useful assessment rather than silently rendering old capped curves.
    if inputs.unresolved_cases > 0
        assessment = publication.assessTails(cases, inputs, outputFolder);
        model = struct('cases', {cases}, 'assessment', assessment);
        report = struct('status', 'needs-tail-data', 'output_directory', outputFolder, ...
            'inputs', inputs, 'rendered', false, 'random_sampling', false, ...
            'assessment', assessment);
        save(fullfile(outputFolder, 'tail_assessment.mat'), 'model', 'report', '-v7');
        fprintf('Final figures not regenerated: resolve missing tails listed in %s.\n', ...
            fullfile(outputFolder, 'missing_tail_cases.csv'));
        return
    end

    %% 4. Combine responses and evaluate adversarial knowledge
    % Assemble the physical response matrix and reliability mixtures first.
    % Add analytical one/two-component results for r=8,9. Calculate VoIR
    % once, then retain that same result for every export.
    model = publication.modelFromCases(repositoryRoot, cases, p_ref);
    model.aggregate = calculate_voir(model.response, p_ref, ...
        'BrittleCount', system.n_brittle, ...
        'DuctileCount', system.n_ductile, ...
        'AttackSizes', model.attack_sizes, ...
        'SurvivalResponse', model.survival_response, ...
        'ReferenceSurvival', model.reference_survival, ...
        'KnowledgeSizes', 0:system.n_bars);

    %% 5. Export the numerical results and their figures
    % Tables contain the plotted coordinates and all 99 (h,r) results.
    % Rendering uses these model values and the publication layout.
    % Illustrative Figure 2 has no calculation and is omitted.
    publication.writeTables(model, outputFolder);
    writetable(inputs.case_table, fullfile(outputFolder, 'initial_damage_cases.csv'));
    if ~isempty(inputs.tail_integrations)
        writetable(struct2table(inputs.tail_integrations), fullfile(outputFolder, 'tail_integration.csv'));
    end
    if options.Render
        publication.renderFigures(model, outputFolder);
    end

    %% 6. Save the model and identify the inputs used
    % results.mat keeps the intermediate model for later inspection.
    % Repeated calls replace generated outputs in the chosen folder.
    report = struct('status', 'complete', 'output_directory', outputFolder, 'inputs', inputs, ...
        'rendered', options.Render, 'random_sampling', false);
    if isempty(options.SimulationData)
        save(fullfile(outputFolder, 'results.mat'), 'model', 'report', '-v7');
    else
        save(fullfile(outputFolder, 'results.mat'), 'model', 'report', 'data', '-v7');
    end
    fprintf('Publication results complete; no new sampling. Outputs: %s\n', outputFolder);
end
