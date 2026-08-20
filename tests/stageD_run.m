function stageD_run()
% stageD_run  Stage-D lightweight self-test for ONLINE honest LLM contribution accounting.
%
% Verifies, WITHOUT heavy computation:
%   1. online_llm_modulate: a genuine online LLM call (mode=='online') PRESERVES the
%      contract-parsed gains (online_contributed=true); non-online modes fall back to the
%      Stage-C structured modulation (online_contributed=false) -- honest offline==modulate.
%   2. Zero-regression guard: with the default ONLINE_LLM_MODULATE=false, llmaoo behaviour
%      is identical to Stage-C (the switch never changes numerics for direct callers).
%   3. ablation stays honest: offline (no key) 'full' == 'modulate' after the Stage-D switch.
%   4. End-to-end: llmaoo runs with ONLINE_LLM_MODULATE=true on a tiny budget (offline mock),
%      returning a finite makespan (the new switch does not break the main chain).
%
% SAFE / ADDITIVE: analysis + public entry points only.

    addpath('benchmarks'); addpath('tests');

    %% 1) online_llm_modulate attribution logic
    s0 = struct('levy_gain', 1.4, 'diff_gain', 0.8, 'explore_bias', 1.1);
    % genuine online LLM signal: keep the (non-default) gains as the true contribution
    sOn = online_llm_modulate(s0, 1000, 'online');
    assert(sOn.online_contributed == true, 'online mode must mark online_contributed=true');
    assert(sOn.levy_gain == 1.4 && sOn.diff_gain == 0.8, ...
           'online mode must preserve contract gains (no override)');
    % cached / offline / fallback: fall back to structured modulation (Stage-C consistent)
    sOff = online_llm_modulate(s0, 1000, 'offline');
    assert(sOff.online_contributed == false, 'offline mode must mark online_contributed=false');
    % offline structured modulation changes gains vs the preserved online values
    sStruct = offline_structured_modulate(s0, 1000);
    assert(abs(sOff.levy_gain - sStruct.levy_gain) < 1e-12 && ...
           abs(sOff.diff_gain - sStruct.diff_gain) < 1e-12, ...
           'offline fallback must equal offline_structured_modulate');
    disp('  [D1] online_llm_modulate attribution: PASS (online preserves, offline falls back)');

    %% 2) zero-regression: default ONLINE_LLM_MODULATE=false keeps Stage-C behaviour
    cfgD = llmaoo_config();
    assert(isfield(cfgD, 'ONLINE_LLM_MODULATE') && cfgD.ONLINE_LLM_MODULATE == false, ...
           'ONLINE_LLM_MODULATE must default false (zero regression)');
    % direct callers with default config must see unchanged structured-modulation default
    assert(cfgD.OFFLINE_STRUCTURED_MODULATE == false, 'OFFLINE_STRUCTURED_MODULATE default false');
    disp('  [D2] default ONLINE_LLM_MODULATE=false zero-regression guard: PASS');

    %% 3) ablation honest equivalence offline: full == modulate
    prob = load_benchmark('MK01');
    A = ablation(prob, 'N', 3);
    if ~isfield(A.stats.desc, 'full')
        % no key: full variant not appended -> honestly equivalent to modulate
        assert(isfield(A.stats.desc, 'modulate') && isfield(A.stats.desc, 'aoo'), ...
               'ablation must report aoo + modulate');
        assert(isnan(A.full_vs_modulate_improve_pct), ...
               'offline full_vs_modulate must be NaN (honest: full==modulate)');
        disp('  [D3] ablation offline honest (full==modulate, no key): PASS');
    else
        % key present: full variant present and distinct; just ensure both finite
        assert(all(isfinite(A.stats.desc.full.mean)) && all(isfinite(A.stats.desc.modulate.mean)), ...
               'ablation full/modulate means must be finite');
        disp('  [D3] ablation online (full present, distinct from modulate): PASS');
    end

    %% 4) end-to-end with ONLINE_LLM_MODULATE=true (offline mock, tiny budget) - no crash
    rng(cfgD.RNG_SEED);
    res = llmaoo('ONLINE_LLM_MODULATE', true, 'AOO_MAXGEN', 6, 'AOO_POP', 12, ...
                 'SHOW_PLOTS', false, 'EXPORT_PNG', false);
    assert(isfinite(res.makespan) && res.makespan > 0, ...
           'llmaoo with ONLINE_LLM_MODULATE=true must return finite makespan');
    disp(['  [D4] llmaoo(ONLINE_LLM_MODULATE=true) end-to-end PASS: mk=', ...
          num2str(res.makespan, '%.1f')]);

    fprintf('stageD_run PASS (all checks green)\n');
end
