function stage7_sota_mk0810()
% stage7_sota_mk0810  Complete ONLY MK08 and MK10 (the two largest Brandimarte
% instances) with the default-config N=30 five-arm SOTA compare, writing a NEW
% file logs/stage7_sota_mk0810.json (ADDITIVE, never overwrites). MK08 previously
% stalled on the pso arm under a long-lived MATLAB session; running it in a fresh
% isolated process (one -batch invocation per instance via the .bat) avoids the
% cumulative-memory / stall issue. Pure-ASCII (no Chinese) to stay -batch safe.
%
% Budget matches stage7_sota_only exactly (Pop=30, MaxGen=60, Seed0=9000+idx*100).

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    ALL = {'MK01','MK02','MK03','MK04','MK05','MK06','MK07','MK08','MK09','MK10'};
    MISS = {'MK08','MK10'};
    variants = {'aoo','ga','pso','alns','random'};
    BKS_TBL2 = struct('MK01',40,'MK02',26,'MK03',204,'MK04',81,'MK05',173, ...
                      'MK06',55,'MK07',144,'MK08',523,'MK09',311,'MK10',297);

    fprintf('\n=== Stage-2 MK08/10 default-config N=30 five-arm SOTA ===\n');
    out = struct();
    for s = 1:numel(MISS)
        nm = MISS{s};
        idx = find(strcmp(ALL, nm));
        try
            prob = load_benchmark(nm);
        catch
            fprintf('  %s  SKIP (no standard .fjs)\n', nm);
            continue;
        end
        if isfield(BKS_TBL2, nm), prob.bks = BKS_TBL2.(nm); end
        cfg = llmaoo_config();
        cfg.AOO_POP = 30; cfg.AOO_MAXGEN = 60; cfg.AOO_REFINE_EVERY = 5;
        cfg.LLM_ENABLE = false;
        try
            R = experiment_runs(prob, 'N', 30, 'Variants', variants, 'Seed0', 9000 + idx*100, ...
                'Pop', cfg.AOO_POP, 'MaxGen', cfg.AOO_MAXGEN);
            instStat = struct('inst', nm, 'bks', prob.bks, 'N', 30, 'budget', ...
                struct('pop', cfg.AOO_POP, 'maxgen', cfg.AOO_MAXGEN));
            for v = 1:numel(variants)
                vv = variants{v};
                instStat.(vv) = struct('mean', mean(R.mk.(vv)), 'best', min(R.mk.(vv)), ...
                    'std', std(R.mk.(vv)));
            end
            [pAooGa, ~]   = signrank(R.mk.aoo, R.mk.ga);
            [pAooPso, ~]  = signrank(R.mk.aoo, R.mk.pso);
            [pAooAlns, ~] = signrank(R.mk.aoo, R.mk.alns);
            [pAooRand, ~] = signrank(R.mk.aoo, R.mk.random);
            instStat.p = struct('aoo_vs_ga', pAooGa, 'aoo_vs_pso', pAooPso, ...
                'aoo_vs_alns', pAooAlns, 'aoo_vs_random', pAooRand);
            out.(nm) = instStat;
            fprintf('  %s: AOO mean=%.1f best=%.0f (BKS=%d, gap=%+.1f%%) | GA %.1f | PSO %.1f | ALNS %.1f | RAND %.1f\n', ...
                    nm, mean(R.mk.aoo), min(R.mk.aoo), prob.bks, ...
                    100*(min(R.mk.aoo)/prob.bks - 1), mean(R.mk.ga), mean(R.mk.pso), ...
                    mean(R.mk.alns), mean(R.mk.random));
            fprintf('       Wilcoxon AOO vs GA p=%.4f, vs PSO p=%.4f, vs ALNS p=%.4f, vs RAND p=%.4f\n', ...
                    pAooGa, pAooPso, pAooAlns, pAooRand);
        catch ME
            fprintf('  %s  SOTA ERROR: %s (skipped)\n', nm, ME.message);
        end
    end

    if ~isfolder('logs'), mkdir('logs'); end
    fid = fopen('logs/stage7_sota_mk0810.json','w');
    fprintf(fid, '%s', jsonencode(out));
    fclose(fid);
    fprintf('\n[written] logs/stage7_sota_mk0810.json  (instances: %s)\n', ...
        strjoin(fieldnames(out), ', '));
    fprintf('=== Stage-2 MK08/10 DONE ===\n');
end
