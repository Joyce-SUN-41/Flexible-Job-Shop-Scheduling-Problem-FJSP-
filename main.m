%% main.m — 项目入口
% LLMAOO：LLM (DeepSeek) 调度知识中枢 × AOO 群体智能优化引擎，求解 FJSP。
% 直接运行即可求解 data.mat 中的实例并生成可视化报告。
% 可选覆盖参数： llmaoo('AOO_MAXGEN',100,'AOO_POP',80)
% 注：未配置 DeepSeek API Key 时自动降级本地启发式，离线可跑。

clc; clear;
fprintf('========================================\n');
fprintf(' 柔性作业车间调度求解器 (LLMAOO)\n');
fprintf('========================================\n\n');

result = llmaoo();

fprintf('\n===== 运行摘要 =====\n');
fprintf('最优 makespan: %.1f | 机器负荷不均衡: %.1f\n', result.makespan, result.loadUnb);
fprintf('实际迭代: %d 代 | 运行耗时: %.1f 秒\n', result.iters, result.elapsed_sec);
fprintf('提示: 收敛曲线/甘特图/机器负荷图已显示，PNG 存于 ./figures。\n');
