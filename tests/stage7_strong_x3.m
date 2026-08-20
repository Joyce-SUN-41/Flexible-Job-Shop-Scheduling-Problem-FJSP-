function stage7_strong_x3()
% stage7_strong_x3  Stage-3.1 safe augmentation: strengthen local search for the
% three weak large instances (MK02/MK06/MK09) WITHOUT touching solver source.
% Only runtime params change (conservative: LS_KMAX=8, REFINE_EVERY=3).
% Budget kept identical to stage7_run [7.1] (POP=30, MAXGEN=60) for fair compare.
% SAFE/ADDITIVE: writes logs/stage7_strong_x3.json incrementally; never edits source.
% Each instance is isolated (try/catch) and saved separately so one slow instance
% cannot lose the others. Results are honest "augmented-config" evidence only;
% the paper's primary evidence remains stage7_benchmark.json (default config).

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    fprintf('\n=== [3.1] Strengthened-LS benchmark MK02/MK06/MK09 (N=30) ===\n');
    names = {'MK02','MK06','MK09'};
    BKS_TBL = struct('MK02',26,'MK06',55,'MK09',311);
    N = 30;
    out = struct();
    for s = 1:numel(names)
        nm = names{s};
        try
            prob = load_benchmark(nm);
        catch
            fprintf('  %s  SKIP (no standard .fjs)\n', nm);
            continue;
        end
        if isfield(BKS_TBL, nm), prob.bks = BKS_TBL.(nm); end
        cfg = llmaoo_config();
        cfg.AOO_POP = 30; cfg.AOO_MAXGEN = 60;
        cfg.AOO_REFINE_EVERY = 3;   % conservative (default 5)
        cfg.LS_KMAX = 8;            % moderate depth (default 5)
        cfg.LLM_ENABLE = false;
        llm_state = default_llm_state(cfg);
        try
            mks = zeros(N, 1);
            for i = 1:N
                rng(7000 + i);
                [~, res] = aoo_engine(prob, cfg, llm_state, []);
                mks(i) = res.makespan;
            end
            bks = prob.bks;
            bestMk = min(mks); meanMk = mean(mks); stdMk = std(mks);
            gapMean = (meanMk - bks) / bks * 100;
            gapBest = (bestMk - bks) / bks * 100;
            out.(nm) = struct('bks', bks, 'N', N, 'pop', 30, 'maxgen', 60, ...
                'ls_kmax', 8, 'refine_every', 3, ...
                'best_mk', bestMk, 'mean_mk', meanMk, 'std_mk', stdMk, ...
                'gap_mean_pct', gapMean, 'gap_best_pct', gapBest);
            fprintf('  %s: BKS=%d  best=%.0f (gap %.1f%%)  mean=%.1f (gap %.1f%%)  std=%.1f\n', ...
                    nm, bks, bestMk, gapBest, meanMk, gapMean, stdMk);
        catch ME
            fprintf('  %s  ERROR: %s (skipped, continuing)\n', nm, ME.message);
        end
        % incremental save so a later instance failure cannot lose earlier results
        savejson('logs/stage7_strong_x3.json', out);
    end
    fprintf('  Strengthened-LS results saved: logs/stage7_strong_x3.json\n');
    fprintf('\nstage7_strong_x3 DONE\n');

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
