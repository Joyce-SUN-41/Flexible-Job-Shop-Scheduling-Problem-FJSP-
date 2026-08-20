%% nsga3_select.m — NSGA-III 主选择算子（独立文件，跨文件可见）
% 标准 NSGA-III (Deb & Jain 2014) 主选择：父代+子代合并 -> 非支配排序 ->
% 参考点关联 -> 小生境(niche)保留。本文件为主函数 + 局部 associate / niching。
% 安全：纯函数，不触碰任何 solver 数值主链；仅在 prob.AOO_THREE_OBJ==true
% 时由 aoo_engine 委托进入。
%
% 三目标归一化向量 obj(i,:) = [mk_n, ld_n, en_n]，均落在 [0,1] 量级
% （由 evaluate.m 以 prob.mk_ub / ENERGY_UB 归一化），量纲已对齐。

%% 主选择算子：NSGA-III 一代选择（输入父代+子代合并，输出下一代 N 个下标）
% 输入：
%   objAll : (2N)×M 父代+子代合并目标矩阵（已归一化，最小化）
%   RP     : 参考点矩阵（das_dennis 生成）
%   N      : 下一代种群规模
% 输出：
%   idxKeep: 选中的 (2N) 中下标（长度 N），指向保留个体
function idxKeep = nsga3_select(objAll, RP, N)
    % 数值卫生：AO0 解码偶发 NaN/Inf（能量等）会破坏非支配排序与小生境，
    % 统一替换为"劣化"大值，确保选择稳定（安全：不改变可行解的排序语义）。
    objAll = double(objAll);
    objAll(~isfinite(objAll)) = 1e6;
    S = objAll - min(objAll, [], 1);      % 平移到理想点，坐标非负
    S(S < 0) = 0;
    fronts = non_dominated_sort(S);

    P = [];                               % 已选个体原下标
    RPcnt = zeros(size(RP, 1), 1);
    fIdx = 1;
    while fIdx <= numel(fronts)
        f = fronts{fIdx}(:).';
        if numel(P) + numel(f) <= N
            [rhoP, ~] = associate(S(f, :), RP);
            for q = 1:numel(f), RPcnt(rhoP(q)) = RPcnt(rhoP(q)) + 1; end
            P = [P, f];                   %#ok<AGROW>
            fIdx = fIdx + 1;
        else
            [rhoL, dL] = associate(S(f, :), RP);
            k = N - numel(P);
            [selPos, RPcnt] = niching(rhoL, dL, k, RPcnt);
            P = [P, f(selPos)];           %#ok<AGROW>
            break;
        end
    end
    % 兜底：若 fronts 耗尽仍不足 N（极端退化），从未选个体按第一目标贪心补齐
    if numel(P) < N
        allIdx = 1:size(objAll, 1);
        remain = setdiff(allIdx, P);
        [~, ord] = sort(sum(objAll(remain, :), 2));
        need = N - numel(P);
        P = [P, remain(ord(1:min(need, numel(ord))))];   %#ok<AGROW>
    end
    idxKeep = P(1:N);
end

%% 关联 (association)：每个个体关联到最近参考点
% 输入：
%   Sobj : N×M 平移到理想点后的目标矩阵（坐标非负）
%   RP   : K×M 参考点矩阵
% 输出：
%   rho    : N×1 关联参考点索引
%   d_perp : N×1 到关联参考点连线的垂直距离（penalty-based 小生境用）
function [rho, d_perp] = associate(Sobj, RP)
    N = size(Sobj, 1); K = size(RP, 1);
    rho = zeros(N, 1); d_perp = zeros(N, 1);
    for i = 1:N
        best = inf; br = 1;
        for k = 1:K
            w = RP(k, :); wlen = norm(w);
            if wlen < 1e-12
                d = norm(Sobj(i, :));
            else
                wu = w / wlen;
                proj = Sobj(i, :) * wu.';          % 沿参考点方向投影标量
                d = norm(Sobj(i, :) - proj * wu);  % 垂直分量
            end
            if d < best
                best = d; br = k;
            end
        end
        rho(i) = br; d_perp(i) = best;
    end
end

%% 小生境保留 (niching)：在最后一层截断处补齐剩余名额
% 输入：
%   rhoL  : 最后一层候选个体的关联参考点索引（lastlen×1）
%   dL    : 候选个体的垂直距离（lastlen×1）
%   k     : 还需补充的个体数
%   RPcnt : 当前各参考点的小生境计数（K×1）
% 输出：
%   selPos: 从 1..lastlen 中选中的候选下标
%   RPcnt : 更新后的小生境计数
function [selPos, RPcnt] = niching(rhoL, dL, k, RPcnt)
    selPos = [];
    if k <= 0, return; end
    if isempty(rhoL), return; end
    rhoL = rhoL(:).'; dL = dL(:).';        % 强制行向量，避免 horzcat 维度不一致
    while k > 0 && ~isempty(rhoL)
        avail = 1 - RPcnt;                 % 小生境容量 J=1
        candRP = unique(rhoL);
        candRP = candRP(avail(candRP) > 0);
        if isempty(candRP)
            candRP = find(RPcnt == min(RPcnt));   % 全饱和 -> 最小计数参考点
        end
        bestD = inf; bestPos = [];
        for q = 1:numel(candRP)
            rp = candRP(q);
            mem = find(rhoL == rp);
            [dmin, mi] = min(dL(mem));
            if dmin < bestD
                bestD = dmin; bestPos = mem(mi);
            end
        end
        if numel(bestPos) > 1
            bestPos = bestPos(randi(numel(bestPos)));
        end
        if isempty(bestPos)
            break;   % 防御：无可用候选（理论不应发生），交由末尾贪心补齐
        end
        j = bestPos(1);
        selPos(end+1) = j;                 % 行向量追加，方向稳定
        RPcnt(rhoL(j)) = RPcnt(rhoL(j)) + 1;
        rhoL(j) = []; dL(j) = [];          %#ok<AGROW>
        k = k - 1;
    end
    if k > 0 && ~isempty(rhoL)
        [~, ord] = sort(dL);
        take = min(k, numel(ord));
        selPos(end+1:end+take) = ord(1:take);   % 行追加补齐
    end
end
