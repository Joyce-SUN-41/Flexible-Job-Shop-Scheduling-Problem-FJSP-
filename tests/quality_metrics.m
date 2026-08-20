function quality_metrics()
% quality_metrics — Stage B 轻量自检：NSGA-III 标准指标 (HV/IGD) 正确性验证
% 不跑完整求解，仅验证 nsga3_quality 在合成三目标点集上的数值正确性，
% 以及 define_problem('multi') 存档链路能产出三目标 obj3 向量。
% Run: cd project root in MATLAB, then execute tests.quality_metrics

    fprintf('==== Stage B quality metrics self-test ====\n');
    rng(20260812);

    % 1. 合成三目标点集：Pareto 前沿应为一条递减曲线，HV>0、IGD 有限
    fprintf('\n[1] nsga3_quality on synthetic 3-obj front\n');
    S = 30;
    x = linspace(0.1, 0.9, S).';
    synth = [x, 1 - x, 0.2 + 0.1*rand(S,1)];   % mk_n 增、ld_n 减、en_n 微扰
    Q = nsga3_quality(synth);
    assert(isfinite(Q.HV) && Q.HV > 0, 'HV must be positive finite');
    assert(isfinite(Q.IGD) && Q.IGD >= 0, 'IGD must be finite non-negative');
    assert(Q.nPF > 0 && Q.nPF <= S, 'PF size invalid');
    % 自适应参考点应覆盖解空间（各分量 > 解最大）
    assert(all(max(Q.ref,[],1) >= max(synth,[],1)), 'ref must cover PF');
    fprintf('  HV=%.4f IGD=%.4f nPF=%d nRef=%d OK\n', Q.HV, Q.IGD, Q.nPF, size(Q.ref,1));

    % 2. 退化点集（全部相同）应仍可计算且不崩溃
    fprintf('\n[2] degenerate point set (no crash)\n');
    deg = repmat([0.5 0.5 0.5], 10, 1);
    Qd = nsga3_quality(deg);
    assert(isfinite(Qd.HV), 'degenerate HV must be finite');
    fprintf('  degenerate HV=%.4f IGD=%.4f OK\n', Qd.HV, Qd.IGD);

    % 3. 端到端：multi 模式存档产出三目标 obj3，且 nsga3_quality 可用
    fprintf('\n[3] end-to-end multi archive -> obj3 -> quality\n');
    cfg = llmaoo_config();
    cfg.AOO_THREE_OBJ = true;
    p = load_data(cfg.DATA_FILE);
    pa = attach_stage8(p, cfg);
    assert(pa.has_energy && pa.AOO_THREE_OBJ, 'multi attach failed');
    % 轻量主链（足够代数以收集稳定存档）
    rng(cfg.RNG_SEED);
    res = llmaoo('AOO_DEFAULT_SCENARIO', 'multi', 'AOO_MAXGEN', 40);
    assert(isfield(res, 'pareto') && isfield(res.pareto, 'obj3'), 'pareto.obj3 missing');
    assert(size(res.pareto.obj3, 2) == 3, 'obj3 must be N x 3');
    assert(all(isfinite(res.pareto.obj3(:))), 'obj3 must be finite');
    assert(isfield(res, 'quality') && isfinite(res.quality.HV) && res.quality.HV >= 0, ...
        'quality.HV must be finite non-negative');
    assert(isfinite(res.quality.IGD) && res.quality.IGD >= 0, 'quality.IGD must be finite non-negative');
    fprintf('  archive PF size=%d, HV=%.4f IGD=%.4f OK\n', ...
            res.quality.nPF, res.quality.HV, res.quality.IGD);

    fprintf('\n==== Stage B quality metrics self-test ALL PASS ====\n');
end
