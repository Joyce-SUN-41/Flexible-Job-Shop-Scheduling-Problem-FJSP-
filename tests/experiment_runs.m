function R = experiment_runs(prob, varargin)
% experiment_runs  Run LLMAOO / AOO / Random for N independent seeds and collect statistics.
%
%   R = experiment_runs(prob, 'N', 30, 'Variants', {'aoo','random'}, 'Seed0', 1001)
%
% Inputs:
%   prob      - LLMAOO problem struct (from load_data / load_benchmark).
%   N         - number of independent runs (default 30, the TEVC convention).
%   Variants  - cell of {'full','aoo','modulate','random','ga','pso','alns'}.
%               'aoo'     = pure AOO five-strategy search, no LLM modulation (gains = 1.0).
%               'modulate' = AOO + OFFLINE_STRUCTURED_MODULATE=true (stage-C structured
%                           modulation; gains vary with stagnation, no API key needed).
%               'full'    = complete LLMAOO with LLM modulation (requires DEEPSEEK_API_KEY
%                           to differ from 'modulate'; offline it is equivalent to 'modulate'
%                           because OFFLINE_STRUCTURED_MODULATE defaults false -- see config).
%               'random'  = random initialization + random decode, same evaluation budget.
%               'ga'/'pso'/'alns' = standard GA / discrete PSO / ALNS baselines (SOTA compare).
%   Modulate  - (deprecated alias for Variants={'modulate'}) kept for back-compat.
%   Seed0     - base seed; run i uses Seed0 + i.
%
% Output R fields:
%   R.mk.(variant)   - Nx1 best makespan per run
%   R.lb.(variant)   - Nx1 best loadUnbalance per run
%   R.conv.(variant) - cell of convergence trajectories (best makespan vs generation)
%   R.prob           - problem descriptor
%   R.nEval          - evaluation budget used (same across variants for fairness)
%
% SAFE / ADDITIVE: does not modify decode / evaluate / aoo_engine / llmaoo.
% Uses only public entry points of the solver.

    % Ensure the solver root (where llm_hook.m, deepseek_chat.m, prompt_*.m,
    % parse_contract.m, online/offline_structured_modulate.m, fjsp_system_prompt.m,
    % decode.m live) is on the path so the shared LLM hook is callable here.
    rootDir = fileparts(fileparts(mfilename('fullpath')));  % tests/ -> project root
    addpath(rootDir);

    p = inputParser;
    addParameter(p, 'N', 30, @(x) isscalar(x) && x > 0);
    addParameter(p, 'Variants', {'aoo', 'random'}, @iscell);
    addParameter(p, 'Modulate', false, @(x) isscalar(x) && (x == 0 || x == 1));
    addParameter(p, 'Seed0', 1001, @isscalar);
    addParameter(p, 'Pop', 50, @(x) isscalar(x) && x > 0);
    addParameter(p, 'MaxGen', 130, @(x) isscalar(x) && x > 0);
    parse(p, varargin{:});
    N = p.Results.N;
    variants = p.Results.Variants;
    seed0 = p.Results.Seed0;

    cfg = llmaoo_config();
    % Fixed, comparable budget across variants. Default 50x130 (standard SOTA budget);
    % callers may override via Pop/MaxGen (e.g. stage7_run uses 30x60 to match its [7.1]
    % benchmark budget for full consistency). ADDITIVE: other callers unchanged.
    cfg.AOO_POP = p.Results.Pop;
    cfg.AOO_MAXGEN = p.Results.MaxGen;
    cfg.AOO_REFINE_EVERY = 5;
    % Default-safe: structured modulation OFF unless explicit 'modulate'/'full' variant.
    % Keeps zero-regression guarantee for all existing callers (ablation, stage6/7 runs).
    cfg.OFFLINE_STRUCTURED_MODULATE = false;   % zero regression (stage C)

    nEval = cfg.AOO_POP * cfg.AOO_MAXGEN;  % approximate AOO evaluations
    addpath('benchmarks');  % for load_benchmark used by stage6_run

    R = struct();
    R.prob = struct('name', prob.name, 'nJob', prob.nJob, ...
        'nMachine', prob.nMachine, 'nOp', prob.nOp, 'bks', prob.bks);
    R.nEval = nEval;
    R.N = N;
    R.mk = struct();
    R.lb = struct();
    R.conv = struct();

    for v = 1:numel(variants)
        variant = variants{v};
        mks = zeros(N, 1);
        lbs = zeros(N, 1);
        convs = cell(N, 1);
        % Stage-C: 'modulate' and 'full' activate OFFLINE_STRUCTURED_MODULATE so the
        % aoo_engine internal hook drives gains from stagnation (no API key needed).
        % 'aoo' keeps gains = 1.0 (pure AOO, zero modulation). 'random' is a baseline.
        if strcmpi(variant, 'modulate')
            % Offline structured modulation only (Stage-C). No online contribution.
            cfg.OFFLINE_STRUCTURED_MODULATE = true;
            cfg.ONLINE_LLM_MODULATE = false;
        elseif strcmpi(variant, 'full')
            % Complete LLMAOO: enable online honest contribution accounting. When a real
            % DEEPSEEK_API_KEY is present and the call succeeds (mode=='online'), the LLM
            % gains are preserved as the true dual-engine contribution; offline it falls
            % back to the structured modulation (so 'full' == 'modulate' offline, honestly).
            cfg.OFFLINE_STRUCTURED_MODULATE = true;   % keep structured fallback available
            cfg.ONLINE_LLM_MODULATE = true;            % Stage-D attribution switch
            % 省着用：当且仅当 Key 已配置才真正联网（LLM_ENABLE 置 true）；否则保持离线降级，
            % 行为与 modulate 等价（零回归、零消耗）。频率由 LLM_CALL_EVERY_GEN 控制（默认联网周期）。
            if ~isempty(cfg.DEEPSEEK_API_KEY)
                cfg.LLM_ENABLE = true;   % 仅在 full 变体 + 有 Key 时真实联网（消融唯一消耗点）
            end
        else
            cfg.OFFLINE_STRUCTURED_MODULATE = false;
            cfg.ONLINE_LLM_MODULATE = false;
        end
        for i = 1:N
            rng(seed0 + i, 'twister');  % independent, reproducible seed
            if strcmpi(variant, 'random')
                [mk, lb] = random_baseline(prob, cfg);
                convs{i} = [mk];  % single-point baseline
            else
                % 'full'/'modulate'/'aoo' all run aoo_engine. The only difference is
                % whether OFFLINE_STRUCTURED_MODULATE is on (set above). When on, aoo_engine
                % internally overrides the unity-gain onIter with offline_structured_modulate.
                % We supply the unity-gain initial llm_state + no-op onIter, matching
                % llmaoo's offline (default) hook behaviour. Safe / additive.
                % 'ga' runs the standard GA baseline (阶段7 SOTA comparison).
                % 'pso' runs the standard discrete PSO baseline (阶段五 SOTA comparison).
                % Both share the ga_fjsp contract (result.makespan / loadUnb / conv_best)
                % so stat_report / convergence_plot work unchanged. ADDITIVE.
                if strcmpi(variant, 'ga')
                    addpath('benchmarks/baselines');
                    [~, res] = ga_fjsp(prob, cfg);
                    mk = res.makespan;
                    lb = res.loadUnb;
                    convs{i} = res.conv_best(:).';
                elseif strcmpi(variant, 'pso')
                    addpath('benchmarks/baselines');
                    [~, res] = pso_fjsp(prob, cfg);
                    mk = res.makespan;
                    lb = res.loadUnb;
                    convs{i} = res.conv_best(:).';
                elseif strcmpi(variant, 'alns')
                    addpath('benchmarks/baselines');
                    [~, res] = alns_fjsp(prob, cfg);
                    mk = res.makespan;
                    lb = res.loadUnb;
                    convs{i} = res.conv_best(:).';
                else
                    init_state = struct('levy_gain', 1.0, 'diff_gain', 1.0, 'explore_bias', 1.0, 'last_best', Inf);
                    if strcmpi(variant, 'aoo')
                        % Pure AOO: unity-gain no-op callback (no LLM modulation).
                        onIter = @(t, b, m) init_state;
                    else
                        % 'modulate' / 'full': wire the REAL LLM modulation hook so the
                        % OFFLINE_STRUCTURED_MODULATE / ONLINE_LLM_MODULATE switches set above
                        % actually take effect inside aoo_engine (previously bypassed, making
                        % all variants identical). SAFE/ADDITIVE: equivalent to llmaoo's llm_hook,
                        % but self-contained so experiment_runs does not depend on llmaoo internals.
                        onIter = make_llm_oniter(cfg, init_state, prob);
                    end
                    [~, res] = aoo_engine(prob, cfg, init_state, onIter);
                    mk = res.makespan;
                    lb = res.loadUnb;
                    convs{i} = res.conv_best(:).';
                end
            end
            mks(i) = mk;
            lbs(i) = lb;
        end
        R.mk.(variant) = mks;
        R.lb.(variant) = lbs;
        R.conv.(variant) = convs;
        disp(['[', variant, '] N=', num2str(N), ' done (modulate=', ...
            num2str(cfg.OFFLINE_STRUCTURED_MODULATE), ')']);
    end
