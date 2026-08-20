%% crowding.m — NSGA-II 拥挤度距离计算
% 输入 fronts（non_dominated_sort 的 cell 输出）与 objs(N x m)，
% 返回 crowd(N x 1)，同一前沿内按各目标归一化后相邻差之和，
% 边界个体（每目标极值）拥挤度设为 Inf（优先保留多样性）。
function crowd = crowding(fronts, objs)
    N = size(objs, 1);
    crowd = zeros(N, 1);
    if N == 0, return; end
    m = size(objs, 2);
    % 每目标归一化范围（避免量纲差异导致拥挤度被单一目标主导）
    objMin = min(objs, [], 1);
    objMax = max(objs, [], 1);
    objRange = objMax - objMin;
    objRange(objRange == 0) = 1;  % 退化目标保护
    for f = 1:numel(fronts)
        idx = fronts{f};
        if numel(idx) <= 2
            crowd(idx) = Inf;
            continue;
        end
        normObj = (objs(idx, :) - objMin) ./ objRange;  % 归一化
        cd = zeros(numel(idx), 1);
        for k = 1:m
            [~, ord] = sort(normObj(:, k));
            cd(ord(1)) = Inf;
            cd(ord(end)) = Inf;
            for r = 2:(numel(idx)-1)
                cd(ord(r)) = cd(ord(r)) + (normObj(ord(r+1), k) - normObj(ord(r-1), k));
            end
        end
        crowd(idx) = cd;
    end
end
