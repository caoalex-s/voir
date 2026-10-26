function writeTables(model, outputFolder)
    %WRITETABLES Export actual plotted coordinates and all 99 aggregate responses.
    %
    % Called after model.aggregate has been attached. model contains the
    % same values used by renderFigures. This function writes coordinates,
    % aggregate results and analytical responses, without drawing figures.

    %% 1. Record Figure 1 and the intact reliability coordinates
    % Each row identifies a figure, panel, named series and point, followed
    % by its numerical coordinates and conditioning. display_x records the
    % renderer's pi=-3 boundary separately from the uncapped numerical x.
    % The CSV exposes the values supplied to the renderer.
    rows = cell(0, 14);
    x = -3:0.1:4;
    rows = append(rows, 1, 'single', 'CDF', 'curve', x, normcdf(x), NaN, NaN, NaN, NaN, 'small-baseline approximation');
    rows = append(rows, 1, 'single', 'threshold', 'point', [0, 1], [.5, .84], NaN, NaN, NaN, NaN, 'rounded display thresholds');
    rows = append(rows, 3, 'single', 'intact', 'scenario', model.intact.pi, model.intact.beta, 0, NaN, 1:9, NaN, 'subsequent initiating damage j');
    rows = append(rows, 3, 'single', 'intact', 'system', model.intact.system_pi, model.intact.system_beta, 0, NaN, NaN, NaN, 'all damage outcomes conditional on applied load');

    %% 2. Record reliability and robustness coordinates for Figures 4-5
    % r=1,...,4 identifies the four panels. Scenario points retain j and
    % composition identity; system points retain the probability mixture.
    % Figure 5 also records its first KL argument to make its convention
    % inspectable alongside the plotted robustness value.
    for r = 1:4
        panel = char('a'+r-1);
        residualState = model.residual(r);
        rows = append(rows, 4, panel, 'intact', 'scenario', model.intact.pi, model.intact.beta, 0, NaN, 1:9, NaN, 'subsequent initiating damage j');
        for k = 1:numel(residualState.deltas)
            rows = append(rows, 4, panel, sprintf('composition_delta%d', residualState.deltas(k)), 'scenario', ...
                residualState.pi(k, :), residualState.beta(k, :), r, NaN, 1:(residualState.n-1), NaN, 'conditional physical scenario', residualState.deltas(k) ~= residualState.informed_delta);
        end
        rows = append(rows, 4, panel, 'uninformed', 'scenario', residualState.pi_uninformed, residualState.beta_uninformed, r, 0, 1:(residualState.n-1), NaN, 'Bayes scenario mixture');
        rows = append(rows, 4, panel, 'informed', 'scenario', residualState.pi_informed, residualState.beta_informed, r, 10, 1:(residualState.n-1), NaN, 'composition maximizing the full extinction response');
        rows = append(rows, 4, panel, 'intact', 'system', model.intact.system_pi, model.intact.system_beta, 0, NaN, NaN, NaN, 'all damage outcomes conditional on applied load');
        rows = append(rows, 4, panel, 'uninformed', 'system', residualState.system_pi_uninformed, residualState.system_beta_uninformed, r, 0, NaN, NaN, 'all damage outcomes conditional on applied load');
        rows = append(rows, 4, panel, 'informed', 'system', residualState.system_pi_informed, residualState.system_beta_informed, r, 10, NaN, NaN, 'all damage outcomes conditional on applied load');
        rows = append(rows, 5, panel, 'baseline', 'scenario', zeros(1, 9), model.figure5.baseline, 0, NaN, 1:9, model.p_ref, 'intact conditional-on-load first KL argument');
        rows = append(rows, 5, panel, 'uninformed', 'scenario', ones(1, residualState.n-1), model.figure5.uninformed{r}, r, 0, 1:(residualState.n-1), model.p_ref, 'intact conditional-on-load first KL argument');
        rows = append(rows, 5, panel, 'informed', 'scenario', 2*ones(1, residualState.n-1), model.figure5.informed{r}, r, 10, 1:(residualState.n-1), model.p_ref, 'intact conditional-on-load first KL argument');
    end

    %% 3. Record VoIR and robustness coordinates for Figures 6-7
    % Figure 6 compares selected h at each attack size r. Figure 7 places
    % attack outcomes on the exact robustness curve for the fixed p_ref.
    attacks = model.aggregate.attack_sizes;
    for h = [1, 3, 5, 7, 10]
        rows = append(rows, 6, 'single', sprintf('h%d', h), 'attack', attacks, model.aggregate.VoIR_D(h+1, :), attacks, h, NaN, model.p_ref, model.conditioning);
    end
    knowledgeSizes = [0, 3, 5, 10];
    shown = attacks <= 7; % Figure 7 retains its readable plotted range.
    for k = 1:4
        h = knowledgeSizes(k);
        panel = char('a'+k-1);
        x = -3:.1:3;
        curve = exp(-voir.bernoulliKL(model.p_ref, normcdf(-x)));
        rows = append(rows, 7, panel, 'exact_KL_curve', 'curve', x, curve, NaN, h, NaN, model.p_ref, 'fixed intact reference conditional on applied load');
        rows = append(rows, 7, panel, sprintf('h%d', h), 'attack', model.aggregate.pi(h+1, shown), model.aggregate.robustness(h+1, shown), attacks(shown), h, NaN, model.p_ref, model.conditioning);
    end

    %% 4. Write the coordinate table and all 99 knowledge/attack results
    % aggregate_h_r.csv contains every h=0:10 and r=1:9 combination,
    % including conditional extinction, pi, KL, I_rob and both VoIR forms.
    names = {'figure', 'panel', 'series', 'kind', 'point_index', 'x', 'y', 'attack_r', 'knowledge_h', 'scenario_j', 'first_KL_probability', 'conditioning', 'rendered_as_named_series', 'display_x'};
    writetable(cell2table(rows, 'VariableNames', names), fullfile(outputFolder, 'figure_series.csv'));
    [r, h] = meshgrid(attacks, model.aggregate.knowledge_sizes);
    aggregate = table(h(:), r(:), model.aggregate.probability(:), model.aggregate.pi(:), model.aggregate.KL(:), ...
        model.aggregate.robustness(:), model.aggregate.VoIR_D(:), model.aggregate.VoIR_R(:), model.aggregate.survival(:), ...
        'VariableNames', {'h', 'r', 'p_post', 'pi', 'KL_nats', 'Irob', 'VoIR_D_nats', 'VoIR_R', 'survival_post'});
    aggregate = sortrows(aggregate, {'h', 'r'});
    writetable(aggregate, fullfile(outputFolder, 'aggregate_h_r.csv'));
    writetable(model.analytical_responses, fullfile(outputFolder, 'analytical_responses.csv'));
end

% Store one coordinate per row; expand scalar metadata over a whole series.
function rows = append(rows, fig, panel, series, kind, x, y, r, h, j, p, conditioning, rendered)
    % x/y are matching coordinate vectors. r, h and j identify the physical
    % case; p records the first KL probability where relevant. Scalar metadata
    % applies to every point, and NaN marks a field that does not apply.
    if nargin<13
        rendered = true;
    end
    n = numel(x);
    assert(numel(y) == n);
    r = expand(r, n);
    h = expand(h, n);
    j = expand(j, n);
    p = expand(p, n);
    for k = 1:n
        displayX = x(k);
        if ismember(fig, [3, 4, 7])
            displayX = max(displayX, -3);
        end
        rows(end+1, :) = {fig, panel, series, kind, k, x(k), y(k), r(k), h(k), j(k), p(k), conditioning, rendered, displayX}; %#ok<AGROW>
    end
end

% Repeating scalar metadata lets each coordinate carry its own interpretation.
function v = expand(v, n)
    if isscalar(v)
        v = repmat(v, 1, n);
    end
    assert(numel(v) == n);
end
