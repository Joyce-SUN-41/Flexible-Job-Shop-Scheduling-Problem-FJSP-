%% default_llm_state.m — LLM 调制状态初始化（独立文件，供 llmaoo / experiment_runs 跨文件调用）
% 与 llm_hook.m 内逻辑保持一致。SAFE/ADDITIVE: 阶段三修复阶段二抽离
% llm_hook 时遗留的跨文件不可见问题（局部函数无法被 llmaoo 主入口调用）。
function llm_state = default_llm_state(cfg)   %#ok<INUSD> cfg 预留（后续可携场景相关默认）
    llm_state.levy_gain    = 1.0;
    llm_state.diff_gain    = 1.0;
    llm_state.explore_bias = 1.0;
    llm_state.last_best    = Inf;   % 上次 LLM 触发时的精英目标，用于停滞门控
end
