function A = ablation(prob, varargin)
% ablation  Stage-C ablation study quantifying the LLM dual-engine contribution.
%
%   A = ablation(prob, 'N', 30)
%
% Compares three configurations on the SAME problem and SAME evaluation budget:
%   1. aoo     - pure AOO five-strategy discrete-neighborhood search, gains = 1.0
%               (no LLM modulation; the "AOO-only" baseline).
%   2. modulate - AOO + OFFLINE_STRUCTURED_MODULATE=true. Gains (levy_gain /
%               diff_gain / explore_bias) vary with stagnation via the internal
%               offline_structured_modulate hook. No API key required -- this is the
%               offline proxy for the LLM modulation layer.
%   3. full    - complete LLMAOO with online LLM modulation (requires DEEPSEEK_API_KEY).
%               Offline (no key) it is equivalent to 'modulate' and is reported honestly
%               as such.
%
% The ablation quantifies:
%   (a) how much the AOO strategy itself improves over random;
%   (b) how much the structured modulation layer adds on top of pure AOO;
%   (c) (online only) the true LLM contribution beyond offline modulation.
%
% SAFE / ADDITIVE: calls only public solver entry points; does not modify decode /
% evaluate / aoo_engine / llmaoo. Default OFFLINE_STRUCTURED_MODULATE stays false for
% the 'aoo' variant, preserving the stage-7 competitiveness gate.

    p = inputParser;
    addParameter(p, 'N', 30, @(x) isscalar(x) && x > 0);
    addParameter(p, 'Cfg', [], @(x) isempty(x) || isstruct(x));  % 可选注入已配置 cfg（用于临时开启联网 LLM）
    parse(p, varargin{:});
    N = p.Results.N;

    % SAFE / ADDITIVE: accept a benchmark name string ('MK01') and load it, so the
    % ablation entry point is callable the same way as llmaoo('Problem','MK01').
    if ischar(prob)
        prob = load_benchmark(prob);
    end

    if isempty(p.Results.Cfg)
        cfg = llmaoo_config();
    else
        cfg = p.Results.Cfg;   % 使用外部注入的配置（如 LLM_ENABLE=true 联网消融）
    end
    withKey = ~isempty(cfg.DEEPSEEK_API_KEY);
    % (a) pure AOO, (b) offline structured modulation, (c) full LLMAOO (online).
    variants = {'aoo', 'modulate', 'random'};
    if withKey
        variants = [variants(1:2), {'full'}, variants(3)];  % include online variant
    end

    disp('=== Stage-C Ablation study (LLMAOO dual-engine) ===');
    disp(['DEEPSEEK_API_KEY present: ', num2str(withKey)]);
    R = experiment_runs(prob, 'N', N, 'Variants', variants);
    S = stat_report(R, 'Compare', variants);

    A.results = R;
    A.stats = S;

    % Component contribution summary (makespan).
    aooMean = S.desc.aoo.mean;
    rndMean = S.desc.random.mean;
    modMean = S.desc.modulate.mean;
    A.aoo_vs_random_improve_pct = 100 * (rndMean - aooMean) / rndMean;
    A.modulate_vs_aoo_improve_pct = 100 * (aooMean - modMean) / aooMean;

    if isfield(S.desc, 'full')
        fullMean = S.desc.full.mean;
        A.full_vs_modulate_improve_pct = 100 * (modMean - fullMean) / modMean;
    else
        A.full_vs_modulate_improve_pct = NaN;
        A.note = 'Offline: full == modulate (set DEEPSEEK_API_KEY for true online LLM contribution).';
        disp(A.note);
    end
    disp(sprintf('AOO vs Random improvement: %.1f%%', A.aoo_vs_random_improve_pct));
    disp(sprintf('Modulate vs AOO improvement: %.1f%%', A.modulate_vs_aoo_improve_pct));
end
