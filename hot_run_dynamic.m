function hot_run_dynamic()
% hot_run_dynamic  Run the 2026 "hottest" LLMAOO configuration end-to-end:
%   - problem side: dynamic FJSP (AOO_DEFAULT_SCENARIO='dynamic') => DFJSP reschedule
%   - viz side: EXPORT_JSON=true -> results_*.json (Gantt + convergence) +
%               replay_*.json (dynamic reschedule -> Streamlit + Three.js digital twin)
% All output JSON goes under logs/ with canonical names for the Python renderers.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    jsonDir = fullfile(pwd, 'logs');
    figDir  = fullfile(pwd, 'figures');
    if ~exist(jsonDir,'dir'), mkdir(jsonDir); end
    if ~exist(figDir,'dir'), mkdir(figDir); end

    %% 1) dynamic solve -> result + replay JSON (the 2026 hottest "dynamic + digital twin" loop)
    fprintf('[HOT1] dynamic LLMAOO solve (MK01) + export result/replay JSON\n');
    rng(20260814);
    res = llmaoo('AOO_DEFAULT_SCENARIO', 'dynamic', 'EXPORT_JSON', true, ...
                 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                 'AOO_MAXGEN', 80, 'AOO_POP', 60);
    resPath = fullfile(jsonDir, 'hot_result.json');
    export_result_json(res, resPath);
    fprintf('  result -> %s (mk=%.1f, %d ops)\n', resPath, res.makespan, numel(res.schedule));

    %% 2) N runs -> convergence band JSON set (mean +/- std)
    fprintf('[HOT2] N=6 runs -> convergence band JSON set\n');
    N = 6;
    convPaths = cell(N,1);
    for r = 1:N
        rng(2000 + r);
        rres = llmaoo('AOO_DEFAULT_SCENARIO', 'dynamic', 'EXPORT_JSON', true, ...
                      'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                      'AOO_MAXGEN', 60, 'AOO_POP', 40);
        p = fullfile(jsonDir, sprintf('hot_conv_%d.json', r));
        export_result_json(rres, p);
        convPaths{r} = p;
    end
    fprintf('  %d convergence runs exported\n', N);

    %% 3) canonical replay JSON (real AOO elite baseline + 2 breakdown events)
    fprintf('[HOT3] dynamic replay JSON (real elite baseline)\n');
    cfg = llmaoo_config();
    cfg.AOO_DYNAMIC = true;
    prob = load_benchmark('MK01');
    frames = dynamic_replay(prob, cfg, [], res.elite);
    rPath = fullfile(jsonDir, 'hot_replay.json');
    export_replay_json(frames, rPath);
    fprintf('  replay -> %s (%d frames)\n', rPath, numel(frames));

    %% 4) drive Python renderers (non-fatal)
    fprintf('[HOT4] Python Plotly render (non-fatal)\n');
    ganttHtml  = fullfile(figDir, 'hot_gantt.html');
    convHtml   = fullfile(figDir, 'hot_convergence.html');
    replayHtml = fullfile(figDir, 'hot_replay.html');
    twinHtml   = fullfile(figDir, 'hot_digital_twin.html');
    cmds = {
        sprintf('python viz/plotly_gantt.py %s -o %s', resPath, ganttHtml);
        sprintf('python viz/plotly_convergence.py %s -o %s', strjoin(convPaths, ' '), convHtml);
        sprintf('python viz/replay_dynamic.py %s -o %s', rPath, replayHtml);
        sprintf('python viz/digital_twin.py %s -o %s', resPath, twinHtml);
    };
    pyOk = true;
    for k = 1:numel(cmds)
        [stat, out] = system(cmds{k});
        if stat == 0
            fprintf('  [render %d] OK: %s\n', k, strtrim(out));
        else
            pyOk = false;
            fprintf('  [render %d] SKIPPED (python/plotly unavailable): %s\n', k, strtrim(out));
        end
    end

    %% 5) cleanup stray root-level results_*.json (logs/ holds canonical copies)
    stray = dir(fullfile(pwd, 'results_*.json'));
    for s = 1:numel(stray), delete(fullfile(pwd, stray(s).name)); end
    if numel(stray) > 0, fprintf('[HOT5] cleaned %d stray root result json\n', numel(stray)); end

    fprintf('hot_run_dynamic DONE (pyOk=%d, mk=%.1f)\n', pyOk, res.makespan);
end
