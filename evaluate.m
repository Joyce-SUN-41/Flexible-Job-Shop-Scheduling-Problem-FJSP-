%% evaluate.m — 单染色体多目标适应度评估
% 目标1：makespan（最大完工时间）—— 越小越好
% 目标2：机器负荷不均衡度 = max(load)-min(load) —— 越小越好（资源均衡）
% 为适应度（最小化）：先对两个目标做固定上界归一化，再加权合成
%   Z = w_makespan * norm(makespan) + w_load * norm(load_unbalance)
%
% 改进3：归一化改用"固定理论上界"（prob.mk_ub = 各工序最快可选机器工时之和），
%   使得适应度量纲跨代恒定、无漂移，且无需首代探边界。
%   makespan 与 load_unbalance 均以 mk_ub 为分母归一化到 [0,1] 量级。
%
% === Stage8 extension (safe: default zero regression) ===
% When prob.has_energy==true and cfg.AOO_THREE_OBJ==true, returns a 5th output
%   extra.obj = [mk_n, load_n, energy_n] (three-obj vector), and adds energy to Z
%   via w(3) (default 0 => main chain numerically unchanged).
% Otherwise behavior is identical to Stage1-7.

function [Z, makespan, loadUnb, sched, extra] = evaluate(prob, chrom, w)
    % 唯一归一化评估入口（阶段2 收敛后 obj_eval/obj_of 均复用本函数）。
    % --- 入口防御（fail-fast）---
    if nargin < 3 || isempty(w)
        w = [1.0, 1.0];
    elseif ~isvector(w) || (numel(w) ~= 2 && numel(w) ~= 3)
        error('evaluate:BadWeight', 'w 必须是长度 2 或 3 的权重向量，收到 %d 个元素', numel(w));
    end
    w = w(:).';   % 行向量

    [sched, makespan, loadVec] = decode(prob, chrom);
    loadUnb = max(loadVec) - min(loadVec);

    % --- 阶段一修复：负荷不均衡归一化改用负荷差物理上界 load_ub ---
    % 旧代码两目标均用 makespan 上界 mk_ub(~200) 归一化 loadUnb(~7)，致 ld≈0.035，
    % 双目标加权和实质被 makespan 单目标主导，"双目标均衡"名不副实。
    % 现 makespan 仍用 mk_ub 归一化（同数量级合理）；loadUnb 改用 load_ub（=mk_ub，
    % 即全部工序最快工时之和，负荷差恒 ≤ 此值），使 ld 与 mk 同量级、恢复均衡语义。
    % load_ub 缺失时回退 mk_ub（兼容未构造该字段的旧路径，零回归）。
    if isfield(prob, 'load_ub') && isnumeric(prob.load_ub) ...
            && isscalar(prob.load_ub) && isfinite(prob.load_ub) && prob.load_ub > 0
        lub = prob.load_ub;
    else
        lub = prob.mk_ub;
    end
    % ---- 防御：确保分母为有限正标量 double，杜绝 struct→double 崩溃（阶段一 P2）----
    % 旧 struct→double 崩溃根因：prob.mk_ub/prob.load_ub 偶发为非标量或 struct，
    % 直接 isfinite(struct) 抛错。必须先做 isinstance/numeric 类型守卫再数值校验。
    ub = prob.mk_ub;
    if ~isnumeric(ub) || ~isscalar(ub) || ~isfinite(ub) || ub <= 0
        ub = 1e-9;
    end
    if ~isnumeric(lub) || ~isscalar(lub) || ~isfinite(lub) || lub <= 0
        lub = 1e-9;
    end

    mk = makespan / ub;                    % 归一化 makespan ∈ ~[0,1]
    ld = loadUnb / lub;                    % 归一化负荷不均衡 ∈ ~[0,1]，与 mk 同量级

    % 能耗第三目标（阶段8，默认关）
    if nargout >= 5 && isfield(prob,'has_energy') && prob.has_energy ...
            && isfield(prob,'AOO_THREE_OBJ') && prob.AOO_THREE_OBJ
        energy = compute_energy(prob, chrom);
        % 阶段二 P1: 优先用固定理论上界 prob.e_ub（由 attach_energy 构造，
        % e_ub = Σ_j Σ_k max_m(能耗)），使 en 在 [0,1] 真实分化，消除旧代码
        % get_eub 自适应 "1.5*energy+1" 使 en→1/1.5=0.667 渐近线塌缩（旧导出
        % obj3 第三维恒 0.6645 的根因）。固定上界缺失时退回保守自适应兜底。
        e_ub = get_eub(prob, energy);
        en = energy / max(e_ub, 1e-9);
        % 阶段二 P1 (安全修复): w3 默认 0，仅当调用方显式传入 3 元素权重时才取
        % cfg.W_ENERGY（由 evaluate_population 在 AOO_THREE_OBJ 开启时传入）。
        % 默认关 AOO_THREE_OBJ 时 evaluate_population 传 [W_MAKESPAN, W_LOAD]（2 元素），
        % 此处 w3 维持 0 => 主链加权和数值完全不变（零回归）。
        w3 = 0;
        if numel(w) >= 3, w3 = w(3); end
        Z = w(1) * mk + w(2) * ld + w3 * en;
        extra = struct('obj', [mk, ld, en], 'energy', energy, 'energy_n', en);
    else
        Z = w(1) * mk + w(2) * ld;
        if nargout >= 5
            extra = struct('obj', [mk, ld], 'energy', NaN, 'energy_n', NaN);
        end
    end
end

% 累加已选机器的单位工序能耗
function energy = compute_energy(prob, chrom)
    energy = 0;
    ms = chrom.MS; os = chrom.OS;
    jobOpPtr = zeros(1, prob.nJob);
    for t = 1:length(os)
        j = os(t);
        jobOpPtr(j) = jobOpPtr(j) + 1;
        k = jobOpPtr(j);
        mIdx = min(max(ms(t), 1), length(prob.op_mach{j}{k}));
        m = prob.op_mach{j}{k}(mIdx);
        if k <= numel(prob.energy{j}) && m >= 1 && m <= numel(prob.energy{j}{k})
            energy = energy + prob.energy{j}{k}(m);
        end
    end
end

function e_ub = get_eub(prob, energy)
    % 阶段二 P1: 优先固定理论界 prob.e_ub（attach_energy 构造）；其次配置项
    % ENERGY_UB；最后才退回保守自适应兜底（仅兜底，正常路径不走）。
    if isfield(prob,'e_ub') && prob.e_ub > 0
        e_ub = prob.e_ub;
    elseif isfield(prob,'ENERGY_UB') && prob.ENERGY_UB > 0
        e_ub = prob.ENERGY_UB;
    else
        e_ub = 1.5 * energy + 1;   % 保守兜底（正常路径不应触发）
    end
end
