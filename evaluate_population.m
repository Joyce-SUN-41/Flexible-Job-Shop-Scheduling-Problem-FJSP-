%% evaluate_population.m — 种群批量评估封装（阶段3：统一评估入口）
% 将 aoo_engine 中散落的逐个体 obj_eval 调用收敛到单一接口，
% 统一维度、便于未来并行化与缓存，且不改变任何数值语义。
%
% 用法：
%   Z = evaluate_population(prob, pop, cfg)                  % 评估全部个体
%   Z = evaluate_population(prob, pop, cfg, idx)             % 仅评估 idx 指定个体
%   Z = evaluate_population(prob, pop, cfg, idx, Zbase)      % 子集评估，其余位置沿用 Zbase
%
% 输入：
%   prob : 问题实例（load_data 返回）
%   pop  : cell 数组，pop{i} 为标量 chrom struct
%   cfg  : 全局配置（使用 W_MAKESPAN / W_LOAD）
%   idx  : 可选，1×k 正整数向量，指定要评估的种群下标（默认 1:numel(pop)）
%   Zbase: 可选，N×2 基底矩阵；子集模式下未被 idx 覆盖的位置沿用 Zbase，
%          避免丢失未修改个体的目标值（与 aoo_engine Phase3/4 提速语义一致）
% 输出：
%   Z    : N×2 矩阵，Z(i,:) = [makespan, loadUnb]
%
% 并行说明：默认串行（for）。若需启用并行，将 cfg.AOO_PARALLEL 设为 true
%   且已安装 Parallel Computing Toolbox，则对全群评估走 parfor。
%   子集评估（带 idx）始终串行，避免 parfor 切片复杂性。当前默认关闭，零风险。

function Z = evaluate_population(prob, pop, cfg, idx, Zbase)
    N = numel(pop);
    if nargin < 5 || isempty(Zbase)
        Z = zeros(N, 2);
    else
        Z = Zbase;   % 子集模式：沿用基底，仅覆盖 idx 位置
    end
    % Stage9-viz fix: 返回加权归一化两目标 [w_mk*mk_n, w_ld*ld_n]，而非 obj_eval
    % 的标量加权和。原因：原 obj_eval 返回标量被赋给 Z(i,:)（2 列）会整行广播成
    % 同一加权和值，导致 build_pareto 的 pareto.Z/obj3 两维相同（归一化失真）。
    % 改为两列加权向量后，sum(Z,2) 仍等于原加权和（get_best 语义不变，零回归），
    % 且 Pareto 存档得到正确的 [mk_n, ld_n] 分离维度。
    % 阶段二 P1: 三目标权重扩展。当 prob.AOO_THREE_OBJ 开启时，权重扩展为
    % [W_MAKESPAN, W_LOAD, W_ENERGY] 三元组，使 evaluate 的 energy 第三维真正
    % 参与加权和（修复旧代码 w3=0 恒为 0 的"伪三目标"退化）。默认关时仅传二元
    % 组 [W_MAKESPAN, W_LOAD] => evaluate 内 w3 维持 0，主链数值完全不变（零回归）。
    % 注意：返回的 Z 始终是 N×2（前两维加权），energy 不参与 Z 也不进 sum(Z,2)
    % （精英排序仍用两目标加权和），仅 extra.obj 携带三目标向量供 Pareto/NSGA-III。
    if isfield(prob, 'AOO_THREE_OBJ') && prob.AOO_THREE_OBJ ...
            && isfield(cfg, 'W_ENERGY')
        w = [cfg.W_MAKESPAN, cfg.W_LOAD, cfg.W_ENERGY];
    else
        w = [cfg.W_MAKESPAN, cfg.W_LOAD];
    end
    if nargin < 4 || isempty(idx)
        idx = 1:N;
        usePar = isfield(cfg, 'AOO_PARALLEL') && cfg.AOO_PARALLEL ...
                 && exist('parpool', 'file') == 2;
        if usePar
            parfor i = 1:N
                [~, ~, ~, ~, ex] = evaluate(prob, pop{i}, w);
                zi = [w(1) * ex.obj(1), w(2) * ex.obj(2)];
                Z(i, :) = zi;
            end
        else
            for i = 1:N
                [~, ~, ~, ~, ex] = evaluate(prob, pop{i}, w);
                Z(i, :) = [w(1) * ex.obj(1), w(2) * ex.obj(2)];
            end
        end
    else
        % 子集评估：串行，仅覆盖 idx 指定位置（其余沿用 Zbase）
        for k = 1:numel(idx)
            i = idx(k);
            [~, ~, ~, ~, ex] = evaluate(prob, pop{i}, w);
            Z(i, :) = [w(1) * ex.obj(1), w(2) * ex.obj(2)];
        end
    end
end
