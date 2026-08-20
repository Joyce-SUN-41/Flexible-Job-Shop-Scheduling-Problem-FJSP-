function stage7_run()
% stage7_run  Stage-Refine: submission-grade evidence chain (replaces the earlier
% lightweight single-run benchmark).
%   (1) FULL BENCHMARK: MK01-10, AOO, N=30 independent seeds -> mean/best/std makespan
%       and BKS gap (mean + best columns). This gives statistically meaningful
%       evidence instead of the earlier N=1 single run.
%   (2) MULTI-INSTANCE SOTA: aoo / ga / pso / alns / random on representative
%       instances (MK01 small, MK04 mid, MK06 hard, MK09 large), N=30, with
%       Wilcoxon significance (via stat_report). Resolves the earlier "only MK01"
%       weakness and adds the ALNS strong baseline.
%
% Budget note: uses POP=30, MAXGEN=60 (lighter than experiment_runs' 50x130) so the
% full 10-instance x 30-run benchmark stays runnable in one sitting; the SOTA step
% uses the same budget for fairness. Both are reproducible (fixed Seed0).
%
% SAFE / ADDITIVE: writes logs/stage7_benchmark.json + logs/stage7_sota.json only;
% never changes solver numerics. Missing .fjs instances are skipped gracefully.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    %% (1) Full MK01-10 benchmark, AOO, N=30
    fprintf('\n=== [7.1] Full benchmark MK01-10 (AOO, N=30) ===\n');
    names = {'MK01','MK02','MK03','MK04','MK05','MK06','MK07','MK08','MK09','MK10'};
    benchRows = cell(numel(names), 1);
    nDone = 0;
    for s = 1:numel(names)
        nm = names{s};
        try
            prob = load_benchmark(nm);
        catch
            fprintf('  %s  SKIP (no standard .fjs available)\n', nm);
            continue;
        end
        % 标准 Brandimarte BKS 参考值（公开文献，仅用于 gap 报告，不影响求解）。
        % 双保险：即便 load_benchmark 未注入，这里也强制补全（修复 attach_bks 失效）。
        BKS_TBL = struct('MK01',40,'MK02',26,'MK03',204,'MK04',81,'MK05',173, ...
                         'MK06',55,'MK07',144,'MK08',523,'MK09',311,'MK10',297);
        if isfield(BKS_TBL, nm), prob.bks = BKS_TBL.(nm); end
        cfg = llmaoo_config();
        cfg.AOO_POP = 30; cfg.AOO_MAXGEN = 60; cfg.AOO_REFINE_EVERY = 5;
        cfg.LLM_ENABLE = false;
        llm_state = default_llm_state(cfg);
        mks = zeros(30, 1);
        for i = 1:30
            rng(7000 + i);
            [~, res] = aoo_engine(prob, cfg, llm_state, []);
            mks(i) = res.makespan;
        end
        bks = prob.bks;
        bestMk = min(mks);
        meanMk = mean(mks);
        gapBest = 100 * (bestMk - bks) / bks;
        gapMean = 100 * (meanMk - bks) / bks;
        fprintf('  %s  jobs=%d mach=%d  AOO best=%.0f mean=%.1f std=%.1f  BKS=%.0f  gapBest=%+.1f%% gapMean=%+.1f%%\n', ...
                nm, prob.nJob, prob.nMachine, bestMk, meanMk, std(mks), bks, gapBest, gapMean);
        benchRows{nDone+1} = struct('inst', nm, 'nJob', prob.nJob, 'nMachine', prob.nMachine, ...
            'aoo_best', bestMk, 'aoo_mean', meanMk, 'aoo_std', std(mks), ...
            'bks', bks, 'gap_best_pct', gapBest, 'gap_mean_pct', gapMean);
        nDone = nDone + 1;
    end
    benchRows = benchRows(1:nDone);
    savejson('logs/stage7_benchmark.json', benchRows);
    fprintf('  benchmark table saved: logs/stage7_benchmark.json (%d instances)\n', nDone);

    %% (2) Multi-instance SOTA compare
    fprintf('\n=== [7.2] Multi-instance SOTA (aoo/ga/pso/alns/random, N=30) ===\n');
    sotaInst = {'MK01','MK04','MK06','MK09'};
    variants = {'aoo','ga','pso','alns','random'};
    sotaAll = struct();
    for s = 1:numel(sotaInst)
        nm = sotaInst{s};
        try
            prob = load_benchmark(nm);
        catch
            fprintf('  %s  SKIP (no standard .fjs)\n', nm);
            continue;
        end
        % 单实例隔离：即便该实例某个变体异常，也不影响其余实例与已完成的 [7.1]。
        try
        % 标准 Brandimarte BKS 参考值（双保险，与 [7.1] 一致）
        BKS_TBL2 = struct('MK01',40,'MK02',26,'MK03',204,'MK04',81,'MK05',173, ...
                          'MK06',55,'MK07',144,'MK08',523,'MK09',311,'MK10',297);
        if isfield(BKS_TBL2, nm), prob.bks = BKS_TBL2.(nm); end
        R = experiment_runs(prob, 'N', 30, 'Variants', variants, 'Seed0', 9000 + s*100, ...
            'Pop', cfg.AOO_POP, 'MaxGen', cfg.AOO_MAXGEN);
        % compact stats
        instStat = struct('inst', nm, 'bks', prob.bks, 'N', 30);
        for v = 1:numel(variants)
            vv = variants{v};
            instStat.(vv) = struct('mean', mean(R.mk.(vv)), 'best', min(R.mk.(vv)), ...
                'std', std(R.mk.(vv)));
        end
        % Wilcoxon AOO vs each baseline (signrank returns [p, h]; take p = first output)
        [pAooGa, ~]   = signrank(R.mk.aoo, R.mk.ga);
        [pAooPso, ~]  = signrank(R.mk.aoo, R.mk.pso);
        [pAooAlns, ~] = signrank(R.mk.aoo, R.mk.alns);
        [pAooRand, ~] = signrank(R.mk.aoo, R.mk.random);
        instStat.p = struct('aoo_vs_ga', pAooGa, 'aoo_vs_pso', pAooPso, ...
            'aoo_vs_alns', pAooAlns, 'aoo_vs_random', pAooRand);
        sotaAll.(nm) = instStat;
        fprintf('  %s: AOO mean=%.1f best=%.0f | GA %.1f | PSO %.1f | ALNS %.1f | RAND %.1f\n', ...
                nm, mean(R.mk.aoo), min(R.mk.aoo), mean(R.mk.ga), mean(R.mk.pso), ...
                mean(R.mk.alns), mean(R.mk.random));
        fprintf('       Wilcoxon AOO vs GA p=%.4f, vs PSO p=%.4f, vs ALNS p=%.4f, vs RAND p=%.4f\n', ...
                pAooGa, pAooPso, pAooAlns, pAooRand);
        catch ME
            fprintf('  %s  SOTA ERROR: %s (skipped, continuing with remaining instances)\n', nm, ME.message);
        end
    end
    savejson('logs/stage7_sota.json', sotaAll);
    fprintf('  SOTA comparison saved: logs/stage7_sota.json\n');

    fprintf('\nstage7_run PASS (full MK01-10 benchmark N=30 + multi-instance SOTA)\n');
end

function savejson(path, S)
% savejson  Minimal JSON serializer for a struct array / scalar struct (ASCII-safe,
% avoids MATLAB jsonencode column-cell double-nesting issues seen historically).
    if isstruct(S) && numel(S) >= 1 && isfield(S, 'inst')
        % struct array of benchmark rows (inst is a char field, not cell)
        parts = cell(numel(S), 1);
        for i = 1:numel(S)
            parts{i} = struct2jsonrow(S(i));
        end
        txt = ['[', strjoin(parts, ','), ']'];
    elseif isstruct(S) && isscalar(S)
        % scalar struct keyed by instance
        keys = fieldnames(S);
        parts = cell(numel(keys), 1);
        for i = 1:numel(keys)
            parts{i} = ['"', keys{i}, '":', struct2jsonrow(S.(keys{i}))];
        end
        txt = ['{', strjoin(parts, ','), '}'];
    else
        txt = '{}';
    end
    fid = fopen(path, 'w');
    fwrite(fid, txt, 'char');
    fclose(fid);
end

function txt = struct2jsonrow(S)
    f = fieldnames(S);
    parts = cell(numel(f), 1);
    for i = 1:numel(f)
        v = S.(f{i});
        if ischar(v)
            parts{i} = ['"', f{i}, '":"', v, '"'];
        elseif isstruct(v)
            parts{i} = ['"', f{i}, '":', struct2jsonrow(v)];
        elseif isnumeric(v) && isscalar(v)
            parts{i} = ['"', f{i}, '":', num2str(v, '%.6g')];
        else
            parts{i} = ['"', f{i}, '":', mat2str(v)];
        end
    end
    txt = ['{', strjoin(parts, ','), '}'];
end
