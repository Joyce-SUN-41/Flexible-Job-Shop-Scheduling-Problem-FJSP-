function stage7_sota_extend()
% stage7_sota_extend  Stage-2 extension: fill the DEFAULT-config N=30 five-arm SOTA
% compare for the 6 instances missing from stage7_sota_only (MK02/03/05/07/08/10),
% so the full MK01-10 SOTA table is complete. SAFE/ADDITIVE: writes a NEW file
% logs/stage7_sota_full.json (never overwrites stage7_sota.json) and merges the
% 4 already-locked instances (MK01/04/06/09) from stage7_sota.json.
%
% Budget matches stage7_sota_only exactly (Pop=30, MaxGen=60, Seed0=9000+idx*100)
% so the two files are directly comparable. Does NOT modify any solver source.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    ALL = {'MK01','MK02','MK03','MK04','MK05','MK06','MK07','MK08','MK09','MK10'};
    DONE = {'MK01','MK04','MK06','MK09'};              % already locked in stage7_sota.json
    MISS = {'MK02','MK03','MK05','MK07','MK08','MK10'}; % to run now
    variants = {'aoo','ga','pso','alns','random'};
    BKS_TBL2 = struct('MK01',40,'MK02',26,'MK03',204,'MK04',81,'MK05',173, ...
                      'MK06',55,'MK07',144,'MK08',523,'MK09',311,'MK10',297);

    %% (1) Run the 6 missing instances with identical budget
    fprintf('\n=== Stage-2 extend: default-config N=30 five-arm SOTA (MK02/03/05/07/08/10) ===\n');
    ext = struct();
    for s = 1:numel(MISS)
        nm = MISS{s};
        idx = find(strcmp(ALL, nm));                  % 1..10 position
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
            ext.(nm) = instStat;
            fprintf('  %s: AOO mean=%.1f best=%.0f (BKS=%d, gap=%+.1f%%) | GA %.1f | PSO %.1f | ALNS %.1f | RAND %.1f\n', ...
                    nm, mean(R.mk.aoo), min(R.mk.aoo), prob.bks, ...
                    100*(min(R.mk.aoo)/prob.bks - 1), mean(R.mk.ga), mean(R.mk.pso), ...
                    mean(R.mk.alns), mean(R.mk.random));
            fprintf('       Wilcoxon AOO vs GA p=%.4f, vs PSO p=%.4f, vs ALNS p=%.4f, vs RAND p=%.4f\n', ...
                    pAooGa, pAooPso, pAooAlns, pAooRand);
        catch ME
            fprintf('  %s  SOTA ERROR: %s (skipped, continuing)\n', nm, ME.message);
        end
    end

    %% (2) Merge with the 4 locked instances from stage7_sota.json (ADDITIVE, never overwrite)
    full = struct();
    if isfile('logs/stage7_sota.json')
        locked = jsondecode(fileread('logs/stage7_sota.json'));
        fNames = fieldnames(locked);
        for k = 1:numel(fNames)
            fn = fNames{k};
            if isstruct(locked.(fn)) && isfield(locked.(fn),'inst') && isfield(locked.(fn),'aoo')
                full.(fn) = locked.(fn);   % carry over MK01/04/06/09
            end
        end
        fprintf('\n[merge] carried over %d locked instances from stage7_sota.json\n', ...
            numel(fieldnames(full)));
    end
    eNames = fieldnames(ext);
    for k = 1:numel(eNames)
        full.(eNames{k}) = ext.(eNames{k});
    end

    %% (3) Write NEW file + print complete 10-instance summary
    if ~isfolder('logs'), mkdir('logs'); end
    fid = fopen('logs/stage7_sota_full.json','w');
    fprintf(fid, '%s', jsonencode(full));
    fclose(fid);
    fprintf('\n[written] logs/stage7_sota_full.json  (instances: %s)\n', ...
        strjoin(fieldnames(full), ', '));

    fprintf('\n=== Complete MK01-10 default-config SOTA summary (AOO best vs BKS) ===\n');
    fNames = fieldnames(full);
    for k = 1:numel(fNames)
        fn = fNames{k};
        st = full.(fn);
        gap = 100*(st.aoo.best / st.bks - 1);
        fprintf('  %s  AOO best=%.0f  BKS=%d  gap=%+.1f%%  (GA best=%.0f, PSO %.0f, ALNS %.0f, RAND %.0f)\n', ...
            fn, st.aoo.best, st.bks, gap, st.ga.best, st.pso.best, st.alns.best, st.random.best);
    end
    fprintf('=== Stage-2 extend DONE ===\n');
end
