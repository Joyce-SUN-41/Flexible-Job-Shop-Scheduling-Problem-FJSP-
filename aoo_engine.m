%% aoo_engine.m — AOO 群体智能优化引擎（五策略离散邻域版，适配 FJSP）
% AOO（Animated Oat Optimization，动麦种子传播优化）本质是一套受植物/自然
% 种子传播机制启发的群体智能算法，其方法论特征在于 Phase2~4 的五个搜索策略
% （风/水/动物传播 + 滚动/弹射开发）及其系数公式。
%
% 为在 FJSP 离散可行域上保留 AOO 特点，本实现将五策略直接映射为离散邻域算子，
% 作用在 OS+MS 染色体上；同时保留 AOO 的全部系数语义：
%   风 Wind   : 精英扩散——对优质个体做低强度离散变异（交换工序 + 改机器）
%   水 Water  : 差分交叉——两染色体按随机工件子集做 POX 式序交叉 + MS 混合
%   动物 Animal: 向精英靠拢——劣势个体复制精英的 OS 前缀片段
%   滚动 Rolling: 精英 + Lévy 跳跃——随机选 ~Lévy 个位置做块反转（精细开发）
%   弹射 Ejection: 精英 + 大幅重置——随机重置部分片段（逃离局部最优）
% 系数：c = 1-(t/T)^3 三次衰减（前期探索、后期开发）；m/L/e 为文档基准系数，
% 经 LLM 增益（levy_gain / diff_gain）外部调制，仅缩放操作强度，不改策略结构。
% X 仅作为"连续潜力场"辅助生成随机强度（风/滚动/弹射的随机性来源）。
%
% 种群以 cell 数组存储（pop{i} 为 scalar struct），避免 struct 数组维度歧义。

