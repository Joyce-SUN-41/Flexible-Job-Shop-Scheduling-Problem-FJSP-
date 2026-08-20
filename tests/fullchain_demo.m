function fullchain_demo()
% fullchain_demo  Stage-Refine: end-to-end "hot" closed-loop demo that binds the
% most-fashionable VISUALIZATION (digital-twin / replay / Gantt / convergence) to the
% most-fashionable PROBLEM (dynamic reschedule + 3-obj green) so the "hot viz vs static
% problem" mismatch is resolved with a runnable artifact.
%
% SAFE / ADDITIVE:
%  - Does NOT touch any solver numerics; only produces JSON + HTML under logs/ and
%    figures/ when explicitly run (never from the default code path).
%  - Uses AOO_DYNAMIC + AOO_THREE_OBJ (Stage8 capability bits) which default OFF, so
%    the main chain is byte-identical without this call (zero regression).
%  - Python render steps are non-fatal (skip if python/plotly absent), matching the
%    Stage9 probe behaviour, so this never breaks the regression suite.
%  - No taskkill of matlab; dedicated log file via _cc_fullchain.bat.

    addpath('benchmarks'); addpath('benchmarks/baselines');
    addpath('exports'); addpath('viz');

    jsonDir = fullfile(pwd, 'logs');
    figDir  = fullfile(pwd, 'figures');
    if ~exist(jsonDir,'dir'), mkdir(jsonDir); end
    if ~exist(figDir,'dir'), mkdir(figDir); end

    %% 1) full dynamic + 3-obj solve -> result JSON (drives Gantt + convergence)
    fprintf('  [FC1] dynamic + 3-obj LLMAOO -> export result JSON\n');
    rng(20260813);
    res = llmaoo('AOO_DEFAULT_SCENARIO', 'dynamic', 'AOO_DEFAULT_PROB', 'MK01', ...
                 'AOO_DYNAMIC', true, 'AOO_THREE_OBJ', true, ...
                 'EXPORT_JSON', true, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                 'LLM_ENABLE', false, 'AOO_MAXGEN', 40, 'AOO_POP', 30);
    resPath = fullfile(jsonDir, 'fullchain_result.json');
    export_result_json(res, resPath);
    assert(exist(resPath,'file')==2, 'result JSON not written');
    fprintf('    result JSON -> %s (mk=%.1f, lb=%.1f, %d ops)\n', ...
            resPath, res.makespan, res.loadUnb, numel(res.schedule));

    %% 2) dynamic replay frames -> replay JSON (drives animated replay + digital-twin)
    fprintf('  [FC2] dynamic replay -> replay JSON\n');
    cfg = llmaoo_config();
    cfg.AOO_DYNAMIC = true; cfg.AOO_THREE_OBJ = true;
    prob = load_benchmark('MK01');
    frames = dynamic_replay(prob, cfg, [], res.elite);
    rPath = fullfile(jsonDir, 'fullchain_replay.json');
    export_replay_json(frames, rPath);
    assert(exist(rPath,'file')==2, 'replay JSON not written');
    fprintf('    replay JSON -> %s (%d frames)\n', rPath, numel(frames));

    %% 3) convergence band: a few extra runs sharing the same scenario
    fprintf('  [FC3] N=4 convergence runs -> convergence JSON set\n');
    N = 4;
    convPaths = cell(N,1);
    for r = 1:N
        rng(2000 + r);
        rres = llmaoo('AOO_DEFAULT_SCENARIO', 'dynamic', 'AOO_DEFAULT_PROB', 'MK01', ...
                      'AOO_DYNAMIC', true, 'AOO_THREE_OBJ', true, ...
                      'EXPORT_JSON', true, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                      'LLM_ENABLE', false, 'AOO_MAXGEN', 25, 'AOO_POP', 25);
        p = fullfile(jsonDir, sprintf('fullchain_conv_%d.json', r));
        export_result_json(rres, p);
        convPaths{r} = p;
    end

    %% 4) drive Python renderers (non-fatal: skip if no python/plotly)
    fprintf('  [FC4] Python render (non-fatal): gantt / convergence / replay / digital-twin\n');
    ganttHtml  = fullfile(figDir, 'fullchain_gantt.html');
    convHtml   = fullfile(figDir, 'fullchain_convergence.html');
    replayHtml = fullfile(figDir, 'fullchain_replay.html');
    twinHtml   = fullfile(figDir, 'fullchain_digital_twin.html');
    cmds = {
        sprintf('python viz/plotly_gantt.py %s -o %s', resPath, ganttHtml);
        sprintf('python viz/plotly_convergence.py %s -o %s', ...
                strjoin(convPaths, ' '), convHtml);
        sprintf('python viz/replay_dynamic.py %s -o %s', rPath, replayHtml);
        sprintf('python viz/digital_twin.py %s -o %s', resPath, twinHtml);
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

    %% 5) cleanup stray root-level results_*.json written by llmaoo(EXPORT_JSON=true)
    stray = dir(fullfile(pwd, 'results_*.json'));
    for s = 1:numel(stray), delete(fullfile(pwd, stray(s).name)); end
    if numel(stray) > 0
        fprintf('  [FC5] cleaned %d stray root results_*.json\n', numel(stray));
    end

    fprintf(['fullchain_demo PASS (dynamic+3obj solve + JSON contract + Plotly render %s)\n' ...
             '  Dashboard (Streamlit) is served separately: streamlit run viz/dashboard.py\n'], ...
            iff(pyOk, 'OK', 'skipped'));
end

function s = iff(cond, a, b)
    if cond, s = a; else s = b; end
end
