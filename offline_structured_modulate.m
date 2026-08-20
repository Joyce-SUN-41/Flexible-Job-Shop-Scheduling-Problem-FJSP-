function llm_state = offline_structured_modulate(llm_state, stagnation)
% offline_structured_modulate  Stage-C structured modulation hook (offline proxy for
% the LLM dual-engine layer). Maps the per-generation stagnation signal to the three
% AOO gain coefficients so the search adapts its explore/exploit balance without an
% online API call.
%
%   llm_state = offline_structured_modulate(llm_state, stagnation)
%
% Inputs:
%   llm_state  - struct with fields levy_gain, diff_gain, explore_bias (init 1.0).
%   stagnation - normalized objective (sum Z) improvement across generations; near 0
%                means the search is stagnating, large means it is still progressing.
%
% Output: llm_state with gains updated in [0.5, 2.0], and offline_modulated=true.
%
% Top-level function (extracted from llmaoo.m) so stage-C tests can call it directly.
% SAFE / ADDITIVE.

    % stagnation 接近 0 表示停滞；用 sigmoid 映射为探索强度信号（0~1）。
    % 尺度取 1e-3：stagnation 为归一化目标(sum Z)跨代改进量，典型量级 1e-3~1e-1。
    sig = 1 ./ (1 + exp(stagnation / 1e-3));
    % levy_gain: 停滞深(sig->1)则加强探索至 ~1.8；收敛好(sig->0)则 ~0.8
    llm_state.levy_gain = 0.8 + 1.0 * sig;
    % diff_gain: 与 levy 反向，停滞时收缩传播以跳出局部最优
    llm_state.diff_gain  = 1.2 - 0.4 * sig;
    % explore_bias（风传播幅度）随探索强度轻微上升
    llm_state.explore_bias = 0.9 + 0.3 * sig;
    llm_state.offline_modulated = true;   % 标记该次增益来源于结构化默认（便于实验报告归因）
end
