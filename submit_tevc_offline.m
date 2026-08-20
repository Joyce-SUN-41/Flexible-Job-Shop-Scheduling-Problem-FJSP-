function submit_tevc_offline()
% submit_tevc_offline  Stage-0 safety re-export of TEVC submission artifacts.
%   Purpose: regenerate results/tevc_submission/* using the CURRENT (fixed) code so the
%   exported JSON carries real-scale values + contract_version='1.1' + a genuine (non
%   collapsed) energy third dimension. This replaces the 2026-08-14/16 legacy files that
%   were produced before the energy-collapse fix (old 1.5*energy+1 fallback => obj3 en==0.6645).
%
%   SAFETY: LLM stays OFFLINE (LLM_ENABLE=false). We do NOT claim online LLM gain. The
%   dual-engine contribution is honestly the offline structured-modulation proxy. No
%   network call is attempted; if DEEPSEEK_API_KEY happens to be set we still force offline
%   to keep the re-export reproducible and honest (env_manifest semantics).
%
%   Output: results/tevc_submission/tevc_full_result.json, tevc_multi_result.json,
%           tevc_full_replay.json  (same filenames as legacy, overwriting stale ones).
%   Each result JSON now carries contract_version='1.2' (with explicit pareto.energy_n)
%   plus a top-level env_state ('offline_honest') and llm_counts so it is self-describing.
%   Non-fatal Python renders are skipped here; run viz scripts separately if needed.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    outDir = fullfile(pwd, 'results', 'tevc_submission');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    %% Switch A: full hottest scenario (dynamic + green + AGV, 3-obj NSGA-III), OFFLINE
    fprintf('[TEVC-A-offline] full hottest scenario (dynamic+green+AGV, NSGA-III, OFFLINE)\n');
    rng(20260814);
    res = llmaoo('AOO_DEFAULT_SCENARIO', 'full', ...
                 'AOO_THREE_OBJ', true, ...
                 'EXPORT_JSON', true, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                 'LLM_ENABLE', false, ...                 % SAFETY: no network
                 'AOO_MAXGEN', 100, 'AOO_POP', 60);
    resPath = fullfile(outDir, 'tevc_full_result.json');
    export_result_json(res, resPath);
    fprintf('  mk=%.1f loadUnb=%.1f\n', res.makespan, res.loadUnb);
    if isfield(res, 'quality')
        fprintf('  NSGA-III: HV=%.4f IGD=%.4f PF=%d\n', ...
                res.quality.HV, res.quality.IGD, res.quality.nPF);
    end

    %% Replay (real AOO elite baseline + breakdown events) for dynamic digital twin, OFFLINE
    cfg = llmaoo_config();
    cfg.AOO_DYNAMIC = true; cfg.AOO_AGV = true; cfg.AOO_THREE_OBJ = true;
    cfg.LLM_ENABLE = false;                              % SAFETY: no network
    prob = load_benchmark('MK01');
    prob = attach_stage8(prob, cfg);
    frames = dynamic_replay(prob, cfg, [], res.elite);
    rPath = fullfile(outDir, 'tevc_full_replay.json');
    export_replay_json(frames, rPath);
    fprintf('  replay -> %s (%d frames)\n', rPath, numel(frames));

    %% Switch B: multi three-objective NSGA-III (makespan/load/energy), OFFLINE
    fprintf('[TEVC-B-offline] multi 3-obj NSGA-III (OFFLINE)\n');
    rng(20260814);
    resM = llmaoo('AOO_DEFAULT_SCENARIO', 'multi', ...
                  'AOO_THREE_OBJ', true, ...
                  'EXPORT_JSON', true, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                  'LLM_ENABLE', false, ...                 % SAFETY: no network
                  'AOO_MAXGEN', 100, 'AOO_POP', 60);
    resMPath = fullfile(outDir, 'tevc_multi_result.json');
    export_result_json(resM, resMPath);
    fprintf('  mk=%.1f loadUnb=%.1f\n', resM.makespan, resM.loadUnb);
    if isfield(resM, 'quality')
        fprintf('  NSGA-III: HV=%.4f IGD=%.4f PF=%d\n', ...
                resM.quality.HV, resM.quality.IGD, resM.quality.nPF);
    end

    %% Honest manifest: record that this re-export is OFFLINE (no online LLM gain claimed)
    manifest.path = fullfile(outDir, 'env_manifest_reexport.json');
    manifest.online_llm = false;
    manifest.env_state = struct('mode', 'offline_honest', ...
                                 'note', 'Re-exported with fixed code (contract_version 1.2, e_ub fixed energy). OFFLINE structured-modulation proxy only; no online LLM gain claimed.');
    manifest.note = 'Re-exported with fixed code (contract_version 1.2, e_ub fixed energy). OFFLINE structured-modulation proxy only; no online LLM gain claimed.';
    manifest.generated = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    fid = fopen(manifest.path, 'w');
    if fid >= 0, fwrite(fid, jsonencode(manifest, 'PrettyPrint', true), 'char'); fclose(fid); end

    %% cleanup stray root json (llmaoo may write timestamped results_*.json to cwd)
    % 修复: -batch 下 pwd 可能被 MATLAB 重置, 故用脚本所在目录(即项目根)定位 stray,
    % 避免残留到 results/ 根目录污染可复现性包。
    rootDir = fileparts(mfilename('fullpath'));
    stray = dir(fullfile(rootDir, 'results_*.json'));
    for s = 1:numel(stray), delete(fullfile(rootDir, stray(s).name)); end
    % 若 pwd 与 rootDir 不同, 也清理 pwd 下的 stray (双保险)
    if ~strcmp(pwd, rootDir)
        stray2 = dir(fullfile(pwd, 'results_*.json'));
        for s = 1:numel(stray2), delete(fullfile(pwd, stray2(s).name)); end
    end

    fprintf('submit_tevc_offline DONE (full mk=%.1f, multi mk=%.1f)\n', ...
            res.makespan, resM.makespan);
end
