%% visualize.m — 统一风格可视化（暗色仪表盘）
% 绘制三张图并组合为优雅的仪表盘布局：
%   (1) 收敛曲线：最优值 + 种群均值
%   (2) 甘特图：各机器上的工序块，按工件着色，标注工序号
%   (3) 机器负荷条形图：展示资源利用均衡情况
% 支持导出高分辨率 PNG 到 ./figures。

function visualize(result, dark, exportPNG, dpi)
    if nargin < 2, dark = true; end
    if nargin < 3, exportPNG = true; end
    if nargin < 4, dpi = 150; end
    T = theme(dark);
    prob = result.problem;
    sched = result.schedule;

    figDir = fullfile(pwd, 'figures');
    if exportPNG && ~isfolder(figDir), mkdir(figDir); end

    %% ---------- 图1：收敛曲线 ----------
    % Stage5 E1/E7 量纲标注：本图纵轴为归一化两目标和 trace_best (legacy 0.x 刻度，
    % evaluate.m 作 mk_n+ld_n 加权)，非真实 makespan。真实 makespan 收敛请见
    % viz/plotly_convergence.py / dashboard.py（优先读取 logs/conv_*.json 的
    % trace_makespan；缺失时回退真实 trace_best）。两套量纲不可互换，勿将 0.x 刻度
    % 误读为真实工期。
    fig1 = figure('Color', T.bg, 'Name', 'Convergence', 'Position',[100 100 720 420]);
    ax = axes('Parent', fig1, 'Color', T.bg, 'XColor', T.fg, 'YColor', T.fg);
    hold(ax, 'on');
    plot(ax, result.trace_best, 'Color', T.best, 'LineWidth', 2, ...
         'DisplayName', '最优适应度');
    plot(ax, result.trace_mean, 'Color', T.accent2, 'LineWidth', 1.4, ...
         'LineStyle', '--', 'DisplayName', '种群均值');
    grid(ax, 'on'); ax.GridColor = T.grid; ax.GridAlpha = 1;
    ax.FontName = T.font; ax.FontSize = T.fontsize;
    ax.Title.String = '收敛曲线 (两目标和)'; ax.Title.Color = T.fg;
    ax.Title.FontSize = T.title_size; ax.Title.FontWeight = 'bold';
    xlabel(ax, '迭代代数', 'Color', T.muted);
    ylabel(ax, '归一化适应度', 'Color', T.muted);
    legend(ax, 'Location', 'northeast', 'TextColor', T.fg, ...
           'Color', T.panel, 'EdgeColor', T.grid, 'FontWeight', 'bold');
    if exportPNG, exportgraphics(fig1, fullfile(figDir, 'convergence.png'), 'Resolution', dpi); end

    %% ---------- 图2：甘特图 ----------
    fig2 = figure('Color', T.bg, 'Name', 'Gantt', 'Position',[50 50 1500 900]);
    ax = axes('Parent', fig2, 'Color', T.bg, 'XColor', T.fg, 'YColor', T.fg, ...
              'Position', [0.05 0.10 0.80 0.84]);   % 放大绘图区，减少边距
    hold(ax, 'on');
    nMach = prob.nMachine;
    for t = 1:length(sched)
        s = sched(t);
        y = nMach - s.machine + 0.5;          % 机器在纵轴自下而上
        x = [s.start, s.duration];
        col = T.cmap(mod(s.job-1, size(T.cmap,1)) + 1, :);
        rectangle(ax, 'Position', [x(1), y-0.38, x(2), 0.76], ...
                  'FaceColor', col, 'EdgeColor', T.bg, 'LineWidth', 0.8);
        txt = sprintf('J%d-%d', s.job, s.op);
        text(ax, s.start + x(2)/2, y, txt, ...
             'Color', T.fg, 'FontSize', 8, 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    end
    grid(ax, 'on'); ax.GridColor = T.grid; ax.GridAlpha = 0.6;
    ax.FontName = T.font; ax.FontSize = T.fontsize;
    ax.YLim = [0.2 nMach + 0.8];
    ax.YTick = (1:nMach) + 0.5;                 % 递增，才能被 YTick 接受
    ax.YTickLabel = arrayfun(@(m) sprintf('M%d', m), nMach:-1:1, 'Uniform', false);
    ax.Title.String = sprintf('最优调度甘特图 | Makespan = %.1f', result.makespan);
    ax.Title.Color = T.fg; ax.Title.FontSize = T.title_size; ax.Title.FontWeight = 'bold';
    xlabel(ax, '时间', 'Color', T.muted);
    ylabel(ax, '机器', 'Color', T.muted);
    % 图例（工件色板）
    lg = gobjects(prob.nJob, 1);
    for j = 1:prob.nJob
        col = T.cmap(mod(j-1, size(T.cmap,1)) + 1, :);
        lg(j) = plot(ax, NaN, NaN, 'o', 'MarkerFaceColor', col, ...
                     'MarkerEdgeColor', col, 'MarkerSize', 8);
    end
    legend(ax, lg, arrayfun(@(j) sprintf('工件%d', j), 1:prob.nJob, 'Uniform', false), ...
           'Location', 'eastoutside', 'TextColor', T.fg, ...
           'Color', T.panel, 'EdgeColor', T.grid, 'FontWeight', 'bold');
    if exportPNG, exportgraphics(fig2, fullfile(figDir, 'gantt.png'), 'Resolution', dpi); end

    %% ---------- 图3：机器负荷 ----------
    fig3 = figure('Color', T.bg, 'Name', 'MachineLoad', 'Position',[100 100 720 420]);
    ax = axes('Parent', fig3, 'Color', T.bg, 'XColor', T.fg, 'YColor', T.fg);
    hold(ax, 'on');
    bars = bar(ax, result.loadVec, 'FaceColor', T.accent, 'EdgeColor', T.bg);
    bars.FaceColor = T.accent;
    grid(ax, 'on'); ax.GridColor = T.grid; ax.GridAlpha = 1;
    ax.FontName = T.font; ax.FontSize = T.fontsize;
    ax.Title.String = '机器负荷分布 | Machine Load';
    ax.Title.Color = T.fg; ax.Title.FontSize = T.title_size; ax.Title.FontWeight = 'bold';
    xlabel(ax, '机器', 'Color', T.muted);
    ylabel(ax, '负荷(总工时)', 'Color', T.muted);
    meanL = mean(result.loadVec);
    yline(ax, meanL, '--', sprintf('均值 %.1f', meanL), ...
          'Color', T.accent2, 'LineWidth', 1.4, 'FontSize', T.fontsize, 'FontWeight', 'bold');
    if exportPNG, exportgraphics(fig3, fullfile(figDir, 'machine_load.png'), 'Resolution', dpi); end

    %% ---------- 阶段5 增强图：关键路径高亮 / 帕累托邻域 / 负荷热力 ----------
    fig4 = gantt_critical(result, T, prob);
    if exportPNG, exportgraphics(fig4, fullfile(figDir, 'gantt_critical.png'), 'Resolution', dpi); end

    fig5 = pareto_scatter(result, T, prob);
    if exportPNG && ~isempty(fig5)
        exportgraphics(fig5, fullfile(figDir, 'pareto_scatter.png'), 'Resolution', dpi);
    end

    fig6 = load_heatmap(result, T, prob);
    if exportPNG, exportgraphics(fig6, fullfile(figDir, 'load_heatmap.png'), 'Resolution', dpi); end

    fprintf('图表已保存至 ./figures (convergence / gantt / machine_load / gantt_critical / pareto_scatter / load_heatmap)\n');
end

%% ===================== 阶段5 本地子函数 =====================

%% 关键路径高亮甘特图：复用图2 绘制，关键路径工序加粗红框高亮
function fig = gantt_critical(result, T, prob)
    sched = result.schedule; nOp = prob.nOp;
    [cp, critMach] = critical_path(prob, sched, result.makespan);
    cpSet = containers.Map('KeyType','int32','ValueType','logical');
    for k = 1:numel(cp), cpSet(int32(cp(k))) = true; end

    fig = figure('Color', T.bg, 'Name', 'Gantt - Critical Path', ...
                 'Position', [50 50 1500 900]);
    ax = axes('Parent', fig, 'Color', T.bg, 'XColor', T.fg, 'YColor', T.fg, ...
              'Position', [0.06 0.10 0.88 0.84]);   % 放大绘图区，减少边距
    hold(ax, 'on');
    nMach = prob.nMachine;
    for t = 1:nOp
        s = sched(t);
        y = nMach - s.machine + 0.5;          % 机器自下而上，与图2一致，避免重叠
        isC = isKey(cpSet, int32(t));
        if isC
            rectangle(ax, 'Position', [s.start, y-0.38, s.duration, 0.76], ...
                'FaceColor', [0.85 0.15 0.15], 'EdgeColor', [1 1 1], 'LineWidth', 1.5);
        else
            rectangle(ax, 'Position', [s.start, y-0.38, s.duration, 0.76], ...
                'FaceColor', T.cmap(mod(s.job-1, size(T.cmap,1))+1, :), ...
                'EdgeColor', T.bg, 'LineWidth', 0.6);
        end
        txt = sprintf('J%dO%d', s.job, s.op);
        if s.duration > 4, text(ax, s.start + s.duration/2, y, txt, ...
            'HorizontalAlignment','center','Color', T.fg, 'FontSize', T.fontsize*0.8); end
    end
    ylabel(ax, '机器', 'Color', T.muted); xlabel(ax, '时间', 'Color', T.muted);
    grid(ax, 'on'); ax.GridColor = T.grid; ax.GridAlpha = 0.5;
    set(ax, 'YTick', (1:nMach) + 0.5, ...
        'YTickLabel', arrayfun(@(m) sprintf('M%d', m), nMach:-1:1, 'Uniform', false), ...
        'YLim', [0.2 nMach + 0.8], 'YDir','normal', 'Color', T.bg, ...
        'XColor', T.fg, 'YColor', T.fg, 'GridColor', T.grid, ...
        'GridAlpha', 0.5, 'FontSize', T.fontsize, 'FontName', T.font);
    title(ax, sprintf('FJSP 甘特图 - 关键路径高亮 (makespan=%.0f)', ...
        result.makespan), 'Color', T.fg, 'FontSize', T.title_size, 'FontName', T.font);
    annotation('textbox', [0.01 0.96 0.42 0.03], 'String', '红框 = 关键路径工序', ...
        'Color', [0.95 0.35 0.35], 'FontSize', T.fontsize, 'FontName', T.font, ...
        'FontWeight', 'bold', 'BackgroundColor', 'none', 'EdgeColor', 'none');
    hold(ax, 'off');
end

%% 帕累托邻域权衡散点：对精英做局部扰动生成邻域权衡面，展示双目标 (makespan, 负荷不均衡) 的取舍
function fig = pareto_scatter(result, T, prob)
    % 阶段5：优先绘制真实非支配 Pareto 前沿（result.pareto），
    % 若存档不可用则回退到精英邻域采样（向后兼容）。
    muted = T.muted; if ~isfield(T,'muted'), muted = T.fg * 0.6; end
    fig = figure('Color', T.bg, 'Name', 'Pareto Front');
    hold on;

    usePareto = isfield(result, 'pareto') && ~isempty(result.pareto) ...
                && ~isempty(result.pareto.mk);
    if usePareto
        mkVec = result.pareto.mk;
        unbVec = result.pareto.lb;
        scatter(mkVec, unbVec, 55, T.accent, 'filled', 'MarkerFaceAlpha', 0.85);
        % 高亮 makespan 最优（最小化）前沿解
        [~, bestI] = min(mkVec);
        scatter(mkVec(bestI), unbVec(bestI), 130, T.accent2, 'p', 'LineWidth', 2.5);
        % 连线呈现前沿形状（按 makespan 升序）
        [~, ordp] = sort(mkVec);
        plot(mkVec(ordp), unbVec(ordp), '--', 'Color', muted, 'LineWidth', 1.2);
        legend({'帕累托解', '最优makespan', '帕累托前沿'}, 'TextColor', T.fg, ...
               'Color', T.panel, 'Location', 'best', 'FontWeight', 'bold');
        title(sprintf('真实 Pareto 前沿 (非支配解 %d 个)', numel(mkVec)), ...
            'Color', T.fg, 'FontSize', T.title_size, 'FontName', T.font);
    else
        % 回退：精英邻域采样（保持原行为，避免缺字段崩溃）
        nOp = prob.nOp; nMach = prob.nMachine; %#ok<NASGU>
        elite = result.elite;
        rs = RandStream('mt19937ar', 'Seed', 20260812);
        N = 300;
        mkVec = zeros(N, 1); unbVec = zeros(N, 1);
        for i = 1:N
            OS = elite.OS; MS = elite.MS;
            if rs.rand < 0.5
                a = randi(rs, nOp); b = randi(rs, nOp);
                OS([a b]) = OS([b a]);
            else
                t = randi(rs, nOp); j = OS(t); kk = sum(OS(1:t) == j);
                nM = length(prob.op_mach{j}{kk});
                MS(t) = randi(rs, nM);
            end
            [~, mk, lv] = decode(prob, struct('OS', OS, 'MS', MS));
            mkVec(i) = mk; unbVec(i) = max(lv) - min(lv);
        end
        scatter(mkVec, unbVec, 18, muted, 'filled', 'MarkerFaceAlpha', 0.6);
        scatter(result.makespan, result.loadUnb, 120, T.accent2, 'x', 'LineWidth', 2.5);
        legend({'邻域解', '当前精英'}, 'TextColor', T.fg, 'Color', T.panel, 'Location', 'best', 'FontWeight', 'bold');
        title('精英邻域双目标权衡散点 (× = 当前精英解)', ...
            'Color', T.fg, 'FontSize', T.title_size, 'FontName', T.font);
    end
    xlabel('完工时间'); ylabel('机器负荷不均衡');
    grid on;
    set(gca, 'Color', T.bg, 'XColor', T.fg, 'YColor', T.fg, ...
        'GridColor', T.grid, 'GridAlpha', 0.5, 'FontSize', T.fontsize, 'FontName', T.font);
    hold off;
end

%% 机器×工件 负荷热力图：揭示负荷在 (机器, 工件) 维度的分布不均
function fig = load_heatmap(result, T, prob)
    sched = result.schedule; nMach = prob.nMachine; nJob = prob.nJob;
    M = zeros(nMach, nJob);
    for t = 1:numel(sched)
        s = sched(t);
        M(s.machine, s.job) = M(s.machine, s.job) + s.duration;
    end
    fig = figure('Color', T.bg, 'Name', 'Load Heatmap', 'Position',[50 50 1500 900]);
    imagesc(M);
    colormap(T.cmap);
    colorbar;
    xlabel('工件'); ylabel('机器');
    set(gca, 'YDir', 'normal', 'Color', T.bg, 'XColor', T.fg, 'YColor', T.fg, ...
        'FontSize', T.fontsize, 'FontName', T.font);
    title('机器 × 工件 负荷热力图 (累计工时)', ...
        'Color', T.fg, 'FontSize', T.title_size, 'FontName', T.font);
end
