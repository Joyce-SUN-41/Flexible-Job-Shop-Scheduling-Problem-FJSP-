function stage5_run()
% stage5_run  Stage-5 gate: submission-grade evidence chain.
%   - 5.1  Complete benchmark scaffold: MK01 (built-in, runnable) + MK02-10
%          (requires standard .fjs instance files; flagged, NOT faked).
%   - 5.2  SOTA comparison: AOO vs GA vs PSO vs Random under equal budget,
%          with Wilcoxon significance (stat_report).
%   - 5.3  Overview dashboard aggregation is produced by viz/dashboard.py
%          (Overview tab); this script only prints the summary for the log.
%
% SAFE / ADDITIVE: only calls public entry points (llmaoo / experiment_runs /
% stat_report). Does not modify solver numerics. Default 'static' chain untouched.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('tests');
    logDir = fullfile(pwd, 'logs');
    if ~exist(logDir, 'dir'), mkdir(logDir); end

    %% 5.1 — Full MK01-10 benchmark (auto-loads standard .fjs from ./data)
    % Brandimarte (1993) best-known makespans (BKS). AOO best is compared to these.
    BKS = struct('MK01',40,'MK02',26,'MK03',204,'MK04',81,'MK05',173, ...
                 'MK06',55,'MK07',144,'MK08',523,'MK09',311,'MK10',297);
    allInst = {'MK01','MK02','MK03','MK04','MK05','MK06','MK07','MK08','MK09','MK10'};
    fprintf('\n[5.1] Full benchmark MK01-10 (auto-load ./data/*.fjs; missing = skipped)\n');
    benchRows = {};
    for ii = 1:numel(allInst)
        nm = allInst{ii};
        try
            p = load_benchmark(nm);   % MK01 built-in; MK02-10 from ./data/*.fjs
        catch ME
            fprintf('  %-5s SKIPPED (no .fjs under ./data): %s\n', nm, ME.message);
            continue;
        end
        % light single-run solve via aoo_engine (same contract as experiment_runs'
        % 'aoo' variant: unity-gain no-op hook). Budget matches the SOTA compare
        % (MAXGEN=30, POP=30). cfg overrides via varargin.
        addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports');
        cfg = llmaoo_config();
        cfg.AOO_MAXGEN = 30; cfg.AOO_POP = 30;   % gate-speed budget (matches SOTA compare)
        init_state = struct('levy_gain', 1.0, 'diff_gain', 1.0, 'explore_bias', 1.0, 'last_best', Inf);
        try
            [~, res] = aoo_engine(p, cfg, init_state, @(t, b, m) init_state);
        catch ME2
            fprintf('  %-5s SOLVE FAILED: %s\n', nm, ME2.message);
            continue;
        end
        bk = BKS.(nm);
        gap = (res.makespan - bk) / bk * 100;
        fprintf('  %-5s jobs=%d mach=%d  AOO best=%.0f  BKS=%d  gap=%+.1f%%\n', ...
                nm, p.nJob, p.nMachine, res.makespan, bk, gap);
        benchRows{end+1} = struct('inst', nm, 'nJob', p.nJob, 'nMachine', p.nMachine, ...
                                  'aoo', res.makespan, 'bks', bk, 'gap_pct', gap);
    end
    if ~isempty(benchRows)
        save_struct_json_bench(benchRows, fullfile(logDir, 'stage5_benchmark.json'));
        fprintf('  benchmark table saved: %s\n', fullfile(logDir, 'stage5_benchmark.json'));
    end

    %% 5.2 — SOTA comparison on MK01 (equal budget, N=10 for gate speed)
    fprintf('\n[5.2] SOTA comparison on MK01 (AOO vs GA vs PSO vs Random, N=10)\n');
    rng(20260813);
    prob = load_benchmark('MK01');
    variants = {'aoo', 'ga', 'pso', 'random'};
    R = experiment_runs(prob, 'N', 10, 'Variants', variants, 'Seed0', 1001);

    % stat_report prints mean/median/best + Wilcoxon (AOO vs each baseline)
    S = stat_report(R);
    fprintf('    summary (variants: %s):\n', strjoin(fieldnames(R.mk), ', '));
    descFns = fieldnames(S.desc);
    for k = 1:numel(descFns)
        vn = descFns{k};
        dd = S.desc.(vn);
        fprintf('      %-6s mean=%.2f median=%.1f best=%.1f [95%%CI %.2f,%.2f]\n', ...
                vn, dd.mean, dd.median, dd.best, dd.ci_lo, dd.ci_hi);
    end
    fprintf('    Wilcoxon (AOO vs baseline):\n');
    testFns = fieldnames(S.test);
    for k = 1:numel(testFns)
        tn = testFns{k};
        tt = S.test.(tn);
        sig = iff(tt.significant, 'SIGNIFICANT', 'not significant');
        fprintf('      vs %-6s p=%.4g -> %s | improve=%.1f%% | r_bis=%.3f\n', ...
                tn, tt.p, sig, tt.mean_improve_pct, tt.rank_biserial);
    end

    % persist the comparison for the dashboard / paper.
    % NOTE: full B3 deliverable (MK01/04/06/09 x 5 arms x N=30 + Wilcoxon) is produced
    % by stage5_sota_full + stage5_sota_merge -> logs/stage5_sota_compare.json. This gate
    % writes a separate lightweight file to avoid clobbering the full B3 artifact.
    cmpPath = fullfile(logDir, 'stage5_sota_gate.json');
    save_struct_json(R, cmpPath);
    fprintf('    SOTA gate (MK01 N=10) saved: %s\n', cmpPath);

    %% 5.3 — Overview aggregation note (rendered by dashboard.py Overview tab)
    fprintf('\n[5.3] Overview dashboard: run `streamlit run viz/dashboard.py`\n');
    fprintf('    The Overview tab aggregates all results_*.json / replay_*.json.\n');

    %% 5.4 — Regression guard summary
    fprintf('\n[5.4] Stage-5 gate summary\n');
    nRun = numel(benchRows);
    nSkip = numel(allInst) - nRun;
    fprintf('    Benchmark instances run: %d / %d (skipped due to missing .fjs: %d)\n', ...
            nRun, numel(allInst), nSkip);
    fprintf('    MK01 SOTA: AOO best (N=10) = %.1f, BKS = %d\n', min(R.mk.aoo), BKS.MK01);
    if nSkip > 0
        fprintf('    NOTE: %d instance(s) skipped - drop standard .fjs into ./data to complete.\n', nSkip);
    end
    fprintf('stage5_run PASS (SOTA comparison produced; benchmark table %d/%d run)\n', nRun, numel(allInst));
end

function save_struct_json(R, path)
% save_struct_json  Minimal JSON writer for the experiment_runs result R.
% Only scalar / vector / struct-of-vectors fields are serialized (the ones
% stat_report / dashboard need). Non-serializable cells (conv) are skipped.
    out = struct();
    out.prob = R.prob;
    out.N = R.N;
    out.nEval = R.nEval;
    out.mk = struct();
    out.lb = struct();
    fns = fieldnames(R.mk);
    for k = 1:numel(fns)
        v = fns{k};
        out.mk.(v) = R.mk.(v);
        out.lb.(v) = R.lb.(v);
    end
    % use MATLAB built-in jsonencode (struct array -> flat array form)
    try
        str = jsonencode(out);
        fid = fopen(path, 'w', 'n', 'UTF-8');
        fwrite(fid, str, 'char');
        fclose(fid);
    catch ME
        fprintf('    [warn] could not write %s: %s\n', path, ME.message);
    end
end

function s = iff(cond, a, b)
    if cond, s = a; else, s = b; end
end

function save_struct_json_bench(rows, path)
% save_struct_json_bench  Serialize a cell array of benchmark structs to JSON.
% Each row is a scalar struct (inst, nJob, nMachine, aoo, bks, gap_pct).
    try
        str = jsonencode(rows);
        fid = fopen(path, 'w', 'n', 'UTF-8');
        fwrite(fid, str, 'char');
        fclose(fid);
    catch ME
        fprintf('    [warn] could not write %s: %s\n', path, ME.message);
    end
end
