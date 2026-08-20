%% non_dominated_sort.m — NSGA-II 快速非支配排序
% 给定目标矩阵 objs(N x m)，返回每个个体的支配层级 fronts（cell 数组），
% fronts{1} 为第一非支配层（Pareto 最优）。算法为 Deb et al. 的经典 O(m N^2) 实现，
% 数值稳健（处理相等目标视为互不支配）。
function fronts = non_dominated_sort(objs)
    N = size(objs, 1);
    if N == 0
        fronts = {};
        return;
    end
    % 预分配稀疏支配关系
    dominatedBy = cell(N, 1);   % 被谁支配
    domCount    = zeros(N, 1);  % 支配本体的个数
    dominatedTo = cell(N, 1);   % 本体支配谁
    for i = 1:N
        dominatedBy{i}  = [];
        dominatedTo{i} = [];
    end
    for i = 1:N
        for j = i+1:N
            if dominates(objs(i,:), objs(j,:))
                dominatedTo{i} = [dominatedTo{i}, j];
                domCount(j) = domCount(j) + 1;
            elseif dominates(objs(j,:), objs(i,:))
                dominatedBy{i} = [dominatedBy{i}, j];
                domCount(i) = domCount(i) + 1;
            end
        end
    end
    % 第一层：不被任何个体支配
    current = find(domCount == 0);
    fronts = {};
    fIdx = 1;
    while ~isempty(current)
        fronts{fIdx} = current;
        next = [];
        for q = current
            qt = dominatedTo{q};
            for kk = 1:numel(qt)
                p = qt(kk);
                domCount(p) = domCount(p) - 1;
                if domCount(p) == 0
                    next = [next, p]; %#ok<AGROW>
                end
            end
        end
        current = next;
        fIdx = fIdx + 1;
    end
end

%% 支配判定：a 支配 b 当且仅当 a 在所有目标上 <= b 且至少一处严格 <
function flag = dominates(a, b)
    flag = all(a <= b) && any(a < b);
end
