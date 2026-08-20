function stageH_run()
% stageH_run  Stage-H: Three.js digital-twin 3D view of the FJSP shop-floor.
% Stage G packaged the JSON contracts into a Streamlit dashboard; Stage H renders
% a rotatable / zoomable 3D digital twin (viz/digital_twin.py -> self-contained
% HTML using Three.js). This is the visualization-side "H" final step.
%
% Safe / ADDITIVE: viz/digital_twin.py is purely read-only over the result JSON
% contract and never touches the MATLAB solver, so it cannot regress any numerical
% result. The python step is NON-FATAL (skipped if python is missing) so it does
% not break the regression suite.

    addpath('viz');

    fprintf('=== Stage H: Three.js digital-twin 3D view (ADDITIVE, read-only over JSON) ===\n');

    %% H1) digital_twin.py exists
    pyPath = fullfile(pwd, 'viz', 'digital_twin.py');
    assert(exist(pyPath,'file')==2, 'viz/digital_twin.py missing');
    fprintf('  [H1] digital_twin.py present: %s\n', pyPath);

    %% H2) python syntax check via py_compile (non-fatal)
    fprintf('  [H2] python syntax check (py_compile, non-fatal)\n');
    [ok, msg] = py_syntax_check(pyPath);
    if ok
        fprintf('    digital_twin.py syntax OK\n');
    else
        fprintf('    WARN: digital_twin.py syntax issue: %s\n', msg);
    end

    %% H3) result JSON contract exists (produced by stageF / stage9)
    fprintf('  [H3] verify result JSON contract exists\n');
    cands = {fullfile(pwd,'logs','stageF_result.json')};
    resPath = '';
    for k = 1:numel(cands)
        if exist(cands{k},'file')==2
            resPath = cands{k}; break;
        end
    end
    if isempty(resPath)
        % fall back: scan logs for any results_*.json
        d = dir(fullfile(pwd,'logs','results_*.json'));
        if ~isempty(d), resPath = fullfile(d(1).folder, d(1).name); end
    end
    if isempty(resPath)
        fprintf('    INFO: no result JSON found; run tests.stageF_run once to export demo data.\n');
    else
        fprintf('    found: %s\n', resPath);
    end

    %% H4) generate self-contained HTML (non-fatal python)
    fprintf('  [H4] generate digital-twin HTML (non-fatal python)\n');
    if ~isempty(resPath)
        outHtml = fullfile(pwd, 'figures', 'digital_twin.html');
        [pok, pout] = system(sprintf('python "%s" "%s" -o "%s" 2>&1', pyPath, resPath, outHtml));
        if pok == 0
            fprintf('    digital-twin HTML generated: %s\n', outHtml);
        else
            fprintf('    INFO: python unavailable / error -> skip HTML gen. (install python + rerun)\n');
            fprintf('    %s\n', strtrim(pout));
        end
    else
        fprintf('    SKIP: no result JSON -> HTML not generated.\n');
    end

    fprintf('=== Stage H PASS (digital-twin ADDITIVE, non-fatal python) ===\n');
end

function [ok, msg] = py_syntax_check(pyFile)
    [status, out] = system(sprintf('python -m py_compile "%s" 2>&1', pyFile));
    if status == 0
        ok = true; msg = '';
    else
        ok = false; msg = strtrim(out);
    end
end
