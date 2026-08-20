function hot_run_multi()
% hot_run_multi  Run the 2026 multi-objective hottest config: 3-obj FJSP
% (makespan + load unbalance + energy) with NSGA-III quality metrics (HV/IGD).
    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');
    jsonDir = fullfile(pwd, 'logs');
    if ~exist(jsonDir,'dir'), mkdir(jsonDir); end

    fprintf('[MULTI] 3-obj LLMAOO (MK01) + NSGA-III HV/IGD\n');
    rng(20260814);
    res = llmaoo('AOO_DEFAULT_SCENARIO', 'multi', 'EXPORT_JSON', true, ...
                 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                 'AOO_MAXGEN', 80, 'AOO_POP', 60);
    resPath = fullfile(jsonDir, 'hot_multi_result.json');
    export_result_json(res, resPath);
    fprintf('  mk=%.1f loadUnb=%.1f\n', res.makespan, res.loadUnb);
    if isfield(res, 'quality')
        fprintf('  NSGA-III quality: HV=%.4f IGD=%.4f PFsize=%d\n', ...
                res.quality.HV, res.quality.IGD, res.quality.nPF);
    else
        fprintf('  [warn] quality field absent (3-obj not active?)\n');
    end
    fprintf('  multi -> %s\n', resPath);
end
