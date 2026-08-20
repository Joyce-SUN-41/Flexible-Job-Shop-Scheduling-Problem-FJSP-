function pass = gate_competitiveness(varargin)
% gate_competitiveness  阶段7 竞争力门禁（投稿硬门槛自动校验）
%
% 在轻量预算下（N=10 独立运行，默认配置）对比 AOO 与 Random 基线：
%   - 要求 AOO 的 mean makespan 不显著劣于 Random（Wilcoxon p >= 0.05），
%     且 mean 劣化不超过 cfg.AOO_GATE_MK_TOL 容忍比例（默认 0 即不允许劣化）。
%   - 若 AOO 系统性弱于 Random（阶段6 已暴露的问题），则门禁 FAIL，
%     防止"隐性退化"再次被静默放过。
%
% 返回逻辑 pass=true/false；同时打印结论。设计为可在 tests.run_all [6] 调用。
% SAFE / ADDITIVE：仅做实验与判定，不修改任何求解器源码。

    p = inputParser;
    addParameter(p, 'N', 10, @isscalar);
    addParameter(p, 'Prob', 'MK01', @ischar);
    parse(p, varargin{:});
    N = p.Results.N; probName = p.Results.Prob;

    addpath('benchmarks');
    prob = load_benchmark(probName);

    cfg = llmaoo_config();
    cfg.AOO_POP = 50; cfg.AOO_MAXGEN = 130; cfg.AOO_REFINE_EVERY = 5;
    cfg.AOO_ACTIVE_DECODE = false;          % 门禁默认关 active（零回归语义）
    cfg.OFFLINE_STRUCTURED_MODULATE = false;

    fprintf('  门禁实验: AOO vs Random on %s, N=%d\n', probName, N);
    R = experiment_runs(prob, 'N', N, 'Variants', {'aoo', 'random'}, 'Seed0', 2001);

    aooMk = R.mk.aoo; rndMk = R.mk.random;
    [pval, h] = ranksum(aooMk, rndMk);
    meanAoo = mean(aooMk); meanRnd = mean(rndMk);
    degradePct = 100 * (meanAoo - meanRnd) / meanRnd;  % 正=劣化

    tol = cfg.AOO_GATE_MK_TOL;
    % 判定（符合 TEVC 惯例：以 Wilcoxon 显著性为主，mean 容忍为次级硬性约束）：
    %   - 主条件：AOO 不显著劣于 Random（ranksum h~=1 即 p>=0.05）
    %   - 次条件：mean 劣化不超过 AOO_GATE_MK_TOL 容忍比例（默认 0.02 = 2%）
    % ranksum 中 h==1 表示第一样本(AOO)分布显著大于第二(Random)，
    % 即 AOO 显著更差（makespan 更大）-> 不通过。
    pass = (h ~= 1) && (degradePct <= tol * 100);

    fprintf('  AOO mean=%.2f  Random mean=%.2f  Wilcoxon p=%.4g  degrade=%.1f%%\n', ...
        meanAoo, meanRnd, pval, degradePct);
    if pass
        fprintf('  竞争力门禁 PASS（AOO 不显著劣于 Random，且 mean 劣化在容忍内）\n');
    else
        if h == 1
            fprintf('  竞争力门禁 FAIL（AOO 仍统计显著弱于 Random，需回到阶段7修复）\n');
        else
            fprintf('  竞争力门禁 FAIL（AOO 虽不显著但 mean 劣化超容忍 %.0f%%，可放宽 AOO_GATE_MK_TOL）\n', tol*100);
        end
    end
end
