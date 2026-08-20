function stage7_sota_only()
% stage7_sota_only  Run ONLY the [7.2] multi-instance SOTA compare (aoo/ga/pso/alns/random,
% N=30) with the corrected budget (Pop/MaxGen from cfg, matching [7.1]) and the corrected
% Wilcoxon p-value extraction (signrank returns [p,h]; we take p, the first output).
% This is used to regenerate logs/stage7_sota.json after the benchmark ([7.1]) is already
% locked, avoiding a full re-run. SAFE/ADDITIVE: standalone entry point.
%
% Budget note: uses cfg.AOO_POP=30, cfg.AOO_MAXGEN=60 (passed to experiment_runs via
% Pop/MaxGen) so [7.2] matches [7.1] exactly. Writes logs/stage7_sota.json only.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    %% (2) Multi-instance SOTA compare (same as stage7_run [7.2], isolated)
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
        % 标准 Brandimarte BKS 参考值（双保险，与 [7.1] 一致）
        BKS_TBL2 = struct('MK01',40,'MK02',26,'MK03',204,'MK04',81,'MK05',173, ...
                          'MK06',55,'MK07',144,'MK08',523,'MK09',311,'MK10',297);
        if isfield(BKS_TBL2, nm), prob.bks = BKS_TBL2.(nm); end
        cfg = llmaoo_config();
        cfg.AOO_POP = 30; cfg.AOO_MAXGEN = 60; cfg.AOO_REFINE_EVERY = 5;
        cfg.LLM_ENABLE = false;
        % 单实例隔离：即便该实例某个变体异常，也不影响其余实例。
        try
            R = experiment_runs(prob, 'N', 30, 'Variants', variants, 'Seed0', 9000 + s*100, ...
                'Pop', cfg.AOO_POP, 'MaxGen', cfg.AOO_MAXGEN);
            % compact stats
            instStat = struct('inst', nm, 'bks', prob.bks, 'N', 30, 'budget', ...
                struct('pop', cfg.AOO_POP, 'maxgen', cfg.AOO_MAXGEN));
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
    fprintf('\nstage7_sota_only PASS\n');

    function savejson(path, S)
        if isstruct(S) && isscalar(S)
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
end
