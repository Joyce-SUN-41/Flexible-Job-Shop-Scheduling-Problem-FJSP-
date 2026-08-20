%% 目标评估包装（阶段2 收敛：与 obj_eval 共用 evaluate 唯一入口）
% 返回归一化加权目标 [Z]，与 aoo_engine 内 obj_eval 完全一致，
% 供 refine_elite 做字典序比较（单调缩放不改变比较结果）。
function o = obj_of(prob, chrom, cfg)
    [Z, ~, ~, ~] = evaluate(prob, chrom, [cfg.W_MAKESPAN, cfg.W_LOAD]);
    o = Z;
end