end

function [mk, lb] = random_baseline(prob, cfg)
% random_baseline  Random search with the SAME total evaluation budget as AOO.
% Generates random feasible (OS, MS), decodes, evaluates; keeps the best.
    nEval = cfg.AOO_POP * cfg.AOO_MAXGEN;
    bestMk = Inf; bestLb = Inf;
    for e = 1:nEval
        [OS, MS] = random_feasible(prob);
        chrom = struct('OS', OS, 'MS', MS);
        [~, mk, loadVec] = decode(prob, chrom);
        lb = max(loadVec) - min(loadVec);
        if mk < bestMk
            bestMk = mk;
            bestLb = lb;
        end
    end
    mk = bestMk; lb = bestLb;
end

function [OS, MS] = random_feasible(prob)
% random_feasible  Sample a feasible OS (job-permutation multiset) and MS (random machine per op).
    nJob = prob.nJob;
    opCount = cellfun(@numel, prob.op_mach);
    % OS: shuffle the multiset of job indices repeated by operation count.
    OS = [];
    for j = 1:nJob, OS = [OS, j * ones(1, opCount(j))]; end
    OS = OS(randperm(numel(OS)));
    % MS: pick one eligible machine per operation.
    MS = zeros(sum(opCount), 1);
    idx = 0;
    for j = 1:nJob
        for k = 1:opCount(j)
            idx = idx + 1;
            em = prob.op_mach{j}{k};
            MS(idx) = em(randi(numel(em)));
        end
    end
end

%% make_llm_oniter — build the on_iter callback that wires the shared llm_hook
% into aoo_engine, so the OFFLINE_STRUCTURED_MODULATE / ONLINE_LLM_MODULATE switches
% set per-variant actually take effect (previously bypassed by a unity-gain no-op).
% SAFE/ADDITIVE: self-contained; replicates llmaoo's hook wiring without depending
% on llmaoo internals. The state carries last_best for stagnation gating.
function onIter = make_llm_oniter(cfg, init_state, prob)
    state = init_state;
    onIter = @(t, best, mean) llm_hook(prob, cfg, t, best, mean, state);
end
