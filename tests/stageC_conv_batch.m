% stageC_conv_batch  Stage5 P2 (任务 5.1): 批量导出收敛 std 带所需的独立 run 序列。
%   循环 N 次独立求解，每次显式置 EXPORT_CONV_JSON=true 且 EXPORT_DIR='logs'，
%   使 llmaoo 写出 logs/conv_<timestamp>.json（仅含该 run 的 trace_makespan 序列）。
%   再由 viz/plotly_convergence.py 聚合 logs/conv_*.json 生成 mean+/-std 带。
%
%   安全原则（贯穿）：
%   * ADDITIVE 新文件；不改动 llmaoo / aoo_engine / evaluate 任何数值语义。
%   * 不改动 EXPORT_CONV_JSON 的默认 false（零回归）；此处仅"显式开启"用于本脚本。
%   * 每次 run 用不同 RNG_SEED，保证独立样本（std 带才有效）。
%   * 默认小实例 MK01 + 低 MAXGEN，跑得快、可复现；可通过参数覆盖。
%
%   用法（建议用 _cc_conv_batch.bat 驱动）：
%     stageC_conv_batch()             % 默认 N=20, MK01, MAXGEN=60
%     stageC_conv_batch(30,'MK01',80) % N=30, MK01, MAXGEN=80
%   注：llmaoo 默认 static 场景走 load_data(DATA_FILE)，不消费 AOO_DEFAULT_PROB；
%   故此处用 scenario='multi' 使 define_problem('multi',probName) 正确载入 MK01
%   （含 energy 能力位，与阶段四验证的 NSGA-III 三目标路径一致），trace_makespan
%   仍是该实例真实 makespan 收敛，适合 std 带聚合。
function stageC_conv_batch(varargin)
    N = 20; probName = 'MK01'; maxgen = 60;
    if nargin >= 1, N = varargin{1}; end
    if nargin >= 2, probName = varargin{2}; end
    if nargin >= 3, maxgen = varargin{3}; end

    addpath('benchmarks'); addpath('tests'); addpath('benchmarks/baselines'); addpath('exports');
    if ~isfolder('logs'), mkdir('logs'); end

    fprintf('[stageC_conv_batch] N=%d  prob=%s (scenario=multi)  MAXGEN=%d  -> logs/conv_*.json\n', N, probName, maxgen);
    t0 = tic();
    ok = 0;
    for i = 1:N
        seed = 1000 + i;   % 独立种子；每次 run 互不相关，std 带统计有效
        try
            llmaoo('AOO_DEFAULT_SCENARIO', 'multi', ...   % 使 AOO_DEFAULT_PROB 被消费（载入 MK01）
                   'AOO_DEFAULT_PROB', probName, ...
                   'AOO_MAXGEN', maxgen, ...
                   'RNG_SEED', seed, ...
                   'EXPORT_JSON', false, ...        % 仅写 conv，不写完整结果（省 I/O）
                   'EXPORT_CONV_JSON', true, ...     % 关键：写出本 run 的 trace_makespan
                   'EXPORT_DIR', 'logs');            % 路由到 logs/（与计划一致）
            ok = ok + 1;
        catch ME
            fprintf('  run %d (seed=%d) FAILED: %s\n', i, seed, ME.message);
        end
    end
    dt = toc(t0);
    % 统计实际产出
    convFiles = dir(fullfile('logs','conv_*.json'));
    fprintf('[stageC_conv_batch] done: %d/%d runs ok, %d conv files in logs/, %.1fs elapsed\n', ...
            ok, N, numel(convFiles), dt);
    if ok > 0
        fprintf('  聚合示例: python viz/plotly_convergence.py logs/conv_*.json -o figures/convergence_std.html\n');
    end
end
