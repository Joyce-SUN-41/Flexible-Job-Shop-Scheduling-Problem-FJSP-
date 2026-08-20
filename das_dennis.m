%% das_dennis.m — Das & Dennis 结构化参考点（单纯形晶格）
% 独立文件：供 aoo_engine.m 跨文件调用（局部函数不可跨文件；原 nsga3_core.m 已移除）。
% M 目标, p 分层 => C(M+p-1, p) 个参考点，均匀覆盖单位单纯形。
% 例：M=3, p=12 => C(14,12)=91 个参考点。
function RP = das_dennis(M, p)
    comb = nchoosek((0:p) + M - 1, M - 1) - (M - 1);   % 组合坐标
    coords = zeros(size(comb, 1), M);
    for r = 1:size(comb, 1)
        seq = [comb(r, :), p + M - 1] - [0, comb(r, :)];   % 差分得到各分量步长
        acc = 0; vals = zeros(1, M);
        for c = 1:M
            vals(c) = seq(c) - acc;
            acc = seq(c);
        end
        coords(r, :) = vals / p;
    end
    RP = coords;
end
