%% obj_eval.m — 单染色体两目标评估（独立文件，供 evaluate_population 跨文件调用）
% 阶段5 修复：原 obj_eval 作为 aoo_engine.m 的局部函数，evaluate_population.m
% 作为独立文件无法访问，导致 -batch 下 "函数或变量 'obj_eval' 无法识别"。
% 现提升为独立文件，保持与 aoo_engine 内局部版本完全一致的数值语义。
%
% 归一化入口唯一：仅调用 evaluate.m（其内部以 prob.mk_ub 归一化 makespan、
% 以 cfg.W_LOAD 归一化 loadUnb），本函数不再做任何二次归一化，避免量纲泄漏。
% 输出 Z = [makespan_n, loadUnb_n]，两目标均落在 [0,1] 量级，保证双目标均衡生效。
function z = obj_eval(prob, chrom, cfg)
    [Z, ~, ~, ~] = evaluate(prob, chrom, [cfg.W_MAKESPAN, cfg.W_LOAD]);
    z = Z;
end
