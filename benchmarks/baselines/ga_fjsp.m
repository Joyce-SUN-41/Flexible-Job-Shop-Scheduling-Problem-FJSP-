%% ga_fjsp.m — 标准遗传算法求解 FJSP（POX 交叉 + 插入/机器变异 + active 解码）
% 作为阶段7 SOTA 对比基线之一，与 aoo_engine 使用相同评估预算
% (AOO_POP * AOO_MAXGEN) 以保证公平。实现参照 Gao & Li (2009) 等经典 FJSP-GA。
%
% 接口与 experiment_runs 对齐：
%   [elite, result] = ga_fjsp(prob, cfg)
%   result.makespan / result.loadUnb / result.conv_best 与 aoo_engine 同构，
%   便于 stat_report / convergence_plot 直接复用。
%
% SAFE / ADDITIVE：独立新文件，不修改任何现有求解器源码。

function [elite, result] = ga_fjsp(prob, cfg)
    N = cfg.AOO_POP; T = cfg.AOO_MAXGEN; nOp = prob.nOp;

    % 初始化种群
    pop = cell(N, 1);
    for i = 1:N
        pop{i} = random_chrom(prob);
    end
    Z = evaluate_population(prob, pop, cfg);
    [elite, eliteObj] = get_best_ga(Z, pop);

    conv_best = zeros(1, T);
    for t = 1:T
        % 锦标赛选择 + POX 交叉 + 变异
        newPop = cell(N, 1);
        for i = 1:N
            p1 = tournament(prob, pop, Z, 3);
            p2 = tournament(prob, pop, Z, 3);
            child = pox_xover(prob, p1, p2);
            child = mutate_ga(prob, child, 0.2);  % 变异概率
            newPop{i} = child;
        end
        Z = evaluate_population(prob, newPop, cfg);
        % 精英保留（与 aoo 同：按两目标和 min 选最优）
        [b, bobj] = get_best_ga(Z, newPop);
        if sum(bobj) < sum(eliteObj)
            elite = b; eliteObj = bobj;
        end
        % 用 elite 替换最差（经典精英保留）
        [~, worstIdx] = max(sum(Z, 2));
        newPop{worstIdx} = elite;
        pop = newPop;
        conv_best(t) = sum(eliteObj);
    end

    result.conv_best = conv_best;
    result.obj = eliteObj; result.iters = T;
    [result.sched, result.makespan, result.loadVec] = decode(prob, elite);
    result.loadUnb = max(result.loadVec) - min(result.loadVec);
    result.nan_count = 0;
end

%% 随机可行染色体
function chrom = random_chrom(prob)
    nJob = prob.nJob;
    opCount = prob.nOpPerJob;
    OS = [];
    for j = 1:nJob, OS = [OS, j * ones(1, opCount(j))]; end
    OS = OS(randperm(numel(OS)));
    MS = zeros(1, prob.nOp);
    seen = zeros(1, nJob);
    for t = 1:prob.nOp
        j = OS(t); seen(j) = seen(j) + 1; kk = seen(j);
        em = prob.op_mach{j}{kk};
        MS(t) = em(randi(numel(em)));
    end
    chrom = struct('OS', OS, 'MS', MS);
end

%% 锦标赛选择
function c = tournament(prob, pop, Z, k)
    idx = randperm(numel(pop), k);
    [~, best] = min(sum(Z(idx, :), 2));
    c = pop{idx(best)};
end

%% POX 交叉（先序工件交叉，保证工序优先级）
function child = pox_xover(prob, p1, p2)
    nJob = prob.nJob; nOp = prob.nOp;
    sub = rand(1, nJob) < 0.5;
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
    % 兜底
    if pos <= nOp, childOS(pos:nOp) = 1; end
    childOS = fix_os_counts(childOS, prob);
    % MS：取 p1
    child = struct('OS', childOS, 'MS', p1.MS);
end

%% 变异：交换 OS 两位置 + 改机器
function child = mutate_ga(prob, chrom, pm)
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

%% 最优个体（按两目标和）
function [b, bobj] = get_best_ga(Z, pop)
    [~, idx] = min(sum(Z, 2));
    b = pop{idx}; bobj = Z(idx, :);
end

%% 修正 OS 计数使其与 nOpPerJob 严格一致（防交叉/变异产生非法序）
% GA 基线修复（阶段五 SOTA 对比暴露的缺失辅助函数）。纯 ADDITIVE。
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
    if ~isempty(missing)
        OS = [OS, missing];
    end
    if numel(OS) > sum(prob.nOpPerJob)
        OS = OS(1:sum(prob.nOpPerJob));
    end
end
