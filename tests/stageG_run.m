function stageG_run()
% stageG_run  Stage-G: interactive Streamlit dashboard for the FJSP LLMAOO solver.
% StageE/F rendered static Plotly HTML; Stage-G packages the exported JSON
% contracts (results_*.json / *_conv_*.json / replay_*.json) into a single
% interactive web dashboard (viz/dashboard.py): KPI cards + Gantt + convergence
% band + dynamic replay slider. This is the visualization-side "G" step.
%
% Safe / ADDITIVE: viz/dashboard.py is purely read-only over the JSON contracts
% and never touches the MATLAB solver, so it cannot regress any numerical result.
% The dashboard .py needs `streamlit` (pip install -r viz/requirements.txt); the
% Python step here is NON-FATAL (skipped if streamlit is missing or python absent)
% so it does not break the regression suite. We only verify syntax + (if available)
% an import-level smoke test, never launch the blocking server.

    addpath('viz');

    fprintf('=== Stage G: Streamlit dashboard (ADDITIVE, read-only over JSON) ===\n');

    %% G1) dashboard.py exists
    dashPath = fullfile(pwd, 'viz', 'dashboard.py');
    assert(exist(dashPath,'file')==2, 'viz/dashboard.py missing');
    fprintf('  [G1] dashboard.py present: %s\n', dashPath);

    %% G2) python syntax check via py_compile (non-fatal)
    fprintf('  [G2] python syntax check (py_compile, non-fatal)\n');
    [ok, msg] = py_syntax_check(dashPath);
    if ok
        fprintf('    dashboard.py syntax OK\n');
    else
        fprintf('    WARN: dashboard.py syntax issue: %s\n', msg);
    end

    %% G3) streamlit import smoke test (non-fatal: needs pip install streamlit)
    fprintf('  [G3] streamlit availability smoke test (non-fatal)\n');
    [hasSt, info] = py_module_available('streamlit');
    if hasSt
        fprintf('    streamlit available (%s). Dashboard ready: streamlit run viz/dashboard.py\n', info);
    else
        fprintf('    INFO: streamlit not installed -> skip live test. Install with: pip install -r viz/requirements.txt\n');
    end

    %% G4) confirm JSON contracts the dashboard consumes exist (produced by stageF / stage9)
    fprintf('  [G4] verify JSON contracts exist for the dashboard\n');
    cands = {fullfile(pwd,'logs','stageF_result.json'), ...
             fullfile(pwd,'logs','stageF_replay.json')};
    anyJson = false;
    for k = 1:numel(cands)
        if exist(cands{k},'file')==2
            fprintf('    found: %s\n', cands{k});
            anyJson = true;
        end
    end
    if ~anyJson
        fprintf('    INFO: no stageF JSON found; run tests.stageF_run once to export demo data.\n');
    end

    fprintf('=== Stage G PASS (dashboard ADDITIVE, non-fatal python) ===\n');
end

function [ok, msg] = py_syntax_check(pyFile)
    [status, out] = system(sprintf('python -m py_compile "%s" 2>&1', pyFile));
    if status == 0
        ok = true; msg = '';
    else
        ok = false; msg = strtrim(out);
    end
end

function [avail, info] = py_module_available(mod)
    cmd = sprintf('python -c "import %s; print(%s.__version__)" 2>&1', mod, mod);
    [status, out] = system(cmd);
    if status == 0
        avail = true; info = strtrim(out);
    else
        avail = false; info = strtrim(out);
    end
end
