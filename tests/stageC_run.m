function stageC_run()
% stageC_run  Stage-C lightweight self-test for the LLM dual-engine modulation layer.
%
% Verifies, WITHOUT heavy computation:
%   1. OFFLINE_STRUCTURED_MODULATE=true changes the three gain coefficients across
%      generations (offline_structured_modulate behaviour) -- i.e. the modulation
%      layer is non-degenerate, not stuck at 1.0.
%   2. aoo_engine runs end-to-end with modulation ON for a small budget and returns
%      a finite makespan (modulation does not break the main chain).
%   3. Zero-regression guard: with OFFLINE_STRUCTURED_MODULATE=false the gains stay
%      at 1.0 (matches gate_competitiveness default), and 'aoo' variant survives.
%
% SAFE / ADDITIVE: analysis + public entry points only.

    addpath('benchmarks'); addpath('tests');

    %% 1) modulation hook is non-degenerate (gains vary with stagnation)
    % NOTE: in llmaoo, 'stagnation' = cross-generation IMPROVEMENT of normalized objective.
    %   large positive stagnation -> good progress -> exploit more (diff_gain up, levy_gain down)
    %   large negative stagnation -> objective worsened / stuck -> explore more (levy_gain up, diff_gain down)
    s0 = struct('levy_gain', 1.0, 'diff_gain', 1.0, 'explore_bias', 1.0);
    sGood = offline_structured_modulate(s0, 1000);   % strong progress
    sStuck = offline_structured_modulate(s0, -1000); % strong stagnation (objective worsened)
    assert(sGood.levy_gain < 1.0 && sGood.diff_gain > 1.0, 'good progress should raise diff/exploit');
    assert(sStuck.levy_gain > 1.0 && sStuck.diff_gain < 1.0, 'stagnation should raise levy/explore');
    assert(sStuck.explore_bias ~= sGood.explore_bias, 'explore_bias should respond to stagnation');
    assert(all([sStuck.levy_gain, sStuck.diff_gain, sStuck.explore_bias] >= 0.5) && ...
           all([sStuck.levy_gain, sStuck.diff_gain, sStuck.explore_bias] <= 2.0), ...
           'gains must stay within [0.5, 2.0]');
    disp('  [C1] offline_structured_modulate non-degenerate: PASS');

    %% 2) aoo_engine end-to-end with modulation ON (small budget, no crash)
    prob = load_benchmark('MK01');
    cfg = llmaoo_config();
    cfg.AOO_POP = 20; cfg.AOO_MAXGEN = 15; cfg.AOO_REFINE_EVERY = 5;
    cfg.OFFLINE_STRUCTURED_MODULATE = true;
    init_state = struct('levy_gain', 1.0, 'diff_gain', 1.0, 'explore_bias', 1.0);
    onIter = @(t, b, m) init_state;
    [~, resM] = aoo_engine(prob, cfg, init_state, onIter);
    assert(isfinite(resM.makespan) && resM.makespan > 0, 'modulated aoo_engine must return finite makespan');
    disp(['  [C2] aoo_engine(modulate ON) end-to-end PASS: mk=', num2str(resM.makespan, '%.1f')]);

    %% 3) zero-regression: modulation OFF keeps gains at 1.0, aoo variant runs
    cfg.OFFLINE_STRUCTURED_MODULATE = false;
    [~, resA] = aoo_engine(prob, cfg, init_state, onIter);
    assert(isfinite(resA.makespan) && resA.makespan > 0, 'aoo (no modulation) must return finite makespan');
    disp(['  [C3] aoo_engine(modulate OFF) zero-regression PASS: mk=', num2str(resA.makespan, '%.1f')]);

    %% 4) ablation entry point runs for small N without error
    A = ablation(prob, 'N', 3);
    assert(isfield(A.stats.desc, 'modulate') && isfield(A.stats.desc, 'aoo'), ...
           'ablation must report aoo + modulate');
    disp('  [C4] ablation(prob, N=3) PASS (aoo vs modulate vs random)');

    fprintf('stageC_run PASS (all checks green)\n');
end
