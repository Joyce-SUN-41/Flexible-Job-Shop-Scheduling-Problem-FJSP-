function run_full_hot()
% run_full_hot  Run the "full" hottest config: dynamic + green(energy) + AGV
% (AOO_DEFAULT_SCENARIO='full') => DFJSP with 3-obj (makespan/load/energy)
% and AGV transport constraint, plus dynamic reschedule replay. Export JSON
% and render the full Plotly artifact set (Gantt / convergence / replay / twin).

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');
    jsonDir = fullfile(pwd, 'logs');
    figDir  = fullfile(pwd, 'figures');
    if ~exist(jsonDir,'dir'), mkdir(jsonDir); end
    if ~exist(figDir,'dir'), mkdir(figDir); end

    fprintf('[FULL] dynamic + green + AGV (MK01), 3-obj + NSGA-III\n');
    rng(20260814);
    res = llmaoo('AOO_DEFAULT_SCENARIO', 'full', 'EXPORT_JSON', true, ...
                 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                 'AOO_MAXGEN', 80, 'AOO_POP', 60);
    resPath = fullfile(jsonDir, 'hot_full_result.json');
    export_result_json(res, resPath);
    fprintf('  mk=%.1f loadUnb=%.1f\n', res.makespan, res.loadUnb);
    if isfield(res, 'quality')
        fprintf('  NSGA-III: HV=%.4f IGD=%.4f PF=%d\n', ...
                res.quality.HV, res.quality.IGD, res.quality.nPF);
    end

    %% replay (real elite baseline + breakdown events)
    cfg = llmaoo_config();
    cfg.AOO_DYNAMIC = true; cfg.AOO_AGV = true; cfg.AOO_THREE_OBJ = true;
    prob = load_benchmark('MK01');
    prob = attach_stage8(prob, cfg);
    frames = dynamic_replay(prob, cfg, [], res.elite);
    rPath = fullfile(jsonDir, 'hot_full_replay.json');
    export_replay_json(frames, rPath);
    fprintf('  replay -> %s (%d frames)\n', rPath, numel(frames));

    %% render
    fprintf('[FULL] Python Plotly render (non-fatal)\n');
    ganttHtml  = fullfile(figDir, 'hot_full_gantt.html');
    replayHtml = fullfile(figDir, 'hot_full_replay.html');
    twinHtml   = fullfile(figDir, 'hot_full_digital_twin.html');
    cmds = {
        sprintf('python viz/plotly_gantt.py %s -o %s', resPath, ganttHtml);
        sprintf('python viz/replay_dynamic.py %s -o %s', rPath, replayHtml);
        sprintf('python viz/digital_twin.py %s -o %s', resPath, twinHtml);
    };
    pyOk = true;
    for k = 1:numel(cmds)
        [stat, out] = system(cmds{k});
        if stat == 0, fprintf('  [render %d] OK\n', k);
        else, pyOk = false; fprintf('  [render %d] SKIP: %s\n', k, strtrim(out)); end
    end

    %% cleanup stray root json
    stray = dir(fullfile(pwd, 'results_*.json'));
    for s = 1:numel(stray), delete(fullfile(pwd, stray(s).name)); end
    fprintf('hot_full DONE (pyOk=%d, mk=%.1f)\n', pyOk, res.makespan);
end
