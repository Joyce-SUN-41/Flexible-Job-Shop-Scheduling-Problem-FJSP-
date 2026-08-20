function stage6_run(varargin)
% stage6_run  Stage-6 unified experiment driver for TEVC-class evidence.
%
%   tests.stage6_run                 % quick check: N=5 on MK01
%   tests.stage6_run('N',30,'Prob','MK01')   % publication-grade: 30 independent runs
%   tests.stage6_run('N',30,'Prob','data')   % use the project's own data.mat instance
%
% Pipeline:
%   1. load benchmark (MK01 built-in, or 'data' for data.mat, or external .fjs)
%   2. experiment_runs  -> N independent runs of AOO / Random (and full LLMAOO if key)
%   3. stat_report      -> mean/std/CI + Wilcoxon rank-sum significance
%   4. ablation         -> component contribution (AOO vs Random; full vs AOO if online)
%   5. convergence_plot -> export convergence + Pareto figures to figures/
%
% SAFE / ADDITIVE: only calls public solver entry points; no modification to the
% core solver (decode / evaluate / aoo_engine / llmaoo).
%
% NOTE on fairness: all variants share the same evaluation budget
% (AOO_POP * AOO_MAXGEN), satisfying the equal-effort comparison convention.

    p = inputParser;
    addParameter(p, 'N', 5, @(x) isscalar(x) && x > 0);
    addParameter(p, 'Prob', 'MK01', @ischar);
    parse(p, varargin{:});
    N = p.Results.N;
    probName = p.Results.Prob;

    fprintf('=== Stage 6 experiments (N=%d, prob=%s) ===\n', N, probName);
    addpath('benchmarks');  % ensure load_benchmark on path
    prob = load_benchmark(probName);

    % 1) N independent runs
    R = experiment_runs(prob, 'N', N, 'Variants', {'aoo', 'random'});

    % 2) Statistics + significance
    S = stat_report(R, 'Compare', {'aoo', 'random'});

    % 3) Ablation (adds 'full' only if DEEPSEEK_API_KEY present)
    A = ablation(prob, 'N', N);

    % 4) Figures
    figFiles = convergence_plot(R, 'Tag', probName);

    % 5) Summary to console
    fprintf('\n=== Stage 6 summary ===\n');
    fprintf('Problem %s : %d jobs, %d machines, %d ops, BKS=%.0f\n', ...
        prob.name, prob.nJob, prob.nMachine, prob.nOp, prob.bks);
    fprintf('AOO mean makespan = %.2f (vs Random %.2f, improvement %.1f%%)\n', ...
        S.desc.aoo.mean, S.desc.random.mean, A.aoo_vs_random_improve_pct);
    if isfield(A, 'note'), fprintf('%s\n', A.note); end
    fprintf('Figures: %s\n', strjoin(figFiles, ', '));
end
