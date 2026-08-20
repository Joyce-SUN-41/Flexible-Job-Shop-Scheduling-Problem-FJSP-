%% llmaoo.m — LLMAOO 双引擎求解器主入口（LLM × AOO 协同求解 FJSP）
% 引擎一 (DeepSeek LLM)：调度知识中枢，四个职责点
%   ① 启发式规则生成（低频，每 LLM_CALL_EVERY_GEN 代）
%   ② 算子调度（停滞时，调 levy_gain/diff_gain/explore_bias 三个 AOO 增益系数）
%   ③ 局部搜索指导（关键块邻域，由 LLM 选关键机器）
%   ④ 种群状态诊断（更低频，LLM_DIAG_EVERY_GEN 代）
% 引擎二 (AOO)：五策略离散邻域生物启发主搜索，完整保留，仅接受 LLM 的系数调制。
%
% 调用： result = llmaoo();  或 llmaoo('MAXGEN',100) 覆盖参数。
% 无 DeepSeek API Key 时自动降级本地启发式，离线可跑。

function result = llmaoo(varargin)
    cfg = llmaoo_config();
    % 阶段2 修复：varargin 覆盖做大小写不敏感匹配，避免 'MAXGEN' 与
    % cfg.AOO_MAXGEN 字段名大小写不一致导致覆盖整体静默失效。
    cfgFields = fieldnames(cfg);
    cfgLower  = lower(cfgFields);
    for i = 1:2:length(varargin)-1
        key = varargin{i};
        if ~ischar(key), continue; end
        idx = find(strcmp(cfgLower, lower(key)), 1);
        if ~isempty(idx)
            cfg.(cfgFields{idx}) = varargin{i+1};   % 用真实字段名赋值，保证生效
        else
            warning('llmaoo:IgnoredParam', ...
                '忽略未知覆盖参数 ''%s''（合法参数见 llmaoo_config 顶部契约）', key);
        end
    end
    if ~isempty(cfg.RNG_SEED), rng(cfg.RNG_SEED); end
    t_total = tic();   % 运行总耗时计时（阶段1：可观测性增强）

    % 阶段3：初始化统一日志（logs/run_<timestamp>.log），结构化留存逐 run 输出
    logging('init');

    % ---- Stage A: activate dynamic/multi-objective default scenario ----
    % Safety: default cfg.AOO_DEFAULT_SCENARIO == 'static' => no capability bit
    % is flipped, so the main chain is byte-for-byte identical to Stage7
    % (zero regression). Only when the user sets a non-static scenario do we
    % turn on the corresponding cfg_stage8 switches, keeping the Stage8
    % default-off contract intact for direct callers.
    scen = lower(cfg.AOO_DEFAULT_SCENARIO);
    if ~strcmpi(scen, 'static')
        if strcmpi(scen, 'green') || strcmpi(scen, 'multi') || strcmpi(scen, 'full')
            cfg.AOO_THREE_OBJ = true;
        end
        if strcmpi(scen, 'transport') || strcmpi(scen, 'full')
            cfg.AOO_AGV = true;
        end
        if strcmpi(scen, 'dynamic') || strcmpi(scen, 'full')
            cfg.AOO_DYNAMIC = true;
        end
        fprintf('  Stage A scenario active: %s (auto-enabled Stage8 capability bits)\n', scen);
    end

    % ---- Load / build problem ----
    if strcmpi(cfg.AOO_DEFAULT_SCENARIO, 'static')
        % Backward-compatible path: identical to Stage7 (load_data only).
        prob = load_data(cfg.DATA_FILE);
    else
        % Stage A active: build via benchmarks/define_problem so energy/agv/
        % dynamic capability fields are constructed consistently.
        addpath('benchmarks');
        prob = define_problem(cfg.AOO_DEFAULT_SCENARIO, cfg.AOO_DEFAULT_PROB, ...
                              'scenario', cfg.DYN_SCENARIO);
    end
    logging(sprintf('LLMAOO 载入实例: %d 工件 x %d 机器, 总工序 %d', ...
            prob.nJob, prob.nMachine, prob.nOp), 'INFO');
    fprintf('LLMAOO: %d 工件 x %d 机器, 总工序 %d\n', prob.nJob, prob.nMachine, prob.nOp);

    % Stage8 problem upgrade (default off, zero regression).
    % Only when AOO_THREE_OBJ / AOO_AGV / AOO_DYNAMIC is on do we safely attach
    % capability fields; otherwise prob is identical to load_data output.
    if cfg.AOO_THREE_OBJ || cfg.AOO_AGV || cfg.AOO_DYNAMIC
        prob = attach_stage8(prob, cfg);
        caps = {};
        if prob.has_energy, caps{end+1} = '3-obj(energy)'; end
        if prob.has_agv,    caps{end+1} = 'AGV'; end
        if cfg.AOO_DYNAMIC, caps{end+1} = ['dyn(' cfg.DYN_SCENARIO ')']; end
        fprintf('  Stage8 capabilities active: %s\n', strjoin(caps, ' / '));
    end
    % Stage C contract: mirror cfg.AOO_THREE_OBJ onto prob so aoo_engine can
    % branch on the struct field directly (zero regression for non-3-obj scenes,
    % which simply won't carry this field).
    if cfg.AOO_THREE_OBJ
        prob.AOO_THREE_OBJ = true;
    end

    llm_state = default_llm_state(cfg);     % 初始 AOO 调制（默认）

    % ---- 主搜索：AOO 引擎 ----
    % on_iter(t, best, mean) -> 返回更新后的 llm_state，实现 LLM 信号回灌 AOO
    [elite, aoo] = aoo_engine(prob, cfg, llm_state, ...
        @(t, best, mean) llm_hook(prob, cfg, t, best, mean, llm_state));

    % ---- LLM 指导的局部搜索（在 AOO 输出 elite 上做关键块精炼）----
    % 触发一次知识调用以决定 ls_mode/target_machine
    stats = gather_stats(prob, elite, aoo, cfg, 0, 0);
    [user_p, ~] = prompt_knowledge(prob, stats);
    [txt, ok, mode] = deepseek_chat(cfg, fjsp_system_prompt(), user_p);
    if ~ok && ~strcmpi(mode,'offline')
        fprintf('  [LLM 局部搜索指导@0] 警告：知识调用未成功 (%s)，已用降级启发式。\n', mode);
    end
    contract = parse_contract(txt);
    [elite, ~] = llm_guided_local_search(prob, elite, cfg, contract);

    % ---- 打包结果（显式命名赋值，契约见 llmaoo_config 顶部）----
    [sched, makespan, loadVec] = decode(prob, elite);
    result.problem = prob;            % 问题实例（含能力标志位）
    result.elite   = elite;           % 最优染色体 chrom{OS,MS}
    result.schedule = sched;          % 解码调度（含机器/起止时间）
    result.makespan = makespan;       % 目标1：最大完工时间
    result.loadVec  = loadVec;        % 各机器负荷向量（各机负荷和）
    result.loadUnb  = max(loadVec)-min(loadVec);  % 目标2：负荷不均衡度
    result.trace_best = aoo.conv_best;% 每代最优目标加权和（归一化）
    result.trace_mean = aoo.conv_mean;% 每代平均目标加权和（归一化）
    result.trace_makespan = aoo.conv_mk;  % 每代真实 makespan（前端真实刻度）
    result.trace_loadUnb = aoo.conv_lb;   % 每代真实负荷不均衡
    % Stage9-viz: 可复现性元数据（回溯某 JSON 到某次配置/种子）
    result.mk_ub = prob.mk_ub;        % 归一化理论上界，前端反归一化用
    result.cfg_hash = cfg_hash(cfg);  % 关键超参短哈希
    result.seed = cfg.RNG_SEED;       % 随机种子
    result.scenario = cfg.AOO_DEFAULT_SCENARIO;  % 场景名（static/multi/...）
    result.llm_heuristics = contract.heuristics;  % LLM 给出的最终启发式文本
    result.iters   = aoo.iters;       % 实际迭代代数（可能早停）
    result.llm_enabled = cfg.LLM_ENABLE && ~isempty(cfg.DEEPSEEK_API_KEY);
    result.nan_count = aoo.nan_count;  % 阶段3：数值异常触发次数
    result.pareto = aoo.pareto;        % 阶段5：真实非支配 Pareto 存档（供多目标分析/可视化）
    % 阶段 B：NSGA-III 标准质量指标（HV/IGD），仅当三目标激活时由 aoo_engine 计算
    if isfield(aoo, 'quality')
        result.quality = aoo.quality;
    end

    % 阶段3：只读获取 DeepSeek 累计计数（联网/缓存/降级），供实验报告量化 LLM 贡献
    [~, ~, ~, llm_stats] = deepseek_chat(cfg, 'stats', '');
    result.llm_counts = llm_stats;

    logging('==== LLMAOO 求解完成 ====', 'INFO');
    logging(sprintf('最优 makespan: %.1f | 机器负荷不均衡: %.1f', makespan, result.loadUnb), 'INFO');
    logging(sprintf('LLM 启发式: %s', contract.heuristics), 'INFO');
    fprintf('\n==== LLMAOO 求解完成 ====\n');
    fprintf('最优 makespan: %.1f | 机器负荷不均衡: %.1f\n', makespan, result.loadUnb);
    fprintf('LLM 启发式: %s\n', contract.heuristics);

    % 阶段3：输出 LLM 量化计数（联网/缓存/降级），离线态全为离线启发式
    if isfield(result, 'llm_counts')
        fprintf('LLM 计数: 联网=%d 缓存命中=%d 降级=%d (总计调用=%d)\n', ...
                result.llm_counts.llm_online, result.llm_counts.llm_cache_hits, ...
                result.llm_counts.llm_fallbacks, result.llm_counts.llm_calls);
        logging(sprintf('LLM 计数: 联网=%d 缓存命中=%d 降级=%d (总计调用=%d)', ...
                result.llm_counts.llm_online, result.llm_counts.llm_cache_hits, ...
                result.llm_counts.llm_fallbacks, result.llm_counts.llm_calls), 'INFO');
    end

    % 运行耗时（阶段1：可观测性增强）
    elapsed = toc(t_total);
    result.elapsed_sec = elapsed;
    fprintf('实际迭代: %d 代 | 运行耗时: %.1f 秒 | 数值异常: %d 次\n', ...
            result.iters, elapsed, result.nan_count);
    logging(sprintf('实际迭代: %d 代 | 运行耗时: %.1f 秒 | 数值异常: %d 次', ...
            result.iters, elapsed, result.nan_count), 'INFO');

    if cfg.SHOW_PLOTS || cfg.EXPORT_PNG
        visualize(result, cfg.THEME_DARK, cfg.EXPORT_PNG, cfg.FIG_DPI);
    end

    % Stage9: optional JSON export for Python/Plotly visualization (default off).
    % Safe: pure serialization; never changes solver numerics. Only writes a file
    % when cfg.EXPORT_JSON is explicitly enabled (e.g. llmaoo('EXPORT_JSON',true)).
    % Stage9: export directory (阶段一 P0): honors cfg.EXPORT_DIR so timestamped
    % JSON files are grouped under one folder instead of the cwd. Created if missing.
    % Safe: default 'results' exists already; zero regression for direct callers.
    expDir = 'results';
    if isfield(cfg,'EXPORT_DIR') && ~isempty(cfg.EXPORT_DIR)
        expDir = cfg.EXPORT_DIR;
    end
    if ~isfolder(expDir), mkdir(expDir); end

    if isfield(cfg,'EXPORT_JSON') && cfg.EXPORT_JSON
        addpath('exports');
        outPath = fullfile(expDir, ['results_' datestr(now,'yyyy_mm_dd_HH_MM_SS') '.json']);
        export_result_json(result, outPath);
    end

    % Stage9 (阶段一 P0): optional per-run convergence export for std-band aggregation.
    % Default off => zero regression. When on, writes conv_<date>.json carrying
    % only the real makespan trace of THIS run, so dashboard/plotly_convergence can
    % build a mean +/- std band across N independent runs. Safe: pure serialization.
    if isfield(cfg,'EXPORT_CONV_JSON') && cfg.EXPORT_CONV_JSON
        addpath('exports');
        convPath = fullfile(expDir, ['conv_' datestr(now,'yyyy_mm_dd_HH_MM_SS') '.json']);
        export_conv_json(result, convPath);
    end

    % Stage9: optional dynamic-replay export (only when Stage8 AOO_DYNAMIC is on,
    % i.e. a dynamic scenario was solved). Default off -> zero regression.
    if isfield(cfg,'AOO_DYNAMIC') && cfg.AOO_DYNAMIC
        addpath('benchmarks'); addpath('exports');
        % Stage4: pass the real AOO-optimal elite so the replay baseline reflects the
        % true best schedule (not a random chrom). dynamic_replay tolerates [] for
        % backward compatibility, but llmaoo always has `elite` from aoo_engine.
        frames = dynamic_replay(prob, cfg, [], elite);
        replayPath = fullfile(expDir, ['replay_' datestr(now,'yyyy_mm_dd_HH_MM_SS') '.json']);
        export_replay_json(frames, replayPath);
    end
end

%% 配置短哈希（可复现性：把关键超参压缩为 8 位十六进制串，写入导出 JSON）
function h = cfg_hash(cfg)
    key = {cfg.AOO_POP, cfg.AOO_MAXGEN, cfg.AOO_C_DECAY, cfg.AOO_LEVY_BETA, ...
           cfg.W_MAKESPAN, cfg.W_LOAD, cfg.W_ENERGY, ...    % 阶段二 P1: 追加 W_ENERGY（默认0 => 哈希与旧一致，零回归）
           cfg.AOO_DEFAULT_SCENARIO, ...
           cfg.AOO_THREE_OBJ, cfg.OFFLINE_STRUCTURED_MODULATE, ...
           cfg.LLM_ENABLE, cfg.RNG_SEED, ...
           cfg.ENERGY_UB};   % 阶段四 P2: 追加能量归一化上界，区分固定 e_ub(=0) vs 配置上界(>0) 两种归一化路径，保证可复现
    str = '';
    for i = 1:numel(key)
        str = [str '|' char(string(key{i}))];  %#ok<AGROW>
    end
    % 简单 FNV-1a 风格哈希（纯 MATLAB，无 Java 依赖）
    hsh = uint32(2166136261);
    for i = 1:numel(str)
        hsh = bitxor(hsh, uint32(str(i)));
        hsh = bitand(bitsll(hsh, 5) + bitsrl(hsh, 27), uint32(4294967295));
    end
    h = sprintf('%08x', hsh);
end
