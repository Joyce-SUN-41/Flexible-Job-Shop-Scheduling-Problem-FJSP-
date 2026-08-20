%% llmaoo_config.m — LLMAOO 双引擎优化器全局配置
% LLMAOO = LLM (DeepSeek) 调度知识中枢  ×  AOO 群体智能优化引擎
% 设计哲学（继承自双引擎架构）：
%   引擎一 (LLM) 负责"理解调度情境、生成启发式、诊断种群"，不直接算解；
%   引擎二 (AOO) 负责"数学寻优、五策略离散邻域进化、Pareto 前沿"，是主搜索核心。
% 两者通过标准化"调度知识契约"解耦：LLM 产出 heuristics/operator_plan/
%   local_search_hint/diagnostics，AOO 消费这些信号调制自身搜索行为。
% AOO 的所有核心机制（五策略离散邻域、Levy、精英、早停、Pareto 三路径）均原样保留，
% LLM 仅以"外部调制器"身份注入知识，不参与逐解计算 -> 保证 AOO 最大化保留。
%
% 方法学口径（投稿诚实定位，阶段一 P0）：本求解器提供两种互斥配置，不得混述：
%   (A) 默认路径 AOO_THREE_OBJ=false：LLM 引导的"两目标加权和自适应搜索"
%       （makespan + 机器负荷不均衡，权重 W_MAKESPAN/W_LOAD），主链为标量加权和。
%   (B) 投稿多目标路径 AOO_THREE_OBJ=true：aoo_engine 用 NSGA-III 非支配排序替主链
%       选择 N 个个体（真实三目标主选，含 energy 第三维），HV/IGD 由门禁[10]验证。
%   二者是开关互斥的两种配置；论文须分别如实定位，勿将 (B) 的多目标性归因于 (A)。

