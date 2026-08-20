function export_result_json(result, path)
% export_result_json  Stage9: serialize llmaoo result to JSON for Python/Plotly viz.
%   result  : struct returned by llmaoo (schedule / makespan / loadVec / pareto /
%             trace_best / trace_mean / problem config / timings).
%   path    : output .json file path.
% Safe: pure serialization; does NOT change any solver numerics. Called only when
%   cfg.EXPORT_JSON == true (default false => llmaoo never calls it, zero regression).
% All field names ASCII English to avoid MATLAB -batch encoding issues.

    if nargin < 2 || isempty(path)
        path = fullfile(pwd, ['results_' datestr(now,'yyyy_mm_dd_HH_MM_SS') '.json']);
    end

    out = struct();
    out.version = '1.0';
    % 阶段四 P2 (pareto 契约清理): 契约升 1.2。
    % 新增显式 pareto.energy_n 字段作色轴（解耦于 obj3 第三列，消除两目标 NaN 纠缠 +
    % 前端"从 obj3[:,2] 取 energy"的脆弱/易误读依赖）。obj3 保留供 NSGA-III 指标链
    % (HV/IGD) 使用，不再作为前端色轴唯一来源。前端据此区分 >=1.2 (显式 energy_n) 与
    % 旧契约 (<1.2 回退读 obj3[:,2])。
    out.contract_version = '1.2';
    out.generated = datestr(now, 'yyyy-mm-dd HH:MM:SS');

    % ---- problem meta ----
    prob = result.problem;
    probMeta = struct();
    probMeta.nJob = prob.nJob;
    probMeta.nMachine = prob.nMachine;
    probMeta.nOp = prob.nOp;
    probMeta.has_energy = isfield(prob,'has_energy') && prob.has_energy;
    probMeta.has_agv = isfield(prob,'has_agv') && prob.has_agv;
    probMeta.has_dynamic = isfield(prob,'has_dynamic') && prob.has_dynamic;
    if isfield(prob,'name'), probMeta.name = prob.name; else probMeta.name = 'data'; end
    out.problem = probMeta;

    % ---- scalar objectives ----
    out.makespan = result.makespan;
    out.loadUnb = result.loadUnb;
    out.iters = result.iters;
    out.nan_count = result.nan_count;
    out.elapsed_sec = result.elapsed_sec;
    if isfield(result,'pareto') && ~isempty(result.pareto)
        out.pareto_count = numel(result.pareto.mk);
    else
        out.pareto_count = 0;
    end
    % ---- Stage9-viz: 可复现性 + 反归一化元数据 ----
    if isfield(result,'mk_ub'), out.mk_ub = result.mk_ub; end
    if isfield(result,'cfg_hash'), out.cfg_hash = result.cfg_hash; end
    if isfield(result,'seed'), out.seed = result.seed; end
    if isfield(result,'scenario'), out.scenario = result.scenario; end

    % ---- Stage0/阶段A: 顶层诚实态，使每个 JSON 自带环境/LLM 来源，第三方无需外部
    %      env_manifest 即可反推是否联网 LLM 产物（与"诚实声明"目标闭环）。
    %      env_state.mode: 'online_real'  -> LLM_ENABLE 且 Key 已注入，联网真实调用
    %                       'offline_honest' -> 离线结构化调制代理（full≡modulate, 增益=0 是环境事实）
    if isfield(result,'llm_enabled') && result.llm_enabled
        out.env_state = struct('mode', 'online_real', ...
                                'note', 'LLM_ENABLE=true with DEEPSEEK_API_KEY injected; online DeepSeek calls were attempted.');
    else
        out.env_state = struct('mode', 'offline_honest', ...
                                'note', 'LLM offline (no network or no key); dual-engine contribution is the offline structured-modulation proxy. No online LLM gain claimed.');
    end
    % LLM 量化计数（联网/缓存/降级/总调用）：离线态 llm_online=0，供复现性审核。
    if isfield(result,'llm_counts') && ~isempty(result.llm_counts)
        lc = result.llm_counts;
        out.llm_counts = struct('llm_online', lc.llm_online, ...
                                 'llm_cache_hits', lc.llm_cache_hits, ...
                                 'llm_fallbacks', lc.llm_fallbacks, ...
                                 'llm_calls', lc.llm_calls);
    end

    % ---- schedule (array of structs -> cell of row arrays) ----
    sched = result.schedule;
    nS = numel(sched);
    schedRows = cell(nS, 1);
    for i = 1:nS
        schedRows{i} = [sched(i).job, sched(i).op, sched(i).machine, ...
                         sched(i).start, sched(i).finish, sched(i).duration];
    end
    out.schedule = schedRows;
    % SCHEMA 约定（阶段零 Z4 占位）：schedule 每行严格 6 列，顺序固定为
    % [job, op, machine, start, finish, duration]，且须 finish >= start >= 0。
    % 导出侧在此定义唯一列名常量；viz/*（dashboard/digital_twin/plotly_gantt）
    % 按同一列序位置读取（如 digital_twin 固定读 row[3..5]）。
    % 计划在阶段五加 validate_schedule(rows) 统一校验层，消除跨模块隐性耦合。
    out.schedule_cols = {'job','op','machine','start','finish','duration'};

    % ---- machine load vector ----
    out.loadVec = result.loadVec(:).';

    % ---- convergence traces ----
    out.trace_best = result.trace_best(:).';      % 归一化加权和（兼容旧前端）
    out.trace_mean = result.trace_mean(:).';
    % Stage9-viz: 真实刻度序列（前端优先用此绘制收敛曲线，避免归一化误读）
    if isfield(result,'trace_makespan') && ~isempty(result.trace_makespan)
        out.trace_makespan = result.trace_makespan(:).';
    end
    if isfield(result,'trace_loadUnb') && ~isempty(result.trace_loadUnb)
        out.trace_loadUnb = result.trace_loadUnb(:).';
    end

    % ---- Pareto front (stage5): real mk/lb + normalized obj3 + explicit energy_n ----
    % 契约（v1.2，阶段四 P2 pareto 契约清理）：
    %   * mk/lb        : 真实 makespan / loadUnb（坐标轴直接用）
    %   * obj3         : 完整三目标向量 [mk_n, ld_n, en_n]，保留供 NSGA-III 指标链
    %                    (HV/IGD) 使用；不再作为前端色轴唯一来源。
    %   * energy_n     : 显式能量色轴字段（= obj3 第三列 en_n）。三目标分支为数值向量；
    %                    两目标分支置 []（空数组，非 NaN），前端据 isempty 判定无能量维。
    % 两目标分支用 [] 而非 NaN：避免前端 np.isfinite 误判，契约更诚实（"无能量维"
    % 与"能量维存在但含非有限值"语义区分清晰）。
    if isfield(result,'pareto') && ~isempty(result.pareto) && ~isempty(result.pareto.mk)
        out.pareto.mk = result.pareto.mk(:).';        % 真实 makespan（坐标轴直接用）
        out.pareto.lb = result.pareto.lb(:).';        % 真实 loadUnb（坐标轴直接用）
        % full 3-obj vector (makespan_n / load_n / energy_n) for HV/IGD + fallback colour
        if isfield(result.pareto,'obj3') && ~isempty(result.pareto.obj3)
            out.pareto.obj3 = result.pareto.obj3;
            % 显式能量色轴：取 obj3 第三列（en_n）。两目标分支 obj3 第三列为 NaN，
            % 此时 energy_n 置 [] 表达"无能量维"。
            en3 = result.pareto.obj3(:, 3);
            if any(isfinite(en3))
                out.pareto.energy_n = en3(:).';
            else
                out.pareto.energy_n = [];   % 两目标分支：空数组，非 NaN
            end
        else
            out.pareto.energy_n = [];       % 无 obj3（极端降级）：空数组
        end
    end

    % ---- NSGA-III quality indicators (HV / IGD / PF size) ----
    if isfield(result,'quality') && ~isempty(result.quality)
        q = result.quality;
        out.quality = struct();
        if isfield(q,'HV'), out.quality.HV = q.HV; end
        if isfield(q,'IGD'), out.quality.IGD = q.IGD; end
        if isfield(q,'nPF'), out.quality.nPF = q.nPF; end
    end

    % ---- write JSON ----
    fid = fopen(path, 'w');
    if fid < 0, error('export_result_json: cannot open %s', path); end
    try
        jsonStr = jsonencode(out, 'PrettyPrint', true);
        fwrite(fid, jsonStr, 'char');
    catch ME
        fclose(fid);
        rethrow(ME);
    end
    fclose(fid);
    fprintf('  [Stage9] exported result JSON -> %s (%d schedule rows)\n', path, nS);
end

% NOTE: export_conv_json moved to its own file exports/export_conv_json.m so that
% llmaoo.m can call it via addpath('exports') under -batch (local sub-functions are
% not visible outside their own file). Kept here only as a comment to avoid a
% duplicate definition in the same directory.
