%% llm_hook.m — LLM 知识注入回调（AOO 每代后调用，受频率/停滞门控）
% 输入/输出 llm_state：把 LLM 调制信号回灌给 AOO 下一代（双引擎协同核心）。
%
% SAFE / ADDITIVE: extracted from llmaoo.m as a standalone function so that BOTH
% llmaoo (main entry) and experiment_runs (ablation) share the IDENTICAL modulation
% logic. Previously experiment_runs bypassed this hook (empty onIter), making the
% 'modulate'/'full' ablation variants numerically identical to pure 'aoo'.
%
% Dependencies (all standalone files in the solver root):
%   deepseek_chat, prompt_diagnosis, prompt_knowledge, parse_contract,
%   online_llm_modulate, offline_structured_modulate, fjsp_system_prompt, decode.

function llm_state = llm_hook(prob, cfg, t, best, mean, llm_state)
    % last_best is carried inside llm_state (not persistent) so repeated calls
    % within one MATLAB session (e.g. verify_run) do not cross-contaminate.

    % Trigger only on agreed generations to avoid a call every generation.
    if mod(t, cfg.LLM_CALL_EVERY_GEN) ~= 0 && mod(t, cfg.LLM_DIAG_EVERY_GEN) ~= 0
        return;
    end
    stagWindow = cfg.LLM_CALL_EVERY_GEN;
    last_best = llm_state.last_best;
    stagnation = best - last_best;   % true cross-generation improvement
    llm_state.last_best = best;

    if mod(t, cfg.LLM_DIAG_EVERY_GEN) == 0
        % 职责④ population diagnosis
        stats = struct('gen',t,'best',best,'mean',mean,'diversity',0.5, ...
                        'stagWindow',stagWindow,'stagnation',stagnation,'nearEarlyStop',false);
        [user_p, ~] = prompt_diagnosis(stats);
        [txt, ok, mode] = deepseek_chat(cfg, fjsp_system_prompt(), user_p);
        if ~ok && ~strcmpi(mode,'offline')
            fprintf('  [LLM 诊断@%d] 警告：知识调用未成功 (%s)，已用降级启发式。\n', t, mode);
        end
        diag = parse_contract(txt);
        if strcmpi(diag.action,'INCREASE_EXPLORE')
            llm_state.levy_gain = min(2.0, llm_state.levy_gain*1.3);
        elseif strcmpi(diag.action,'INCREASE_EXPLOIT')
            llm_state.levy_gain = max(0.5, llm_state.levy_gain*0.8);
        end
        % Stage-D attribution: keep real gain only when truly online.
        if cfg.ONLINE_LLM_MODULATE
            llm_state = online_llm_modulate(llm_state, stagnation, mode);
        elseif cfg.OFFLINE_STRUCTURED_MODULATE && ~strcmpi(mode, 'online')
            llm_state = offline_structured_modulate(llm_state, stagnation);
        end
        fprintf('  [LLM 诊断@%d] mode=%s stagnant=%d action=%s | levGain=%.2f\n', ...
                t, mode, diag.stagnant, diag.action, llm_state.levy_gain);
    else
        % 职责①②③ knowledge injection
        stats = gather_stats(prob, [], [], cfg, t, stagnation);
        [user_p, ~] = prompt_knowledge(prob, stats);
        [txt, ok, mode] = deepseek_chat(cfg, fjsp_system_prompt(), user_p);
        if ~ok && ~strcmpi(mode,'offline')
            fprintf('  [LLM 知识@%d] 警告：知识调用未成功 (%s)，已用降级启发式。\n', t, mode);
        end
        contract = parse_contract(txt);
        llm_state = make_llm_state(cfg, contract, llm_state);
        if cfg.ONLINE_LLM_MODULATE
            llm_state = online_llm_modulate(llm_state, stagnation, mode);
        elseif cfg.OFFLINE_STRUCTURED_MODULATE && ~strcmpi(mode, 'online')
            llm_state = offline_structured_modulate(llm_state, stagnation);
        end
        fprintf('  [LLM 知识@%d] mode=%s %s | levGain=%.2f diffGain=%.2f expBias=%.2f\n', ...
                t, mode, contract.heuristics, llm_state.levy_gain, ...
                llm_state.diff_gain, llm_state.explore_bias);
    end
end

%% LLM 调制状态：由契约生成（默认/统计见独立文件 default_llm_state.m / gather_stats.m，跨文件可见）
function llm_state = make_llm_state(cfg, contract, prev)
    llm_state.levy_gain   = contract.levy_gain;
    llm_state.diff_gain   = contract.diff_gain;
    llm_state.explore_bias = contract.explore_bias;
    llm_state.last_best   = prev.last_best;  % 继承上次触发时的 last_best，保证停滞门控连续
end
