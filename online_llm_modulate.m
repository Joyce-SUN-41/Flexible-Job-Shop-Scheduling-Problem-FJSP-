function llm_state = online_llm_modulate(llm_state, stagnation, mode)
% online_llm_modulate  Stage-D online LLM gain modulation (honest dual-engine accounting).
%
%   llm_state = online_llm_modulate(llm_state, stagnation, mode)
%
% This is the *online* counterpart of offline_structured_modulate (Stage-C). It resolves
% the long-standing ambiguity in the ablation study: when DEEPSEEK_API_KEY is present and
% the LLM call truly succeeds (mode=='online'), the gains already written into llm_state by
% make_llm_state (from the parsed LLM contract) are KEPT as the genuine LLM contribution.
% When the call is offline / cached / fallback (no real online LLM signal), we fall back to
% the Stage-C structured default modulation so the behaviour is identical to OFFLINE mode
% (zero regression, honest offline==modulate equivalence preserved).
%
% Inputs:
%   llm_state  - struct with fields levy_gain, diff_gain, explore_bias. For an online call,
%                these already hold the LLM-contract-parsed values (set by make_llm_state).
%   stagnation - normalized objective improvement across generations (see offline_structured_modulate).
%   mode       - string from deepseek_chat: 'online' | 'cached' | 'offline' | 'fallback'.
%
% Output: llm_state with gains either (a) preserved as-is for a genuine online LLM call, or
%         (b) replaced by the structured default modulation for any non-online mode, plus a
%         flag llm_state.online_contributed = true/false for transparent experiment attribution.
%
% SAFE / ADDITIVE: top-level function; does not modify decode / evaluate / aoo_engine / llmaoo.
% Only llmaoo's llm_hook may call it when cfg.ONLINE_LLM_MODULATE is explicitly enabled.

    if strcmpi(mode, 'online')
        % Genuine online LLM signal: preserve the contract-parsed gains as the true
        % LLM dual-engine contribution. Do NOT override with the offline heuristic.
        llm_state.online_contributed = true;
    else
        % Offline / cached / fallback: no real online LLM signal -> use the Stage-C
        % structured default modulation. This keeps offline behaviour byte-identical to
        % the OFFLINE_STRUCTURED_MODULATE path, so ablation('full') == 'modulate' offline.
        llm_state = offline_structured_modulate(llm_state, stagnation);
        llm_state.online_contributed = false;
    end
end
