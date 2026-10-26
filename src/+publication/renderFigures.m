function renderFigures(model, out)
    %RENDERFIGURES Numerical publication panels and combined figures.
    %
    % Called with the completed publication model and an output folder.
    % Creates figures/ containing individual panels and combined figures.
    % The local helpers control drawing and geometry; physical response
    % mixtures and attack policies have already been calculated.

    %% 1. Read the publication layout
    % All scientific values arrive in model; rendering does not sample or
    % select attacks. layout.json specifies canvas, plot and caption
    % positions in points, separated from the physical calculations.
    folder = fullfile(out, 'figures');
    if ~isfolder(folder)
        mkdir(folder);
    end
    layout = jsondecode(fileread(fullfile(fileparts(mfilename('fullpath')), 'layout.json')));
    assert(any(strcmpi(listfonts, 'Times New Roman')), 'publication:MissingCaptionFont', ...
        'Times New Roman is required for the publication figures.');

    %% 2. Draw individual numerical figures and panels
    % Figure 1: probability/robustness illustration. Figures 3-4: reliability.
    % Figure 5: robustness by knowledge category. Figure 6: VoIR by attack
    % size. Figure 7: attack results on the fixed-reference robustness curve.
    % The drawing functions below explain their individual inputs.
    panels = {'a', 'b', 'c', 'd'};
    exportPanel(1, 'single', @(ax) drawOne(ax), folder, layout, model);
    exportPanel(3, 'single', @(ax) drawReliability(ax, model, 0), folder, layout, model);
    for r = 1:4
        exportPanel(4, panels{r}, @(ax) drawReliability(ax, model, r), folder, layout, model);
        exportPanel(5, panels{r}, @(ax) drawFive(ax, model, r), folder, layout, model);
    end
    exportPanel(6, 'single', @(ax) drawSix(ax, model), folder, layout, model);
    knowledgeSizes = [0, 3, 5, 10];
    for k = 1:4
        exportPanel(7, panels{k}, @(ax) drawSeven(ax, model, knowledgeSizes(k)), folder, layout, model);
    end

    %% 3. Combine the four-panel figures and export them
    % Redraw the same panel functions within the combined canvas. Captions
    % and axes use the measured layout, then exportSet writes PDF/SVG/PNG.
    for fig = [4, 5, 7]
        target = layout.composites([layout.composites.figure] == fig);
        figureHandle = newFigure(target.canvas_points(1), target.canvas_points(2));
        cleanup = onCleanup(@() close(figureHandle));
        captionAxes = axes(figureHandle, 'Units', 'points', 'Position', [0, 0, target.canvas_points(:).'], ...
            'PositionConstraint', 'innerposition', 'Visible', 'off', ...
            'XLim', [0, target.canvas_points(1)], 'YLim', [0, target.canvas_points(2)], ...
            'HandleVisibility', 'off');
        placeAxes(captionAxes, [0, 0, target.canvas_points(:).']);
        for k = 1:4
            ax = axes(figureHandle); %#ok<LAXES> Four independent publication panels.
            if fig == 4
                drawReliability(ax, model, k);
                caption = sprintf('(%s) Attack on {\\it r} = %d component%s.', panels{k}, k, plural(k));
            elseif fig == 5
                drawFive(ax, model, k);
                caption = sprintf('(%s) Attack on {\\it r} = %d component%s.', panels{k}, k, plural(k));
            else
                drawSeven(ax, model, knowledgeSizes(k));
            end
            placeAxes(ax, target.axes_points(k, :));
            if fig == 4
                drawPublicationLegend(ax, model, k, layout);
            end
            captionLayout = target.captions(k);
            if fig == 7
                drawKnowledgeCaption(captionAxes, captionLayout, k, knowledgeSizes(k), layout.caption_glyph_style);
            else
                text(captionAxes, captionLayout.center_x, captionLayout.baseline_y, caption, ...
                    'Interpreter', 'tex', 'FontName', 'Times New Roman', ...
                    'FontSize', captionLayout.font_size, 'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'baseline', 'Clipping', 'off');
            end
        end
        exportSet(figureHandle, fullfile(folder, sprintf('figure%02d', fig)));
        clear cleanup
    end
end

%% Caption placement for knowledge states
% Position Times text and subscripts explicitly to preserve the source baseline.
function drawKnowledgeCaption(ax, captionLayout, k, h, glyphStyle)
    % TeX's automatic subscripts extended below the fixed publication canvas.
    % Keep the Times family and source baseline, placing subscript
    % text explicitly at the font-size and baseline ratios measured in the paper.
    panels = {'a', 'b', 'c', 'd'};
    titles = {'Uninformed attack', 'Partially informed attack', ...
        'Partially informed attack', 'Fully informed attack'};
    % Each row contains text, font angle, size ratio and baseline offset.
    % All offsets use caption font size; horizontal placement uses measured widths.
    parts = {sprintf('(%s) %s ', panels{k}, titles{k}), 'normal', 1, 0; ...
        char(954), 'italic', 1, 0}; % Unicode kappa uses the actual Times italic font.
    subSize = glyphStyle.subscript_size_ratio;
    subDescent = -glyphStyle.subscript_descent_ratio;
    if k == 4
        parts = [parts;{'T', 'normal', subSize, subDescent; char(8801), 'normal', 1, 0; ...
            char(954), 'italic', 1, 0; '10', 'normal', subSize, subDescent}];
    else
        parts = [parts;{sprintf('%d', h), 'normal', subSize, subDescent}];
    end
    parts = [parts;{', ', 'normal', 1, 0; 'h', 'italic', 1, 0; ...
        sprintf('=%d.', h), 'normal', 1, 0}];
    objects = gobjects(size(parts, 1), 1);
    for j = 1:size(parts, 1)
        objects(j) = text(ax, 0, captionLayout.baseline_y+parts{j, 4}*captionLayout.font_size, parts{j, 1}, ...
            'Interpreter', 'none', 'FontName', 'Times New Roman', 'FontAngle', parts{j, 2}, ...
            'FontSize', parts{j, 3}*captionLayout.font_size, 'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'baseline', 'Clipping', 'off');
    end
    drawnow;
    widths = zeros(size(objects));
    for j = 1:numel(objects)
        widths(j) = objects(j).Extent(3);
    end
    left = captionLayout.center_x-sum(widths)/2;
    for j = 1:numel(objects)
        position = objects(j).Position;
        position(1) = left;
        objects(j).Position = position;
        left = left+widths(j);
    end
end

%% Individual-panel export
% Select the measured canvas, draw one panel, place its legend and export it.
function exportPanel(fig, panel, draw, folder, layout, model)
    % fig/panel select one layout entry. draw(ax) adds its plotted contents;
    % this helper supplies the canvas, geometry, filename and export formats.
    target = layout.panels([layout.panels.figure] == fig & strcmp({layout.panels.panel}, panel));
    assert(isscalar(target), 'Each numerical panel needs one publication layout.');
    canvas = target.canvas_points;
    if ismember(fig, [3, 4])
        % The 7.5 tick extends above the original tightly cropped page.
        % Add only top whitespace; keep axes size and position unchanged.
        canvas(2) = canvas(2)+4;
    end
    figureHandle = newFigure(canvas(1), canvas(2));
    cleanup = onCleanup(@() close(figureHandle));
    ax = axes(figureHandle);
    draw(ax);
    placeAxes(ax, target.axes_points);
    if fig == 3 || fig == 4
        if fig == 3
            r = 0;
        else
            r = find(strcmp({'a', 'b', 'c', 'd'}, panel));
        end
        drawPublicationLegend(ax, model, r, layout);
    end
    if strcmp(panel, 'single')
        name = sprintf('figure%02d', fig);
    else
        name = sprintf('figure%02d%s', fig, panel);
    end
    exportSet(figureHandle, fullfile(folder, name));
end

%% Shared canvas and export operations
% The following helpers control geometry and output formats, not scientific data.
function figureHandle = newFigure(w, h)
    % w and h are canvas width and height in typographic points.
    % Select window style before geometry: R2025a+ otherwise starts in a container.
    figureHandle = figure('Visible', 'off', 'WindowStyle', 'normal', 'WindowState', 'normal', ...
        'MenuBar', 'none', 'ToolBar', 'none', 'Color', 'white', 'Units', 'points', ...
        'Position', [1, 1, w, h]);
    setappdata(figureHandle, 'PublicationCanvasPoints', [w, h]);
    drawnow;
    figureHandle.Position = [1, 1, w, h];
    drawnow;
end

function exportSet(figureHandle, stem)
    % stem is an output path without extension. Restore fixed geometry before
    % each export because rendering can change axes and canvas positions.
    canvas = getappdata(figureHandle, 'PublicationCanvasPoints');
    options = {'BackgroundColor', 'white', 'Units', 'points', 'Padding', 'figure', ...
        'Width', canvas(1), 'Height', canvas(2), 'PreserveAspectRatio', 'on'};
    restoreGeometry(figureHandle);
    exportgraphics(figureHandle, [stem, '.pdf'], 'ContentType', 'vector', options{:});
    restoreGeometry(figureHandle);
    exportgraphics(figureHandle, [stem, '.svg'], 'ContentType', 'vector', options{:});
    restoreGeometry(figureHandle);
    exportgraphics(figureHandle, [stem, '.png'], 'Resolution', 180, options{:});
end

function restoreGeometry(figureHandle)
    % Reapply the canvas and inner axes rectangles stored when they were placed.
    canvas = getappdata(figureHandle, 'PublicationCanvasPoints');
    figureHandle.Units = 'points';
    figureHandle.Position = [1, 1, canvas];
    drawnow;
    objects = findall(figureHandle, 'Type', 'axes');
    for k = 1:numel(objects)
        target = getappdata(objects(k), 'PublicationAxesPoints');
        set(objects(k), 'Units', 'points', 'PositionConstraint', 'innerposition', 'Position', target);
    end
    drawnow;
end

function placeAxes(ax, position)
    % position is [left, bottom, width, height] in points. The fixed inner
    % plot rectangle was extracted from the manuscript vector graphic.
    set(ax, 'Units', 'points', 'PositionConstraint', 'innerposition', ...
        'Position', position(:).');
    setappdata(ax, 'PublicationAxesPoints', position(:).');
end

%% Figure 1: the displayed normal-probability relationship
% Plot Phi(pi), the publication category thresholds and their annotations.
function drawOne(ax)
    hold(ax, 'on');
    x = -3:.1:4;
    plot(ax, x, normcdf(x), 'k-', 'LineWidth', .75);
    scatter(ax, [0, 1], [.5, .84], 36, 'k', 'filled', 'MarkerFaceAlpha', .4);
    categories(ax, 4);
    plot(ax, [0, 0, -3], [0, .5, .5], 'k:');
    plot(ax, [1, 1, -3], [0, .84, .84], 'k:');
    text(ax, .2, .25, '$\pi_-$', 'Interpreter', 'latex', 'FontSize', 10, 'HorizontalAlignment', 'center');
    text(ax, 1.2, .5, '$\pi_+$', 'Interpreter', 'latex', 'FontSize', 10, 'HorizontalAlignment', 'center');
    text(ax, -1.5, .55, '$I_{\mathrm{rob},-}$', 'Interpreter', 'latex', 'FontSize', 10, 'HorizontalAlignment', 'center');
    text(ax, -1, .89, '$I_{\mathrm{rob},+}$', 'Interpreter', 'latex', 'FontSize', 10, 'HorizontalAlignment', 'center');
    text(ax, .45, .5, '$(0.0,0.5)$', 'Interpreter', 'latex', 'FontSize', 8, 'HorizontalAlignment', 'center');
    text(ax, 1.5, .84, '$(1.0,0.84)$', 'Interpreter', 'latex', 'FontSize', 8, 'HorizontalAlignment', 'center');
    robustAxes(ax);
end

%% Figures 3-4: initiating and conditional extinction indices
% Each point is (pi,beta) for one damage count j; triangles are system mixtures.
% r=0 draws the intact system. Positive r also draws residual compositions
% and their uninformed/informed series, already computed in modelFromCases.
function drawReliability(ax, model, r)
    hold(ax, 'on');
    colors = model.palette([3, 7], :);
    plot(ax, displayPi(model.intact.pi), model.intact.beta, 'k-', 'LineWidth', .75, 'DisplayName', 'Null action $a_0$');
    scatter(ax, displayPi(model.intact.pi), model.intact.beta, 36, 'k', 'filled', 'MarkerFaceAlpha', .6, 'HandleVisibility', 'off');
    text(ax, displayPi(model.intact.pi)+.1, model.intact.beta+.1, string(1:9), 'Color', 'k', 'FontSize', 10);
    if r>0
        residualState = model.residual(r);
        for k = 1:numel(residualState.deltas)
            if residualState.deltas(k) == residualState.informed_delta
                continue
            end
            % RGBA lines preserve the faint composition overlays in the source.
            plot(ax, displayPi(residualState.pi(k, :)), residualState.beta(k, :), 'Color', [colors(1, :), .2], 'LineWidth', .75, 'HandleVisibility', 'off');
            scatter(ax, displayPi(residualState.pi(k, :)), residualState.beta(k, :), 36, colors(1, :), 'filled', ...
                'MarkerFaceAlpha', .1, 'MarkerEdgeColor', colors(1, :), ...
                'MarkerEdgeAlpha', .1, 'HandleVisibility', 'off');
        end
        plot(ax, displayPi(residualState.pi_uninformed), residualState.beta_uninformed, 'Color', colors(1, :), 'LineWidth', .75, ...
            'DisplayName', 'Uninformed $a(\kappa_0)$');
        scatter(ax, displayPi(residualState.pi_uninformed), residualState.beta_uninformed, 36, colors(1, :), 'filled', ...
            'MarkerFaceAlpha', .6, 'MarkerEdgeColor', colors(1, :), ...
            'MarkerEdgeAlpha', .6, 'HandleVisibility', 'off');
        plot(ax, displayPi(residualState.pi_informed), residualState.beta_informed, 'Color', colors(2, :), 'LineWidth', .75, ...
            'DisplayName', 'Informed $a^{\star}(\kappa_T)$');
        scatter(ax, displayPi(residualState.pi_informed), residualState.beta_informed, 36, colors(2, :), 'filled', ...
            'MarkerFaceAlpha', .6, 'MarkerEdgeColor', colors(2, :), ...
            'MarkerEdgeAlpha', .6, 'HandleVisibility', 'off');
    end
    systemPoint(ax, model.intact.system_pi, model.intact.system_beta, [0, 0, 0]);
    if r>0
        systemPoint(ax, residualState.system_pi_uninformed, residualState.system_beta_uninformed, colors(1, :));
        systemPoint(ax, residualState.system_pi_informed, residualState.system_beta_informed, colors(2, :));
    end
    xlabel(ax, '$\pi$', 'Interpreter', 'latex');
    ylabel(ax, '$\beta$', 'Interpreter', 'latex');
    xlim(ax, [-3, 4]);
    ylim(ax, [3, 7.5]);
    xticks(ax, -3:4);
    yticks(ax, 3:.5:7.5);
    style(ax, 11.5, 1.15);
end

% Add a system-mixture triangle and its formatted (beta,pi) legend label.
function systemPoint(ax, pi, beta, color)
    label = sprintf('$(\\beta,\\pi)=(%.2f,%.2f)$', beta, pi);
    scatter(ax, displayPi(pi), beta, 50, color, '^', 'filled', 'MarkerFaceAlpha', .6, ...
        'MarkerEdgeColor', color, 'MarkerEdgeAlpha', .6, 'DisplayName', label);
end

%% Reliability legend
% Use the already calculated model indices to build labels and symbols.
function drawPublicationLegend(ax, model, r, layout)
    % Fixed source box and uniform row centers avoid release-dependent spacing.
    % Labels and colors are rebuilt from the model; no source artwork is reused.
    target = layout.legends([layout.legends.attack_count] == r);
    assert(isscalar(target), 'Each reliability panel needs one measured legend.');
    box = target.box_relative_to_axes_points(:).';
    box(1:2) = box(1:2)+ax.Position(1:2);
    overlay = axes(ancestor(ax, 'figure'), 'Units', 'points', 'Position', box, ...
        'PositionConstraint', 'innerposition', 'Visible', 'off', ...
        'XLim', [0, box(3)], 'YLim', [0, box(4)], 'NextPlot', 'add', ...
        'HandleVisibility', 'off', 'Tag', 'pubrepPublicationLegend');
    placeAxes(overlay, box);
    patch(overlay, [0, box(3), box(3), 0], [0, 0, box(4), box(4)], 'white', ...
        'EdgeColor', [.9, .9, .9], 'LineWidth', .5, 'Clipping', 'off');
    labels = {'Null action $a_0$'};
    colors = [0, 0, 0];
    values = [model.intact.system_beta, model.intact.system_pi];
    if r>0
        residualState = model.residual(r);
        labels = [labels, {'Uninformed $a(\kappa_0)$', 'Informed $a^{\star}(\kappa_T)$'}];
        colors = [colors;model.palette([3, 7], :)];
        values = [values;residualState.system_beta_uninformed, residualState.system_pi_uninformed; ...
            residualState.system_beta_informed, residualState.system_pi_informed];
    end
    lineCount = numel(labels);
    for k = 1:lineCount
        labels{end+1} = sprintf('$(\\beta,\\pi)=(%.2f,%.2f)$', values(k, 1), values(k, 2)); %#ok<AGROW>
    end
    centers = target.row_centers_points;
    assert(numel(centers) == numel(labels), 'Legend row labels must match the measured layout.');
    token = target.token_x_points;
    for k = 1:numel(labels)
        color = colors(mod(k-1, lineCount)+1, :);
        if k <= lineCount
            plot(overlay, token, centers(k)*[1, 1], '-', 'Color', color, 'LineWidth', .75);
        else
            scatter(overlay, mean(token), centers(k), 50, color, '^', 'filled', ...
                'MarkerFaceAlpha', .6, 'MarkerEdgeColor', color, 'MarkerEdgeAlpha', .6, ...
                'LineWidth', .5, 'Clipping', 'off');
        end
        text(overlay, target.label_x_points, centers(k)-target.text_baseline_offset_points, labels{k}, ...
            'Interpreter', 'latex', 'FontSize', 10, 'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'baseline', 'Clipping', 'off');
    end
end

%% Figure 5: robustness for baseline, uninformed and informed series
% Each category has one point per initiating damage count. Values come from
% model.figure5; shaded regions and close labels follow the manuscript layout.
function drawFive(ax, model, r)
    hold(ax, 'on');
    patch(ax, [-.5, 2.5, 2.5, -.5], [0, 0, .5, .5], 'k', 'EdgeColor', 'none', 'FaceAlpha', .25);
    patch(ax, [-.5, 2.5, 2.5, -.5], [.5, .5, .84, .84], 'k', 'EdgeColor', 'none', 'FaceAlpha', .15);
    patch(ax, [-.5, 2.5, 2.5, -.5], [.84, .84, 1, 1], 'k', 'EdgeColor', 'none', 'FaceAlpha', .05);
    for k = 1:3
        ys = [.25, .67, .92];
        labels = {'Low', 'Medium', 'High'};
        text(ax, -.25, ys(k), labels{k}, 'Rotation', 90, 'HorizontalAlignment', 'center', 'FontSize', 10);
    end
    colors = [0, 0, 0;model.palette([3, 7], :)];
    series = {model.figure5.baseline, model.figure5.uninformed{r}, model.figure5.informed{r}};
    for k = 1:3
        y = series{k};
        x = (k-1)*ones(size(y));
        if k == 1
            scatter(ax, x, y, 36, colors(k, :), 'filled', 'MarkerFaceAlpha', .6);
        else
            scatter(ax, x, y, 36, colors(k, :), 'filled', 'MarkerFaceAlpha', .6, ...
                'MarkerEdgeColor', colors(k, :), 'MarkerEdgeAlpha', .6);
        end
        text(ax, x+.1, y, string(1:numel(y)), 'Color', 'k', 'FontSize', 10);
    end
    xlabel(ax, '$\kappa$', 'Interpreter', 'latex');
    ylabel(ax, '$I_{\mathrm{rob}}$', 'Interpreter', 'latex');
    xlim(ax, [-.5, 2.5]);
    ylim(ax, [0, 1]);
    xticks(ax, 0:2);
    yticks(ax, 0:.1:1);
    xticklabels(ax, {'Baseline', 'Uninformed', 'Informed'});
    style(ax, 10, 1);
end

%% Figure 6: VoIR_D versus attack size for selected knowledge states
% Row h+1 in model.aggregate contains the response for h known identities.
% Every point uses the same intact reference conditional on load and the h=0 comparison.
function drawSix(ax, model)
    hold(ax, 'on');
    attacks = model.aggregate.attack_sizes;
    for h = [1, 3, 5, 7, 10]
        color = knowledgeColor(model, h);
        y = model.aggregate.VoIR_D(h+1, :);
        plot(ax, attacks, y, '-', 'Color', color, 'LineWidth', 1, 'DisplayName', sprintf('$h = %d$', h));
        scatter(ax, attacks, y, 36, color, 'filled', 'MarkerFaceAlpha', .6, ...
            'MarkerEdgeColor', color, 'MarkerEdgeAlpha', .6, 'HandleVisibility', 'off');
    end
    xlabel(ax, '$r$', 'Interpreter', 'latex');
    ylabel(ax, '$\mathrm{VoIR}_{\mathrm{D}}(r|\kappa_h)$', 'Interpreter', 'latex');
    xticks(ax, attacks);
    xlim(ax, [attacks(1)-.1, attacks(end)+.1]);
    style(ax, 11.5, 1);
    legend(ax, 'show', 'Location', 'northwest', 'Interpreter', 'latex', 'FontSize', 9, 'EdgeColor', [.9, .9, .9]);
end

%% Figure 7: robustness versus the extinction-probability index
% The continuous curve uses the exact Bernoulli KL with fixed p_ref.
% The points are the seven optimized attack results at the selected h.
function drawSeven(ax, model, h)
    hold(ax, 'on');
    x = -3:.1:3;
    y = exp(-voir.bernoulliKL(model.p_ref, normcdf(-x)));
    plot(ax, x, y, 'k-', 'LineWidth', .75);
    % r=8,9 lie beyond the displayed pi range and would pile up at its edge.
    % They remain in Figure 6 and the tables; this panel displays r=1,...,7.
    shown = model.aggregate.attack_sizes <= 7;
    attacks = model.aggregate.attack_sizes(shown);
    pi = displayPi(model.aggregate.pi(h+1, shown));
    robust = model.aggregate.robustness(h+1, shown);
    text(ax, pi+.1, robust+linspace(-.02, .02, numel(attacks)), string(attacks), ...
        'Color', 'k', 'Interpreter', 'latex', 'FontSize', 8);
    color = knowledgeColor(model, h);
    scatter(ax, pi, robust, 36, color, 'filled', 'MarkerFaceAlpha', .6, ...
        'MarkerEdgeColor', color, 'MarkerEdgeAlpha', .6);
    thresholds = model.robustness_threshold_pi;
    categories(ax, 3, thresholds);
    plot(ax, [thresholds(1), thresholds(1), -3], [0, .5, .5], 'k:');
    plot(ax, [thresholds(2), thresholds(2), -3], [0, .84, .84], 'k:');
    robustAxes(ax);
    yticks(ax, 0:.2:1);
end

%% Shared category shading, axes and text styling
% These helpers preserve the publication thresholds, ticks, colours and fonts.
function categories(ax, right, thresholds)
    % thresholds gives the two pi boundaries; right is the shading extent.
    % Figure 7 supplies exact finite-reference values, while Figure 1 uses
    % the manuscript approximation at pi=0 and pi=1.
    if nargin < 3
        thresholds = [0, 1]; % Figure 1: small-reference approximation.
    end
    patch(ax, [-3, thresholds(1), thresholds(1), -3], [0, 0, .5, .5], 'k', 'EdgeColor', 'none', 'FaceAlpha', .25);
    patch(ax, [thresholds(1), thresholds(2), thresholds(2), -3, -3, thresholds(1)], [0, 0, .84, .84, .5, .5], 'k', 'EdgeColor', 'none', 'FaceAlpha', .15);
    patch(ax, [thresholds(2), right, right, -3, -3, thresholds(2)], [0, 0, 1, 1, .84, .84], 'k', 'EdgeColor', 'none', 'FaceAlpha', .05);
    text(ax, -1.75, .25, 'Low', 'HorizontalAlignment', 'center', 'FontSize', 8);
    text(ax, -.7, .67, 'Medium', 'HorizontalAlignment', 'center', 'FontSize', 8);
    text(ax, 0, .92, 'High', 'HorizontalAlignment', 'center', 'FontSize', 8);
end

function robustAxes(ax)
    % Apply the shared pi/robustness axes labels and display range.
    xlabel(ax, '$\pi$', 'Interpreter', 'latex');
    ylabel(ax, '$I_{\mathrm{rob}}$', 'Interpreter', 'latex');
    xlim(ax, [-3, 3]);
    ylim(ax, [0, 1]);
    xticks(ax, -3:3);
    yticks(ax, 0:.1:1);
    style(ax, 11.5, 1.15);
end

function c = knowledgeColor(model, h)
    % Return the publication RGB color for h known component identities.
    if h == 10
        c = [0, 0, 0];
    else
        c = model.palette(9-h, :);
    end
end

function style(ax, fontSize, textScale)
    % fontSize sets ticks; textScale adjusts annotations without rescaling
    % axis labels or titles a second time. Fonts and colors match the paper.
    set(ax, 'FontName', 'Times New Roman', 'FontSize', fontSize, 'Box', 'off');
    texts = findall(ax, 'Type', 'text');
    set(texts, 'FontName', 'Times New Roman');
    for k = 1:numel(texts)
        if ~isequal(texts(k), ax.XLabel) && ~isequal(texts(k), ax.YLabel) && ...
                ~isequal(texts(k), ax.ZLabel) && ~isequal(texts(k), ax.Title)
            texts(k).FontSize = texts(k).FontSize*textScale;
        end
    end
end

function suffix = plural(n)
    % Caption suffix for the number of attacked components.
    if n == 1
        suffix = '';
    else
        suffix = 's';
    end
end

% The pi=-3 limit is exclusively a display operation. Numerical probabilities,
% robustness values, VoIR and saved model coordinates are left untouched.
function value = displayPi(value)
    value = max(value, -3);
end
