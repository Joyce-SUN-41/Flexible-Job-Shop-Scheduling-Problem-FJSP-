function figFiles = convergence_plot(R, varargin)
% convergence_plot  Export convergence-curve and Pareto-front figures for a TEVC-class paper.
%
%   figFiles = convergence_plot(R, 'OutDir', 'figures', 'Tag', 'MK01')
%
% Produces:
%   1. convergence_mean_std.png  - mean +/- std best-makespan trajectory across N runs
%                                  (one line per variant). Requires convergent trajectories
%                                  in R.conv; for 'random' a single point is used.
%   2. pareto_front.png          - if R carries a Pareto set (from a single full LLMAOO run),
%                                  scatter of (makespan, loadUnbalance) non-dominated points.
%
% Figures are written to OutDir and their paths returned. No solver modification.
%
% SAFE / ADDITIVE: visualization only.

    p = inputParser;
    addParameter(p, 'OutDir', 'figures', @ischar);
    addParameter(p, 'Tag', 'exp', @ischar);
    parse(p, varargin{:});
    outDir = p.Results.OutDir;
    tag = p.Results.Tag;
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    figFiles = {};
    variants = fieldnames(R.conv);

    % --- Convergence: thin faint per-run trajectories + bold mean line per variant ---
    % Avoids the "overlapping blob" artefact of stacked translucent fill bands:
    % each run is drawn as a light, semi-transparent line, and the mean is a bold
    % solid line. The legend lists only variant names (English), bold-faced.
    fig = figure('Color', 'w', 'Position', [100 100 640 460]);
    hold on; grid on; box on;
    colors = lines(numel(variants));
    maxLen = 0;
    for c = 1:numel(variants)
        v = variants{c};
        col = colors(c, :);
        traj = R.conv.(v);
        nR = numel(traj);
        L = max(cellfun(@numel, traj));
        maxLen = max(maxLen, L);
        M = NaN(L, nR);
        for i = 1:nR
            t = traj{i}(:).';
            M(1:numel(t), i) = t;
        end
        x = 1:L;
        % Faint individual-run trajectories (skip degenerate single-point baselines).
        if L > 1
            for i = 1:nR
                plot(x, M(:, i), 'Color', col, 'LineWidth', 0.7, ...
                    'HandleVisibility', 'off', 'Marker', 'none');
            end
        end
        mu = nanmean(M, 2);
        if L > 1
            plot(x, mu, 'LineWidth', 2.4, 'Color', col, 'DisplayName', v);
        else
            % Single-point baseline (e.g. random): draw a horizontal reference line.
            yv = mu(1);
            plot([1 maxLen], [yv yv], 'LineWidth', 2.4, 'Color', col, ...
                'LineStyle', '--', 'DisplayName', [v, ' (mean)']);
        end
    end
    xlabel('Generation / Evaluation'); ylabel('Best makespan');
    title(sprintf('Convergence Curve (%s, N=%d independent runs)', tag, R.N));
    legend('Location', 'best', 'FontWeight', 'bold');
    f1 = fullfile(outDir, sprintf('convergence_%s.png', tag));
    saveas(fig, f1); close(fig); figFiles{end+1} = f1;

    % --- Pareto front (if available from a stored run) ---
    if isfield(R, 'pareto') && ~isempty(R.pareto)
        P = R.pareto;
        fig = figure('Color', 'w', 'Position', [100 100 560 420]);
        scatter(P.mk, P.lb, 40, 'filled', 'MarkerFaceColor', [0.2 0.4 0.8]);
        grid on; box on;
        xlabel('Makespan'); ylabel('Load unbalance');
        title(sprintf('Pareto front (%s)', tag));
        f2 = fullfile(outDir, sprintf('pareto_%s.png', tag));
        saveas(fig, f2); close(fig); figFiles{end+1} = f2;
    end
    disp(sprintf('Figures exported: %s', strjoin(figFiles, ', ')));
end
