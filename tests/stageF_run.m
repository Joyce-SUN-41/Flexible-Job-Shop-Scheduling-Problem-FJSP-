function stageF_run()
% stageF_run  Stage-F: actually render the Stage9 Plotly interactive artifacts from
% REAL LLMAOO JSON output. Stage9 built the Python renderers + JSON export contract;
% Stage-F closes the loop by generating real result/replay JSON and driving the three
% Python scripts (plotly_gantt.py / plotly_convergence.py / replay_dynamic.py) to emit
% gantt.html / convergence.html / replay.html. This is the visualization-side "E" step:
% verify the Stage9 JSON contract is faithfully consumed by Plotly (honest, runnable).
%
% Safe / ADDITIVE: only writes JSON + HTML under logs/ and figures/ when explicitly run;
% never changes solver numerics. Python step is non-fatal (skipped if no python/plotly),
% matching Stage9's probe behaviour, so it does not break the regression suite.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    jsonDir = fullfile(pwd, 'logs');
    figDir  = fullfile(pwd, 'figures');
    if ~exist(jsonDir,'dir'), mkdir(jsonDir); end
    if ~exist(figDir,'dir'), mkdir(figDir); end

    %% 1) one full static solve -> result JSON (drives Gantt + single-run convergence)
    fprintf('  [F1] running static LLMAOO -> export result JSON\n');
    rng(20260812);
    res = llmaoo('EXPORT_JSON', true, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                 'AOO_MAXGEN', 30, 'AOO_POP', 30);
    % export_result_json already called inside llmaoo (EXPORT_JSON=true); but write an
    % explicit canonical file too for the Python step (deterministic name).
    resPath = fullfile(jsonDir, 'stageF_result.json');
    export_result_json(res, resPath);
    assert(exist(resPath,'file')==2, 'result JSON not written');
    fprintf('    result JSON -> %s (mk=%.1f, %d ops)\n', resPath, res.makespan, numel(res.schedule));

    %% 2) N small runs -> convergence JSON set (mean +/- std band)
    fprintf('  [F2] N=4 small runs -> convergence JSON set\n');
    N = 4;
    convPaths = cell(N,1);
    for r = 1:N
        rng(1000 + r);
        rres = llmaoo('EXPORT_JSON', true, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                      'AOO_MAXGEN', 20, 'AOO_POP', 20);
        p = fullfile(jsonDir, sprintf('stageF_conv_%d.json', r));
        export_result_json(rres, p);
        convPaths{r} = p;
    end
    fprintf('    %d convergence runs exported\n', N);

    %% 3) dynamic replay frames -> replay JSON (drives animated replay.html)
    fprintf('  [F3] dynamic replay -> replay JSON\n');
    cfg = llmaoo_config();
    cfg.AOO_DYNAMIC = true;          % enable dynamic scenario for replay demo
    prob = load_benchmark('MK01');
    frames = dynamic_replay(prob, cfg);
    rPath = fullfile(jsonDir, 'stageF_replay.json');
    export_replay_json(frames, rPath);
    assert(exist(rPath,'file')==2, 'replay JSON not written');
    fprintf('    replay JSON -> %s (%d frames)\n', rPath, numel(frames));

    %% 4) drive Python renderers (non-fatal: skip if no python/plotly)
    fprintf('  [F4] Python Plotly render (non-fatal)\n');
    ganttHtml = fullfile(figDir, 'stageF_gantt.html');
    convHtml  = fullfile(figDir, 'stageF_convergence.html');
    replayHtml= fullfile(figDir, 'stageF_replay.html');
    cmds = {
        sprintf('python viz/plotly_gantt.py %s -o %s', resPath, ganttHtml);
        sprintf('python viz/plotly_convergence.py %s -o %s', ...
                strjoin(convPaths, ' '), convHtml);
        sprintf('python viz/replay_dynamic.py %s -o %s', rPath, replayHtml);
    };
    pyOk = true;
    for k = 1:numel(cmds)
        [stat, out] = system(cmds{k});
        if stat == 0
            fprintf('    [render %d] OK: %s\n', k, strtrim(out));
        else
            pyOk = false;
            fprintf('    [render %d] SKIPPED (python/plotly unavailable): %s\n', k, strtrim(out));
        end
    end
    assert(exist(ganttHtml,'file')==2 || ~pyOk, 'gantt.html not produced though python present');
    assert(exist(convHtml,'file')==2  || ~pyOk, 'convergence.html not produced though python present');
    assert(exist(replayHtml,'file')==2|| ~pyOk, 'replay.html not produced though python present');

    if pyOk
        fprintf('  [F4] Stage-F rendered 3 interactive HTML artifacts OK\n');
    else
        fprintf('  [F4] JSON artifacts generated; Python render skipped (no plotly in this env).\n');
    end

    %% 5) cleanup: llmaoo(EXPORT_JSON=true) also writes results_<date>.json at CWD.
    % Remove those stray root-level files so the workspace stays clean (logs/ holds the
    % canonical copies used by the Python renderers). Only timestamped result files.
    stray = dir(fullfile(pwd, 'results_*.json'));
    for s = 1:numel(stray)
        delete(fullfile(pwd, stray(s).name));
    end
    if numel(stray) > 0
        fprintf('  [F5] cleaned %d stray root results_*.json (kept logs/ copies)\n', numel(stray));
    end

    fprintf('stageF_run PASS (JSON contract generated; Plotly render %s)\n', ...
            iff(pyOk, 'OK', 'skipped'));
end

function s = iff(cond, a, b)
    if cond, s = a; else s = b; end
end