function cfg = llmaoo_config()
    % 阶段7 新增配置（AOO 停滞重启 + active 解码 + 探索衰减保护 + 竞争力门禁）
    % 全部以保守默认值引入，默认不开/不影响既有数值语义（零回归边界）。
    % 字段：AOO_RESTART_PATIENCE(停滞重启耐心, 0=关), AOO_ACTIVE_DECODE(active后处理开关),
    %       AOO_MIN_EXPLORE(探索概率地板, 防止c过早收拢使变异趋于0),
    %       AOO_GATE_MK_TOL(竞争力门禁: AOO vs Random mean 容忍劣化比例, 0=不强制)
    cfg_stage7 = struct( ...
        'AOO_RESTART_PATIENCE', 40, ...   % 连续 elite_stag 达此值则重启部分种群（打破早熟）
        'AOO_ACTIVE_DECODE', false, ...  % decode 末端是否接 active 化解码后处理（默认关，零回归）
        'AOO_MIN_EXPLORE', 0.1, ...       % wind_mutate 概率地板，防止 c->0 时变异消失
        'AOO_GATE_MK_TOL', 0.02 ...       % 竞争力门禁容忍 mean 劣化比例（0.02=允许2%，小实例random极强时给余量）
    );

    % Stage8 new config (problem upgrade: dynamic reschedule + 3-obj green + AGV)
    % All default off; only when explicitly enabled do they change prob/decode/eval
    % semantics (zero-regression boundary).
    % Fields:
    %   AOO_THREE_OBJ  : enable three-obj (with energy) eval; evaluate 5th output = 3-obj vector
    %   AOO_DYNAMIC    : enable dynamic reschedule main loop (local reschedule on events)
    %   AOO_AGV        : enable AGV transport time constraint (decode inserts transport delay)
    %   ENERGY_UB      : energy normalization upper bound (0 => adaptive)
    %   W_ENERGY       : energy third-objective weight in the main-chain weighted sum
    %                    (Stage8 three-obj). Default 0 => main-chain sum is unchanged
    %                    (pure two-obj makespan+load), zero regression; when >0 AND
    %                    AOO_THREE_OBJ is true, energy truly enters selection (no longer
    %                    the old forced w3=0 degenerate "pseudo-three-obj").
    %   DYN_SCENARIO   : dynamic scenario ('breakdown'/'urgent'/'delay')
    %   HV_REF         : three-obj Hypervolume reference point (empty => adaptive by max)
    cfg_stage8 = struct( ...
        'AOO_THREE_OBJ', false, ...
        'AOO_DYNAMIC', false, ...
        'AOO_AGV', false, ...
        'ENERGY_UB', 0, ...               % 0 => adaptive (1.5*energy+1)
        'W_ENERGY', 0, ...                % 默认 0 => 主链加权和不变（零回归）；>0 且 AOO_THREE_OBJ 开时能源真实参与选择
        'DYN_SCENARIO', 'breakdown', ...
        'HV_REF', [], ...                 % empty => adaptive by per-objective max
        'NSGA3_P', 12, ...                % Das-Dennis 分层数（三目标，12 => 91 参考点）
        'STAGE8_PROB', 'MK01', ...        % Stage8 unified problem source (default benchmark)
        'STAGE8_MODE', 'static' ...       % problem mode (static/green/transport/multi/dynamic/full)
    );

    % Stage9 new config (visualization modernization: JSON export for Python/Plotly).
    % Default off => llmaoo never exports; zero regression to Stage8 behavior.
    % Fields:
    %   EXPORT_JSON    : if true, llmaoo writes results_<date>.json at end (for viz).
    %   EXPORT_CONV_JSON: if true, additionally writes a *_conv_<stem>.json carrying
    %                     only the real makespan convergence trace (trace_makespan) of
    %                     THIS run, so the dashboard/plotly_convergence can aggregate
    %                     N independent runs into a mean +/- std band. Default off so
    %                     single-run behaviour is unchanged (zero regression).
    %   EXPORT_DIR     : output directory for the above JSON exports (created if
    %                     missing). Default 'results' keeps exports out of the cwd and
    %                     stops timestamped files from piling up in the project root.
    cfg_stage9 = struct( ...
        'EXPORT_JSON', false, ...         % default off (zero regression)
        'EXPORT_CONV_JSON', false, ...    % default off (zero regression)
        'EXPORT_DIR', 'results' ...       % default 'results' (zero regression)
    );

    % Stage A config (activate dynamic/multi-objective default scenario).
    % Default 'static' => main chain identical to Stage7 (zero regression).
    % When set to 'multi'/'dynamic'/'green'/'transport'/'full', llmaoo.m
    % auto-enables the corresponding cfg_stage8 capability bits and builds the
    % problem via benchmarks/define_problem, turning on the 2025-2026 hot
    % problem setting without touching the default-off cfg_stage8 switches.
    % This is the single entry point for "activating" Stage8 capabilities.
    cfg_stageA = struct( ...
        'AOO_DEFAULT_SCENARIO', 'static', ...  % static/multi/dynamic/green/transport/full
        'AOO_DEFAULT_PROB', 'MK01' ...          % default benchmark instance for Stage8 modes
    );

    % Stage D config (online LLM honest contribution accounting).
    % Default false => llmaoo behaviour is byte-identical to Stage-C / Stage7 (zero regression):
    % the offline structured modulation path (or constant gains) is used, and ONLINE_LLM_MODULATE
    % never changes numerics for direct callers.
    % When set true (requires DEEPSEEK_API_KEY for a genuine effect), the llm_hook calls
    % online_llm_modulate: a real online LLM call (mode=='online') preserves the contract-parsed
    % gains as the true dual-engine contribution; offline/cached/fallback falls back to the
    % Stage-C structured modulation (so ablation('full') == 'modulate' offline, honestly).
    % Fields:
    %   ONLINE_LLM_MODULATE  : enable honest online-vs-offline gain attribution (default off).
    cfg_stageD = struct( ...
        'ONLINE_LLM_MODULATE', false ...        % default off (zero regression)
    );
    % ========================================================================
    % 接口契约（模块间数据结构约定，阶段1 标准化文档）
    % ------------------------------------------------------------------------
    % cfg       : 本函数返回的全局配置（标量 struct），所有字段见下方定义。
    % prob      : load_data 返回的问题实例（标量 struct），字段见 load_data.m。
    %             - 必含: op_time, op_mach, nMachine, nJob, nOpPerJob, nOp,
    %                     opGlobal, jobOf, opOf, machW, mk_ub
    %             - 能力标志位（阶段1 新增，默认 false，供后续变体扩展判定）:
    %                     has_setup (顺序相关换型), has_agv, has_energy,
    %                     has_dynamic, is_reentrant
    % chrom     : 染色体（标量 struct），字段 OS(1xnOp), MS(1xnOp)。
    % llm_state : LLM 调制状态（标量 struct），字段 levy_gain, diff_gain,
    %             explore_bias（默认均为 1.0）。
    % result    : llmaoo 返回的结果（标量 struct），字段见 llmaoo.m 打包处。
    % ------------------------------------------------------------------------
    % 可经 llmaoo('ParamName', value, ...) 覆盖的合法参数白名单（大小写不敏感，
    % 内部统一按此表映射，避免 'MAXGEN' 误写导致静默失效）：
    %   LLM_ENABLE, DEEPSEEK_API_URL, DEEPSEEK_API_KEY, DEEPSEEK_MODEL,
    %   LLM_MAX_TOKENS, LLM_TEMPERATURE, LLM_TIMEOUT_SEC, LLM_CACHE,
    %   LLM_CALL_EVERY_GEN, LLM_DIAG_EVERY_GEN, LLM_ONLY_ON_STAGNATION,
    %   AOO_POP, AOO_MAXGEN, AOO_REFINE_EVERY, AOO_LEVY_BETA, AOO_C_DECAY,
    %   AOO_EARLY_PATIENCE, AOO_EARLY_DIV_TH, AOO_SNAPSHOT, AOO_PARALLEL,
    %   AOO_RESTART_PATIENCE, AOO_ACTIVE_DECODE, AOO_MIN_EXPLORE, AOO_GATE_MK_TOL,
    %   OFFLINE_STRUCTURED_MODULATE, ONLINE_LLM_MODULATE,
    %   W_MAKESPAN, W_LOAD, W_ENERGY, LS_KMAX, LS_FRAC, RNG_SEED,
    %   EXPORT_PNG, FIG_DPI, SHOW_PLOTS, THEME_DARK, DATA_FILE,
    %   EXPORT_JSON, EXPORT_CONV_JSON
    % ========================================================================

    %% --- DeepSeek LLM 接入（MATLAB 直连官方 API）---
    cfg.LLM_ENABLE   = false;       % 省着用：默认 false 全部走本地 mock 回退（离线可跑，零消耗）。
                                     % 量化 LLM 增益消融时临时置 true（见阶段二执行脚本 _cc_stageD_ablation.bat）。
    cfg.DEEPSEEK_API_URL = 'https://api.deepseek.com/v1/chat/completions';
    % 明文 Key 已移除(2026-08-15)：避免密钥泄露。请通过环境变量 DEEPSEEK_API_KEY 注入，
    % 或在 deepseek_chat.m 中本地填写。LLM_ENABLE=true 且无 Key 时自动降级本地 mock。
    cfg.DEEPSEEK_API_KEY = getenv('DEEPSEEK_API_KEY');
    if isempty(cfg.DEEPSEEK_API_KEY)
        cfg.DEEPSEEK_API_KEY = '';   % 留空 => 离线 mock 降级（零消耗，离线可跑）
    end
    cfg.DEEPSEEK_MODEL  = 'deepseek-chat';   % 或 deepseek-reasoner
    cfg.LLM_MAX_TOKENS   = 600;
    cfg.LLM_TEMPERATURE  = 0.4;     % 偏低，保证调度建议稳定可复现
    cfg.LLM_TIMEOUT_SEC  = 30;      % webwrite 超时
    cfg.LLM_CACHE        = true;    % 相同 prompt 命中缓存，避免重复计费/延迟

    %% --- LLM 调用时机（四个职责点）---
    cfg.LLM_CALL_EVERY_GEN  = 15;   % 职责1/2/3：每 N 代让 LLM 给一次调度知识（启发式+算子+局搜）
    cfg.LLM_DIAG_EVERY_GEN  = 40;   % 职责4：种群诊断（低频，读收敛+多样性）
    cfg.LLM_ONLY_ON_STAGNATION = true; % 仅在近 LLM_STAG_WINDOW 代无改进才触发算子/局搜调制

    %% --- AOO 引擎核心参数（五策略离散邻域生物启发，原样保留并允许 LLM 调制）---
    cfg.AOO_POP        = 100;       % 种群规模 N（FJSP 规模较大，适度增大以增强探索）
    cfg.AOO_MAXGEN     = 150;       % 最大迭代（提速：质量已达 ~217，过长收益递减）
    cfg.AOO_REFINE_EVERY = 5;       % 精英关键路径精炼频率（每 N 代执行一次，降 decode 开销）
    cfg.AOO_LEVY_BETA  = 1.5;       % Levy 指数
    cfg.AOO_C_DECAY    = 3;         % 探索->开发三次衰减幂次
    cfg.AOO_EARLY_PATIENCE = 120;   % 早停耐心（代），AOO 探索较慢，放宽以防过早停
    cfg.AOO_EARLY_DIV_TH = 0.01;    % 早停多样性阈值
    cfg.AOO_SNAPSHOT   = false;     % 是否记录种群快照（FJSP 下关，省内存）
    cfg.AOO_PARALLEL   = false;

    %% --- 阶段5：双引擎协同去虚化（结构化离线调制，默认关）---
    % 离线/降级态下，LLM 不可用，原设计增益恒为 1.0（合理降级）；
    % 打开此开关后，离线态改用基于真实停滞信号的结构化默认调制（levy_gain/diff_gain/
    % explore_bias 随进化状态变化），用于投稿消融实验展示"双引擎协同"而非恒定基线。
    % 默认关闭以确保离线求解语义与阶段4 基线完全一致（零回归、主链数值不变）。
    cfg.OFFLINE_STRUCTURED_MODULATE = false;     % 阶段4：主群评估并行化（需 Parallel Computing Toolbox）
                                      % 默认关；true 时全群评估走 parfor，子集评估仍串行

    %% --- 双目标权重（Pareto 评估用；不再人工加权，改为非支配排序）---
    % 目标1 makespan（越小越好），目标2 机器负荷不均衡度（越小越好）
    cfg.W_MAKESPAN     = 1.0;
    cfg.W_LOAD         = 1.0;

    %% --- 局部搜索（关键块邻域，由 LLM 指导关键机器选择）---
    cfg.LS_KMAX        = 5;         % 关键块邻域最大层数
    cfg.LS_FRAC        = 0.25;      % 仅对前 25% 个体做局部搜索（提速）

    %% --- 随机种子（可复现）---
    cfg.RNG_SEED       = 20260811;

    %% --- 可视化/输出 ---
    cfg.EXPORT_PNG     = true;
    cfg.FIG_DPI        = 150;
    cfg.SHOW_PLOTS     = true;
    cfg.THEME_DARK     = false;

    %% --- 数据文件 ---
    cfg.DATA_FILE      = 'data.mat';

    %% --- 阶段7 配置合并（见函数顶部 cfg_stage7 定义）---
    fns = fieldnames(cfg_stage7);
    for q = 1:numel(fns)
        cfg.(fns{q}) = cfg_stage7.(fns{q});
    end

    %% --- Stage8 config merge (see cfg_stage8 at top; all default off, zero regression) ---
    fns = fieldnames(cfg_stage8);
    for q = 1:numel(fns)
        cfg.(fns{q}) = cfg_stage8.(fns{q});
    end

    %% --- Stage9 config merge (see cfg_stage9 at top; EXPORT_JSON default off) ---
    fns = fieldnames(cfg_stage9);
    for q = 1:numel(fns)
        cfg.(fns{q}) = cfg_stage9.(fns{q});
    end

    %% --- Stage A config merge (see cfg_stageA at top; default 'static' => zero regression) ---
    fns = fieldnames(cfg_stageA);
    for q = 1:numel(fns)
        cfg.(fns{q}) = cfg_stageA.(fns{q});
    end

    %% --- Stage D config merge (see cfg_stageD at top; default off => zero regression) ---
    fns = fieldnames(cfg_stageD);
    for q = 1:numel(fns)
        cfg.(fns{q}) = cfg_stageD.(fns{q});
    end

    % whitelist additions for llmaoo('ParamName',value) override (case-insensitive)
    % (EXPORT_JSON added here so it can be toggled via llmaoo('EXPORT_JSON',true))
    whitelist_extra = {'EXPORT_JSON'};
    % (the main whitelist is built in llmaoo.m via fieldnames(cfg); this is a note)
end
