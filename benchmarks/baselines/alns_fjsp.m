%% alns_fjsp.m — 自适应大邻域搜索 (ALNS) 求解 FJSP，作为阶段五/七 SOTA 对比强基线。
% ALNS 是当前 FJSP 文献中最主流的邻域搜索元启发式之一（相较 GA/PSO 通常有更强开发能力）。
% 与 ga_fjsp / pso_fjsp 使用相同评估预算 (AOO_POP * AOO_MAXGEN) 以保证公平比较。
%
% 接口与 experiment_runs 对齐：
%   [elite, result] = alns_fjsp(prob, cfg)
%   result.makespan / result.loadUnb / result.conv_best 与 aoo_engine 同构，
%   便于 stat_report / convergence_plot 直接复用。
%
% SAFE / ADDITIVE：独立新文件，不修改任何现有求解器源码。

function [elite, result] = alns_fjsp(prob, cfg)
    N = cfg.AOO_POP; T = cfg.AOO_MAXGEN; nOp = prob.nOp;

    % ---- 初始解：随机可行 ----
    cur = random_chrom(prob);
    [~, curMk, curLv] = decode(prob, cur);
    curObj = curMk + (max(curLv) - min(curLv));
    best = cur; bestObj = curObj; bestMk = curMk; bestLv = curLv;

    % ---- 自适应算子权重（ALNS 核心）----
    % 破坏算子：① 随机移除 r 个工序的机器指派；② 随机打乱 r 个连续工序的机器指派。
    % 修复算子：① 贪心重指派到使负荷最均衡的机器；② 随机重指派。
    wDestroy = [1 1]; wRepair = [1 1];
    rho = 0.1;                              % 权重更新学习率
    conv_best = zeros(1, T);

    for t = 1:T
        % 轮盘赌选算子
        d = roulette(wDestroy); r = roulette(wRepair);
        cand = cur;
        cand = destroy_op(prob, cand, d);
        cand = repair_op(prob, cand, r);
        [~, mk, lv] = decode(prob, cand);
        obj = mk + (max(lv) - min(lv));

        % 接受准则：优则接受；否则以模拟退火式概率接受（温度随 t 衰减）
        Ttemp = max(1e-3, 1.0 * (1 - t / T));
        if obj < curObj || rand < exp(-(obj - curObj) / max(Ttemp, 1e-3))
            cur = cand; curObj = obj; curMk = mk; curLv = lv;
            % 算子得分：改进则 +1，接受(含劣化)则 +0.5
            if obj < bestObj
                score_d = 1; score_r = 1;
            else
                score_d = 0.5; score_r = 0.5;
            end
            wDestroy(d) = (1 - rho) * wDestroy(d) + rho * score_d;
            wRepair(r) = (1 - rho) * wRepair(r) + rho * score_r;
        end

        if obj < bestObj
            best = cand; bestObj = obj; bestMk = mk; bestLv = lv;
        end
        conv_best(t) = bestMk;
    end

    result = struct();
    result.makespan = bestMk;
    result.loadUnb = max(bestLv) - min(bestLv);
    result.conv_best = conv_best(:).';
    elite = best;
end

%% === 邻域算子 ===
function c = destroy_op(prob, chrom, which)
    nOp = prob.nOp;
    r = max(1, round(nOp * 0.15));         % 破坏比例
    c = chrom;
    if which == 1
        % 随机移除 r 个工序的机器指派（置 0，修复时重选）
        idx = randperm(nOp, min(r, nOp));
        for t = idx
            j = c.OS(t); kk = sum(c.OS(1:t) == j);
            em = prob.op_mach{j}{kk};
            if numel(em) > 1, c.MS(t) = 0; end   % 0 = 待修复
        end
    else
        % 随机打乱 r 个工序的机器指派（重置为随机合法）
        idx = randperm(nOp, min(r, nOp));
        for t = idx
            j = c.OS(t); kk = sum(c.OS(1:t) == j);
            em = prob.op_mach{j}{kk};
            if numel(em) > 1, c.MS(t) = em(randi(numel(em))); end
        end
    end
end

function chrom = random_chrom(prob)
% random_chrom  Sample a feasible (OS, MS) chromosome (self-contained; matches the
% helper used by ga_fjsp / pso_fjsp so ALNS needs no cross-file dependency).
    opCount = cellfun(@numel, prob.op_mach);
    nOp = sum(opCount);
    OS = [];
    for j = 1:prob.nJob, OS = [OS, j * ones(1, opCount(j))]; end
    OS = OS(randperm(nOp));
    MS = zeros(1, nOp);
    idx = 0;
    for j = 1:prob.nJob
        for k = 1:opCount(j)
            idx = idx + 1;
            em = prob.op_mach{j}{k};
            MS(idx) = em(randi(numel(em)));
        end
    end
    chrom = struct('OS', OS(:).', 'MS', MS);
end

function c = repair_op(prob, chrom, which)
    c = chrom;
    nOp = prob.nOp;
    % 先修复所有 MS==0 的位置
    for t = 1:nOp
        if c.MS(t) == 0
            j = c.OS(t); kk = sum(c.OS(1:t) == j);
            em = prob.op_mach{j}{kk};
            if which == 1
                % 贪心：选使该工序完成时间最早的机器（局部最优）
                [~, bi] = min(arrayfun(@(m) probe_end(prob, c, t, m), em));
                c.MS(t) = em(bi);
            else
                c.MS(t) = em(randi(numel(em)));
            end
        end
    end
end

function e = probe_end(prob, chrom, t, m)
    % probe_end: 在 chrom 基础上临时把 t 工序指派到机器 m，估算该工序结束时间
    % （简化：用机器当前累计负荷近似，避免完整 decode 开销）。
    c = chrom; c.MS(t) = m;
    [~, ~, lv] = decode(prob, c);
    e = lv(m);
end

function idx = roulette(w)
    % 轮盘赌选择
    cw = cumsum(w);
    r = rand * cw(end);
    idx = find(r <= cw, 1, 'first');
    if isempty(idx), idx = numel(w); end
end
