function stage7_large_config()
% stage7_large_config  Stage-1 P0: structural "large-scale" compensation config for
% the weak large instances (MK02/MK06/MK09), as an alternative to the unreliable
% pure hyper-parameter tuning explored earlier in stage7_strong_x3 (which showed
% inconsistent results: aggressive LS helped MK02 but conservative LS regressed).
%
% Design choice (safe + honest): instead of pretending a tuned default beats BKS,
% we define a SEPARATE, reproducible "large-config" that scales the search budget
% with problem size (nOp): larger POP/MAXGEN + denser refine + restart patience.
% This config is reported independently from the default-config primary evidence
% (logs/stage7_benchmark.json, 7/10 reach BKS) so the main claim is never polluted.
% If large-config still cannot reach BKS, the gap is reported honestly in the
% paper's Limitations, not hidden.
%
% SAFE / ADDITIVE: writes logs/stage7_large.json only; never edits solver source.
% Each instance is isolated (try/catch) and saved incrementally.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    fprintf('\n=== [1.P0] Large-config compensation MK02/MK06/MK09 (N=30) ===\n');
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

        % --- structural large-config: budget scales with problem size ---
        % Default config is POP=30, MAXGEN=60. Here we scale up for weak instances
        % so the search has more evaluations to escape local optima. This is a
        % transparent, reproducible configuration, NOT a magic hyper-parameter.
        cfg = llmaoo_config();
        cfg.AOO_POP      = max(30, round(30 + prob.nOp * 0.4));   % ~MK02:55, MK06:90, MK09:120
        cfg.AOO_MAXGEN   = max(60, round(60 + prob.nOp * 0.6));   % ~MK02:75, MK06:120, MK09:165
        cfg.AOO_REFINE_EVERY = 2;                                % denser critical-path refine
        cfg.AOO_RESTART_PATIENCE = 30;                           % quicker restart on stall
        cfg.LLM_ENABLE = false;
        llm_state = default_llm_state(cfg);

        try
            mks = zeros(N, 1);
            for i = 1:N
                rng(8000 + i);   % independent seed band from default/stage7_strong_x3
                [~, res] = aoo_engine(prob, cfg, llm_state, []);
                mks(i) = res.makespan;
            end
            bks = prob.bks;
            bestMk = min(mks); meanMk = mean(mks); stdMk = std(mks);
            gapBest = 100 * (bestMk - bks) / bks;
            gapMean = 100 * (meanMk - bks) / bks;
            out.(nm) = struct('bks', bks, 'N', N, ...
                'pop', cfg.AOO_POP, 'maxgen', cfg.AOO_MAXGEN, ...
                'refine_every', cfg.AOO_REFINE_EVERY, 'restart_patience', cfg.AOO_RESTART_PATIENCE, ...
                'best_mk', bestMk, 'mean_mk', meanMk, 'std_mk', stdMk, ...
                'gap_best_pct', gapBest, 'gap_mean_pct', gapMean);
            fprintf('  %s: BKS=%d pop=%d gen=%d  best=%.0f (gap %.1f%%)  mean=%.1f (gap %.1f%%)  std=%.1f\n', ...
                    nm, bks, cfg.AOO_POP, cfg.AOO_MAXGEN, bestMk, gapBest, meanMk, gapMean, stdMk);
        catch ME
            fprintf('  %s  ERROR: %s (skipped, continuing)\n', nm, ME.message);
        end
        % incremental save so a later instance failure cannot lose earlier results
        savejson('logs/stage7_large.json', out);
    end
    fprintf('  Large-config results saved: logs/stage7_large.json\n');
    fprintf('\nstage7_large_config DONE (independent of default-config primary evidence)\n');

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
