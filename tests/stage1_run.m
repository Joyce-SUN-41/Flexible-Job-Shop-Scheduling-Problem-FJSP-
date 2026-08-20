function stage1_run()
% stage1_run  Stage-1 gate: verify the "hot" problem scenarios (dynamic rescheduling
% and multi-objective 3-obj) are solvable and export the JSON contract correctly, so
% the latest visualization forms (digital-twin / replay) have real, non-static data.
%
% Safe / ADDITIVE: only exercises the existing Stage-A capability switches
% (AOO_DEFAULT_SCENARIO = dynamic / multi) plus Stage9 JSON export. Does NOT modify
% solver numerics; default 'static' chain is untouched. Python digital-twin render is
% non-fatal (skipped if python/plotly absent), matching Stage9/Stage-F behaviour.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    jsonDir = fullfile(pwd, 'logs');
    if ~exist(jsonDir, 'dir'), mkdir(jsonDir); end

    %% 1) dynamic scenario -> replay JSON (drives replay.html + digital_twin.html)
    fprintf('  [1A] dynamic scenario -> solve + export replay JSON\n');
    rng(20260813);
    rd = llmaoo('AOO_DEFAULT_SCENARIO', 'dynamic', 'AOO_DEFAULT_PROB', 'MK01', ...
                'AOO_DYNAMIC', true, 'EXPORT_JSON', true, 'EXPORT_PNG', false, ...
                'SHOW_PLOTS', false, 'LLM_ENABLE', false, 'AOO_MAXGEN', 30, 'AOO_POP', 30);
    % dynamic_replay is triggered inside llmaoo when AOO_DYNAMIC=true -> replay_*.json written
    % Use the date-prefixed pattern to avoid matching stale demo files like replay__demo.json.
    % llmaoo EXPORT_JSON writes to results/ subdir (consistent with export_result_json default).
    repDir = fullfile(pwd, 'results');
    repFiles = dir(fullfile(repDir, 'replay_2026_*.json'));
    assert(~isempty(repFiles), 'dynamic scenario did not export replay JSON');
    repPath = fullfile(repDir, repFiles(end).name);
    fprintf('    dynamic: mk=%.1f, loadUnb=%.1f, %d ops, replay=%s\n', ...
            rd.makespan, rd.loadUnb, numel(rd.schedule), repPath);
    assert(rd.makespan > 0 && numel(rd.schedule) > 0, 'dynamic solve produced empty schedule');

    %% 2) multi-objective scenario -> results JSON with 3-obj pareto + NSGA-III quality
    fprintf('  [1B] multi-objective (3-obj) scenario -> solve + export results JSON\n');
    rng(20260813);
    rm = llmaoo('AOO_DEFAULT_SCENARIO', 'multi', 'AOO_DEFAULT_PROB', 'MK01', ...
                'AOO_THREE_OBJ', true, 'EXPORT_JSON', true, 'EXPORT_PNG', false, ...
                'SHOW_PLOTS', false, 'LLM_ENABLE', false, 'AOO_MAXGEN', 30, 'AOO_POP', 30);
    resFiles = dir(fullfile(repDir, 'results_2026_*.json'));
    assert(~isempty(resFiles), 'multi scenario did not export results JSON');
    resPath = fullfile(repDir, resFiles(end).name);
    hasQuality = isfield(rm, 'quality') && isfield(rm.quality, 'HV');
    fprintf('    multi: mk=%.1f, loadUnb=%.1f, %d ops, HV=%s\n', ...
            rm.makespan, rm.loadUnb, numel(rm.schedule), ...
            iff(hasQuality, sprintf('%.4f', rm.quality.HV), 'n/a'));
    assert(rm.makespan > 0 && numel(rm.schedule) > 0, 'multi solve produced empty schedule');

    %% 3) digital-twin render from replay JSON (non-fatal Python step)
    fprintf('  [1C] digital-twin render from replay JSON (non-fatal)\n');
    dtHtml = fullfile(pwd, 'figures', 'stage1_gate_digital_twin.html');
    [stat, out] = system(sprintf('python viz/digital_twin.py %s -o %s', repPath, dtHtml));
    if stat == 0
        fprintf('    [digital-twin] OK: %s\n', strtrim(out));
    else
        fprintf('    [digital-twin] SKIPPED (python/plotly unavailable): %s\n', strtrim(out));
    end

    %% 4) cleanup stray results/ results_*/replay_*.json (gate-only artifacts)
    stray = [dir(fullfile(repDir, 'results_*.json')); dir(fullfile(repDir, 'replay_*.json'))];
    for s = 1:numel(stray)
        delete(fullfile(pwd, stray(s).name));
    end
    if numel(stray) > 0
        fprintf('  [1D] cleaned %d stray root JSON files (kept logs/ copies)\n', numel(stray));
    end

    fprintf('stage1_run PASS (dynamic + multi scenarios solvable and exported)\n');
end

function s = iff(cond, a, b)
    if cond, s = a; else s = b; end
end
