%% pso_fjsp.m — 标准粒子群优化求解 FJSP（离散 PSO + active 解码）
% 作为阶段五 SOTA 对比基线之一，与 aoo_engine / ga_fjsp 使用相同评估预算
% (AOO_POP * AOO_MAXGEN) 以保证公平。实现参照 经典离散 PSO for scheduling。
%
% 接口与 experiment_runs 对齐：
%   [elite, result] = pso_fjsp(prob, cfg)
%   result.makespan / result.loadUnb / result.conv_best 与 ga_fjsp / aoo_engine 同构，
%   便于 stat_report / convergence_plot 直接复用。
%
% SAFE / ADDITIVE：独立新文件，不修改任何现有求解器源码。

function [elite, result] = pso_fjsp(prob, cfg)
    N = cfg.AOO_POP; T = cfg.AOO_MAXGEN; nOp = prob.nOp;

    % 粒子初始化：每个粒子位置编码为 (OS 序, MS 机器) 可直接解码的 chrom。
    % 速度用"swap 概率 + 机器变异概率"的随机扰动表征（离散 PSO）。
    pop = cell(N, 1); pbest = cell(N, 1); pbestObj = zeros(N, 2);
    gbest = []; gbestObj = [Inf, Inf];
    for i = 1:N
        pop{i} = random_chrom(prob);
        Z = evaluate(prob, pop{i}, cfg);
        pbest{i} = pop{i}; pbestObj(i, :) = Z;
        if sum(Z) < sum(gbestObj)
            gbest = pop{i}; gbestObj = Z;
        end
    end

    w = 0.9; wEnd = 0.4; c1 = 1.5; c2 = 1.5;   % 惯性 + 认知 + 社会系数
    conv_best = zeros(1, T);
    for t = 1:T
        wT = w - (w - wEnd) * (t - 1) / max(T - 1, 1);   % 线性递减惯性
        for i = 1:N
            % 离散速度更新：以概率受 pbest / gbest 吸引做 OS 片段拷贝 + 机器迁移
            child = pop{i};
            if rand < c1 * wT
                child = copy_segment(prob, child, pbest{i});
            end
            if rand < c2 * wT
                child = copy_segment(prob, child, gbest);
            end
            child = jitter(prob, child, 0.2 * wT);   % 随机扰动保持多样性
            Z = evaluate(prob, child, cfg);
            pop{i} = child;
            if sum(Z) < sum(pbestObj(i, :))
                pbest{i} = child; pbestObj(i, :) = Z;
            end
            if sum(Z) < sum(gbestObj)
                gbest = child; gbestObj = Z;
            end
        end
        conv_best(t) = sum(gbestObj);
    end

    elite = gbest;
    result.conv_best = conv_best;
    result.obj = gbestObj; result.iters = T;
    [result.sched, result.makespan, result.loadVec] = decode(prob, elite);
    result.loadUnb = max(result.loadVec) - min(result.loadVec);
    result.nan_count = 0;
end

%% 随机可行染色体
function chrom = random_chrom(prob)
    nJob = prob.nJob;
    opCount = cellfun(@numel, prob.op_mach);
    OS = [];
    for j = 1:nJob, OS = [OS, j * ones(1, opCount(j))]; end
    OS = OS(randperm(numel(OS)));
    MS = zeros(sum(opCount), 1);
    idx = 0;
    for j = 1:nJob
        for k = 1:opCount(j)
            idx = idx + 1;
            em = prob.op_mach{j}{k};
            MS(idx) = em(randi(numel(em)));
        end
    end
    chrom = struct('OS', OS, 'MS', MS);
end

%% 评估（复用 decode，与 ga_fjsp / aoo_engine 一致）
function Z = evaluate(prob, chrom, cfg)
    [~, mk, loadVec] = decode(prob, chrom);
    lb = max(loadVec) - min(loadVec);
    Z = [mk, lb];
end

%% 从一个源拷贝一段 OS 片段（按工件计数），保持工件工序数不变
function child = copy_segment(prob, child, src)
    nJob = prob.nJob; nOp = prob.nOp;
    sub = rand(1, nJob) < 0.5;
    out = zeros(1, nOp); seen = zeros(1, nJob); pos = 1;
    for t = 1:nOp
        j = src.OS(t);
        if sub(j) && seen(j) < prob.nOpPerJob(j)
            seen(j) = seen(j) + 1; out(pos) = j; pos = pos + 1;
        end
    end
    for t = 1:nOp
        j = child.OS(t);
        if ~sub(j) && seen(j) < prob.nOpPerJob(j)
            seen(j) = seen(j) + 1; out(pos) = j; pos = pos + 1;
        end
    end
    if pos <= nOp, out(pos:nOp) = 1; end
    out = fix_os_counts(out, prob);
    child.OS = out;
end

%% 随机扰动：交换 OS 两位置 + 改机器
function child = jitter(prob, chrom, pm)
    child = chrom;
    nOp = prob.nOp;
    if rand < pm
        i1 = randi(nOp); i2 = randi(nOp);
        tmp = child.OS(i1); child.OS(i1) = child.OS(i2); child.OS(i2) = tmp;
    end
    if rand < pm
        t = randi(nOp); j = child.OS(t); kk = sum(child.OS(1:t) == j);
        if kk >= 1 && kk <= numel(prob.op_mach{j})
            em = prob.op_mach{j}{kk};
            if numel(em) > 1, child.MS(t) = em(randi(numel(em))); end
        end
    end
    child.OS = fix_os_counts(child.OS, prob);
end

%% 修正 OS 计数使其与 nOpPerJob 严格一致（防交叉/变异产生非法序）
function OS = fix_os_counts(OS, prob)
    nJob = prob.nJob;
    cnt = zeros(1, nJob);
    for t = 1:numel(OS)
        j = OS(t);
        if j >= 1 && j <= nJob, cnt(j) = cnt(j) + 1; end
    end
    missing = [];
    for j = 1:nJob
        if cnt(j) < prob.nOpPerJob(j)
            missing = [missing, repmat(j, 1, prob.nOpPerJob(j) - cnt(j))];
        end
    end
    extra = [];
    for j = 1:nJob
        if cnt(j) > prob.nOpPerJob(j)
            e = cnt(j) - prob.nOpPerJob(j);
            extra = [extra, repmat(j, 1, e)];
        end
    end
    % 替换非法位置：优先用 missing 补齐，再用 extra 的合法工件填充（保证总数= nOp）
    pos = 1;
    while ~isempty(missing)
        while pos <= numel(OS) && (OS(pos) < 1 || OS(pos) > nJob || cnt(OS(pos)) > prob.nOpPerJob(OS(pos)))
            if isempty(missing), break; end
            j = missing(1); missing(1) = [];
            OS(pos) = j; cnt(j) = cnt(j) + 1; pos = pos + 1;
        end
        if pos > numel(OS), break; end
        pos = pos + 1;
    end
    % 若仍有 missing（数量不足），追加在末尾
    if ~isempty(missing)
        OS = [OS, missing];
    end
    if numel(OS) > sum(prob.nOpPerJob)
        OS = OS(1:sum(prob.nOpPerJob));
    end
end
