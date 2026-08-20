function tevc_sota()
% tevc_sota  TEVC 投稿级完整基准 + 多实例 SOTA 对比（含联网真实 LLM 的 full 变体）。
%   在 tests.stage7_run 基础上增强：加入 'full' 联网 LLM 变体，使 SOTA 对比同时呈现
%   "纯 AOO / 离线调制 / 联网 LLM 双引擎 / GA / PSO / ALNS / 随机" 七方对比，
%   并覆盖完整 MK01-10 基准（N=30）+ 难实例多目标场景。产出投唐级证据链 JSON。
%   零回归：新建脚本，不修改 stage7_run。

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests'); addpath('exports'); addpath('viz');
    jsonDir = fullfile(pwd, 'logs');
    if ~exist(jsonDir, 'dir'), mkdir(jsonDir); end

    N = 30; Seed0 = 20260814;
    variantsFull = {'aoo', 'modulate', 'full', 'ga', 'pso', 'alns', 'random'};

    %% (1) 完整 MK01-10 基准（含联网 full 变体，N=30）
    fprintf('\n=== [SOTA-1] Full benchmark MK01-10 (incl. online full, N=30) ===\n');
    names = {'MK01','MK02','MK03','MK04','MK05','MK06','MK07','MK08','MK09','MK10'};
    benchRows = cell(numel(names), 1);
    nDone = 0;
    for s = 1:numel(names)
        nm = names{s};
        try
            prob = load_benchmark(nm);
        catch
            fprintf('  %s  SKIP (no standard .fjs)\n', nm); continue;
        end
        R = experiment_runs(prob, 'N', N, 'Variants', {'aoo', 'full'}, 'Seed0', Seed0 + s*10);
        bks = prob.bks;
        aooBest = min(R.mk.aoo); aooMean = mean(R.mk.aoo);
        fullBest = min(R.mk.full); fullMean = mean(R.mk.full);
        benchRows{nDone+1} = struct( ...
            'inst', nm, 'nJob', prob.nJob, 'nMachine', prob.nMachine, ...
            'aoo_best', aooBest, 'aoo_mean', aooMean, 'aoo_std', std(R.mk.aoo), ...
            'full_best', fullBest, 'full_mean', fullMean, 'full_std', std(R.mk.full), ...
            'bks', bks, ...
            'gap_aoo_best_pct', 100*(aooBest-bks)/bks, ...
            'gap_full_best_pct', 100*(fullBest-bks)/bks);
        nDone = nDone + 1;
        fprintf('  %s: AOO best=%.0f mean=%.1f | LLM-full best=%.0f mean=%.1f | BKS=%.0f\n', ...
                nm, aooBest, aooMean, fullBest, fullMean, bks);
    end
    benchRows = benchRows(1:nDone);
    savejson_tevc(fullfile(jsonDir, 'tevc_benchmark.json'), benchRows);
    fprintf('  saved logs/tevc_benchmark.json (%d instances)\n', nDone);

    %% (2) 多实例 SOTA（七方对比，N=30，含联网 full）
    fprintf('\n=== [SOTA-2] Multi-instance SOTA (7-way, N=30, online full) ===\n');
    sotaInst = {'MK01','MK04','MK06','MK09'};
    sotaAll = struct();
    for s = 1:numel(sotaInst)
        nm = sotaInst{s};
        try
            prob = load_benchmark(nm);
        catch
            fprintf('  %s  SKIP\n', nm); continue;
        end
        R = experiment_runs(prob, 'N', N, 'Variants', variantsFull, 'Seed0', Seed0 + 500 + s*100);
        instStat = struct('inst', nm, 'bks', prob.bks, 'N', N);
        for v = 1:numel(variantsFull)
            vv = variantsFull{v};
            instStat.(vv) = struct('mean', mean(R.mk.(vv)), 'best', min(R.mk.(vv)), 'std', std(R.mk.(vv)));
        end
        % 关键显著性：联网 full vs 各基线（Wilcoxon）
        [~, pFullAoo]  = signrank(R.mk.full, R.mk.aoo);
        [~, pFullAlns] = signrank(R.mk.full, R.mk.alns);
        [~, pFullRand] = signrank(R.mk.full, R.mk.random);
        instStat.p = struct('full_vs_aoo', pFullAoo, 'full_vs_alns', pFullAlns, 'full_vs_random', pFullRand);
        sotaAll.(nm) = instStat;
        fprintf('  %s: full=%.1f | aoo=%.1f | alns=%.1f | rand=%.1f | p(full vs aoo)=%.4f\n', ...
                nm, mean(R.mk.full), mean(R.mk.aoo), mean(R.mk.alns), mean(R.mk.random), pFullAoo);
    end
    savejson_tevc(fullfile(jsonDir, 'tevc_sota.json'), sotaAll);
    fprintf('  saved logs/tevc_sota.json\n');

    fprintf('\ntevc_sota DONE (full MK01-10 + 7-way SOTA, online LLM)\n');
end

function savejson_tevc(path, S)
    if isstruct(S) && numel(S) >= 1 && isfield(S, 'inst') && iscell(S(1).inst)
        parts = cell(numel(S), 1);
        for i = 1:numel(S), parts{i} = row2json(S(i)); end
        txt = ['[', strjoin(parts, ','), ']'];
    elseif isstruct(S) && isscalar(S)
        keys = fieldnames(S); parts = cell(numel(keys), 1);
        for i = 1:numel(keys), parts{i} = ['"', keys{i}, '":', row2json(S.(keys{i}))]; end
        txt = ['{', strjoin(parts, ','), '}'];
    else, txt = '{}';
    end
    fid = fopen(path, 'w'); fwrite(fid, txt, 'char'); fclose(fid);
end

function txt = row2json(S)
    f = fieldnames(S); parts = cell(numel(f), 1);
    for i = 1:numel(f)
        v = S.(f{i});
        if isstruct(v), parts{i} = ['"', f{i}, '":', row2json(v)];
        elseif isnumeric(v) && isscalar(v), parts{i} = ['"', f{i}, '":', num2str(v, '%.6g')];
        else, parts{i} = ['"', f{i}, '":', mat2str(v)];
        end
    end
    txt = ['{', strjoin(parts, ','), '}'];
end