function [elite, result] = aoo_engine(prob, cfg, llm_state, on_iter)
    % 调试分支：aoo_engine(prob,cfg,llm,'DBG') 跑自检
    if ischar(on_iter) && strcmp(on_iter, 'DBG')
        dbg_self(prob, cfg, llm_state); elite = []; result = struct(); return;
    end
    % 不在此处重置 rng，随机性由调用方控制，支持独立重复与统计检验。
    N = cfg.AOO_POP; T = cfg.AOO_MAXGEN; nOp = prob.nOp;
    LB = zeros(1, 2*nOp); UB = ones(1, 2*nOp);

    % ---- Phase0 初始化（X 均匀随机潜力场 + 解码为可行染色体）----
    X = LB + rand(N, 2*nOp) .* (UB - LB);
    pop = cell(N, 1);
    for i = 1:N
        pop{i} = decode_X(prob, X(i, :));
    end
    Z = evaluate_population(prob, pop, cfg);   % 阶段3：统一批量评估入口
    [elite, eliteObj, eliteX] = get_best(Z, pop, X);

    % ---- Stage C: NSGA-III 参考点 + 真实 Pareto 累积缓冲（仅三目标模式用，默认零占用）----
    if isfield(prob, 'AOO_THREE_OBJ') && prob.AOO_THREE_OBJ
        pLattice = cfg.NSGA3_P;                 % 分层数（默认 12 -> 三目标 91 参考点）
        RP3 = das_dennis(3, pLattice);
        pf3 = zeros(0, 3);                      % 整段进化期真实非支配前沿缓冲
        pf3_chrom = {};                         % 同步累积对应染色体（输出真实 mk/lb 用）
        fprintf('  [Stage C] NSGA-III 主选择已启用（M=3, 参考点=%d, pop=%d）。\n', ...
            size(RP3, 1), N);
    else
        RP3 = []; pf3 = []; pf3_chrom = {};
    end

    conv_best = zeros(1, T); conv_mean = zeros(1, T);
    % Stage9-viz: 真实 makespan / loadUnb 每代序列（未经归一化），供前端收敛曲线
    % 显示真实刻度，避免 "trace_best" 归一化加权和(0.x) 造成读者误读。
    conv_mk = zeros(1, T); conv_lb = zeros(1, T);
    stag = 0; last_best = sum(eliteObj);
    nan_count = 0;                 % 阶段3：数值异常（NaN/Inf）污染精英触发次数
    elite_stag = 0;                % 阶段3：连续精英未更新代数计数器
    const_stag_warn = cfg.AOO_EARLY_PATIENCE;  % 连续多少代未更新触发显式日志标记
    archive = {};                  % 阶段5：精英存档（供 Pareto 非支配解收集）

    for t = 1:T
        % ---- Phase1 参数（三次衰减 + 文档 m/L/e 系数，LLM 增益外部调制）----
        [c, m, L, e] = aoo_params(t, T, N, nOp, llm_state);
        levy = levy_vec(nOp) .* llm_state.levy_gain;   % Lévy 飞行（β=1.5）

        % ---- Phase2 探索：按适应度三等分，施加三种传播 ----
        [~, ord] = sortrows(Z, [1 2]);      % 字典序近似分组（保留 AOO 分组思想）
        third = floor(N / 3);
        newPop = pop;
        % 风传播（最优 1/3）：离散变异（精英扩散）
        % 阶段7：探索概率地板 AOO_MIN_EXPLORE，防止 c->0（后期）时变异概率趋于 0
        % 导致种群彻底固化、无法逃离局部最优。
        % 双引擎协同：LLM 的 explore_bias 增益调制风传播幅度（探索强弱），
        % 是 LLM 三增益(levy_gain/diff_gain/explore_bias)中唯一原未被算子消费的项，
        % 现明确接入 windPm，使 LLM 真正影响全部 5 策略中的风策略（闭合双引擎链路）。
        windPm = max(0.15*c*llm_state.explore_bias + 0.02, cfg.AOO_MIN_EXPLORE);
        for k = 1:third
            i = ord(k);
            newPop{i} = wind_mutate(prob, pop{i}, windPm);
        end
        % 水传播（中间 1/3）：差分交叉（POX 式）
        for k = third+1:2*third
            i = ord(k);
            r1 = randi(N); r2 = randi(N);
            newPop{i} = water_xover(prob, pop{r1}, pop{r2}, m, L);
        end
        % 动物传播（最差 1/3）：向精英靠拢（复制精英 OS 前缀片段）
        for k = 2*third+1:N
            i = ord(k);
            newPop{i} = animal_copy(prob, pop{i}, elite, c, e);
        end

        % 评估（Phase2 后，阶段3：统一批量评估）
        Z = evaluate_population(prob, newPop, cfg);

        % ---- Phase3/4 开发：基于精英 + Lévy（滚动=优，弹射=劣）----
        meanObj = mean(Z, 1);
        ssum = Z(:, 1) + Z(:, 2);
        above = find(ssum <= meanObj(1) + meanObj(2));
        below = find(ssum >  meanObj(1) + meanObj(2));
        % 仅对实际被滚动/弹射修改的个体重新评估，其余沿用 Phase2 的 Z（未改动）
        touched = unique([above(:); below(:)].');
        for k = 1:numel(above)
            i = above(k);
            newPop{i} = rolling_block(prob, elite, newPop{i}, levy, c);
        end
        for k = 1:numel(below)
            i = below(k);
            newPop{i} = ejection_block(prob, elite, newPop{i}, e, c, nOp);
        end
        % 仅对实际被滚动/弹射修改的个体重新评估（阶段3：子集批量评估，保留提速语义）
        % 传入当前 Z 作基底，非 touched 位置沿用 Phase2 的全群评估值，避免目标值丢失
        Z = evaluate_population(prob, newPop, cfg, touched, Z);

        % ---- Phase5 边界钳制 + 精英保留 ----
        % 合法化兜底：确保所有染色体 OS 长度=nOp 且工件工序数守恒
        for i = 1:N
            newPop{i}.OS = fix_os_counts(newPop{i}.OS, prob);
        end

        % 阶段7：精英注入（标准精英保留，提升稳定性）。
        % 将当前精英克隆替换最差的精英保留数(默认 ceil(2%*N)+1)个个体，
        % 确保优质基因每代不丢失，抑制动物/弹射算子对优质解的过度破坏。
        nKeep = max(1, ceil(0.02 * N) + 1);
        if nKeep < N
            [~, ordW] = sort(sum(Z, 2), 'descend');   % 最差在前
            for kk2 = 1:nKeep
                newPop{ordW(kk2)} = elite;
            end
        end

        if isfield(prob,'AOO_THREE_OBJ') && prob.AOO_THREE_OBJ
            % === Stage C: NSGA-III 主选择（多目标模式，默认关 => 零回归）===
            % 父代 pop 与子代 newPop 合并为 2N，按三目标非支配排序 + 参考点小生境
            % 选回 N 个。替换两目标和"取最优"的单目标精英语义，提供真实的 Pareto
            % 分布搜索，而非把三目标压成加权和。
            objAll = zeros(2*N, 3);
            for i = 1:N
                % 阶段二 P1 修复: 传 3 元素权重 [1 1 1] 使 evaluate 进入三目标分支
                % (evaluate 第35行要求 numel(w)>=3 才返回 3 维 extra.obj=[mk,ld,en])。
                % 旧代码传 [1 1]（2 元素）导致 evaluate 走 else 返回 2 维，objAll 第三列
                % 恒为 0 => NSGA-III 实际只按两目标排序（energy 被忽略），是"伪三目标"
                % 的另一根因。权重在 NSGA-III 非支配排序中本就不参与，此处仅触发分支。
                [~, ~, ~, ~, ex] = evaluate(prob, pop{i}, [1 1 1]);
                objAll(i, :) = ex.obj;
                [~, ~, ~, ~, ex2] = evaluate(prob, newPop{i}, [1 1 1]);
                objAll(N+i, :) = ex2.obj;
            end
            keep = nsga3_select(objAll, RP3, N);
            newPopMerged = [pop; newPop];
            pop = newPopMerged(keep);
            Z = evaluate_population(prob, pop, cfg);   % 同步两目标和(供下游兼容)
            % 真实 Pareto 前沿：合并 2N 个体非支配解（整段进化期累积到 pf3）
            fronts = non_dominated_sort(objAll);
            pf3 = [pf3; objAll(fronts{1}, :)];          %#ok<AGROW>
            % Stage9-viz: 同步累积对应染色体，供导出端输出真实 mk/lb（pf3 为归一化量）
            mergedAll = [pop; newPop];
            pf3_chrom = [pf3_chrom; mergedAll(fronts{1})];  %#ok<AGROW>
        else
        pop = newPop;
        end
        % ---- 阶段7：停滞重启机制（打破早熟，恢复探索）----
        % 当连续 AOO_RESTART_PATIENCE 代精英未改进时，对一部分劣势个体注入随机
        % 染色体（保留精英），重建种群多样性。仅扰动非精英个体，避免破坏已得最优。
        if cfg.AOO_RESTART_PATIENCE > 0 && elite_stag >= cfg.AOO_RESTART_PATIENCE
            restartFrac = 0.3;                       % 重启动比例（保守，保留 70% 种群）
            nRestart = max(1, round(N * restartFrac));
            % 选当前最差的 nRestart 个个体（按两目标和降序）做精英引导重置：
            % 以精英为基底，随机重置一段片段，保留已得优质结构，避免纯随机丢失信息。
            [~, ordW] = sort(sum(Z, 2), 'descend');
            for rr = 1:nRestart
                ii = ordW(rr);
                pop{ii} = elite_guided_restart(prob, elite);
            end
            Z = evaluate_population(prob, pop, cfg);  % 重评估被重置个体所在种群
            elite_stag = 0;                           % 重置停滞计数，重启探索窗口
            fprintf('  [AOO] 触发停滞重启：重置 %d 个劣势个体（best=%.4f）。\n', ...
                nRestart, sum(eliteObj));
        end
        [b, bobj, bx] = get_best(Z, pop, X);
        % 主循环 guard（阶段3）：防御数值异常（NaN/Inf）污染精英，触发则回退上一精英
        if any(~isfinite(bobj))
            nan_count = nan_count + 1;            % 阶段3：记录异常次数，供实验报告量化稳定性
            b = elite; bobj = eliteObj; bx = eliteX;
        end
        if sum(bobj) < sum(eliteObj)
            elite = b; eliteObj = bobj; eliteX = bx;
            elite_stag = 0;                       % 阶段3：精英更新，重置连续未更新计数
            % 阶段5：将改进精英纳入存档（仅记录，不参与主链数值决策）
            archive{end+1} = struct('OS', elite.OS, 'MS', elite.MS, ...
                                    'X', eliteX, 'Z', eliteObj);
        else
            elite_stag = elite_stag + 1;          % 阶段3：精英未更新，累加
            if elite_stag == const_stag_warn
                % 阶段3：显式日志标记"连续 K 代精英未更新"，便于诊断早熟/停滞
                fprintf('  [AOO] 连续 %d 代精英未更新（当前 best=%.4f），疑似停滞。\n', ...
                    elite_stag, sum(eliteObj));
            end
        end

        % ---- AOO 开发增强：精英关键路径邻域精炼（FJSP 经典局部搜索）----
        % 频率控制：每 AOO_REFINE_EVERY 代执行一次，降低 decode 开销
        if mod(t, cfg.AOO_REFINE_EVERY) == 0
            [elite, eliteObj, eliteX] = refine_elite(prob, cfg, elite, eliteObj, eliteX);
        end

        % 收敛记录
        conv_best(t) = sum(eliteObj);
        conv_mean(t) = mean(sum(Z, 2));
        % Stage9-viz: 真实 makespan / loadUnb（供前端真实刻度收敛曲线）
        [~, cmk, clv] = decode(prob, elite);
        conv_mk(t) = cmk;
        conv_lb(t) = max(clv) - min(clv);
        if ~isempty(on_iter)
            try
                ns = on_iter(t, sum(eliteObj), conv_mean(t));
                if ~isempty(ns), llm_state = ns; end
            catch
            end
        end

        % 早停
        if abs(sum(eliteObj) - last_best) < 1e-6, stag = stag + 1; else stag = 0; end
        last_best = sum(eliteObj);
        if stag >= cfg.AOO_EARLY_PATIENCE, break; end
    end

    result.conv_best = conv_best(1:t);
    result.conv_mean = conv_mean(1:t);
    result.conv_mk = conv_mk(1:t);      % 真实 makespan 逐代序列（前端真实刻度）
    result.conv_lb = conv_lb(1:t);      % 真实 负荷不均衡 逐代序列
    result.obj = eliteObj; result.iters = t;
    result.nan_count = nan_count;   % 阶段3：数值异常触发次数，量化求解稳定性
    [result.sched, result.makespan, result.loadVec] = decode(prob, elite, cfg);
    result.loadUnb = max(result.loadVec) - min(result.loadVec);

    % ---- 阶段5 / Stage C：真实 Pareto 存档 ----
    % 三目标模式：直接用整段进化期累积的真实非支配前沿 pf3（mk,ld,en 向量），
    % 从中取 makespan 最优解作为精英（保持 result.obj/makespan 下游契约不变）。
    % 两目标模式：沿用原 archive 随机存档构造（行为不变，零回归）。
    if isfield(prob,'AOO_THREE_OBJ') && prob.AOO_THREE_OBJ && ~isempty(pf3)
        % 去 NaN/Inf，保真实非支配
        good = all(isfinite(pf3), 2);
        pf3c = pf3(good, :);
        if ~isempty(pf3c)
            fronts = non_dominated_sort(pf3c);
            pf3c = pf3c(fronts{1}, :);              % 最终再筛一次非支配
            % 阶段二 P1: 唯一化（NSGA-III 分支逐代累积 fronts{1} 但未去重，导致
            % 同一非支配解在多代重复出现，padaro 前端计数虚高）。按三目标向量
            % 四舍五入去重（eps 容差），仅保留真实不同的非支配解。
            [~, uiq] = unique(round(pf3c, 6), 'rows', 'stable');
            pf3c = pf3c(uiq, :);
            pf3_chrom = pf3_chrom(uiq);             % 同步去重染色体（供真实 mk/lb 输出）
            [~, imk] = min(pf3c(:, 1));
            % 若精英在两目标和语义下劣于 Pareto makespan 最优，则用 Pareto 最优覆盖
            if pf3c(imk, 1) < eliteObj(1) || pf3c(imk, 2) < eliteObj(2)
                [result.sched, result.makespan, result.loadVec] = ...
                    decode(prob, elite, cfg);       % 保持 sched 契约（精英解码）
                result.loadUnb = max(result.loadVec) - min(result.loadVec);
            end
            % Stage9-viz: 输出真实 mk/lb（decode 每个非支配解），归一化向量保留在
            % obj3 供 NSGA-III 指标与能量色轴；避免前端把归一化 mk(0.26) 当真实刻度。
            nP = size(pf3c, 1);
            mk_raw = zeros(nP, 1); lb_raw = zeros(nP, 1);
            OS_cell = cell(nP, 1); MS_cell = cell(nP, 1);
            for qi = 1:nP
                ch = pf3_chrom{qi};
                OS_cell{qi} = ch.OS; MS_cell{qi} = ch.MS;
                [~, mki, lvi] = decode(prob, ch);
                mk_raw(qi) = mki; lb_raw(qi) = max(lvi) - min(lvi);
            end
            [mk_raw, ordR] = sort(mk_raw);
            % 阶段一 P0: 精简 Pareto 契约——仅真实 mk/lb + 完整 obj3([mk_n,ld_n,en_n])。
            % 已删除与 obj3 前两列重叠的 Z/mk_n/lb_n，避免冗余与不一致。
            result.pareto = struct('OS', {OS_cell(ordR)}, 'MS', {MS_cell(ordR)}, ...
                'mk', mk_raw, 'lb', lb_raw(ordR), ...
                'energy', pf3c(ordR,3), 'obj3', pf3c(ordR,:));
        else
            result.pareto = build_pareto(prob, archive, cfg);
        end
    else
        result.pareto = build_pareto(prob, archive, cfg);
    end

    % ---- 阶段 B：NSGA-III 标准质量指标（HV / IGD，纯附加）----
    % 仅当三目标激活时计算；不修改主链数值语义，仅向 result.quality 附加证据。
    if isfield(prob,'AOO_THREE_OBJ') && prob.AOO_THREE_OBJ ...
            && isfield(result.pareto,'obj3') && ~isempty(result.pareto.obj3)
        % 清理 obj3 中可能的 NaN/Inf 行（防御：个别存档点三目标评估异常）
        obj3c = result.pareto.obj3;
        bad = any(~isfinite(obj3c), 2);
        if any(bad), obj3c(bad, :) = []; end
        if ~isempty(obj3c)
            if isfield(cfg,'HV_REF') && ~isempty(cfg.HV_REF)
                result.quality = nsga3_quality(obj3c, cfg.HV_REF);
            else
                result.quality = nsga3_quality(obj3c);  % 自适应参考点
            end
            fprintf('  [Stage B] NSGA-III quality: HV=%.4f IGD=%.4f (PF size=%d)\n', ...
                result.quality.HV, result.quality.IGD, result.quality.nPF);
        end
    end
end

%% 阶段5：由精英存档构造非支配 Pareto 前沿（仅"附加"，不改主链数值语义）
% archive: cell 数组，每个元素为 struct('OS',..,'MS',..,'X',..,'Z',[mk_n, lb_n])。
% 返回 result.pareto: struct('OS',{..},'MS',{..},'mk',[],'lb',[],'energy',[],'obj3',[])，
% 其中 mk/lb 为原始两目标（未归一化）：mk=makespan, lb=loadUnb；
% obj3 = [mk_n, ld_n, en_n]（归一化三目标，energy 维无能耗时为 NaN）。
% 阶段一 P0: 已删除冗余的 Z/mk_n/lb_n 导出字段（与 obj3 前两列重叠）。
function pareto = build_pareto(prob, archive, cfg)
    pareto = struct('OS', {{}}, 'MS', {{}}, 'mk', [], 'lb', [], 'energy', [], 'obj3', []);
    if isempty(archive), return; end
    % 去 NaN/Inf 个体，保证排序数值稳健
    clean = {};
    for i = 1:numel(archive)
        if all(isfinite(archive{i}.Z)), clean{end+1} = archive{i}; end  %#ok<AGROW>
    end
    if isempty(clean), return; end
    Zall = cell2mat(cellfun(@(a) a.Z, clean, 'UniformOutput', false));
    if size(Zall, 2) > 2, Zall = Zall(:, 1:2); end  % 防御：仅取两目标归一化维度
    fronts = non_dominated_sort(Zall);
    if isempty(fronts), return; end
    f1 = fronts{1};  % 第一非支配层 = Pareto 最优
    OS = {};
    MS = {};
    mk = zeros(numel(f1), 1);
    lb = zeros(numel(f1), 1);
    en = zeros(numel(f1), 1);
    obj3 = zeros(numel(f1), 3);   % 三目标归一化向量（Stage B：NSGA-III 输入）
    hasEnergy = isfield(prob,'has_energy') && prob.has_energy ...
                && isfield(prob,'AOO_THREE_OBJ') && prob.AOO_THREE_OBJ;
    for q = 1:numel(f1)
        a = clean{f1(q)};
        OS{q} = a.OS; MS{q} = a.MS;       %#ok<AGROW>
        % 还原原始两目标（非归一化）：直接重解码得 makespan 与 loadUnb
        [~, mki, lv] = decode(prob, a);
        mk(q) = mki; lb(q) = max(lv) - min(lv);  %#ok<AGROW>
        if hasEnergy
            [~,~,~,~,ex] = evaluate(prob, a);    %#ok<AGROW>  % 三目标附加存档（仅可视化 + Stage B 指标）
            en(q) = ex.energy;
            obj3(q, :) = ex.obj(:).';           % [mk_n, ld_n, en_n] 归一化
        else
            % 阶段一 P0: 两目标分支 obj3 统一为 [mk_n, ld_n, NaN]，与三目标分支
            % 前两列语义对齐（均为归一化 makespan/loadUnb），避免前端/下游对
            % obj3 前两列含义产生歧义（旧代码曾填归一化加权和分量 Zsel）。
            obj3(q, :) = [Zall(f1(q), 1), Zall(f1(q), 2), NaN];
        end
    end
    % 按 makespan 升序排列，便于可视化与读取
    [mk, ordp] = sort(mk);
    pareto.OS = OS(ordp);
    pareto.MS = MS(ordp);
    pareto.mk = mk;
    pareto.lb = lb(ordp);
    % 阶段一 P0: 精简契约。归一化前两维仅作局部变量用于构造 obj3，不再写入
    % pareto（已删除冗余导出的 Z / mk_n / lb_n，与三目标分支保持一致）。
    Zsel = Zall(f1(ordp), :);          % K x 2 归一化 [mk_n, ld_n]
    % Stage9-viz: 统一 obj3 维度（前端能量色轴契约稳定）。
    if hasEnergy
        pareto.energy = en(ordp);
        pareto.obj3 = obj3(ordp, :);            % 三目标分支已含完整 [mk_n, ld_n, en_n]
    else
        pareto.obj3 = obj3(ordp, :);            % 两目标分支 = [mk_n, ld_n, NaN]（语义已对齐）
    end
end

%% ============ AOO 五策略（离散邻域算子，保留系数语义）============

%% Phase1 参数（与文档 _calculate_parameters 一致；LLM 增益为外部调制）
function [c, m, L, e] = aoo_params(t, T, N, nOp, llm)
    r = rand();
    m = 0.5 * r;                  % 水传播基础强度（Cross 概率）
    L = 0.5 + 0.5 * r;            % 水传播缩放
    e = 0.3 * r;                  % 动物传播基础强度
    e = e * llm.diff_gain;        % LLM 调制（仅缩放，不改公式结构）
    m = m * llm.diff_gain;        % 修复(2026-08-15)：diff_gain 同时调制水传播，与契约语义一致
    m = m * min(1.0, sqrt(N / nOp));
    L = L * min(1.0, sqrt(N / nOp));
    c = 1.0 - (t / T)^3;          % 三次衰减：前期探索、后期开发
end

%% 风传播 Wind：精英扩散——低强度离散变异（交换工序 + 改机器）
function chrom = wind_mutate(prob, chrom, pm)
    nOp = prob.nOp;
    c = chrom;
    if rand < pm
        i1 = randi(nOp); i2 = randi(nOp);
        tmp = c.OS(i1); c.OS(i1) = c.OS(i2); c.OS(i2) = tmp;
    end
    if rand < pm
        t = randi(nOp); j = c.OS(t); kk = sum(c.OS(1:t) == j);
        if kk >= 1 && kk <= numel(prob.op_mach{j})
            nM = length(prob.op_mach{j}{kk});
            if nM > 1, c.MS(t) = randi(nM); end
        end
    end
    chrom = c;
end

%% 水传播 Water：差分交叉（类 POX）——按随机工件子集定 OS 序，MS 混合
function child = water_xover(prob, p1, p2, m, L)
    nJob = prob.nJob; nOp = prob.nOp;
    % 随机工件子集（L 调制子集大小），子代 OS 中这些工件工序序取自 p1，其余取 p2
    n = round((0.5 * L) * nJob);
    subIdx = randperm(nJob, max(1, min(nJob, n)));
    sub = false(1, nJob); sub(subIdx) = true;
    % 构造子代 OS：先按 p1 序填入子集工件，再按 p2 序填入其余（保证工序数守恒）
    childOS = zeros(1, nOp);
    seen1 = zeros(1, nJob); seen2 = zeros(1, nJob);
    pos = 1;
    for t = 1:nOp
        j = p1.OS(t);
        if sub(j) && seen1(j) < prob.nOpPerJob(j)
            seen1(j) = seen1(j) + 1; childOS(pos) = j; pos = pos + 1;
        end
    end
    for t = 1:nOp
        j = p2.OS(t);
        if ~sub(j) && seen2(j) < prob.nOpPerJob(j)
            seen2(j) = seen2(j) + 1; childOS(pos) = j; pos = pos + 1;
        end
    end
    % 兜底：若仍有缺失（理论上不发生），用 fix_os_counts 修复保证合法
    if pos <= nOp
        childOS(pos:nOp) = 1;
    end
    childOS = fix_os_counts(childOS, prob);
    % MS：按 m 概率从 p1/p2 混合
    childMS = p1.MS;
    for t = 1:nOp
        if rand < m, childMS(t) = p2.MS(t); end
    end
    child = struct('OS', childOS, 'MS', childMS);
end

%% 动物传播 Animal：劣势个体复制精英 OS 前缀片段（向精英靠拢）
function child = animal_copy(prob, chrom, elite, c, e)
    nOp = prob.nOp;
    % 复制比例随 c*e（越往后越少），将精英前 k 个工序的工件序列搬入 child 前部
    k = max(1, round(nOp * c * e * 0.5));
    seedJobs = elite.OS(1:k);
    child = chrom;
    child.OS = resequence(prob, seedJobs, chrom.OS);
    child.OS = fix_os_counts(child.OS, prob);
end

%% 将 seed（精英前 k 工序的工件序列）置于前，剩余工序按原序补齐，保证计数守恒
function OS = resequence(prob, seed, rest)
    nJob = prob.nJob; nOp = prob.nOp;
    cnt = zeros(1, nJob);
    for t = 1:numel(seed), cnt(seed(t)) = cnt(seed(t)) + 1; end
    OS = zeros(1, nOp);
    p = 1;
    for t = 1:numel(seed)
        OS(p) = seed(t); p = p + 1;
    end
    for t = 1:numel(rest)
        j = rest(t);
        if cnt(j) < prob.nOpPerJob(j)
            cnt(j) = cnt(j) + 1; OS(p) = j; p = p + 1;
        end
    end
    % 补位：剩余工序按工件顺序补齐
    for j = 1:nJob
        while cnt(j) < prob.nOpPerJob(j)
            OS(p) = j; cnt(j) = cnt(j) + 1; p = p + 1;
        end
    end
end

%% 滚动 Rolling：精英 + Lévy 跳跃（随机选 ~k 个位置做块反转，精细开发）
function child = rolling_block(prob, elite, chrom, levy, c)
    nOp = prob.nOp;
    child = elite;   % 基于精英开发
    % Lévy 决定的跳跃强度：k 个位置做块反转
    k = min(nOp-1, max(1, round(mean(levy(1:min(5, nOp))) * nOp * c)));
    if k >= 2 && rand < 0.5
        i1 = randi(nOp - k + 1);
        seg = child.OS(i1:i1+k-1);
        child.OS(i1:i1+k-1) = seg(end:-1:1);
    end
    % 机器维度：随机改少数机器（随 c 衰减）。k 用 OS 累加得到，与 decode 一致。
    if rand < 0.3*c
        t = randi(nOp); j = child.OS(t);
        % 计算 job 内工序序号 k（t 之前 j 出现的次数 + 1），与 decode 一致。
        kk = sum(child.OS(1:t) == j);
        if kk >= 1 && kk <= numel(prob.op_mach{j}) && length(prob.op_mach{j}{kk}) > 1
            child.MS(t) = randi(length(prob.op_mach{j}{kk}));
        end
    end
end

%% 弹射 Ejection：精英 + 大幅重置部分片段（逃离局部最优）
function child = ejection_block(prob, elite, chrom, e, c, nOp)
    child = elite;
    % 重置比例随 e*c（后期衰减），重置一段为随机可行片段
    k = max(1, round(nOp * e * c * 0.3));
    i1 = randi(nOp - k + 1);
    % 把该段重置为随机工件序列（守恒由 fix_os 保证）
    seg = randi(prob.nJob, 1, k);
    child.OS(i1:i1+k-1) = seg;
    child.OS = fix_os_counts(child.OS, prob);
    % 机器重置：用与 decode 一致的 job 内工序序号 (k 由 OS 累加得到)，
    % 避免误用固定的 prob.opOf(t)（其 job 与当前 OS(t) 可能不一致）。
    cnt = zeros(1, prob.nJob);
    for t = i1:i1+k-1
        j = child.OS(t); cnt(j) = cnt(j) + 1; kk = cnt(j);
        if kk <= numel(prob.op_mach{j}) && length(prob.op_mach{j}{kk}) > 1
            child.MS(t) = randi(length(prob.op_mach{j}{kk}));
        end
    end
end

%% Lévy 飞行（β=1.5，复刻文档 _levy_flight）
function v = levy_vec(dim)
    beta = 1.5;
    sig = (gamma(1+beta)*sin(pi*beta/2) / ...
           (gamma((1+beta)/2)*beta*2^((beta-1)/2)))^(1/beta);
    u = randn(1, dim)*sig; w = randn(1, dim);
    v = u ./ (abs(w).^(1/beta) + 1e-15);
end

%% ============ FJSP 离散解码层（X -> 可行 OS+MS 染色体）============
% X 作为"优先级分数"：X_os 降序定工序加工先后，X_ms 均匀映射可选机器。
function chrom = decode_X(prob, x)
    nOp = prob.nOp;
    Xos = x(1:nOp); Xms = x(nOp+1:2*nOp);
    [~, order] = sort(Xos, 'descend');
    OS = prob.jobOf(order);
    MS = zeros(1, nOp);
    seen = zeros(1, prob.nJob);
    for t = 1:nOp
        j = OS(t); seen(j) = seen(j) + 1; kk = seen(j);
        % 阶段4：复用 select_machine 统一机器选择（X 映射 -> 钳制索引 -> 机器号）
        [m, ~] = select_machine(prob, j, kk, floor(Xms(t)*length(prob.op_mach{j}{kk})) + 1);
        MS(t) = m;
    end
    chrom = struct('OS', OS, 'MS', MS);
end

%% 修复 OS 使每个工件出现次数 = 其工序数（保证解码可行）
% 阶段4 优化：预分配计数数组 + 单次扫描配对，去除内层兜底冗余分支。
% 复用同一 cnt 数组（首次填充后直接配对，配对中同步维护 cnt），
% 配对终止即守恒（超额与不足一一配对，总数守恒保证必然收敛）。
function OS = fix_os_counts(OS, prob)
    nJob = prob.nJob; nOpPer = prob.nOpPerJob;
    cnt = zeros(1, nJob);
    for t = 1:numel(OS), cnt(OS(t)) = cnt(OS(t)) + 1; end
    % 单次扫描配对：把超额工件的首个位置改为最缺工件，直至完全守恒
    % （总数守恒 => over/under 必然同步清空，无需二次计数兜底）
    over = find(cnt > nOpPer);   % 超额工件列表（长度随配对递减，按需刷新）
    under = find(cnt < nOpPer);  % 不足工件列表
    while ~isempty(over) && ~isempty(under)
        j = over(1);  d = under(1);
        idx = find(OS == j, 1);
        OS(idx) = d;
        cnt(j) = cnt(j) - 1; cnt(d) = cnt(d) + 1;
        % 刷新受影响的超额/不足状态
        if cnt(j) == nOpPer(j), over(1) = []; end
        if cnt(d) == nOpPer(d), under(1) = []; end
    end
end

%% 目标评估（两目标，归一化到一致量级以保证均衡生效）
% 阶段2 收敛说明：本函数与 obj_of.m 共用唯一归一化入口 evaluate.m，
% 仅在此按权重合成 Z 并返回（evaluate 内部已完成 mk_ub 归一化，禁止二次除）。
% 关键修正（暗伤修复）：原实现直接返回原始 makespan 与 loadUnb，因
% makespan(~200) 量级远大于 loadUnb(~30)，导致 get_best 的 min(sum(Z,2))
% 实质上完全由 makespan 主导，loadUnb 权重被淹没，"双目标均衡"名不副实。
% 现统一以固定理论上界 prob.mk_ub 归一化（在 evaluate 内完成），两目标均落在 [0,1] 量级。
function z = obj_eval(prob, chrom, cfg)
    [Z, ~, ~, ~] = evaluate(prob, chrom, [cfg.W_MAKESPAN, cfg.W_LOAD]);
    z = Z;   % 直接复用 evaluate 的归一化加权输出，避免重复归一化导致量纲泄漏
end

%% 最优个体（含 X 一并返回）
function [b, bobj, bx] = get_best(Z, pop, X)
    [~, idx] = min(sum(Z, 2));
    b = pop{idx}; bobj = Z(idx, :); bx = X(idx, :);
end

%% AOO 开发增强：精英关键路径邻域精炼（FJSP 经典局部搜索）
% 反推真实关键路径（makespan 决定链），在关键机器上的同机工序做机器指派穷举，
% 接受使(makespan, 负荷不均衡)字典序更优的解。弥补离散 AOO 的开发不足。
function [chrom, obj, Xc] = refine_elite(prob, cfg, chrom, obj, Xc)
    K = cfg.LS_KMAX;
    for k = 1:K
        [sched, makespan, ~] = decode(prob, chrom);
        if makespan <= 0, return; end
        [critPath, critMach] = critical_path(prob, sched, makespan);
        if critMach < 1, return; end
        % 阶段4：复用 critical_block_neighborhood 统一关键块邻域定位
        [onM, locs] = critical_block_neighborhood(prob, sched, critMach);
        if numel(onM) < 2, return; end
        [~, curMk, curLv] = decode(prob, chrom);
        curUnb = max(curLv) - min(curLv);
        bestCand = chrom;
        for q = 1:numel(onM)
            tq = locs(q);
            if tq < 1 || tq > prob.nOp, continue; end
            jq = chrom.OS(tq); kq = sum(chrom.OS(1:tq) == jq);
            if kq < 1 || kq > numel(prob.op_mach{jq}), continue; end
            machSet = prob.op_mach{jq}{kq};
            if length(machSet) > 1
                for mi = 1:length(machSet)
                    c2 = chrom; c2.MS(tq) = mi;
                    [~, mk2, lv2] = decode(prob, c2);
                    unb2 = max(lv2) - min(lv2);
                    if mk2 < curMk - 1e-9 || ...
                       (abs(mk2 - curMk) < 1e-9 && unb2 < curUnb - 1e-9)
                        bestCand = c2; curMk = mk2; curUnb = unb2;
                        Xc(prob.nOp + tq) = (mi - 0.5) / length(machSet);
                    end
                end
            end
        end
        chrom = bestCand;
        obj = obj_of(prob, chrom, cfg);
    end
end

%% 阶段7：精英引导重启染色体（仅用于停滞重启）
% 以精英为基底，随机重置一段 OS 片段并随机关键机器，保留精英优质结构的同时
% 注入多样性，避免纯随机重置丢失已得信息（纯随机在强随机基线面前易退化）。
function chrom = elite_guided_restart(prob, elite)
    nOp = prob.nOp; nJob = prob.nJob;
    chrom = elite;  % 克隆精英
    % 重置一段随机 OS 片段（保持工序计数守恒由 fix_os_counts 保证）
    k = max(1, round(nOp * 0.3));
    i1 = randi(nOp - k + 1);
    seg = randi(nJob, 1, k);
    chrom.OS(i1:i1+k-1) = seg;
    chrom.OS = fix_os_counts(chrom.OS, prob);
    % 随机重置部分机器指派
    nReset = max(1, round(nOp * 0.3));
    idxs = randperm(nOp, nReset);
    for t = idxs
        j = chrom.OS(t); kk = sum(chrom.OS(1:t) == j);
        em = prob.op_mach{j}{kk};
        if numel(em) > 1, chrom.MS(t) = em(randi(numel(em))); end
    end
end

%% 自检（调试用）
function dbg_self(prob, cfg, llm_state)
    X = rand(2, 2*prob.nOp);
    p1 = decode_X(prob, X(1, :)); p2 = decode_X(prob, X(2, :));
    fprintf('p1 OS size: '); disp(size(p1.OS));
    [~, m, L, e] = aoo_params(1, 200, cfg.AOO_POP, prob.nOp, llm_state);
    c = water_xover(prob, p1, p2, m, L);
    fprintf('water OS size: '); disp(size(c.OS));
    c2 = animal_copy(prob, p1, p2, 0.9, e);
    fprintf('animal OS size: '); disp(size(c2.OS));
    levy = levy_vec(prob.nOp);
    c3 = rolling_block(prob, p2, p1, levy, 0.9);
    fprintf('rolling OS size: '); disp(size(c3.OS));
    c4 = ejection_block(prob, p2, p1, e, 0.9, prob.nOp);
    fprintf('ejection OS size: '); disp(size(c4.OS));
    wm = wind_mutate(prob, p1, 0.15);
    fprintf('wind OK\n');
end
